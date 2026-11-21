"""Generate MPFB muscle studies and independent featured-cast fits in an isolated Blender profile."""
import argparse
import json
from pathlib import Path
import sys

import bpy
from mathutils import Vector

sys.path.insert(0, str(Path(__file__).resolve().parent))
from build import (HumanService, LocationService, TargetService, activate, animate,
                   body_copy, coat, evaluated, export, material)

# gender slider, card age, weight slider, review height (metres), target head ratio
CAST = {
    "detective": (1.0, 27, 0.42, 1.77, 6.5),
    "halvard": (1.0, 29, 0.60, 1.82, None),
    "jane": (0.0, 19, 0.49, 1.56, None),
    "qingyue": (0.0, 19, 0.45, 1.64, None),
}
# First MPFB pass for the remaining featured cast. Heights are review choices.
# The Caretaker's age input shapes his adult guise rather than dating the character.
FEATURED_CAST = {
    "lucian": (1.0, 21, 0.34, 1.79, None),
    "ward": (1.0, 38, 0.53, 1.80, None),
    "shending": (1.0, 44, 0.69, 1.75, None),
    "caretaker": (1.0, 38, 0.31, 1.84, None),
}
LEVELS = (0.50, 0.75, 1.00)
FIT_LEVELS = {"detective": 0.50, "halvard": 0.75, "jane": 0.75, "qingyue": 0.50,
              "lucian": 0.44, "ward": 0.56, "shending": 0.64, "caretaker": 0.40}

# Signed strengths on named stock targets, not normalized macro slider values.
# {side} applies the same weight to the corresponding left and right targets.
FIT_TARGETS = {
    "detective": {
        "measure-shoulder-dist": 0.06, "{side}-upperarm-shoulder-muscle": 0.10, "torso-scale-horiz": -0.10,
        "torso-muscle-pectoral": 0.17, "torso-muscle-dorsi": 0.10,
        "{side}-upperarm-muscle": -0.10, "{side}-lowerarm-muscle": -0.14,
        "{side}-upperleg-muscle": -0.22, "measure-thigh-circ": -0.18,
        "{side}-lowerleg-muscle": -0.16, "measure-calf-circ": -0.14,
        "measure-waist-circ": -0.08,
    },
    "halvard": {
        "measure-shoulder-dist": 0.36, "{side}-upperarm-shoulder-muscle": 0.55,
        "torso-muscle-dorsi": 0.57, "torso-muscle-pectoral": 0.52, "torso-scale-depth": 0.14,
        "{side}-upperarm-muscle": 0.52, "measure-upperarm-circ": 0.19,
        "{side}-lowerarm-muscle": 0.82, "{side}-lowerarm-fat": 0.13, "{side}-upperleg-muscle": 0.29,
        "measure-thigh-circ": 0.14, "{side}-lowerleg-muscle": 0.50, "measure-calf-circ": 0.16,
    },
    "jane": {
        "measure-shoulder-dist": 0.17, "{side}-upperarm-shoulder-muscle": 0.34,
        "torso-muscle-dorsi": 0.22, "{side}-upperarm-muscle": 0.15,
        "{side}-lowerarm-muscle": 0.31, "{side}-upperleg-muscle": 0.28,
        "{side}-lowerleg-muscle": 0.24, "measure-waist-circ": 0.23, "stomach-tone": -0.36,
    },
    "qingyue": {
        "measure-shoulder-dist": -0.13, "{side}-upperarm-shoulder-muscle": -0.16,
        "torso-muscle-dorsi": -0.16, "{side}-upperarm-muscle": -0.23,
        "{side}-lowerarm-muscle": -0.18, "{side}-upperleg-muscle": -0.15,
        "{side}-lowerleg-muscle": -0.16, "stomach-tone": -0.25,
    },
    "lucian": {
        "measure-shoulder-dist": -0.12, "torso-scale-depth": -0.16, "measure-waist-circ": -0.13,
        "{side}-upperarm-muscle": -0.12, "{side}-upperleg-muscle": -0.10,
        "head-scale-vert": 0.13, "head-scale-horiz": -0.29, "chin-width": -0.22,
        "chin-prominent": -0.12, "nose-scale-horiz": -0.10, "{side}-cheek-volume": 0.10,
    },
    "ward": {
        "measure-shoulder-dist": 0.25, "torso-vshape": 0.20, "torso-muscle-pectoral": 0.18,
        "measure-neck-circ": 0.14, "head-scale-horiz": 0.24, "head-scale-vert": -0.14,
        "chin-width": 0.42, "chin-height": -0.17, "{side}-cheek-bones": 0.10,
    },
    "shending": {
        "torso-scale-depth": 0.32, "measure-waist-circ": 0.34, "stomach-tone": -0.30,
        "measure-neck-circ": 0.28, "torso-muscle-dorsi": 0.26, "{side}-lowerarm-muscle": 0.34,
        "head-scale-horiz": 0.19, "head-fat": 0.23, "chin-width": 0.22,
        "{side}-cheek-volume": 0.30, "nose-scale-horiz": 0.16,
    },
    "caretaker": {
        "measure-shoulder-dist": -0.18, "torso-scale-horiz": -0.16, "measure-waist-circ": -0.17,
        "{side}-hand-scale": -0.25, "{side}-hand-fingers-diameter": -0.35,
        "{side}-hand-fingers-length": 0.20, "head-scale-vert": 0.25, "forehead-temple": -0.22,
        "head-scale-horiz": -0.22, "chin-height": 0.28, "chin-width": -0.37, "head-fat": -0.18,
    },
}


def apply_local_targets(body, strengths):
    applied = {}
    for pattern, signed_value in strengths.items():
        assert 0 < abs(signed_value) <= 1
        for side in (("l", "r") if "{side}" in pattern else (None,)):
            name = pattern.format(side=side) + ("-incr" if signed_value > 0 else "-decr")
            path = TargetService.target_full_path(name)
            assert path and Path(path).name in (name + ".target.gz", name + ".target"), name
            key = TargetService.load_target(body, path, name=name, weight=abs(signed_value))
            applied[name] = float(key.value)
    return applied


def age_slider(years):
    # Legacy MakeHuman AgeYears convention (1 / 25 / 90 at 0 / .5 / 1).
    return (years - 1) / 48 if years <= 25 else 0.5 + (years - 25) / 130


def landmarks(body, crown, chin):
    verts = evaluated(body).vertices
    sole, top = min(v.co.z for v in verts), max(v.co.z for v in verts)
    assert abs(top - verts[crown].co.z) < 0.001
    return sole, top - sole, verts[crown].co.z - verts[chin].co.z


def head_fit(body, crown, chin, ratio, fixed):
    name = "head-scale-vert-incr"
    TargetService.load_target(body, TargetService.target_full_path(name), name=name)
    key = body.data.shape_keys.key_blocks[name]
    if fixed is None:
        key.value = 0.0
        _, height, head = landmarks(body, crown, chin)
        a = height - ratio * head
        key.value = 1.0
        _, height, head = landmarks(body, crown, chin)
        b = height - ratio * head
        fixed = a / (a - b)
        assert 0.0 <= fixed <= 1.0, fixed
    key.value = fixed
    return float(key.value)


def section_cm(mesh, origin, normal):
    """Perimeter of the closed triangle-plane contour nearest the landmark."""
    verts = [v.co.copy() for v in mesh.vertices]
    distances = [(v - origin).dot(normal) for v in verts]
    points, adjacency = {}, {}
    for tri in mesh.loop_triangles:
        edge_keys = []
        ids = list(tri.vertices)
        for i, j in zip(ids, ids[1:] + ids[:1]):
            a, b = distances[i], distances[j]
            if (a < 0) != (b < 0):
                key = tuple(sorted((i, j)))
                if key not in points:
                    points[key] = verts[i].lerp(verts[j], a / (a - b))
                edge_keys.append(key)
        if edge_keys:
            a, b = edge_keys
            adjacency.setdefault(a, []).append(b)
            adjacency.setdefault(b, []).append(a)
    candidates = []
    unseen = set(adjacency)
    while unseen:
        stack, component = [unseen.pop()], []
        while stack:
            edge = stack.pop()
            component.append(edge)
            for other in adjacency[edge]:
                if other in unseen:
                    unseen.remove(other)
                    stack.append(other)
        if len(component) <= 3 or any(len(adjacency[e]) != 2 for e in component):
            continue
        center = sum((points[e] for e in component), Vector()) / len(component)
        perimeter = sum((points[e] - points[n]).length for e in component for n in adjacency[e]) / 2
        candidates.append(((center - origin).length, perimeter))
    distance, perimeter = min(candidates)
    assert distance < 0.045 and 0.12 < perimeter < 1.6, (origin, distance, perimeter)
    return perimeter * 100


def measurements(mesh, bones, height):
    mesh.calc_loop_triangles()
    values = {}
    for label, bone_name, fraction in (("upper_arm", "upperarm_r", 0.48),
                                       ("forearm", "lowerarm_r", 0.32),
                                       ("thigh", "thigh_r", 0.38),
                                       ("calf", "calf_r", 0.31)):
        bone = bones[bone_name]
        origin = bone.head_local.lerp(bone.tail_local, fraction)
        normal = (bone.tail_local - bone.head_local).normalized()
        values[label] = section_cm(mesh, origin, normal)
    spine = bones["spine_01"]
    values["shoulder_joint_span"] = (bones["upperarm_l"].head_local - bones["upperarm_r"].head_local).length * 100
    values["waist_line"] = section_cm(mesh, Vector((0, spine.head_local.y - 0.045, height * 0.59)), Vector((0, 0, 1)))
    return values


def coverage(body, bones):
    """Rest-mesh material assignment for a review unitard, reused across the sweep."""
    arm = bones["upperarm_r"]
    arm_axis = (arm.tail_local - arm.head_local).normalized()
    # Arm weights guard the sleeve rule from affecting the torso and pelvis.
    arm_bones = {b.name for side in ("r", "l") for b in bones[f"upperarm_{side}"].children_recursive}
    arm_bones.update(("upperarm_r", "upperarm_l"))
    arm_groups = {g.index for g in body.vertex_groups if g.name in arm_bones}
    side = 1 if arm.tail_local.x > 0 else -1
    hem = bones["thigh_r"].head_local.lerp(bones["thigh_r"].tail_local, 0.60).z
    neck = bones["neck_01"].head_local.z - 0.008
    indices = set()
    for p in body.data.polygons:
        c = p.center.copy()
        if not hem < c.z < neck:
            continue
        c.x = side * abs(c.x)
        arm_weight = sum(g.weight for v in p.vertices for g in body.data.vertices[v].groups
                         if g.group in arm_groups) / len(p.vertices)
        if arm_weight < 0.40 or (c - arm.head_local).dot(arm_axis) < arm.length * 0.28:
            indices.add(p.index)
    assert 1000 < len(indices) < 7000, len(indices)
    return indices


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--out", required=True, type=Path)
    parser.add_argument("--design-fit", action="store_true", help="Build baseline and locally fitted presets")
    parser.add_argument("--featured-additions", action="store_true", help="Generate only the four new featured-cast models")
    args = parser.parse_args(sys.argv[sys.argv.index("--") + 1:])
    if args.featured_additions and not args.design_fit:
        parser.error("--featured-additions needs --design-fit")
    cast = FEATURED_CAST if args.featured_additions else CAST
    out = args.out.resolve()
    presets = out / "presets"
    preview = out / "godot"
    for folder in (presets, preview):
        folder.mkdir(parents=True, exist_ok=True)
    asset = Path(LocationService.get_user_data()) / "eyes/low-poly/low-poly.mhclo"
    assert asset.is_file(), asset
    metadata = Path(LocationService.get_mpfb_data("mesh_metadata")) / "hm08_config.json"
    head = json.loads(metadata.read_text())["dimensions"]["Head"]
    crown, chin = head["zmax"], head["zmin"]
    receipt = {"blender": bpy.app.version_string, "mpfb": "2.0.18", "cast": {}}
    bpy.ops.wm.read_factory_settings(use_empty=True)
    for name, (gender, years, weight, height, ratio) in cast.items():
        fixed_head, faces, original_macro = None, None, None
        variants = []
        samples = (("base", FIT_LEVELS[name]), ("fit", FIT_LEVELS[name])) if args.design_fit else (
            tuple((f"{int(muscle * 100):03d}", muscle) for muscle in LEVELS))
        for tag, muscle in samples:
            for obj in list(bpy.data.objects):
                bpy.data.objects.remove(obj, do_unlink=True)
            bpy.data.orphans_purge(do_recursive=True)
            stem = f"{name}-{tag}"
            macro = TargetService.get_default_macro_info_dict()
            macro.update(gender=gender, age=age_slider(years), weight=weight, muscle=muscle)
            body = HumanService.create_human(macro_detail_dict=macro, feet_on_ground=False)
            actual = TargetService.get_macro_info_dict_from_basemesh(body)
            assert abs(actual.pop("muscle") - muscle) < 1e-6
            if original_macro is None:
                original_macro = actual
            assert original_macro == actual, (original_macro, actual)
            if ratio:
                fixed_head = head_fit(body, crown, chin, ratio, fixed_head)
            local = apply_local_targets(body, FIT_TARGETS[name]) if tag == "fit" else {}
            sole, raw_height, head_height = landmarks(body, crown, chin)
            if ratio and not variants:
                assert abs(raw_height / head_height - ratio) < 0.0001
            preset = presets / f"human.{stem}.json"
            HumanService.serialize_to_json_file(body, str(preset), save_clothes=False)
            stored = json.loads(preset.read_text(encoding="utf-8"))
            assert abs(stored["phenotype"]["muscle"] - muscle) < 1e-6
            stored_targets = {t["target"]: t["value"] for t in stored["targets"]}
            for target, strength in local.items():
                assert abs(stored_targets[target] - strength) < 1e-6
            scale = height / raw_height
            activate(body)
            body.scale = (scale,) * 3
            body.location.z = -sole * scale
            bpy.ops.object.transform_apply(location=True, rotation=False, scale=True)
            rig = HumanService.add_builtin_rig(body, "game_engine")
            assert rig and len(rig.data.bones) == 53
            eyes = HumanService.add_mhclo_asset(asset, body, asset_type="Eyes", subdiv_levels=0,
                                                material_type="GAMEENGINE")
            model = body_copy(body, "Review_Body")
            eyes.data.name = "Review_Eyes"
            assert len(model.data.vertices) == 13380
            dims = measurements(model.data, rig.data.bones, height)
            coat(model, material("Warm gray study clay", (0.44, 0.37, 0.31)))
            model.data.materials.append(material("Fitted slate suit", (0.165, 0.255, 0.28)))
            if faces is None:
                faces = coverage(model, rig.data.bones)
            for index in faces:
                model.data.polygons[index].material_index = 1
            animate(rig, arm_drop=8 if args.design_fit else 24)
            result = export(preview, stem, rig, [model, eyes])
            lo, hi = result["bounds_y_m"]["Review_Body"]
            assert abs(lo) < 0.001 and abs(hi - height) < 0.001, (lo, hi, height)
            assert result["triangles"]["Review_Body"] == 26756
            variants.append({"name": stem, "muscle": muscle, "preset_height_m": raw_height,
                             "uniform_scale": scale, "head_ratio": raw_height / head_height,
                             "sections_cm": dims, "local_targets": local, "export": result})
            print("MPFB_MUSCLE_SAMPLE", stem, json.dumps(dims), flush=True)
        if args.design_fit:
            base, fit = (v["sections_cm"] for v in variants)
            delta = {k: fit[k] - base[k] for k in base}
            # Confirm the intended directional changes in the exported body.
            if name == "detective":
                assert delta["thigh"] < -1 and delta["calf"] < -1
            elif name == "halvard":
                assert delta["upper_arm"] > 4 and delta["forearm"] > 3 and delta["shoulder_joint_span"] > 1
            elif name == "jane":
                assert delta["forearm"] > 1 and delta["calf"] > 1 and delta["waist_line"] > 2
            elif name == "qingyue":
                assert all(delta[k] < 0 for k in ("upper_arm", "forearm", "thigh", "calf"))
        receipt["cast"][name] = {"card_age_years": None if name == "caretaker" else years,
                                 "mpfb_age_input_years": years, "macros_except_muscle": original_macro,
                                 "review_height_m": height, "fixed_head_target": fixed_head, "samples": variants}
    basename = "featured-fit-receipt.json" if args.featured_additions else (
        "fit-receipt.json" if args.design_fit else "muscle-receipt.json")
    (out / basename).write_text(json.dumps(receipt, indent=2) + "\n", encoding="utf-8")


if __name__ == "__main__":
    main()
