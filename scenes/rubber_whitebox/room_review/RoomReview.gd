extends Node3D
## Independent manual review route; no seed, campaign saves or puzzle state.

const Plans = preload("RoomPlans.gd")
const Blockout = preload("RoomBlockout.gd")
const RoomTitles = preload("res://scenes/rogue_crossing/Rooms.gd")
const Inputs = preload("res://scenes/rubber_whitebox/WhiteboxInput.gd")
const PlayerScene = preload("res://scenes/rubber_whitebox/TestPlayer.tscn")
const Player = preload("res://scenes/rubber_whitebox/TestPlayer.gd")
const LOOK = preload("res://scenes/rubber_whitebox/YardLook.tres")
const REVIEW_CONTROLS := {
	&"review_next": KEY_N, &"review_previous": KEY_B, &"review_plan": KEY_TAB,
	&"review_directory": KEY_M, &"review_use_threshold": KEY_E,
}
const WARM := Color("efb776")
const PAPER := Color("f3ebdb")
const MUTED := Color("a9c8cf")

var room_index := 0
var plan := {}
var blockout: Node3D
var player: Player
var plan_camera: Camera3D
var viewing_plan := false
var finished := false
var hud: CanvasLayer
var title: Label
var chapter: Label
var brief: Label
var status: Label
var mode_button: Button
var room_list: PanelContainer
var room_buttons: Array[Button] = []
var previous_taa := false

func _ready() -> void:
	Inputs.install(REVIEW_CONTROLS)
	previous_taa = get_viewport().use_taa
	if RenderingServer.get_current_rendering_method() == "forward_plus":
		get_viewport().use_taa = true
	_lighting()
	_setup_hud()
	get_viewport().size_changed.connect(_on_resize)
	player = PlayerScene.instantiate()
	add_child(player)
	plan_camera = Camera3D.new()
	plan_camera.name = "ReviewCamera"
	plan_camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	plan_camera.keep_aspect = Camera3D.KEEP_HEIGHT
	add_child(plan_camera)
	open_room(0)

func _exit_tree() -> void:
	get_viewport().use_taa = previous_taa

func _lighting() -> void:
	var world := WorldEnvironment.new()
	var env := LOOK.duplicate() as Environment
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color("273847")
	env.ambient_light_energy = 0.45
	world.environment = env
	add_child(world)
	var key := DirectionalLight3D.new()
	key.name = "FixedReviewKey"
	key.rotation_degrees = Vector3(-62, -28, 0)
	key.light_color = Color("fff1dd")
	key.light_energy = 1.17
	key.light_angular_distance = 1.1
	key.shadow_enabled = true
	key.directional_shadow_max_distance = 47
	add_child(key)

func open_room(index: int) -> void:
	if is_instance_valid(blockout):
		remove_child(blockout)
		blockout.queue_free()
	room_index = posmod(index, Plans.ORDER.size())
	plan = Plans.plan(Plans.ORDER[room_index])
	blockout = Blockout.new()
	blockout.name = "Blockout_" + Plans.ORDER[room_index]
	add_child(blockout)
	blockout.build(plan)
	finished = false
	_frame_plan()
	_reset_player()
	_set_plan_view(viewing_plan)
	chapter.text = "NIGHT WATCH     /     BLOCKOUT %02d OF %02d" % [room_index + 1, Plans.ORDER.size()]
	title.text = RoomTitles.TITLES[Plans.ORDER[room_index]]
	brief.text = plan.brief
	for i in room_buttons.size():
		room_buttons[i].modulate = WARM if i == room_index else PAPER

func _on_resize() -> void:
	if plan_camera != null and not plan.is_empty():
		_frame_plan()

func _frame_plan() -> void:
	var half: Vector2 = plan.size * 0.5
	plan_camera.position = Vector3(half.x * 0.45, half.y * 3.32, half.y * 1.18)
	plan_camera.look_at(Vector3.ZERO)
	var right := plan_camera.basis.x
	var up := plan_camera.basis.y
	var extent := Rect2()
	var first := true
	var hull: Array[Vector3] = []
	for x in [-half.x - 0.13, half.x + 0.13]:
		for z in [-half.y - 0.13, half.y + 0.13]:
			hull.append(Vector3(x, 0, z))
			hull.append(Vector3(x, plan.height, z))
	# Frame both aprons as well as the wall caps, keeping the full shell in view.
	for side in [-1, 1]:
		hull.append(Vector3(side * Blockout.APRON_WIDTH * 0.5, 0, half.y + Blockout.APRON_FRONT))
		if not plan.terminal:
			hull.append(Vector3(plan.exit_x + side * 1.75, 0, -half.y - Blockout.APRON_BACK))
	for corner in hull:
		var projected := Vector2(corner.dot(right), corner.dot(up))
		extent = Rect2(projected, Vector2.ZERO) if first else extent.expand(projected)
		first = false
	var center := extent.get_center()
	plan_camera.position += right * center.x + up * center.y
	var viewport_size := get_viewport().get_visible_rect().size
	var aspect := viewport_size.x / maxf(viewport_size.y, 1.0)
	plan_camera.size = maxf(extent.size.y, extent.size.x / aspect) / 0.81

func _reset_player() -> void:
	finished = false
	var start: Vector2 = plan.start
	player.reset_to(Transform3D(Basis.IDENTITY, Vector3(start.x, 0.035, start.y)))
	player.boom.spring_length = 5.55
	player.boom.rotation.x = -0.40

func _set_plan_view(enabled: bool) -> void:
	viewing_plan = enabled
	if enabled:
		plan_camera.make_current()
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	else:
		(player.get_node("Orbit/Boom/Camera") as Camera3D).make_current()
	player.set_physics_process(not enabled)
	player.set_process_unhandled_input(not enabled)
	mode_button.text = "Tab   Walk view" if enabled else "Tab   Plan view"

func _toggle_directory() -> void:
	room_list.visible = not room_list.visible
	if room_list.visible:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

func _near_finish() -> bool:
	return Vector2(player.position.x, player.position.z).distance_to(plan.finish) < 1.42

func _physics_process(_delta: float) -> void:
	if Input.is_action_just_pressed("whitebox_hud"):
		hud.visible = not hud.visible
	if Input.is_action_just_pressed("whitebox_reset") or player.position.y < -3.0:
		_reset_player()
	if Input.is_action_just_pressed("review_next"):
		open_room(room_index + 1)
	elif Input.is_action_just_pressed("review_previous"):
		open_room(room_index - 1)
	if Input.is_action_just_pressed("review_plan"):
		_set_plan_view(not viewing_plan)
	if Input.is_action_just_pressed("review_directory"):
		_toggle_directory()
	if not viewing_plan and Input.is_action_just_pressed("review_use_threshold") and _near_finish():
		if plan.terminal:
			finished = true
		else:
			open_room(room_index + 1)
	if viewing_plan:
		status.text = "PLAN   /   AMBER: PRIMARY     TEAL: ALTERNATE"
	elif finished:
		status.text = "BELL CHECK COMPLETE"
	elif _near_finish():
		status.text = "E   /   CHECK THE BELL" if plan.terminal else "E   /   NEXT ROOM"
	else:
		status.text = "WALK   /   FOLLOW THE AMBER MARKS"

func mcp_observe() -> Dictionary:
	return {"stage": Plans.ORDER[room_index], "name": title.text, "index": room_index + 1,
		"count": Plans.ORDER.size(), "view": "plan" if viewing_plan else "walk",
		"fixtures": plan.fixtures.size(), "alternate": not plan.alternative.is_empty(),
		"grounded": player.is_on_floor(), "position": [player.position.x, player.position.y, player.position.z],
		"near_finish": _near_finish(), "finished": finished}

func _setup_hud() -> void:
	hud = CanvasLayer.new()
	add_child(hud)
	var root := Control.new()
	hud.add_child(root)
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var heading := _card(root, Vector2.ZERO, Rect2(24, 22, 365, 0), true)
	var heading_rows := _stack(heading)
	chapter = _line(heading_rows, 12, WARM)
	title = _line(heading_rows, 29, PAPER)
	brief = _line(heading_rows, 13, MUTED)
	brief.custom_minimum_size.x = 330.0
	brief.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	var nav := _card(root, Vector2(1, 0), Rect2(-349, 22, 325, 0), false)
	var nav_rows := _stack(nav)
	status = _line(nav_rows, 12, MUTED)
	var bar := HBoxContainer.new()
	nav_rows.add_child(bar)
	_button(bar, "B   Prev", func(): open_room(room_index - 1))
	_button(bar, "N   Next", func(): open_room(room_index + 1))
	mode_button = _button(bar, "Tab   Plan view", func(): _set_plan_view(not viewing_plan))
	_button(bar, "M   Rooms", _toggle_directory)
	room_list = _card(root, Vector2(1, 0), Rect2(-349, 110, 325, 0), true)
	var entries := _stack(room_list)
	for i in Plans.ORDER.size():
		var name_: String = RoomTitles.TITLES[Plans.ORDER[i]]
		room_buttons.append(_button(entries, "%02d    %s" % [i + 1, name_], func(): open_room(i); room_list.hide()))
	room_list.hide()
	var help := _card(root, Vector2(0.5, 1), Rect2(-365, -59, 730, 0), false)
	var commands := _line(_stack(help), 12, PAPER)
	commands.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	commands.text = "WASD  Move     /     CLICK or Q · R  Orbit     /     E  Use threshold     /     BACKSPACE  Reset     /     H  HUD"

func _card(parent: Control, anchor: Vector2, rect: Rect2, accented: bool) -> PanelContainer:
	var panel := PanelContainer.new()
	parent.add_child(panel)
	panel.set_anchor(SIDE_LEFT, anchor.x)
	panel.set_anchor(SIDE_RIGHT, anchor.x)
	panel.set_anchor(SIDE_TOP, anchor.y)
	panel.set_anchor(SIDE_BOTTOM, anchor.y)
	panel.offset_left = rect.position.x
	panel.offset_right = rect.end.x
	panel.offset_top = rect.position.y
	panel.offset_bottom = rect.end.y
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var style := StyleBoxFlat.new()
	style.bg_color = Color("101d29f4")
	style.set_corner_radius_all(4)
	style.border_width_left = 2 if accented else 0
	style.border_color = WARM
	style.content_margin_left = 13
	style.content_margin_right = 13
	style.content_margin_top = 9
	style.content_margin_bottom = 9
	panel.add_theme_stylebox_override("panel", style)
	return panel

func _stack(parent: Control) -> VBoxContainer:
	var rows := VBoxContainer.new()
	rows.add_theme_constant_override("separation", 3)
	rows.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(rows)
	return rows

func _line(parent: Container, size: int, ink: Color) -> Label:
	var line := Label.new()
	line.add_theme_font_size_override("font_size", size)
	line.add_theme_color_override("font_color", ink)
	parent.add_child(line)
	return line

func _button(parent: Container, caption: String, command: Callable) -> Button:
	var button := Button.new()
	button.text = caption
	button.focus_mode = Control.FOCUS_NONE
	button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	button.add_theme_font_size_override("font_size", 12)
	button.pressed.connect(command)
	parent.add_child(button)
	return button
