"""Detect body (33) and face (478) landmarks with MediaPipe on a painting or a render.

Runs outside Blender (needs mediapipe, opencv, numpy):
    python detect.py --image ref.jpg --box x0 y0 x1 y1 --out ref.json [--overlay ref.png]
    python detect.py --manifest tools/cast/reference/manifest.json --out-dir <dir>

Coordinates in the JSON are pixels of the source image. The face is found in a second pass on an
upscaled square around the head that the pose pass located, so small painted faces still resolve.
"""
import argparse
import json
from pathlib import Path

import cv2
import mediapipe as mp
import numpy as np
from mediapipe.tasks.python import BaseOptions, vision

MODELS = Path(__file__).resolve().parents[3] / ".runtime" / "facefit" / "models"


class Detector:
    def __init__(self, models=MODELS):
        self.pose = vision.PoseLandmarker.create_from_options(vision.PoseLandmarkerOptions(
            base_options=BaseOptions(model_asset_path=str(models / "pose_landmarker_heavy.task")),
            min_pose_detection_confidence=0.2, min_pose_presence_confidence=0.2))
        self.face = vision.FaceLandmarker.create_from_options(vision.FaceLandmarkerOptions(
            base_options=BaseOptions(model_asset_path=str(models / "face_landmarker.task")),
            min_face_detection_confidence=0.2, min_face_presence_confidence=0.2))

    @staticmethod
    def _mp(rgb):
        return mp.Image(image_format=mp.ImageFormat.SRGB, data=np.ascontiguousarray(rgb))

    def run(self, rgb, box=None):
        h, w = rgb.shape[:2]
        x0, y0, x1, y1 = box or (0, 0, w, h)
        crop = rgb[y0:y1, x0:x1]
        s = 1280 / max(crop.shape[:2])
        big = cv2.resize(crop, None, fx=s, fy=s, interpolation=cv2.INTER_CUBIC)
        res = self.pose.detect(self._mp(big))
        out = {"box": [x0, y0, x1, y1], "pose": None, "face": None}
        if res.pose_landmarks:
            bw, bh = big.shape[1], big.shape[0]
            out["pose"] = [[x0 + p.x * bw / s, y0 + p.y * bh / s, p.visibility] for p in res.pose_landmarks[0]]
        out["face"], out["face_box"] = self._face(rgb, out["pose"], (x0, y0, x1, y1))
        return out

    def _face(self, rgb, pose, box):
        h, w = rgb.shape[:2]
        if pose:
            head = np.array([p[:2] for p in pose[:11]])
            centre = head.mean(axis=0)
            span = max(np.ptp(head[:, 0]), np.ptp(head[:, 1]), 1.0)
            sizes = [3.2 * span, 4.5 * span, 2.4 * span]
        else:
            x0, y0, x1, y1 = box
            centre = np.array([(x0 + x1) / 2, y0 + (y1 - y0) * 0.12])
            sizes = [(x1 - x0) * 0.6]
        for size in sizes:
            hx0, hy0 = int(max(0, centre[0] - size / 2)), int(max(0, centre[1] - size / 2))
            hx1, hy1 = int(min(w, centre[0] + size / 2)), int(min(h, centre[1] + size / 2))
            crop = rgb[hy0:hy1, hx0:hx1]
            s = 640 / max(crop.shape[:2])
            big = cv2.resize(crop, None, fx=s, fy=s, interpolation=cv2.INTER_CUBIC)
            res = self.face.detect(self._mp(big))
            if res.face_landmarks:
                bw, bh = big.shape[1], big.shape[0]
                pts = [[hx0 + p.x * bw / s, hy0 + p.y * bh / s, p.z * bw / s] for p in res.face_landmarks[0]]
                return pts, [hx0, hy0, hx1, hy1]
        return None, None


def overlay(rgb, det, path):
    img = cv2.cvtColor(rgb, cv2.COLOR_RGB2BGR).copy()
    if det["face"]:
        for x, y, _ in det["face"]:
            cv2.circle(img, (int(round(x)), int(round(y))), 1, (80, 255, 80), -1)
    if det["pose"]:
        for i, (x, y, v) in enumerate(det["pose"]):
            if i > 10:
                cv2.circle(img, (int(x), int(y)), 4, (0, 200, 255), -1)
    x0, y0, x1, y1 = det["box"]
    img = img[y0:y1, x0:x1]
    cv2.imwrite(str(path), img)


def load_rgb(path):
    bgr = cv2.imdecode(np.fromfile(str(path), dtype=np.uint8), cv2.IMREAD_COLOR)
    return cv2.cvtColor(bgr, cv2.COLOR_BGR2RGB)


def main():
    p = argparse.ArgumentParser()
    p.add_argument("--image", type=Path)
    p.add_argument("--box", type=int, nargs=4)
    p.add_argument("--out", type=Path)
    p.add_argument("--overlay", type=Path)
    p.add_argument("--manifest", type=Path)
    p.add_argument("--out-dir", type=Path)
    p.add_argument("--batch", type=Path, help="JSON list of {image, out[, box]}; one model load for all")
    a = p.parse_args()
    det = Detector()
    if a.batch:
        for job in json.loads(a.batch.read_text()):
            d = det.run(load_rgb(job["image"]), job.get("box"))
            Path(job["out"]).write_text(json.dumps(d))
        print("BATCH", a.batch)
        return
    if a.manifest:
        man = json.loads(a.manifest.read_text(encoding="utf-8"))
        a.out_dir.mkdir(parents=True, exist_ok=True)
        for hero, spec in man.items():
            if not isinstance(spec, dict):
                continue
            rgb = load_rgb(a.manifest.parent / spec["image"])
            d = det.run(rgb, spec["box"])
            (a.out_dir / f"{hero}.json").write_text(json.dumps(d))
            overlay(rgb, d, a.out_dir / f"{hero}-landmarks.png")
            print(hero, "pose" if d["pose"] else "NO-POSE", "face" if d["face"] else "NO-FACE")
        return
    rgb = load_rgb(a.image)
    d = det.run(rgb, a.box)
    a.out.write_text(json.dumps(d))
    if a.overlay:
        overlay(rgb, d, a.overlay)
    print("pose" if d["pose"] else "NO-POSE", "face" if d["face"] else "NO-FACE")


if __name__ == "__main__":
    main()
