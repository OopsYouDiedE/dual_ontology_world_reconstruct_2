extends SceneTree
## Non-bypassable Level Pipeline CI Gate & Live F2 Visual Blueprint Inspector Capture.
## 1. Verifies AcademyLevelBase auto-mounts unified UI, furniture catalog, 3D AI gizmos, and F2 inspector.
## 2. Verifies AcademyLevelAudit hard-rejects Epistemic Firewall leaks, unknown furniture, and <3.0s AI telegraphs.
## 3. Auto-exports docs/design/manifests/chapter1_r01_corridor.md directly from the live code manifest.

const R01Level := preload("res://scenes/levels/Chapter1R01Level.gd")
const LevelAudit := preload("res://scenes/components/shared/AcademyLevelAudit.gd")
const LevelPipeline := preload("res://scenes/components/shared/AcademyLevelPipeline.gd")

var failed := 0

func _initialize() -> void:
	run.call_deferred()

func check(ok: bool, msg: String) -> void:
	print(("PASS " if ok else "FAIL ") + msg)
	if not ok:
		failed += 1

func frames(n: int) -> void:
	for i in n:
		await process_frame

func run() -> void:
	# 1. Negative enforcement checks (prove the pipeline CANNOT be bypassed)
	var bad_firewall := {
		"level_id": "bad_lore", "title": "Bad", "allow_deep_lore": false,
		"capabilities": LevelPipeline.capabilities_expedition(),
		"dialogues": [{"id": "d1", "text_zh": "我们需要去井底取回备用源核并解除十二条对赌契约。"}],
	}
	var res_fw := LevelAudit.validate_manifest(bad_firewall)
	check(not res_fw.ok and res_fw.errors.size() >= 2, "Audit rejects Epistemic Firewall leaks (%s)" % str(res_fw.errors))

	var bad_furn := {
		"level_id": "bad_furn", "title": "Bad", "capabilities": LevelPipeline.capabilities_expedition(),
		"objects": [{"id": "o1", "kind": "glb", "catalog_id": "unregistered_chair_999", "pos": Vector3.ZERO}],
	}
	check(not LevelAudit.validate_manifest(bad_furn).ok, "Audit rejects furniture bypassing AcademyFurnitureCatalog")

	var bad_ai := {
		"level_id": "bad_ai", "title": "Bad", "capabilities": LevelPipeline.capabilities_expedition(),
		"ai_routes": [{"actor_id": "hale", "actor_name": "Hale", "waypoints": [{"pos": Vector3.ZERO, "action": "mistake", "is_rule_mistake": true, "foreshadow_sec": 1.2}]}],
	}
	check(not LevelAudit.validate_manifest(bad_ai).ok, "Audit rejects teammate rule-mistake AI waypoint with foreshadow_sec < 3.0s")

	
	var bad_self_bypass := {
		"level_id": "rogue_bypass", "title": "Bypass", "allow_deep_lore": true,
		"capabilities": LevelPipeline.capabilities_expedition(),
	}
	check(not LevelAudit.validate_manifest(bad_self_bypass).ok, "Audit blocks unauthorized allow_deep_lore=true self-bypass")

	var bad_kind := {
		"level_id": "bad_kind", "title": "Kind", "capabilities": LevelPipeline.capabilities_expedition(),
		"objects": [{"id": "o1", "kind": "custom_bypass", "catalog_id": "x", "pos": Vector3.ZERO}],
	}
	check(not LevelAudit.validate_manifest(bad_kind).ok, "Audit blocks unknown object kind bypass")

	var bad_nan := {
		"level_id": "bad_nan", "title": "NaN", "capabilities": LevelPipeline.capabilities_expedition(),
		"ai_routes": [{"actor_id": "hale", "actor_name": "Hale", "waypoints": [{"pos": Vector3.ZERO, "action": "x", "is_rule_mistake": true, "foreshadow_sec": NAN, "rule_tag": "R4", "dialogue_id": ""}]}],
	}
	check(not LevelAudit.validate_manifest(bad_nan).ok, "Audit blocks NAN foreshadow_sec bypass")

	# 2. Live instantiation of Chapter1R01Level (extends AcademyLevelBase)
	var lvl := R01Level.new()
	root.add_child(lvl)
	await frames(4)

	check(lvl.audit_report.ok, "Chapter1R01Level passes full manifest audit")
	check(is_instance_valid(lvl.dual_ui) and is_instance_valid(lvl.dialogue_presenter) and is_instance_valid(lvl.teammate_wheel),
		"AcademyLevelBase auto-mounts unified DualModeInteractionHud + DialoguePresenter + TeammateWheel")
	check(lvl.spawned_objects.size() == 7, "AcademyLevelBase auto-spawns all 7 declared catalog objects (%d)" % lvl.spawned_objects.size())

	# 3. Export human-readable Markdown blueprint directly from live code manifest
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://docs/design/manifests"))
	var md := LevelAudit.export_markdown(lvl.level_manifest)
	var md_path := ProjectSettings.globalize_path("res://docs/design/manifests/chapter1_r01_corridor.md")
	var f := FileAccess.open(md_path, FileAccess.WRITE)
	f.store_string(md)
	f.close()
	check(FileAccess.file_exists(md_path) and md.contains("AI 动作路线"), "Exported live Markdown design manifest to docs/design/manifests/chapter1_r01_corridor.md")

	# 4. Open F2 Visual Blueprint Inspector + 3D AI Route Gizmos and capture screenshot
	lvl.set_blueprint_inspector_visible(true)
	lvl.play_dialogue("dlg_hale_entry")
	await frames(3)
	if DisplayServer.get_name() == "headless":
		print("SKIP F2 inspector screenshot (headless renderer never emits frame_post_draw)")
	else:
		await RenderingServer.frame_post_draw
		var img := root.get_texture().get_image()
		DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://.runtime/unify"))
		var shot_path := ProjectSettings.globalize_path("res://.runtime/unify/level_base_f2_inspector_live.png")
		check(img.save_png(shot_path) == OK, "Saved live F2 Blueprint Inspector screenshot %s" % shot_path)

	print("PIPELINE_GATE_SUMMARY failed=%d" % failed)
	quit(0 if failed == 0 else 1)
