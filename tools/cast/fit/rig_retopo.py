"""Turn each hero's retopologised Tripo mesh into a game GLB: rig, weights, UVs, painted texture, motion.

    blender -b --python tools/cast/fit/rig_retopo.py -- --system-pack <system_cc0.zip> --motion <UAL glb> --hero quer

1. Skeleton: the hero's fitted MPFB body (fit/<hero>.json) with its Mixamo rig, scaled to stature.
2. Registration: front and side renders of both meshes go through MediaPipe; the retopo mesh is scaled and
   moved so its shoulders, hips, knees and ankles sit on the body's.
3. Pose: the rig's arms and legs are turned to the retopo mesh's joint directions and that pose becomes the
   rest pose (body and rig), so the two overlap limb for limb.
4. Weights: transferred from the posed body (nearest face, interpolated), smoothed, normalised, 4 bones max.
5. Texture: smart-UV, then the painting is projected from the front. Body pixels follow a similarity on the
   pose landmarks, the face a piecewise-affine warp on the 468 face landmarks. Only surfaces facing the
   viewer and not occluded sample the painting; everything else is filled from its neighbours over the
   mesh, so ink outlines and background never land on sides or backs.
6. Motion: the same UAL clips as build_heroes.py, retargeted onto the new rest pose; GLB exported to
   assets/characters/heroes/<hero>.glb with a receipt entry.
"""
import argparse
import json
import math
import sys
from collections import deque
from pathlib import Path

import bpy
import numpy as np
from mathutils import Matrix, Vector
from mathutils.bvhtree import BVHTree
from mathutils.geometry import delaunay_2d_cdt

FIT = Path(__file__).resolve().parent
sys.path.append(str(FIT.parent))
sys.path.append(str(FIT))
import build_heroes as B  # noqa: E402
from bl_ext.user_default.mpfb.services.humanservice import HumanService  # noqa: E402
from bl_ext.user_default.mpfb.services.targetservice import TargetService  # noqa: E402
from face_paint import bilinear, dist_to_poly, load_painting, point_in_poly, warp  # noqa: E402
from face_params import OVAL  # noqa: E402
from fit_heroes import WORK, detect, render, similarity  # noqa: E402

ROOT = FIT.parents[2]
REF = FIT.parent / "reference"
RETOPO = WORK / "retopo"
OUT = ROOT / "assets" / "characters" / "heroes"
REG = [11, 12, 23, 24, 25, 26, 27, 28]
LIMBS = [("LeftArm", 11, 13), ("LeftForeArm", 13, 15), ("RightArm", 12, 14), ("RightForeArm", 14, 16),
         ("LeftUpLeg", 23, 25), ("LeftLeg", 25, 27), ("RightUpLeg", 24, 26), ("RightLeg", 26, 28)]
PAIR = {11: 12, 12: 11, 13: 14, 14: 13, 15: 16, 16: 15, 23: 24, 24: 23, 25: 26, 26: 25, 27: 28, 28: 27}


def activate(obj):
    bpy.ops.object.select_all(action="DESELECT")
    obj.select_set(True)
    bpy.context.view_layer.objects.active = obj


# ------------------------------------------------------------------ inputs
def make_body(hero, height=None):
    fitd = json.loads((FIT / f"{hero}.json").read_text())
    spec = B.HEROES[hero]
    macro = TargetService.get_default_macro_info_dict()
    macro.update(fitd["macro"])
    body = HumanService.create_human(macro_detail_dict=macro, feet_on_ground=False)
    keys = None
    for name, value in fitd["targets"].items():
        TargetService.load_target(body, TargetService.target_full_path(name), weight=value, name=name)
        keys = body.data.shape_keys.key_blocks
        keys[name].slider_max = max(1.0, value)
        keys[name].value = value
    B.fit(body, height or spec["height"], None)
    rig = HumanService.add_builtin_rig(body, "mixamo")
    activate(body)
    TargetService.bake_targets(body)
    body.name, rig.name = f"{hero}_mpfb", f"{hero}_rig"
    return body, rig


def load_retopo(hero):
    with bpy.data.libraries.load(str(RETOPO / f"{hero}.blend")) as (src, dst):
        dst.objects = [n for n in src.objects if n == f"{hero}_retopo"]
    obj = dst.objects[0]
    bpy.context.scene.collection.objects.link(obj)
    obj.modifiers.clear()
    for layer in list(obj.data.uv_layers):
        obj.data.uv_layers.remove(layer)
    obj.data.materials.clear()
    # QuadriFlow can hand back inward-facing normals; the projection and the toon light need them outward.
    activate(obj)
    bpy.ops.object.mode_set(mode="EDIT")
    bpy.ops.mesh.select_all(action="SELECT")
    bpy.ops.mesh.normals_make_consistent(inside=False)
    bpy.ops.object.mode_set(mode="OBJECT")
    return obj


# ------------------------------------------------------------------ landmarks in world space
def solo(obj):
    for o in bpy.data.objects:
        if o.type == "MESH":
            o.hide_render = o is not obj


def bounds(obj):
    deps = bpy.context.evaluated_depsgraph_get()
    m = obj.evaluated_get(deps).to_mesh()
    co = np.array([tuple(obj.matrix_world @ v.co) for v in m.vertices])
    obj.evaluated_get(deps).to_mesh_clear()
    return co.min(0), co.max(0)


def view_landmarks(obj, tag):
    """Front and side MediaPipe pose (and front face) of one object, mapped back to world coordinates."""
    solo(obj)
    lo, hi = bounds(obj)
    h = hi[2] - lo[2]
    cz = (lo[2] + hi[2]) / 2
    res = (1100, 2000)
    unit = h * 1.1 / max(res)
    out = {"front": {}, "side": {}, "front_view": {"centre": [0.0, cz], "size": h * 1.1, "res": list(res)}}
    for name, yaw in (("front", 0.0), ("side", 90.0)):
        png = WORK / "rig" / f"{tag}-{name}.png"
        png.parent.mkdir(parents=True, exist_ok=True)
        render(png, (0.0, cz), h * 1.1, res, yaw, 0.0, 0.0)
        det = detect(png, tag=f"rig/{tag}-{name}")
        out[name + "_det"] = det
        if not det["pose"]:
            continue
        for i, (px, py, vis) in enumerate(det["pose"]):
            a = (px - res[0] / 2) * unit
            z = cz - (py - res[1] / 2) * unit
            # Front: image x is world +X. Side camera sits on +X looking -X: image x is world +Y.
            out[name][i] = (a, z, vis)
    return out


def register(retopo, body, hero):
    """Scale and move the retopo mesh so its pose landmarks fall on the body's (front x/z, side y)."""
    lb = view_landmarks(body, f"{hero}-body")
    lr = view_landmarks(retopo, f"{hero}-retopo")
    ids = [i for i in REG if i in lb["front"] and i in lr["front"]]
    a = np.array([[lr["front"][i][0], lr["front"][i][1]] for i in ids])
    b = np.array([[lb["front"][i][0], lb["front"][i][1]] for i in ids])
    ca, cb = a.mean(0), b.mean(0)
    s = float(np.sqrt(((b - cb) ** 2).sum() / ((a - ca) ** 2).sum()))
    t = cb - s * ca
    side = [i for i in (11, 12, 23, 24) if i in lb["side"] and i in lr["side"]]
    ty = float(np.mean([lb["side"][i][0] - s * lr["side"][i][0] for i in side])) if side else 0.0
    retopo.matrix_world = Matrix.Translation((t[0], ty, t[1])) @ Matrix.Scale(s, 4) @ retopo.matrix_world
    activate(retopo)
    bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
    # Retopo joints after registration: x/z from the front view, depth from the side view (pair-averaged:
    # MediaPipe cannot tell the near and far limb apart in profile).
    joints = {}
    for i in range(11, 29):
        if i not in lr["front"]:
            continue
        x, z = s * lr["front"][i][0] + t[0], s * lr["front"][i][1] + t[1]
        ys = [lr["side"][k][0] for k in (i, PAIR.get(i, i)) if k in lr["side"]]
        y = s * float(np.mean(ys)) + ty if ys else 0.0
        joints[i] = Vector((x, y, z))
    return {"scale": round(s, 4), "offset": [round(float(t[0]), 4), round(ty, 4), round(float(t[1]), 4)],
            "joints": joints, "landmarks": lr}


def pose_to(rig, body, joints):
    """Point each limb bone at the retopo joint directions, then make that pose the rest pose."""
    bpy.context.view_layer.update()
    for name, a, b in LIMBS:
        if a not in joints or b not in joints:
            continue
        pb = next(p for p in rig.pose.bones if p.name.endswith(":" + name))
        head, tail = rig.matrix_world @ pb.head, rig.matrix_world @ pb.tail
        cur = (tail - head).normalized()
        want = (joints[b] - joints[a]).normalized()
        rot = cur.rotation_difference(want).to_matrix().to_4x4()
        m = pb.matrix.copy()
        loc = m.to_translation()
        pb.matrix = Matrix.Translation(loc) @ rot @ Matrix.Translation(-loc) @ m
        bpy.context.view_layer.update()
    activate(body)
    mod = next(m for m in body.modifiers if m.type == "ARMATURE")
    bpy.ops.object.modifier_apply(modifier=mod.name)
    activate(rig)
    bpy.ops.object.mode_set(mode="POSE")
    bpy.ops.pose.select_all(action="SELECT")
    bpy.ops.pose.armature_apply(selected=False)
    bpy.ops.object.mode_set(mode="OBJECT")


def smooth_weights(obj, rounds=12, limit=4):
    """Laplacian-smooth all bone weights over the mesh (coat skirts, brims and capes then bend as a whole
    instead of tearing at bone borders), keep the `limit` largest per vertex and normalise."""
    mesh = obj.data
    n, groups = len(mesh.vertices), list(obj.vertex_groups)
    W = np.zeros((n, len(groups)))
    for v in mesh.vertices:
        for g in v.groups:
            W[v.index, g.group] = g.weight
    a = np.array([e.vertices[0] for e in mesh.edges])
    b = np.array([e.vertices[1] for e in mesh.edges])
    deg = np.bincount(a, minlength=n) + np.bincount(b, minlength=n)
    for _ in range(rounds):
        acc = np.zeros_like(W)
        np.add.at(acc, a, W[b])
        np.add.at(acc, b, W[a])
        W = 0.5 * W + 0.5 * acc / np.maximum(deg, 1)[:, None]
    if W.shape[1] > limit:
        cut = np.sort(W, axis=1)[:, -limit][:, None]
        W[W < cut] = 0.0
    W /= np.maximum(W.sum(1, keepdims=True), 1e-9)
    for gi, g in enumerate(groups):
        g.remove(list(range(n)))
        nz = np.nonzero(W[:, gi] > 1e-4)[0]
        for i in nz:
            g.add([int(i)], float(W[i, gi]), "REPLACE")


def transfer_weights(retopo, body, rig):
    activate(retopo)
    dt = retopo.modifiers.new("Weights", "DATA_TRANSFER")
    dt.object = body
    dt.use_vert_data = True
    dt.data_types_verts = {"VGROUP_WEIGHTS"}
    dt.vert_mapping = "POLYINTERP_NEAREST"
    dt.layers_vgroup_select_src = "ALL"
    dt.layers_vgroup_select_dst = "NAME"
    bpy.ops.object.datalayout_transfer(modifier=dt.name)
    bpy.ops.object.modifier_apply(modifier=dt.name)
    bones = {b.name for b in rig.data.bones}
    for g in list(retopo.vertex_groups):
        if g.name not in bones:
            retopo.vertex_groups.remove(g)
    smooth_weights(retopo, rounds=12, limit=4)
    retopo.parent = rig
    retopo.matrix_parent_inverse = rig.matrix_world.inverted()
    arm = retopo.modifiers.new("Armature", "ARMATURE")
    arm.object = rig
    return len(retopo.vertex_groups)


# ------------------------------------------------------------------ texture
def projection(retopo, hero, lr, res=2048):
    """Front projection of the painting into a smart-UV texture (see module docstring)."""
    activate(retopo)
    bpy.ops.object.mode_set(mode="EDIT")
    bpy.ops.mesh.select_all(action="SELECT")
    bpy.ops.uv.smart_project(angle_limit=math.radians(66), island_margin=0.002)
    bpy.ops.object.mode_set(mode="OBJECT")
    man = json.loads((REF / "manifest.json").read_text(encoding="utf-8"))[hero]
    ref = json.loads((REF / "landmarks" / f"{hero}.json").read_text())
    painting, pimg = load_painting(REF / man["image"])
    mesh = retopo.data
    n = len(mesh.vertices)
    co = np.empty(n * 3)
    mesh.vertices.foreach_get("co", co)
    co = co.reshape(-1, 3)
    nrm = np.empty(n * 3)
    mesh.vertices.foreach_get("normal", nrm)
    nrm = nrm.reshape(-1, 3)
    # The registration moved the mesh after its landmark renders: render it again from the front.
    view = view_landmarks(retopo, f"{hero}-final")
    det, fv = view["front_det"], view["front_view"]
    unit = fv["size"] / max(fv["res"])
    if not det["face"] and det["pose"]:
        det["face"] = closeup_face(retopo, hero, det, fv)
    mask = figure_mask(hero)
    rpx = np.c_[fv["res"][0] / 2 + co[:, 0] / unit, fv["res"][1] / 2 - (co[:, 2] - fv["centre"][1]) / unit]
    ids = [i for i in (0, 2, 5, 7, 8, 11, 12, 13, 14, 15, 16, 23, 24, 25, 26, 27, 28)
           if det["pose"] and ref["pose"] and det["pose"][i][2] > 0.5]
    body_map = similarity(np.array([det["pose"][i][:2] for i in ids]), np.array([ref["pose"][i][:2] for i in ids]))
    pp = body_map(rpx)
    if det["face"] and ref["face"]:
        src = np.array([p[:2] for p in det["face"][:468]])
        dst = np.array([p[:2] for p in ref["face"][:468]])
        tri = delaunay_2d_cdt([Vector(p) for p in src], [], [], 0, 1e-9)
        orig = tri[3]
        idx = np.array([[orig[k][0] for k in f] for f in tri[2] if len(f) == 3 and all(orig[k] for k in f)])
        oval = src[OVAL]
        width = np.ptp(oval[:, 0])
        inside = point_in_poly(rpx, oval) & (nrm[:, 1] < 0)
        face_pp = np.full((n, 2), np.nan)
        face_pp[inside] = warp(src[idx], dst[idx], rpx[inside])
        wf = np.zeros(n)
        wf[inside] = np.clip(dist_to_poly(rpx[inside], oval) / (0.12 * width), 0, 1)
        ok = ~np.isnan(face_pp[:, 0])
        pp[ok] = pp[ok] * (1 - wf[ok, None]) + face_pp[ok] * wf[ok, None]
    # Visibility: facing the viewer (-Y) and nothing of the mesh in front.
    tree = BVHTree.FromPolygons([Vector(c) for c in co], [tuple(p.vertices) for p in mesh.polygons])
    visible = np.zeros(n, bool)
    for i in np.nonzero(nrm[:, 1] < -0.35)[0]:
        hit = tree.ray_cast(Vector(co[i] + nrm[i] * 0.003), Vector((0, -1, 0)), 5.0)
        visible[i] = hit[0] is None
    h, w = painting.shape[:2]
    visible &= (pp[:, 0] > 1) & (pp[:, 0] < w - 2) & (pp[:, 1] > 1) & (pp[:, 1] < h - 2)
    if mask is not None:
        mx = np.clip(pp[:, 0].astype(int), 0, w - 1)
        my = np.clip(pp[:, 1].astype(int), 0, h - 1)
        visible &= mask[my, mx] > 0.5
    color = np.zeros((n, 3))
    color[visible] = bilinear(painting, pp[visible, 0], pp[visible, 1])
    # Fill sides, backs and occluded parts from painted neighbours, ring by ring.
    nbrs = [[] for _ in range(n)]
    for e in mesh.edges:
        a, b = e.vertices
        nbrs[a].append(b)
        nbrs[b].append(a)
    known = visible.copy()
    frontier = deque(i for i in range(n) if not known[i] and any(known[j] for j in nbrs[i]))
    while frontier:
        nxt = []
        batch = list(dict.fromkeys(frontier))
        frontier.clear()
        for i in batch:
            if known[i]:
                continue
            src = [j for j in nbrs[i] if known[j]]
            color[i] = np.mean(color[src], axis=0)
            nxt.append(i)
        for i in nxt:
            known[i] = True
        for i in nxt:
            for j in nbrs[i]:
                if not known[j]:
                    frontier.append(j)
    image = np.zeros((res, res, 4), np.float32)
    image[..., :3] = color[visible].mean(0) if visible.any() else 0.5
    image[..., 3] = 1.0
    mesh.calc_loop_triangles()
    uv = mesh.uv_layers.active.data
    for lt in mesh.loop_triangles:
        tv = list(lt.vertices)
        tuv = np.array([uv[k].uv for k in lt.loops]) * res
        lo = np.floor(tuv.min(0)).astype(int) - 1
        hi = np.ceil(tuv.max(0)).astype(int) + 1
        xs, ys = np.meshgrid(np.arange(lo[0], hi[0] + 1), np.arange(lo[1], hi[1] + 1))
        pts = np.stack([xs.ravel() + 0.5, ys.ravel() + 0.5], 1)
        m = np.array([tuv[1] - tuv[0], tuv[2] - tuv[0]]).T
        if abs(np.linalg.det(m)) < 1e-9:
            continue
        bc = (pts - tuv[0]) @ np.linalg.inv(m).T
        wts = np.c_[1 - bc.sum(1), bc]
        keep = (wts >= -0.08).all(1)
        if not keep.any():
            continue
        wts = np.clip(wts[keep], 0, None)
        wts /= wts.sum(1, keepdims=True)
        px = np.clip((pts[keep] - 0.5).astype(int), 0, res - 1)
        if visible[tv].all():
            q = wts @ pp[tv]
            col = bilinear(painting, q[:, 0], q[:, 1])
        else:
            col = wts @ color[tv]
        image[px[:, 1], px[:, 0], :3] = col
    img = bpy.data.images.new(f"{hero}_paint", res, res)
    img.pixels.foreach_set(image.ravel())
    png = WORK / "rig" / f"{hero}-paint.png"
    img.filepath_raw, img.file_format = str(png), "PNG"
    img.save()
    img.pack()
    bpy.data.images.remove(pimg)
    mat = bpy.data.materials.new(f"{hero}_painted")
    mat.use_nodes = True
    tex = mat.node_tree.nodes.new("ShaderNodeTexImage")
    tex.image = img
    shader = mat.node_tree.nodes["Principled BSDF"]
    mat.node_tree.links.new(tex.outputs["Color"], shader.inputs["Base Color"])
    shader.inputs["Roughness"].default_value = 0.8
    mesh.materials.append(mat)
    for p in mesh.polygons:
        p.use_smooth = True
    return {"visible_vertices": int(visible.sum()), "vertices": n, "face_warp": bool(det["face"]),
            "figure_mask": mask is not None}


def closeup_face(obj, hero, det, fv):
    """The full-body render's face can be too small or hat-shaded: re-detect on a close-up around the nose
    and map the 478 points back into full-body render pixels."""
    unit = fv["size"] / max(fv["res"])
    nx, ny = det["pose"][0][:2]
    cx = (nx - fv["res"][0] / 2) * unit
    cz = fv["centre"][1] - (ny - fv["res"][1] / 2) * unit
    size, res = 0.36, 1024
    png = WORK / "rig" / f"{hero}-final-face.png"
    solo(obj)
    render(png, (cx, cz), size, (res, res), 0.0, 0.0, 0.0)
    close = detect(png, tag=f"rig/{hero}-final-face")
    if not close["face"]:
        print("NO_FACE_CLOSEUP", hero)
        return None
    cu = size / res
    pts = []
    for px, py, pz in close["face"]:
        x = cx + (px - res / 2) * cu
        z = cz - (py - res / 2) * cu
        pts.append([fv["res"][0] / 2 + x / unit, fv["res"][1] / 2 - (z - fv["centre"][1]) / unit, pz])
    return pts


def figure_mask(hero):
    """GrabCut figure mask of the painting seeded by this mesh's silhouette (figure_mask.py, MediaPipe venv)."""
    import os
    import subprocess
    from fit_heroes import VENV
    out = WORK / "rig" / f"{hero}-mask.png"
    r = subprocess.run([str(VENV), str(FIT / "figure_mask.py"), "--hero", hero,
                        "--render", str(WORK / "rig" / f"{hero}-final-front.png"),
                        "--det", str(WORK / "rig" / f"{hero}-final-front.json"), "--out", str(out)],
                       capture_output=True, text=True, env={k: v for k, v in os.environ.items()
                                                             if k not in ("PYTHONHOME", "PYTHONPATH")})
    if r.returncode or not out.exists():
        print("MASK_FAILED", hero, r.stderr[-800:])
        return None
    img = bpy.data.images.load(str(out))
    w, h = img.size
    px = np.empty(w * h * 4, np.float32)
    img.pixels.foreach_get(px)
    bpy.data.images.remove(img)
    return px.reshape(h, w, 4)[::-1, :, 0].copy()


# ------------------------------------------------------------------ main
def main():
    p = argparse.ArgumentParser()
    p.add_argument("--system-pack", type=Path, required=True)
    p.add_argument("--motion", type=Path, required=True)
    p.add_argument("--hero", required=True)
    p.add_argument("--out", type=Path, default=OUT)
    a = p.parse_args(sys.argv[sys.argv.index("--") + 1:])
    hero = a.hero
    # Pass 1 measures how the fitted skeleton compares with the retopo mesh (kept at its designed stature);
    # pass 2 rebuilds the skeleton at the matching stature, so registration only has to translate.
    bpy.ops.wm.read_factory_settings(use_empty=True)
    body, rig = make_body(hero)
    retopo = load_retopo(hero)
    first = register(retopo, body, hero)
    stature = B.HEROES[hero]["height"] / first["scale"]
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.context.scene.render.fps = 24
    body, rig = make_body(hero, stature)
    retopo = load_retopo(hero)
    reg = register(retopo, body, hero)
    reg["skeleton_stature"] = round(stature, 4)
    pose_to(rig, body, reg["joints"])
    groups = transfer_weights(retopo, body, rig)
    paint = projection(retopo, hero, reg["landmarks"])
    bpy.data.objects.remove(body, do_unlink=True)
    retopo.name = retopo.data.name = f"{hero}_body"
    for o in bpy.data.objects:
        o.hide_render = False
    clips = dict(B.CLIPS)
    clips.update(B.OVERRIDES.get(hero, {}))
    src = B.load_motion(a.motion)
    made = B.retarget(src, rig, clips, 24)
    bpy.data.objects.remove(src, do_unlink=True)
    for act in list(bpy.data.actions):
        if act.name not in clips:
            bpy.data.actions.remove(act)
    path = a.out / f"{hero}.glb"
    B.export(path, rig, [retopo])
    receipt_path = a.out / "receipt.json"
    receipt = json.loads(receipt_path.read_text()) if receipt_path.exists() else {}
    lo, hi = bounds(retopo)
    receipt[hero] = {"id": hero, "source": f"tools/cast/reference/tripo/{hero}.glb (retopo)",
                     "registration": {"scale": reg["scale"], "offset": reg["offset"],
                                      "skeleton_stature": reg["skeleton_stature"]},
                     "weight_groups": groups, "paint": paint, "clips": made,
                     "height_m": round(float(hi[2] - lo[2]), 4), "triangles": sum(len(p.vertices) - 2 for p in retopo.data.polygons),
                     "glb_bytes": path.stat().st_size}
    receipt_path.write_text(json.dumps(receipt, indent=1) + "\n")
    print("RIG_PASS", hero, json.dumps({k: receipt[hero][k] for k in ("registration", "paint", "height_m", "triangles")}))


if __name__ == "__main__":
    main()
