"""Local video -> measured MediaPipe landmarks -> BVH + retargetable motion JSON.

Root calibration assumes a fixed camera and a supplied subject height. Horizontal
translation is an image-plane estimate; depth translation is deliberately zero.
Every missing or held frame and confidence value is retained for motion review.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import math
from pathlib import Path
import sys
import time
import warnings

import cv2
import numpy as np
from scipy.spatial.transform import Rotation
import mediapipe as mp
from mediapipe.tasks import python
from mediapipe.tasks.python import vision

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "mcp"))
import capture_provenance as provenance

PARENTS = {"Hips": None, "Spine": "Hips", "Spine2": "Spine", "Neck": "Spine2", "Head": "Neck",
           "LeftArm": "Spine2", "LeftForeArm": "LeftArm", "LeftHand": "LeftForeArm",
           "RightArm": "Spine2", "RightForeArm": "RightArm", "RightHand": "RightForeArm",
           "LeftUpLeg": "Hips", "LeftLeg": "LeftUpLeg", "LeftFoot": "LeftLeg", "LeftToeBase": "LeftFoot",
           "RightUpLeg": "Hips", "RightLeg": "RightUpLeg", "RightFoot": "RightLeg", "RightToeBase": "RightFoot"}
CANONICAL = {"Hips": [0, 0, 0], "Spine": [0, .18, 0], "Spine2": [0, .36, 0], "Neck": [0, .50, 0], "Head": [0, .63, 0],
             "LeftArm": [.20, .40, 0], "LeftForeArm": [.48, .40, 0], "LeftHand": [.73, .40, 0],
             "RightArm": [-.20, .40, 0], "RightForeArm": [-.48, .40, 0], "RightHand": [-.73, .40, 0],
             "LeftUpLeg": [.09, -.02, 0], "LeftLeg": [.09, -.44, 0], "LeftFoot": [.09, -.83, 0], "LeftToeBase": [.09, -.86, .15],
             "RightUpLeg": [-.09, -.02, 0], "RightLeg": [-.09, -.44, 0], "RightFoot": [-.09, -.83, 0], "RightToeBase": [-.09, -.86, .15]}
CHILDREN = {key: [child for child, parent in PARENTS.items() if parent == key] for key in PARENTS}
PRIMARY = {key: children[0] for key, children in CHILDREN.items() if children}
PRIMARY.update(Hips="Spine", Spine2="Neck")


def digest(path: Path) -> str:
    result = hashlib.sha256()
    with path.open("rb") as stream:
        for chunk in iter(lambda: stream.read(1048576), b""):
            result.update(chunk)
    return result.hexdigest()


def joints(points: np.ndarray) -> dict[str, np.ndarray]:
    hips = (points[23] + points[24]) * .5
    shoulders = (points[11] + points[12]) * .5
    head = (points[7] + points[8]) * .5
    result = {"Hips": hips, "Spine": hips * .67 + shoulders * .33,
              "Spine2": hips * .15 + shoulders * .85, "Neck": shoulders * .65 + head * .35, "Head": head}
    indices = {"LeftArm": 11, "LeftForeArm": 13, "LeftHand": 15, "RightArm": 12, "RightForeArm": 14, "RightHand": 16,
               "LeftUpLeg": 23, "LeftLeg": 25, "LeftFoot": 27, "LeftToeBase": 31,
               "RightUpLeg": 24, "RightLeg": 26, "RightFoot": 28, "RightToeBase": 32}
    result.update({name: points[index] for name, index in indices.items()})
    return result


def align(source: np.ndarray, target: np.ndarray) -> Rotation:
    a = source / max(np.linalg.norm(source), 1e-9)
    b = target / max(np.linalg.norm(target), 1e-9)
    dot = float(np.clip(np.dot(a, b), -1, 1))
    if dot > .999999:
        return Rotation.identity()
    if dot < -.999999:
        axis = np.cross(a, [1, 0, 0] if abs(a[0]) < .8 else [0, 1, 0])
        return Rotation.from_rotvec(axis / np.linalg.norm(axis) * math.pi)
    q = np.r_[np.cross(a, b), 1 + dot]
    return Rotation.from_quat(q / np.linalg.norm(q))


def export_bvh(path: Path, samples: list[dict], fps: float) -> None:
    offsets = {}
    for name, parent in PARENTS.items():
        direction = np.array(CANONICAL[name]) - np.array(CANONICAL[parent]) if parent else np.zeros(3)
        lengths = [np.linalg.norm(np.array(frame["joints"][name]) - frame["joints"][parent]) for frame in samples] if parent else [0]
        offsets[name] = direction / max(np.linalg.norm(direction), 1e-9) * float(np.median(lengths))
    order = []
    lines = ["HIERARCHY"]

    def write_joint(name: str, level: int):
        order.append(name)
        pad = "  " * level
        lines.extend([pad + ("ROOT " if level == 0 else "JOINT ") + name, pad + "{"])
        lines.append(pad + "  OFFSET " + " ".join(f"{value:.6f}" for value in offsets[name]))
        lines.append(pad + ("  CHANNELS 6 Xposition Yposition Zposition Zrotation Xrotation Yrotation" if level == 0 else "  CHANNELS 3 Zrotation Xrotation Yrotation"))
        for child in CHILDREN[name]:
            write_joint(child, level + 1)
        if not CHILDREN[name]:
            lines.extend([pad + "  End Site", pad + "  {", pad + "    OFFSET 0 0.04 0", pad + "  }"])
        lines.append(pad + "}")

    write_joint("Hips", 0)
    lines.extend(["MOTION", f"Frames: {len(samples)}", f"Frame Time: {1/fps:.9f}"])
    for frame in samples:
        global_rotations = {}
        values = list(frame["root"])
        for name in order:
            child = PRIMARY.get(name)
            if child:
                direction = np.array(CANONICAL[child]) - CANONICAL[name]
                observed = np.array(frame["joints"][child]) - frame["joints"][name]
                global_rotations[name] = align(direction, observed)
            else:
                global_rotations[name] = global_rotations.get(PARENTS[name], Rotation.identity())
            parent_rotation = global_rotations.get(PARENTS[name], Rotation.identity())
            local_rotation = parent_rotation.inv() * global_rotations[name]
            with warnings.catch_warnings():
                warnings.simplefilter("ignore", UserWarning)
                values.extend(local_rotation.as_euler("ZXY", degrees=True).tolist())
        lines.append(" ".join(f"{value:.6f}" for value in values))
    path.write_text("\n".join(lines) + "\n", encoding="utf-8")


def run(args: argparse.Namespace) -> int:
    video = Path(args.video).resolve()
    model = Path(args.model).resolve()
    output = provenance.project_path(args.output, ROOT)
    if output.exists() and (output / "motion.json").exists():
        raise ValueError("Motion output already exists; use a new job directory")
    output.mkdir(parents=True, exist_ok=True)
    status_path = output / "status.json"
    started = time.time()

    def status(phase: str, **extra):
        temporary = status_path.with_suffix(".next.json")
        temporary.write_text(json.dumps(dict(phase=phase, elapsed_s=time.time()-started, **extra)), encoding="utf-8")
        for attempt in range(10):
            try:
                temporary.replace(status_path)
                return
            except PermissionError:
                if attempt == 9:
                    raise
                time.sleep(.01)

    status("loading")
    if not video.is_file() or not model.is_file():
        raise ValueError("Input video and pose model must exist")
    cap = cv2.VideoCapture(str(video))
    source_fps = float(cap.get(cv2.CAP_PROP_FPS))
    width, height = int(cap.get(cv2.CAP_PROP_FRAME_WIDTH)), int(cap.get(cv2.CAP_PROP_FRAME_HEIGHT))
    if source_fps <= 0 or width <= 0:
        raise ValueError("Video has no readable frame timing or dimensions")
    fps = min(args.fps, source_fps)
    frames = []
    previous_hip = np.array([args.subject_x, args.subject_y])
    detections = 0
    next_time = 0.0
    source_index = 0
    options = vision.PoseLandmarkerOptions(base_options=python.BaseOptions(model_asset_path=str(model)),
              running_mode=vision.RunningMode.VIDEO, num_poses=args.max_people,
              min_pose_detection_confidence=.5, min_pose_presence_confidence=.5, min_tracking_confidence=.5)
    with vision.PoseLandmarker.create_from_options(options) as landmarker:
        while True:
            success, bgr = cap.read()
            if not success:
                break
            timestamp = source_index / source_fps
            source_index += 1
            if timestamp + 1e-6 < next_time:
                continue
            if timestamp >= args.seconds:
                break
            next_time += 1/fps
            crop_width, crop_height = int(width*args.crop_width), int(height*args.crop_height)
            crop_x = max(0, min(width-crop_width, int(previous_hip[0]*width-crop_width*.5)))
            crop_y = max(0, min(height-crop_height, int(previous_hip[1]*height-crop_height*.5)))
            crop = bgr[crop_y:crop_y+crop_height, crop_x:crop_x+crop_width]
            image = mp.Image(image_format=mp.ImageFormat.SRGB, data=cv2.cvtColor(crop, cv2.COLOR_BGR2RGB))
            result = landmarker.detect_for_video(image, int(round(timestamp*1000)))
            record = {"time": timestamp, "source_frame": source_index-1, "valid": False,
                      "inference_crop": [crop_x,crop_y,crop_width,crop_height], "candidate_count": len(result.pose_landmarks)}
            if result.pose_landmarks:
                centers = [np.array([((pose[23].x + pose[24].x)*.5*crop_width+crop_x)/width,
                                     ((pose[23].y + pose[24].y)*.5*crop_height+crop_y)/height]) for pose in result.pose_landmarks]
                distances = [float(np.linalg.norm(center-previous_hip)) for center in centers]
                selected = int(np.argmin(distances))
                # A sudden detection switch is recorded as a missing frame.
                if distances[selected] < .18:
                    previous_hip = centers[selected]
                    world = result.pose_world_landmarks[selected]
                    image_points = result.pose_landmarks[selected]
                    confidence = [min(float(point.visibility or 0), float(point.presence or 0)) for point in image_points]
                    full_points = [[(p.x*crop_width+crop_x)/width,(p.y*crop_height+crop_y)/height,p.z*crop_width/width] for p in image_points]
                    record.update(valid=True, confidence=confidence, image_points=full_points,
                                  world_points=[[p.x,-p.y,-p.z] for p in world], image_hip=previous_hip.tolist(), tracking_distance=distances[selected])
                    detections += 1
                    if detections in (1, 15, 30):
                        preview = bgr.copy()
                        cv2.rectangle(preview,(crop_x,crop_y),(crop_x+crop_width,crop_y+crop_height),(180,100,20),1)
                        for point in full_points:
                            cv2.circle(preview, (int(point[0]*width),int(point[1]*height)), 3, (40,240,170), -1)
                        cv2.imwrite(str(output/f"pose-{detections:03}.jpg"), preview)
            frames.append(record)
            if len(frames) % 10 == 0:
                status("tracking", processed_frames=len(frames), detected_frames=detections)
    cap.release()
    (output / "landmarks.json").write_text(json.dumps({"frames":frames},allow_nan=False),encoding="utf-8")
    valid = [frame for frame in frames if frame["valid"]]
    if len(valid) < 2:
        status("error", reason="Fewer than two tracked poses; select a visible full-body subject", detected_frames=detections)
        return 2
    measured_heights = [max(p[1] for p in frame["world_points"][:11]) - min(p[1] for p in frame["world_points"][27:]) + .10 for frame in valid]
    scale = args.subject_height / float(np.median(measured_heights))
    pixel_heights = [(max(p[1] for p in frame["image_points"][27:])-min(p[1] for p in frame["image_points"][:11]))*height for frame in valid[:30]]
    meters_per_pixel = args.subject_height / max(float(np.median(pixel_heights)),1)
    initial_hip = np.array(valid[0]["image_hip"])
    samples = []
    last = valid[0]
    held = 0
    leading_filled = 0
    for record in frames:
        if record["valid"]:
            last = record
        else:
            held += 1
            if record["source_frame"] < valid[0]["source_frame"]:
                leading_filled += 1
        points = np.array(last["world_points"]) * scale
        named = joints(points)
        hip = named["Hips"]
        named = {name:(point-hip).tolist() for name,point in named.items()}
        floor = float(np.min(points[[27,28,29,30,31,32],1]))
        root_x = (last["image_hip"][0]-initial_hip[0])*width*meters_per_pixel
        root_y = float(hip[1]-floor)
        samples.append({"time":record["time"],"valid":record["valid"],"held":not record["valid"],
                        "fill_method":"measured" if record["valid"] else "first_future_valid_pose" if record["source_frame"]<valid[0]["source_frame"] else "previous_valid_pose",
                        "pose_source_frame":last["source_frame"],
                        "root":[root_x,root_y,0.0],"joints":named,"minimum_visibility":min(last["confidence"]),
                        "mean_visibility":float(np.mean(last["confidence"]))})
    # Preserve measured motion. No hidden smoothing, foot locking or keyframed substitutes.
    metadata = {"schema_version":1,"coordinate_system":"right-handed Y-up, meters", "fps":fps,"source_fps":source_fps,
                "source_video":str(video),"source_sha256":digest(video),"model":str(model),"model_sha256":digest(model),
                "mediapipe_version":mp.__version__,"subject_height_m":args.subject_height,"scale":scale,
                "root_calibration":{"method":"fixed-camera image-plane X + measured floor-relative hips Y","meters_per_pixel":meters_per_pixel,
                                    "depth_translation":"unobserved; fixed to zero","floor":"lowest measured heel/toe per frame","root_origin":"first tracked image hip"},
                "quality":{"input_frames":len(frames),"detected_frames":detections,"held_frames":held,"detection_ratio":detections/max(len(frames),1),
                           "leading_filled_frames":leading_filled,
                           "minimum_visibility":min(frame["minimum_visibility"] for frame in samples),"requires_manual_motion_review":True},
                "bones":PARENTS,"frames":samples,"acceptance_scored":False}
    (output/"motion.json").write_text(json.dumps(metadata,ensure_ascii=False,allow_nan=False),encoding="utf-8")
    export_bvh(output/"motion.bvh",samples,fps)
    manifest = {key:metadata[key] for key in ("source_video","source_sha256","model","model_sha256","mediapipe_version","root_calibration","quality")}
    manifest["outputs"] = {name:digest(output/name) for name in ("motion.json","motion.bvh","landmarks.json")}
    (output/"manifest.json").write_text(json.dumps(manifest,ensure_ascii=False,indent=2),encoding="utf-8")
    status("complete",frames=len(samples),detected_frames=detections,motion=str(output/"motion.json"),bvh=str(output/"motion.bvh"))
    print(json.dumps(manifest,ensure_ascii=False),flush=True)
    return 0


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--video",required=True)
    parser.add_argument("--model",default=str(ROOT/".runtime/mocap/models/pose_landmarker_full.task"))
    parser.add_argument("--output",required=True)
    parser.add_argument("--subject-height",type=float,default=1.72)
    parser.add_argument("--subject-x",type=float,default=.5)
    parser.add_argument("--subject-y",type=float,default=.5)
    parser.add_argument("--max-people",type=int,default=3)
    parser.add_argument("--crop-width",type=float,default=1.0,help="Normalized tracking crop width")
    parser.add_argument("--crop-height",type=float,default=1.0,help="Normalized tracking crop height")
    parser.add_argument("--fps",type=float,default=30)
    parser.add_argument("--seconds",type=float,default=20)
    args = parser.parse_args()
    if not .5 <= args.subject_height <= 2.5 or not 1 <= args.fps <= 60 or not 0 < args.seconds <= 300:
        parser.error("Height, FPS or duration is outside the supported capture range")
    if not .1 <= args.crop_width <= 1 or not .1 <= args.crop_height <= 1:
        parser.error("Tracking crop dimensions must be between 0.1 and 1")
    try:
        return run(args)
    except Exception as error:
        output = provenance.project_path(args.output,ROOT)
        output.mkdir(parents=True,exist_ok=True)
        (output/"status.json").write_text(json.dumps({"phase":"error","reason":str(error)}),encoding="utf-8")
        raise


if __name__ == "__main__":
    raise SystemExit(main())
