extends Node3D

const Rules := preload("PalimpsestRules.gd")
const Room := preload("PalimpsestRoom.gd")
const Env := preload("res://scenes/components/rendering/post/Hall04.tres")
const Ink := preload("res://scenes/components/rendering/post/InkPass.gd")
const KEYS := {"i": KEY_1, "ii": KEY_2, "iii": KEY_3, "confirm": KEY_E, "reset": KEY_R, "view": KEY_TAB}
const REASONS := {"ink_revisit": "An inked bay cannot be set twice.", "turn_incomplete": "The Turn waits for every bay to be inked.",
	"lift_capped": "The return socket ends in an iron cap.", "early_exit": "The Exit waits for every bay to be cured.",
	"lift_revisit": "A cured gate cannot take a second pass.", "tape_spent": "The tape ended before the cart reached the Exit.",
	"capped_socket": "A solid cap fills this socket."}
var authority := Rules.new()
var art := Room.new()
var view: Camera3D
var atmosphere: WorldEnvironment
var ink: MeshInstance3D
var look := 0
var selected := {}
var shown := 0
var commit_requested := false
var board: Dictionary
var prompt: Label
var status: Label
var route_card: Label
var socket_detail: Label
var forecast_meter: ProgressBar
var inspect_bay := -1
var data := {}


func _ready() -> void:
	Engine.physics_ticks_per_second = Rules.TICK_HZ
	for command: String in KEYS:
		var action := StringName("palimpsest_" + command)
		if not InputMap.has_action(action):
			InputMap.add_action(action)
			var key := InputEventKey.new()
			key.physical_keycode = KEYS[command]
			InputMap.action_add_event(action, key)
	get_viewport().msaa_3d = Viewport.MSAA_2X
	get_viewport().scaling_3d_scale = 1.0
	atmosphere = WorldEnvironment.new()
	atmosphere.environment = Env.duplicate() as Environment
	atmosphere.environment.background_color = Color("202932")
	add_child(atmosphere)
	if RenderingServer.get_current_rendering_method() == &"forward_plus":
		ink = Ink.create()
		ink.material_override.set_shader_parameter("opacity", 0.4)
		add_child(ink)
	var lamp := DirectionalLight3D.new()
	lamp.rotation_degrees = Vector3(-65, -40, 0)
	lamp.light_color = Color("ffdfb9")
	lamp.light_energy = 1.09
	lamp.shadow_enabled = true
	add_child(lamp)
	view = Camera3D.new()
	view.projection = Camera3D.PROJECTION_ORTHOGONAL
	view.current = true
	add_child(view)
	board = authority.board()
	add_child(art)
	art.build(board)
	make_hud()
	refresh()
	camera()


func _input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		if event.position.y < get_viewport().get_visible_rect().size.y - 138:
			inspect_bay = pick_bay(event.position)
			refresh()
			get_viewport().set_input_as_handled()
		return
	for command: String in KEYS:
		if not event.is_action_pressed("palimpsest_" + command): continue
		if command == "view":
			look = (look + 1) % 3
			camera()
		elif command == "reset":
			authority = Rules.new()
			clear_preview()
			inspect_bay = -1
		elif data.in_flight.is_empty() and data.phase == "record":
			if command == "confirm":
				if selected.is_empty() and data.actions == ["rewind"]:
					select_route("rewind")
				elif selected.get("ok", false):
					commit_requested = true
			elif not commit_requested:
				inspect_bay = -1
				select_route("port_%d" % ["i", "ii", "iii"].find(command))
		refresh()
		get_viewport().set_input_as_handled()
		return


func pick_bay(point: Vector2) -> int:
	var pos: Variant = Plane(Vector3.UP, 0.10).intersects_ray(view.project_ray_origin(point), view.project_ray_normal(point))
	if pos == null: return -1
	for deck: String in ["ink", "lift"]:
		for b in board.bays.size():
			var pad := art.place(deck, b)
			if absf(pos.x - pad.x) < 0.565 and absf(pos.z - pad.z) < 0.565:
				return b
	return -1


func select_route(action: String) -> void:
	selected = authority.preview(action)
	shown = 0
	commit_requested = false


func clear_preview() -> void:
	selected.clear()
	shown = 0
	commit_requested = false


func _physics_process(_delta: float) -> void:
	var refresh_now := false
	if selected.get("ok", false) and shown < Rules.PREVIEW_TICKS:
		shown += 1
		refresh_now = true
	if commit_requested and shown >= Rules.PREVIEW_TICKS:
		if authority.submit(selected.action):
			clear_preview()
			refresh_now = true
	if authority.step_tick(): refresh_now = true
	if refresh_now:
		refresh()
		if look == 1: camera()


func camera() -> void:
	var focus := Vector3(0, -0.60, 0.74)
	var ray := Vector3(4.6, 19, 17)
	var unit := 18.0
	if look == 1:
		var deck := "ink" if data.phase == "record" else "lift"
		focus = art.carts[deck].position
		unit = 5.9
	elif look == 2:
		ray = Vector3(1.6, 26, 13)
		unit = 17.6
	view.position = focus + ray
	view.look_at(focus)
	view.size = unit
	art.cut_away(view)


func make_hud() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)
	var header := VBoxContainer.new()
	header.position = Vector2(26, 15)
	layer.add_child(header)
	label(header, "THE SLEEPING ACADEMY  /  SWITCHYARD TRIAL A03", 13, Color("a9d8cc"))
	label(header, "The Palimpsest Switchyard", 31, Color("f8e8cc"))
	var footer := PanelContainer.new()
	footer.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	footer.offset_top = -138
	var backdrop := StyleBoxFlat.new()
	backdrop.bg_color = Color("14212af9")
	backdrop.content_margin_left = 26
	backdrop.content_margin_right = 26
	backdrop.content_margin_top = 7
	backdrop.content_margin_bottom = 9
	footer.add_theme_stylebox_override("panel", backdrop)
	layer.add_child(footer)
	var content := VBoxContainer.new()
	content.add_theme_constant_override("separation", 2)
	footer.add_child(content)
	var row := HBoxContainer.new()
	content.add_child(row)
	prompt = label(row, "", 16, Color("efbf89"))
	prompt.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	status = label(row, "", 14, Color("a9d8cc"))
	forecast_meter = ProgressBar.new()
	forecast_meter.show_percentage = false
	forecast_meter.max_value = Rules.PREVIEW_TICKS
	forecast_meter.custom_minimum_size.y = 5
	content.add_child(forecast_meter)
	socket_detail = label(content, "", 14, Color("dedfce"))
	route_card = label(content, "", 14, Color("dedfce"))
	label(content, "Return: read tape backward, mirror I ↔ III, then rotate by the local pin: I = 0, II = 1, III = 2 clockwise steps.", 13, Color("aad3c9"))
	label(content, "1 / 2 / 3  Preview I / II / III   ·   E  Confirm / preview Turn   ·   R  Reset attempt   ·   Tab  View   ·   Click pad  Inspect both decks", 13, Color("91aea8"))


func label(parent: Node, words: String, size: int, shade: Color) -> Label:
	var l := Label.new()
	l.text = words
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", shade)
	parent.add_child(l)
	return l


func badge(idx: int) -> String:
	if idx >= 0: return str(idx + 1).pad_zeros(2)
	return {board.turn: "TURN", board.exit: "EXIT", board.hold: "CAP"}.get(idx, "—")


func refresh() -> void:
	data = authority.snapshot()
	var total: int = board.bays.size()
	var marked: int = data.tape.size()
	var freed: int = data.cured.count(true)
	status.text = "INK %02d/%02d    CURED %02d/%02d    TICK %04d" % [marked, total, freed, total, data.tick]
	forecast_meter.value = shown
	prompt.text = "Ink each bay once. The Turn plays the same tape backwards on the lift."
	socket_detail.text = ""
	route_card.text = ""
	if data.phase == "record" and (data.ink_bay >= 0 or inspect_bay >= 0):
		var cell: Dictionary = board.bays[inspect_bay if inspect_bay >= 0 else data.ink_bay]
		if inspect_bay >= 0: prompt.text = "Inspecting Bay %s. The live Ink cart remains at %s." % [badge(inspect_bay), badge(data.ink_bay)]
		socket_detail.text = "INK BAY %s   /   I → %s      II → %s      III → %s" % [badge(cell.id), badge(cell.ink[0]), badge(cell.ink[1]), badge(cell.ink[2])]
		route_card.text = "RETURN BAY %s   /   I → %s      II → %s      III → %s" % [badge(cell.id), badge(cell.lift[0]), badge(cell.lift[1]), badge(cell.lift[2])]
	elif data.phase == "record":
		prompt.text = "All ink pins are set. E previews the first two return strokes; E again runs the tape."
	elif data.phase == "rewind":
		var f: Dictionary = data.in_flight
		prompt.text = "Returning: mirror the recorded pulse, then rotate the gate by its ink pin."
		if not f.is_empty():
			socket_detail.text = "PULSE %s   /   PIN %s   /   RESULT SOCKET %s   /   BAY %s → %s" % [f.pulse + 1, f.pin + 1, f.port + 1, badge(f.from), badge(f.to)]
	elif data.phase == "won":
		prompt.text = "The same tape inked and cured every bay. The Exit is open."
	elif data.phase == "failed":
		prompt.text = REASONS.get(data.failure, data.failure) + "   R resets the attempt."
	if selected.get("ok", false):
		var soon: Dictionary = selected.frames[19]
		var later: Dictionary = selected.frames[39]
		var first := badge(soon.event.to)
		var then := "   /   then %s" % badge(later.event.to) if selected.action == "rewind" else ""
		var reason: String = REASONS.get(later.failure, later.failure)
		prompt.text = "FORECAST +40 TICKS   /   %s%s   %s" % [first, then, reason]
		if commit_requested: prompt.text += "   [CONFIRM QUEUED]"
	elif not selected.is_empty():
		prompt.text = REASONS.get(selected.reason, "Select an available socket.")
	art.render(data, selected, view)


func mcp_observe() -> Dictionary:
	return {"state": data.duplicate(true), "selected": selected.get("action", ""), "preview_ticks_visible": shown,
		"preview_result": selected.get("frames", [])[-1].phase if selected.get("ok", false) else "",
		"commit_queued": commit_requested, "inspect_bay": inspect_bay, "faded_piers": art.faded, "section": look + 1,
		"render": {"msaa_samples": 2, "scaling_3d_scale": get_viewport().scaling_3d_scale,
		"ink_opacity": ink.material_override.get_shader_parameter("opacity") if ink != null else 0.0,
		"sdfgi_enabled": atmosphere.environment.sdfgi_enabled,
		"atmosphere_baseline": Env.resource_path, "opaque_shader": Room.Finish.resource_path}}
