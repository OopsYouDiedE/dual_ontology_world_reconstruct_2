"""Fit each hero's MPFB2 body and face to its target painting, using MediaPipe landmarks on both sides.

Run inside Blender 4.2 with MPFB 2.0.18 (isolated profile, see tools/cast/README.md):
    blender -b --python tools/cast/fit/fit_heroes.py -- --system-pack <system_cc0.zip> calibrate
    blender -b --python tools/cast/fit/fit_heroes.py -- --system-pack <system_cc0.zip> fit --only quer

calibrate  Renders a neutral MPFB human, detects its face and body landmarks, and stores which mesh
           point each face landmark lands on (face_map.json) and how MediaPipe body points sit relative
           to MPFB joints (pose_bias in the same file).
fit        For each hero: race and age macros from the manifest and HEROES, then a bounded least-squares
           solve of body-proportion targets (eye, shoulders, hips, knees, ankles, arm lengths, head size)
           followed by face-shape targets (oval, eyes, brows, nose, lips). The solved targets go to
           tools/cast/fit/<hero>.json, which build_heroes.py applies. A verification render (arms
           lowered) is re-detected with MediaPipe and the landmark errors are written next to it.

Landmark detection runs in a separate Python with MediaPipe (.runtime/facefit-venv, see detect.py).
"""
import argparse
import json
import math
import os
import subprocess
import sys
import zipfile
from pathlib import Path

import bpy
import numpy as np
from mathutils import Matrix, Vector
from mathutils.bvhtree import BVHTree
from mathutils.interpolate import poly_3d_calc

from bl_ext.user_default.mpfb.services.humanservice import HumanService
from bl_ext.user_default.mpfb.services.locationservice import LocationService
from bl_ext.user_default.mpfb.services.targetservice import TargetService

FIT = Path(__file__).resolve().parent
ROOT = FIT.parents[2]
REF = FIT.parent / "reference"
WORK = ROOT / ".runtime" / "facefit"
VENV = ROOT / ".runtime" / "facefit-venv" / "Scripts" / "python.exe"
sys.path.append(str(FIT.parent))
sys.path.append(str(FIT))
from build_heroes import HEROES  # noqa: E402
from face_params import (BROWS, EYE_L, EYE_R, EYES, FACE, FACE_LIMIT, FACE_PARAMS, FACE_W,  # noqa: E402,F401
                         LIPS, NOSE, OVAL, pair, sym)

# ------------------------------------------------------------------ MediaPipe landmark sets

# MediaPipe pose index -> MPFB joint helper group (person's left = MakeHuman "l" = +X = image right).
POSE = {11: "joint-l-shoulder", 12: "joint-r-shoulder", 23: "joint-l-upper-leg", 24: "joint-r-upper-leg",
        25: "joint-l-knee", 26: "joint-r-knee", 27: "joint-l-ankle", 28: "joint-r-ankle"}
ARMS = [((11, 13), ("joint-l-shoulder", "joint-l-elbow")), ((12, 14), ("joint-r-shoulder", "joint-r-elbow")),
        ((13, 15), ("joint-l-elbow", "joint-l-hand")), ((14, 16), ("joint-r-elbow", "joint-r-hand"))]




BODY_TARGETS = [
    ["head-scale-vert-incr"], ["head-scale-vert-decr"], ["head-scale-horiz-incr"], ["head-scale-horiz-decr"],
    ["neck-scale-vert-incr"], ["neck-scale-vert-decr"], ["neck-scale-horiz-incr"], ["neck-scale-horiz-decr"],
    ["torso-scale-vert-incr"], ["torso-scale-vert-decr"], ["torso-scale-horiz-incr"], ["torso-scale-horiz-decr"],
    ["measure-shoulder-dist-incr"], ["measure-shoulder-dist-decr"], ["torso-vshape-incr"], ["torso-vshape-decr"],
    ["hip-scale-horiz-incr"], ["hip-scale-horiz-decr"], ["hip-scale-vert-incr"], ["hip-scale-vert-decr"],
    ["upperlegs-height-incr"], ["upperlegs-height-decr"], ["lowerlegs-height-incr"], ["lowerlegs-height-decr"],
    ["measure-upperarm-length-incr"], ["measure-upperarm-length-decr"],
    ["measure-lowerarm-length-incr"], ["measure-lowerarm-length-decr"],
]
FACE_TARGETS = [
    ["head-oval"], ["head-round"], ["head-square"], ["head-rectangular"], ["head-triangular"],
    ["head-invertedtriangular"], ["head-diamond"], ["head-scale-horiz-incr"], ["head-scale-horiz-decr"],
    ["head-fat-incr"], ["head-fat-decr"], ["forehead-scale-vert-incr"], ["forehead-scale-vert-decr"],
    ["chin-width-incr"], ["chin-width-decr"], ["chin-height-incr"], ["chin-height-decr"],
    ["chin-jaw-drop-incr"], ["chin-jaw-drop-decr"], ["chin-triangle"], ["chin-bones-incr"], ["chin-bones-decr"],
    sym("cheek-bones-incr"), sym("cheek-bones-decr"), sym("cheek-volume-incr"), sym("cheek-volume-decr"),
    sym("cheek-inner-incr"), sym("cheek-inner-decr"),
    sym("eye-scale-incr"), sym("eye-scale-decr"), sym("eye-trans-up"), sym("eye-trans-down"),
    sym("eye-trans-in"), sym("eye-trans-out"), sym("eye-height2-incr"), sym("eye-height2-decr"),
    sym("eye-corner1-up"), sym("eye-corner1-down"), sym("eye-corner2-up"), sym("eye-corner2-down"),
    ["eyebrows-trans-up"], ["eyebrows-trans-down"], ["eyebrows-angle-up"], ["eyebrows-angle-down"],
    ["nose-scale-horiz-incr"], ["nose-scale-horiz-decr"], ["nose-scale-vert-incr"], ["nose-scale-vert-decr"],
    ["nose-trans-up"], ["nose-trans-down"], ["nose-flaring-incr"], ["nose-flaring-decr"],
    ["nose-point-width-incr"], ["nose-point-width-decr"],
    ["mouth-scale-horiz-incr"], ["mouth-scale-horiz-decr"], ["mouth-scale-vert-incr"], ["mouth-scale-vert-decr"],
    ["mouth-trans-up"], ["mouth-trans-down"], ["mouth-upperlip-height-incr"], ["mouth-upperlip-height-decr"],
    ["mouth-lowerlip-height-incr"], ["mouth-lowerlip-height-decr"], ["mouth-angles-up"], ["mouth-angles-down"],
]

# Body targets that read as deformity well before they reach 1.
BODY_CAP = {"neck-scale-vert-incr": 0.35, "neck-scale-vert-decr": 0.5, "head-scale-vert-decr": 0.5,
            "head-scale-horiz-decr": 0.5, "torso-vshape-decr": 0.5}

SKINS = {("caucasian", 1): "young_caucasian_male", ("caucasian", 0): "young_caucasian_female",
         ("asian", 1): "young_asian_male", ("asian", 0): "young_asian_female",
         ("african", 1): "young_african_male", ("african", 0): "young_african_female"}


# ------------------------------------------------------------------ helpers
def activate(obj):
    bpy.ops.object.select_all(action="DESELECT")
    obj.select_set(True)
    bpy.context.view_layer.objects.active = obj


def detect(image, box=None, tag="render"):
    out = WORK / f"{tag}.json"
    cmd = [str(VENV), str(FIT / "detect.py"), "--image", str(image), "--out", str(out),
           "--overlay", str(WORK / f"{tag}-landmarks.png")]
    if box:
        cmd += ["--box", *map(str, box)]
    env = dict(os.environ, TF_CPP_MIN_LOG_LEVEL="3", GLOG_minloglevel="3", PYTHONNOUSERSITE="")
    for k in ("PYTHONHOME", "PYTHONPATH"):
        env.pop(k, None)
    r = subprocess.run(cmd, capture_output=True, text=True, env=env)
    if r.returncode:
        raise RuntimeError(r.stderr[-2000:])
    return json.loads(out.read_text())


def human(macro, asset_root, skin, brows="eyebrow001"):
    bpy.ops.wm.read_factory_settings(use_empty=True)
    m = TargetService.get_default_macro_info_dict()
    m.update(macro)
    body = HumanService.create_human(macro_detail_dict=m, feet_on_ground=True)
    HumanService.add_mhclo_asset(asset_root / "eyes/low-poly/low-poly.mhclo", body, asset_type="Eyes",
                                 subdiv_levels=0, material_type="GAMEENGINE")
    HumanService.add_mhclo_asset(asset_root / f"eyebrows/{brows}/{brows}.mhclo", body, asset_type="Eyebrows",
                                 subdiv_levels=0, material_type="GAMEENGINE")
    HumanService.set_character_skin(str(asset_root / f"skins/{skin}/{skin}.mhmat"), body, skin_type="GAMEENGINE")
    return body


def body_faces(body):
    group = body.vertex_groups["body"].index
    inside = np.zeros(len(body.data.vertices), bool)
    for v in body.data.vertices:
        if any(g.group == group for g in v.groups):
            inside[v.index] = True
    return [p for p in body.data.polygons if all(inside[i] for i in p.vertices)], inside


def keyed_coords(body):
    """Vertex positions with every shape key mixed in (no modifiers), as an (N, 3) array."""
    keys = body.data.shape_keys.key_blocks
    n = len(body.data.vertices)
    basis = np.empty(n * 3)
    keys[0].data.foreach_get("co", basis)
    basis = basis.reshape(-1, 3)
    out = basis.copy()
    buf = np.empty(n * 3)
    for kb in keys[1:]:
        if kb.value and not kb.mute:
            kb.data.foreach_get("co", buf)
            out += kb.value * (buf.reshape(-1, 3) - basis)
    return out, basis


def joint_groups(body):
    names = {g.index: g.name for g in body.vertex_groups}
    groups = {}
    for v in body.data.vertices:
        for g in v.groups:
            n = names[g.group]
            if n.startswith("joint-"):
                groups.setdefault(n, []).append(v.index)
    return groups


def load_deltas(body, targets, basis):
    """Per parameter: summed vertex delta of its targets (each loaded at weight 0)."""
    n = len(body.data.vertices)
    buf = np.empty(n * 3)
    deltas = []
    for group in targets:
        d = np.zeros((n, 3))
        for t in group:
            if t not in body.data.shape_keys.key_blocks:
                TargetService.load_target(body, TargetService.target_full_path(t), weight=0.0, name=t)
            kb = body.data.shape_keys.key_blocks[t]
            kb.data.foreach_get("co", buf)
            d += buf.reshape(-1, 3) - basis
        deltas.append(d)
    return deltas


def set_weights(body, targets, w):
    keys = body.data.shape_keys.key_blocks
    for group, value in zip(targets, w):
        for t in group:
            kb = keys[t]
            kb.slider_min, kb.slider_max = 0.0, 1.0
            kb.value = float(value)


# ------------------------------------------------------------------ cameras and renders
def setup_render(res):
    scene = bpy.context.scene
    scene.render.engine = "BLENDER_WORKBENCH"
    scene.display.shading.light = "STUDIO"
    scene.display.shading.color_type = "TEXTURE"
    scene.display.shading.show_cavity = False
    scene.render.resolution_x, scene.render.resolution_y = res
    scene.render.film_transparent = False
    scene.world = scene.world or bpy.data.worlds.new("World")
    scene.display.shading.background_type = "VIEWPORT"
    scene.display.shading.background_color = (0.30, 0.34, 0.40)
    scene.view_settings.view_transform = "Standard"


def ortho_camera(centre, size, yaw=0.0, pitch=0.0, pivot_y=0.0):
    """Front orthographic camera; yaw/pitch (degrees) orbit it around (centre x, pivot_y, centre z)."""
    cam_data = bpy.data.cameras.new("Cam")
    cam_data.type = "ORTHO"
    cam_data.ortho_scale = size
    cam = bpy.data.objects.new("Cam", cam_data)
    bpy.context.scene.collection.objects.link(cam)
    orbit = Matrix.Rotation(math.radians(yaw), 3, "Z") @ Matrix.Rotation(math.radians(pitch), 3, "X")
    pivot = Vector((centre[0], pivot_y, centre[1]))
    cam.location = pivot + orbit @ Vector((0.0, -6.0, 0.0))
    cam.rotation_euler = (orbit @ Matrix.Rotation(math.pi / 2, 3, "X")).to_euler()
    bpy.context.scene.camera = cam
    return cam


def render(path, centre, size, res, yaw=0.0, pitch=0.0, pivot_y=0.0):
    setup_render(res)
    for o in [o for o in bpy.data.objects if o.type == "CAMERA"]:
        bpy.data.objects.remove(o, do_unlink=True)
    ortho_camera(centre, size, yaw, pitch, pivot_y)
    bpy.context.scene.render.filepath = str(path)
    bpy.ops.render.render(write_still=True)
    return {"centre": list(centre), "size": size, "res": list(res)}


def pixel_to_world(view, px, py):
    w, h = view["res"]
    unit = view["size"] / max(w, h)
    return (view["centre"][0] + (px - w / 2) * unit, view["centre"][1] - (py - h / 2) * unit)


def world_to_pixel(view, x, z):
    w, h = view["res"]
    unit = view["size"] / max(w, h)
    return (w / 2 + (x - view["centre"][0]) / unit, h / 2 - (z - view["centre"][1]) / unit)


def lower_arms(body, angle=8.0):
    """Add the Mixamo rig and swing both upper arms down to hang `angle` degrees off vertical."""
    rig = HumanService.add_builtin_rig(body, "mixamo")
    bpy.context.view_layer.update()
    for side, sign in (("Left", 1), ("Right", -1)):
        pb = next(p for p in rig.pose.bones if p.name.endswith(f"{side}Arm"))
        head = rig.matrix_world @ pb.head
        tail = rig.matrix_world @ pb.tail
        cur = (tail - head).normalized()
        a = math.radians(angle)
        want = Vector((sign * math.sin(a), 0.0, -math.cos(a)))
        rot = cur.rotation_difference(want).to_matrix().to_4x4()
        m = pb.matrix.copy()
        loc = m.to_translation()
        pb.matrix = Matrix.Translation(loc) @ rot @ Matrix.Translation(-loc) @ m
        bpy.context.view_layer.update()
    return rig


# ------------------------------------------------------------------ calibration
def calibrate(asset_root):
    WORK.mkdir(parents=True, exist_ok=True)
    macro = dict(gender=1.0, age=0.5, race={"caucasian": 1.0, "asian": 0.0, "african": 0.0})
    body = human(macro, asset_root, "young_caucasian_male")
    bpy.context.view_layer.update()
    coords, _ = keyed_coords(body)
    groups = joint_groups(body)
    joint = {k: coords[v].mean(axis=0) for k, v in groups.items()}
    # Face: close-up, then cast each landmark back onto the mesh.
    head_c = (joint["joint-l-eye"] + joint["joint-r-eye"]) / 2
    view = render(WORK / "calib-face.png", (0.0, head_c[2] - 0.03), 0.34, (768, 768))
    det = detect(WORK / "calib-face.png", tag="calib-face")
    assert det["face"], "no face on the calibration render"
    polys, _ = body_faces(body)
    verts = [Vector(c) for c in coords]
    tris = [list(p.vertices) for p in polys]
    tree = BVHTree.FromPolygons(verts, tris)
    fmap = {}
    for i, (px, py, _) in enumerate(det["face"][:468]):
        x, z = pixel_to_world(view, px, py)
        hit = tree.ray_cast(Vector((x, -6.0, z)), Vector((0, 1, 0)))
        if hit[0] is None:
            continue
        ids = tris[hit[2]]
        w = poly_3d_calc([verts[j] for j in ids], hit[0])
        fmap[i] = [ids, [round(float(a), 6) for a in w]]
    # Body: the same render path at full length, so MediaPipe's own bias toward MPFB joints is known.
    height = coords[:, 2].max() - coords[:, 2].min()
    view = render(WORK / "calib-body.png", (0.0, height / 2), height * 1.1, (768, 1024))
    det = detect(WORK / "calib-body.png", tag="calib-body")
    assert det["pose"], "no body on the calibration render"
    bias = {}
    for idx, group in POSE.items():
        x, z = pixel_to_world(view, *det["pose"][idx][:2])
        j = joint[group]
        bias[idx] = [(x - j[0]) / height, (z - j[2]) / height]
    out = {"face": fmap, "pose_bias": bias, "note": "MediaPipe face landmark -> MPFB hm08 polygon + weights"}
    (FIT / "face_map.json").write_text(json.dumps(out))
    print("CALIBRATED", len(fmap), "face points", json.dumps(bias))


# ------------------------------------------------------------------ fitting
class Model:
    """Front-view (x, z) of mapped landmarks and joints as a linear function of target weights."""

    def __init__(self, body, fmap, bias, targets):
        self.body = body
        self.coords0, self.basis = keyed_coords(body)
        self.groups = joint_groups(body)
        self.targets = targets
        self.deltas = load_deltas(body, targets, self.basis)
        self.fmap = fmap
        self.bias = bias
        self.height0 = self.coords0[:, 2].max() - self.coords0[:, 2].min()

    def _face_matrix(self, ids):
        rows = []
        for i in ids:
            vids, w = self.fmap[str(i)]
            rows.append((vids, w))
        return rows

    def points(self, coords, face_ids, pose_ids):
        out = []
        for vids, w in self._face_matrix(face_ids):
            out.append(sum(coords[v] * a for v, a in zip(vids, w)))
        for idx in pose_ids:
            j = coords[self.groups[POSE[idx]]].mean(axis=0)
            b = self.bias[str(idx)]
            out.append(j + np.array([b[0], 0.0, b[1]]) * self.height0)
        return np.array(out)

    def arm_lengths(self, coords):
        out = []
        for _, (a, b) in ARMS:
            out.append(np.linalg.norm(coords[self.groups[a]].mean(0) - coords[self.groups[b]].mean(0)))
        return np.array(out)

    def coords(self, w):
        c = self.coords0.copy()
        for wk, d in zip(w, self.deltas):
            if wk:
                c += wk * d
        return c


def solve(model, face_ids, pose_ids, ref_pts, ref_w, ref_arms=None, arm_w=0.0, ridge=0.02, iters=40, hi=None):
    """Bounded Gauss-Newton on target weights w in [0, hi] plus a 2D scale and translation."""
    K = len(model.targets)
    hi = np.ones(K) if hi is None else np.asarray(hi)
    w = np.zeros(K)
    # Linear pieces: points(w) = P0 + sum w_k Dk (front x, z).
    P0 = model.points(model.coords0, face_ids, pose_ids)[:, [0, 2]]
    D = [model.points(model.coords0 + d, face_ids, pose_ids)[:, [0, 2]] - P0 for d in model.deltas]
    R = np.asarray(ref_pts)
    W = np.sqrt(np.asarray(ref_w))[:, None]
    A0 = model.arm_lengths(model.coords0) if ref_arms is not None else None
    # Initial similarity (scale + translation, no rotation).
    c0, cr = P0.mean(0), R.mean(0)
    s = np.sqrt(((R - cr) ** 2).sum() / ((P0 - c0) ** 2).sum())
    t = cr - s * c0
    for _ in range(iters):
        P = P0 + sum(wk * d for wk, d in zip(w, D))
        r_pts = (W * (s * P + t - R)).ravel()
        J = [(W * (s * d)).ravel() for d in D]
        Js = (W * P).ravel()
        Jt = [np.tile(np.array([1.0, 0.0]), len(P)) * W.repeat(2, 1).ravel(),
              np.tile(np.array([0.0, 1.0]), len(P)) * W.repeat(2, 1).ravel()]
        res = [r_pts]
        cols = [np.column_stack(J + [Js] + Jt)]
        if ref_arms is not None:
            c = model.coords(w)
            L = model.arm_lengths(c)
            dL = []
            for d in model.deltas:
                dL.append(model.arm_lengths(c + 1e-3 * d) - L)
            dL = np.array(dL).T / 1e-3
            res.append(arm_w * (s * L - ref_arms))
            cols.append(np.column_stack([arm_w * s * dL, arm_w * L, np.zeros(len(L)), np.zeros(len(L))]))
        res.append(ridge * w)
        cols.append(np.column_stack([ridge * np.eye(K), np.zeros((K, 3))]))
        r = np.concatenate(res)
        J = np.vstack(cols)
        step = np.linalg.solve(J.T @ J + 1e-6 * np.eye(K + 3), -J.T @ r)
        w = np.clip(w + step[:K], 0.0, hi)
        s, t = s + step[K], t + step[K + 1:]
    P = P0 + sum(wk * d for wk, d in zip(w, D))
    return w, s, t, s * P + t


def ref_points(det, face_ids, pose_ids):
    pts = [det["face"][i][:2] for i in face_ids] + [det["pose"][i][:2] for i in pose_ids]
    # Model space is (x, z) with z up; image space is y down.
    return np.array([[x, -y] for x, y in pts])


def eye_centre(face):
    return np.mean([face[i][:2] for i in EYE_L + EYE_R], axis=0)


def fit_hero(hero, asset_root, fmap, bias, manifest):
    spec, man = HEROES[hero], manifest[hero]
    det = json.loads((WORK / "ref" / f"{hero}.json").read_text())
    race = {"caucasian": 0.0, "asian": 0.0, "african": 0.0}
    race.update(man["race"])
    macro = dict(spec["macro"], race=race)
    gender = 1 if macro.get("gender", 0.5) >= 0.5 else 0
    skin = SKINS[(max(race, key=race.get), gender)]
    body = human(macro, asset_root, skin, spec["brows"])
    bpy.context.view_layer.update()
    face_ids = [i for i in FACE if str(i) in fmap]
    pose_ids = list(POSE)

    # --- stage 1: body proportions (joints, arm lengths, head size and placement)
    head_ids = [i for i in (152, 234, 454, 33, 263, 1, 13) if str(i) in fmap]
    model = Model(body, fmap, bias, BODY_TARGETS)
    R = ref_points(det, head_ids, pose_ids)
    scale = np.ptp(R[:, 1])
    Rn = R / scale
    Wt = [1.0] * len(head_ids) + [2.0] * len(pose_ids)
    arms = np.array([np.linalg.norm(np.subtract(det["pose"][a][:2], det["pose"][b][:2])) for (a, b), _ in ARMS]) / scale
    hi = [BODY_CAP.get(g[0], 1.0) for g in BODY_TARGETS]
    w_body, s1, t1, fitted = solve(model, head_ids, pose_ids, Rn, Wt, arms, arm_w=1.0, ridge=0.015, hi=hi)
    set_weights(body, BODY_TARGETS, w_body)
    body_err = float(np.sqrt(((fitted - Rn) ** 2).sum(1)).mean())

    # --- stage 2: face shape, closed loop through the detector (render -> MediaPipe -> solve)
    HumanService.refit(body)
    v_face, face_err, history, pose = face_loop(hero, body, det)

    targets = {}
    for group, value in zip(BODY_TARGETS, w_body):
        for t in group:
            if value > 1e-3:
                targets[t] = round(float(value), 4)
    for (pos, neg), value in zip(FACE_PARAMS, v_face):
        for t in (pos if value > 0 else neg):
            if abs(value) > 1e-3:
                targets[t] = round(float(targets.get(t, 0.0) + abs(value)), 4)
    result = {"macro": macro, "skin_reference": skin, "targets": targets,
              "solve": {"body_mean_err_of_height": round(body_err, 4), "face_loop_nme": history},
              "painting_head_pose": {k: pose[k] for k in ("yaw_deg", "pitch_deg")}}
    result["verify"] = verify(hero, body, det, fmap, pose)
    # Baseline: the same hero as build_heroes made it before fitting (default race mix, no targets).
    base = human(dict(spec["macro"]), asset_root, skin, spec["brows"])
    result["baseline"] = verify(hero + "-base", base, det, fmap, pose)
    (FIT / f"{hero}.json").write_text(json.dumps(result, indent=1) + "\n")
    print("FIT_PASS", hero, json.dumps(result["solve"]), json.dumps(result["verify"]), json.dumps(result["baseline"]))


def set_face(body, v):
    keys = body.data.shape_keys.key_blocks
    for (pos, neg), value in zip(FACE_PARAMS, v):
        for names, w in ((pos, max(0.0, value)), (neg, max(0.0, -value))):
            for t in names:
                if t not in keys:
                    TargetService.load_target(body, TargetService.target_full_path(t), weight=0.0, name=t)
                kb = keys[t]
                kb.slider_min, kb.slider_max = 0.0, 1.0
                kb.value = float(w)
    HumanService.refit(body)
    bpy.context.view_layer.update()


def face_view(body):
    coords, _ = keyed_coords(body)
    groups = joint_groups(body)
    eye = (coords[groups["joint-l-eye"]].mean(0) + coords[groups["joint-r-eye"]].mean(0)) / 2
    return (0.0, float(eye[2]) - 0.03), float(eye[1]) + 0.08


def detect_batch(jobs, tag):
    listing = WORK / f"{tag}-batch.json"
    listing.write_text(json.dumps(jobs))
    env = dict(os.environ, TF_CPP_MIN_LOG_LEVEL="3", GLOG_minloglevel="3")
    for k in ("PYTHONHOME", "PYTHONPATH"):
        env.pop(k, None)
    r = subprocess.run([str(VENV), str(FIT / "detect.py"), "--batch", str(listing)],
                       capture_output=True, text=True, env=env)
    if r.returncode:
        raise RuntimeError(r.stderr[-2000:])
    return [json.loads(Path(j["out"]).read_text()) for j in jobs]


def face_residual(face, ref, weights, T=None):
    a = np.array([face[i][:2] for i in FACE])
    b = np.array([ref["face"][i][:2] for i in FACE])
    iod = np.linalg.norm(np.subtract(ref["face"][33][:2], ref["face"][263][:2]))
    T = T or similarity(a, b)
    return (np.sqrt(weights)[:, None] * (T(a) - b) / iod).ravel(), T


POSE_DEG = 20.0   # one unit of a head-pose parameter, in degrees of camera orbit


def face_loop(hero, body, ref, iters=10, h=0.2, ridge=0.05):
    """Gauss-Newton on FACE_PARAMS with a finite-difference Jacobian measured by MediaPipe itself.

    Two extra parameters orbit the camera (yaw, pitch) so the painting's head turn is matched by pose,
    not by bending the face shape."""
    F = len(FACE_PARAMS)
    K = F + 2
    v = np.zeros(K)
    # One-sided parameters (no negative targets) only move in the positive direction.
    lo = np.r_[[0.0 if not neg else -FACE_LIMIT for _, neg in FACE_PARAMS], -1.25, -1.25]
    hi = np.r_[FACE_LIMIT * np.ones(F), 1.25, 1.25]
    reg = np.r_[np.ones(F), 0.0, 0.0] * ridge
    weights = np.array([FACE_W.get(i, 1.0) for i in FACE])
    history, tried = [], []
    centre = None
    for it in range(iters + 1):
        jobs, probes = [], [v.copy()]
        if it < iters:
            for k in range(K):
                p = v.copy()
                p[k] += h if v[k] < hi[k] - h else -h
                probes.append(p)
        for n, p in enumerate(probes):
            set_face(body, p[:F])
            if centre is None:
                centre, pivot_y = face_view(body)
            png = WORK / f"{hero}-loop-{n}.png"
            render(png, centre, 0.34, (768, 768), p[F] * POSE_DEG, p[F + 1] * POSE_DEG, pivot_y)
            jobs.append({"image": str(png), "out": str(WORK / f"{hero}-loop-{n}.json")})
        dets = detect_batch(jobs, hero)
        if not dets[0]["face"]:
            raise RuntimeError(f"{hero}: no face on loop render {it}")
        r0, T = face_residual(dets[0]["face"], ref, weights)
        nme = float(np.linalg.norm(r0.reshape(-1, 2) / np.sqrt(weights)[:, None], axis=1).mean())
        history.append(round(nme, 4))
        tried.append(v.copy())
        print("FACE_LOOP", hero, it, round(nme, 4), np.round(v, 2).tolist(), flush=True)
        if it == iters:
            break
        J = np.zeros((len(r0), K))
        for k in range(K):
            if dets[k + 1]["face"]:
                rk, _ = face_residual(dets[k + 1]["face"], ref, weights, T)
                J[:, k] = (rk - r0) / (probes[k + 1][k] - v[k])
        A = J.T @ J + np.diag(reg ** 2) + 1e-6 * np.eye(K)
        step = np.linalg.solve(A, -(J.T @ r0) - reg ** 2 * v)
        # Trust region: no parameter moves more than 0.35 per round.
        step *= min(1.0, 0.35 / max(1e-9, np.abs(step).max()))
        v = np.clip(v + step, lo, hi)
    best = int(np.argmin(history))
    v = tried[best]
    set_face(body, v[:F])
    pose = {"yaw_deg": round(float(v[F] * POSE_DEG), 2), "pitch_deg": round(float(v[F + 1] * POSE_DEG), 2),
            "pivot_y": pivot_y, "centre": list(centre)}
    return v[:F], history[best], history, pose


# ------------------------------------------------------------------ verification
def similarity(src, dst):
    """Least-squares similarity (scale, rotation, translation) mapping src onto dst."""
    mu_s, mu_d = src.mean(0), dst.mean(0)
    a, b = src - mu_s, dst - mu_d
    u, sig, vt = np.linalg.svd(b.T @ a)
    d = np.sign(np.linalg.det(u @ vt))
    rot = u @ np.diag([1, d]) @ vt
    s = (sig[0] + d * sig[1]) / (a ** 2).sum()
    return lambda p: s * (rot @ (p - mu_s).T).T + mu_d


def verify(hero, body, det, fmap, pose):
    """Render with the arms lowered, re-detect, and score against the painting.

    The face is scored from the painting's head pose (solved yaw/pitch); the body from the front."""
    coords, _ = keyed_coords(body)
    height = coords[:, 2].max() - coords[:, 2].min()
    lower_arms(body)
    bpy.context.view_layer.update()
    body_png = WORK / f"{hero}-fit-body.png"
    render(body_png, (0.0, height / 2), height * 1.12, (768, 1024))
    rdet = detect(body_png, tag=f"{hero}-fit-body")
    groups = joint_groups(body)
    joint = {k: coords[v].mean(axis=0) for k, v in groups.items()}
    eye = (joint["joint-l-eye"] + joint["joint-r-eye"]) / 2
    face_png = WORK / f"{hero}-fit-face.png"
    view = render(face_png, (0.0, eye[2] - 0.03), 0.34, (768, 768), pose["yaw_deg"], pose["pitch_deg"],
                  float(eye[1]) + 0.08)
    fdet = detect(face_png, tag=f"{hero}-fit-face")
    out = {}
    if fdet["face"]:
        ids = FACE
        a = np.array([fdet["face"][i][:2] for i in ids])
        b = np.array([det["face"][i][:2] for i in ids])
        f = similarity(a, b)
        iod = np.linalg.norm(b[ids.index(33)] - b[ids.index(263)])
        err = np.linalg.norm(f(a) - b, axis=1) / iod
        out["face_nme_iod"] = round(float(err.mean()), 4)
        out["face_p90_iod"] = round(float(np.percentile(err, 90)), 4)
        compare_face(hero, det, fdet, f)
    else:
        out["face_nme_iod"] = None
    if rdet["pose"]:
        ids = [0, 11, 12, 23, 24, 25, 26, 27, 28]
        a = np.array([rdet["pose"][i][:2] for i in ids])
        b = np.array([det["pose"][i][:2] for i in ids])
        f = similarity(a, b)
        tall = np.ptp(b[:, 1])
        err = np.linalg.norm(f(a) - b, axis=1) / tall
        out["body_nme_height"] = round(float(err.mean()), 4)
        out["body_max_height"] = round(float(err.max()), 4)
    vids, w = fmap["152"]
    chin = sum(coords[v][2] * a for v, a in zip(vids, w))
    out["head_ratio"] = round(float(height / (coords[:, 2].max() - chin)), 2)
    return out


def compare_face(hero, det, fdet, f):
    """Side-by-side painting crop and render crop, with both landmark sets drawn on the painting."""
    import struct  # noqa: F401  (keeps Blender's image API path; no PIL inside Blender)
    out = WORK / f"{hero}-face-overlay.json"
    pts_r = f(np.array([p[:2] for p in fdet["face"][:468]])).tolist()
    out.write_text(json.dumps({"render_on_ref": pts_r, "ref": [p[:2] for p in det["face"][:468]],
                               "face_box": det["face_box"]}))


# ------------------------------------------------------------------ face rig for the Godot loop
def evaluated_coords(obj):
    bpy.context.view_layer.update()
    m = obj.evaluated_get(bpy.context.evaluated_depsgraph_get()).to_mesh()
    co = np.empty(len(m.vertices) * 3)
    m.vertices.foreach_get("co", co)
    obj.evaluated_get(bpy.context.evaluated_depsgraph_get()).to_mesh_clear()
    return co.reshape(-1, 3)


def flat(name, color, image=None):
    mat = bpy.data.materials.new(name)
    mat.use_nodes = True
    shader = mat.node_tree.nodes["Principled BSDF"]
    lin = [c / 12.92 if c <= 0.04045 else ((c + 0.055) / 1.055) ** 2.4 for c in color]
    shader.inputs["Base Color"].default_value = (*lin, 1.0)
    shader.inputs["Roughness"].default_value = 0.6
    if image:
        tex = mat.node_tree.nodes.new("ShaderNodeTexImage")
        tex.image = bpy.data.images.load(str(image))
        mat.node_tree.links.new(tex.outputs["Color"], shader.inputs["Base Color"])
    return mat


def rebuild(name, src, base, keys, keep=None, material=None):
    """New mesh from `src` topology with positions `base`, shape keys `keys` {name: delta}, optional vertex mask."""
    n = len(src.data.vertices)
    keep = np.ones(n, bool) if keep is None else keep
    remap = -np.ones(n, int)
    remap[keep] = np.arange(keep.sum())
    polys = [p for p in src.data.polygons if keep[list(p.vertices)].all()]
    faces = [[int(remap[i]) for i in p.vertices] for p in polys]
    mesh = bpy.data.meshes.new(name)
    mesh.from_pydata([tuple(v) for v in base[keep]], [], faces)
    if src.data.uv_layers.active:
        uv_src = src.data.uv_layers.active.data
        uv = mesh.uv_layers.new(name="UVMap").data
        k = 0
        for p in polys:
            for li in p.loop_indices:
                uv[k].uv = uv_src[li].uv
                k += 1
    obj = bpy.data.objects.new(name, mesh)
    bpy.context.scene.collection.objects.link(obj)
    obj.shape_key_add(name="Basis")
    for kname, delta in keys.items():
        kb = obj.shape_key_add(name=kname)
        co = (base + delta)[keep]
        kb.data.foreach_set("co", co.ravel())
    if material:
        mesh.materials.append(material)
    for p in mesh.polygons:
        p.use_smooth = True
    return obj


def export_facerig(hero, asset_root):
    """Body, eyes, brows, lashes and hair at the current fit, with one shape key per face-parameter direction.

    Keys 'p<k>' / 'n<k>' add +1 of FACE_PARAMS[k]'s positive / negative targets on top of the fit, assets
    refitted, so Godot can move the face by blend-shape weights alone."""
    spec = HEROES[hero]
    fitd = json.loads((FIT / f"{hero}.json").read_text())
    body = human(fitd["macro"], asset_root, fitd["skin_reference"], spec["brows"])
    lashes = HumanService.add_mhclo_asset(asset_root / "eyelashes/eyelashes01/eyelashes01.mhclo", body,
                                          asset_type="Eyelashes", subdiv_levels=0, material_type="GAMEENGINE")
    HumanService.add_mhclo_asset(asset_root / f"hair/{spec['hair']}/{spec['hair']}.mhclo", body,
                                 asset_type="Hair", subdiv_levels=0, material_type="GAMEENGINE")
    keys = body.data.shape_keys.key_blocks
    for name, value in fitd["targets"].items():
        if name not in keys:
            TargetService.load_target(body, TargetService.target_full_path(name), weight=0.0, name=name)
        keys[name].slider_max = max(1.0, value)
        keys[name].value = value
    HumanService.refit(body)
    assets = [o for o in bpy.data.objects if o.type == "MESH" and o is not body]
    kinds = {}
    for o in assets:
        low = o.name.lower()
        kinds[o] = ("brows" if "brow" in low else "lashes" if "lash" in low
                    else "eyes" if ("low-poly" in low or "high-poly" in low) else "hair")
    body_base, _ = keyed_coords(body)
    asset_base = {o: evaluated_coords(o) for o in assets}
    body_keys, asset_keys = {}, {o: {} for o in assets}
    for k, (pos, neg) in enumerate(FACE_PARAMS):
        for tag, names in (("p", pos), ("n", neg)):
            if not names:
                continue
            for t in names:
                if t not in keys:
                    TargetService.load_target(body, TargetService.target_full_path(t), weight=0.0, name=t)
                keys[t].slider_max = max(2.0, keys[t].slider_max)
                keys[t].value += 1.0
            HumanService.refit(body)
            body_now, _ = keyed_coords(body)
            body_keys[f"{tag}{k}"] = body_now - body_base
            for o in assets:
                asset_keys[o][f"{tag}{k}"] = evaluated_coords(o) - asset_base[o]
            for t in names:
                keys[t].value -= 1.0
    HumanService.refit(body)
    _, inside = body_faces(body)
    mats = {"skin": flat("Skin", spec["skin"]), "hair": flat("Hair", spec["hair_color"]),
            "lashes": flat("Lashes", (0.06, 0.05, 0.05)),
            "eyes": flat("Eyes", (1, 1, 1), asset_root / f"eyes/materials/{spec.get('eyes', 'brown')}_eye.png")}
    out = [rebuild(f"{hero}_body", body, body_base, body_keys, inside, mats["skin"])]
    for o in assets:
        kind = kinds[o]
        out.append(rebuild(f"{hero}_{kind}", o, asset_base[o], asset_keys[o], None,
                           mats["hair" if kind in ("hair", "brows") else kind]))
    for o in [body, *assets]:
        bpy.data.objects.remove(o, do_unlink=True)
    rig_dir = WORK / "facerig"
    rig_dir.mkdir(parents=True, exist_ok=True)
    bpy.ops.object.select_all(action="DESELECT")
    for o in out:
        o.select_set(True)
    bpy.context.view_layer.objects.active = out[0]
    bpy.ops.export_scene.gltf(filepath=str(rig_dir / f"{hero}.glb"), export_format="GLB", use_selection=True,
                              export_morph=True, export_morph_normal=True, export_apply=False)
    print("FACERIG", hero, len(body_keys), "keys", [o.name for o in out])


# ------------------------------------------------------------------ Tripo 3D references
TRIPO_YAWS = (0, 35, -35)


def tripo_views(hero):
    """Render the hero's Tripo model (reference/tripo/<hero>.glb) at TRIPO_YAWS and detect its landmarks.

    Tripo meshes face +X and are 1 m tall; they are turned to face -Y like MPFB. Only the geometry is
    used: Tripo repaints the costume, so colours keep coming from the painting."""
    src = REF / "tripo" / f"{hero}.glb"
    if not src.exists():
        return None
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.ops.import_scene.gltf(filepath=str(src))
    meshes = [o for o in bpy.data.objects if o.type == "MESH"]
    root = bpy.data.objects.new("TripoRoot", None)
    bpy.context.scene.collection.objects.link(root)
    for o in bpy.data.objects:
        if o.parent is None and o is not root:
            o.parent = root
    root.rotation_euler = (0.0, 0.0, -math.pi / 2)
    bpy.context.view_layer.update()
    pts = np.array([tuple(o.matrix_world @ v.co) for o in meshes for v in o.data.vertices])
    lo, hi = pts.min(0), pts.max(0)
    height = hi[2] - lo[2]
    out = {}
    for yaw in TRIPO_YAWS:
        png = WORK / f"tripo-{hero}-{yaw}.png"
        render(png, (float((lo[0] + hi[0]) / 2), float((lo[2] + hi[2]) / 2)), height * 1.08, (1200, 2000),
               yaw, 0.0, float((lo[1] + hi[1]) / 2))
        out[str(yaw)] = detect(png, tag=f"tripo-{hero}-{yaw}")
        print("TRIPO_VIEW", hero, yaw, "face" if out[str(yaw)]["face"] else "NO-FACE")
    (REF / "landmarks" / f"{hero}-tripo.json").write_text(json.dumps(out))
    return out


# ------------------------------------------------------------------ main
def main():
    p = argparse.ArgumentParser()
    p.add_argument("--system-pack", type=Path, required=True)
    p.add_argument("mode", choices=("calibrate", "fit", "facerig", "tripo"))
    p.add_argument("--only", default="")
    args = p.parse_args(sys.argv[sys.argv.index("--") + 1:])
    asset_root = Path(LocationService.get_user_data()).resolve()
    with zipfile.ZipFile(args.system_pack) as z:
        for entry in z.namelist():
            if entry.startswith(("eyes/", "eyebrows/", "eyelashes/", "skins/", "hair/")) and not entry.endswith("/"):
                if not (asset_root / entry).exists():
                    z.extract(entry, asset_root)
    WORK.mkdir(parents=True, exist_ok=True)
    if args.mode == "calibrate":
        calibrate(asset_root)
        return
    if args.mode == "tripo":
        for hero in (args.only.split(",") if args.only else ["detective", "hale", "quer", "lucian"]):
            tripo_views(hero)
        return
    if args.mode == "facerig":
        for hero in (args.only.split(",") if args.only else ["detective", "hale", "quer", "lucian"]):
            export_facerig(hero, asset_root)
        return
    data = json.loads((FIT / "face_map.json").read_text())
    manifest = json.loads((REF / "manifest.json").read_text(encoding="utf-8"))
    for hero in HEROES:
        if hero not in manifest or (args.only and hero not in args.only.split(",")):
            continue
        fit_hero(hero, asset_root, data["face"], data["pose_bias"], manifest)


if __name__ == "__main__":
    main()
