extends SceneTree
## Cross-level unification test: verifies that Public Hall (Run.tscn) and Expedition-01 (Sortie.tscn)
## share the exact same DualModeInteractionHud, AcademyUnifiedInput global V-toggle preference,
## and unified multi-group 3-state tracking without regressions.
##
## Run:
##   xvfb-run -a -s "-screen 0 1280x720x24" /home/spark/godot_472/Godot_v4.7.2-stable_mono_linux_x86_64/Godot_v4.7.2-stable_mono_linux.x86_64 \
##     --path . --rendering-method gl_compatibility --windowed --resolution 1280x720 --audio-driver Dummy \
##     -s res://tools/test/unified_level_ui_test.gd -- --no-rule-save --skip-intro

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

	check(is_instance_valid(hall.dual_ui), "Public Hall mounts unified DualModeInteractionHud")
	var h_snap: Dictionary = hall.dual_ui.get_state_snapshot()
	check(h_snap.enabled and h_snap.mode == "cplus" and int(h_snap.group_count) >= 1,
		"Public Hall unified HUD active in cplus mode with groups (%s)" % str(h_snap))
	check(hall.room_view.unified_hud_active, "RogueRoomView suppresses legacy duplicate prompt when unified HUD is active")

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

	check(is_instance_valid(exp.dual_ui), "Expedition-01 mounts the exact same DualModeInteractionHud")
	var e_snap: Dictionary = exp.dual_ui.get_state_snapshot()
	check(e_snap.enabled and e_snap.mode == "detroit" and int(e_snap.group_count) >= 6,
		"Expedition-01 inherits global detroit mode from Hall with all live 3D targets (%s)" % str(e_snap))
	check(is_equal_approx(exp.prompt.modulate.a, 0.0),
		"Expedition-01 hides legacy center prompt visually while keeping prompt.text for MCP tests")

	# Press V in Expedition-01 -> switches global mode back to C+
	await send_key(KEY_V)
	var e_snap2: Dictionary = exp.dual_ui.get_state_snapshot()
	check(e_snap2.mode == "cplus" and UnifiedInput.get_ui_mode() == UnifiedInput.UiMode.AGGREGATED_CPLUS,
		"Pressing V in Expedition-01 hot-toggles back to cplus globally (%s)" % str(e_snap2))

	exp.queue_free()
	print("UNIFIED_TEST_SUMMARY failed=%d" % failed)
	quit(0 if failed == 0 else 1)
