"""Build a hero GLB from Tripo's part-segmented model: parts kept apart, face made symmetric, MPFB rig.

    .runtime/cast-pass/blender.sh --python tools/cast/fit/build_tripo_parts.py -- \
        --motion <UAL Godot Standard.glb> --hero quer [--out assets/characters/heroes]

Source: tools/cast/reference/tripo-parts/<hero>.glb (Tripo export, one mesh per garment/prop part, no rig).
Colour reference: tools/cast/reference/sheets/<hero>.jpg (front character sheet) and its MediaPipe
landmarks (reference/landmarks/<hero>-sheet.json).

1. Parts: each part is cleaned on its own (merge duplicates, drop loose/degenerate geometry, outward
   normals) and the parts are joined without ever welding across them, so coat, sleeves, hands, bag and
   lute stay separate surfaces. A per-vertex `part` index is kept for weights and texture.
2. Registration: front/side MediaPipe pose on the model and on the hero's fitted MPFB body; the model is
   scaled onto the body and the rig's limbs are turned onto the model's joints (rig_retopo).
3. Face: the head part is snapped to its own mirror image about the face's symmetry plane, and paired
   face parts (eyes, brows) are moved to mirror positions, so nose and eyes sit straight.
4. Weights: every vertex casts a ray inward (against its normal) onto the posed MPFB body and takes the
   hit triangle's weights, so a sleeve's inner side gets the arm and the coat panel beside it the torso.
   Each part is then classed (head, rigid, hand, arm, leg, coat, torso) from those weights; a class limits
   which bones it may use, coat skirts lean on the hips, props listed in RIGID ride one bone, and weights
   are smoothed inside the part only.
5. Texture: tools/cast/fit/parts_paint.py recolours Tripo's atlas in place. Each part's texels are split
   into colour clusters; every cluster takes the median sheet colour seen by its front-visible vertices
   (clusters seen only from behind borrow from their nearest seen neighbours), so colours are flat like
   the sheet. The face is drawn from the sheet through a 468-landmark warp.
6. Motion: UAL clips retargeted (limbs by direction, spine/clavicles/neck/head by delta), GLB exported.
"""
import argparse
import json
import math
import os
import subprocess
import sys
from pathlib import Path

import bmesh
import bpy
import numpy as np
from mathutils import Matrix, Vector
from mathutils.bvhtree import BVHTree
from mathutils.kdtree import KDTree

FIT = Path(__file__).resolve().parent
sys.path.append(str(FIT.parent))
sys.path.append(str(FIT))
import build_heroes as B  # noqa: E402
import rig_retopo as R  # noqa: E402
from fit_heroes import VENV, WORK  # noqa: E402

ROOT = FIT.parents[2]
REF = FIT.parent / "reference"
PARTS = REF / "tripo-parts"
OUT = ROOT / "assets" / "characters" / "heroes"
STAGE = WORK / "parts"

# Props that must move as one piece with one bone (Tripo part names without the "tripo_part_"/"_Clone").
RIGID = {
    "detective": {"Hips": ["p9", "p31", "p46", "p57", "p60", "p61", "p62", "p68", "p69", "p70", "p75"]},
    "hale": {"Hips": ["p5", "p11", "p32", "p35", "p38", "p40"]},
    "quer": {},
    "lucian": {"Spine2": ["p19", "p40", "p44", "p45", "p46", "p47", "p50", "p58", "p59", "p5", "p60", "p61",
                          "p62", "p63", "p65", "p66", "p67", "p68", "p69", "p70", "p71", "p72", "p73", "p77",
                          "p78", "p79", "p83", "p84", "p85", "p87", "p88", "p89", "p90", "p91", "p93", "p95",
                          "p96"]},
}
# Drapes over the shoulders: trunk bones only (and the clavicle it hangs from), smoothed hard.
CAPE = {"lucian": ["p9"]}
# Hips and legs copy UAL by direction (they must agree, or skirts sink into the seat); spine, clavicles, neck and head copy UAL's motion as a delta from rest (see build_heroes.retarget).
DELTA = ("Spine", "Spine1", "Spine2", "Neck", "Head", "LeftShoulder", "RightShoulder")
# Lucian idles like the others; the talking loop stays on `signal`.
CLIP_FIX = {"lucian": {"idle": "Idle_Loop"}}


def activate(obj):
    bpy.ops.object.select_all(action="DESELECT")
    obj.select_set(True)
    bpy.context.view_layer.objects.active = obj


def short(name):
    return name.replace("tripo_part_", "p").replace("_Clone", "").split(".")[0]


# ------------------------------------------------------------------ 1. parts
def load_parts(hero, height):
    before = set(bpy.data.objects)
    bpy.ops.import_scene.gltf(filepath=str(PARTS / f"{hero}.glb"))
    new = [o for o in bpy.data.objects if o not in before]
    meshes = [o for o in new if o.type == "MESH"]
    for o in meshes:
        mw = o.matrix_world.copy()
        o.parent = None
        o.matrix_world = mw
    for o in new:
        if o.type != "MESH":
            bpy.data.objects.remove(o, do_unlink=True)
    meshes.sort(key=lambda o: o.name)
    names, removed = [], 0
    for o in meshes:
        activate(o)
        bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
        bm = bmesh.new()
        bm.from_mesh(o.data)
        n0 = len(bm.verts)
        bmesh.ops.remove_doubles(bm, verts=bm.verts, dist=2e-5)
        bmesh.ops.dissolve_degenerate(bm, edges=bm.edges, dist=1e-6)
        loose = [v for v in bm.verts if not v.link_faces]
        bmesh.ops.delete(bm, geom=loose, context="VERTS")
        # Crumbs: islands of a handful of faces inside a part.
        seen, crumbs = set(), []
        for f in bm.faces:
            if f.index in seen:
                continue
            island, stack = [], [f]
            seen.add(f.index)
            while stack:
                g = stack.pop()
                island.append(g)
                for e in g.edges:
                    for h in e.link_faces:
                        if h.index not in seen:
                            seen.add(h.index)
                            stack.append(h)
            if len(island) < 6 and len(island) < len(bm.faces):
                crumbs += island
        if crumbs:
            bmesh.ops.delete(bm, geom=list(set(crumbs)), context="FACES")
        bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
        removed += n0 - len(bm.verts)
        bm.to_mesh(o.data)
        bm.free()
        attr = o.data.attributes.new("part", "INT", "POINT")
        attr.data.foreach_set("value", [len(names)] * len(o.data.vertices))
        names.append(short(o.name))
    activate(meshes[0])
    for o in meshes:
        o.select_set(True)
    bpy.ops.object.join()
    obj = bpy.context.active_object
    obj.name = obj.data.name = f"{hero}_body"
    # Tripo: +Y up in glTF = +Z here, character faces +X. Turn to face -Y, feet on z=0, centred, to height.
    co = np.empty(len(obj.data.vertices) * 3)
    obj.data.vertices.foreach_get("co", co)
    co = co.reshape(-1, 3)
    lo, hi = co.min(0), co.max(0)
    s = height / (hi[2] - lo[2])
    m = Matrix.Scale(s, 4) @ Matrix.Rotation(-math.pi / 2, 4, "Z") @ \
        Matrix.Translation((-(lo[0] + hi[0]) / 2, -(lo[1] + hi[1]) / 2, -lo[2]))
    obj.data.transform(m)
    obj.data.update()
    for p in obj.data.polygons:
        p.use_smooth = True
    return obj, names, removed


def part_index(obj):
    a = np.empty(len(obj.data.vertices), np.int32)
    obj.data.attributes["part"].data.foreach_get("value", a)
    return a


def coords(obj):
    co = np.empty(len(obj.data.vertices) * 3)
    obj.data.vertices.foreach_get("co", co)
    return co.reshape(-1, 3)


def normals(obj):
    nrm = np.empty(len(obj.data.vertices) * 3)
    obj.data.vertices.foreach_get("normal", nrm)
    return nrm.reshape(-1, 3)


def set_coords(obj, co):
    obj.data.vertices.foreach_set("co", co.ravel())
    obj.data.update()


def base_image(obj):
    for mat in obj.data.materials:
        if not mat or not mat.use_nodes:
            continue
        bsdf = mat.node_tree.nodes.get("Principled BSDF")
        if bsdf and bsdf.inputs["Base Color"].is_linked:
            node = bsdf.inputs["Base Color"].links[0].from_node
            if node.type == "TEX_IMAGE":
                return node.image
    raise RuntimeError("no base colour image")


# ------------------------------------------------------------------ 2. registration
def register(obj, body, hero):
    """Scale the joined parts onto the body from the heights of shoulders, hips, knees and ankles only
    (capes, lutes and sleeves make MediaPipe's widths unreliable), put the soles on the body's soles,
    centre x on the landmarks and depth from the side view. Returns joints as rig_retopo.register."""
    lb = R.view_landmarks(body, f"{hero}-body")
    lr = R.view_landmarks(obj, f"{hero}-parts")
    ids = [i for i in R.REG if i in lb["front"] and i in lr["front"]]
    zr = np.array([lr["front"][i][1] for i in ids])
    zb = np.array([lb["front"][i][1] for i in ids])
    s = float(((zr - zr.mean()) * (zb - zb.mean())).sum() / ((zr - zr.mean()) ** 2).sum())
    blo, _ = R.bounds(body)
    olo, _ = R.bounds(obj)
    tz = float(blo[2] - s * olo[2])
    tx = float(np.mean([lb["front"][i][0] - s * lr["front"][i][0] for i in ids]))
    side = [i for i in (11, 12, 23, 24) if i in lb["side"] and i in lr["side"]]
    ty = float(np.mean([lb["side"][i][0] - s * lr["side"][i][0] for i in side])) if side else 0.0
    obj.matrix_world = Matrix.Translation((tx, ty, tz)) @ Matrix.Scale(s, 4) @ obj.matrix_world
    activate(obj)
    bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
    joints = {}
    for i in range(11, 29):
        if i not in lr["front"]:
            continue
        x, z = s * lr["front"][i][0] + tx, s * lr["front"][i][1] + tz
        ys = [lr["side"][k][0] for k in (i, R.PAIR.get(i, i)) if k in lr["side"]]
        y = s * float(np.mean(ys)) + ty if ys else 0.0
        joints[i] = Vector((x, y, z))
    # Skull base: where the body's Head bone sits relative to its ears, carried over to the model's ears.
    head = None
    ears = [i for i in (7, 8) if i in lb["front"] and i in lr["front"]]
    if ears:
        rig = body.parent or next(o for o in bpy.data.objects if o.type == "ARMATURE")
        hb = next(b for b in rig.data.bones if b.name.endswith(":Head"))
        hpos = rig.matrix_world @ hb.head_local
        ex_b = np.mean([lb["front"][i][0] for i in ears]); ez_b = np.mean([lb["front"][i][1] for i in ears])
        ex_r = np.mean([s * lr["front"][i][0] + tx for i in ears]); ez_r = np.mean([s * lr["front"][i][1] + tz for i in ears])
        sb = [lb["side"][i][0] for i in ears if i in lb["side"]]
        sr = [s * lr["side"][i][0] + ty for i in ears if i in lr["side"]]
        dy = (np.mean(sr) - np.mean(sb)) if sb and sr else 0.0
        head = Vector((hpos.x + (ex_r - ex_b), hpos.y + dy, hpos.z + (ez_r - ez_b)))
    return {"scale": round(s, 4), "offset": [round(tx, 4), round(ty, 4), round(tz, 4)],
            "joints": joints, "landmarks": lr, "skull_base": head}


def pose_to(rig, body, joints, skull_base):
    """rig_retopo.pose_to plus the neck: the Neck bone is turned and stretched so the Head bone starts at
    the model's skull base (Tripo necks run longer than MPFB's), before the pose becomes the rest pose."""
    if skull_base is not None:
        bpy.context.view_layer.update()
        pb = next(p for p in rig.pose.bones if p.name.endswith(":Neck"))
        head = rig.matrix_world @ pb.head
        tail = rig.matrix_world @ pb.tail
        want = skull_base - head
        rot = (tail - head).normalized().rotation_difference(want.normalized()).to_matrix().to_4x4()
        m = pb.matrix.copy()
        loc = m.to_translation()
        pb.matrix = Matrix.Translation(loc) @ rot @ Matrix.Translation(-loc) @ m
        bpy.context.view_layer.update()
        pb.scale = (1.0, want.length / (tail - head).length, 1.0)
        bpy.context.view_layer.update()
        hb = next(p for p in rig.pose.bones if p.name.endswith(":Head"))
        hb.scale = (1.0, (tail - head).length / want.length, 1.0)  # keep the head its own size
        bpy.context.view_layer.update()
    R.pose_to(rig, body, joints)


# ------------------------------------------------------------------ 3. face symmetry
def head_part(obj, parts, joints_face):
    """The part a ray from the front meets at the nose."""
    nose = joints_face
    mesh = obj.data
    tree = BVHTree.FromPolygons([tuple(v.co) for v in mesh.vertices], [tuple(p.vertices) for p in mesh.polygons])
    hit = tree.ray_cast(Vector((nose[0], -3.0, nose[1])), Vector((0, 1, 0)), 6.0)
    if hit[2] is None:
        return None
    return int(parts[mesh.polygons[hit[2]].vertices[0]])


def symmetrize_face(obj, parts, head, names):
    co = coords(obj)
    hv = np.nonzero(parts == head)[0]
    hco = co[hv]
    top, bot = hco[:, 2].max(), hco[:, 2].min()
    # Symmetry plane x = x0 (the model is built facing -Y): search x0 and a small yaw on the front half.
    front = hco[(hco[:, 1] < np.median(hco[:, 1])) & (hco[:, 2] > bot + 0.35 * (top - bot))]
    kd = KDTree(len(front))
    for i, p in enumerate(front):
        kd.insert(Vector(p), i)
    kd.balance()
    best = None
    cx = float(np.median(front[:, 0]))
    for x0 in np.linspace(cx - 0.012, cx + 0.012, 25):
        for yaw in np.radians(np.linspace(-4, 4, 9)):
            c, s = math.cos(yaw), math.sin(yaw)
            # mirror across the plane through (x0, *, *) whose normal is (cos yaw, sin yaw, 0)
            nrm = np.array([c, s, 0.0])
            d = (front - np.array([x0, 0, 0])) @ nrm
            mir = front - 2 * d[:, None] * nrm
            err = np.mean([kd.find(Vector(p))[2] for p in mir[::7]])
            if best is None or err < best[0]:
                best = (err, x0, yaw)
    err0, x0, yaw = best
    nrm = np.array([math.cos(yaw), math.sin(yaw), 0.0])
    origin = np.array([x0, 0.0, 0.0])

    def mirror(p):
        d = (p - origin) @ nrm
        return p - 2 * np.outer(d, nrm) if p.ndim == 2 else p - 2 * d * nrm

    mesh = obj.data
    tri = [tuple(mesh.vertices[i].co) for i in hv]
    index = {int(v): k for k, v in enumerate(hv)}
    polys = [[index[i] for i in p.vertices] for p in mesh.polygons if int(parts[p.vertices[0]]) == head]
    moved = 0.0
    for _ in range(2):
        tree = BVHTree.FromPolygons(tri, polys)
        mir = mirror(hco)
        q = np.array([tuple(tree.find_nearest(Vector(p))[0]) for p in mir])
        new = 0.5 * (hco + mirror(q))
        moved = max(moved, float(np.linalg.norm(new - hco, axis=1).max()))
        hco = new
        tri = [tuple(p) for p in hco]
    co[hv] = hco
    # Face parts: small parts whose centre lies on the front of the head, between chin and crown.
    lo, hi = hco.min(0), hco.max(0)
    feats = []
    for p in np.unique(parts):
        if p == head:
            continue
        v = np.nonzero(parts == p)[0]
        c = co[v].mean(0)
        size = np.ptp(co[v], axis=0).max()
        if lo[2] + 0.25 * (hi[2] - lo[2]) < c[2] < hi[2] - 0.1 * (hi[2] - lo[2]) and c[1] < (lo[1] + hi[1]) / 2 \
                and abs((c - origin) @ nrm) < 0.45 * (hi[0] - lo[0]) and size < 0.06:
            feats.append((p, v, c))
    shifts, paired = [], []
    used = set()
    for p, v, c in feats:
        if p in used:
            continue
        d = (c - origin) @ nrm
        if abs(d) < 0.004:
            delta = -d * nrm
            if np.linalg.norm(delta) < 0.012:
                co[v] += delta
                shifts.append((names[p], round(float(np.linalg.norm(delta)) * 1000, 1)))
            used.add(p)
            continue
        mc = mirror(c)
        mate = min((f for f in feats if f[0] != p and f[0] not in used),
                   key=lambda f: np.linalg.norm(f[2] - mc), default=None)
        if mate is None or np.linalg.norm(mate[2] - mc) > 0.02 or \
                abs(len(mate[1]) - len(v)) > 0.7 * max(len(v), len(mate[1])):
            continue
        target = 0.5 * (c + mirror(mate[2]))
        da, db = target - c, mirror(target) - mate[2]
        co[v] += da
        co[mate[1]] += db
        used |= {p, mate[0]}
        paired += [int(p), int(mate[0])]
        shifts.append((f"{names[p]}+{names[mate[0]]}", round(float(max(np.linalg.norm(da), np.linalg.norm(db))) * 1000, 1)))
    set_coords(obj, co)
    return {"head_part": names[head], "plane_x": round(float(x0), 4), "plane_yaw_deg": round(math.degrees(yaw), 2),
            "mirror_error_mm": round(err0 * 1000, 2), "max_snap_mm": round(moved * 1000, 2), "feature_moves_mm": shifts,
            "paired_parts": paired}


# ------------------------------------------------------------------ 4. weights
CATS = {
    "head": ("Head", "Neck", "HeadTop_End"),
    "hand": ("Hand",),
    "arm": ("Arm", "ForeArm"),
    "leg": ("UpLeg", "Leg", "Foot", "ToeBase", "Toe_End"),
}


def cat_of(name):
    s = name.split(":")[-1]
    if s in CATS["head"]:
        return "head"
    if "Hand" in s:
        return "hand"
    if s.endswith(CATS["arm"]):
        return "arm"
    if s.endswith(CATS["leg"]):
        return "leg"
    return "trunk"


def body_weights(body, bones):
    n = len(body.data.vertices)
    W = np.zeros((n, len(bones)))
    col = {b: i for i, b in enumerate(bones)}
    names = {g.index: g.name for g in body.vertex_groups}
    for v in body.data.vertices:
        for g in v.groups:
            j = col.get(names[g.group])
            if j is not None:
                W[v.index, j] = g.weight
    return W


def ray_weights(obj, body, bones):
    """Weights per vertex from the body triangle hit by a ray cast against the vertex normal."""
    bm = bmesh.new()
    bm.from_mesh(body.data)
    bmesh.ops.triangulate(bm, faces=bm.faces)
    bm.verts.ensure_lookup_table()
    tris = [[v.index for v in f.verts] for f in bm.faces]
    bco = np.array([tuple(v.co) for v in bm.verts])
    bm.free()
    tree = BVHTree.FromPolygons([tuple(p) for p in bco], tris)
    Wb = body_weights(body, bones)
    co, nrm = coords(obj), normals(obj)
    W = np.zeros((len(co), len(bones)))
    ray_hits = 0
    for i in range(len(co)):
        p = Vector(co[i])
        near = tree.find_nearest(p)
        loc, _, fi, dist = tree.ray_cast(p - Vector(nrm[i]) * 0.002, -Vector(nrm[i]), 0.25)
        if fi is None or dist > 2.5 * near[3] + 0.03:
            loc, fi = near[0], near[2]
        else:
            ray_hits += 1
        a, b, c = (bco[k] for k in tris[fi])
        # barycentric of loc in (a, b, c)
        v0, v1, v2 = b - a, c - a, np.array(loc) - a
        d00, d01, d11 = v0 @ v0, v0 @ v1, v1 @ v1
        d20, d21 = v2 @ v0, v2 @ v1
        den = d00 * d11 - d01 * d01
        if abs(den) < 1e-14:
            bc = np.array([1.0, 0.0, 0.0])
        else:
            y = (d11 * d20 - d01 * d21) / den
            z = (d00 * d21 - d01 * d20) / den
            bc = np.clip(np.array([1 - y - z, y, z]), 0, 1)
            bc /= bc.sum()
        W[i] = bc @ Wb[tris[fi]]
    return W, ray_hits


def smooth_part(W, edges, rows, rounds):
    """Laplacian smoothing of one part's weights over its own edges."""
    if rounds <= 0 or len(edges) == 0:
        return W
    loc = np.full(len(W), -1)
    loc[rows] = np.arange(len(rows))
    a, b = loc[edges[:, 0]], loc[edges[:, 1]]
    n = len(rows)
    deg = np.bincount(a, minlength=n) + np.bincount(b, minlength=n)
    sub = W[rows].copy()
    for _ in range(rounds):
        acc = np.zeros_like(sub)
        np.add.at(acc, a, sub[b])
        np.add.at(acc, b, sub[a])
        has = deg > 0
        sub[has] = 0.5 * sub[has] + 0.5 * acc[has] / deg[has, None]
    W[rows] = sub
    return W


def tuck_inner(obj, parts, names, classes, reach=0.04, depth=0.012):
    """Trousers under a coat or cape: points with the outer layer within `reach` along their normal sink
    `depth` inward (eased over the part), so the outer layer keeps a margin when the legs and the
    two-legged skirt move apart."""
    co, nrm = coords(obj), normals(obj)
    mesh = obj.data
    outer = [i for i, n in enumerate(names) if classes.get(n) in ("coat", "cape")]
    inner = [i for i, n in enumerate(names) if classes.get(n) == "leg"]
    if not outer or not inner:
        return 0
    opolys = [tuple(p.vertices) for p in mesh.polygons if parts[p.vertices[0]] in outer]
    tree = BVHTree.FromPolygons([tuple(c) for c in co], opolys)
    rows = np.nonzero(np.isin(parts, inner))[0]
    amount = np.zeros(len(co))
    for i in rows:
        hit = tree.ray_cast(Vector(co[i] + nrm[i] * 0.001), Vector(nrm[i]), reach)
        if hit[0] is not None:
            amount[i] = depth
    edges = np.array([tuple(e.vertices) for e in mesh.edges], np.int64)
    sel = np.isin(edges[:, 0], rows)
    amount = smooth_part(amount[:, None], edges[sel], rows, 6)[:, 0]
    co[rows] -= nrm[rows] * amount[rows, None]
    set_coords(obj, co)
    return int((amount > 0.006).sum())


def assign_weights(obj, body, rig, parts, names, head, hero):
    bones = [b.name for b in rig.data.bones]
    idx = {b.split(":")[-1]: i for i, b in enumerate(bones)}
    cats = np.array([cat_of(b) for b in bones])
    W, ray_hits = ray_weights(obj, body, bones)
    co = coords(obj)
    z_of = {k: (rig.matrix_world @ rig.data.bones[bones[i]].head_local).z for k, i in idx.items()}
    hips_z, knee_z, chin_z = z_of["Hips"], z_of["LeftLeg"], z_of["Head"]
    crotch_z = z_of["LeftUpLeg"]
    ankle_z = z_of["LeftFoot"]
    rigid = {}
    for bone, plist in RIGID.get(hero, {}).items():
        for nm in plist:
            if nm in names:
                rigid[names.index(nm)] = bone
    cape = {names.index(nm) for nm in CAPE.get(hero, []) if nm in names}
    edges_all = np.array([tuple(e.vertices) for e in obj.data.edges], np.int64)
    classes = {}
    finger = [i for i, b in enumerate(bones) if "Hand" in b.split(":")[-1] and not b.endswith("Hand")]

    def move(rows, src_cols, dst_col):
        for c in src_cols:
            W[np.ix_(rows, [dst_col])] += W[np.ix_(rows, [c])]
            W[np.ix_(rows, [c])] = 0.0

    def side_cols(rows, suffixes, side_bone):
        """Fold the given per-side bones into `side_bone` of the same side."""
        for side in ("Left", "Right"):
            src = [idx[side + s] for s in suffixes if side + s in idx]
            move(rows, src, idx[side + side_bone])

    for p in range(len(names)):
        rows = np.nonzero(parts == p)[0]
        if len(rows) == 0:
            continue
        mass = {c: float(W[rows][:, cats == c].sum()) for c in ("head", "hand", "arm", "leg", "trunk")}
        tot = max(sum(mass.values()), 1e-9)
        frac = {c: mass[c] / tot for c in mass}
        pz = co[rows, 2]
        if p in rigid:
            cls, bone = "rigid", rigid[p]
        elif p == head:
            cls, bone = "head", None
        elif pz.min() > chin_z - 0.01 or (frac["head"] > 0.3 and pz.max() > chin_z + 0.08):
            # hats, hair, braids, goggles: anything mostly on the head rides the head whole
            cls, bone = "rigid", "Head"
        elif p in cape:
            cls, bone = "cape", None
        elif frac["hand"] > 0.5:
            cls, bone = "hand", None
        elif pz.min() < 0.5 * (knee_z + ankle_z) and frac["leg"] > 0.35:
            # trousers, overalls, stockings, boots: down to the shins and sitting on the legs
            cls, bone = "leg", None
        elif pz.min() < knee_z + 0.1 and pz.max() > hips_z + 0.25:
            # long coats (with or without sleeves): checked before arms, sleeves can outweigh the body
            cls, bone = "coat", None
        elif pz.min() < crotch_z - 0.05 and frac["leg"] > 0.35:
            cls, bone = "leg", None
        elif frac["arm"] + frac["hand"] > 0.5 and frac["trunk"] < 0.25:
            cls, bone = "arm", None
        elif frac["leg"] > 0.6:
            cls, bone = "leg", None
        elif pz.min() < crotch_z - 0.05 and pz.max() > hips_z + 0.1:
            cls, bone = "coat", None
        elif frac["head"] > 0.6:
            cls, bone = "headwear", None
        else:
            cls, bone = "torso", None
        if cls not in ("rigid", "head") and np.ptp(co[rows], axis=0).max() < 0.04:
            # buttons, laces, buckles: one piece on the bone that carries most of their weight
            pick = W[rows].sum(0)
            if cls == "hand":
                pick = pick * np.array([("Hand" in b or "ForeArm" in b) for b in bones])
            cls, bone = "rigid", bones[int(np.argmax(pick))].split(":")[-1]
        classes[names[p]] = cls if cls != "rigid" else f"rigid:{bone}"
        if cls == "rigid":
            W[rows] = 0.0
            W[rows, idx[bone]] = 1.0
            continue
        if cls == "hand":
            for side in ("Left", "Right"):
                fing = [i for i in finger if bones[i].split(":")[-1].startswith(side)]
                move(rows, fing, idx[side + "Hand"])
            keep = [idx[s + k] for s in ("Left", "Right") for k in ("Hand", "ForeArm")]
        elif cls == "arm":
            for side in ("Left", "Right"):
                fing = [i for i in finger if bones[i].split(":")[-1].startswith(side)]
                move(rows, fing, idx[side + "Hand"])
            keep = [idx[s + k] for s in ("Left", "Right") for k in ("Shoulder", "Arm", "ForeArm", "Hand")] + \
                [idx["Spine2"]]
        elif cls in ("head", "headwear"):
            keep = [idx["Head"], idx["Neck"], idx["Spine2"]]
        elif cls == "leg":
            keep = [idx["Hips"]] + [idx[s + k] for s in ("Left", "Right") for k in ("UpLeg", "Leg", "Foot", "ToeBase")]
        elif cls in ("coat", "torso"):
            # Jackets and coats that include their sleeves keep the arm bones (the inward rays already
            # gave the panels beside the sleeves to the torso); garments without sleeves fold them away.
            side_cols(rows, ("Leg", "Foot", "ToeBase"), "UpLeg")
            if frac["arm"] + frac["hand"] < 0.08:
                side_cols(rows, ("Arm", "ForeArm", "Hand"), "Shoulder")
                for side in ("Left", "Right"):
                    move(rows, [i for i in finger if bones[i].split(":")[-1].startswith(side)], idx[side + "Shoulder"])
            else:
                for side in ("Left", "Right"):
                    move(rows, [i for i in finger if bones[i].split(":")[-1].startswith(side)], idx[side + "Hand"])
            keep = None
        else:  # cape: the chest carries it, the hips its hem (below); clavicles and arms would fling it
            keep = [idx["Spine2"], idx["Spine1"], idx["Spine"], idx["Hips"]]
        if keep is not None:
            mask = np.zeros(len(bones), bool)
            mask[keep] = True
            dropped = W[np.ix_(rows, ~mask)].sum(1)
            W[np.ix_(rows, ~mask)] = 0.0
            # Anything outside the allowed set goes to the strongest allowed bone of that vertex.
            sub = W[np.ix_(rows, mask)]
            top = np.argmax(sub, axis=1)
            sub[np.arange(len(rows)), top] += dropped
            W[np.ix_(rows, mask)] = sub
        if cls in ("coat", "torso", "cape"):
            # Skirts below the hips lean on the hips so the walk does not tear them between the legs.
            f = np.clip((hips_z - co[rows, 2]) / max(hips_z - knee_z, 1e-3), 0, 1) * 0.45
            W[rows] *= (1 - f)[:, None]
            W[rows, idx["Hips"]] += f
        rounds = {"head": 3, "headwear": 4, "hand": 2, "arm": 5, "leg": 5, "coat": 10, "torso": 8, "cape": 16}[cls]
        sel = np.isin(edges_all[:, 0], rows)
        W = smooth_part(W, edges_all[sel], rows, rounds)
    tucked = tuck_inner(obj, parts, names, classes)
    # 4 bones max, normalised.
    cut = np.sort(W, axis=1)[:, -4][:, None]
    W[W < cut] = 0.0
    W /= np.maximum(W.sum(1, keepdims=True), 1e-9)
    for g in list(obj.vertex_groups):
        obj.vertex_groups.remove(g)
    for j, b in enumerate(bones):
        nz = np.nonzero(W[:, j] > 1e-4)[0]
        if len(nz) == 0:
            continue
        g = obj.vertex_groups.new(name=b)
        for w in np.unique(np.round(W[nz, j], 4)):
            g.add(nz[np.round(W[nz, j], 4) == w].tolist(), float(w), "REPLACE")
    obj.parent = rig
    obj.matrix_parent_inverse = rig.matrix_world.inverted()
    arm = obj.modifiers.new("Armature", "ARMATURE")
    arm.object = rig
    counts = {}
    for c in classes.values():
        c = c.split(":")[0]
        counts[c] = counts.get(c, 0) + 1
    (STAGE / f"{hero}-classes.json").write_text(json.dumps(classes, indent=0))
    return {"ray_hit_vertices": ray_hits, "vertices": len(co), "classes": counts, "tucked_vertices": tucked,
            "rigid_parts": {names[p]: b for p, b in rigid.items()}}


# ------------------------------------------------------------------ 5. texture
def clear_view(tree, p, n):
    """True when nothing facing the front camera lies between p and it. Back faces are skipped: Tripo
    eyeballs poke through the inside of their lids, which must not hide them."""
    o = Vector(p + n * 0.002)
    for _ in range(6):
        loc, normal, _, _ = tree.ray_cast(o, Vector((0, -1, 0)), 5.0)
        if loc is None:
            return True
        if normal.y < 0:
            return False
        o = loc + Vector((0, -0.0005, 0))
    return False


def paint(obj, hero, parts, head, sym):
    """Visibility and sheet coordinates per vertex here; the image work runs in parts_paint.py."""
    mesh = obj.data
    co, nrm = coords(obj), normals(obj)
    view = R.view_landmarks(obj, f"{hero}-parts-final")
    det, fv = view["front_det"], view["front_view"]
    if det["pose"]:
        # the full-body face is a few dozen pixels wide: always re-detect on a close-up
        det["face"] = R.closeup_face(obj, hero, det, fv) or det["face"]
    unit = fv["size"] / max(fv["res"])
    # Only surfaces lying on the head (skin, eyes, brows) take the drawn face; curls and brims in
    # front of it keep their own colour.
    hv = np.nonzero(parts == head)[0]
    index = {int(v): k for k, v in enumerate(hv)}
    htree = BVHTree.FromPolygons([tuple(co[i]) for i in hv],
                                 [[index[i] for i in p.vertices] for p in mesh.polygons if parts[p.vertices[0]] == head])
    hlo, hhi = co[hv].min(0) - 0.02, co[hv].max(0) + 0.02
    near_head = np.zeros(len(co), bool)
    for i in np.nonzero(((co > hlo) & (co < hhi)).all(1))[0]:
        near_head[i] = parts[i] == head or htree.find_nearest(Vector(co[i]))[3] < 0.006
    # mirror-paired face parts (eyes, brows) can sit deep in their sockets: they take the drawn face too
    near_head |= np.isin(parts, sym["paired_parts"])
    plane_px = fv["res"][0] / 2 + sym["plane_x"] / unit
    rpx = np.c_[fv["res"][0] / 2 + co[:, 0] / unit, fv["res"][1] / 2 - (co[:, 2] - fv["centre"][1]) / unit]
    tree = BVHTree.FromObject(obj, bpy.context.evaluated_depsgraph_get())
    visible = np.zeros(len(co), bool)
    for i in np.nonzero(nrm[:, 1] < -0.3)[0]:
        visible[i] = clear_view(tree, co[i], nrm[i])
    # Hat brims stand in front of the eyes: for the face, only the face's own surfaces may occlude.
    own = np.isin(parts, [head] + list(sym["paired_parts"]))
    fpolys = [tuple(p.vertices) for p in mesh.polygons if own[p.vertices[0]]]
    ftree = BVHTree.FromPolygons([tuple(c) for c in co], fpolys)
    for i in np.nonzero(near_head & (nrm[:, 1] < -0.3))[0]:
        visible[i] = clear_view(ftree, co[i], nrm[i])
    uv = np.zeros((len(co), 2))
    loops = mesh.uv_layers.active.data
    for poly in mesh.polygons:
        for li, vi in zip(poly.loop_indices, poly.vertices):
            uv[vi] = loops[li].uv
    mesh.calc_loop_triangles()
    tri_v = np.array([lt.vertices[:] for lt in mesh.loop_triangles], np.int32)
    tri_uv = np.array([[loops[k].uv[:] for k in lt.loops] for lt in mesh.loop_triangles], np.float32)
    # Tripo scatters the face over dozens of atlas fragments; the drawn face needs one piece. The head
    # part and its eyes/brows get their own unwrap and texture (material slot 1).
    face_set = np.isin(parts, [head] + list(sym["paired_parts"]))
    face_poly = np.array([face_set[p.vertices[0]] for p in mesh.polygons])
    activate(obj)
    bpy.ops.object.mode_set(mode="EDIT")
    bpy.ops.mesh.select_all(action="DESELECT")
    bpy.ops.object.mode_set(mode="OBJECT")
    mesh.polygons.foreach_set("select", face_poly)
    bpy.ops.object.mode_set(mode="EDIT")
    bpy.ops.uv.smart_project(angle_limit=math.radians(70), island_margin=0.004)
    bpy.ops.object.mode_set(mode="OBJECT")
    loops = mesh.uv_layers.active.data
    mesh.calc_loop_triangles()
    tri_uv2 = np.array([[loops[k].uv[:] for k in lt.loops] for lt in mesh.loop_triangles], np.float32)
    tri_face = np.array([face_poly[lt.polygon_index] for lt in mesh.loop_triangles])
    img = base_image(obj)
    tex = STAGE / f"{hero}-tripo.png"
    img.filepath_raw, img.file_format = str(tex), "PNG"
    img.save()
    out = STAGE / f"{hero}-albedo.png"
    npz = STAGE / f"{hero}-paint.npz"
    np.savez(npz, co=co, nrm=nrm, part=parts, head=np.array([head]), visible=visible, uv=uv,
             tri_v=tri_v, tri_uv=tri_uv, tri_uv2=tri_uv2, tri_face=tri_face, render_px=rpx, near_head=near_head, paired=np.isin(parts, sym["paired_parts"]), plane_px=np.array([plane_px]),
             render_pose=np.array(det["pose"] or [], float), render_face=np.array(det["face"] or [], float))
    env = {k: v for k, v in os.environ.items() if k not in ("PYTHONHOME", "PYTHONPATH")}
    face_out = STAGE / f"{hero}-face.png"
    r = subprocess.run([str(VENV), str(FIT / "parts_paint.py"), "--hero", hero, "--npz", str(npz),
                        "--tex", str(tex), "--out", str(out), "--face-out", str(face_out)],
                       capture_output=True, text=True, env=env)
    print(r.stdout[-3000:])
    if r.returncode:
        raise RuntimeError(r.stderr[-3000:])
    info = json.loads((STAGE / f"{hero}-paint.json").read_text())
    mesh.materials.clear()
    for tag, png in (("toon", out), ("face", face_out)):
        painted = bpy.data.images.load(str(png))
        painted.name = f"{hero}_{tag}"
        painted.pack()
        mat = bpy.data.materials.new(f"{hero}_{tag}")
        mat.use_nodes = True
        texn = mat.node_tree.nodes.new("ShaderNodeTexImage")
        texn.image = painted
        bsdf = mat.node_tree.nodes["Principled BSDF"]
        mat.node_tree.links.new(texn.outputs["Color"], bsdf.inputs["Base Color"])
        bsdf.inputs["Roughness"].default_value = 0.85
        bsdf.inputs["Metallic"].default_value = 0.0
        mesh.materials.append(mat)
    mesh.polygons.foreach_set("material_index", face_poly.astype(np.int32))
    # Face normals lean toward the viewer so the toon light lays one broad lit plane over the face.
    face = np.zeros(len(co), bool)
    face[np.asarray(info["face_vertices"], int)] = True
    flat = nrm.copy()
    w = np.zeros(len(co))
    w[np.asarray(info["face_vertices"], int)] = np.asarray(info["face_weight"], float)
    flat[face] = nrm[face] * (1 - 0.45 * w[face, None]) + np.array([0, -1, 0]) * 0.45 * w[face, None]
    flat /= np.linalg.norm(flat, axis=1, keepdims=True)
    mesh.normals_split_custom_set_from_vertices([tuple(n) for n in flat])
    return info


# ------------------------------------------------------------------ main
def main():
    p = argparse.ArgumentParser()
    p.add_argument("--motion", type=Path, required=True)
    p.add_argument("--hero", required=True)
    p.add_argument("--out", type=Path, default=OUT)
    p.add_argument("--stature", type=float, default=None,
                   help="skeleton stature; by default the first run measures it (see RESTATURE)")
    a = p.parse_args(sys.argv[sys.argv.index("--") + 1:])
    hero = a.hero
    STAGE.mkdir(parents=True, exist_ok=True)
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.context.scene.render.fps = 24
    target = B.HEROES[hero]["height"]
    stature = a.stature or target
    body, rig = R.make_body(hero, stature)
    obj, names, removed = load_parts(hero, target)
    reg = register(obj, body, hero)
    nose = reg["landmarks"]["front"].get(0)
    sc, off = reg["scale"], reg["offset"]
    head = head_part(obj, part_index(obj), (sc * nose[0] + off[0], sc * nose[1] + off[2])) if nose else None
    if head is None:
        raise RuntimeError("no head part under the nose")
    # The fitted MPFB skeleton and Tripo's figure differ in proportion: registration sizes the model by
    # its joints, so the crown lands wherever the skeleton puts it. Measure the crown (head part top) and,
    # when it misses the designed stature, report the skeleton stature that lands it (one rebuild).
    crown = float(coords(obj)[part_index(obj) == head, 2].max())
    if a.stature is None and abs(crown / target - 1) > 0.015:
        fixed = round(stature * target / crown, 4)
        (STAGE / f"{hero}-stature.json").write_text(json.dumps({"crown": crown, "stature": fixed}))
        print("RESTATURE", hero, fixed, "crown", round(crown, 4))
        return
    sym = symmetrize_face(obj, part_index(obj), head, names)
    # Eye parts: small parts at MediaPipe's eye points (a Tripo eye may be its own part on one side and
    # part of the head on the other, so mirror pairing alone misses some).
    pts = [Vector((sc * reg["landmarks"]["front"][i][0] + off[0], 0, sc * reg["landmarks"]["front"][i][1] + off[2]))
           for i in (2, 5) if i in reg["landmarks"]["front"]]
    pi, co = part_index(obj), coords(obj)
    for p in np.unique(pi):
        v = co[pi == p]
        c = v.mean(0)
        if p != head and np.ptp(v, axis=0).max() < 0.05 and                 any(math.hypot(c[0] - e.x, c[2] - e.z) < 0.03 for e in pts) and int(p) not in sym["paired_parts"]:
            sym["paired_parts"].append(int(p))
    pose_to(rig, body, reg["joints"], reg["skull_base"])
    weights = assign_weights(obj, body, rig, part_index(obj), names, head, hero)
    bpy.data.objects.remove(body, do_unlink=True)
    info = paint(obj, hero, part_index(obj), head, sym)
    obj.data.attributes.remove(obj.data.attributes["part"])
    for o in bpy.data.objects:
        o.hide_render = False
    clips = dict(B.CLIPS)
    clips.update(B.OVERRIDES.get(hero, {}))
    clips.update(CLIP_FIX.get(hero, {}))
    src = B.load_motion(a.motion)
    made = B.retarget(src, rig, clips, 24, delta=DELTA)
    bpy.data.objects.remove(src, do_unlink=True)
    for act in list(bpy.data.actions):
        if act.name not in clips:
            bpy.data.actions.remove(act)
    path = a.out / f"{hero}.glb"
    B.export(path, rig, [obj])
    receipt_path = a.out / "receipt.json"
    receipt = json.loads(receipt_path.read_text()) if receipt_path.exists() else {}
    co = coords(obj)
    receipt[hero] = {"id": hero, "source": f"tools/cast/reference/tripo-parts/{hero}.glb",
                     "builder": "tools/cast/fit/build_tripo_parts.py",
                     "parts": len(names), "cleanup_removed_vertices": removed,
                     "registration": {"scale": reg["scale"], "offset": reg["offset"],
                                      "skeleton_stature": stature, "crown_m": round(crown, 4)},
                     "face_symmetry": {k: v for k, v in sym.items() if k != "paired_parts"}, "weights": weights,
                     "paint": {k: v for k, v in info.items() if k not in ("face_vertices", "face_weight")},
                     "clips": made, "height_m": round(float(co[:, 2].max() - co[:, 2].min()), 4),
                     "triangles": sum(len(p.vertices) - 2 for p in obj.data.polygons),
                     "glb_bytes": path.stat().st_size}
    receipt_path.write_text(json.dumps(receipt, indent=1) + "\n")
    print("PARTS_PASS", hero, json.dumps({k: receipt[hero][k] for k in ("parts", "face_symmetry", "height_m", "triangles")}))


if __name__ == "__main__":
    main()
