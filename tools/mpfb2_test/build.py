"""Run in Blender 4.2+ with MPFB 2.0.18 enabled (see the review notes)."""
import argparse
import hashlib
import json
import math
import os
from pathlib import Path
import struct
import sys
import zipfile

import bpy
from mathutils import Quaternion, Vector

from bl_ext.user_default.mpfb.entities.objectproperties import HumanObjectProperties
from bl_ext.user_default.mpfb.services.humanservice import HumanService
from bl_ext.user_default.mpfb.services.locationservice import LocationService
from bl_ext.user_default.mpfb.services.targetservice import TargetService

SYSTEM_SHA = "b542127a8e25547c7c29c19f2d1d2adb9a664c80396ecd694095dbc8028a0107"
HEIGHT, RATIO = 1.77, 6.5


def activate(obj):
    bpy.ops.object.select_all(action="DESELECT")
    obj.select_set(True)
    bpy.context.view_layer.objects.active = obj


def evaluated(obj):
    bpy.context.view_layer.update()
    return obj.evaluated_get(bpy.context.evaluated_depsgraph_get()).data


def fit(body):
    # Read landmarks from the HM08 data shipped with this extension.
    metadata = Path(LocationService.get_mpfb_data("mesh_metadata")) / "hm08_config.json"
    head = json.loads(metadata.read_text())["dimensions"]["Head"]
    crown, chin = head["zmax"], head["zmin"]
    group = body.vertex_groups["body"].index
    ids = [v.index for v in body.data.vertices if any(g.group == group for g in v.groups)]

    def measure():
        v = evaluated(body).vertices
        sole = min(v[i].co.z for i in ids)
        height = v[crown].co.z - sole
        head_height = v[crown].co.z - v[chin].co.z
        return {"sole_z_m": sole, "height_m": height, "head_height_m": head_height,
                "head_ratio": height / head_height}

    target = "head-scale-vert-incr"
    TargetService.load_target(body, TargetService.target_full_path(target), name=target)
    key = body.data.shape_keys.key_blocks[target]
    original = measure()
    key.value = 1.0
    head_slider_limit = measure()
    low, high = 0.5, 1.0
    for _ in range(13):
        height_slider = (low + high) / 2
        HumanObjectProperties.set_value("height", height_slider, entity_reference=body)
        TargetService.reapply_macro_details(body, remove_zero_weight_targets=False)
        key.value = 0.0
        a = measure()
        key.value = 1.0
        b = measure()
        # Solve height - ratio * head_height = 0 for the linear shape key.
        f0 = a["height_m"] - RATIO * a["head_height_m"]
        f1 = b["height_m"] - RATIO * b["head_height_m"]
        key.value = f0 / (f0 - f1)
        result = measure()
        if result["height_m"] < HEIGHT:
            low = height_slider
        else:
            high = height_slider
    assert 0 < key.value < 1 and abs(result["height_m"] - HEIGHT) < 0.001, result
    assert abs(result["head_ratio"] - RATIO) < 0.002, result
    assert abs(max(evaluated(body).vertices[i].co.z for i in ids) -
               evaluated(body).vertices[crown].co.z) < 0.001
    activate(body)
    body.location.z = -result["sole_z_m"]
    bpy.ops.object.transform_apply(location=True, rotation=False, scale=False)
    return {"original": original, "head_slider_limit": head_slider_limit,
            "fitted": measure(), "height_slider": height_slider, "head_slider": float(key.value),
            "crown_vertex": crown, "chin_vertex": chin}


def animate(rig):
    def set_pose(name, axis, degrees):
        bone = rig.pose.bones[name]
        bone.rotation_mode = "QUATERNION"
        local = bone.bone.matrix_local.to_3x3().inverted() @ Vector(axis)
        bone.rotation_quaternion = Quaternion(local.normalized(), math.radians(degrees))
        bone.keyframe_insert(data_path="rotation_quaternion", frame=frame, group=name)

    bpy.context.scene.render.fps = 24
    bpy.context.scene.frame_start = 1
    bpy.context.scene.frame_end = 73
    for frame, reach, stride, knee in [(1, 0, 0, 0), (19, 45, 0, 0), (37, 0, 0, 0),
                                       (55, 0, 29, 44), (73, 0, 0, 0)]:
        for side in ("l", "r"):
            upper = rig.data.bones[f"upperarm_{side}"]
            down = 1 if upper.tail_local.x > upper.head_local.x else -1
            set_pose(f"upperarm_{side}", (0, 1, 0), down * (24 if side == "l" else 24 - reach * 0.8))
            set_pose(f"lowerarm_{side}", (0, 0, 1), -down * (reach if side == "r" else 0))
            set_pose(f"thigh_{side}", (1, 0, 0), stride if side == "r" else -stride * 0.55)
            set_pose(f"calf_{side}", (1, 0, 0), -knee if side == "r" else 0)
    rig.animation_data.action.name = "MPFB_Pose_Check"
    bpy.context.scene.frame_set(1)


def material(name, color):
    mat = bpy.data.materials.new(name)
    mat.use_nodes = True
    mat.diffuse_color = (*color, 1)
    shader = mat.node_tree.nodes.get("Principled BSDF")
    shader.inputs["Base Color"].default_value = mat.diffuse_color
    shader.inputs["Roughness"].default_value = 0.72
    return mat


def coat(obj, mat):
    obj.data.materials.clear()
    obj.data.materials.append(mat)
    for p in obj.data.polygons:
        p.material_index = 0
        p.use_smooth = True


def cover_for_review(obj, mat):
    # Review-only painted shorts; body triangles stay intact.
    obj.data.materials.append(mat)
    for p in obj.data.polygons:
        if 0.775 < p.center.z < 0.994 and abs(p.center.x) < 0.20:
            p.material_index = 1


def duplicate(obj, name):
    new = obj.copy()
    new.data = obj.data.copy()
    new.name = name
    new.data.name = name
    bpy.context.collection.objects.link(new)
    return new


def apply_modifier(obj, mod):
    activate(obj)
    while obj.modifiers.find(mod.name) > 0:
        bpy.ops.object.modifier_move_up(modifier=mod.name)
    bpy.ops.object.modifier_apply(modifier=mod.name)


def body_copy(source, name):
    out = duplicate(source, name)
    activate(out)
    TargetService.bake_targets(out)
    apply_modifier(out, out.modifiers["Hide helpers"])
    return out


def glb_json(path):
    with path.open("rb") as file:
        assert file.read(4) == b"glTF"
        assert struct.unpack("<I", file.read(4))[0] == 2
        file.read(4)
        size, kind = struct.unpack("<I4s", file.read(8))
        assert kind == b"JSON"
        return json.loads(file.read(size))


def export(folder, name, rig, meshes):
    activate(rig)
    for obj in meshes:
        obj.select_set(True)
        deform_groups = {group.index for group in obj.vertex_groups if group.name in rig.data.bones}
        unweighted = sum(not any(g.group in deform_groups and g.weight > 1e-6 for g in v.groups)
                         for v in obj.data.vertices)
        assert unweighted == 0, (obj.name, unweighted)
    path = folder / f"{name}.glb"
    bpy.ops.export_scene.gltf(filepath=str(path), export_format="GLB", use_selection=True,
                              export_morph=False, export_animations=True)
    info = glb_json(path)
    triangles, bounds_y = {}, {}
    for mesh in info["meshes"]:
        assert all(p.get("mode", 4) == 4 and "JOINTS_0" in p["attributes"] and
                   "WEIGHTS_0" in p["attributes"] for p in mesh["primitives"]), mesh["name"]
        triangles[mesh["name"]] = sum(info["accessors"][p["indices"]]["count"] // 3
                                      for p in mesh["primitives"])
        positions = [info["accessors"][p["attributes"]["POSITION"]] for p in mesh["primitives"]]
        bounds_y[mesh["name"]] = [min(p["min"][1] for p in positions),
                                  max(p["max"][1] for p in positions)]
    assert len(info["skins"]) == 1 and info["animations"][0]["channels"]
    return {"triangles": triangles, "total_triangles": sum(triangles.values()),
            "bounds_y_m": bounds_y, "glb_bytes": path.stat().st_size, "joints": len(info["skins"][0]["joints"]),
            "animation": info["animations"][0]["name"]}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--system-pack", type=Path, required=True)
    args = parser.parse_args(sys.argv[sys.argv.index("--") + 1:])
    folder = args.output.resolve()
    folder.mkdir(parents=True, exist_ok=True)
    with args.system_pack.open("rb") as file:
        assert hashlib.file_digest(file, "sha256").hexdigest() == SYSTEM_SHA
    profile = Path(os.environ["BLENDER_USER_RESOURCES"]).resolve()
    asset_root = Path(LocationService.get_user_data()).resolve()
    assert asset_root.is_relative_to(profile), asset_root
    with zipfile.ZipFile(args.system_pack) as pack:
        for entry in pack.namelist():
            if entry.startswith(("proxymeshes/male1591/", "eyes/low-poly/",
                                 "clothes/male_casualsuit01/")) and not entry.endswith("/") or entry in {
                                     "eyes/materials/brown.mhmat", "eyes/materials/brown_eye.png"}:
                pack.extract(entry, asset_root)

    bpy.ops.wm.read_factory_settings(use_empty=True)
    macro = TargetService.get_default_macro_info_dict()
    macro.update(gender=1.0, age=0.5, weight=0.42, muscle=0.42)
    body = HumanService.create_human(macro_detail_dict=macro, feet_on_ground=False)
    measures = fit(body)
    body.name = "HM08_Master"
    rig = HumanService.add_builtin_rig(body, "game_engine")
    assert rig and len(rig.data.bones) == 53
    root = rig.data.bones["Root"].head_local
    assert abs(root.z) < 0.005, root
    proxy = HumanService.add_mhclo_asset(asset_root / "proxymeshes/male1591/male1591.proxy", body,
                                         asset_type="Proxymeshes", subdiv_levels=0)
    eyes = HumanService.add_mhclo_asset(asset_root / "eyes/low-poly/low-poly.mhclo", body,
                                        asset_type="Eyes", subdiv_levels=0, material_type="GAMEENGINE")
    suit = HumanService.add_mhclo_asset(asset_root / "clothes/male_casualsuit01/male_casualsuit01.mhclo",
                                        body, subdiv_levels=0, material_type="GAMEENGINE")
    skin = material("Clay", (0.48, 0.32, 0.21))
    fabric = material("Review coverage", (0.035, 0.056, 0.071))
    coat(body, skin)
    coat(proxy, skin)
    # Save the editable morphs and fitted assets before baking export copies.
    animate(rig)
    for obj in (proxy, suit):
        obj.hide_set(True)
    activate(body)
    bpy.ops.file.pack_all()
    bpy.ops.wm.save_as_mainfile(filepath=str(folder / "detective_mpfb.blend"))
    for obj in (proxy, suit):
        obj.hide_set(False)
    high = body_copy(body, "Full_Body")
    low = duplicate(high, "Collapse_Body")
    mod = low.modifiers.new("Budget probe", "DECIMATE")
    mod.ratio = 4700 / 26756
    mod.use_collapse_triangulate = True
    # Simplify the undeformed mesh before skinning, preserving original bone groups.
    apply_modifier(low, mod)
    dressed = duplicate(high, "Masked_Body")
    mod = dressed.modifiers.new("Hide body under suit", "MASK")
    mod.vertex_group = "Delete.male_casualsuit01"
    mod.invert_vertex_group = True
    apply_modifier(dressed, mod)
    dressed.data.materials.clear()
    dressed.data.materials.append(skin)
    for mod in list(proxy.modifiers):
        # MPFB added the suit mask to the proxy too; compare the intact proxy.
        if mod.type == "MASK":
            proxy.modifiers.remove(mod)
    proxy.data.name = "Male1591_Body"
    eyes.data.name = "Low_Poly_Eyes"
    suit.data.name = "Casual_Suit"
    for obj in (high, low, proxy):
        cover_for_review(obj, fabric)
    exports = {
        "full": export(folder, "full", rig, [high, eyes]),
        "collapse": export(folder, "collapse", rig, [low, eyes]),
        "proxy": export(folder, "proxy", rig, [proxy, eyes]),
        "dressed": export(folder, "dressed", rig, [dressed, eyes, suit]),
    }
    full_sole, full_crown = exports["full"]["bounds_y_m"]["Full_Body"]
    assert abs(full_sole) < 0.001 and abs(full_crown - HEIGHT) < 0.001, (full_sole, full_crown)
    assert exports["full"]["total_triangles"] > 5_000
    assert all(exports[k]["total_triangles"] <= 5_000 for k in ("proxy", "collapse")), exports
    (folder / "blender_receipt.json").write_text(json.dumps({"blender": bpy.app.version_string,
        "measurements": measures, "exports": exports}, indent=2) + "\n")


if __name__ == "__main__":
    main()
