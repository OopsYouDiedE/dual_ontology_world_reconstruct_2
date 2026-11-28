@tool
extends EditorPlugin
## Godot editor front-end for level structures. Levels are ordinary scenes built from @tool
## nodes (LevelStructure3D + SmartWall3D / SmartFloorZone3D / LevelAnchor3D / LevelStation3D /
## catalog components); this dock adds them with undo, files them under the right group,
## and rebuilds. Everything else is plain Godot: move with gizmos, tune in the Inspector, save.
##
## Verification hook (real editor window, see tools/test/README or tools-guide):
##   Godot --editor --path . -- --archbuilder-editor-capture=<scene.tscn>,<out.jpg>[,<node path to select>]

const Components := preload("res://tools/building_construction/BuildingConstruction/Shared/ComponentFactory.gd")
const Structure := preload("res://scenes/components/structure/LevelStructure3D.gd")
const Anchor := preload("res://scenes/components/structure/LevelAnchor3D.gd")
const Station := preload("res://scenes/components/structure/LevelStation3D.gd")
const Wall := preload("res://tools/building_construction/BuildingConstruction/Walls/SmartWall3D.gd")
const FloorZone := preload("res://tools/building_construction/BuildingConstruction/Floors/SmartFloorZone3D.gd")
const ToolTheme := preload("res://tools/building_construction/ToolTheme.gd")

var dock: Control
var category: OptionButton
var items: ItemList
var search: LineEdit
var info: Label
var catalog: Dictionary
var entries: Array = []

func _enter_tree() -> void:
	catalog = Components.load_catalog()
	dock = _build_dock()
	add_control_to_dock(DOCK_SLOT_LEFT_BR, dock)
	get_editor_interface().get_selection().selection_changed.connect(_update_info)
	_refresh()
	_update_info()
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--archbuilder-editor-capture="):
			_capture.call_deferred(arg.get_slice("=", 1))

func _exit_tree() -> void:
	if dock:
		remove_control_from_docks(dock)
		dock.queue_free()

# ── dock ──────────────────────────────────────────────────────────────────────

func _build_dock() -> Control:
	var root := VBoxContainer.new()
	root.name = "关卡结构"
	root.add_theme_constant_override("separation", 6)
	info = Label.new()
	info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	info.theme_type_variation = "HintLabel"
	root.add_child(info)
	_section(root, "结构")
	var grid := GridContainer.new()
	grid.columns = 2
	root.add_child(grid)
	for spec in [["墙", _add_wall], ["地面", _add_floor], ["锚点", _add_anchor], ["站位", _add_station]]:
		var b := Button.new()
		b.text = "+ " + spec[0]
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.pressed.connect(spec[1])
		grid.add_child(b)
	var rebuild := Button.new()
	rebuild.text = "重建结构"
	rebuild.pressed.connect(func():
		var s := _structure()
		if s: s.rebuild_all(); _update_info())
	root.add_child(rebuild)
	var new_root := Button.new()
	new_root.text = "在当前场景新建 LevelStructure3D"
	new_root.pressed.connect(_add_structure_root)
	root.add_child(new_root)
	_section(root, "目录构件")
	search = LineEdit.new()
	search.placeholder_text = "搜索构件…"
	search.clear_button_enabled = true
	search.text_changed.connect(func(_t): _refresh())
	root.add_child(search)
	category = OptionButton.new()
	for key in catalog.get("categories", {}):
		category.add_item(str(catalog.categories[key]))
		category.set_item_metadata(category.item_count - 1, key)
	category.item_selected.connect(func(_i): _refresh())
	root.add_child(category)
	items = ItemList.new()
	items.custom_minimum_size = Vector2(220, 220)
	items.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_child(items)
	var add := Button.new()
	add.text = "添加到结构（Components）"
	add.theme_type_variation = "PrimaryButton"
	add.pressed.connect(_add_component)
	root.add_child(add)
	return root

func _section(parent: Control, text: String) -> void:
	var l := Label.new()
	l.text = text
	l.add_theme_color_override("font_color", ToolTheme.MUTED)
	parent.add_child(l)

func _refresh() -> void:
	if items == null:
		return
	items.clear()
	entries.clear()
	var query := search.text.strip_edges().to_lower()
	var key = category.get_item_metadata(category.selected) if category.item_count > 0 else null
	for entry in catalog.get("items", []):
		var hit: bool = (query in str(entry.label).to_lower() or query in str(entry.id).to_lower()) if query != "" else entry.category == key
		if hit:
			entries.append(entry)
			var row := items.add_item(str(entry.label))
			items.set_item_tooltip(row, Components.production_note(entry))

func _update_info() -> void:
	var s := _structure()
	if info == null:
		return
	if s == null:
		info.text = "打开一个含 LevelStructure3D 的关卡场景，或点下方按钮新建。"
	else:
		s.refresh_summary()
		info.text = "%s\n%s" % [s.name, s.summary]

# ── structure helpers ─────────────────────────────────────────────────────────

func _scene_root() -> Node:
	return get_editor_interface().get_edited_scene_root()

func _structure() -> Node:
	var root := _scene_root()
	if root == null:
		return null
	for node in get_editor_interface().get_selection().get_selected_nodes():
		var n: Node = node
		while n != null:
			if n is LevelStructure3D:
				return n
			n = n.get_parent()
	if root is LevelStructure3D:
		return root
	var found := root.find_children("*", "LevelStructure3D", true, true)
	return found[0] if not found.is_empty() else null

func _group(structure: Node, title: String) -> Node:
	var g := structure.get_node_or_null(title)
	if g == null:
		g = Node3D.new()
		g.name = title
		structure.add_child(g)
		g.owner = _scene_root()
	return g

func _add(kind: String, node: Node3D, title: String) -> void:
	var s := _structure()
	if s == null:
		push_warning("先打开或新建一个 LevelStructure3D 场景。")
		return
	var parent := _group(s, kind)
	node.name = title
	var undo := get_undo_redo()
	undo.create_action("添加%s" % title)
	undo.add_do_method(parent, "add_child", node, true)
	undo.add_do_method(node, "set_owner", _scene_root())
	undo.add_do_reference(node)
	undo.add_undo_method(parent, "remove_child", node)
	undo.commit_action()
	get_editor_interface().get_selection().clear()
	get_editor_interface().get_selection().add_node(node)
	_update_info()

func _add_wall() -> void:
	var wall: Node3D = Wall.new()
	wall.start_point = Vector3.ZERO
	wall.end_point = Vector3(4, 0, 0)
	wall.wall_height = 2.75
	wall.wall_thickness = 0.13
	wall.skirting_enabled = false
	_add("Walls", wall, "Wall")

func _add_floor() -> void:
	var zone: Node3D = FloorZone.new()
	zone.polygon = PackedVector2Array([Vector2(0, 0), Vector2(4, 0), Vector2(4, 4), Vector2(0, 4)])
	zone.floor_thickness = 0.15
	_add("Floors", zone, "Floor")

func _add_anchor() -> void:
	var a: Node3D = Anchor.new()
	a.anchor_id = "anchor"
	_add("Anchors", a, "Anchor")

func _add_station() -> void:
	_add("Stations", Station.new(), "Station")

func _add_component() -> void:
	var selected := items.get_selected_items()
	if selected.is_empty():
		push_warning("先在列表里选一个构件。")
		return
	var entry: Dictionary = entries[selected[0]]
	var instance := Components.create_entry(entry)
	if instance == null:
		push_error("无法加载构件：" + str(entry.path))
		return
	_add("Components", instance, str(entry.id))

func _add_structure_root() -> void:
	var root := _scene_root()
	if root == null:
		push_warning("先新建或打开一个 3D 场景。")
		return
	var s: Node3D = Structure.new()
	s.name = "LevelStructure"
	var undo := get_undo_redo()
	undo.create_action("新建关卡结构")
	undo.add_do_method(root, "add_child", s, true)
	undo.add_do_method(s, "set_owner", root)
	undo.add_do_reference(s)
	undo.add_undo_method(root, "remove_child", s)
	undo.commit_action()
	for title in ["Floors", "Walls", "Anchors", "Stations", "Components"]:
		_group(s, title)
	get_editor_interface().get_selection().clear()
	get_editor_interface().get_selection().add_node(s)

# ── real-window verification ──────────────────────────────────────────────────

func _capture(spec: String) -> void:
	var scene := spec.get_slice(",", 0)
	var out := spec.get_slice(",", 1)
	var select_path := spec.get_slice(",", 2) if spec.get_slice_count(",") > 2 else ""
	var ei := get_editor_interface()
	while ei.get_resource_filesystem().is_scanning():
		await get_tree().process_frame
	# Let the editor finish restoring last session's scene tabs first.
	var settle := 0
	while settle < 600 and (ei.get_open_scenes().is_empty() or ei.get_open_scenes() == PackedStringArray([""])):
		settle += 1
		await get_tree().process_frame
	for i in 60:
		await get_tree().process_frame
	# A scene restored from the last session keeps its old camera: close it first, then
	# write the framing state, then open it fresh.
	if scene in ei.get_open_scenes():
		ei.open_scene_from_path(scene)
		for i in 20:
			await get_tree().process_frame
		ei.close_scene()
		for i in 20:
			await get_tree().process_frame
	_frame_editor_camera(scene)
	for attempt in 5:
		ei.open_scene_from_path(scene)
		for i in 40:
			await get_tree().process_frame
		var current := ei.get_edited_scene_root()
		if current and current.scene_file_path == scene:
			break
	var root := ei.get_edited_scene_root()
	var target: Node = root
	if root:
		var walls := root.find_children("*", "", true, true).filter(func(n): return LevelStructure3D.is_wall(n))
		if select_path != "" and root.has_node(select_path):
			target = root.get_node(select_path)
		elif not walls.is_empty():
			target = walls[0]
	ei.get_selection().clear()
	if target:
		ei.get_selection().add_node(target)
		ei.edit_node(target)
	ei.set_main_screen_editor("3D")
	_update_info()
	ei.get_selection().clear()
	if target:
		ei.get_selection().add_node(target)
		ei.edit_node(target)
	# The editor 3D view only re-renders on interaction; force fresh frames for the capture.
	var vp3 := ei.get_editor_viewport_3d(0)
	if vp3:
		vp3.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	var tabs := dock.get_parent() as TabContainer
	if tabs:
		tabs.current_tab = dock.get_index()
	for i in 60:
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var img := ei.get_base_control().get_viewport().get_texture().get_image()
	img.convert(Image.FORMAT_RGB8)
	var err := img.save_jpg(ProjectSettings.globalize_path(out), 0.86)
	print("ARCHBUILDER_EDITOR_CAPTURE %s %s selected=%s" % [out, error_string(err), target.name if target else "none"])
	get_tree().quit()

## The editor restores each scene's 3D camera from .godot/editor/<scene>-editstate-<md5>.cfg.
## Writing that state before opening frames the whole structure from above at 3/4 view.
func _frame_editor_camera(scene: String) -> void:
	var packed := load(scene) as PackedScene
	if packed == null:
		return
	var probe := packed.instantiate()
	var center := Vector3(16, 0, 16)
	var span := 16.0
	if probe is LevelStructure3D:
		var lot: Dictionary = probe.derive_lot()
		if not lot.floors.is_empty():
			var box := Rect2(Vector2(lot.floors[0]), Vector2.ONE)
			for c: Vector2i in lot.floors:
				box = box.merge(Rect2(Vector2(c), Vector2.ONE))
			center = Vector3(box.get_center().x, 0.0, box.get_center().y)
			span = maxf(box.size.x, box.size.y)
	probe.free()
	# Start from the state the editor itself saved (complete keys), override only the camera.
	var file := "res://.godot/editor/%s-editstate-%s.cfg" % [scene.get_file(), scene.md5_text()]
	var state := ConfigFile.new()
	state.load(file)
	var three: Dictionary = state.get_value("editor_states", "3D", {})
	var views: Array = three.get("viewports", [{}])
	if views.is_empty():
		views.append({})
	var view: Dictionary = views[0]
	view["position"] = center
	view["distance"] = span * 1.6
	view["x_rotation"] = 0.95
	view["y_rotation"] = 0.0
	view["orthogonal"] = false
	view["view_type"] = 0
	views[0] = view
	three["viewports"] = views
	three["viewport_mode"] = 1
	state.set_value("editor_states", "3D", three)
	state.save(file)
