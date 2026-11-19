extends Control
## Walkable, read-only projection of native FreeSO lot data.

signal exit_selected(index: int)
signal landmark_inspected

signal lane_selected(index: int)

const Veil := preload("res://scenes/rogue_view/render/NightVeil.gdshader")
const Followers := preload("res://scenes/rogue_view/FieldFollowers.gd")
const OilLamp := preload("res://scenes/blue_prince_lab/lamp/Lamp.tscn")
var expedition_view := false
var _modal := false
var _night_stage := ""
var _night_variant := false
var _night_open := false
var _night_root: Node3D
var _night_anchor := Vector3.ZERO
var _lanes: Array[Vector3] = []
var _veil_material: ShaderMaterial
var _crosshair: Label
var _stability := 100
var _echo_glass: Label3D
var _followers: Node3D
var _gate_root: Node3D
var _gate_positions := {}
var _gate_labels: Array = []

const FreeSoSnapshot = preload("res://scenes/rogue_view/FreeSoSnapshot.gd")
const Blueprint = preload("res://scenes/rogue_view/NativeBlueprint.gd")
const Silhouette = preload("res://scenes/rogue_view/CatalogSilhouette.gd")
const Plan = preload("res://scenes/rogue_view/NativeLotPlan.gd")
const PLAYER_SCENE := "res://scenes/rogue_player/RoguePlayer.tscn"
const ACADEMY_ART := "res://scenes/academy_art/AcademyArt.gd"
const ACADEMY_TEMPLATES := ["foyer", "kitchen", "living_hall", "lecture", "clinic", "dining", "valve_gallery", "service_stair"]
const INTERACT := &"interact"
const REACH := 1.85

@onready var _viewport: SubViewport = $RoomViewport
@onready var _geometry: Node3D = $RoomViewport/Geometry
@onready var _camera: Camera3D = $RoomViewport/Camera3D
@onready var _title: Label = $RoomViewport/Title
@onready var _pixels: TextureRect = $Frame/Pixels

var _lot: Dictionary = {}
var _blueprint: Dictionary = {}
var _blueprint_path := ""
var _blueprint_stamp := -1
var _lot_level := 1
var _template := ""
var _art: Script
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
var _level_button: Button
var _plan_level := 1
var _upper_plan: Dictionary = {}
var _focus_ring: MeshInstance3D
var _targets: Array[Dictionary] = []
var _clicks: Array[Vector2] = []
var _keyboard_interact := false
var _can_interact := false
var _walkable_cells := {}


const Kitchen = preload("res://scenes/rogue_view/render/HotKitchen.gd")
var _kitchen
var _kitchen_plan := {}
const Lighting = preload("res://scenes/rogue_view/render/RoomLighting.gd")
const TileShader = preload("res://scenes/rogue_view/render/AcademyTile.gdshader")
var _lights: Node3D
var _hour := 12.0

func set_hour(hour: float) -> void:
	_hour = hour
	if is_instance_valid(_lights): _lights.apply(_hour, "ember" if _template == "kitchen" else "ordinary")

func _tile_surface(tint: Color, wall_surface: bool) -> ShaderMaterial:
	var mat := ShaderMaterial.new()
	mat.shader = TileShader
	mat.set_shader_parameter("wall", wall_surface)
	mat.set_shader_parameter("glaze", tint)
	return mat

func _resize_render_target() -> void:
	var display := _pixels.get_global_transform_with_canvas().get_scale().abs() * _pixels.size
	_viewport.size = Vector2i(display.round()).max(Vector2i.ONE)

func _ready() -> void:
	_pixels.resized.connect(_resize_render_target)
	_resize_render_target.call_deferred()
	if not InputMap.has_action(INTERACT):
		InputMap.add_action(INTERACT)
		var key := InputEventKey.new()
		key.physical_keycode = KEY_E
		InputMap.action_add_event(INTERACT, key)
		var pad := InputEventJoypadButton.new()
		pad.button_index = JOY_BUTTON_A
		InputMap.action_add_event(INTERACT, pad)
	if ResourceLoader.exists(ACADEMY_ART): _art = load(ACADEMY_ART) as Script
	_title.hide()
	if expedition_view:
		var veil := ColorRect.new()
		veil.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_pixels.add_child(veil)
		veil.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		_veil_material = ShaderMaterial.new()
		_veil_material.shader = Veil
		veil.material = _veil_material
		_crosshair = Label.new()
		_crosshair.text = "·"
		_crosshair.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_pixels.add_child(_crosshair)
		_crosshair.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		_crosshair.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_crosshair.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		_crosshair.add_theme_font_size_override("font_size", 23)
	_pixels.gui_input.connect(_on_pixels_input)
	_plan = Plan.new()
	_plan.mouse_filter = Control.MOUSE_FILTER_IGNORE
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
	_heading = Label.new()
	_heading.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_heading.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_heading.add_theme_font_size_override("font_size", 19)
	_heading.add_theme_constant_override("outline_size", 7)
	bar.add_child(_heading)
	_plan_button = Button.new()
	_plan_button.focus_mode = Control.FOCUS_NONE
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
	_navigation = HFlowContainer.new()
	_navigation.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_navigation.alignment = FlowContainer.ALIGNMENT_CENTER
	_panel.add_child(_navigation)
	_rebuild()


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
	_night_stage = ""
	_night_open = false
	_clicks.clear()
	_keyboard_interact = false
	_drop_player()


func set_room(label: String, exits: Array) -> void:
	_apply(label, exits, {}, "", 1)


func set_blueprint_room(title: String, exits: Array, xml_path: String) -> Error:
	if xml_path == "res://content/academy_lots/kitchen.xml":
		if _kitchen_plan.is_empty(): _kitchen_plan = Kitchen.read_plan()
		if _kitchen_plan.is_empty(): return ERR_INVALID_DATA
		_template = "kitchen"
		_apply(title, exits, Kitchen.layout(_kitchen_plan), "blueprint", 1)
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
	var same_ground: bool = _mode == mode and _lot_level == level and _lot.get("segments") == lot.get("segments") and _lot.get("patterns") == lot.get("patterns") and _lot.get("windows") == lot.get("windows")
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
		_rebuild_objects()
	if changed_avatars and is_instance_valid(_avatar_root):
		_update_lot_avatars()
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
	_night_root = null
	_echo_glass = null
	_gate_root = null
	_gate_positions.clear()
	_gate_labels.clear()
	_lanes.clear()
	_walkable_cells.clear()
	_avatar_root = null
	_object_root = null
	_focus_ring = null
	if _lot.is_empty():
		_drop_player()
	else:
		_rebuild_architecture()
		_spawn_if_needed()
	_refresh_targets()
	_refresh_ui()


func _rebuild_architecture() -> void:
	if _template == "kitchen" and not _kitchen_plan.is_empty():
		for cell in _lot.floors: _walkable_cells[cell] = true
		_kitchen = Kitchen.new()
		_geometry.add_child(_kitchen)
		_kitchen.build(_kitchen_plan, _lot.floors)
		return
	var static_body := StaticBody3D.new()
	_geometry.add_child(static_body)
	var tile := BoxMesh.new()
	tile.size = Vector3(1, 0.15, 1)
	var batches := {}
	var floor_bounds := Rect2i()
	for cell: Vector2i in _lot.floors:
		var pattern: int = _lot.patterns.get(cell, 0)
		if not batches.has(pattern):
			var surface := SurfaceTool.new()
			surface.begin(Mesh.PRIMITIVE_TRIANGLES)
			batches[pattern] = surface
		var pos := Vector3(cell.x + 0.5, -0.075, cell.y + 0.5)
		batches[pattern].append_from(tile, 0, Transform3D(Basis.IDENTITY, pos))
		var area := Rect2i(cell, Vector2i.ONE)
		floor_bounds = area if not floor_bounds.has_area() else floor_bounds.merge(area)
		if pattern != 65535:
			_walkable_cells[cell] = true
			_add_shape(static_body, pos, tile.size)
	for pattern: int in batches:
		_commit_static_mesh(batches[pattern], _tile_surface(Plan.floor_color(pattern).darkened(0.22), false))
	var wall := BoxMesh.new()
	wall.size = Vector3(1, 2.45, 0.13)
	var walls := SurfaceTool.new()
	walls.begin(Mesh.PRIMITIVE_TRIANGLES)
	for edge: Vector4i in _lot.segments:
		var a := Vector2(edge.x, edge.y)
		var b := Vector2(edge.z, edge.w)
		var d := b - a
		var middle := (a + b) * 0.5
		var position := Vector3(middle.x, wall.size.y * 0.5, middle.y)
		var basis := Basis(Vector3.UP, -d.angle())
		if _lot.get("windows", {}).has(edge):
			_build_window(position, basis, d.length())
		else:
			walls.append_from(wall, 0, Transform3D(basis * Basis.from_scale(Vector3(d.length(), 1, 1)), position))
		_add_shape(static_body, position, Vector3(d.length(), wall.size.y, wall.size.z), basis)
	_commit_static_mesh(walls, _tile_surface(Color("aa997e"), true))
	if expedition_view:
		# The old orbit view needed a cutaway roof. First person needs an interior ceiling.
		var ceiling := SurfaceTool.new()
		ceiling.begin(Mesh.PRIMITIVE_TRIANGLES)
		for cell: Vector2i in _walkable_cells:
			ceiling.append_from(tile, 0, Transform3D(Basis.IDENTITY, Vector3(cell.x + 0.5, 2.49, cell.y + 0.5)))
		_commit_static_mesh(ceiling, _material(Color("30383a")))
	_avatar_root = Node3D.new()
	_object_root = Node3D.new()
	_geometry.add_child(_avatar_root)
	_geometry.add_child(_object_root)
	_update_lot_avatars()
	_rebuild_objects()
	var center := Vector3(floor_bounds.get_center().x, 0.0, floor_bounds.get_center().y)
	_camera.projection = Camera3D.PROJECTION_PERSPECTIVE
	_camera.position = center + Vector3(1, 10, 8)
	_camera.look_at(center)
	_lights = Lighting.new()
	_geometry.add_child(_lights)
	_lights.build(_lot, center)
	set_hour(_hour)
	if _art != null and _mode == "blueprint" and _template in ACADEMY_TEMPLATES:
		_art.dress_shell(_geometry, _template, _lot)


func _build_window(wall_center: Vector3, basis: Basis, width: float) -> void:
	var anchor := Node3D.new()
	_geometry.add_child(anchor)
	anchor.transform = Transform3D(basis, Vector3(wall_center.x, 0, wall_center.z))
	var plaster := _material(Color("aeb8b5"))
	var frame := _material(Color("43362f"))
	var glass := _material(Color(0.39, 0.74, 0.89, 0.30))
	glass.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	glass.roughness = 0.18
	_window_part(anchor, Vector3(0, 0.40, 0), Vector3(width, 0.80, 0.13), plaster)
	_window_part(anchor, Vector3(0, 2.285, 0), Vector3(width, 0.33, 0.13), plaster)
	for x in [-width * 0.45, width * 0.45, 0.0]:
		_window_part(anchor, Vector3(x, 1.46, 0), Vector3(0.09, 1.32, 0.19), frame)
	for y in [0.83, 1.46, 2.09]:
		_window_part(anchor, Vector3(0, y, 0), Vector3(width, 0.07, 0.21), frame)
	_window_part(anchor, Vector3(0, 1.46, 0), Vector3(width - 0.12, 1.24, 0.018), glass)


static func _window_part(anchor: Node3D, point: Vector3, dimensions: Vector3, material: Material) -> void:
	var mesh := BoxMesh.new()
	mesh.size = dimensions
	mesh.material = material
	var part := MeshInstance3D.new()
	part.mesh = mesh
	part.position = point
	anchor.add_child(part)


func _rebuild_objects() -> void:
	for child in _object_root.get_children():
		_object_root.remove_child(child)
		child.queue_free()
	for item: Dictionary in _lot.objects:
		if item.role == "window" or item.get("layout_only", false): continue
		var anchor := Node3D.new()
		_object_root.add_child(anchor)
		anchor.position = _world(item.position)
		anchor.rotation.y = item.yaw
		anchor.set_meta("native_guid", item.guid)
		var role: String = item.role
		var marker := MeshInstance3D.new()
		var body := BoxMesh.new()
		var word := String(item.label).to_lower()
		body.size = Vector3(0.74, 0.70, 0.66)
		if "table" in word or "desk" in word or "counter" in word: body.size = Vector3(0.94, 0.76, 0.64)
		if "shelf" in word or "cabinet" in word or "bookcase" in word: body.size = Vector3(0.82, 1.48, 0.40)
		if role in ["entry", "exit"] or item.get("annotation_only", false): body.size = Vector3(0.76, 0.035, 0.76)
		body.material = _material(Color("5ba47f") if role == "entry" else Color("ce9b58") if role == "exit" else Color("866d55"))
		var populated := false
		if not item.get("annotation_only", false) and _art != null:
			populated = _art.populate_object(anchor, _template if _mode == "blueprint" else "", item)
		if not populated:
			populated = Silhouette.populate(anchor, int(item.guid))
		if not populated:
			marker.mesh = body
			marker.position.y = body.size.y * 0.5
			anchor.add_child(marker)
		else:
			marker.free()


func _spawn_if_needed() -> void:
	if is_instance_valid(_player):
		var current_cell := Vector2i(floori(_player.position.x), floori(_player.position.z))
		if not _walkable_cells.has(current_cell) or _player.position.y < -0.75:
			if not _walkable_cells.is_empty(): _player.spawn_at(_spawn_point())
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
		if is_instance_valid(_kitchen): _player.set_room_camera(0.20,3.0)
	else:
		_player.orbit_by(Vector2(0.0, 380.0))
	_player.spawn_at(point, _spawn_yaw(point))


func _drop_player() -> void:
	if is_instance_valid(_followers):
		_viewport.remove_child(_followers)
		_followers.queue_free()
		_followers = null
	if is_instance_valid(_player):
		_viewport.remove_child(_player)
		_player.queue_free()
	_player = null


func _spawn_point() -> Vector3:
	if is_instance_valid(_kitchen): return Kitchen.SPAWN
	for object: Dictionary in _lot.objects:
		if object.role == "entry":
			var interior: Vector2 = object.get("interior", object.position)
			var start := _nearest_walkable(interior)
			var step := Vector2i((interior - Vector2(object.position)).normalized().round())
			var cell := Vector2i(floori(start.x), floori(start.z))
			for i in 2:
				var next := cell + step
				if not _is_clear_cell(next) or _has_wall_between(cell, next): break
				cell = next
			return _world(Vector2(cell) + Vector2(0.5, 0.5))
	# A genuine floor tile is a safe fallback when an imported snapshot has no entry annotation.
	var bounds := Rect2i(_lot.floors[0], Vector2i.ONE)
	for cell: Vector2i in _lot.floors:
		bounds = bounds.merge(Rect2i(cell, Vector2i.ONE))
	return _nearest_walkable(Vector2(bounds.get_center()))


func _spawn_yaw(_point: Vector3) -> float:
	for item: Dictionary in _lot.objects:
		if item.role == "entry" and item.has("interior"):
			var inward: Vector2 = item.interior - item.position
			if inward.length_squared() > 0.01:
				return atan2(-inward.x, -inward.y)
	return NAN


func _nearest_walkable(point: Vector2) -> Vector3:
	var best := INF
	var result := Vector3.ZERO
	for cell: Vector2i in _walkable_cells:
		if not _is_clear_cell(cell): continue
		var center := Vector2(cell) + Vector2(0.5, 0.5)
		var distance := center.distance_squared_to(point)
		if distance < best:
			best = distance
			result = _world(center)
	if best == INF and not _walkable_cells.is_empty():
		var first: Vector2i = _walkable_cells.keys()[0]
		return _world(Vector2(first) + Vector2(0.5, 0.5))
	return result


func _is_clear_cell(cell: Vector2i) -> bool:
	if not _walkable_cells.has(cell): return false
	var center := Vector2(cell) + Vector2(0.5, 0.5)
	for item: Dictionary in _lot.objects:
		if not item.get("annotation_only", false) and item.role not in ["window", "entry", "exit"] and center.distance_to(item.position) < 0.48:
			return false
	for edge: Vector4i in _lot.segments:
		if edge.x != edge.z and edge.y != edge.w and Vector2(edge.x + edge.z, edge.y + edge.w) * 0.5 == center:
			return false
	return true


func _has_wall_between(from: Vector2i, to: Vector2i) -> bool:
	if from == to: return false
	var edge: Vector4i
	if from.x != to.x:
		var x := maxi(from.x, to.x)
		edge = Vector4i(x, from.y, x, from.y + 1)
	else:
		var y := maxi(from.y, to.y)
		edge = Vector4i(from.x, y, from.x + 1, y)
	return edge in _lot.segments


func _refresh_targets() -> void:
	_targets.clear()
	_can_interact = false
	if _lot.is_empty() or not is_instance_valid(_player):
		return
	var focus: Dictionary = {}
	var portals: Array[Dictionary] = []
	var entrances: Array[Dictionary] = []
	for item: Dictionary in _lot.objects:
		if item.role == "exit": portals.append(item)
		if item.role == "entry": entrances.append(item)
		if item.role in ["focal", "inspect"] and (focus.is_empty() or focus.role not in ["focal", "inspect"]): focus = item
		elif focus.is_empty() and item.role not in ["entry", "exit", "window"]: focus = item
	if _inspection_active and _exits.is_empty():
		if is_instance_valid(_night_root):
			_targets.append({"kind": "inspect", "position": _night_anchor, "label": "the threshold"})
		elif not focus.is_empty():
			_targets.append({"kind": "inspect", "position": _world(focus.position), "label": _item_name(focus, "Landmark")})
	if _night_open and _night_stage == "rain":
		for i in _lanes.size():
			_targets.append({"kind": "lane", "index": i, "position": _lanes[i], "label": "brass strip" if i == 0 else "red strip"})
	if portals.size() < _exits.size():
		portals.append_array(entrances)
	if expedition_view:
		_sync_gates(portals)
		for i in _gate_positions:
			_targets.append({"kind": "exit", "index": i, "position": _gate_positions[i], "label": _exit_label(i)})
	else:
		for i in mini(portals.size(), _exits.size()):
			_targets.append({"kind": "exit", "index": i, "position": _portal_position(portals[i]), "label": _exit_label(i)})
	if is_instance_valid(_kitchen): _targets.append_array(_kitchen.targets())
	if not is_instance_valid(_focus_ring):
		_focus_ring = MeshInstance3D.new()
		var ring := TorusMesh.new()
		ring.inner_radius = 0.46
		ring.outer_radius = 0.51
		ring.material = _material(Color("74c9b0"), Color("569986"))
		_focus_ring.mesh = ring
		_geometry.add_child(_focus_ring)
	_focus_ring.visible = not _targets.is_empty() and _targets[0].kind == "inspect"
	if _focus_ring.visible: _focus_ring.position = _targets[0].position + Vector3.UP * 0.06


func _portal_position(portal: Dictionary) -> Vector3:
	var center := _nearest_walkable(portal.get("interior", portal.position))
	return _world(portal.position).lerp(center, 0.25)


func _refresh_ui() -> void:
	var has_lot := not _lot.is_empty()
	var plan_mode := has_lot and (_plan_open or not is_instance_valid(_player))
	_pixels.visible = has_lot and not plan_mode
	_plan.visible = plan_mode
	_level_button.visible = plan_mode and _mode == "blueprint" and not _upper_plan.is_empty()
	_level_button.text = "Floor %d · switch" % _plan_level
	_plan.set_lot(_upper_plan if _level_button.visible and _plan_level == 2 else _lot)
	_plan_button.visible = has_lot and is_instance_valid(_player)
	_plan_button.text = "Walk view" if _plan_open else "Overhead plan"
	var heading := "Topology navigation · no native lot available"
	if has_lot:
		heading = "Native lot plan" if plan_mode else ("First person" if expedition_view else "Native lot · Walk view")
		if _mode == "snapshot":
			var source := "Live FreeSO VM" if _lot.source_kind == "live-vm" else "Saved FreeSO VM"
			heading += " · %s, floor %d" % [source, _lot_level]
	_heading.text = "%s  |  %s" % [heading, _room_label]
	if is_instance_valid(_player): _player.set_controls_enabled(not plan_mode and not _modal)
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
	if not is_instance_valid(_player): return result
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
		_prompt.text = "Travel links" if not _exits.is_empty() else ""
	elif target.is_empty():
		_prompt.text = "WASD · Move   |   Click to look / Esc to release" if expedition_view else "WASD · Move     Q / R or right-drag · Orbit"
	else:
		var verb := "Inspect" if target.kind == "inspect" else ("Operate" if target.kind == "fixture" else "Travel")
		_prompt.text = "E / A / Click · %s %s" % [verb, target.label] if _can_interact else "Approach · " + target.label


func _input(event: InputEvent) -> void:
	if not expedition_view or _modal or _plan_open or not is_instance_valid(_player): return
	if Input.mouse_mode != Input.MOUSE_MODE_CAPTURED: return
	if event is InputEventMouseMotion:
		_player.orbit_by(event.screen_relative)
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
	# Check native walls and line of sight before firing a nearby interaction.
	var start := _player.position + Vector3.UP * 0.65
	var destination: Vector3 = target.position + Vector3.UP * 0.65
	if start.distance_squared_to(destination) > 0.01:
		var query := PhysicsRayQueryParameters3D.create(start, destination, 1)
		if not _viewport.find_world_3d().direct_space_state.intersect_ray(query).is_empty():
			return false
	return true


func _activate(target: Dictionary) -> bool:
	if not _is_reachable(target): return false
	if target.kind == "fixture":
		if not is_instance_valid(_kitchen) or not _kitchen.toggle(target.id, _player.global_position): return false
		_player.play_action("interact")
		return true
	_player.play_action("interact")
	if target.kind == "inspect":
		set_inspection_target(false)
		landmark_inspected.emit()
	elif target.kind == "lane":
		lane_selected.emit(target.index)
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
			var anchor := p + Vector3.UP * 0.5
			if camera != null and not camera.is_position_behind(anchor):
				var projected := camera.unproject_position(anchor) / Vector2(_viewport.size) * _pixels.size + _pixels.global_position
				info.screen_position = [projected.x, projected.y]
		targets.append(info)
	if is_instance_valid(_player):
		var p := _player.position
		player.position = [p.x, p.y, p.z]
	var velocity: Variant = player.get("velocity")
	if velocity is Vector3: player.velocity = [velocity.x, velocity.y, velocity.z]
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
	return player


static func _world(point: Vector2) -> Vector3:
	return Vector3(point.x, 0.0, point.y)


static func _item_name(item: Dictionary, fallback: String) -> String:
	var title: String = item.label
	return fallback if title.is_empty() else title


static func _add_shape(body: StaticBody3D, point: Vector3, size: Vector3, basis := Basis.IDENTITY) -> void:
	var shape := BoxShape3D.new()
	shape.size = size
	var collision := CollisionShape3D.new()
	collision.shape = shape
	collision.transform = Transform3D(basis, point)
	body.add_child(collision)


func _commit_static_mesh(surface: SurfaceTool, material: Material) -> void:
	var mesh := surface.commit()
	if mesh == null or mesh.get_surface_count() == 0:
		return
	var instance := MeshInstance3D.new()
	instance.mesh = mesh
	instance.material_override = material
	instance.gi_mode = GeometryInstance3D.GI_MODE_STATIC
	_geometry.add_child(instance)


func _update_lot_avatars() -> void:
	var positions: PackedVector2Array = _lot.avatars
	while _avatar_root.get_child_count() > positions.size():
		var last := _avatar_root.get_child(-1)
		_avatar_root.remove_child(last)
		last.queue_free()
	var silhouette := CapsuleMesh.new()
	silhouette.radius = 0.19
	silhouette.height = 0.88
	silhouette.material = _material(Color("eab46e"), Color("986034"))
	for i in positions.size():
		if i == _avatar_root.get_child_count():
			var marker := MeshInstance3D.new()
			marker.mesh = silhouette
			_avatar_root.add_child(marker)
		var marker := _avatar_root.get_child(i) as MeshInstance3D
		marker.position = Vector3(positions[i].x, 0.44, positions[i].y)


func _exit_label(index: int) -> String:
	var entry: Variant = _exits[index]
	var fallback := "Exit %d" % (index + 1)
	var text := str(entry.get("label", fallback)) if entry is Dictionary else (str(entry) if entry is String else fallback)
	text = text.replace("\n", " ").strip_edges()
	if text.is_empty():
		return fallback
	return text


func _material(color: Color, emission := Color.BLACK) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = 0.89
	if emission != Color.BLACK:
		material.emission_enabled = true
		material.emission = emission
	return material

## The camp AI and the player use the same floor, furniture and wall edges.
func camp_layout(names: Array) -> Dictionary:
	var graph := {}
	for cell: Vector2i in _walkable_cells:
		if _is_clear_cell(cell): graph[cell] = []
	for cell: Vector2i in graph:
		for dir: Vector2i in [Vector2i.LEFT, Vector2i.UP, Vector2i.RIGHT, Vector2i.DOWN]:
			if graph.has(cell + dir) and not _has_wall_between(cell, cell + dir): graph[cell].append(cell + dir)
	var objects := []
	var taken := {}
	for item: Dictionary in _lot.get("objects", []):
		var need: String = {0x06ea4309:"hunger", 0x68ea432a:"fatigue", 0x5dea43f0:"social"}.get(item.guid, "")
		if need.is_empty(): continue
		var cell := Vector2i(item.position)
		for dir: Vector2i in [Vector2i.DOWN, Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP]:
			var stand := cell + dir
			if graph.has(stand) and not taken.has(stand) and not _has_wall_between(cell, stand):
				taken[stand] = true
				var title: String = {"hunger":"Meal table", "fatigue":"Armchair", "social":"Common table seat"}[need]
				objects.append({"id":"%s (%d,%d)" % [title,cell.x,cell.y], "stand":stand, "need":need, "duration":12, "relief":55})
				break
	var people := []
	if is_instance_valid(_player): taken[Vector2i(_player.position.x, _player.position.z)] = true
	for cell: Vector2i in graph:
		if people.size() == names.size(): break
		if taken.has(cell): continue
		var index := people.size()
		people.append({"id":names[index], "cell":cell,"needs":{"hunger":75 if index % 3 == 0 else 20,"fatigue":75 if index % 3 == 1 else 20,"social":75 if index % 3 == 2 else 20}})
	return {"graph":graph, "objects":objects, "people":people}


func _release_mouse() -> void:
	if expedition_view and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func set_modal(active: bool) -> void:
	_modal = active
	if active:
		_release_mouse()
		_clicks.clear()
		_keyboard_interact = false
	if is_instance_valid(_player): _player.set_controls_enabled(not _plan_open and not _modal)


func is_walking_view() -> bool:
	return not _plan_open and not _modal and is_instance_valid(_player)


func lane_at_feet() -> int:
	if not is_walking_view(): return -1
	for i in _lanes.size():
		if _flat_distance(_lanes[i]) <= 0.64: return i
	return -1


func set_night(stage: String, variant: bool, route_open: bool, stability: int, safe_room: bool) -> void:
	if not expedition_view or _veil_material == null: return
	var changed := _night_stage != stage or _night_variant != variant
	_night_stage = stage
	_night_variant = variant
	_night_open = route_open
	if changed and is_instance_valid(_night_root):
		_geometry.remove_child(_night_root)
		_night_root.queue_free()
		_night_root = null
		_lanes.clear()
	if not stage.is_empty() and not is_instance_valid(_night_root) and is_instance_valid(_player):
		_build_threshold(stage)
	var climate := "shelter" if safe_room else stage
	if is_instance_valid(_lights): _lights.apply(_hour, "ember" if _template == "kitchen" and stage.is_empty() else climate)
	set_stability(stability)
	_veil_material.set_shader_parameter("rainfall", 0.95 if stage == "rain" else 0.0)
	_veil_material.set_shader_parameter("unrest", float(stage in ["echo", "rewrite", "rain"]))
	_refresh_targets()


func set_stability(value: int) -> void:
	_stability = value
	if _veil_material == null: return
	_veil_material.set_shader_parameter("fracture", clampf((76.0 - value) / 76.0, 0.0, 1.0))
	if is_instance_valid(_echo_glass): _echo_glass.visible = value < 65


func _build_threshold(stage: String) -> void:
	_night_root = Node3D.new()
	_geometry.add_child(_night_root)
	_night_anchor = _spawn_point()
	var spawn := Vector2i(floori(_night_anchor.x), floori(_night_anchor.z))
	var directions := [Vector2i.UP, Vector2i.RIGHT, Vector2i.DOWN, Vector2i.LEFT]
	var camera: Camera3D = _player.camera()
	var look := -camera.global_basis.z
	var direction := Vector2i(roundi(look.x), 0) if absf(look.x) > absf(look.z) else Vector2i(0, roundi(look.z))
	if direction != Vector2i.ZERO:
		directions.erase(direction)
		directions.push_front(direction)
	var paths: Array[Vector3] = []
	for dir: Vector2i in directions:
		var first := spawn + dir
		if not _is_clear_cell(first) or _has_wall_between(spawn, first): continue
		var second := first + dir
		var end := second if _is_clear_cell(second) and not _has_wall_between(first, second) else first
		paths.append(_world(Vector2(end) + Vector2(0.5, 0.5)))
	var marker := _night_anchor + (paths[0] - _night_anchor).normalized() * 0.78 if not paths.is_empty() else _night_anchor + Vector3.FORWARD * 0.78
	var lamp := OilLamp.instantiate()
	lamp.hang_length = 0.53
	lamp.light_energy = 1.5
	lamp.shadow_enabled = false
	lamp.position = marker + Vector3.UP * 2.37
	_night_root.add_child(lamp)
	lamp.set_wind(Vector3(6, 0, -2) if stage == "rain" else Vector3.ZERO)
	match stage:
		"echo":
			_set_clock(marker)
			_echo_glass = _plaque("REFLECTION\n" + ("04:10" if _night_variant else "04:11"), marker + Vector3.UP * 2.03, Color("8ba9cc"))
		"rewrite":
			_plaque("THE CURATOR\nCROSS BEFORE THE BELL", marker + Vector3.UP * 1.62, Color("ff8278"))
			_plaque("II · DOUBLE SEAL" if _night_variant else "I · BROKEN SEAL", marker + Vector3.UP * 0.16, Color("fbd3a2"))
		"rain":
			if paths.size() < 2:
				# Keep both choices usable even in a narrow lot. Both terminate on walkable floor.
				if paths.is_empty(): paths.append(_night_anchor)
				paths.append(_night_anchor)
			for i in 2:
				_lanes.append(paths[i])
				var tint := Color("ffcf82") if i == 0 else Color("ea6864")
				var strip := BoxMesh.new()
				var length := maxf(0.22, _night_anchor.distance_to(paths[i]))
				strip.size = Vector3(0.25, 0.018, length)
				var mesh := MeshInstance3D.new()
				mesh.mesh = strip
				mesh.material_override = _material(tint, tint.darkened(0.42))
				_night_root.add_child(mesh)
				mesh.position = _night_anchor.lerp(paths[i], 0.5) + Vector3.UP * 0.025
				if length > 0.23: mesh.look_at(paths[i] + Vector3.UP * 0.025)
				_plaque("BRASS" if i == 0 else "RED", paths[i] + Vector3.UP * 0.52, tint)


func _plaque(text: String, point: Vector3, tint: Color, parent: Node3D = null) -> Label3D:
	var sign := Label3D.new()
	sign.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	sign.text = text
	sign.font_size = 42
	sign.pixel_size = 0.0024
	sign.modulate = tint
	sign.outline_size = 13
	sign.position = point
	(_night_root if parent == null else parent).add_child(sign)
	return sign


func repeat_threshold() -> void:
	if is_instance_valid(_player):
		var point := _spawn_point()
		_player.spawn_at(point, _spawn_yaw(point))
	for sign in _night_root.get_children() if is_instance_valid(_night_root) else []:
		if sign.name == "ThresholdClock":
			sign.get_node("Minute").rotation.z = -TAU * 10.0 / 60.0
			sign.get_node("FaceTime").text = "04:10"


func _sync_gates(portals: Array[Dictionary]) -> void:
	if is_instance_valid(_gate_root) and _gate_labels == _exits: return
	if is_instance_valid(_gate_root):
		_geometry.remove_child(_gate_root)
		_gate_root.queue_free()
	_gate_positions.clear()
	_gate_labels = _exits.duplicate()
	_gate_root = Node3D.new()
	_geometry.add_child(_gate_root)
	var cells := _reachable_cells()
	for i in _exits.size():
		var at := Vector3.ZERO
		if i < portals.size(): at = _portal_position(portals[i])
		if i >= portals.size() or _gate_positions.values().any(func(p: Vector3): return at.distance_squared_to(p) < 0.64):
			# The topology can have more doors than a native blueprint. Dress the surplus
			# as folded thresholds on reachable floor rather than leaving them menu-only.
			for cell in cells:
				var candidate := _world(Vector2(cell) + Vector2(0.5, 0.5))
				if candidate.distance_squared_to(_spawn_point()) < 4.0: continue
				if _gate_positions.values().any(func(p: Vector3): return candidate.distance_squared_to(p) < 2.0): continue
				at = candidate
				break
		if at == Vector3.ZERO: continue
		var tint := Color("e7bb77") if not str(_exits[i]).begins_with("E") else Color("9bc7c5")
		_gate_positions[i] = at
		_plaque(_exit_label(i), at + Vector3.UP * 1.90, tint, _gate_root)
		var plinth := MeshInstance3D.new()
		var slab := BoxMesh.new()
		slab.size = Vector3(0.78, 0.024, 0.42)
		plinth.mesh = slab
		plinth.material_override = _material(tint.darkened(0.43), tint.darkened(0.52))
		_gate_root.add_child(plinth)
		plinth.position = at + Vector3.UP * 0.029


func _reachable_cells(limit := 120) -> Array[Vector2i]:
	var start := _spawn_point()
	var cell := Vector2i(floori(start.x), floori(start.z))
	var result: Array[Vector2i] = [cell]
	var seen := {cell: true}
	var cursor := 0
	while cursor < result.size() and result.size() < limit:
		var from := result[cursor]
		for dir: Vector2i in [Vector2i.UP, Vector2i.RIGHT, Vector2i.DOWN, Vector2i.LEFT]:
			var next := from + dir
			if not seen.has(next) and _is_clear_cell(next) and not _has_wall_between(from, next):
				seen[next] = true
				result.append(next)
		cursor += 1
	return result


func set_field_party(names: Array) -> void:
	if not is_instance_valid(_player): return
	if is_instance_valid(_followers):
		_followers.sync(names)
		return
	if names.is_empty(): return
	_followers = Followers.new()
	_viewport.add_child(_followers)
	var points: Array[Vector3] = []
	var origin := _spawn_point()
	var cells := _reachable_cells(12)
	var back: Vector3 = _player.camera().global_basis.z
	var cursor := Vector2i(floori(origin.x), floori(origin.z))
	var seen := {cursor: true}
	var previous := back
	for i in 4:
		var best_score := -INF
		var chosen := cursor
		for dir: Vector2i in [Vector2i.UP, Vector2i.RIGHT, Vector2i.DOWN, Vector2i.LEFT]:
			var next := cursor + dir
			if seen.has(next) or not cells.has(next) or _has_wall_between(cursor, next): continue
			var score := Vector3(dir.x, 0.0, dir.y).dot(previous)
			if score > best_score:
				best_score = score
				chosen = next
		if cursor == chosen: break
		previous = Vector3(chosen.x - cursor.x, 0.0, chosen.y - cursor.y)
		cursor = chosen
		seen[chosen] = true
		points.append(_world(Vector2(cursor) + Vector2(0.5, 0.5)))
	_followers.setup(_player, points)
	_followers.sync(names)


func _clock_piece(parent: Node3D, mesh: Mesh, tint: Color, at: Vector3) -> MeshInstance3D:
	var piece := MeshInstance3D.new()
	piece.mesh = mesh
	piece.material_override = _material(tint)
	parent.add_child(piece)
	piece.position = at
	return piece


func _set_clock(at: Vector3) -> void:
	var clock := Node3D.new()
	clock.name = "ThresholdClock"
	_night_root.add_child(clock)
	clock.position = at
	var towards := _night_anchor - at
	clock.rotation.y = atan2(towards.x, towards.z)
	var post := BoxMesh.new()
	post.size = Vector3(0.12, 1.44, 0.12)
	_clock_piece(clock, post, Color("392922"), Vector3(0, 0.72, -0.065))
	var brass := CylinderMesh.new()
	brass.top_radius = 0.24
	brass.bottom_radius = 0.24
	brass.height = 0.11
	_clock_piece(clock, brass, Color("a48350"), Vector3(0, 1.48, 0)).rotation.x = PI / 2.0
	var dial := CylinderMesh.new()
	dial.top_radius = 0.193
	dial.bottom_radius = 0.193
	dial.height = 0.011
	_clock_piece(clock, dial, Color("ded4af"), Vector3(0, 1.48, 0.064)).rotation.x = PI / 2.0
	for i in 12:
		var radians := TAU * i / 12.0
		var tick := BoxMesh.new()
		tick.size = Vector3(0.006, 0.019, 0.004)
		var offset := Vector3(sin(radians) * 0.167, cos(radians) * 0.167, 0.073)
		_clock_piece(clock, tick, Color("372b21"), offset + Vector3.UP * 1.48).rotation.z = -radians
	for i in 2:
		var hand := Node3D.new()
		hand.name = "Hour" if i == 0 else "Minute"
		clock.add_child(hand)
		hand.position = Vector3(0, 1.48, 0.082 + i * 0.008)
		hand.rotation.z = -TAU * (4.18 / 12.0 if i == 0 else (11.0 if _night_variant else 10.0) / 60.0)
		var mesh := BoxMesh.new()
		mesh.size = Vector3(0.012 if i == 0 else 0.007, 0.101 if i == 0 else 0.144, 0.005)
		_clock_piece(hand, mesh, Color("46352a"), Vector3.UP * (mesh.size.y * 0.43))
	var label := _plaque("04:11" if _night_variant else "04:10", Vector3(0, 1.196, 0.074), Color("f5d79c"), clock)
	label.name = "FaceTime"
	label.billboard = BaseMaterial3D.BILLBOARD_DISABLED
	label.pixel_size = 0.00096
