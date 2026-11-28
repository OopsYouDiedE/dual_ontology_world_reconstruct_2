extends SceneTree
## Full cross-level unification test: verifies Public Hall (Run.tscn) and Expedition-01 (Sortie.tscn)
## share AcademyLevelPipeline, explicit capability exceptions (Hall allow_jump=false vs Expedition true),
## DualModeInteractionHud + V global preference sync, UnifiedDialoguePresenter bottom captions,
## and UnifiedTeammateWheel (Q radial wheel) in BOTH Hall and Expedition.

const RunScene := preload("res://scenes/rogue/Run.tscn")
const SortieScene := preload("res://scenes/expedition_01/Sortie.tscn")
const UnifiedInput := preload("res://scenes/components/shared/AcademyUnifiedInput.gd")

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

func send_key(code: Key) -> void:
	var ev := InputEventKey.new()
	ev.physical_keycode = code
	ev.pressed = true
	ev.echo = false
	root.push_input(ev, true)
	await frames(2)

func run() -> void:
	# 1. Public Hall (Run.tscn)
	UnifiedInput.set_ui_mode(UnifiedInput.UiMode.AGGREGATED_CPLUS)
	var hall := RunScene.instantiate()
	root.add_child(hall)
	await frames(5)

	check(hall.level_capabilities.get("allow_jump", true) == false,
		"Public Hall explicitly enforces allow_jump=false exception")
	check(is_instance_valid(hall.dual_ui) and is_instance_valid(hall.dialogue_presenter) and is_instance_valid(hall.teammate_wheel),
		"Public Hall bootstraps complete unified stack (dual_ui + dialogue_presenter + teammate_wheel)")
	var h_snap: Dictionary = hall.dual_ui.get_state_snapshot()
	check(h_snap.enabled and h_snap.mode == "cplus" and int(h_snap.group_count) >= 1,
		"Public Hall unified HUD active in cplus mode (%s)" % str(h_snap))

	# Test unified dialogue presenter in Public Hall
	hall._speak_hall_mumble("测试统一底部字幕", "hale")
	await frames(1)
	check(hall.dialogue_presenter.has_active_caption(),
		"Public Hall speech posts to unified bottom subtitle bar (ExpeditionCaptions)")

	# Test unified Q radial teammate wheel in Public Hall
	await send_key(KEY_Q)
	check(hall.teammate_wheel.is_open(), "Pressing Q in Public Hall opens unified CommandWheel")
	await send_key(KEY_ESCAPE)
	check(not hall.teammate_wheel.is_open(), "Pressing Esc closes Public Hall unified CommandWheel")

	# Press V in Public Hall -> switches global mode to Detroit
	await send_key(KEY_V)
	check(UnifiedInput.get_ui_mode() == UnifiedInput.UiMode.DISTRIBUTED_DETROIT,
		"Pressing V in Public Hall updates global AcademyUnifiedInput mode -> detroit")
	hall.queue_free()
	await frames(2)

	# 2. Expedition-01 North Wing (Sortie.tscn)
	var exp := SortieScene.instantiate()
	root.add_child(exp)
	await frames(5)

	check(exp.level_capabilities.get("allow_jump", false) == true,
		"Expedition-01 explicitly enables allow_jump=true")
	check(is_instance_valid(exp.dual_ui), "Expedition-01 mounts the exact same DualModeInteractionHud")
	var e_snap: Dictionary = exp.dual_ui.get_state_snapshot()
	check(e_snap.enabled and e_snap.mode == "detroit" and int(e_snap.group_count) >= 6,
		"Expedition-01 inherits global detroit mode from Hall (%s)" % str(e_snap))
	check(is_equal_approx(exp.prompt.modulate.a, 0.0),
		"Expedition-01 hides legacy center prompt visually while preserving prompt.text")

	# Press V in Expedition-01 -> switches global mode back to C+
	await send_key(KEY_V)
	var e_snap2: Dictionary = exp.dual_ui.get_state_snapshot()
	check(e_snap2.mode == "cplus" and UnifiedInput.get_ui_mode() == UnifiedInput.UiMode.AGGREGATED_CPLUS,
		"Pressing V in Expedition-01 hot-toggles back to cplus globally (%s)" % str(e_snap2))

	exp.queue_free()
	print("UNIFIED_TEST_SUMMARY failed=%d" % failed)
	quit(0 if failed == 0 else 1)
