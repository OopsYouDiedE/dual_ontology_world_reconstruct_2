extends SceneTree
## Regression test for the unified r18n, UI, FeelProfile, AcademyRenderProfile,
## CommandWheel mouse interaction, and south-catwalk oil grace window.

const R18n = preload("res://scenes/components/shared/R18n.gd")
const Feel = preload("res://scenes/components/shared/FeelProfile.gd")
const RenderProfile = preload("res://scenes/components/rendering/AcademyRenderProfile.gd")

var fails := 0

func _initialize() -> void:
	run.call_deferred()

func check(ok: bool, what: String) -> void:
	if ok:
		print("  ok  " + what)
	else:
		push_error("FAIL " + what)
		fails += 1

func _key(code: Key) -> InputEventKey:
	var e := InputEventKey.new()
	e.physical_keycode = code
	e.pressed = true
	return e

func run() -> void:
	R18n.set_locale("zh")
	var level = preload("Expedition.tscn").instantiate()
	root.add_child(level)
	for i in 4:
		await physics_frame
		await process_frame

	# 1. r18n live bilingual switching (ZH <-> EN via F8)
	check(R18n.locale() == "zh", "default locale is zh")
	check("灯油" in level.polish.oil_label.text, "oil label renders in zh")
	level._input(_key(KEY_F8))
	await process_frame
	check(R18n.locale() == "en", "F8 switches locale to en")
	check("Lamp Oil" in level.polish.oil_label.text, "oil label updates live to en")
	check(level.polish.lang_badge.text == "[F8] EN", "lang badge reflects en")
	check("Contract" in level.contracts.region_card("trial").rule, "region card switches to en")
	check("Caisson Watch Log" in level.contracts.manual_pages(false)[0], "manual switches to en")
	level._input(_key(KEY_F8))
	await process_frame
	check(R18n.locale() == "zh", "F8 toggles back to zh")

	# 2. Gameplay rule HUD is promoted out of F3 debug_layer
	check(level.polish.plate_line.get_parent() != level.polish.debug_layer, "plate_line is on live HUD canvas")
	check(level.polish.bead_row.get_parent() != level.polish.debug_layer, "bead_row is on live HUD canvas")
	check(level.polish.card_holder.get_parent() != level.polish.debug_layer, "region card is on live HUD canvas")
	level.polish.fail_card("测试", "契约A 第一码")
	await process_frame
	check(level.polish.fail_body.visible, "fail rule clause is visible without F3 debug")

	# 3. CommandWheel mouse sector hit & click confirmation
	var picked := [""]
	level.wheel.chosen.connect(func(id: String) -> void: picked[0] = id)
	level.wheel.bind([
		{"id": "a", "title": "A", "hint": "hA", "cost": "cA"},
		{"id": "b", "title": "B", "hint": "hB", "cost": "cB"},
	])
	level.wheel.reveal()
	var center: Vector2 = level.wheel.wheel.size * 0.5
	check(level.wheel._hit_option(Vector2(10, 10)) == -1, "background click does not hit any sector")
	var opt1_pos: Vector2 = center + level.wheel._point_for(1, 2, 150.0)
	check(level.wheel._hit_option(opt1_pos) == 1, "sector 1 center hits index 1")
	var click := InputEventMouseButton.new()
	click.button_index = MOUSE_BUTTON_LEFT
	click.pressed = true
	click.position = opt1_pos
	level.wheel._on_gui_input(click)
	check(picked[0] == "b" and not level.wheel.open, "left click on sector confirms order and closes wheel")

	# 4. Unified FeelProfile stride & lantern inertia
	check(is_equal_approx(Feel.stride_for_stance(Feel.ST_QUIET), 0.68), "quiet stride is 0.68 m")
	check(is_equal_approx(Feel.stride_for_stance(Feel.ST_WALK), 0.92), "walk stride is 0.92 m")
	check(is_equal_approx(Feel.stride_for_stance(Feel.ST_RUN), 1.24), "run stride is 1.24 m")
	level.walker.rotate_y(0.35)
	level.update_lantern(0.05)
	check(level._lamp_sway.length() > 0.001, "lantern develops spring inertia sway on yaw turn")

	# 5. Unified PBR materials & regional atmosphere grading
	var brass: StandardMaterial3D = level.kit.mat("brass")
	var glass: StandardMaterial3D = level.kit.mat("glass")
	var felt: StandardMaterial3D = level.kit.mat("felt_dark")
	var door_g: StandardMaterial3D = level.kit.mat("door_green")
	check(brass.metallic > 0.75 and brass.roughness < 0.35, "brass PBR preset applied")
	check(glass.roughness < 0.15 and glass.rim_enabled, "glass PBR preset applied")
	check(felt.roughness > 0.95, "felt_dark PBR preset applied")
	check(door_g.clearcoat_enabled, "door_green clearcoat preset applied")
	var a_arc := RenderProfile.atmosphere_for("arcade", 0.0)
	var a_shaft := RenderProfile.atmosphere_for("shaft", 0.0)
	check(a_shaft.fog_density > a_arc.fog_density and a_shaft.fog_color != a_arc.fog_color, "regional atmosphere differentiates shaft from arcade")

	# 6. South catwalk oil-out grace buffer (no instant hard death on 1 tick)
	level.released = true
	level.oil = 0.0
	level.walker.position = Vector3(61.0, 0.05, 23.2) # on south catwalk (radial.y > 2.65, len ~13.1)
	level.retry = 0.0
	level.rules(0.05)
	check(level.retry <= 0.0 and level.catwalk_oil_grace > 0.0 and not level.lamp_on, "south catwalk oil-out grants grace window instead of instant fail")

	print("PASS: unified r18n, UI, CommandWheel mouse, FeelProfile, PBR/atmosphere, catwalk grace (%d failed)" % fails)
	level.queue_free()
	for frame in 12:
		await process_frame
	quit(0 if fails == 0 else 1)
