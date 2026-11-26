"""Build the five hero characters with MPFB2 and bake CC0 motion onto them.

Run inside Blender 4.2 with MPFB 2.0.18 (isolated profile, see tools/cast/README.md):
    blender -b --python tools/cast/build_heroes.py -- --system-pack <system_cc0.zip>
        --motion <AnimationLibrary_Godot_Standard.glb> --out assets/characters/heroes [--only detective]

Each hero is one GLB: MPFB2 body (6.5 heads), Mixamo-named rig, modelled garments and hair,
and baked clips named after the game's playback protocol (idle, walk, run, interact, ...).
"""
import argparse
import hashlib
import json
import math
import os
import sys
import zipfile
from pathlib import Path

import bpy
import bmesh
from mathutils import Matrix, Quaternion, Vector
from mathutils.bvhtree import BVHTree

from bl_ext.user_default.mpfb.entities.objectproperties import HumanObjectProperties
from bl_ext.user_default.mpfb.services.humanservice import HumanService
from bl_ext.user_default.mpfb.services.locationservice import LocationService
from bl_ext.user_default.mpfb.services.targetservice import TargetService

sys.path.append(str(Path(__file__).resolve().parent))
import wardrobe  # noqa: E402  (garment modelling, shares this Blender session)
sys.path.append(str(Path(__file__).resolve().parent / "fit"))
import face_paint  # noqa: E402  (painting projected onto the face texture)

SYSTEM_SHA = "b542127a8e25547c7c29c19f2d1d2adb9a664c80396ecd694095dbc8028a0107"
RATIO = 6.5

# Age macro: 0.1875 = 11 y, 0.5 = 25 y, 1.0 = 90 y.
def age(years):
    return 0.1875 + (years - 11) / 14 * 0.3125 if years <= 25 else 0.5 + (years - 25) / 65 * 0.5

HEROES = {
    "detective": dict(eyes="grey", height=1.76, macro=dict(gender=1.0, age=age(20), muscle=0.45, weight=0.40, proportions=0.6),
                      hair="short02", hair_color=(0.30, 0.17, 0.10), brows="eyebrow010", skin=(0.84, 0.64, 0.52)),
    "hale": dict(eyes="grey", height=1.80, macro=dict(gender=1.0, age=age(38), muscle=0.72, weight=0.62, proportions=0.45),
                 hair="short02", hair_color=(0.30, 0.22, 0.15), brows="eyebrow001", skin=(0.86, 0.63, 0.50)),
    "quer": dict(eyes="brown", height=1.56, macro=dict(gender=0.0, age=age(17), muscle=0.40, weight=0.32, proportions=0.55),
                 hair="ponytail01", hair_color=(0.10, 0.08, 0.07), brows="eyebrow006", skin=(0.90, 0.69, 0.57)),
    "lucian": dict(eyes="bluegreen", height=1.86, macro=dict(gender=1.0, age=age(28), muscle=0.40, weight=0.36, proportions=0.75),
                   hair="long01", hair_color=(0.66, 0.36, 0.14), brows="eyebrow003", skin=(0.92, 0.73, 0.60)),
    "demon": dict(height=1.98, macro=dict(gender=0.85, age=age(45), muscle=0.30, weight=0.08, proportions=1.0),
                  hair="short01", hair_color=(0.03, 0.03, 0.035), brows="eyebrow012", skin=(0.62, 0.63, 0.64)),
}

# Heroes with a target painting (tools/cast/reference) carry a landmark fit from tools/cast/fit/fit_heroes.py:
# race and age macros plus body-proportion and face-shape targets. Their head ratio follows the painting.
FIT_DIR = Path(__file__).resolve().parent / "fit"


def fitted(hero_id):
    path = FIT_DIR / f"{hero_id}.json"
    return json.loads(path.read_text()) if path.exists() else None

# Game clip -> UAL action, with per-hero overrides that carry each character's manner.
CLIPS = {"idle": "Idle_Loop", "walk": "Walk_Loop", "run": "Jog_Fwd_Loop", "interact": "Interact",
         "signal": "Idle_Talking_Loop", "examine": "Crouch_Idle_Loop", "listen": "Idle_Loop"}
OVERRIDES = {
    "hale": {"ward": "Idle_Torch_Loop", "gate_effort": "Push_Loop", "watch_plate": "Idle_Loop",
             "peek": "Crouch_Idle_Loop", "repair": "Fixing_Kneeling"},
    "quer": {"run": "Sprint_Loop", "crouch_walk": "Crouch_Fwd_Loop"},
    "lucian": {"idle": "Idle_Talking_Loop", "walk": "Walk_Formal_Loop", "perform": "Dance_Loop"},
    "demon": {"walk": "Walk_Formal_Loop", "run": "Walk_Formal_Loop"},
}

# Standing clips: UAL idles use a wide ready stance; ease the legs toward a calm upright stance.
CALM = {"idle", "listen", "signal", "ward", "watch_plate"}
CALM_LEGS = 0.65
LEG_BONES = ("UpLeg", "Leg", "Foot", "ToeBase")
# UAL idles hang the head ~15 degrees forward; standing clips keep it near level, as the paintings do.
CALM_HEAD = 0.85
HEAD_BONES = ("Neck", "Head")

MAP = {"Hips": "DEF-hips", "Spine": "DEF-spine.001", "Spine1": "DEF-spine.002", "Spine2": "DEF-spine.003",
       "Neck": "DEF-neck", "Head": "DEF-head"}
for side, s in (("Left", "L"), ("Right", "R")):
    MAP.update({f"{side}Shoulder": f"DEF-shoulder.{s}", f"{side}Arm": f"DEF-upper_arm.{s}",
                f"{side}ForeArm": f"DEF-forearm.{s}", f"{side}Hand": f"DEF-hand.{s}",
                f"{side}UpLeg": f"DEF-thigh.{s}", f"{side}Leg": f"DEF-shin.{s}",
                f"{side}Foot": f"DEF-foot.{s}", f"{side}ToeBase": f"DEF-toe.{s}"})
    for finger, src in (("Thumb", "thumb"), ("Index", "f_index"), ("Middle", "f_middle"),
                        ("Ring", "f_ring"), ("Pinky", "f_pinky")):
        for k in (1, 2, 3):
            MAP[f"{side}Hand{finger}{k}"] = f"DEF-{src}.0{k}.{s}"


def activate(obj):
    bpy.ops.object.select_all(action="DESELECT")
    obj.select_set(True)
    bpy.context.view_layer.objects.active = obj


def evaluated(obj):
    bpy.context.view_layer.update()
    return obj.evaluated_get(bpy.context.evaluated_depsgraph_get()).data


def fit(body, height, ratio=RATIO):
    """Solve the height slider and head-scale key so stature = height and stature/head = ratio.

    With ratio=None the body keeps its fitted proportions and is only scaled to the stature."""
    metadata = Path(LocationService.get_mpfb_data("mesh_metadata")) / "hm08_config.json"
    head = json.loads(metadata.read_text())["dimensions"]["Head"]
    crown, chin = head["zmax"], head["zmin"]
    group = body.vertex_groups["body"].index
    ids = [v.index for v in body.data.vertices if any(g.group == group for g in v.groups)]

    def measure():
        v = evaluated(body).vertices
        sole = min(v[i].co.z for i in ids)
        return {"sole": sole, "height": v[crown].co.z - sole, "head": v[crown].co.z - v[chin].co.z}

    if ratio is None:
        result, slider = measure(), None
        key = None
    else:
        result, slider, key = solve_ratio(body, height, ratio, measure)
    # The slider range cannot reach every stature at 6.5 heads; uniform scale closes the gap.
    uniform = height / result["height"]
    activate(body)
    body.location.z = -result["sole"] * uniform * body.scale.z
    body.scale *= uniform
    bpy.ops.object.transform_apply(location=True, rotation=False, scale=True)
    final = measure()
    assert abs(final["height"] - height) < 0.003 and abs(final["sole"]) < 0.002, final
    return {"height_m": round(final["height"], 4), "head_ratio": round(final["height"] / final["head"], 4),
            "height_slider": slider and round(slider, 4), "head_key": key and round(key.value, 4),
            "uniform_scale": round(uniform, 4)}


def solve_ratio(body, height, ratio, measure):
    target = "head-scale-vert-incr"
    TargetService.load_target(body, TargetService.target_full_path(target), name=target)
    key = body.data.shape_keys.key_blocks[target]
    low, high = 0.0, 1.0
    for _ in range(16):
        slider = (low + high) / 2
        HumanObjectProperties.set_value("height", slider, entity_reference=body)
        TargetService.reapply_macro_details(body, remove_zero_weight_targets=False)
        key.slider_min, key.slider_max = -3.0, 3.0
        key.value = -1.0
        a = measure()
        key.value = 1.0
        b = measure()
        f0, f1 = a["height"] - ratio * a["head"], b["height"] - ratio * b["head"]
        key.value = -1.0 + 2.0 * f0 / (f0 - f1)
        result = measure()
        if result["height"] < height:
            low = slider
        else:
            high = slider
    assert abs(result["height"] / result["head"] - ratio) < 0.01, result
    return result, slider, key


def flat_material(name, color, roughness=0.8):
    color = wardrobe.linear(color)
    mat = bpy.data.materials.new(name)
    mat.use_nodes = True
    shader = mat.node_tree.nodes["Principled BSDF"]
    shader.inputs["Base Color"].default_value = (*color, 1.0)
    shader.inputs["Roughness"].default_value = roughness
    mat.diffuse_color = (*color, 1.0)
    return mat


def eye_material(png):
    """MakeHuman CC0 eye texture: white sclera, coloured iris, pupil (the eyes read as open in toon)."""
    mat = bpy.data.materials.new("Eyes")
    mat.use_nodes = True
    nodes = mat.node_tree.nodes
    tex = nodes.new("ShaderNodeTexImage")
    tex.image = bpy.data.images.load(str(png))
    shader = nodes["Principled BSDF"]
    mat.node_tree.links.new(tex.outputs["Color"], shader.inputs["Base Color"])
    shader.inputs["Roughness"].default_value = 0.3
    return mat


def paint(obj, mat):
    obj.data.materials.clear()
    obj.data.materials.append(mat)
    for p in obj.data.polygons:
        p.material_index = 0
        p.use_smooth = True


def solidify(obj, thickness):
    mod = obj.modifiers.new("Solid", "SOLIDIFY")
    mod.thickness = thickness
    mod.offset = 1.0
    mod.use_even_offset = False
    activate(obj)
    bpy.ops.object.modifier_apply(modifier=mod.name)


def bake_asset(obj):
    """Apply MPFB fitting modifiers but keep the armature binding."""
    activate(obj)
    for mod in list(obj.modifiers):
        if mod.type != "ARMATURE":
            bpy.ops.object.modifier_apply(modifier=mod.name)


def extract(pack, asset_root, prefixes):
    with zipfile.ZipFile(pack) as z:
        for entry in z.namelist():
            if entry.startswith(prefixes) and not entry.endswith("/"):
                z.extract(entry, asset_root)


# ---------------------------------------------------------------- motion retarget
def load_motion(path):
    before = set(bpy.data.objects)
    bpy.ops.import_scene.gltf(filepath=str(path))
    new = [o for o in bpy.data.objects if o not in before]
    src = next(o for o in new if o.type == "ARMATURE")
    for o in new:
        if o is not src:
            bpy.data.objects.remove(o, do_unlink=True)
    src.animation_data_create()
    return src


def world_rot(rig, m):
    return (rig.matrix_world.to_3x3().normalized() @ m.to_3x3()).normalized()


def retarget(src, rig, clips, fps):
    """Bake each UAL action onto the Mixamo rig, keyed as local quaternions plus hips travel."""
    bones = [b for b in rig.data.bones]  # parents precede children
    names = {b.name.split(":")[-1]: b.name for b in bones}
    rest_t = {b.name: world_rot(rig, b.matrix_local) for b in bones}
    src.animation_data.action = None
    bpy.context.view_layer.update()
    rest_s = {pb.name: world_rot(src, pb.bone.matrix_local) for pb in src.pose.bones}
    # Align each target bone's direction to the source rest direction (T-pose), keeping its roll.
    offset = {}
    for short, src_name in MAP.items():
        t = names.get(short)
        if t is None or src_name not in rest_s:
            continue
        b = rig.data.bones[t]
        sb = src.data.bones[src_name]
        dt = (rig.matrix_world.to_3x3() @ (b.tail_local - b.head_local)).normalized()
        ds = (src.matrix_world.to_3x3() @ (sb.tail_local - sb.head_local)).normalized()
        aligned = dt.rotation_difference(ds).to_matrix() @ rest_t[t]
        offset[t] = rest_s[src_name].transposed() @ aligned
    hips_t, hips_s = names["Hips"], "DEF-hips"
    t_head0 = rig.matrix_world @ rig.data.bones[hips_t].head_local
    s_head0 = src.matrix_world @ src.data.bones[hips_s].head_local
    scale = t_head0.z / s_head0.z
    obj_rot_inv = rig.matrix_world.to_3x3().normalized().transposed()
    rig.animation_data_create()
    made = {}
    for clip, action_name in clips.items():
        action = bpy.data.actions.get(action_name + "_Rig") or bpy.data.actions[action_name]
        src.animation_data.action = action
        out = bpy.data.actions.new(clip)
        out.use_fake_user = True
        rig.animation_data.action = out
        start, end = int(action.frame_range[0]), int(math.ceil(action.frame_range[1]))
        calm = CALM_LEGS if clip in CALM else 0.0
        for frame in range(start, end + 1):
            bpy.context.scene.frame_set(frame)
            want = {}
            for b in bones:
                src_name = MAP.get(b.name.split(":")[-1])
                if b.name in offset:
                    want[b.name] = world_rot(src, src.pose.bones[src_name].matrix) @ offset[b.name]
                    short = b.name.split(":")[-1]
                    if calm and short.endswith(LEG_BONES):
                        q = want[b.name].to_quaternion().slerp(rest_t[b.name].to_quaternion(), calm)
                        want[b.name] = q.to_matrix()
                    elif calm and short in HEAD_BONES:
                        q = want[b.name].to_quaternion().slerp(rest_t[b.name].to_quaternion(), CALM_HEAD)
                        want[b.name] = q.to_matrix()
                else:
                    parent = b.parent
                    base = want[parent.name] @ rest_t[parent.name].transposed() if parent else Matrix.Identity(3)
                    want[b.name] = base @ rest_t[b.name]
            for b in bones:
                pb = rig.pose.bones[b.name]
                pb.rotation_mode = "QUATERNION"
                rest_local = (b.parent.matrix_local.to_3x3().inverted() @ b.matrix_local.to_3x3()) if b.parent \
                    else b.matrix_local.to_3x3()
                parent_arm = obj_rot_inv @ want[b.parent.name] if b.parent else Matrix.Identity(3)
                local = rest_local.inverted() @ parent_arm.inverted() @ (obj_rot_inv @ want[b.name])
                pb.rotation_quaternion = local.to_quaternion()
                pb.keyframe_insert("rotation_quaternion", frame=frame - start, group=b.name)
            s_head = src.matrix_world @ src.pose.bones[hips_s].head
            delta = (s_head - s_head0) * scale
            delta.z *= 1.0 - calm
            target = t_head0 + delta
            pb = rig.pose.bones[hips_t]
            arm = rig.matrix_world.inverted() @ target
            rest = rig.data.bones[hips_t].matrix_local
            parent = rig.data.bones[hips_t].parent
            if parent:
                rest = parent.matrix_local.inverted() @ rest
            pb.location = rest.to_3x3().inverted() @ (arm - rig.data.bones[hips_t].head_local)
            pb.keyframe_insert("location", frame=frame - start, group=hips_t)
        made[clip] = {"source": action_name, "frames": end - start + 1}
    rig.animation_data.action = bpy.data.actions["idle"]
    return made


# ---------------------------------------------------------------- export
def export(path, rig, meshes):
    bpy.ops.object.select_all(action="DESELECT")
    rig.select_set(True)
    for obj in meshes:
        obj.select_set(True)
    bpy.context.view_layer.objects.active = rig
    bpy.ops.export_scene.gltf(filepath=str(path), export_format="GLB", use_selection=True,
                              export_morph=False, export_animations=True, export_animation_mode="ACTIONS",
                              export_force_sampling=True, export_frame_range=False)


def build(hero_id, spec, args, asset_root):
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.context.scene.render.fps = 24
    macro = TargetService.get_default_macro_info_dict()
    landmark_fit = fitted(hero_id)
    macro.update(landmark_fit["macro"] if landmark_fit else spec["macro"])
    body = HumanService.create_human(macro_detail_dict=macro, feet_on_ground=False)
    if landmark_fit:
        for name, value in landmark_fit["targets"].items():
            TargetService.load_target(body, TargetService.target_full_path(name), weight=value, name=name)
            kb = body.data.shape_keys.key_blocks[name]
            kb.slider_max = max(1.0, value)
            kb.value = value
    receipt = {"id": hero_id, "fit": fit(body, spec["height"], None if landmark_fit else RATIO)}
    if landmark_fit:
        receipt["landmark_fit"] = landmark_fit["verify"]
    body.name = hero_id + "_body"
    rig = HumanService.add_builtin_rig(body, "mixamo")
    rig.name = hero_id + "_rig"
    parts = {}
    parts["eyes"] = HumanService.add_mhclo_asset(asset_root / "eyes/low-poly/low-poly.mhclo", body,
                                                 asset_type="Eyes", subdiv_levels=0, material_type="GAMEENGINE")
    parts["brows"] = HumanService.add_mhclo_asset(asset_root / f"eyebrows/{spec['brows']}/{spec['brows']}.mhclo",
                                                  body, asset_type="Eyebrows", subdiv_levels=0,
                                                  material_type="GAMEENGINE")
    parts["hair"] = HumanService.add_mhclo_asset(asset_root / f"hair/{spec['hair']}/{spec['hair']}.mhclo", body,
                                                 asset_type="Hair", subdiv_levels=0, material_type="GAMEENGINE")
    plugin = {s: HumanService.add_mhclo_asset(asset_root / f"clothes/{s}/{s}.mhclo", body, asset_type="Clothes",
                                              subdiv_levels=0, material_type="GAMEENGINE")
              for s in wardrobe.suits(hero_id)}
    activate(body)
    TargetService.bake_targets(body)
    for obj in [*parts.values(), *plugin.values()]:
        bake_asset(obj)
    for s, obj in plugin.items():
        obj.name = f"{hero_id}_{s}"
    parts["hair"].name = hero_id + "_hair"
    hair_mat = flat_material("Hair", spec["hair_color"], 0.55)
    paint(parts["hair"], hair_mat)
    paint(parts["brows"], hair_mat)
    solidify(parts["hair"], 0.006)
    skin = flat_material("Skin", spec["skin"], 0.62)
    if landmark_fit:
        # Still the full hm08 topology here, which face_map.json indexes.
        painted = face_paint.paint_face(body, hero_id, spec["skin"],
                                        Path(__file__).resolve().parents[2] / ".runtime" / "facefit" / "paint" / f"{hero_id}-skin.png")
        skin = painted or skin
    activate(body)
    hide = body.modifiers.get("Hide helpers")
    if hide:
        bpy.ops.object.modifier_apply(modifier=hide.name)
    body.data.materials.clear()
    body.data.materials.append(skin)
    for p in body.data.polygons:
        p.material_index = 0
    if "eyes" in spec:
        eye_mat = eye_material(asset_root / f"eyes/materials/{spec['eyes']}_eye.png")
    else:
        eye_mat = flat_material("Eyes", (0.92, 0.90, 0.86) if hero_id == "demon" else (0.30, 0.20, 0.12), 0.3)
    paint(parts["eyes"], eye_mat)
    garments = wardrobe.dress(hero_id, body, rig, plugin)
    # The plugin's delete groups hide the skin under its clothes; apply them now that shells are cut.
    activate(body)
    for mod in [m for m in body.modifiers if m.type == "MASK"]:
        bpy.ops.object.modifier_apply(modifier=mod.name)
    clips = dict(CLIPS)
    clips.update(OVERRIDES.get(hero_id, {}))
    src = load_motion(args.motion)
    receipt["clips"] = retarget(src, rig, clips, 24)
    bpy.data.objects.remove(src, do_unlink=True)
    receipt["clipping"] = wardrobe.audit(body, garments, rig, list(clips))
    receipt["painted_normals"] = face_paint.apply_flat_normals(body)
    meshes = [body, *parts.values(), *garments]
    for obj in meshes:
        obj.data.name = obj.name
    path = args.out / f"{hero_id}.glb"
    export(path, rig, meshes)
    receipt["glb_bytes"] = path.stat().st_size
    receipt["triangles"] = sum(len(evaluated(o).loop_triangles) for o in meshes)
    return receipt


def main():
    p = argparse.ArgumentParser()
    p.add_argument("--system-pack", type=Path, required=True)
    p.add_argument("--motion", type=Path, required=True)
    p.add_argument("--out", type=Path, default=Path("assets/characters/heroes"))
    p.add_argument("--only", default="")
    args = p.parse_args(sys.argv[sys.argv.index("--") + 1:])
    args.out = args.out.resolve()
    args.out.mkdir(parents=True, exist_ok=True)
    with args.system_pack.open("rb") as f:
        assert hashlib.file_digest(f, "sha256").hexdigest() == SYSTEM_SHA
    asset_root = Path(LocationService.get_user_data()).resolve()
    extract(args.system_pack, asset_root, ("eyes/", "eyebrows/", "eyelashes/", "hair/", "clothes/"))
    receipts = {}
    for hero_id, spec in HEROES.items():
        if args.only and hero_id not in args.only.split(","):
            continue
        receipts[hero_id] = build(hero_id, spec, args, asset_root)
        print("HERO_PASS", hero_id, json.dumps(receipts[hero_id]["fit"]), json.dumps(receipts[hero_id]["clipping"]))
    receipt_path = args.out / "receipt.json"
    old = json.loads(receipt_path.read_text()) if receipt_path.exists() else {}
    old.update(receipts)
    receipt_path.write_text(json.dumps(old, indent=1) + "\n")


if __name__ == "__main__":
    main()
