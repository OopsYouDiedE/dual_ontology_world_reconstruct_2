extends Node3D

const CATALOG_PATH := "res://tools/building_construction/catalog.json"
const Assembly = preload("production/assembly/ComponentAssembly.gd")
const Socket = preload("BuildingConstruction/Shared/MechanismSocket.gd")
const Components = preload("BuildingConstruction/Shared/ComponentFactory.gd")
const CANDIDATE_PATH := "res://tools/building_construction/candidates/BuildingCandidate.tscn"

var camera: Camera3D
var candidates: Node3D
var category: OptionButton
var items: ItemList
var status: Label
var entries: Array = []
var activity_layer: Control
var activity_choices: Dictionary
var catalog: Dictionary
var selected_path := ""
var selected_entry: Dictionary = {}
var selected: Node3D
var outline: ItemList
var inspector: VBoxContainer
var history: Array[PackedScene] = []
var history_index := -1
var reverse_end := false
var rotation_y := 0.0
var orbit := Vector2(-0.7, 0.8)
var distance := 18.0
var target := Vector3.ZERO

func _ready() -> void:
	var file := FileAccess.open(CATALOG_PATH, FileAccess.READ)
	if file == null:
		push_error("Could not open the building catalog.")
		return
	var parsed = JSON.parse_string(file.get_as_text())
	if not parsed is Dictionary:
		push_error("Invalid building catalog.")
		return
	catalog = parsed
	catalog.items = catalog.items.filter(func(entry: Dictionary) -> bool:
		return not entry.get("optional", false) or ResourceLoader.exists(str(entry.path)))
	activity_choices = Socket.choices()
	candidates = Node3D.new()
	candidates.name = "BuilderCandidates"
	add_child(candidates)
	var environment := WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.12, 0.15, 0.19)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color.WHITE
	env.ambient_light_energy = 0.65
	environment.environment = env
	add_child(environment)
	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-55, -35, 0)
	add_child(light)
	camera = Camera3D.new()
	add_child(camera)
	_update_camera()
	_make_grid()
	_make_ui()
	var overlay := CanvasLayer.new(); overlay.layer = 8; add_child(overlay)
	activity_layer = Control.new(); overlay.add_child(activity_layer)
	activity_layer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	activity_layer.hide()
	_remember()

func _make_grid() -> void:
	var mesh := ImmediateMesh.new()
	var surface := StandardMaterial3D.new()
	surface.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	surface.albedo_color = Color(0.28, 0.34, 0.39)
	mesh.surface_begin(Mesh.PRIMITIVE_LINES, surface)
	for line in range(-20, 21):
		mesh.surface_add_vertex(Vector3(line, -0.01, -20))
		mesh.surface_add_vertex(Vector3(line, -0.01, 20))
		mesh.surface_add_vertex(Vector3(-20, -0.01, line))
		mesh.surface_add_vertex(Vector3(20, -0.01, line))
	mesh.surface_end()
	var grid := MeshInstance3D.new()
	grid.mesh = mesh
	add_child(grid)

func _button(parent: Node, label: String, callback: Callable) -> void:
	var button := Button.new()
	button.text = label
	button.pressed.connect(callback)
	parent.add_child(button)

func _make_ui() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)
	var panel := PanelContainer.new()
	panel.position = Vector2(12, 12)
	panel.custom_minimum_size = Vector2(270, 480)
	layer.add_child(panel)
	var column := VBoxContainer.new()
	panel.add_child(column)
	var heading := Label.new()
	heading.text = "Component Library"
	column.add_child(heading)
	category = OptionButton.new()
	column.add_child(category)
	for key in catalog.categories:
		category.add_item(str(catalog.categories[key]))
		category.set_item_metadata(category.item_count - 1, key)
	items = ItemList.new()
	items.custom_minimum_size = Vector2(250, 230)
	column.add_child(items)
	_button(column, "Select / Cancel Placement (Esc)", _cancel)
	var actions := HBoxContainer.new()
	column.add_child(actions)
	_button(actions, "Undo", func(): _restore(history_index - 1))
	_button(actions, "Redo", func(): _restore(history_index + 1))
	_button(actions, "Delete", _delete_selected)
	outline = ItemList.new()
	outline.custom_minimum_size = Vector2(250, 150)
	column.add_child(outline)
	outline.item_selected.connect(func(index: int): _select(outline.get_item_metadata(index)))
	_button(column, "Save Candidate", _save_candidate)
	_button(column, "Open Candidate", _open_candidate)
	_button(column, "Show All Components", _show_catalog)
	_button(column, "Save Screenshot", _capture)
	status = Label.new()
	status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	status.custom_minimum_size.x = 250
	status.text = "Select a component and click its support. R: turn. F: swap end or stair-rail side. Right-drag: orbit. Shift+right-drag: pan. Scroll: zoom."
	column.add_child(status)
	var right := PanelContainer.new()
	right.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	right.offset_left = -290
	right.offset_right = -12
	right.offset_top = 12
	right.offset_bottom = 860
	layer.add_child(right)
	var scroll := ScrollContainer.new()
	right.add_child(scroll)
	inspector = VBoxContainer.new()
	inspector.custom_minimum_size.x = 250
	scroll.add_child(inspector)
	category.item_selected.connect(_refresh)
	items.item_selected.connect(_select_item)
	_refresh(0)

func _refresh(index: int) -> void:
	items.clear()
	entries.clear()
	selected_path = ""
	var key = category.get_item_metadata(index)
	for entry in catalog.items:
		if entry.category == key:
			entries.append(entry)
			var row := items.add_item(str(entry.label))
			items.set_item_tooltip(row, _production_note(entry))

func _production_note(entry: Dictionary) -> String:
	return Components.production_note(entry)

func _select_item(index: int) -> void:
	selected_path = str(entries[index].path)
	selected_entry = entries[index]
	var production := Components.production_note(selected_entry).get_slice("\n", 0)
	status.text = "%s · %s mount\n%s\nClick a support. R: turn. F: swap end." % [selected_entry.label, selected_entry.mount, production]

func _cancel() -> void:
	selected_path = ""
	items.deselect_all()
	status.text = "Select an object in the view or in the list."

func _unhandled_input(event: InputEvent) -> void:
	if activity_layer.visible: return
	if event is InputEventMouseMotion and Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT):
		if Input.is_key_pressed(KEY_SHIFT):
			target += (-camera.global_basis.x * event.relative.x + camera.global_basis.y * event.relative.y) * distance * 0.0015
		else:
			orbit.x -= event.relative.x * 0.008
			orbit.y = clampf(orbit.y + event.relative.y * 0.008, 0.15, 1.45)
		_update_camera()
	elif event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			distance = maxf(3.0, distance - 1.0)
			_update_camera()
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			distance = minf(60.0, distance + 1.0)
			_update_camera()
		elif event.button_index == MOUSE_BUTTON_LEFT:
			if selected_path.is_empty():
				_pick(event.position)
			else:
				_place(event.position)
	elif event is InputEventKey and event.pressed and not event.echo:
		match event.keycode:
			KEY_ESCAPE: _cancel()
			KEY_DELETE: _delete_selected()
			KEY_F:
				reverse_end = not reverse_end
				status.text = "Joining the %s end of the next run." % ("last" if reverse_end else "first")
			KEY_R:
				rotation_y = fposmod(rotation_y + 90.0, 360.0)
				status.text = "Placement angle: %d°" % rotation_y

func _update_camera() -> void:
	camera.position = target + Vector3(sin(orbit.x) * cos(orbit.y), sin(orbit.y), cos(orbit.x) * cos(orbit.y)) * distance
	camera.look_at(target)

func _place(mouse: Vector2) -> void:
	if selected_path.is_empty():
		return
	var origin := camera.project_ray_origin(mouse)
	var ray := camera.project_ray_normal(mouse)
	var hit := _hit(origin,ray)
	var point = hit.position if hit else Plane(Vector3.UP,0.0).intersects_ray(origin,ray)
	if point == null: return
	var host := Assembly.component(hit.collider,candidates) if hit else null
	var instance := _make_part(selected_entry)
	if not instance: return
	candidates.add_child(instance,true)
	var issue := Assembly.place(instance,candidates,host,point,hit.normal if hit else Vector3.UP,rotation_y,reverse_end)
	if not issue.is_empty():
		instance.get_parent().remove_child(instance)
		instance.free()
		status.text = issue
		return
	_remember()
	_select(instance)
	status.text = "Placed %s%s" % [selected_entry.label, " on " + str(host.name) if host else ""]

func _make_part(entry: Dictionary) -> Node3D:
	var part := Components.create_entry(entry)
	if part:
		Assembly.tag(part, entry)
	else:
		status.text = "Could not load " + str(entry.label)
	return part

func _hit(origin: Vector3, ray: Vector3) -> Dictionary:
	return get_world_3d().direct_space_state.intersect_ray(PhysicsRayQueryParameters3D.create(origin,origin+ray*500))

func _pick(mouse: Vector2) -> void:
	var hit := _hit(camera.project_ray_origin(mouse),camera.project_ray_normal(mouse))
	if hit:
		var node := Assembly.component(hit.collider,candidates)
		if node: _select(node)

func _select(node: Node3D) -> void:
	selected = node
	_clear_inspector()
	var title := Label.new()
	title.text = str(node.name)
	inspector.add_child(title)
	_activity_fields(node)
	if node.has_method("interact"):
		_button(inspector,"Operate",node.interact)
	if node.has_method("set_angle_checked"):
		_button(inspector,"Swing leaf",func():
			var open_angle: float = Socket.open_angle(node)
			node.set_angle_checked(open_angle if is_zero_approx(node.current_angle) else 0.0))
	if node.has_method("set_wind"):
		_button(inspector,"Apply breeze",func(): node.set_wind(node.global_basis * Vector3(1,0,1)))
		_button(inspector,"Still air",func(): node.set_wind(Vector3.ZERO))
	# Pinned fittings keep their mount and dimensions until removed. Moving a
	# free assembly root carries its subtree. Replacing its geometry needs a refit.
	if node.get_parent() != candidates:
		var hint := Label.new()
		hint.text = "Mounted on: " + str(node.get_parent().name)
		inspector.add_child(hint)
		_refresh_outline()
		return
	_vector_field("Position", "position", node.position)
	_vector_field("Rotation", "rotation_degrees", node.rotation_degrees)
	if not Assembly.members(node).is_empty():
		_refresh_outline()
		return
	for property in node.get_property_list():
		if property.usage & PROPERTY_USAGE_SCRIPT_VARIABLE == 0 or property.usage & PROPERTY_USAGE_EDITOR == 0:
			continue
		var key: String = property.name
		if key in ["recipe_module","recipe_function","recipe_parameters"]: continue
		var value = node.get(key)
		if value is Vector3:
			_vector_field(key, key, value)
		elif value is float or value is int or value is bool or property.hint == PROPERTY_HINT_ENUM:
			_property_field(key, value, property)
		elif value is Array or value is Dictionary or value is String:
			var label := Label.new()
			label.text = key + ("（JSON）" if not value is String else "")
			inspector.add_child(label)
			var field := LineEdit.new()
			field.text = value if value is String else JSON.stringify(value)
			inspector.add_child(field)
			field.text_submitted.connect(func(text: String):
				var parsed = text if value is String else JSON.parse_string(text)
				if parsed != null: _change(key, parsed))
	_refresh_outline()

func _socket(node: Node3D) -> Node:
	var socket := node.get_node_or_null("MechanismSocket")
	if not socket:
		socket = Socket.new(); socket.name = "MechanismSocket"
		node.add_child(socket); socket.owner = candidates
	return socket

func _activity_fields(node: Node3D) -> void:
	var socket := node.get_node_or_null("MechanismSocket")
	var activity: String = socket.activity if socket else ""
	var picker := OptionButton.new(); inspector.add_child(picker)
	for key in activity_choices:
		picker.add_item(activity_choices[key]); picker.set_item_metadata(picker.item_count-1,key)
		if key == activity: picker.select(picker.item_count-1)
	picker.item_selected.connect(func(i:int):
		_socket(node).configure(picker.get_item_metadata(i)); _remember(); _select(node))
	if not activity.is_empty():
		_button(inspector,"Open activity",func():
			if socket.activate(activity_layer):
				activity_layer.show(); socket.dismissed.connect(activity_layer.hide,CONNECT_ONE_SHOT))
	var button := node.has_method("pulse") and Assembly.id(node) == "PhysicalButton"
	if button: _button(inspector,"Press button",func(): _socket(node).press())
	if button or not activity.is_empty() or node.has_signal("running_changed") or node.has_signal("open_changed"):
		var outputs := OptionButton.new(); inspector.add_child(outputs)
		outputs.add_item("Output: unconnected"); outputs.set_item_metadata(0,null)
		for other in Assembly.members(candidates):
			if other == node: continue
			if not (other.has_method("set_open") or other.has_method("set_angle_checked") or (("is_running" in other or "running" in other) and other.has_method("interact"))): continue
			outputs.add_item("Output: " + str(candidates.get_path_to(other))); outputs.set_item_metadata(outputs.item_count-1,other)
			if socket and not socket.target.is_empty() and socket.get_node_or_null(socket.target) == other: outputs.select(outputs.item_count-1)
		outputs.item_selected.connect(func(i:int):
			var output: Node = outputs.get_item_metadata(i); var port := _socket(node)
			port.target = port.get_path_to(output) if output else NodePath(); _remember())

func _clear_inspector() -> void:
	for child in inspector.get_children():
		inspector.remove_child(child)
		child.queue_free()

func _vector_field(label: String, key: String, value: Vector3) -> void:
	var title := Label.new()
	title.text = label
	inspector.add_child(title)
	for axis in range(3):
		var row := HBoxContainer.new()
		inspector.add_child(row)
		var heading := Label.new()
		heading.text = ["X", "Y", "Z"][axis]
		row.add_child(heading)
		var spin := SpinBox.new()
		spin.min_value = -1000
		spin.max_value = 1000
		spin.step = 0.05
		spin.value = value[axis]
		row.add_child(spin)
		spin.value_changed.connect(func(amount: float):
			if is_instance_valid(selected):
				var vector: Vector3 = selected.get(key)
				vector[axis] = amount
				selected.set(key, vector)
				_remember())

func _property_field(key: String, value: Variant, property: Dictionary) -> void:
	var label := Label.new()
	label.text = key
	inspector.add_child(label)
	if value is bool:
		var toggle := CheckBox.new()
		toggle.button_pressed = value
		inspector.add_child(toggle)
		toggle.toggled.connect(func(enabled: bool): _change(key, enabled))
	elif property.hint == PROPERTY_HINT_ENUM:
		var options := OptionButton.new()
		var values: PackedStringArray = str(property.hint_string).split(",")
		for option in values:
			options.add_item(option)
		options.select(values.find(str(value)) if value is String else int(value))
		inspector.add_child(options)
		options.item_selected.connect(func(index: int): _change(key, values[index] if value is String else index))
	else:
		var spin := SpinBox.new()
		spin.min_value = -1000
		spin.max_value = 1000
		spin.step = 1 if value is int else 0.05
		if property.hint == PROPERTY_HINT_RANGE:
			var limits := str(property.hint_string).split(",")
			spin.min_value = float(limits[0])
			spin.max_value = float(limits[1])
			if limits.size() > 2:
				spin.step = float(limits[2])
		spin.value = float(value)
		inspector.add_child(spin)
		spin.value_changed.connect(func(amount: float): _change(key, int(amount) if value is int else amount))

func _change(key: String, value: Variant) -> void:
	if is_instance_valid(selected):
		selected.set(key, value)
		_remember()

func _refresh_outline() -> void:
	outline.clear()
	for child in Assembly.members(candidates):
		var depth := candidates.get_path_to(child).get_name_count()-1
		outline.add_item("    ".repeat(depth) + str(child.name))
		outline.set_item_metadata(outline.item_count-1,child)
		if child == selected: outline.select(outline.item_count-1)

func _snapshot() -> PackedScene:
	var packed := PackedScene.new()
	if packed.pack(candidates) != OK:
		push_error("Could not save the building candidate.")
		return null
	return packed

func _remember() -> void:
	var packed := _snapshot()
	if packed == null:
		return
	history.resize(history_index + 1)
	history.append(packed)
	if history.size() > 100:
		history.pop_front()
	history_index = history.size() - 1
	_refresh_outline()

func _replace(packed: PackedScene) -> void:
	selected = null
	_clear_inspector()
	remove_child(candidates)
	candidates.queue_free()
	candidates = packed.instantiate() as Node3D
	add_child(candidates)
	# Candidates saved before mount metadata existed are flat catalog instances.
	for child in candidates.get_children():
		if child.get_script() and Assembly.id(child).is_empty():
			for entry in catalog.items:
				if child.get_script().resource_path in [entry.path, entry.get("legacy_path", "")]:
					Assembly.tag(child,entry)
					break
	_refresh_outline()

func _restore(index: int) -> void:
	if index >= 0 and index < history.size():
		history_index = index
		_replace(history[index])

func _delete_selected() -> void:
	if is_instance_valid(selected):
		var parent := selected.get_parent()
		# Remove incoming links before recycling a component name.
		for peer in Assembly.members(candidates):
			var port := peer.get_node_or_null("MechanismSocket")
			if port and not port.target.is_empty():
				var sink: Node = port.get_node_or_null(port.target)
				if sink and (sink == selected or selected.is_ancestor_of(sink)): port.target = NodePath()
		parent.remove_child(selected)
		if parent is SmartWall3D: parent.rebuild()
		selected.queue_free()
		selected = null
		_clear_inspector()
		_remember()

func _save_candidate() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(CANDIDATE_PATH.get_base_dir()))
	var packed := _snapshot()
	if packed != null and ResourceSaver.save(packed, CANDIDATE_PATH) == OK:
		status.text = "Saved candidate: " + CANDIDATE_PATH
	else:
		status.text = "Could not save candidate."

func _open_candidate() -> void:
	if not FileAccess.file_exists(CANDIDATE_PATH):
		status.text = "No saved candidate."
		return
	var packed := ResourceLoader.load(CANDIDATE_PATH, "PackedScene", ResourceLoader.CACHE_MODE_IGNORE) as PackedScene
	if packed != null:
		_replace(packed)
		_remember()
		status.text = "Opened candidate: " + CANDIDATE_PATH

func _show_catalog() -> void:
	_cancel()
	var index := 0
	for entry in catalog.items:
		status.text = "Generating component overview: %d / %d" % [index + 1, catalog.items.size()]
		var instance := _make_part(entry)
		if instance == null: continue
		candidates.add_child(instance, true)
		instance.owner = candidates
		instance.position = Vector3((index % 12) * 7.0, 0, (index / 12) * 7.0)
		print("[Catalog] ", entry.id, " -> ", entry.path)
		index += 1
		await get_tree().process_frame
	target = Vector3(38.5, 0, 35)
	distance = 100
	_update_camera()
	_remember()
	status.text = "Generated %d components. Right-drag to orbit, Shift+right-drag to pan. Save the candidate to keep this layout." % index

func _capture() -> void:
	await RenderingServer.frame_post_draw
	var path := "res://.runtime/building_catalog/BuildingSimulator.png"
	var saved := preload("res://mcp/CaptureReceipt.gd").save(get_viewport().get_texture().get_image(), path, get_tree(), "manual-component-capture")
	status.text = "Saved screenshot: " + path if saved else "Could not save screenshot."
