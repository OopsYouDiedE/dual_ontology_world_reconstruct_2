extends Node3D

const CATALOG_PATH := "res://tools/building_construction/catalog.json"
const Assembly = preload("production/assembly/ComponentAssembly.gd")
const Socket = preload("BuildingConstruction/Shared/MechanismSocket.gd")
const Components = preload("BuildingConstruction/Shared/ComponentFactory.gd")
const Interactable = preload("res://scenes/components/interaction/AcademyInteractable.gd")
const ToolTheme = preload("ToolTheme.gd")
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
var search: LineEdit
var recent_bar: HFlowContainer
var recent: Array = []  # most recently placed catalog entries, newest first
const RECENT_MAX := 6

func _ready() -> void:
	catalog = Components.load_catalog(CATALOG_PATH)
	if catalog.is_empty():
		return
	activity_choices = Socket.choices()
	candidates = Node3D.new()
	candidates.name = "BuilderCandidates"
	add_child(candidates)
	var environment := WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = ToolTheme.BG
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
	surface.albedo_color = Color(0.2, 0.23, 0.28)
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

func _button(parent: Node, label: String, callback: Callable, variation := "") -> Button:
	var button := Button.new()
	button.text = label
	button.theme_type_variation = variation
	button.pressed.connect(callback)
	parent.add_child(button)
	return button

func _label(parent: Node, text: String, variation := "") -> Label:
	var label := Label.new()
	label.text = text
	label.theme_type_variation = variation
	parent.add_child(label)
	return label

## Small muted heading that groups the controls below it.
func _section(parent: Node, text: String) -> Label:
	var label := _label(parent, text, "SectionLabel")
	label.custom_minimum_size.y = 24
	label.uppercase = true
	label.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
	return label

## Label on the left, control on the right: the inspector reads as a property sheet.
func _row(parent: Node, text: String, control: Control) -> HBoxContainer:
	var row := HBoxContainer.new()
	parent.add_child(row)
	var label := _label(row, text, "FieldLabel")
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.clip_text = true
	control.custom_minimum_size.x = 150
	row.add_child(control)
	return row

func _make_ui() -> void:
	# 现代简洁风：与 ArchBuilder 共用 ToolTheme；左右两块浮动面板贴满高度，中间留给 3D 视图。
	var layer := CanvasLayer.new()
	add_child(layer)
	var ui := Control.new()
	ui.name = "ToolUI"
	ui.theme = ToolTheme.get_theme()
	ui.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ui.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	layer.add_child(ui)
	var panel := PanelContainer.new()
	panel.theme_type_variation = "FloatingPanel"
	panel.set_anchors_and_offsets_preset(Control.PRESET_LEFT_WIDE)
	panel.offset_left = 12
	panel.offset_top = 12
	panel.offset_right = 312
	panel.offset_bottom = -12
	ui.add_child(panel)
	var column := VBoxContainer.new()
	panel.add_child(column)
	_label(column, "Component Library", "TitleLabel")
	# 最常用：搜索和“最近使用”，一步就能再放同一件物品。
	search = LineEdit.new()
	search.placeholder_text = "Search all components…"
	search.clear_button_enabled = true
	search.text_changed.connect(func(_text): _refresh(category.selected))
	column.add_child(search)
	_section(column, "RECENT")
	recent_bar = HFlowContainer.new()
	recent_bar.add_theme_constant_override("h_separation", 4)
	recent_bar.add_theme_constant_override("v_separation", 4)
	column.add_child(recent_bar)
	_refresh_recent()
	_section(column, "CATALOG")
	category = OptionButton.new()
	column.add_child(category)
	for key in catalog.categories:
		category.add_item(str(catalog.categories[key]))
		category.set_item_metadata(category.item_count - 1, key)
	items = ItemList.new()
	items.custom_minimum_size = Vector2(250, 90)
	items.size_flags_vertical = Control.SIZE_EXPAND_FILL
	items.size_flags_stretch_ratio = 1.6
	column.add_child(items)
	_section(column, "SCENE")
	var actions := HBoxContainer.new()
	column.add_child(actions)
	for spec in [["Esc", _cancel, "FlatButton"], ["Undo", func(): _restore(history_index - 1), "FlatButton"], ["Redo", func(): _restore(history_index + 1), "FlatButton"], ["Delete", _delete_selected, "DangerButton"]]:
		_button(actions, spec[0], spec[1], spec[2]).size_flags_horizontal = Control.SIZE_EXPAND_FILL
	outline = ItemList.new()
	outline.custom_minimum_size = Vector2(250, 64)
	outline.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.add_child(outline)
	outline.item_selected.connect(func(index: int): _select(outline.get_item_metadata(index)))
	_section(column, "FILE")
	var file_grid := GridContainer.new()
	file_grid.columns = 2
	column.add_child(file_grid)
	for spec in [["Save Candidate", _save_candidate, "PrimaryButton"], ["Open Candidate", _open_candidate, ""], ["Show All", _show_catalog, "FlatButton"], ["Screenshot", _capture, "FlatButton"]]:
		_button(file_grid, spec[0], spec[1], spec[2]).size_flags_horizontal = Control.SIZE_EXPAND_FILL
	status = _label(column, "", "HintLabel")
	status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	status.custom_minimum_size.x = 250
	status.text = "R turn · F swap end · Right-drag orbit · Shift pan · Scroll zoom"
	var right := PanelContainer.new()
	right.theme_type_variation = "FloatingPanel"
	right.set_anchors_and_offsets_preset(Control.PRESET_RIGHT_WIDE)
	right.offset_left = -352
	right.offset_right = -12
	right.offset_top = 12
	right.offset_bottom = -12
	ui.add_child(right)
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	right.add_child(scroll)
	inspector = VBoxContainer.new()
	inspector.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(inspector)
	category.item_selected.connect(_refresh)
	items.item_selected.connect(_select_item)
	_refresh(0)

func _refresh(index: int) -> void:
	items.clear()
	entries.clear()
	selected_path = ""
	var key = category.get_item_metadata(index)
	var query := search.text.strip_edges().to_lower() if search else ""
	for entry in catalog.items:
		var hit: bool = (query in str(entry.label).to_lower() or query in str(entry.id).to_lower()) if query != "" else entry.category == key
		if hit:
			entries.append(entry)
			var row := items.add_item(str(entry.label))
			items.set_item_tooltip(row, _production_note(entry))

func _production_note(entry: Dictionary) -> String:
	return Components.production_note(entry)

func _select_item(index: int) -> void:
	_arm(entries[index])

func _arm(entry: Dictionary) -> void:
	selected_path = str(entry.path)
	selected_entry = entry
	var production := Components.production_note(selected_entry).get_slice("\n", 0)
	status.text = "%s · %s mount\n%s\nClick a support. R: turn. F: swap end." % [selected_entry.label, selected_entry.mount, production]

func _note_recent(entry: Dictionary) -> void:
	recent = recent.filter(func(e): return e.id != entry.id)
	recent.push_front(entry)
	recent.resize(mini(recent.size(), RECENT_MAX))
	_refresh_recent()

func _refresh_recent() -> void:
	for child in recent_bar.get_children():
		recent_bar.remove_child(child)
		child.queue_free()
	if recent.is_empty():
		_label(recent_bar, "Placed components appear here.", "HintLabel")
		return
	for entry in recent:
		var chip := _button(recent_bar, str(entry.label), func(): _arm(entry), "ChipButton")
		chip.tooltip_text = "Place another " + str(entry.label)

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
	_own_interaction(instance)
	_remember()
	_select(instance)
	_note_recent(selected_entry)
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
	_label(inspector, str(node.name), "TitleLabel")
	_inspector_body(node)
	_mechanism_fields(node)
	_refresh_outline()

## Frequently edited groups, top to bottom: transform, interaction, parameters.
func _inspector_body(node: Node3D) -> void:
	# Pinned fittings keep their mount and dimensions until removed. Moving a
	# free assembly root carries its subtree. Replacing its geometry needs a refit.
	if node.get_parent() != candidates:
		_label(inspector, "Mounted on: " + str(node.get_parent().name), "HintLabel")
		return
	_section(inspector, "TRANSFORM")
	_vector_field("Position", "position", node.position)
	_vector_field("Rotation", "rotation_degrees", node.rotation_degrees)
	_interaction_fields(node)
	if not Assembly.members(node).is_empty():
		return
	_section(inspector, "PARAMETERS")
	_script_fields(node)

## Rarely used: mechanism activity, outputs and quick test actions.
func _mechanism_fields(node: Node3D) -> void:
	_section(inspector, "MECHANISM")
	_activity_fields(node)
	if node.has_method("interact"):
		_button(inspector,"Operate",node.interact, "FlatButton")
	if node.has_method("set_angle_checked"):
		_button(inspector,"Swing leaf",func():
			var open_angle: float = Socket.open_angle(node)
			node.set_angle_checked(open_angle if is_zero_approx(node.current_angle) else 0.0))
	if node.has_method("set_wind"):
		_button(inspector,"Apply breeze",func(): node.set_wind(node.global_basis * Vector3(1,0,1)), "FlatButton")
		_button(inspector,"Still air",func(): node.set_wind(Vector3.ZERO), "FlatButton")

## Every exported script variable of `target` becomes an editable field.
func _script_fields(target: Object) -> void:
	for property in target.get_property_list():
		if property.usage & PROPERTY_USAGE_SCRIPT_VARIABLE == 0 or property.usage & PROPERTY_USAGE_EDITOR == 0:
			continue
		var key: String = property.name
		if key in ["recipe_module","recipe_function","recipe_parameters"]: continue
		var value = target.get(key)
		if value is Vector3:
			if target == selected:
				_vector_field(key, key, value)
			else:
				_line_field(target, key, value)
		elif value is float or value is int or value is bool or property.hint == PROPERTY_HINT_ENUM:
			_property_field(key, value, property, target)
		elif value is Array or value is Dictionary or value is String:
			_line_field(target, key, value)

func _line_field(target: Object, key: String, value: Variant) -> void:
	_label(inspector, key + ("（JSON）" if not value is String else ""), "FieldLabel")
	var field := LineEdit.new()
	field.text = value if value is String else (str(value) if value is Vector3 else JSON.stringify(value))
	inspector.add_child(field)
	var commit := func(text: String):
		var parsed = text if value is String else (str_to_var("Vector3" + text) if value is Vector3 else JSON.parse_string(text))
		if parsed != null: _change(key, parsed, target)
	field.text_submitted.connect(commit)

## Item interaction (scene-side selectable): edit its exported data, or make the item
## selectable. Only data is edited here; prompts are drawn by each level's runtime.
func _interaction_fields(node: Node3D) -> void:
	_section(inspector, "Interaction")
	var it := node.get_node_or_null("Interactable") as Interactable
	if it == null:
		_label(inspector, "Not selectable in levels yet.", "HintLabel")
		_button(inspector, "Make selectable", func():
			var spec := {"id": str(node.name), "title_en": str(node.name), "title_zh": str(node.name)}
			Interactable.attach_to(node, spec)
			_own_interaction(node)
			_remember()
			_select(node), "PrimaryButton")
		return
	_script_fields(it)
	_button(inspector, "Remove interaction", func():
		node.remove_child(it)
		it.queue_free()
		_remember()
		_select(node), "DangerButton")

func _own_interaction(node: Node) -> void:
	var it := node.get_node_or_null("Interactable")
	if it == null:
		return
	it.owner = candidates
	for child in it.get_children():
		child.owner = candidates

func _socket(node: Node3D) -> Node:
	var socket := node.get_node_or_null("MechanismSocket")
	if not socket:
		socket = Socket.new(); socket.name = "MechanismSocket"
		node.add_child(socket); socket.owner = candidates
	return socket

func _activity_fields(node: Node3D) -> void:
	var socket := node.get_node_or_null("MechanismSocket")
	var activity: String = socket.activity if socket else ""
	var picker := OptionButton.new(); _row(inspector, "Activity", picker)
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
	if button: _button(inspector,"Press button",func(): _socket(node).press(), "FlatButton")
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
	# One compact row per vector: three spin boxes prefixed X / Y / Z.
	_label(inspector, label, "FieldLabel")
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 4)
	inspector.add_child(row)
	for axis in range(3):
		var spin := SpinBox.new()
		spin.prefix = ["X", "Y", "Z"][axis]
		spin.min_value = -1000
		spin.max_value = 1000
		spin.step = 0.05
		spin.value = value[axis]
		spin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		spin.custom_minimum_size.x = 0
		spin.get_line_edit().add_theme_constant_override("minimum_character_width", 3)
		row.add_child(spin)
		spin.value_changed.connect(func(amount: float):
			if is_instance_valid(selected):
				var vector: Vector3 = selected.get(key)
				vector[axis] = amount
				selected.set(key, vector)
				_remember())

func _property_field(key: String, value: Variant, property: Dictionary, target: Object = null) -> void:
	if value is bool:
		var toggle := CheckButton.new()
		toggle.button_pressed = value
		toggle.alignment = HORIZONTAL_ALIGNMENT_RIGHT
		_row(inspector, key, toggle)
		toggle.toggled.connect(func(enabled: bool): _change(key, enabled, target))
	elif property.hint == PROPERTY_HINT_ENUM:
		var options := OptionButton.new()
		var values: PackedStringArray = str(property.hint_string).split(",")
		for option in values:
			options.add_item(option)
		options.select(values.find(str(value)) if value is String else int(value))
		_row(inspector, key, options)
		options.item_selected.connect(func(index: int): _change(key, values[index] if value is String else index, target))
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
		_row(inspector, key, spin)
		spin.value_changed.connect(func(amount: float): _change(key, int(amount) if value is int else amount, target))

func _change(key: String, value: Variant, target: Object = null) -> void:
	var dest: Object = target if target != null else selected
	if is_instance_valid(dest):
		dest.set(key, value)
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
