extends SceneTree
## Live in-scene verification and screenshot capture for DualModeInteractionHud
## (Aggregated C+ vs Distributed Detroit) across all 3 interaction states
## (Potential / Activatable / Selected) in Public Hall.
##
## Run:
##   xvfb-run -a -s "-screen 0 1280x720x24" /home/spark/godot_472/Godot_v4.7.2-stable_mono_linux_x86_64 \
##     --path . --rendering-method gl_compatibility -s res://tools/test/foucault_dual_ui_test.gd -- --no-rule-save --skip-intro

const RunScene := preload("res://scenes/rogue/Run.tscn")
const DualHud := preload("res://scenes/components/shared/DualModeInteractionHud.gd")

var failed := 0
var out_dir := "/tmp/foucault_ui_shots"

func _initialize() -> void:
	DirAccess.make_dir_recursive_absolute(out_dir)
	run.call_deferred()

func check(ok: bool, msg: String) -> void:
	print(("PASS " if ok else "FAIL ") + msg)
	if not ok:
		failed += 1

func frames(n: int) -> void:
	for i in n:
		await process_frame

func snap(name: String) -> void:
	await RenderingServer.frame_post_draw
	var img := root.get_texture().get_image()
	var path := "%s/%s.png" % [out_dir, name]
	var err := img.save_png(path)
	check(err == OK, "Saved screenshot %s (%dx%d)" % [path, img.get_width(), img.get_height()])

func aim_player_at(view, player, pos: Vector3, look_target: Vector3) -> void:
	var dir := look_target - pos
	var flat_dir := Vector3(dir.x, 0.0, dir.z)
	view.place_player(pos, flat_dir)
	await frames(1)
	var cam: Camera3D = player.camera()
	if cam != null:
		# Adjust pitch gently toward the dial/pin
		var horiz := Vector2(dir.x, dir.z).length()
		var target_pitch := atan2(look_target.y - cam.global_position.y, maxf(horiz, 0.01))
		if player.has_method("orbit_by"):
			var cur_pitch := cam.rotation.x
			var delta_y := (cur_pitch - target_pitch) / 0.0022
			player.orbit_by(Vector2(0.0, delta_y))
	await frames(2)

func send_key(code: Key) -> void:
	var ev := InputEventKey.new()
	ev.physical_keycode = code
	ev.pressed = true
	ev.echo = false
	root.push_input(ev, true)
	await frames(1)

func run() -> void:
	var game := RunScene.instantiate()
	root.add_child(game)
	await frames(2)

	var view = game.room_view
	var player = view._player
	var anchors: Dictionary = view.hall_opening_anchors()
	check(not anchors.is_empty(), "Hall anchors available")
	var pend: Vector3 = anchors.pendulum
	var pin := pend + Vector3(0.0, 0.14, 0.0)

	# Hide top-left / bottom-left dev overlay clutter only? No, keep real in-game HUD authentic!
	# Capture 1: C+ Potential (~6.0m away)
	game.dual_ui.set_mode(DualHud.Mode.AGGREGATED_CPLUS, false)
	await aim_player_at(view, player, pend + Vector3(0.0, 0.0, 6.0), pin)
	var st1: Dictionary = game.dual_ui.get_state_snapshot()
	check(st1.mode == "cplus" and st1.cplus_state == "potential", "C+ State 1 = potential (got %s)" % str(st1))
	await snap("01_cplus_potential")

	# Capture 2: C+ Activatable (~3.5m away)
	await aim_player_at(view, player, pend + Vector3(0.0, 0.0, 3.5), pin)
	var st2: Dictionary = game.dual_ui.get_state_snapshot()
	check(st2.cplus_state == "activatable", "C+ State 2 = activatable (got %s)" % str(st2))
	await snap("02_cplus_activatable")

	# Capture 3: C+ Selected (~2.1m away, looking at center pin)
	await aim_player_at(view, player, pend + Vector3(0.0, 0.0, 2.15), pin)
	var st3: Dictionary = game.dual_ui.get_state_snapshot()
	check(st3.cplus_state == "selected", "C+ State 3 = selected (got %s)" % str(st3))
	await snap("03_cplus_selected")

	# Test V key hot-toggle to Detroit Distributed mode
	await send_key(KEY_V)
	var st_toggle: Dictionary = game.dual_ui.get_state_snapshot()
	check(st_toggle.mode == "detroit", "Pressing V toggles C+ -> Detroit (got %s)" % str(st_toggle))

	# Capture 4: Detroit Selected (~2.15m away, center pin focused, outer ring & Hale activatable)
	game.dual_ui.show_toast("", 0.0)
	await frames(1)
	var st4: Dictionary = game.dual_ui.get_state_snapshot()
	check(st4.detroit_focus_id == "pin" and st4.detroit_states.get("pin") == "selected", "Detroit State 3 = pin selected (got %s)" % str(st4))
	await snap("04_detroit_selected")

	# Capture 5: Detroit Activatable (~3.5m away)
	await aim_player_at(view, player, pend + Vector3(0.0, 0.0, 3.5), pin)
	var st5: Dictionary = game.dual_ui.get_state_snapshot()
	check(st5.detroit_states.get("pin") == "activatable", "Detroit State 2 = activatable (got %s)" % str(st5))
	await snap("05_detroit_activatable")

	# Capture 6: Detroit Potential (~6.0m away)
	await aim_player_at(view, player, pend + Vector3(0.0, 0.0, 6.0), pin)
	var st6: Dictionary = game.dual_ui.get_state_snapshot()
	check(st6.detroit_states.get("pin") == "potential", "Detroit State 1 = potential (got %s)" % str(st6))
	await snap("06_detroit_potential")

	# Functional test: step back to Selected and press E -> directly launches pendulum timing judge
	await aim_player_at(view, player, pend + Vector3(0.0, 0.0, 2.15), pin)
	await send_key(KEY_E)
	check(game.modal == "wrpg" and is_instance_valid(game._wrpg_title) and "统计周期" in game._wrpg_title.text,
		"Pressing E in Selected state directly starts pendulum timing judge (modal=%s)" % game.modal)

	print("TEST_SUMMARY failed=%d" % failed)
	quit(0 if failed == 0 else 1)
