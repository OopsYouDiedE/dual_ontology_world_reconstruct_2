"""Garment modelling and clipping audit for the hero cast (runs inside build_heroes.py).

Fitted garments are offset shells cut from the MPFB body: every garment vertex comes from a body
vertex, keeps its skin weights, and sits a fixed distance outside the layer beneath it, so it deforms
with the body instead of through it. Body faces (and inner layers) fully hidden by a closed outer layer
are removed. Hanging parts (coat skirts, tails, aprons, skirts, capes) are generated tubes and panels
whose weights fade from the hips into both thighs so they follow a stride without the legs poking out.
"""
import math

import bmesh
import bpy
import numpy as np
from mathutils import Matrix, Vector
from mathutils.bvhtree import BVHTree

# ------------------------------------------------------------------ palettes and outfits
C = {
    "shirt": (0.86, 0.84, 0.78), "ivory": (0.90, 0.86, 0.74), "charcoal": (0.16, 0.17, 0.19),
    "tweed": (0.40, 0.31, 0.21), "camel": (0.55, 0.42, 0.28), "slate": (0.27, 0.31, 0.36),
    "leather": (0.24, 0.15, 0.09), "boot": (0.11, 0.08, 0.06), "canvas": (0.46, 0.42, 0.32),
    "denim": (0.20, 0.25, 0.33), "rust": (0.48, 0.20, 0.12), "brass": (0.78, 0.60, 0.28),
    "moss": (0.29, 0.33, 0.22), "oat": (0.62, 0.56, 0.44), "patch": (0.38, 0.30, 0.36),
    "plum": (0.33, 0.12, 0.26), "gold": (0.82, 0.63, 0.24), "teal": (0.10, 0.34, 0.36),
    "cream": (0.93, 0.89, 0.80), "crimson": (0.55, 0.08, 0.10), "black": (0.05, 0.05, 0.06),
    "white": (0.95, 0.95, 0.93), "wine": (0.28, 0.05, 0.08), "feather": (0.86, 0.20, 0.16),
    "wood": (0.45, 0.27, 0.13),
}

# Fitted pieces: (name, region, layer, colour). Layer sets the offset: 0 = skin-tight.
# Hanging pieces: dict(kind=...). Props: dict(prop=...).
#
# Plugin garments: dict(suit=<MakeHuman CC0 clothes id>, colors=(...)). MPFB fits and rigs them and masks
# the skin beneath; their texture is clustered into len(colors) regions, ordered top-to-bottom ("z") or
# dark-to-light ("lum"), and each region gets a flat palette colour. Modelled layers sit outside them.
OUTFITS = {
    # 20-year-old private detective: shirt and wool trousers, tweed waistcoat, open slate overcoat, fedora.
    "detective": [
        dict(suit="male_casualsuit01", colors=("shirt", "charcoal"), order="z"),
        dict(suit="shoes03", colors=("boot",)), dict(suit="fedora01", colors=("charcoal",)),
        ("Waistcoat", "waistcoat", 2, "tweed"),
        ("Overcoat", "coat_open", 4, "slate"), ("Collar", "collar", 4, "slate"),
        dict(kind="skirt", name="CoatSkirt", top="waist", hem=0.47, flare=0.10, gap=0.30, layer=4, color="slate"),
        dict(prop="satchel", color="leather"), dict(ribbon="Strap", color="leather"),
    ],
    # Engineer promoted from the shop floor: work overalls kept under a foreman's jacket with rolled sleeves.
    "hale": [
        dict(suit="male_worksuit01", colors=("denim", "oat"), order="lum"),
        dict(suit="shoes03", colors=("boot",)),
        ("Jacket", "coat_rolled", 3, "charcoal"),
        dict(prop="tool_belt", color="leather"), dict(prop="goggles", color="brass"),
    ],
    # 20th-century vagrant girl: blouse and skirt under a man's oversized coat, scarf, newsboy cap.
    "quer": [
        dict(suit="female_elegantsuit01", colors=("oat", "patch"), order="z"),
        dict(suit="shoes02", colors=("leather",)),
        ("Stockings", "stockings", 0.3, "charcoal"),
        ("Coat", "coat_big", 3, "moss"), ("Scarf", "scarf", 5, "rust"),
        dict(kind="skirt", name="CoatSkirt", top="waist", hem=0.50, flare=0.13, gap=0.26, layer=3, color="moss", ragged=True),
        dict(prop="newsboy_cap", color="slate"),
    ],
    # Flamboyant bard: everything the others are not.
    "lucian": [
        dict(suit="male_casualsuit03", colors=("cream", "teal"), order="z"),
        ("Doublet", "doublet", 2, "gold"), ("Boots", "tall_boots", 2, "leather"),
        ("Gloves", "gloves", 1, "cream"), ("Coat", "coat_open", 4, "plum"),
        ("Sash", "sash", 5, "crimson"),
        dict(kind="skirt", name="CoatTails", top="waist", hem=0.30, flare=0.16, gap=0.34, layer=4, color="plum"),
        dict(kind="cape", name="Cape", layer=6, color="crimson"),
        dict(prop="plumed_hat", color="plum"), dict(prop="lute", color="wood"),
    ],
    # Near-human anomaly: a correct evening suit, decades out of date, with tails and a high collar.
    "demon": [
        dict(suit="male_elegantsuit01", colors=("black", "white"), order="lum"),
        dict(suit="shoes04", colors=("black",)),
        ("Gloves", "gloves", 1, "white"), ("Collar", "high_collar", 3, "white"),
        dict(kind="skirt", name="Tails", top="waist", hem=0.40, flare=0.05, gap=1.15, layer=2, color="black", back_only=True),
    ],
}


def suits(hero_id):
    return [item["suit"] for item in OUTFITS[hero_id] if isinstance(item, dict) and "suit" in item]
OFFSET = 0.0055     # metres per layer
SOLID_LAYERS = {"Boots", "Shoes", "Collar"}


# ------------------------------------------------------------------ body sampling
class Body:
    """Rest-pose landmarks plus, for each body vertex, its dominant bone and position along it."""

    def __init__(self, body, rig):
        self.obj, self.rig = body, rig
        mesh = body.data
        self.co = [v.co.copy() for v in mesh.vertices]
        self.normal = [v.normal.copy() for v in mesh.vertices]
        names = {g.index: g.name for g in body.vertex_groups}
        bones = {b.name: b for b in rig.data.bones}
        self.bone = []
        self.t = []
        for v in mesh.vertices:
            best = max(((g.weight, names[g.group]) for g in v.groups if names[g.group] in bones), default=(0, ""))
            short = best[1].split(":")[-1]
            self.bone.append(short)
            if best[1]:
                b = bones[best[1]]
                d = b.tail_local - b.head_local
                self.t.append(max(0.0, min(1.0, (v.co - b.head_local).dot(d) / d.length_squared)))
            else:
                self.t.append(0.0)
        self.z = {b.name.split(":")[-1]: b.head_local.z for b in rig.data.bones}
        self.head = {b.name.split(":")[-1]: b.head_local.copy() for b in rig.data.bones}
        self.tail = {b.name.split(":")[-1]: b.tail_local.copy() for b in rig.data.bones}
        self.neighbors = [[] for _ in mesh.vertices]
        for e in mesh.edges:
            a, b = e.vertices
            self.neighbors[a].append(b)
            self.neighbors[b].append(a)
        self.full = {b.name.split(":")[-1]: b.name for b in rig.data.bones}
        # Skin weights captured now: later culling renumbers the body's vertices.
        self.weights = [{names[g.group].split(":")[-1]: g.weight for g in v.groups
                         if names[g.group] in bones and g.weight > 0} for v in mesh.vertices]
        self.under = [0.0] * len(self.co)   # plugin cloth thickness along each body normal
        self.cloth = []                     # (rest point, dominant bone) of plugin garments

    def points(self):
        yield from zip(self.co, self.bone)
        yield from self.cloth

    def limb(self, i, part, t0=0.0, t1=1.0):
        b = self.bone[i]
        return b.endswith(part) and not b.endswith("Hand" + part) and t0 <= self.t[i] <= t1


TORSO = ("Hips", "Spine", "Spine1", "Spine2", "Shoulder", "Neck")


def region(B, kind):
    """Return the set of body vertex indices covered by a fitted garment region."""
    z = B.z
    waist, chest, neck, head = z["Spine"], z["Spine2"], z["Neck"], z["Head"]
    shoulder_x = abs(B.head["LeftArm"].x)

    def torso(i, lo, hi):
        return B.bone[i].endswith(TORSO) and lo <= B.co[i].z <= hi

    def leg(i, part, t0=0.0, t1=1.0):
        return B.bone[i].endswith(part) and t0 <= B.t[i] <= t1 and "Hand" not in B.bone[i]

    def arm(i, fore_t):
        return leg(i, "Arm") and not B.bone[i].endswith("ForeArm") or leg(i, "ForeArm", 0, fore_t)

    sets = {
        "shirt": lambda i: torso(i, waist - 0.12, neck + 0.035) or arm(i, 0.93),
        "shirt_rolled": lambda i: torso(i, waist - 0.12, neck + 0.035) or arm(i, 0.30),
        "blouse": lambda i: torso(i, waist - 0.12, neck + 0.02) or arm(i, 0.97),
        "trousers": lambda i: (B.bone[i].endswith("Hips") and B.co[i].z <= waist + 0.03)
        or (torso(i, 0, waist + 0.03)) or leg(i, "UpLeg") or leg(i, "Leg", 0, 0.88),
        # Knee down, plus the lower thigh the skirt hem may reveal.
        "stockings": lambda i: leg(i, "UpLeg", 0.6) or leg(i, "Leg", 0, 0.88),
        # V neck: closes to a point a hand below the sternum notch.
        "waistcoat": lambda i: torso(i, waist - 0.09, chest + 0.10) and not B.bone[i].endswith(("Shoulder", "Neck"))
        and not (B.co[i].y < -0.02 and abs(B.co[i].x) < 0.085 * max(0.0, (B.co[i].z - chest + 0.05) / (neck - chest + 0.05))),
        "boots": lambda i: leg(i, "Leg", 0.55) or leg(i, "Foot") or leg(i, "ToeBase"),
        "work_boots": lambda i: leg(i, "Leg", 0.62) or leg(i, "Foot") or leg(i, "ToeBase"),
        "tall_boots": lambda i: leg(i, "Leg", 0.0) or leg(i, "UpLeg", 0.82) or leg(i, "Foot") or leg(i, "ToeBase"),
        "shoes": lambda i: leg(i, "Leg", 0.86) or leg(i, "Foot") or leg(i, "ToeBase"),
        "coat_open": lambda i: (torso(i, waist - 0.14, neck + 0.04) or arm(i, 0.90))
        and not (B.co[i].y < -0.03 and abs(B.co[i].x) < 0.075 and B.co[i].z < neck - 0.02),
        # Long doublet: skirts past the hip joint so the hose never shows at the fork.
        "doublet": lambda i: (torso(i, waist - 0.30, chest + 0.10) and not B.bone[i].endswith(("Shoulder", "Neck"))
                              or leg(i, "UpLeg", 0, 0.16))
        and not (B.co[i].y < -0.02 and abs(B.co[i].x) < 0.06 * max(0.0, (B.co[i].z - chest) / (neck - chest))),
        "coat_rolled": lambda i: (torso(i, waist - 0.10, neck + 0.04) or arm(i, 0.40))
        and not (B.co[i].y < -0.03 and abs(B.co[i].x) < 0.08 and B.co[i].z < neck - 0.02),
        "coat_short": lambda i: (torso(i, waist - 0.05, neck + 0.04) or arm(i, 0.92))
        and not (B.co[i].y < -0.03 and abs(B.co[i].x) < 0.085 and B.co[i].z < neck - 0.02),
        "coat_big": lambda i: (torso(i, waist - 0.14, neck + 0.04) or arm(i, 1.0)
                               or leg(i, "Hand", 0, 0.35))
        and not (B.co[i].y < -0.03 and abs(B.co[i].x) < 0.06 and B.co[i].z < neck - 0.03),
        "collar": lambda i: B.bone[i].endswith("Neck") and B.t[i] < 0.55 or torso(i, neck - 0.01, neck + 0.05),
        "high_collar": lambda i: B.bone[i].endswith("Neck") and B.t[i] < 0.85,
        "scarf": lambda i: B.bone[i].endswith("Neck") and B.t[i] < 0.7 or torso(i, neck - 0.04, neck + 0.05),
        "gloves": lambda i: "Hand" in B.bone[i] or leg(i, "ForeArm", 0.86),
        "braces": lambda i: torso(i, waist, neck + 0.02) and abs(abs(B.co[i].x) - 0.085) < 0.022,
        "sash": lambda i: torso(i, waist - 0.03, waist + 0.06),
        # Satchel strap: right shoulder to left hip, front and back.
        "strap": lambda i: (torso(i, waist - 0.10, neck + 0.04) or B.bone[i].endswith("Hips"))
        and abs(-B.co[i].x - (B.co[i].z - waist) * 0.55 + 0.02) < 0.024 and B.co[i].z > waist - 0.12,
    }
    keep = sets[kind]
    return {i for i in range(len(B.co)) if keep(i)}


def interior(B, cover, rings=1):
    """Covered vertices at least `rings` edges inside the cover's border."""
    inner = set(cover)
    for _ in range(rings):
        inner = {i for i in inner if all(n in inner for n in B.neighbors[i])}
    return inner


# ------------------------------------------------------------------ mesh helpers
def linear(c):
    return tuple(x / 12.92 if x <= 0.04045 else ((x + 0.055) / 1.055) ** 2.4 for x in c)


def material(name, color, rough=0.82):
    """Palette values are authored in sRGB; Blender and glTF factors are linear."""
    color = linear(color)
    mat = bpy.data.materials.get(name) or bpy.data.materials.new(name)
    mat.use_nodes = True
    shader = mat.node_tree.nodes["Principled BSDF"]
    shader.inputs["Base Color"].default_value = (*color, 1.0)
    shader.inputs["Roughness"].default_value = rough
    mat.diffuse_color = (*color, 1.0)
    mat.use_backface_culling = False
    return mat


def cut_shell(B, name, cover, offset, color):
    """Duplicate the body, keep covered faces, push them `offset` along the rest normals."""
    src = B.obj
    obj = src.copy()
    obj.data = src.data.copy()
    obj.name = name
    obj.modifiers.clear()
    bpy.context.collection.objects.link(obj)
    bm = bmesh.new()
    bm.from_mesh(obj.data)
    bm.verts.ensure_lookup_table()
    layer = bm.verts.layers.int.new("src")
    for v in bm.verts:
        v[layer] = v.index
    bmesh.ops.delete(bm, geom=[f for f in bm.faces if not all(v.index in cover for v in f.verts)], context="FACES")
    bmesh.ops.delete(bm, geom=[v for v in bm.verts if not v.link_faces], context="VERTS")
    for v in bm.verts:
        i = v[layer]
        # Above the first layer, clear the plugin cloth measured under this point by the same margin.
        lift = B.under[i] + offset - OFFSET if offset > OFFSET else 0.0
        v.co = B.co[i] + B.normal[i] * max(offset, lift)
    smooth_border(bm)
    bm.to_mesh(obj.data)
    bm.free()
    obj.data.materials.clear()
    obj.data.materials.append(material(name + "_" + color, C[color]))
    for p in obj.data.polygons:
        p.use_smooth = True
    bind(obj, B.rig)
    return obj


def smooth_border(bm, rounds=10, k=0.5):
    """Relax open edges along themselves so a cut that follows body vertices reads as a sewn line."""
    border = [v for v in bm.verts if v.is_boundary]
    links = {v: [e.other_vert(v) for e in v.link_edges if e.is_boundary] for v in border}
    for _ in range(rounds):
        new = {}
        for v, nb in links.items():
            if len(nb) == 2:
                new[v] = v.co.lerp((nb[0].co + nb[1].co) / 2, k)
        for v, co in new.items():
            v.co = co


def body_weights(B, pts):
    """Skin weights of the nearest body vertex for each point."""
    from mathutils.kdtree import KDTree
    kd = KDTree(len(B.co))
    for i, p in enumerate(B.co):
        kd.insert(p, i)
    kd.balance()
    return [dict(B.weights[kd.find(p)[1]]) for p in pts]


def ribbon(B, spec, outer):
    """Satchel strap: right shoulder to left hip, laid over whatever is outermost front and back."""
    verts, faces = [], []
    for obj in outer:
        base = len(verts)
        verts += [obj.matrix_world @ v.co for v in obj.data.vertices]
        faces += [tuple(base + k for k in p.vertices) for p in obj.data.polygons]
    tree = BVHTree.FromPolygons(verts, faces)
    shoulder = Vector((-0.115, 0.0, B.z["Neck"] - 0.005))
    hip_z = B.z["Hips"] - 0.02
    hip_x = max(p.x for p, bone in B.points() if abs(p.z - hip_z) < 0.03 and bone.endswith(("Hips", "UpLeg"))) - 0.015
    hip = Vector((hip_x, 0.0, hip_z))

    def cast(origin, direction):
        hit = tree.ray_cast(origin, direction, 3.0)
        return (hit[0], hit[1]) if hit[0] is not None else (None, None)

    path = []
    n = 26
    for side in (1, -1):    # back first (hip -> shoulder), then front (shoulder -> hip)
        row = []
        for k in range(n + 1):
            q = hip.lerp(shoulder, k / n)
            p, nrm = cast(Vector((q.x, side * 1.5, q.z)), Vector((0, -side, 0)))
            if p is not None:
                row.append((p, nrm))
        path += row if side == 1 else row[::-1]
        if side == 1:
            top = row[-1][0]
            front, _ = cast(Vector((shoulder.x, -1.5, shoulder.z)), Vector((0, 1, 0)))
            for k in range(1, 8):
                y = top.y + (front.y - top.y) * k / 8
                p, nrm = cast(Vector((shoulder.x, y, 3.0)), Vector((0, 0, -1)))
                if p is not None:
                    path.append((p, nrm))
    pts = [p + nrm * 0.007 for p, nrm in path]
    nrms = [nrm for _, nrm in path]
    # Bridge dips (the open coat front) with a running outward max, then smooth.
    for _ in range(4):
        pts = [pts[0]] + [(pts[i - 1] + pts[i] * 2 + pts[i + 1]) / 4 for i in range(1, len(pts) - 1)] + [pts[-1]]
    width = 0.042
    faces = []
    rv = []
    for i, p in enumerate(pts):
        t = (pts[min(i + 1, len(pts) - 1)] - pts[max(i - 1, 0)]).normalized()
        w = t.cross(nrms[i]).normalized() * width / 2
        rv += [p - w, p + w]
    for i in range(len(pts) - 1):
        faces.append((2 * i, 2 * i + 1, 2 * i + 3, 2 * i + 2))
    obj = weighted_mesh(spec["ribbon"], rv, faces, body_weights(B, rv), spec["color"], B.rig)
    thicken(obj, 0.004)
    obj["layer"] = 8
    return obj


def fit_hat(B, hat):
    """Widen a plugin hat fitted to the bald scalp so its crown clears the hairdo."""
    hair = bpy.data.objects.get(B.obj.name.replace("_body", "_hair"))
    mesh = hat.data
    pts = [v.co for v in mesh.vertices]
    low = min(p.z for p in pts)
    cx = sum(p.x for p in pts) / len(pts)
    cy = sum(p.y for p in pts) / len(pts)
    crown = [((p.x - cx) ** 2 + (p.y - cy) ** 2) ** 0.5 for p in pts if p.z > low + 0.03]
    r_hat = max(crown)
    r_hair = 0.0
    if hair:
        for v in hair.data.vertices:
            p = hair.matrix_world @ v.co
            if low - 0.01 < p.z < low + 0.05:
                r_hair = max(r_hair, ((p.x - cx) ** 2 + (p.y - cy) ** 2) ** 0.5)
    s = max(1.0, (r_hair + 0.006) / r_hat)
    for v in mesh.vertices:
        v.co.x = cx + (v.co.x - cx) * s
        v.co.y = cy + (v.co.y - cy) * s
        v.co.z = low + (v.co.z - low) * (1 + (s - 1) * 0.6)
    mesh.update()
    return round(s, 3)


def bind(obj, rig):
    obj.parent = rig
    obj.matrix_parent_inverse = rig.matrix_world.inverted()
    mod = obj.modifiers.new("Armature", "ARMATURE")
    mod.object = rig


def thicken(obj, thickness):
    mod = obj.modifiers.new("Solid", "SOLIDIFY")
    mod.thickness = thickness
    mod.offset = -1.0
    mod.use_rim = True
    with bpy.context.temp_override(object=obj, active_object=obj):
        bpy.ops.object.modifier_move_to_index(modifier=mod.name, index=0)
        bpy.ops.object.modifier_apply(modifier=mod.name)


def remove_faces(obj, hidden, src_layer=None):
    """Delete faces whose vertices (by body index) are all in `hidden`."""
    bm = bmesh.new()
    bm.from_mesh(obj.data)
    layer = bm.verts.layers.int.get("src") if src_layer else None
    key = (lambda v: v[layer]) if layer else (lambda v: v.index)
    doomed = [f for f in bm.faces if all(key(v) in hidden for v in f.verts)]
    bmesh.ops.delete(bm, geom=doomed, context="FACES")
    bmesh.ops.delete(bm, geom=[v for v in bm.verts if not v.link_faces], context="VERTS")
    bm.to_mesh(obj.data)
    bm.free()
    return len(doomed)


def orient(obj, outward):
    """Flip faces so normals agree with outward(face_center) -> Vector."""
    mesh = obj.data
    score = sum(p.normal.dot(outward(p.center)) for p in mesh.polygons)
    if score < 0:
        for p in mesh.polygons:
            p.flip()
        mesh.update()


def weighted_mesh(name, verts, faces, weights, color, rig, smooth=True):
    """Build a mesh whose vertex i is skinned by weights[i] = {bone_short: w}."""
    mesh = bpy.data.meshes.new(name)
    mesh.from_pydata([tuple(v) for v in verts], [], faces)
    mesh.update()
    obj = bpy.data.objects.new(name, mesh)
    bpy.context.collection.objects.link(obj)
    full = {b.name.split(":")[-1]: b.name for b in rig.data.bones}
    groups = {}
    for i, w in enumerate(weights):
        total = sum(w.values())
        for bone, value in w.items():
            if value <= 0:
                continue
            g = groups.get(bone) or obj.vertex_groups.new(name=full[bone])
            groups[bone] = g
            g.add([i], value / total, "REPLACE")
    mesh.materials.append(material(name + "_" + color, C[color]))
    for p in mesh.polygons:
        p.use_smooth = smooth
    bind(obj, rig)
    return obj


# ------------------------------------------------------------------ hanging garments
def hip_section(B, z, pad):
    """Body cross-section radius per angle at height z (rest pose), padded outward."""
    pts = [p for p, bone in B.points() if abs(p.z - z) < 0.025 and bone.endswith(TORSO + ("UpLeg",))]
    cx = sum(p.x for p in pts) / len(pts)
    cy = sum(p.y for p in pts) / len(pts)
    radius = []
    for k in range(48):
        a = 2 * math.pi * k / 48
        d = Vector((math.sin(a), -math.cos(a), 0))  # k=0 points to the front (-Y)
        best = max((Vector((p.x - cx, p.y - cy, 0)).dot(d) for p in pts), default=0.15)
        radius.append(best + pad)
    return Vector((cx, cy, z)), radius


def stride_weights(side_x, depth):
    """Weights for a hanging vertex: hips at the top, sharing into the nearer thigh lower down."""
    leg = min(0.55, 0.55 * depth)
    left = max(0.0, min(1.0, 0.5 + side_x * 4.0))
    return {"Hips": 1.0 - leg, "LeftUpLeg": leg * left, "RightUpLeg": leg * (1.0 - left)}


def skirt(B, spec):
    """Open or closed flared tube from the waist to `hem` (height in metres above the floor)."""
    top_z = B.z["Spine"] - 0.06 if spec["top"] == "waist" else B.z["Spine1"]
    rows = 12
    center, radius = hip_section(B, top_z, OFFSET * spec["layer"] + 0.004)
    _, hip_r = hip_section(B, B.z["Hips"] - 0.07, OFFSET * spec["layer"] + 0.012)
    gap, back = spec.get("gap", 0.0), spec.get("back_only", False)
    cols = [k for k in range(49)]
    verts, weights = [], []
    for r in range(rows + 1):
        f = r / rows
        z = top_z + (spec["hem"] - top_z) * f
        for k in cols:
            a = 2 * math.pi * k / 48
            # Keep the opening centred on the front; tails keep only the back.
            if back:
                a = math.pi + (a - math.pi) * (math.pi - gap) / math.pi
            elif gap:
                a = gap + (2 * math.pi - 2 * gap) * k / 48
            kk = int(round(a / (2 * math.pi) * 48)) % 48
            base = radius[kk] if f < 0.25 else max(radius[kk], hip_r[kk])
            rad = base + spec["flare"] * f ** 1.3 + (0.012 * math.sin(k * 2.3) * f if spec.get("ragged") else 0)
            d = Vector((math.sin(a), -math.cos(a), 0))
            p = center + d * rad
            p.z = z - (0.035 * (1 + math.sin(k * 1.7)) * (f == 1) if spec.get("ragged") else 0)
            verts.append(p)
            weights.append(stride_weights(p.x - center.x, f))
    faces = []
    w = len(cols)
    for r in range(rows):
        for k in range(w - 1):
            faces.append((r * w + k, r * w + k + 1, (r + 1) * w + k + 1, (r + 1) * w + k))
    if not gap and not back:
        for r in range(rows):
            faces.append((r * w + w - 1, r * w, (r + 1) * w, (r + 1) * w + w - 1))
    obj = weighted_mesh(spec["name"], verts, faces, weights, spec["color"], B.rig)
    orient(obj, lambda c: Vector((c.x - center.x, c.y - center.y, 0)))
    return obj


def apron(B, spec):
    """Front panel from the chest bib to the knee, weighted like a skirt."""
    top = B.z["Spine2"] if spec["top"] == "chest" else B.z["Spine"]
    waist = B.z["Spine"] - 0.04
    _, front = hip_section(B, waist, OFFSET * spec["layer"] + 0.01)
    rows, cols = 14, 9
    verts, weights = [], []
    chest_y = min(B.co[i].y for i in range(len(B.co)) if abs(B.co[i].z - top) < 0.03)
    for r in range(rows + 1):
        z = top + (spec["hem"] - top) * r / rows
        below = z < waist
        half = spec["width"] / 2 * (0.62 if not below else 1.0)
        for c in range(cols):
            x = -half + 2 * half * c / (cols - 1)
            if below:
                y = -front[0] - 0.02 * ((waist - z) / (waist - spec["hem"])) + abs(x) * 0.35
            else:
                y = chest_y - OFFSET * spec["layer"] - 0.012 + abs(x) * 0.15
            verts.append(Vector((x, y, z)))
            depth = max(0.0, (waist - z) / (waist - spec["hem"]))
            weights.append(stride_weights(x, depth) if below else {"Spine2": 0.6, "Spine1": 0.4})
    faces = [(r * cols + c, r * cols + c + 1, (r + 1) * cols + c + 1, (r + 1) * cols + c)
             for r in range(rows) for c in range(cols - 1)]
    obj = weighted_mesh(spec["name"], verts, faces, weights, spec["color"], B.rig)
    orient(obj, lambda c: Vector((0, -1, 0)))
    return obj


def cape(B, spec):
    """Half cape thrown over the left shoulder and down the back."""
    neck = B.z["Neck"]
    rows, cols = 12, 14
    verts, weights = [], []
    back_y = max(p.y for p, bone in B.points() if abs(p.z - (neck - 0.15)) < 0.03 and bone.endswith(TORSO))
    for r in range(rows + 1):
        f = r / rows
        z = neck + 0.02 - f * (neck - B.z["Hips"] + 0.25)
        for c in range(cols):
            g = c / (cols - 1)
            x = -0.05 + 0.33 * g + 0.05 * f
            y = back_y + 0.03 + OFFSET * spec["layer"] + 0.05 * f
            if f < 0.18:
                y = back_y + 0.02 - 0.20 * (1 - f / 0.18) * g  # drape forward over the shoulder top
            verts.append(Vector((x, y, z)))
            weights.append({"Spine2": 1 - f, "LeftShoulder": 0.5 * (1 - f) * g, "Hips": f * 0.8,
                            "LeftUpLeg": f * 0.2})
    faces = [(r * cols + c, r * cols + c + 1, (r + 1) * cols + c + 1, (r + 1) * cols + c)
             for r in range(rows) for c in range(cols - 1)]
    obj = weighted_mesh(spec["name"], verts, faces, weights, spec["color"], B.rig)
    orient(obj, lambda c: Vector((0, 1, 0)))
    return obj


# ------------------------------------------------------------------ props
def prim(kind, **kw):
    bm = bmesh.new()
    if kind == "cyl":
        bmesh.ops.create_cone(bm, cap_ends=True, segments=kw.get("seg", 24), radius1=kw["r1"], radius2=kw["r2"],
                              depth=kw["h"])
    elif kind == "sphere":
        bmesh.ops.create_uvsphere(bm, u_segments=16, v_segments=10, radius=kw["r"])
    elif kind == "box":
        bmesh.ops.create_cube(bm, size=1.0)
        bmesh.ops.scale(bm, vec=kw["size"], verts=bm.verts)
    return bm


def prop_mesh(name, parts, color, rig, bone):
    """parts: list of (bmesh, Matrix). Merged, rigidly skinned to `bone`."""
    bm = bmesh.new()
    for piece, xf in parts:
        piece.transform(xf)
        tmp = bpy.data.meshes.new("tmp")
        piece.to_mesh(tmp)
        bm.from_mesh(tmp)
        bpy.data.meshes.remove(tmp)
        piece.free()
    verts = [v.co.copy() for v in bm.verts]
    faces = [[v.index for v in f.verts] for f in bm.faces]
    bm.free()
    colors = color if isinstance(color, dict) else None
    obj = weighted_mesh(name, verts, faces, [{bone: 1.0}] * len(verts), color if not colors else "black", rig, False)
    return obj


def head_frame(B):
    """Crown point and hat radius measured over scalp and hair, so hats sit on the hairdo."""
    pts = [B.co[i] for i in range(len(B.co)) if B.bone[i].endswith("Head")]
    hair = bpy.data.objects.get(B.obj.name.replace("_body", "_hair"))
    if hair:
        pts += [hair.matrix_world @ v.co for v in hair.data.vertices]
    crown = max(p.z for p in pts)
    band = [p for p in pts if crown - 0.075 < p.z < crown - 0.035]
    cy = sum(p.y for p in band) / len(band)
    radius = max(Vector((p.x, p.y - cy)).length for p in band)
    # Loose hair (braids, long hair) spreads below the crown; a hat hugs the skull, not the spread.
    scalp = [B.co[i] for i in range(len(B.co)) if B.bone[i].endswith("Head") and crown - 0.11 < B.co[i].z < crown - 0.05]
    skull = max(Vector((p.x, p.y - cy)).length for p in scalp) if scalp else radius
    return Vector((0.0, cy, crown)), min(radius, skull + 0.022)


def props(B, spec):
    kind, color, rig = spec["prop"], spec["color"], B.rig
    crown, r = head_frame(B)
    T = Matrix.Translation
    if kind == "flat_cap":
        # Soft crown pulled forward onto a short peak, sitting on the hair line.
        return [prop_mesh("Cap", [(prim("sphere", r=1.0), T(crown + Vector((0, -0.012, -0.035))) @ Matrix.Diagonal((r + 0.012, r + 0.026, 0.055, 1))),
                                  (prim("cyl", r1=r + 0.01, r2=r + 0.01, h=0.018, seg=32), T(crown + Vector((0, 0.0, -0.058)))),
                                  (prim("cyl", r1=0.07, r2=0.07, h=0.01, seg=20), T(crown + Vector((0, -r - 0.025, -0.06))) @ Matrix.Rotation(-0.18, 4, "X") @ Matrix.Diagonal((1.2, 0.75, 1, 1)))],
                          color, rig, "Head")]
    if kind == "newsboy_cap":
        return [prop_mesh("Cap", [(prim("sphere", r=1.0), T(crown + Vector((0, 0.0, -0.045))) @ Matrix.Diagonal((r + 0.028, r + 0.032, 0.075, 1))),
                                  (prim("cyl", r1=r + 0.008, r2=r + 0.008, h=0.02, seg=32), T(crown + Vector((0, 0.0, -0.06)))),
                                  (prim("cyl", r1=0.065, r2=0.065, h=0.01, seg=20), T(crown + Vector((0, -r - 0.022, -0.066))) @ Matrix.Rotation(-0.25, 4, "X") @ Matrix.Diagonal((1.15, 0.7, 1, 1)))],
                          color, rig, "Head")]
    if kind == "plumed_hat":
        hat = prop_mesh("Hat", [(prim("cyl", r1=r + 0.15, r2=r + 0.15, h=0.012, seg=40), T(crown + Vector((0, 0.0, -0.05))) @ Matrix.Rotation(0.10, 4, "X")),
                                (prim("cyl", r1=r + 0.008, r2=r - 0.012, h=0.12, seg=32), T(crown + Vector((0, 0.0, 0.01))))],
                        color, rig, "Head")
        plume = prop_mesh("Plume", [(prim("sphere", r=0.05), T(crown + Vector((r * 0.8, 0.07, 0.07))) @ Matrix.Rotation(-0.7, 4, "Y") @ Matrix.Diagonal((0.55, 0.7, 3.6, 1)))],
                          "feather", rig, "Head")
        return [hat, plume]
    if kind == "goggles":
        parts = []
        for x in (-0.04, 0.04):
            parts.append((prim("cyl", r1=0.028, r2=0.028, h=0.025, seg=16), T(crown + Vector((x, -r - 0.004, -0.072))) @ Matrix.Rotation(math.pi / 2 - 0.35, 4, "X")))
        parts.append((prim("cyl", r1=r + 0.006, r2=r + 0.006, h=0.016, seg=32), T(crown + Vector((0, 0.0, -0.075)))))
        return [prop_mesh("Goggles", parts, color, rig, "Head")]
    if kind == "tool_belt":
        z = B.z["Spine"] - 0.05
        center, radius = hip_section(B, z, OFFSET * 5)
        r = sum(radius) / len(radius)
        parts = [(prim("cyl", r1=r, r2=r, h=0.05, seg=40), T(center))]
        for x, h in ((0.13, 0.14), (-0.14, 0.11), (0.05, 0.10)):
            parts.append((prim("box", size=(0.07, 0.045, h)), T(center + Vector((x, -r + 0.01, -h / 2)))))
        return [prop_mesh("ToolBelt", parts, color, rig, "Hips")]
    if kind == "satchel":
        z = B.z["Hips"] - 0.04
        side = max(p.x for p, bone in B.points() if abs(p.z - z) < 0.03 and bone.endswith(("Hips", "UpLeg")))
        bag = prim("box", size=(0.07, 0.24, 0.19))
        flap = prim("box", size=(0.075, 0.245, 0.06))
        x = side + OFFSET * 7 + 0.035
        return [prop_mesh("Satchel", [(bag, T(Vector((x, 0.0, z)))), (flap, T(Vector((x + 0.004, 0.0, z + 0.07))))],
                          color, rig, "Hips")]
    if kind == "lute":
        back = max(p.y for p, bone in B.points() if abs(p.z - B.z["Spine1"]) < 0.03 and bone.endswith(TORSO)) + OFFSET * 8 + 0.05
        tilt = Matrix.Rotation(0.6, 4, "Y")
        body = prim("sphere", r=0.16)
        neck = prim("box", size=(0.05, 0.025, 0.42))
        return [prop_mesh("Lute", [(body, T(Vector((-0.06, back + 0.02, B.z["Spine"] - 0.02))) @ tilt @ Matrix.Diagonal((1.0, 0.45, 1.25, 1))),
                                   (neck, T(Vector((0.08, back - 0.01, B.z["Spine2"] + 0.12))) @ tilt)],
                          color, rig, "Spine1")]
    raise KeyError(kind)


def foot_hulls(B, obj, cover, offset):
    """Replace the toe-shaped foot of a boot shell with a smooth convex hull per foot and a flat sole."""
    ids_all = [i for i in cover if B.bone[i].endswith(("Foot", "ToeBase")) or (B.bone[i].endswith("Leg") and B.t[i] > 0.93)]
    names = {g.index: g.name for g in B.obj.vertex_groups}
    hulls = []
    for sign in (1, -1):
        ids = [i for i in ids_all if B.co[i].x * sign > 0]
        pts = [B.co[i] + B.normal[i] * (offset + 0.004) for i in ids]
        pts += [Vector((p.x, p.y, 0.0)) for p in pts if p.z < 0.035]
        bm = bmesh.new()
        for p in pts:
            bm.verts.new(p)
        hull = bmesh.ops.convex_hull(bm, input=bm.verts)
        loose = list({g for g in hull["geom_interior"] + hull["geom_unused"] if isinstance(g, bmesh.types.BMVert)})
        bmesh.ops.delete(bm, geom=loose, context="VERTS")
        bm.verts.index_update()
        verts = [v.co.copy() for v in bm.verts]
        faces = [[v.index for v in f.verts] for f in bm.faces]
        bm.free()
        weights = []
        for v in verts:
            j = min(ids, key=lambda i: (B.co[i] - v).length_squared)
            weights.append(dict(B.weights[j]))
        h = weighted_mesh(obj.name + ("_L" if sign > 0 else "_R"), verts, faces, weights, "boot", B.rig, False)
        h.data.materials.clear()
        h.data.materials.append(obj.data.materials[0])
        hulls.append(h)
    # The hull replaces the toe-shaped shell below the ankle.
    remove_faces(obj, {i for i in cover if B.bone[i].endswith(("Foot", "ToeBase"))}, src_layer=True)
    return hulls


# ------------------------------------------------------------------ plugin garments
def dominant(obj, rig):
    names = {g.index: g.name for g in obj.vertex_groups}
    out = []
    for v in obj.data.vertices:
        best = max(((g.weight, names[g.group]) for g in v.groups if names[g.group] in rig.data.bones), default=(0, ""))
        out.append(best[1].split(":")[-1])
    return out


def components(bm):
    seen, comps = set(), []
    for v in bm.verts:
        if v.index in seen:
            continue
        stack, comp = [v], []
        seen.add(v.index)
        while stack:
            x = stack.pop()
            comp.append(x)
            for e in x.link_edges:
                y = e.other_vert(x)
                if y.index not in seen:
                    seen.add(y.index)
                    stack.append(y)
        comps.append(comp)
    return comps


def drop_socks(obj):
    """MakeHuman shoes ship with socks; the trousers already cover the ankle."""
    bm = bmesh.new()
    bm.from_mesh(obj.data)
    doomed = [v for comp in components(bm) if max(v.co.z for v in comp) > 0.15 for v in comp]
    bmesh.ops.delete(bm, geom=doomed, context="VERTS")
    bm.to_mesh(obj.data)
    bm.free()


def recolor(obj, spec):
    """Cluster the garment texture into len(colors) regions and give each a flat palette colour."""
    colors = spec["colors"]
    mesh = obj.data
    mats = [material(f"{obj.name}_{c}", C[c]) for c in colors]
    if len(colors) > 1:
        tree = obj.active_material.node_tree
        images = [n.image for n in tree.nodes if n.type == "TEX_IMAGE" and n.image]
        image = next((i for i in images if "diffuse" in i.name.lower()), images[0])
        w, h = image.size
        px = np.empty(w * h * 4, dtype=np.float32)
        image.pixels.foreach_get(px)
        px = px.reshape(h, w, 4)[:, :, :3]
        uv = mesh.uv_layers.active.data
        rgb, z = [], []
        for p in mesh.polygons:
            u = sum(uv[k].uv.x for k in p.loop_indices) / p.loop_total
            v = sum(uv[k].uv.y for k in p.loop_indices) / p.loop_total
            rgb.append(px[min(h - 1, int((v % 1.0) * h)), min(w - 1, int((u % 1.0) * w))])
            z.append((obj.matrix_world @ p.center).z)
        # One UV island is one cut of cloth: average its colour so prints and noise cannot split it.
        island = uv_islands(mesh)
        rgb, z = np.array(rgb), np.array(z)
        for ids in island:
            rgb[ids] = rgb[ids].mean(0)
        lum = rgb @ np.array([0.2126, 0.7152, 0.0722])
        k = len(colors)
        centers = np.array([rgb[np.argsort(lum)[int(len(lum) * (j + 0.5) / k)]] for j in range(k)])
        for _ in range(20):
            label = np.argmin(((rgb[:, None, :] - centers[None]) ** 2).sum(-1), axis=1)
            centers = np.array([rgb[label == j].mean(0) if (label == j).any() else centers[j] for j in range(k)])
        if spec.get("order") == "z":
            key = [-z[label == j].mean() if (label == j).any() else 0 for j in range(k)]
        else:
            key = [lum[label == j].mean() if (label == j).any() else 0 for j in range(k)]
        rank = {j: r for r, j in enumerate(np.argsort(key))}
    mesh.materials.clear()
    for m in mats:
        mesh.materials.append(m)
    for n, p in enumerate(mesh.polygons):
        p.material_index = rank[int(label[n])] if len(colors) > 1 else 0
        p.use_smooth = True


def uv_islands(mesh):
    """Face index lists of the mesh's UV islands (faces sharing an edge with matching UVs)."""
    uv = mesh.uv_layers.active.data
    key = {}
    for p in mesh.polygons:
        loops = list(p.loop_indices)
        for a, b in zip(loops, loops[1:] + loops[:1]):
            va, vb = mesh.loops[a].vertex_index, mesh.loops[b].vertex_index
            ua, ub = tuple(round(x, 5) for x in uv[a].uv), tuple(round(x, 5) for x in uv[b].uv)
            edge = (min(va, vb), max(va, vb))
            pair = (ua, ub) if va < vb else (ub, ua)
            key.setdefault((edge, pair), []).append(p.index)
    parent = list(range(len(mesh.polygons)))

    def find(x):
        while parent[x] != x:
            parent[x] = parent[parent[x]]
            x = parent[x]
        return x

    for faces in key.values():
        for f in faces[1:]:
            parent[find(f)] = find(faces[0])
    groups = {}
    for f in range(len(parent)):
        groups.setdefault(find(f), []).append(f)
    return list(groups.values())


def limb_class(bone):
    side = "L" if bone.startswith("Left") else "R" if bone.startswith("Right") else ""
    if "Hand" in bone or "Arm" in bone:
        return side + "arm"
    if "Leg" in bone or "Foot" in bone or "Toe" in bone:
        return side + "leg"
    return "torso"


def measure_under(B, cloth, reach=0.06, keep_under=False):
    """For every body vertex, how far out along its normal the plugin cloth reaches (same limb only).

    keep_under=True only rebuilds the cloth tree (after hidden cloth was deleted)."""
    verts, faces, face_cls = [], [], []
    if not keep_under:
        B.cloth = []
    for obj in cloth:
        bones = dominant(obj, B.rig)
        base = len(verts)
        verts += [obj.matrix_world @ v.co for v in obj.data.vertices]
        for p in obj.data.polygons:
            faces.append(tuple(base + k for k in p.vertices))
            face_cls.append(limb_class(bones[p.vertices[0]]))
        if not keep_under:
            B.cloth += [(obj.matrix_world @ v.co, bones[v.index]) for v in obj.data.vertices]
    if not faces:
        B.cloth_tree = None
        return
    tree = BVHTree.FromPolygons(verts, faces)
    B.cloth_tree, B.cloth_cls = tree, face_cls
    if keep_under:
        return
    raw = [0.0] * len(B.co)
    for i, (p, n) in enumerate(zip(B.co, B.normal)):
        mine = limb_class(B.bone[i])
        start, far = p + n * 0.0005, 0.0
        while True:
            hit, _, f, d = tree.ray_cast(start, n, reach - far)
            if hit is None:
                break
            other = face_cls[f]
            if other == mine or "torso" in (mine, other) and other.endswith("leg") | mine.endswith("leg"):
                far = (hit - p).length
            start = hit + n * 0.0005
            if (start - p).length >= reach:
                break
        raw[i] = far
    # Dilate then soften so the outer layer does not ripple over seams and buttons.
    for _ in range(2):
        raw = [max([raw[i]] + [raw[j] for j in B.neighbors[i]]) for i in range(len(raw))]
    for _ in range(3):
        raw = [(raw[i] + sum(raw[j] for j in B.neighbors[i])) / (1 + len(B.neighbors[i])) for i in range(len(raw))]
    B.under = raw


def hide_cloth(B, obj, hidden):
    """Delete plugin faces whose every vertex sits over a body vertex hidden by a closed outer shell."""
    if not hidden:
        return 0
    tree = BVHTree.FromPolygons(B.co, [tuple(p.vertices) for p in B.obj.data.polygons])
    bones = dominant(obj, B.rig)
    polys = B.obj.data.polygons
    flag = []
    for v in obj.data.vertices:
        p = obj.matrix_world @ v.co
        hit = tree.find_nearest(p, 0.08)
        mine = limb_class(bones[v.index])
        other = limb_class(B.bone[polys[hit[2]].vertices[0]]) if hit[0] is not None else None
        if other is None or (mine != other and "torso" not in (mine, other)):
            flag.append(False)
            continue
        flag.append(all(k in hidden for k in polys[hit[2]].vertices))
    bm = bmesh.new()
    bm.from_mesh(obj.data)
    doomed = [f for f in bm.faces if all(flag[v.index] for v in f.verts)]
    bmesh.ops.delete(bm, geom=doomed, context="FACES")
    bmesh.ops.delete(bm, geom=[v for v in bm.verts if not v.link_faces], context="VERTS")
    bm.to_mesh(obj.data)
    bm.free()
    return len(doomed)


def clear_cloth(B, obj, gap, rounds=3, cap=0.012):
    """Push a modelled shell out until it sits `gap` outside the plugin cloth of the same limb."""
    tree = getattr(B, "cloth_tree", None)
    if tree is None:
        return 0
    mesh = obj.data
    src = mesh.attributes.get("src")
    ids = [d.value for d in src.data] if src else list(range(len(mesh.vertices)))
    nbr = [[] for _ in mesh.vertices]
    for e in mesh.edges:
        a, b = e.vertices
        nbr[a].append(b)
        nbr[b].append(a)
    moved = 0
    for _ in range(rounds):
        push = []
        for v, i in zip(mesh.vertices, ids):
            n, mine, need = B.normal[i], limb_class(B.bone[i]), 0.0
            for hit in tree.find_nearest_range(v.co, 0.05):
                other = B.cloth_cls[hit[2]]
                if other != mine and not ("torso" in (mine, other) and (other.endswith("leg") or mine.endswith("leg"))):
                    continue
                s = (v.co - hit[0]).dot(n)
                need = max(need, gap - s)
            push.append(min(need, cap))
        if not any(x > 0 for x in push):
            break
        moved = sum(1 for x in push if x > 0)
        # Spread each push over its neighbours so the shell lifts as cloth, not as spikes.
        for _ in range(2):
            push = [max([push[k]] + [0.6 * push[j] for j in nbr[k]]) for k in range(len(push))]
        for v, i, d in zip(mesh.vertices, ids, push):
            v.co += B.normal[i] * d
    mesh.update()
    return moved


def trim_hair(B, hats):
    """Delete hair faces that a hat covers or that would poke through its crown."""
    hair = bpy.data.objects.get(B.obj.name.replace("_body", "_hair"))
    if not hair or not hats:
        return 0
    removed = 0
    for hat in hats:
        pts = [hat.matrix_world @ v.co for v in hat.data.vertices]
        tree = BVHTree.FromPolygons(pts, [tuple(p.vertices) for p in hat.data.polygons])
        low = min(p.z for p in pts)
        cx = sum(p.x for p in pts) / len(pts)
        cy = sum(p.y for p in pts) / len(pts)
        crown = [p for p in pts if p.z > low + 0.03]
        rad = max(((p.x - cx) ** 2 + (p.y - cy) ** 2) ** 0.5 for p in crown) if crown else 0.0

        def covered(p):
            hit = tree.find_nearest(p, 0.08)
            inside = hit[0] is not None and (p - hit[0]).dot(hit[1]) < 0
            return inside or (p.z > low + 0.025 and ((p.x - cx) ** 2 + (p.y - cy) ** 2) ** 0.5 < rad)

        bm = bmesh.new()
        bm.from_mesh(hair.data)
        flag = {v.index: covered(hair.matrix_world @ v.co) for v in bm.verts}
        doomed = [f for f in bm.faces if all(flag[v.index] for v in f.verts)]
        removed += len(doomed)
        bmesh.ops.delete(bm, geom=doomed, context="FACES")
        bmesh.ops.delete(bm, geom=[v for v in bm.verts if not v.link_faces], context="VERTS")
        bm.to_mesh(hair.data)
        bm.free()
    return removed


# ------------------------------------------------------------------ dressing
def dress(hero_id, body, rig, plugin):
    """plugin: {suit id: fitted MPFB clothes object}. Returns every garment object.

    Order matters for clipping: plugin cloth is measured, modelled shells are cut over it, the cloth a
    closed shell hides is deleted, and only then are shells pushed clear of the cloth that remains.
    """
    B = Body(body, rig)
    pieces, covers, hats, cloth = [], [], [], []
    for item in OUTFITS[hero_id]:
        if isinstance(item, dict) and "suit" in item:
            obj = plugin[item["suit"]]
            if item["suit"].startswith("shoes"):
                drop_socks(obj)
            recolor(obj, item)
            obj["layer"] = 1
            pieces.append(obj)
            (hats if item["suit"].startswith("fedora") else cloth).append(obj)
    measure_under(B, cloth)
    for item in OUTFITS[hero_id]:
        if isinstance(item, dict) and ("suit" in item or "ribbon" in item):
            continue
        if isinstance(item, tuple):
            name, kind, layer, color = item
            cover = region(B, kind)
            obj = cut_shell(B, name, cover, OFFSET * layer, color)
            if kind in ("boots", "work_boots", "tall_boots", "shoes"):
                for h in foot_hulls(B, obj, cover, OFFSET * layer):
                    h["layer"] = layer
                    pieces.append(h)
            obj["layer"] = layer
            pieces.append(obj)
            covers.append((layer, kind, cover, obj))
        elif "kind" in item:
            builder = {"skirt": skirt, "apron": apron, "cape": cape}[item["kind"]]
            obj = builder(B, item)
            obj["layer"] = item["layer"]
            pieces.append(obj)
        else:
            made = props(B, item)
            pieces.extend(made)
            hats += [o for o in made if o.name.startswith(("Cap", "Hat"))]
    # Skin, plugin cloth and inner shells that a closed outer layer hides completely are removed.
    closed = [(layer, kind, interior(B, cover, 2)) for layer, kind, cover, _ in covers
              if kind not in ("braces", "sash", "collar", "scarf", "high_collar", "strap")]
    hidden_body = set().union(*(c for _, _, c in closed)) if closed else set()
    over_cloth = set().union(*(c for l, _, c in closed if l > 1)) if closed else set()
    for obj in cloth:
        print("HIDE_CLOTH", obj.name, len(obj.data.polygons), hide_cloth(B, obj, over_cloth), len(over_cloth))
    measure_under(B, cloth, keep_under=True)
    for layer, kind, cover, obj in covers:
        if layer > 1:
            clear_cloth(B, obj, OFFSET * (layer - 1))
        if obj.name.split(".")[0] in SOLID_LAYERS:
            thicken(obj, 0.004)
    remove_faces(body, hidden_body)
    for layer, kind, cover, obj in covers:
        above = set().union(*(c for l, _, c in closed if l > layer)) if closed else set()
        if above:
            remove_faces(obj, above & cover, src_layer=True)
    for obj in hats:
        if "fedora" in obj.name:
            fit_hat(B, obj)
    outer = [o for o in pieces if "layer" in o.keys() and o not in hats]
    for item in OUTFITS[hero_id]:
        if isinstance(item, dict) and "ribbon" in item:
            pieces.append(ribbon(B, item, outer))
    trim_hair(B, hats)
    return pieces


# ------------------------------------------------------------------ clipping audit
def _surface(obj):
    dg = bpy.context.evaluated_depsgraph_get()
    ev = obj.evaluated_get(dg)
    mesh = ev.to_mesh()
    verts = [obj.matrix_world @ v.co for v in mesh.vertices]
    polys = [tuple(p.vertices) for p in mesh.polygons]
    ev.to_mesh_clear()
    return verts, polys


def _poking(tree, pts, ids, reach, tolerance):
    out = []
    for i in ids:
        hit = tree.find_nearest(pts[i], reach)
        if hit[0] is not None and (pts[i] - hit[0]).dot(hit[1]) > tolerance:
            out.append(i)
    return out


def audit(body, garments, rig, clips, frames=8, reach=0.05, tolerance=0.0015):
    """Count inner-layer vertices that the rest pose encloses but a clip pushes out of an outer layer.

    Candidates are the inner vertices lying inside (or on) an outer layer in the rest pose; a frame
    counts a candidate when it is more than `tolerance` outside the nearest outer surface.
    """
    layered = sorted([(o["layer"], o) for o in garments if "layer" in o], key=lambda x: x[0])
    inner_all = [(0, body)] + layered
    rig.data.pose_position = "REST"
    rest = {o.name: _surface(o) for _, o in inner_all}
    rig.data.pose_position = "POSE"
    candidates = {}
    for li, inner in inner_all:
        pts = rest[inner.name][0]
        for lo, outer in layered:
            if lo <= li or not rest[outer.name][1]:
                continue
            tree = BVHTree.FromPolygons(*rest[outer.name])
            enclosed = []
            for i, p in enumerate(pts):
                hit = tree.find_nearest(p, reach)
                if hit[0] is not None and (p - hit[0]).dot(hit[1]) <= 0.0:
                    enclosed.append(i)
            if enclosed:
                candidates[(inner.name, outer.name)] = enclosed
    result = {}
    for clip in clips:
        action = bpy.data.actions[clip]
        rig.animation_data.action = action
        start, end = action.frame_range
        worst, detail = 0, {}
        for k in range(frames):
            frame = start + (end - start) * k / frames
            bpy.context.scene.frame_set(int(frame), subframe=frame % 1)
            surfaces = {o.name: _surface(o) for _, o in inner_all}
            trees = {}
            count = 0
            for (inner, outer), ids in candidates.items():
                if outer not in trees:
                    trees[outer] = BVHTree.FromPolygons(*surfaces[outer])
                n = len(_poking(trees[outer], surfaces[inner][0], ids, reach, tolerance))
                if n:
                    key = f"{inner}>{outer}"
                    detail[key] = max(detail.get(key, 0), n)
                count += n
            worst = max(worst, count)
        result[clip] = {"worst_frame": worst, "pairs": detail}
    rig.animation_data.action = bpy.data.actions["idle"]
    return result
