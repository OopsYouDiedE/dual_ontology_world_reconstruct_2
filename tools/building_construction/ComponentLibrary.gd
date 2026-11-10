extends Node3D

const CATALOG_PATH := "res://tools/building_construction/catalog.json"
const Components = preload("BuildingConstruction/Shared/ComponentFactory.gd")
const CANDIDATE_PATH := "res://tools/building_construction/candidates/BuildingCandidate.tscn"

var camera: Camera3D
var candidates: Node3D
var category: OptionButton
var items: ItemList
var status: Label
var entries: Array = []
var catalog: Dictionary
var selected_path := ""
var selected_defaults: Dictionary = {}
var selected: Node3D
var outline: ItemList
var inspector: VBoxContainer
var history: Array[PackedScene] = []
var history_index := -1
var rotation_y := 0.0
var orbit := Vector2(-0.7, 0.8)
var distance := 18.0
var target := Vector3.ZERO

func _ready() -> void:
	var file := FileAccess.open(CATALOG_PATH, FileAccess.READ)
	if file == null:
		push_error("无法打开建筑目录")
		return
	var parsed = JSON.parse_string(file.get_as_text())
	if not parsed is Dictionary:
		push_error("建筑目录格式错误")
		return
	catalog = parsed
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
	heading.text = "建筑模拟器"
	column.add_child(heading)
	category = OptionButton.new()
	column.add_child(category)
	for key in catalog.categories:
		category.add_item(str(catalog.categories[key]))
		category.set_item_metadata(category.item_count - 1, key)
	items = ItemList.new()
	items.custom_minimum_size = Vector2(250, 230)
	column.add_child(items)
	_button(column, "选择模式／取消放置（Esc）", _cancel)
	var actions := HBoxContainer.new()
	column.add_child(actions)
	_button(actions, "撤销", func(): _restore(history_index - 1))
	_button(actions, "重做", func(): _restore(history_index + 1))
	_button(actions, "删除", _delete_selected)
	outline = ItemList.new()
	outline.custom_minimum_size = Vector2(250, 150)
	column.add_child(outline)
	outline.item_selected.connect(func(index: int): _select(candidates.get_child(index)))
	_button(column, "保存候选", _save_candidate)
	_button(column, "打开候选", _open_candidate)
	_button(column, "组件总览", _show_catalog)
	_button(column, "保存实机截图", _capture)
	status = Label.new()
	status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	status.custom_minimum_size.x = 250
	status.text = "单位：米。选组件后点击网格放置；右键旋转，Shift＋右键平移，滚轮缩放，R 转向。"
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
			items.add_item(str(entry.label))

func _select_item(index: int) -> void:
	selected_path = str(entries[index].path)
	selected_defaults = entries[index].get("defaults", {})
	status.text = "点击地面放置：" + str(entries[index].label)

func _cancel() -> void:
	selected_path = ""
	items.deselect_all()
	status.text = "选择模式：点击对象或左侧对象列表。"

func _unhandled_input(event: InputEvent) -> void:
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
			KEY_R:
				rotation_y = fposmod(rotation_y + 90.0, 360.0)
				status.text = "放置朝向：%d°" % rotation_y

func _update_camera() -> void:
	camera.position = target + Vector3(sin(orbit.x) * cos(orbit.y), sin(orbit.y), cos(orbit.x) * cos(orbit.y)) * distance
	camera.look_at(target)

func _place(mouse: Vector2) -> void:
	if selected_path.is_empty():
		return
	var point = Plane(Vector3.UP, 0.0).intersects_ray(camera.project_ray_origin(mouse), camera.project_ray_normal(mouse))
	if point == null:
		return
	var instance := Components.create(selected_path)
	if instance == null:
		status.text = "无法加载组件：" + selected_path
		return
	for key in selected_defaults:
		instance.set(key, selected_defaults[key])
	candidates.add_child(instance, true)
	instance.owner = candidates
	instance.position = (point as Vector3).snapped(Vector3(0.25, 0.25, 0.25))
	instance.rotation_degrees.y = rotation_y
	_remember()
	_select(instance)
	status.text = "已放置 " + instance.name

func _pick(mouse: Vector2) -> void:
	var origin := camera.project_ray_origin(mouse)
	var query := PhysicsRayQueryParameters3D.create(origin, origin + camera.project_ray_normal(mouse) * 200)
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	if hit.is_empty():
		return
	var node := hit.collider as Node
	while node != null and node.get_parent() != candidates:
		node = node.get_parent()
	if node is Node3D:
		_select(node)

func _select(node: Node3D) -> void:
	selected = node
	_clear_inspector()
	var title := Label.new()
	title.text = str(node.name)
	inspector.add_child(title)
	_vector_field("位置", "position", node.position)
	_vector_field("角度", "rotation_degrees", node.rotation_degrees)
	for property in node.get_property_list():
		if property.usage & PROPERTY_USAGE_SCRIPT_VARIABLE == 0 or property.usage & PROPERTY_USAGE_EDITOR == 0:
			continue
		var key: String = property.name
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
	for child in candidates.get_children():
		outline.add_item(str(child.name))
		if child == selected:
			outline.select(outline.item_count - 1)

func _snapshot() -> PackedScene:
	var packed := PackedScene.new()
	if packed.pack(candidates) != OK:
		push_error("无法保存建筑候选")
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
	_refresh_outline()

func _restore(index: int) -> void:
	if index >= 0 and index < history.size():
		history_index = index
		_replace(history[index])

func _delete_selected() -> void:
	if is_instance_valid(selected):
		candidates.remove_child(selected)
		selected.queue_free()
		selected = null
		_clear_inspector()
		_remember()

func _save_candidate() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(CANDIDATE_PATH.get_base_dir()))
	var packed := _snapshot()
	if packed != null and ResourceSaver.save(packed, CANDIDATE_PATH) == OK:
		status.text = "已保存候选：" + CANDIDATE_PATH
	else:
		status.text = "候选保存失败"

func _open_candidate() -> void:
	if not FileAccess.file_exists(CANDIDATE_PATH):
		status.text = "尚无已保存候选"
		return
	var packed := ResourceLoader.load(CANDIDATE_PATH, "PackedScene", ResourceLoader.CACHE_MODE_IGNORE) as PackedScene
	if packed != null:
		_replace(packed)
		_remember()
		status.text = "已打开候选：" + CANDIDATE_PATH

func _show_catalog() -> void:
	_cancel()
	var index := 0
	for entry in catalog.items:
		status.text = "生成组件总览：%d / %d" % [index + 1, catalog.items.size()]
		var instance := Components.create(str(entry.path))
		if instance == null: continue
		for key in entry.get("defaults", {}): instance.set(key, entry.defaults[key])
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
	status.text = "已生成 %d 个组件。右键转动，Shift＋右键平移；保存候选可保留当前布置。" % index

func _capture() -> void:
	await RenderingServer.frame_post_draw
	var path := "res://docs/BuildingSimulator.png"
	var error := get_viewport().get_texture().get_image().save_png(path)
	status.text = "已保存实机截图：" + path if error == OK else "截图保存失败"
