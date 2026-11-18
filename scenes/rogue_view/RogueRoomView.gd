extends Control
## Isolated Forward+ room. Instantiate RogueRoomView.tscn under a Control.

signal exit_selected(index: int)

const FreeSoSnapshot = preload("res://scenes/rogue_view/FreeSoSnapshot.gd")

const EXIT_LAYER := 1 << 7
const EXIT_PITCH := 2.55
const MAX_COLUMNS := 5
const ROW_PITCH := 4.6

@onready var _viewport: SubViewport = $RoomViewport
@onready var _geometry: Node3D = $RoomViewport/Geometry
@onready var _camera: Camera3D = $RoomViewport/Camera3D
@onready var _title: Label = $RoomViewport/Title
@onready var _pixels: TextureRect = $Frame/Pixels

var _lot: Dictionary = {}
var _lot_level := 1
var _lot_navigation: HFlowContainer
var _lot_avatars: Node3D
var _room_label := ""
var _exits: Array = []
var _nameplates: Array[Label] = []
var _pending_clicks: Array[Vector2] = []

func _ready() -> void:
	_pixels.gui_input.connect(_on_pixels_input)
	_lot_navigation = HFlowContainer.new()
	_lot_navigation.alignment = FlowContainer.ALIGNMENT_CENTER
	_lot_navigation.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_pixels.add_child(_lot_navigation)
	_lot_navigation.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	_lot_navigation.offset_left = 8
	_lot_navigation.offset_right = -8
	_lot_navigation.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_lot_navigation.offset_top = -8
	_lot_navigation.offset_bottom = -8
	_rebuild()


## Exit entries can be strings or dictionaries with a `label` field.
## The signal reports the original zero-based index. Safe before adding to the tree.
func set_room(label: String, exits: Array) -> void:
	_lot.clear()
	_room_label = label
	_exits = exits.duplicate(true)
	_pending_clicks.clear()
	if is_node_ready():
		_rebuild()


## Load a snapshot for this presentation. Failure switches to the topology map.
func set_freeso_room(label: String, exits: Array, path: String, level: int = 1) -> Error:
	var result := FreeSoSnapshot.read_file(path, level)
	return _use_freeso_room(label, exits, level, result)


## Apply a snapshot already decoded from JSON. Safe before adding to the tree.
func set_freeso_snapshot(label: String, exits: Array, snapshot: Dictionary, level: int = 1) -> Error:
	return _use_freeso_room(label, exits, level, FreeSoSnapshot.decode(snapshot, level))


func _use_freeso_room(label: String, exits: Array, level: int, result: Dictionary) -> Error:
	var lot: Dictionary = result.get("lot", {})
	var same_architecture: bool = not lot.is_empty() and not _lot.is_empty() and _lot_level == level \
		and lot.width == _lot.width and lot.height == _lot.height and lot.segments == _lot.segments and lot.floors == _lot.floors
	var avatar_update_only: bool = same_architecture and label == _room_label and exits == _exits
	_room_label = label
	_exits = exits.duplicate(true)
	_lot_level = level
	_lot = lot
	_pending_clicks.clear()
	if is_node_ready():
		if avatar_update_only:
			_update_lot_avatars()
		else:
			_rebuild()
	return result.error


func _rebuild() -> void:
	_lot_avatars = null
	for child in _geometry.get_children():
		_geometry.remove_child(child)
		child.queue_free()
	for plate in _nameplates:
		_viewport.remove_child(plate)
		plate.queue_free()
	_nameplates.clear()
	for button in _lot_navigation.get_children():
		_lot_navigation.remove_child(button)
		button.queue_free()
	_lot_navigation.visible = not _lot.is_empty()
	if _lot_navigation.visible:
		_title.text = "FreeSO VM snapshot · Floor %d\n%s" % [_lot_level, _room_label]
		_rebuild_lot()
		return
	_title.text = "Topology navigation map\n%s" % _room_label

	var columns := clampi(_exits.size(), 1, MAX_COLUMNS)
	var rows := maxi(1, ceili(float(_exits.size()) / MAX_COLUMNS))
	var width := maxf(8.0, columns * EXIT_PITCH + 2.0)
	var depth := 7.0 + (rows - 1) * ROW_PITCH
	var center_z := (rows - 1) * ROW_PITCH * 0.5
	_camera.position = Vector3(0, 11, center_z + 10)
	_camera.look_at(Vector3(0, 0.8, center_z))
	_camera.size = maxf(maxf(8.7, (width + 1.0) * 9.0 / 16.0), depth * 0.76 + 3.9)

	var basalt := _material(Color("344254"))
	var stone := _material(Color("53657a"))
	var trim := _material(Color("8694a1"))
	var slate := _material(Color("202c3e"))
	var copper := _material(Color("ae8053"))
	var lamp := _material(Color("ffa958"), Color("ff9a43"))
	_box(Vector3(0, -0.28, center_z), Vector3(width, 0.5, depth), basalt)
	for x in range(ceili(width)):
		for z in range(ceili(depth)):
			var tile := stone if (x + z * 7) % 5 == 0 else basalt
			_box(Vector3(x - (ceili(width) - 1) * 0.5, -0.039, z + center_z - (ceili(depth) - 1) * 0.5),
					Vector3(0.96, 0.09, 0.96), tile)
	_box(Vector3(0, 0.95, center_z - depth * 0.5), Vector3(width, 2.5, 0.42), stone)
	for side in [-1.0, 1.0]:
		var x: float = side * (width * 0.5 - 0.14)
		_box(Vector3(x, 0.3, center_z), Vector3(0.4, 0.75, depth), stone)
		_box(Vector3(x, 0.72, center_z), Vector3(0.54, 0.15, depth), trim)
		_box(Vector3(x, 1.24, center_z - depth * 0.5 + 0.6), Vector3(0.7, 2.6, 0.7), stone)
		_box(Vector3(x, 2.61, center_z - depth * 0.5 + 0.6), Vector3(0.87, 0.22, 0.87), lamp)
		_light(Vector3(x * 0.84, 2.65, center_z - depth * 0.5 + 1.2), Color("ffc385"), 2.1, 7.0)
	_light(Vector3(0, 6.0, center_z + 2.0), Color("9ebcff"), 3.6, maxf(13.0, depth))

	for index in _exits.size():
		@warning_ignore("integer_division")
		var row := index / MAX_COLUMNS
		var row_count := mini(MAX_COLUMNS, _exits.size() - row * MAX_COLUMNS)
		var x := (index % MAX_COLUMNS - (row_count - 1) * 0.5) * EXIT_PITCH
		var door := Vector3(x, 0, row * ROW_PITCH - 0.75)
		_box(door + Vector3(0, 0.1, 0.58), Vector3(1.85, 0.2, 1.65), stone)
		_box(door + Vector3(0, 1.12, -0.1), Vector3(1.42, 2.16, 0.34), slate)
		for side in [-1.0, 1.0]:
			_box(door + Vector3(side * 0.78, 1.14, 0), Vector3(0.24, 2.28, 0.52), trim)
		_box(door + Vector3(0, 2.28, 0), Vector3(1.85, 0.28, 0.56), trim)
		_box(door + Vector3(0.41, 1.05, 0.11), Vector3(0.16, 0.13, 0.16), copper)
		_box(door + Vector3(0, 2.51, 0), Vector3(0.54, 0.13, 0.32), lamp)
		var nameplate := Label.new()
		nameplate.text = _exit_label(index)
		nameplate.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		nameplate.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		nameplate.add_theme_font_size_override(&"font_size", 10)
		nameplate.add_theme_color_override(&"font_color", Color("ffe2b0"))
		nameplate.add_theme_color_override(&"font_outline_color", Color("121a28"))
		nameplate.add_theme_constant_override(&"outline_size", 4)
		var spacing := EXIT_PITCH * _viewport.size.y / _camera.size
		var caption_point := _camera.unproject_position(door + Vector3(0, 0.23, 0.62))
		nameplate.position = (caption_point - Vector2((spacing - 2) * 0.5, 7)).round()
		nameplate.size.x = floorf(spacing - 2)
		_viewport.add_child(nameplate)
		_nameplates.append(nameplate)
		var target := StaticBody3D.new()
		target.position = door + Vector3(0, 1.23, 0)
		target.collision_layer = EXIT_LAYER
		target.collision_mask = 0
		target.set_meta(&"exit_index", index)
		var hitbox := CollisionShape3D.new()
		var shape := BoxShape3D.new()
		shape.size = Vector3(1.85, 2.6, 0.6)
		hitbox.shape = shape
		target.add_child(hitbox)
		var threshold := CollisionShape3D.new()
		var threshold_shape := BoxShape3D.new()
		threshold_shape.size = Vector3(1.85, 0.25, 1.65)
		threshold.shape = threshold_shape
		threshold.position = Vector3(0, -1.08, 0.58)
		target.add_child(threshold)
		_geometry.add_child(target)


func _rebuild_lot() -> void:
	var width: float = _lot.width
	var height: float = _lot.height
	var center := Vector3(width * 0.5, 0.4, height * 0.5)
	_camera.position = center + Vector3(0, 13, 10)
	_camera.look_at(center)
	_camera.size = maxf(width * 0.67, height * 0.88 + 2.8)
	if _lot_level == 1:
		_box(Vector3(center.x, -0.12, center.z), Vector3(width, 0.22, height), _material(Color("394653")))
	var tile := BoxMesh.new()
	tile.size = Vector3(1, 0.06, 1)
	var flooring := SurfaceTool.new()
	flooring.begin(Mesh.PRIMITIVE_TRIANGLES)
	for cell: Vector2i in _lot.floors:
		flooring.append_from(tile, 0, Transform3D(Basis.IDENTITY, Vector3(cell.x + 0.5, -0.02, cell.y + 0.5)))
	_commit_static_mesh(flooring, _material(Color("657078")))

	# Values are tile coordinates projected onto the XZ plane. One VM tile is one unit.
	var wall_box := BoxMesh.new()
	wall_box.size = Vector3(1, 1.2, 0.12)
	var walls := SurfaceTool.new()
	walls.begin(Mesh.PRIMITIVE_TRIANGLES)
	for segment: Vector4i in _lot.segments:
		var start := Vector2(segment.x, segment.y)
		var finish := Vector2(segment.z, segment.w)
		var middle := (start + finish) * 0.5
		var direction := finish - start
		var basis := Basis(Vector3.UP, -direction.angle()) * Basis.from_scale(Vector3(direction.length(), 1, 1))
		walls.append_from(wall_box, 0, Transform3D(basis, Vector3(middle.x, 0.6, middle.y)))
	_commit_static_mesh(walls, _material(Color("948c7d")))
	_lot_avatars = Node3D.new()
	_geometry.add_child(_lot_avatars)
	_update_lot_avatars()
	_light(Vector3(center.x, maxf(width, height) * 0.8 + 2.0, center.z + 1), Color("ffe5cb"), 5.0, maxf(width, height) * 2.0 + 6.0)
	# Rogue travel remains an explicit overlay; VM architecture provides no rogue exit mapping.
	for index in _exits.size():
		var button := Button.new()
		button.text = _exit_label(index)
		button.tooltip_text = "Rogue navigation: " + button.text
		button.pressed.connect(func(): exit_selected.emit(index))
		_lot_navigation.add_child(button)


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
	while _lot_avatars.get_child_count() > positions.size():
		var last := _lot_avatars.get_child(-1)
		_lot_avatars.remove_child(last)
		last.queue_free()
	var silhouette := CapsuleMesh.new()
	silhouette.radius = 0.19
	silhouette.height = 0.88
	silhouette.material = _material(Color("eab46e"), Color("986034"))
	for i in positions.size():
		if i == _lot_avatars.get_child_count():
			var marker := MeshInstance3D.new()
			marker.mesh = silhouette
			_lot_avatars.add_child(marker)
		var marker := _lot_avatars.get_child(i) as MeshInstance3D
		marker.position = Vector3(positions[i].x, 0.44, positions[i].y)


func _exit_label(index: int) -> String:
	var entry: Variant = _exits[index]
	var fallback := "Exit %d" % (index + 1)
	var text := str(entry.get("label", fallback)) if entry is Dictionary else (str(entry) if entry is String else fallback)
	text = text.replace("\n", " ").strip_edges()
	if text.is_empty():
		return fallback
	return text


func _on_pixels_input(event: InputEvent) -> void:
	if _lot.is_empty() and event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		if Rect2(Vector2.ZERO, _pixels.size).has_point(event.position):
			_pending_clicks.append(event.position / _pixels.size * Vector2(_viewport.size))
			_pixels.accept_event()


func _physics_process(_delta: float) -> void:
	while not _pending_clicks.is_empty():
		var point: Vector2 = _pending_clicks.pop_front()
		var origin := _camera.project_ray_origin(point)
		var end := origin + _camera.project_ray_normal(point) * _camera.far
		var query := PhysicsRayQueryParameters3D.create(origin, end, EXIT_LAYER)
		var hit := _viewport.find_world_3d().direct_space_state.intersect_ray(query)
		if not hit.is_empty():
			exit_selected.emit(int(hit.collider.get_meta(&"exit_index")))


func _material(color: Color, emission := Color.BLACK) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = 0.89
	if emission != Color.BLACK:
		material.emission_enabled = true
		material.emission = emission
	return material


func _box(pos: Vector3, dimensions: Vector3, material: StandardMaterial3D) -> MeshInstance3D:
	var mesh := BoxMesh.new()
	mesh.size = dimensions
	mesh.material = material
	var instance := MeshInstance3D.new()
	instance.mesh = mesh
	instance.position = pos
	instance.gi_mode = GeometryInstance3D.GI_MODE_STATIC
	_geometry.add_child(instance)
	return instance


func _light(pos: Vector3, color: Color, energy: float, radius: float) -> void:
	var light := OmniLight3D.new()
	light.position = pos
	light.light_color = color
	light.light_energy = energy
	light.omni_range = radius
	light.shadow_enabled = true
	_geometry.add_child(light)
