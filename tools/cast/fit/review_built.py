"""Front review of built hero GLBs against their paintings: render, re-detect, score, side-by-side sheet.

    blender -b --python tools/cast/fit/review_built.py -- --heroes detective,hale,quer,lucian [--clip idle]

Each GLB from assets/characters/heroes is posed on the first frame of `clip` (arms down), rendered from the
front with an orthographic camera in flat material colours, and passed through detect.py. Scores
(MediaPipe body points over figure height, face points over the eye distance) go to
.runtime/facefit/built/<hero>.json; the sheet pairs the painting with the render at equal height.
"""
import argparse
import json
import math
import sys
from pathlib import Path

import bpy
import numpy as np
from mathutils import Matrix, Vector

FIT = Path(__file__).resolve().parent
ROOT = FIT.parents[2]
sys.path.append(str(FIT))
from fit_heroes import FACE, WORK, detect, similarity  # noqa: E402

HEROES = ROOT / "assets" / "characters" / "heroes"
REF = FIT.parent / "reference"


def render_glb(hero, clip, out):
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.ops.import_scene.gltf(filepath=str(HEROES / f"{hero}.glb"))
    rig = next(o for o in bpy.data.objects if o.type == "ARMATURE")
    action = bpy.data.actions.get(f"{clip}_{rig.name}") or bpy.data.actions.get(clip)
    if action:
        rig.animation_data_create()
        rig.animation_data.use_nla = False
        rig.animation_data.action = action
        bpy.context.scene.frame_set(int(action.frame_range[0]))
    bpy.context.view_layer.update()
    meshes = [o for o in bpy.data.objects if o.type == "MESH"]
    deps = bpy.context.evaluated_depsgraph_get()
    zs, xs = [], []
    for o in meshes:
        m = o.evaluated_get(deps).to_mesh()
        for v in m.vertices:
            w = o.matrix_world @ v.co
            zs.append(w.z)
            xs.append(w.x)
        o.evaluated_get(deps).to_mesh_clear()
    top, bottom = max(zs), min(zs)
    scene = bpy.context.scene
    scene.render.engine = "BLENDER_WORKBENCH"
    sh = scene.display.shading
    sh.light, sh.color_type, sh.show_object_outline = "STUDIO", "MATERIAL", True
    sh.object_outline_color = (0.05, 0.05, 0.06)
    sh.background_type, sh.background_color = "VIEWPORT", (0.30, 0.34, 0.40)
    scene.view_settings.view_transform = "Standard"
    scene.render.resolution_x, scene.render.resolution_y = 768, 1152
    cam_data = bpy.data.cameras.new("Cam")
    cam_data.type, cam_data.ortho_scale = "ORTHO", (top - bottom) * 1.5 * 1.08
    cam = bpy.data.objects.new("Cam", cam_data)
    scene.collection.objects.link(cam)
    cam.location = (0.0, -6.0, (top + bottom) / 2)
    cam.rotation_euler = (math.pi / 2, 0.0, 0.0)
    scene.camera = cam
    scene.render.filepath = str(out)
    bpy.ops.render.render(write_still=True)
    return {"top": top, "bottom": bottom, "rig": rig, "cam": cam}


def render_face(view, pose, out):
    """Close-up of the head from the painting's head pose (yaw/pitch solved by fit_heroes.py)."""
    rig, cam = view["rig"], view["cam"]
    head = next(b for b in rig.pose.bones if b.name.endswith(":Head"))
    a, b = rig.matrix_world @ head.head, rig.matrix_world @ head.tail
    pivot = a.lerp(b, 0.45)
    orbit = Matrix.Rotation(math.radians(pose.get("yaw_deg", 0.0)), 3, "Z") @         Matrix.Rotation(math.radians(pose.get("pitch_deg", 0.0)), 3, "X")
    cam.location = pivot + orbit @ Vector((0.0, -6.0, -0.01))
    cam.rotation_euler = (orbit @ Matrix.Rotation(math.pi / 2, 3, "X")).to_euler()
    cam.data.ortho_scale = 0.40
    scene = bpy.context.scene
    scene.render.resolution_x = scene.render.resolution_y = 768
    scene.display.shading.color_type = "MATERIAL"
    scene.render.filepath = str(out)
    bpy.ops.render.render(write_still=True)


def score(ref, got):
    out = {}
    if ref["pose"] and got["pose"]:
        ids = [0, 11, 12, 23, 24, 25, 26, 27, 28]
        a = np.array([got["pose"][i][:2] for i in ids])
        b = np.array([ref["pose"][i][:2] for i in ids])
        err = np.linalg.norm(similarity(a, b)(a) - b, axis=1) / np.ptp(b[:, 1])
        out["body_nme_height"], out["body_max_height"] = round(float(err.mean()), 4), round(float(err.max()), 4)
    if ref["face"] and got["face"]:
        a = np.array([got["face"][i][:2] for i in FACE])
        b = np.array([ref["face"][i][:2] for i in FACE])
        iod = np.linalg.norm(np.subtract(ref["face"][33][:2], ref["face"][263][:2]))
        err = np.linalg.norm(similarity(a, b)(a) - b, axis=1) / iod
        out["face_nme_iod"] = round(float(err.mean()), 4)
    return out


def main():
    p = argparse.ArgumentParser()
    p.add_argument("--heroes", default="detective,hale,quer,lucian")
    p.add_argument("--clip", default="idle")
    args = p.parse_args(sys.argv[sys.argv.index("--") + 1:])
    out_dir = WORK / "built"
    out_dir.mkdir(parents=True, exist_ok=True)
    for hero in args.heroes.split(","):
        png = out_dir / f"{hero}.png"
        view = render_glb(hero, args.clip, png)
        got = detect(png, tag=f"built/{hero}")
        ref = json.loads((WORK / "ref" / f"{hero}.json").read_text())
        result = score(ref, got)
        fit = json.loads((FIT / f"{hero}.json").read_text())
        face_png = out_dir / f"{hero}-face.png"
        render_face(view, fit.get("painting_head_pose", {}), face_png)
        face = detect(face_png, tag=f"built/{hero}-face")
        result["face_closeup_nme_iod"] = score(ref, dict(face, pose=None)).get("face_nme_iod")
        (out_dir / f"{hero}.json").write_text(json.dumps(result, indent=1))
        print("BUILT_REVIEW", hero, json.dumps(result))


if __name__ == "__main__":
    main()
