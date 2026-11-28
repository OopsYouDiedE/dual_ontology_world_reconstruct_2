extends Control
## Walkable, read-only projection of native FreeSO lot data and campaign room viewport.

signal exit_selected(index: int)
signal landmark_inspected
signal crossing_selected(group: int)
signal witness_selected(id: String)

const GeoBuilder := preload("res://scenes/rogue_view/LotGeometryBuilder.gd")
const CampaignPresenter := preload("res://scenes/rogue_view/CampaignStagePresenter.gd")
const FreeSoSnapshot := preload("res://scenes/rogue_view/FreeSoSnapshot.gd")
const Blueprint := preload("res://scenes/rogue_view/NativeBlueprint.gd")
const Plan := preload("res://scenes/rogue_view/NativeLotPlan.gd")
const Veil := preload("res://scenes/components/rendering/feedback/NightVeil.gdshader")
const R18n := preload("res://scenes/components/shared/R18n.gd")
const Stage := preload("res://scenes/components/rendering/AcademyStage.gd")
const UiStyle := preload("res://scenes/components/shared/UiTheme.gd")
const UnifiedInput := preload("res://scenes/components/shared/AcademyUnifiedInput.gd")

const HALL_DRIFT_SHIFT := 0.22
const PLAYER_SCENE := "res://scenes/rogue_player/RoguePlayer.tscn"
const INTERACT := &"interact"
const REACH := 1.85
const APPROACH_HINT := 3.5

var campaign_view := false
var expedition_view := false
var field_model: Callable
var routes_released: bool:
	get: return _campaign.routes_released
	set(value): _campaign.routes_released = value

@onready var _viewport: SubViewport = $RoomViewport
@onready var _geometry: Node3D = $RoomViewport/Geometry
@onready var _camera: Camera3D = $RoomViewport/Camera3D
@onready var _title: Label = $RoomViewport/Title
@onready var _pixels: TextureRect = $Frame/Pixels

var _campaign := CampaignPresenter.new()
var _veil_material: ShaderMaterial
var _shift_pass: MeshInstance3D
var _crosshair: Control
var _modal := false
var _stability := 100

var _lot: Dictionary = {}
var _blueprint: Dictionary = {}
var _blueprint_path := ""
var _blueprint_stamp := -1
var _lot_level := 1
var _template := ""
var _mode := ""
var _instance_id := ""
var _player: CharacterBody3D
var _avatar_root: Node3D
var _object_root: Node3D
var _room_label := ""
var _exits: Array = []
var _inspection_active := false
var _plan_open := false
var _plan: Control
var _panel: VBoxContainer
var _heading: Label
var _prompt: Label
var _navigation: HFlowContainer
var _displayed_exits: Array = []
var _plan_button: Button
var _cinematic := false
var _level_button: Button
var _plan_level := 1
var _upper_plan: Dictionary = {}
var _focus_ring: MeshInstance3D
var _targets: Array[Dictionary] = []
var _clicks: Array[Vector2] = []
var _keyboard_interact := false
var _can_interact := false
var _walkable_cells := {}

var _kitchen
var _kitchen_plan := {}
var _lights: Node3D
var _gothic_hall: Node3D
var _pendulum_drifting := true
var suppressed_prompt_ids: PackedStringArray = PackedStringArray()
var unified_hud_active := false
var _hour := 12.0

func mount_viewport_node(node: Node) -> void:
	if is_instance_valid(_viewport) and node != null:
		_viewport.add_child(node)

func is_plan_open() -> bool:
	return _plan_open

func set_hour(hour: float) -> void:
	_hour = hour
	var daylight := smoothstep(0.0, 1.0, maxf(0.0, cos((fposmod(_hour, 24.0) - 12.0) * PI / 12.0)))
	if is_instance_valid(_gothic_hall) and _gothic_hall.has_method("set_hour"):
		_gothic_hall.set_hour(_hour)
	if is_instance_valid(_lights):
		_lights.apply(_hour, "ember" if _template == "kitchen" else "ordinary")
		if expedition_view and GeoBuilder.is_hall_shell(_template, _room_label):
			for lamp in _lights.lamps:
				lamp.position.y = 5.6
				lamp.light_color = Color("ffbe78").lerp(Color("fff6e4"), daylight)
				lamp.light_energy = lerpf(0.16, 1.35, daylight)
				lamp.omni_range = lerpf(10.0, 24.0, daylight)
	if expedition_view and GeoBuilder.is_hall_shell(_template, _room_label):
		var env: Environment = $RoomViewport/WorldEnvironment.environment
		if env != null:
			env.ambient_light_color = Color("222f46").lerp(Color("9fb4cc"), daylight)
			env.ambient_light_energy = lerpf(0.14, 0.34, daylight)
			env.fog_light_color = Color("1b2230").lerp(Color("eee6d6"), daylight)
			env.glow_intensity = lerpf(0.36, 0.72, daylight)
			env.glow_bloom = lerpf(0.03, 0.14, daylight)
		var compat_fill := _viewport.get_node_or_null("CompatibilityFillLight") as DirectionalLight3D
		if compat_fill != null:
			compat_fill.light_energy = lerpf(0.05, 0.18, daylight)

func _resize_render_target() -> void:
	var display := _pixels.get_global_transform_with_canvas().get_scale().abs() * _pixels.size
	_viewport.size = Vector2i(display.round()).max(Vector2i.ONE)

func _fill_window() -> void:
	$Frame.ratio = maxf(size.x, 1.0) / maxf(size.y, 1.0)

func _ready() -> void:
	_pixels.resized.connect(_resize_render_target)
	_resize_render_target.call_deferred()
	if expedition_view:
		var applied := Stage.apply_to_viewport(_viewport, $RoomViewport/WorldEnvironment, true, true)
		_shift_pass = applied.essence
		resized.connect(_fill_window)
		_fill_window()
		get_window().focus_exited.connect(_release_mouse)
	UnifiedInput.ensure_default_actions()
	_title.hide()
	if expedition_view:
		var veil := ColorRect.new()
		veil.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_pixels.add_child(veil)
		veil.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		_veil_material = ShaderMaterial.new()
		_veil_material.shader = Veil
		veil.material = _veil_material
		_crosshair = Control.new()
		_crosshair.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_pixels.add_child(_crosshair)
		_crosshair.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
		_crosshair.draw.connect(func() -> void:
			_crosshair.draw_circle(Vector2.ZERO, 2.2, Color(1, 1, 1, 0.92 if _can_interact else 0.58))
			if _can_interact:
				_crosshair.draw_arc(Vector2.ZERO, 9.0, 0, TAU, 40, Color(UiStyle.ACCENT, 0.9), 1.8, true)
		)
	_pixels.gui_input.connect(_on_pixels_input)
	_build_hud_overlay()
	_rebuild()

func _build_hud_overlay() -> void:
	_plan = Plan.new()
	_plan.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_plan.campaign_hud = campaign_view and expedition_view
	$Frame.add_child(_plan)
	_panel = VBoxContainer.new()
	_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_panel)
	_panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_panel.offset_left = 16
	_panel.offset_top = 8
	_panel.offset_right = -16
	_panel.offset_bottom = -8
	var bar := HBoxContainer.new()
	_panel.add_child(bar)
	var font := UiStyle.make_font()
	_heading = Label.new()
	_heading.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_heading.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	UiStyle.style_label(_heading, font, 19, UiStyle.TEXT_MAIN, 7)
	bar.add_child(_heading)
	_plan_button = Button.new()
	_plan_button.focus_mode = Control.FOCUS_NONE
	if expedition_view:
		UiStyle.style_button(_plan_button, font)
	_plan_button.pressed.connect(func():
		_plan_open = not _plan_open
		_release_mouse()
		_keyboard_interact = false
		_clicks.clear()
		_refresh_ui()
	)
	bar.add_child(_plan_button)
	_level_button = Button.new()
	_level_button.focus_mode = Control.FOCUS_NONE
	if expedition_view:
		UiStyle.style_button(_level_button, font)
	_level_button.pressed.connect(func():
		_plan_level = 2 if _plan_level == 1 else 1
		_refresh_ui()
	)
	bar.add_child(_level_button)
	var spacer := Control.new()
	spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_panel.add_child(spacer)
	_prompt = Label.new()
	_prompt.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_prompt.add_theme_constant_override("outline_size", 6)
	_panel.add_child(_prompt)
	if expedition_view:
		_panel.remove_child(_prompt)
		add_child(_prompt)
		_prompt.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_prompt.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
		_prompt.offset_left = -320
		_prompt.offset_right = 320
		_prompt.offset_top = 23
		_prompt.offset_bottom = 68
		_prompt.vertical_alignment = VERTICAL_ALIGNMENT_TOP
		_prompt.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		UiStyle.style_label(_prompt, font, 19, UiStyle.TEXT_MAIN, 6)
	_navigation = HFlowContainer.new()
	_navigation.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_navigation.alignment = FlowContainer.ALIGNMENT_CENTER
	_panel.add_child(_navigation)

## Call before rendering a room. Same ID preserves the controlled player's pose.
func set_instance_id(room_id: String) -> void:
	if room_id == _instance_id:
		return
	_instance_id = room_id
	_inspection_active = false
	_plan_open = false
	_blueprint.clear()
	_upper_plan.clear()
	_plan_level = 1
	_blueprint_path = ""
	_blueprint_stamp = -1
	_template = ""
	_lot = {}
	_mode = ""
	_clicks.clear()
	_keyboard_interact = false
	_campaign.drop_crossing()
	_drop_player()

func set_blueprint_room(title: String, exits: Array, xml_path: String) -> Error:
	if xml_path == "res://content/academy_lots/kitchen.xml":
		if _kitchen_plan.is_empty():
			_kitchen_plan = GeoBuilder.Kitchen.read_plan()
		if _kitchen_plan.is_empty():
			return ERR_INVALID_DATA
		_template = "kitchen"
		_apply(title, exits, GeoBuilder.Kitchen.layout(_kitchen_plan), "blueprint", 1)
		return OK
	var stamp := int(FileAccess.get_modified_time(xml_path)) if FileAccess.file_exists(xml_path) else -1
	var result := {"error": OK}
	if _blueprint.is_empty() or _blueprint_path != xml_path or _blueprint_stamp != stamp:
		result = Blueprint.read(xml_path)
		_blueprint = result.get("lot", {})
		_blueprint_path = xml_path
		_blueprint_stamp = stamp
		_upper_plan = Blueprint.read(xml_path, 2).get("lot", {}) if not _blueprint.is_empty() else {}
	_template = xml_path.get_file().get_basename() if xml_path.begins_with("res://content/academy_lots/") else ""
	_apply(title, exits, _blueprint, "blueprint" if not _blueprint.is_empty() else "", 1)
	return result.error

func set_freeso_room(label: String, exits: Array, path: String, level: int = 1) -> Error:
	return _use_snapshot(label, exits, FreeSoSnapshot.read_file(path, level), level)

func set_freeso_snapshot(label: String, exits: Array, snapshot: Dictionary, level: int = 1) -> Error:
	return _use_snapshot(label, exits, FreeSoSnapshot.decode(snapshot, level), level)

func _use_snapshot(label: String, exits: Array, result: Dictionary, level: int) -> Error:
	if result.error != OK:
		_apply(label, exits, _blueprint, "blueprint" if not _blueprint.is_empty() else "", 1)
		return result.error
	_apply(label, exits, result.lot, "snapshot", level)
	return OK

func _apply(label: String, exits: Array, lot: Dictionary, mode: String, level: int) -> void:
	var same_ground: bool = GeoBuilder.has_meridian_well(_template, _room_label) == GeoBuilder.has_meridian_well(_template, label) and GeoBuilder.is_hall_shell(_template, _room_label) == GeoBuilder.is_hall_shell(_template, label) and _mode == mode and _lot_level == level and _lot.get("segments") == lot.get("segments") and _lot.get("patterns") == lot.get("patterns") and _lot.get("windows") == lot.get("windows")
	var changed_objects: bool = _lot.get("objects") != lot.get("objects")
	var changed_avatars: bool = _lot.get("avatars") != lot.get("avatars")
	_room_label = label
	_exits = exits.duplicate(true)
	_mode = mode
	_lot = lot
	_lot_level = level
	if not is_node_ready():
		return
	if not same_ground:
		_rebuild()
		return
	if changed_objects and is_instance_valid(_object_root):
		GeoBuilder.rebuild_objects(_object_root, _lot, _template, expedition_view)
	if changed_avatars and is_instance_valid(_avatar_root):
		GeoBuilder.update_lot_avatars(_avatar_root, _lot)
	_refresh_targets()
	_refresh_ui()

func set_inspection_target(active: bool) -> void:
	_inspection_active = active
	if is_node_ready():
		_refresh_targets()
		_update_prompt()

func _rebuild() -> void:
	for child in _geometry.get_children():
		_geometry.remove_child(child)
		child.queue_free()
	_kitchen = null
	_lights = null
	_gothic_hall = null
	set_essence_instability(0.0)
	_campaign.clear_room()
	_walkable_cells.clear()
	_avatar_root = null
	_object_root = null
	_focus_ring = null
	if _lot.is_empty():
		_drop_player()
	else:
		var built: Dictionary = GeoBuilder.build_room(_geometry, _camera, _lot, _template, _room_label, expedition_view, _pendulum_drifting, _kitchen_plan)
		_walkable_cells = built.walkable_cells
		_kitchen = built.kitchen
		_lights = built.lights
		_gothic_hall = built.gothic_hall
		_avatar_root = built.avatar_root
		_object_root = built.object_root
		if is_instance_valid(_gothic_hall):
			set_essence_instability(essence_baseline())
		if is_instance_valid(_lights):
			set_hour(_hour)
		_spawn_if_needed()
	_refresh_targets()
	_refresh_ui()

func _spawn_if_needed() -> void:
	if is_instance_valid(_player):
		var current_cell := Vector2i(floori(_player.position.x), floori(_player.position.z))
		if not _walkable_cells.has(current_cell) or _player.position.y < -0.75:
			if not _walkable_cells.is_empty():
				_player.spawn_at(_spawn_point())
		return
	if _walkable_cells.is_empty() or not ResourceLoader.exists(PLAYER_SCENE):
		return
	var scene := load(PLAYER_SCENE) as PackedScene
	if scene == null:
		return
	_player = scene.instantiate() as CharacterBody3D
	_player.first_person = expedition_view
	_viewport.add_child(_player)
	var point := _spawn_point()
	if not expedition_view:
		_player.orbit_by(Vector2(0.0, -41.0))
		_player.zoom_by(2.4)
		if is_instance_valid(_kitchen):
			_player.set_room_camera(0.20, 3.0)
	elif _template == "public_nave":
		_player.set_first_person_framing(Stage.BASE_FOV, deg_to_rad(7.1))
	else:
		_player.orbit_by(Vector2(0.0, 380.0))
	_player.spawn_at(point, GeoBuilder.spawn_yaw(_lot))

func _drop_player() -> void:
	_campaign.drop_followers(_viewport)
	if is_instance_valid(_player):
		_viewport.remove_child(_player)
		_player.queue_free()
	_player = null

func _spawn_point() -> Vector3:
	return GeoBuilder.spawn_point(_lot, _template, _kitchen, _is_clear_cell, _has_wall_between, _nearest_walkable)

func _nearest_walkable(point: Vector2) -> Vector3:
	return GeoBuilder.nearest_walkable(_lot, _walkable_cells, _is_clear_cell, point)

func _is_clear_cell(cell: Vector2i) -> bool:
	return GeoBuilder.is_clear_cell(_lot, _walkable_cells, _template, _gothic_hall, _campaign.crossing, campaign_view, cell)

func _has_wall_between(from: Vector2i, to: Vector2i) -> bool:
	return GeoBuilder.has_wall_between(_lot, from, to)

func _refresh_targets() -> void:
	_targets.clear()
	_can_interact = false
	if _lot.is_empty() or not is_instance_valid(_player):
		return
	var focus: Dictionary = {}
	var portals: Array[Dictionary] = []
	var entrances: Array[Dictionary] = []
	for item: Dictionary in _lot.objects:
		if item.role == "exit":
			portals.append(item)
		if item.role == "entry":
			entrances.append(item)
		if item.role in ["focal", "inspect"] and (focus.is_empty() or focus.role not in ["focal", "inspect"]):
			focus = item
		elif focus.is_empty() and item.role not in ["entry", "exit", "window"]:
			focus = item
	if is_instance_valid(_campaign.crossing):
		_targets.append_array(_campaign.crossing.targets)
	_targets.append_array(_campaign.witness_targets)
	if _inspection_active and _exits.is_empty() and not focus.is_empty():
		_targets.append({"kind": "inspect", "position": GeoBuilder.world_pos(focus.position), "label": _item_name(focus, "Landmark")})
	if portals.size() < _exits.size():
		portals.append_array(entrances)
	if expedition_view and (not campaign_view or _campaign.routes_released or is_instance_valid(_campaign.crossing)):
		_campaign.sync_gates(_geometry, _player, campaign_view, _exits, portals, _reachable_cells(), _spawn_point(), _exit_label, _portal_position)
		for i in _campaign.gate_positions:
			_targets.append({"kind": "exit", "index": i, "position": _campaign.gate_positions[i], "label": _exit_label(i)})
	elif not expedition_view:
		for i in mini(portals.size(), _exits.size()):
			_targets.append({"kind": "exit", "index": i, "position": _portal_position(portals[i]), "label": _exit_label(i)})
	if is_instance_valid(_kitchen):
		_targets.append_array(_kitchen.targets())
	if campaign_view:
		return
	if not is_instance_valid(_focus_ring):
		_focus_ring = MeshInstance3D.new()
		var ring := TorusMesh.new()
		ring.inner_radius = 0.46
		ring.outer_radius = 0.51
		ring.material = GeoBuilder.painted_material(Color("74c9b0"), Color("569986"))
		_focus_ring.mesh = ring
		_geometry.add_child(_focus_ring)
	_focus_ring.visible = not _targets.is_empty() and _targets[0].kind == "inspect"
	if _focus_ring.visible:
		_focus_ring.position = _targets[0].position + Vector3.UP * 0.06

func _portal_position(portal: Dictionary) -> Vector3:
	var center := _nearest_walkable(portal.get("interior", portal.position))
	return GeoBuilder.world_pos(portal.position).lerp(center, 0.25)

func _refresh_ui() -> void:
	var has_lot := not _lot.is_empty()
	var plan_mode := has_lot and (_plan_open or not is_instance_valid(_player))
	_pixels.visible = has_lot and not plan_mode
	_plan.visible = plan_mode
	_level_button.visible = plan_mode and _mode == "blueprint" and not _upper_plan.is_empty()
	_level_button.text = "Floor %d · switch" % _plan_level
	_plan.set_lot(_upper_plan if _level_button.visible and _plan_level == 2 else _lot)
	_plan_button.visible = has_lot and is_instance_valid(_player) and not _cinematic
	_plan_button.text = R18n.pick("返回视角", "Walk view") if _plan_open else R18n.pick("俯视平面图", "Overhead plan")
	var heading := "Topology navigation · no native lot available"
	if has_lot:
		heading = "Native lot plan" if plan_mode else ("First person" if expedition_view else "Native lot · Walk view")
		if _mode == "snapshot":
			var source := "Live FreeSO VM" if _lot.source_kind == "live-vm" else "Saved FreeSO VM"
			heading += " · %s, floor %d" % [source, _lot_level]
	_heading.text = _room_label if campaign_view and not plan_mode else "%s  |  %s" % [heading, _room_label]
	if campaign_view and expedition_view:
		_heading.text = ""
	_navigation.visible = not campaign_view
	if is_instance_valid(_player):
		_player.set_controls_enabled(not plan_mode and not _modal)
	if is_instance_valid(_crosshair):
		_crosshair.visible = not _modal and not _plan_open and not _cinematic
		_crosshair.queue_redraw()
	if _displayed_exits != _exits:
		_displayed_exits = _exits.duplicate(true)
		for button in _navigation.get_children():
			_navigation.remove_child(button)
			button.queue_free()
		for i in _exits.size():
			var button := Button.new()
			button.text = _exit_label(i)
			button.tooltip_text = "Travel · " + button.text
			button.focus_mode = Control.FOCUS_NONE
			button.pressed.connect(func(): exit_selected.emit(i))
			_navigation.add_child(button)
	_update_prompt()

func _nearest_target() -> Dictionary:
	var result := {}
	var distance := INF
	if not is_instance_valid(_player):
		return result
	for target in _targets:
		var next := _flat_distance(target.position)
		if next < distance:
			result = target
			distance = next
	return result

func _flat_distance(point: Vector3) -> float:
	return Vector2(point.x, point.z).distance_to(Vector2(_player.position.x, _player.position.z))

func _update_prompt() -> void:
	var target := _nearest_target()
	if _modal:
		_prompt.text = ""
	elif _plan_open or not is_instance_valid(_player):
		_prompt.text = "" if (campaign_view and expedition_view) else ("Travel links" if not _exits.is_empty() else "")
	elif unified_hud_active or target.is_empty() or (target.has("id") and str(target.id) in suppressed_prompt_ids):
		_prompt.text = "" if expedition_view else "WASD · Move     Q / R or right-drag · Orbit"
	else:
		if campaign_view and target.kind == "exit" and not _campaign.routes_released:
			_prompt.text = "Sealed passage · " + target.label
		else:
			var verb := R18n.pick("查看", "Inspect") if target.kind == "inspect" else (R18n.pick("检视", "Examine") if target.kind in ["crossing", "fixture"] else (R18n.pick("交谈", "Speak to") if target.kind == "witness" else R18n.pick("前往", "Travel")))
			var approach := R18n.pick("走近 · ", "Approach · ")
			_prompt.text = ("E · %s %s" if campaign_view else "E / A / Click · %s %s") % [verb, target.label] if _can_interact else approach + target.label
			if expedition_view and not _can_interact and _flat_distance(target.position) > APPROACH_HINT:
				_prompt.text = ""
	if expedition_view and not _modal and not _plan_open and is_instance_valid(_player) and Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		_prompt.text = R18n.pick("点击画面控制视角  ·  WASD 移动", "Click to look  ·  WASD to move") + ("\n" + _prompt.text if not _prompt.text.is_empty() else "")
	if is_instance_valid(_crosshair):
		_crosshair.queue_redraw()

func _input(event: InputEvent) -> void:
	if not expedition_view or _modal or _plan_open or not is_instance_valid(_player):
		return
	if Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		return
	if event is InputEventMouseMotion:
		_player.orbit_by(event.relative)
		get_viewport().set_input_as_handled()
	elif event is InputEventKey and event.physical_keycode == KEY_ESCAPE and event.pressed:
		_release_mouse()
		get_viewport().set_input_as_handled()

func _unhandled_input(event: InputEvent) -> void:
	if not _modal and is_instance_valid(_player) and not _plan_open and event.is_action_pressed(INTERACT):
		_keyboard_interact = true
		get_viewport().set_input_as_handled()

func _on_pixels_input(event: InputEvent) -> void:
	if not is_instance_valid(_player) or _plan_open or _modal:
		return
	if expedition_view and event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
		_pixels.accept_event()
		return
	if event is InputEventMouseMotion and event.button_mask & MOUSE_BUTTON_MASK_RIGHT:
		_player.orbit_by(event.relative)
		_pixels.accept_event()
	elif event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_LEFT and _pixels.size.x > 0 and _pixels.size.y > 0:
			_clicks.append(event.position / _pixels.size * Vector2(_viewport.size))
		elif event.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN] and _player.has_method("zoom_by"):
			_player.zoom_by(1.0 if event.button_index == MOUSE_BUTTON_WHEEL_UP else -1.0)
		_pixels.accept_event()

func _physics_process(_delta: float) -> void:
	if not is_instance_valid(_player) or _plan_open or _modal:
		return
	if _player.position.y < -2 and not _walkable_cells.is_empty():
		_player.spawn_at(_spawn_point())
	var nearest := _nearest_target()
	_can_interact = _is_reachable(nearest)
	_update_prompt()
	if _keyboard_interact:
		_keyboard_interact = false
		if _activate(nearest):
			_clicks.clear()
			return
	var camera: Camera3D = _player.camera()
	if camera == null:
		_clicks.clear()
		return
	while not _clicks.is_empty():
		var point: Vector2 = _clicks.pop_front()
		for target in _targets:
			var center: Vector3 = target.position + Vector3.UP * 0.5
			if not camera.is_position_behind(center) and camera.unproject_position(center).distance_to(point) <= 22 and _activate(target):
				_clicks.clear()
				return

func _is_reachable(target: Dictionary) -> bool:
	if target.is_empty() or _flat_distance(target.position) > REACH:
		return false
	var start := _player.position + Vector3.UP * 0.65
	var destination: Vector3 = target.position + Vector3.UP * 0.65
	if start.distance_squared_to(destination) > 0.01:
		var query := PhysicsRayQueryParameters3D.create(start, destination, 1)
		if not _viewport.find_world_3d().direct_space_state.intersect_ray(query).is_empty():
			return false
	return true

func _activate(target: Dictionary) -> bool:
	if campaign_view and target.get("kind") == "exit" and not _campaign.routes_released:
		return false
	if not _is_reachable(target):
		return false
	if target.kind == "fixture":
		if not is_instance_valid(_kitchen) or not _kitchen.toggle(target.id, _player.global_position):
			return false
		_player.play_action("interact")
		return true
	_player.play_action("interact")
	if target.kind == "crossing":
		crossing_selected.emit(target.index)
	elif target.kind == "witness":
		witness_selected.emit(target.id)
	elif target.kind == "inspect":
		set_inspection_target(false)
		landmark_inspected.emit()
	else:
		exit_selected.emit(target.index)
	return true

func player_observation() -> Dictionary:
	var player: Dictionary = _player.snapshot() if is_instance_valid(_player) else {}
	var targets := []
	for target in _targets:
		var info := target.duplicate()
		var p: Vector3 = target.position
		info.position = [p.x, p.y, p.z]
		if is_instance_valid(_player) and not _plan_open:
			var camera: Camera3D = _player.camera()
			var anchor := p + Vector3.UP * (1.18 if target.kind == "crossing" else 0.5)
			if camera != null and not camera.is_position_behind(anchor):
				var projected := camera.unproject_position(anchor) / Vector2(_viewport.size) * _pixels.size + _pixels.global_position
				info.screen_position = [projected.x, projected.y]
		targets.append(info)
	if is_instance_valid(_player):
		var p := _player.position
		player.position = [p.x, p.y, p.z]
	var velocity: Variant = player.get("velocity")
	if velocity is Vector3:
		player.velocity = [velocity.x, velocity.y, velocity.z]
	player["perspective"] = "first_person" if expedition_view else "third_person"
	player["action"] = player.get("animation", "")
	player["prompt"] = _prompt.text if is_instance_valid(_prompt) else ""
	player["nearest_prompt"] = player.prompt
	player["targets"] = targets
	if is_instance_valid(_kitchen):
		player["fixtures"] = _kitchen.closed.duplicate()
		player["fixtures_moving"] = _kitchen.moving.keys()
	player["available_interact"] = not _plan_open and _can_interact
	player["view"] = "plan" if is_instance_valid(_plan) and _plan.visible else _mode
	player["mouse_captured"] = Input.mouse_mode == Input.MOUSE_MODE_CAPTURED
	if is_instance_valid(_player) and _player.camera() != null:
		var eye: Camera3D = _player.camera()
		player["camera_forward"] = [-eye.global_basis.z.x, -eye.global_basis.z.y, -eye.global_basis.z.z]
		player["fov"] = eye.fov
	return player

func _exit_label(index: int) -> String:
	var entry: Variant = _exits[index]
	var fallback := "Exit %d" % (index + 1)
	var text := str(entry.get("label", fallback)) if entry is Dictionary else (str(entry) if entry is String else fallback)
	text = text.replace("\n", " ").strip_edges()
	return fallback if text.is_empty() else text

static func _item_name(item: Dictionary, fallback: String) -> String:
	var title: String = item.label
	return fallback if title.is_empty() else title

func camp_layout(names: Array) -> Dictionary:
	return _campaign.camp_layout(_lot, _walkable_cells, _player, campaign_view, _template, _gothic_hall, names, _is_clear_cell, _has_wall_between, _nearest_walkable)

func _release_mouse() -> void:
	if expedition_view and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

func set_cinematic(active: bool) -> void:
	_cinematic = active
	set_modal(active or _modal)
	for item: CanvasItem in [_heading, _plan_button, _prompt, _crosshair]:
		if is_instance_valid(item):
			item.visible = not active
	if not active:
		_plan_button.visible = is_instance_valid(_player)

func close_plan() -> void:
	if not _plan_open:
		return
	_plan_open = false
	_keyboard_interact = false
	_clicks.clear()
	if is_node_ready():
		_refresh_ui()

func set_modal(active: bool) -> void:
	_modal = active
	if active:
		_release_mouse()
		_clicks.clear()
		_keyboard_interact = false
	if is_instance_valid(_player):
		_player.set_controls_enabled(not _plan_open and not _modal)
	if is_node_ready():
		_update_prompt()
	if is_instance_valid(_crosshair):
		_crosshair.visible = not _modal and not _plan_open and not _cinematic
		_crosshair.queue_redraw()

func is_walking_view() -> bool:
	return not _plan_open and not _modal and is_instance_valid(_player)

func set_stability(value: int) -> void:
	_stability = value
	if _veil_material == null:
		return
	_veil_material.set_shader_parameter("fracture", clampf((76.0 - value) / 76.0, 0.0, 1.0))

func _reachable_cells(limit := 120) -> Array[Vector2i]:
	var start := _spawn_point()
	return GeoBuilder.reachable_cells(Vector2i(floori(start.x), floori(start.z)), _is_clear_cell, _has_wall_between, limit)

func set_field_party(names: Array) -> void:
	var origin := _player.position if (campaign_view and is_instance_valid(_player)) else _spawn_point()
	_campaign.set_field_party(_viewport, _player, origin, field_model, names, _reachable_cells(40 if campaign_view else 12), _has_wall_between)

func set_crossing(stage: String, survivor: String, variant: bool, stability: int, resolved: bool) -> void:
	if not is_instance_valid(_player):
		return
	var climate: String = _campaign.STAGE_CLIMATE.get(stage, "")
	if is_instance_valid(_lights):
		_lights.apply(_hour, climate)
	set_stability(stability)
	if _campaign.set_crossing(_geometry, _player, _lot, _instance_id, stage, survivor, variant, resolved, _spawn_point(), _reachable_cells(280), _has_wall_between):
		_refresh_targets()

func show_crossing_action(group: int, action: String, result: Dictionary) -> void:
	if is_instance_valid(_campaign.crossing):
		_campaign.crossing.react(group, action, result)

func set_witness_targets(rows: Array[Dictionary]) -> void:
	_campaign.witness_targets = rows
	_refresh_targets()

func show_crossing_turn(actors: Dictionary, beat: int) -> void:
	_campaign.show_crossing_turn(actors, beat)

func release_routes(released: bool) -> void:
	_campaign.release_routes(released)

func viewport_routes() -> Array:
	return CampaignPresenter.viewport_routes_grid(camp_layout([]).graph)

func set_pendulum_drifting(drifting: bool) -> void:
	_pendulum_drifting = drifting
	set_essence_instability(essence_baseline())
	if is_instance_valid(_gothic_hall) and _gothic_hall.has_method("set_drift_state"):
		_gothic_hall.set_drift_state(drifting)

func place_player(point: Vector3, facing: Vector3) -> void:
	if is_instance_valid(_player):
		_player.spawn_at(point, atan2(-facing.x, -facing.z))

func set_essence_instability(value: float) -> void:
	if not is_instance_valid(_shift_pass):
		return
	_shift_pass.visible = value > 0.001
	_shift_pass.material_override.set_shader_parameter("instability", clampf(value, 0.0, 1.0))

func essence_baseline() -> float:
	return HALL_DRIFT_SHIFT if is_instance_valid(_gothic_hall) and _pendulum_drifting else 0.0

func hall_opening_anchors() -> Dictionary:
	if not is_instance_valid(_gothic_hall) or not is_instance_valid(_player):
		return {}
	return {
		"viewport": _viewport,
		"camera": _player.camera(),
		"cot": _gothic_hall.watch_cot_pos,
		"pendulum": _gothic_hall.pendulum_world_pos,
		"gate": _gothic_hall.north_gate_pos,
	}

## Export all active room targets in the unified DualModeInteractionHud group schema.
func unified_room_targets(exclude_ids: PackedStringArray = PackedStringArray()) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for t in _targets:
		var tid := str(t.get("id", "%s_%s" % [str(t.get("kind", "t")), str(t.get("index", 0))]))
		if tid in exclude_ids:
			continue
		var kind := str(t.get("kind", ""))
		if campaign_view and kind == "exit" and not _campaign.routes_released:
			continue
		var verb := R18n.pick("查看", "Inspect") if kind == "inspect" else (R18n.pick("检视", "Examine") if kind in ["crossing", "fixture"] else (R18n.pick("交谈", "Speak to") if kind == "witness" else R18n.pick("前往", "Travel")))
		var label := str(t.get("label", tid))
		var wpos: Vector3 = t.get("position", Vector3.ZERO) + Vector3(0.0, 1.25 if kind == "witness" else 0.75, 0.0)
		var captured_target: Dictionary = t
		out.append({
			"id": tid,
			"title": label,
			"anchor_world": wpos,
			"dist_selected": REACH + 0.55,
			"dist_activatable": APPROACH_HINT + 1.0,
			"dist_potential": 9.5,
			"hotspots": [{
				"id": tid,
				"part_name": label,
				"verb": verb,
				"world_pos": wpos,
				"callback": func(): _activate(captured_target),
			}],
		})
	return out
