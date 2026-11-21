"""Run MPFB 2.0.18 workflows in an isolated Blender profile with test asset packs."""
import argparse
import json
import sys
import traceback
from pathlib import Path

import bpy
from bl_ext.user_default.mpfb.entities.objectproperties import HumanObjectProperties
from bl_ext.user_default.mpfb.services import (
    AnimationService, AssetService, ExportService, FaceService, HumanService,
    LocationService, ObjectService, RandomizationService, RigService, TargetService,
)
from bl_ext.user_default.mpfb.ui.new_human.randomize.randomizeproperties import RANDOMIZE_PROPERTIES

sys.path.insert(0, str(Path(__file__).resolve().parent))
from build import activate, glb_json


def reset():
    for obj in list(bpy.context.scene.objects):
        bpy.data.objects.remove(obj, do_unlink=True)


def asset(name, directory):
    path = AssetService.find_asset_absolute_path(name, directory)
    assert path, (name, directory)
    return str(path)


def human(**kwargs):
    macro = TargetService.get_default_macro_info_dict()
    macro.update(gender=1.0, age=0.5, **kwargs)
    return HumanService.create_human(macro_detail_dict=macro)


def batch():
    config = dict(add_rig="NONE", eyes_mode="DONOTADD", hair_randomize=False,
                  randomize_skin=False, randomize_details=False, new_random_seed=False,
                  batch_count=4, batch_strategy="GRID", batch_random_rotation=False, seed=2026)
    for name in ("eyebrows", "eyelashes", "teeth", "tongue"):
        config[name + "_enable"] = False
    for name in RandomizationService.get_clothes_slots():
        config[f"clothes_{name}_enable"] = False
    for name, value in config.items():
        RANDOMIZE_PROPERTIES.set_value(name, value, entity_reference=bpy.context.scene)
    signatures = []
    for _ in range(2):
        before = set(bpy.data.objects)
        assert bpy.ops.mpfb.create_random_human_batch() == {"FINISHED"}
        bodies = [b for b in bpy.data.objects if b not in before and ObjectService.object_is_basemesh(b)]
        assert len(bodies) == 4
        signatures.append(sorted((b["mpfb_randomization_seed"], tuple(b.location),
                                  TargetService.get_macro_info_dict_from_basemesh(b)) for b in bodies))
    assert signatures[0] == signatures[1]
    return {"characters_per_batch": 4, "same_seed_reproduces_macros_and_positions": True,
            "unique_character_seeds": len({entry[0] for entry in signatures[0]})}


def rigs_and_pose():
    counts = {}
    for key in ("default", "game_engine", "mixamo", "mixamo_unity", "cmu_mb", "openpose"):
        b = human()
        arm = HumanService.add_builtin_rig(b, key)
        counts[key] = len(arm.data.bones)
    b = human()
    meta = HumanService.add_builtin_rig(b, "rigify.human")
    control = RigService.generate_rigify_rig(meta)
    assert control and len(control.pose.bones) > len(meta.pose.bones)
    counts["rigify_meta"] = len(meta.pose.bones)
    counts["rigify_generated"] = len(control.pose.bones)
    b = human()
    arm = HumanService.add_builtin_rig(b, "default")
    pose = str(Path(LocationService.get_user_data()) / "poses/sit01/sit01.bvh")
    before = [bone.matrix_basis.copy() for bone in arm.pose.bones]
    AnimationService.import_bvh_file_as_pose(arm, pose)
    bpy.context.view_layer.update()
    after = [bone.matrix_basis.copy() for bone in arm.pose.bones]
    changed = sum(a != b for a, b in zip(before, after))
    assert changed > 10
    return {"bones": counts, "sit01_bvh_changed_bones": changed}


def import_mhm(fixture):
    settings = HumanService.get_default_deserialization_settings()
    settings.update(load_clothes=False, subdiv_levels=0, clothes_deep_search=False, bodypart_deep_search=False)
    b = HumanService.deserialize_from_mhm(str(fixture), settings)
    assert len(b.data.vertices) == 19158 and b.data.shape_keys
    return {"source": fixture.name, "vertices_in_editable_HM08": len(b.data.vertices),
            "shape_keys_after_import": len(b.data.shape_keys.key_blocks)}


def fitted_character(out):
    b = human(weight=0.42, muscle=0.42)
    rig = HumanService.add_builtin_rig(b, "game_engine")
    asym_name = "asym-cheek-1-l"
    asym = TargetService.load_target(b, TargetService.target_full_path(asym_name), weight=0.8, name=asym_name)
    basis = b.data.shape_keys.key_blocks[0]
    asym_max = max((v.co - neutral.co).length for v, neutral in zip(asym.data, basis.data))
    assert 0.0001 < asym_max < 0.025
    asym.value = 0.0
    skin_path = asset("young_caucasian_male.mhmat", "skins")
    HumanService.set_character_skin(skin_path, b, skin_type="LAYERED")
    layered_nodes = len(b.active_material.node_tree.nodes)
    assert layered_nodes > 3
    HumanService.set_character_skin(skin_path, b, skin_type="GAMEENGINE")
    game_nodes = len(b.active_material.node_tree.nodes)
    assert b.active_material.use_nodes and game_nodes > 1
    parts = []
    for folder, filename, kind in [
        ("eyes", "low-poly.mhclo", "Eyes"), ("eyebrows", "eyebrow001.mhclo", "Eyebrows"),
        ("hair", "short01.mhclo", "Hair"), ("clothes", "male_casualsuit01.mhclo", "Clothes"),
    ]:
        parts.append(HumanService.add_mhclo_asset(asset(filename, folder), b, asset_type=kind,
                                                 subdiv_levels=0, material_type="GAMEENGINE"))
    original_z = rig.data.bones["head"].head_local.z
    garment_points = [v.co.copy() for v in parts[-1].data.vertices]
    HumanObjectProperties.set_value("height", 0.67, entity_reference=b)
    TargetService.reapply_macro_details(b)
    HumanService.refit(b)
    moved_z = abs(rig.data.bones["head"].head_local.z - original_z)
    garment_shift = max((v.co - co).length for v, co in zip(parts[-1].data.vertices, garment_points))
    assert moved_z > 0.015 and garment_shift > 0.01, (moved_z, garment_shift)
    preset = out / "human.audit-character.json"
    HumanService.serialize_to_json_file(b, str(preset), save_clothes=True)
    settings = HumanService.get_default_deserialization_settings()
    settings.update(subdiv_levels=0)
    copy = HumanService.deserialize_from_json_file(str(preset), settings)
    assert abs(TargetService.get_macro_info_dict_from_basemesh(copy)["height"] - 0.67) < 1e-5
    copy_rig = ObjectService.find_object_of_type_amongst_nearest_relatives(copy, "Skeleton")
    assert len(copy_rig.data.bones) == 53
    loaded = sorted(HumanService.get_asset_sources_of_equipped_mesh_assets(copy))
    assert all(any(f in a for a in loaded) for f in ("short01", "low-poly", "eyebrow001", "male_casualsuit01")), loaded
    for obj in ObjectService.get_list_of_children(copy_rig):
        if obj.name in bpy.data.objects:
            bpy.data.objects.remove(obj, do_unlink=True)
    bpy.data.objects.remove(copy_rig, do_unlink=True)
    # Face packages and independent expression preset on the still-editable source.
    FaceService.load_targets(b, True, True, True)
    for key in ("viseme_aa", "jawOpen"):
        assert key in b.data.shape_keys.key_blocks, key
    FaceService.set_expression(b, {"jawOpen": 0.6, "mouthSmileLeft": 0.45})
    expression = FaceService.read_current_expression(b)
    assert abs(expression["jawOpen"] - 0.6) < 1e-5
    FaceService.clear_expression(b)
    assert b.data.shape_keys.key_blocks["!ex-jawOpen"].value == 0.0
    bpy.ops.file.pack_all()
    bpy.ops.wm.save_as_mainfile(filepath=str(out / "workbench.blend"))
    # ExportService works on a copy; bake current body shape before adding the expressive keys.
    branch = ExportService.create_character_copy(b, name_suffix="_engine")
    stage_body = ObjectService.find_object_of_type_amongst_nearest_relatives(branch, "Basemesh")
    activate(stage_body)
    TargetService.bake_targets(stage_body)
    FaceService.load_targets(stage_body, False, True, True)
    key_count = len(stage_body.data.shape_keys.key_blocks) - 1
    source_vertices = len(b.data.vertices)
    ExportService.bake_modifiers_remove_helpers(stage_body, bake_masks=True, remove_helpers=True)
    assert len(stage_body.data.vertices) < source_vertices
    assert "viseme_aa" in stage_body.data.shape_keys.key_blocks
    assert len(b.data.vertices) == source_vertices
    activate(branch)
    for obj in ObjectService.get_list_of_children(branch):
        obj.select_set(True)
    glb = out / "character_face.glb"
    bpy.ops.export_scene.gltf(filepath=str(glb), export_format="GLB", use_selection=True, export_morph=True)
    fbx = out / "character_face.fbx"
    bpy.ops.export_scene.fbx(filepath=str(fbx), use_selection=True, add_leaf_bones=False, bake_anim=False)
    result = glb_json(glb)
    targets = {name for m in result["meshes"] for name in m.get("extras", {}).get("targetNames", [])}
    assert {"viseme_aa", "jawOpen"} <= targets and len(result["skins"]) == 1
    assert fbx.stat().st_size > 10_000
    return {"layered_skin_nodes": layered_nodes, "game_skin_nodes": game_nodes,
            "asym_cheek_target_max_m": asym_max, "head_bone_refit_m": moved_z, "garment_max_refit_m": garment_shift, "preset_assets": loaded,
            "face_shape_keys_before_export": key_count, "face_shape_keys_in_glb": len(targets),
            "export_body_vertices": len(stage_body.data.vertices), "original_body_vertices": source_vertices,
            "glb_bytes": glb.stat().st_size, "fbx_bytes": fbx.stat().st_size}


def hair_editor():
    b = human()
    assert b.name == "Human", b.name
    activate(b)
    assert bpy.ops.mpfb.setup_hair_operator() == {"FINISHED"}
    result = {}
    for label, name, op in (("hair", "basic_short_hair", bpy.ops.mpfb.apply_hair_operator),
                            ("fur", "fur_forearms", bpy.ops.mpfb.apply_fur_operator)):
        activate(b)
        assert op(hair_asset=name) == {"FINISHED"}
        obj = next((child for child in b.children if child.name == name), None)
        assert obj is not None and obj.type == "CURVES" and obj.data.surface == b
        result[label] = {"template": name, "node_modifiers": len(obj.modifiers),
                         "source_curves": len(obj.data.curves)}
    # This is an experimental operator; the 2.0.18 panel does not expose it.
    try:
        activate(b)
        status = bpy.ops.mpfb.generate_hair_cards_operator(hair_asset="basic_short_hair", card_asset="Audit cards")
        cards = bpy.data.objects.get("Audit cards")
        assert status == {"FINISHED"} and cards and cards.modifiers.get("HairCards"), status
        evaluated = cards.evaluated_get(bpy.context.evaluated_depsgraph_get())
        mesh = evaluated.to_mesh()
        result["experimental_cards"] = {"status": "generated", "evaluated_faces": len(mesh.polygons) if mesh else 0}
        evaluated.to_mesh_clear()
    except (RuntimeError, AssertionError) as exc:
        result["experimental_cards"] = {"status": "unavailable", "detail": str(exc).strip()}
    return result


def main():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument("--out", type=Path, required=True)
    p.add_argument("--mhm", type=Path, required=True)
    p.add_argument("--only", choices=["hair", "rigs", "character", "mhm", "batch"])
    args = p.parse_args(sys.argv[sys.argv.index("--") + 1:])
    out = args.out.resolve()
    out.mkdir(parents=True, exist_ok=True)
    tests = {"character": lambda: fitted_character(out), "batch": batch,
             "mhm": lambda: import_mhm(args.mhm), "rigs": rigs_and_pose, "hair": hair_editor}
    receipt = {}
    for key, test in tests.items():
        if args.only is not None and key != args.only:
            continue
        reset()
        try:
            receipt[key] = {"status": "pass", "measurements": test()}
        except Exception as exc:
            traceback.print_exc()
            receipt[key] = {"status": "fail", "detail": str(exc)}
        print("MPFB_WORKFLOW", key, receipt[key], flush=True)
    (out / f"workflow-{args.only or 'all'}.json").write_text(json.dumps(receipt, indent=2) + "\n", encoding="utf8")
    if any(entry["status"] == "fail" for entry in receipt.values()):
        raise RuntimeError("A workflow failed; see workflow receipt")


if __name__ == "__main__":
    main()
