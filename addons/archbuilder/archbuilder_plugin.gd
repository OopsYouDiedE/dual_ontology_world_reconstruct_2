@tool
extends EditorPlugin
## Godot editor front-end for level structures. Levels are ordinary scenes built from @tool
## nodes (LevelStructure3D + walls, floors, columns, arches, stairs, triggers, movers,
## anchors, stations, catalog components); everything is edited as plain Godot nodes:
##   - 3D viewport: click any piece (its generated meshes select it), drag its handles
##     (structure_gizmo.gd), move it with the gizmo (snap points pull it into place);
##   - Godot's 2D tab: the plan view (plan_view.gd) painted over the 2D viewport, with grid
##     snapping and drawing tools in the 2D toolbar (Godot's 2D editor itself draws only
##     2D nodes, so without this a 3D level shows nothing there);
##   - this dock: add pieces, group a selection into a StructureAssembly3D and expose its
##     member properties as the assembly's own parameters, save it as a reusable scene;
##   - the Inspector: every exported parameter, trigger actions, mover poses.
##
## Verification hook (real editor window, see docs/production/tools-guide.md):
##   Godot --editor --path . -- --archbuilder-editor-capture=<scene.tscn>,<out.jpg>[,<node path>[,<view>]]
##   view: 3d (default) | 2d (plan in the 2D tab) | pick (clicks the 3D viewport centre, reports the selection)

const Components := preload("res://tools/building_construction/BuildingConstruction/Shared/ComponentFactory.gd")
const Structure := preload("res://scenes/components/structure/LevelStructure3D.gd")
const ToolTheme := preload("res://tools/building_construction/ToolTheme.gd")
const Ops := preload("res://addons/archbuilder/structure_ops.gd")
const Adopt := preload("res://addons/archbuilder/structure_adopt.gd")
const PlanView := preload("res://addons/archbuilder/plan_view.gd")
const Gizmo := preload("res://addons/archbuilder/structure_gizmo.gd")
const Assembly := preload("res://scenes/components/structure/StructureAssembly3D.gd")

var dock: Control
var category: OptionButton
var items: ItemList
var search: LineEdit
var info: Label
var catalog: Dictionary
var entries: Array = []
var ops
var plan
var gizmo
var assembly_box: VBoxContainer
var bind_member: OptionButton
var bind_property: OptionButton
var bind_name: LineEdit
var bind_list: ItemList
var _adopt_queue: Array = []
var _info_pending := false
var _last_selected: Array = []

func _enter_tree() -> void:
	ops = Ops.new(self)
	catalog = Components.load_catalog()
	dock = _build_dock()
	add_control_to_dock(DOCK_SLOT_LEFT_BR, dock)
	gizmo = Gizmo.new(ops)
	add_node_3d_gizmo_plugin(gizmo)
	plan = PlanView.new()
	plan.setup(self, ops)
	add_child(plan)
	add_control_to_container(CONTAINER_CANVAS_EDITOR_MENU, plan.toolbar)
	set_force_draw_over_forwarding_enabled()
	main_screen_changed.connect(_on_main_screen_changed)
	EditorInterface.get_selection().selection_changed.connect(_on_selection_changed)
	get_tree().node_added.connect(_on_node_added)
	scene_changed.connect(func(_root): _sweep.call_deferred(); _schedule_info())
	_sweep.call_deferred()
	_refresh()
	_update_info()
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--archbuilder-editor-capture="):
			_capture.call_deferred(arg.get_slice("=", 1))

func _exit_tree() -> void:
	if get_tree().node_added.is_connected(_on_node_added):
		get_tree().node_added.disconnect(_on_node_added)
	if gizmo:
		remove_node_3d_gizmo_plugin(gizmo)
	if plan:
		remove_control_from_container(CONTAINER_CANVAS_EDITOR_MENU, plan.toolbar)
		plan.toolbar.queue_free()
		plan.queue_free()
	if dock:
		remove_control_from_docks(dock)
		dock.queue_free()

# ── plan in Godot's 2D tab ─────────────────────────────────────────────────────

## Nodes of a scene with a level structure are "ours" in the 2D tab: the plan takes the mouse.
func _handles(object: Object) -> bool:
	if not (object is Node) or plan == null:
		return false
	var root := EditorInterface.get_edited_scene_root()
	return root != null and (object == root or root.is_ancestor_of(object)) and plan.find_structure() != null

func _forward_canvas_force_draw_over_viewport(overlay: Control) -> void:
	plan.draw(overlay)

func _forward_canvas_gui_input(event: InputEvent) -> bool:
	return plan.input(event)

## Opening the 2D tab on a structure scene with nothing selected selects the structure,
## so the plan receives clicks right away.
func _on_main_screen_changed(screen: String) -> void:
	if screen != "2D" and Time.get_ticks_msec() < plan.hold_2d_until:
		(func(): EditorInterface.set_main_screen_editor("2D")).call_deferred()
		return
	plan.in_2d = screen == "2D"
	if screen != "2D":
		return
	plan.refresh()
	var s: Node = plan.find_structure()
	if s != null and EditorInterface.get_selection().get_selected_nodes().is_empty():
		plan.stay_in_2d()
		EditorInterface.get_selection().add_node(s)
		EditorInterface.edit_node(s)
	update_overlays()

# ── click selection of generated meshes ───────────────────────────────────────

func _on_node_added(node: Node) -> void:
	if Adopt.wants(node):
		if _adopt_queue.is_empty():
			_flush_adopt.call_deferred()
		_adopt_queue.append(node)

## Deferred: nodes the editor adds itself get their owner in the same step and are skipped.
func _flush_adopt() -> void:
	var root := EditorInterface.get_edited_scene_root()
	var queue := _adopt_queue
	_adopt_queue = []
	for node in queue:
		if is_instance_valid(node):
			Adopt.adopt(node, root)

func _sweep() -> void:
	Adopt.sweep(EditorInterface.get_edited_scene_root())

func _on_selection_changed() -> void:
	# Redraw the outline / handles of pieces that were or now are selected.
	var now: Array = EditorInterface.get_selection().get_selected_nodes()
	for n in _last_selected + now:
		if is_instance_valid(n) and n is Node3D:
			n.update_gizmos()
	_last_selected = now.duplicate()
	_schedule_info()

# ── dock ──────────────────────────────────────────────────────────────────────

func _build_dock() -> Control:
	var scroll := ScrollContainer.new()
	scroll.name = "关卡结构"
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	var root := VBoxContainer.new()
	root.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	root.add_theme_constant_override("separation", 6)
	scroll.add_child(root)
	info = Label.new()
	info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	info.theme_type_variation = "HintLabel"
	root.add_child(info)
	_section(root, "添加构件（也可在 2D 标签里直接画）")
	var grid := GridContainer.new()
	grid.columns = 3
	root.add_child(grid)
	for spec in [["墙", "wall"], ["地面", "floor"], ["柱", "column"], ["拱", "arch"], ["柱廊", "colonnade"], ["楼梯", "stair"],
			["触发器", "trigger"], ["移动体", "mover"], ["站位", "station"], ["锚点", "anchor"]]:
		var b := Button.new()
		b.text = "+ " + spec[0]
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.pressed.connect(_add_kind.bind(spec[1]))
		grid.add_child(b)
	var row := HBoxContainer.new()
	root.add_child(row)
	var rebuild := Button.new()
	rebuild.text = "重建结构"
	rebuild.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	rebuild.pressed.connect(func():
		var s := _structure()
		if s:
			s.rebuild_all()
			_update_info())
	row.add_child(rebuild)
	var new_root := Button.new()
	new_root.text = "新建结构根"
	new_root.tooltip_text = "在当前场景新建 LevelStructure3D"
	new_root.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	new_root.pressed.connect(_add_structure_root)
	row.add_child(new_root)
	_section(root, "组合结构")
	var group_row := HBoxContainer.new()
	root.add_child(group_row)
	var group_btn := Button.new()
	group_btn.text = "组合选中"
	group_btn.tooltip_text = "把选中的构件放进一个新的 StructureAssembly3D"
	group_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	group_btn.pressed.connect(_group_selection)
	group_row.add_child(group_btn)
	var save_btn := Button.new()
	save_btn.text = "存为组件场景"
	save_btn.tooltip_text = "把选中的结构组存成 scenes/components/assemblies/<名字>.tscn，并换成它的实例"
	save_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	save_btn.pressed.connect(_save_assembly)
	group_row.add_child(save_btn)
	assembly_box = VBoxContainer.new()
	root.add_child(assembly_box)
	var hint := Label.new()
	hint.text = "暴露参数：成员 + 属性 → 结构组检视器里的「参数/名字」；同名参数一起驱动"
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hint.theme_type_variation = "HintLabel"
	assembly_box.add_child(hint)
	bind_member = OptionButton.new()
	bind_member.item_selected.connect(func(_i): _fill_properties())
	assembly_box.add_child(bind_member)
	bind_property = OptionButton.new()
	assembly_box.add_child(bind_property)
	var bind_row := HBoxContainer.new()
	assembly_box.add_child(bind_row)
	bind_name = LineEdit.new()
	bind_name.placeholder_text = "参数名"
	bind_name.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bind_row.add_child(bind_name)
	var bind_btn := Button.new()
	bind_btn.text = "暴露"
	bind_btn.pressed.connect(_expose_param)
	bind_row.add_child(bind_btn)
	bind_list = ItemList.new()
	bind_list.custom_minimum_size = Vector2(0, 70)
	bind_list.item_activated.connect(_unexpose_param)
	bind_list.tooltip_text = "双击删除一个参数"
	assembly_box.add_child(bind_list)
	assembly_box.hide()
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
	items.custom_minimum_size = Vector2(220, 200)
	items.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_child(items)
	var add := Button.new()
	add.text = "添加到结构（Components）"
	add.theme_type_variation = "PrimaryButton"
	add.pressed.connect(_add_component)
	root.add_child(add)
	return scroll

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

## Selection changes are frequent: the dock text refreshes at most once per idle frame and
## shows the cached summary (walking the whole structure on every click made clicks lag).
func _schedule_info() -> void:
	if not _info_pending:
		_info_pending = true
		_update_info.call_deferred()

func _update_info() -> void:
	_info_pending = false
	if info == null:
		return
	var s := _structure()
	if s == null:
		info.text = "打开一个含 LevelStructure3D 的关卡场景，或点「新建结构根」。切到 2D 标签可在平面图上拖拽、吸附和绘制。"
	else:
		if s.summary == "":
			s.refresh_summary()
		info.text = "%s\n%s" % [s.name, s.summary]
	_update_assembly_panel()

# ── structure helpers ─────────────────────────────────────────────────────────

func _scene_root() -> Node:
	return EditorInterface.get_edited_scene_root()

func _structure() -> Node:
	var root := _scene_root()
	if root == null:
		return null
	for node in EditorInterface.get_selection().get_selected_nodes():
		var n: Node = node
		while n != null:
			if n is LevelStructure3D:
				return n
			n = n.get_parent()
	if root is LevelStructure3D:
		return root
	var found := root.find_children("*", "LevelStructure3D", true, true)
	return found[0] if not found.is_empty() else null

func _add_kind(kind: String) -> void:
	var s := _structure()
	if s == null:
		push_warning("先打开或新建一个 LevelStructure3D 场景。")
		return
	var c := _spawn_point(s)
	var made: Node3D
	match kind:
		"wall": made = ops.add_wall(s, c, c + Vector2(4, 0))
		"floor": made = ops.add_floor(s, Rect2(c - Vector2(2, 2), Vector2(4, 4)))
		"column": made = ops.add_column(s, c)
		"arch": made = ops.add_arch(s, c, c + Vector2(3, 0))
		"colonnade": made = ops.add_colonnade(s, c, c + Vector2(7.5, 0))
		"stair": made = ops.add_stair(s, c, c + Vector2(4, 0))
		"trigger": made = ops.add_trigger(s, Rect2(c - Vector2.ONE, Vector2(2, 2)))
		"mover": made = ops.add_mover(s, Rect2(c - Vector2(1, 0.2), Vector2(2, 0.4)))
		"station": made = ops.add_station(s, Rect2(c - Vector2(0.5, 0.5), Vector2.ONE))
		"anchor": made = ops.add_anchor(s, c)
	_select(made)

## New pieces appear next to the selected node, else in the middle of the lot.
func _spawn_point(s: Node3D) -> Vector2:
	for n in EditorInterface.get_selection().get_selected_nodes():
		if n is Node3D and n != s and s.is_ancestor_of(n):
			var o := Ops.relative(s, n).origin
			return Vector2(o.x, o.z).snappedf(0.25) + Vector2(1, 1)
	var lot: int = s.lot_size if "lot_size" in s else 16
	return Vector2(lot, lot) * 0.5

func _select(node: Node) -> void:
	if node == null:
		return
	EditorInterface.get_selection().clear()
	EditorInterface.get_selection().add_node(node)
	EditorInterface.edit_node(node)
	_schedule_info()

func _add_component() -> void:
	var selected := items.get_selected_items()
	if selected.is_empty():
		push_warning("先在列表里选一个构件。")
		return
	var s := _structure()
	if s == null:
		push_warning("先打开或新建一个 LevelStructure3D 场景。")
		return
	var entry: Dictionary = entries[selected[0]]
	var instance := Components.create_entry(entry)
	if instance == null:
		push_error("无法加载构件：" + str(entry.path))
		return
	_select(ops.add(s, "component", instance, str(entry.id), Ops.at_plan(_spawn_point(s))))

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
	for title in ["Floors", "Walls", "Structure", "Anchors", "Stations", "Triggers", "Components"]:
		ops.group(s, title)
	_select(s)

# ── assemblies ────────────────────────────────────────────────────────────────

func _selected_assembly() -> Node:
	for n in EditorInterface.get_selection().get_selected_nodes():
		if n is Assembly:
			return n
	return null

func _group_selection() -> void:
	var s := _structure()
	if s == null:
		push_warning("先打开或新建一个 LevelStructure3D 场景。")
		return
	var nodes: Array = EditorInterface.get_selection().get_selected_nodes().filter(func(n): return n is Node3D and n != s and s.is_ancestor_of(n))
	if nodes.is_empty():
		push_warning("先在结构里选中要组合的构件（可多选）。")
		return
	_select(ops.group_into_assembly(s, nodes))

func _save_assembly() -> void:
	var a := _selected_assembly()
	if a == null:
		push_warning("先选中一个结构组（StructureAssembly3D）。")
		return
	var path := save_assembly_scene(a, "res://scenes/components/assemblies")
	if path == "":
		return
	EditorInterface.get_resource_filesystem().scan()
	# Replace the assembly by an instance of the saved scene (undoable).
	var instance: Node3D = (load(path) as PackedScene).instantiate(PackedScene.GEN_EDIT_STATE_INSTANCE)
	instance.name = a.name
	instance.transform = a.transform
	var parent := a.get_parent()
	var index := a.get_index()
	var owned: Array = [a] + a.find_children("*", "", true, false).filter(func(n): return n.owner == _scene_root())
	var undo := get_undo_redo()
	undo.create_action("存为组件场景 %s" % path.get_file())
	undo.add_do_method(parent, "remove_child", a)
	undo.add_do_method(parent, "add_child", instance, true)
	undo.add_do_method(parent, "move_child", instance, index)
	undo.add_do_method(instance, "set_owner", _scene_root())
	undo.add_do_reference(instance)
	undo.add_undo_method(parent, "remove_child", instance)
	undo.add_undo_method(parent, "add_child", a, true)
	undo.add_undo_method(parent, "move_child", a, index)
	for n in owned:
		undo.add_undo_method(n, "set_owner", _scene_root())
	undo.add_undo_reference(a)
	undo.commit_action()
	_select(instance)
	print("ARCHBUILDER_ASSEMBLY_SAVED ", path)

## Save an assembly (its authored members only) as <dir>/<name>.tscn. Returns the path.
static func save_assembly_scene(a: Node3D, dir: String) -> String:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(dir))
	var path := "%s/%s.tscn" % [dir, str(a.name).to_snake_case()]
	var packed: PackedScene = a.to_packed_scene()
	if packed == null or ResourceSaver.save(packed, path) != OK:
		push_error("保存结构组失败：" + path)
		return ""
	return path

func _update_assembly_panel() -> void:
	var a := _selected_assembly()
	if assembly_box == null:
		return
	assembly_box.visible = a != null
	if a == null:
		return
	bind_member.clear()
	for n in a.find_children("*", "Node3D", true, false):
		if n.owner != null and not n.has_meta(&"_structure_generated"):
			bind_member.add_item(str(a.get_path_to(n)))
	_fill_properties()
	bind_list.clear()
	for param in a.bindings:
		bind_list.add_item("%s → %s" % [param, ", ".join(a.bindings[param])])
		bind_list.set_item_metadata(bind_list.item_count - 1, param)

func _fill_properties() -> void:
	bind_property.clear()
	var a := _selected_assembly()
	if a == null or bind_member.item_count == 0:
		return
	var n := a.get_node_or_null(bind_member.get_item_text(bind_member.selected))
	if n == null:
		return
	for prop in n.get_property_list():
		if prop.usage & PROPERTY_USAGE_SCRIPT_VARIABLE and prop.usage & PROPERTY_USAGE_EDITOR:
			bind_property.add_item(prop.name)
	for extra in ["position", "rotation_degrees", "scale", "visible"]:
		bind_property.add_item(extra)

func _expose_param() -> void:
	var a := _selected_assembly()
	if a == null or bind_member.item_count == 0 or bind_property.item_count == 0:
		return
	var member := bind_member.get_item_text(bind_member.selected)
	var prop := bind_property.get_item_text(bind_property.selected)
	var param := bind_name.text.strip_edges()
	if param == "":
		param = prop
	var before := [Ops.snapshot(a)]
	a.expose(param, member, prop)
	ops.commit("暴露参数 %s" % param, [a], before)
	_update_assembly_panel()

func _unexpose_param(index: int) -> void:
	var a := _selected_assembly()
	if a == null:
		return
	var before := [Ops.snapshot(a)]
	a.unexpose(str(bind_list.get_item_metadata(index)))
	ops.commit("删除参数", [a], before)
	_update_assembly_panel()

# ── real-window verification ──────────────────────────────────────────────────

func _capture(spec: String) -> void:
	var parts := spec.split(",")
	var scene := parts[0]
	var out := parts[1]
	var select_path := parts[2] if parts.size() > 2 else ""
	var view := parts[3] if parts.size() > 3 else "3d"
	var ei := EditorInterface
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
	var t0 := Time.get_ticks_msec()
	for attempt in 5:
		ei.open_scene_from_path(scene)
		for i in 40:
			await get_tree().process_frame
		var current := ei.get_edited_scene_root()
		if current and current.scene_file_path == scene:
			break
	print("ARCHBUILDER_OPEN_MS %d" % (Time.get_ticks_msec() - t0))
	var root := ei.get_edited_scene_root()
	var target: Node = root
	if root:
		var walls := root.find_children("*", "", true, true).filter(func(n): return LevelStructure3D.is_wall(n))
		if select_path != "" and root.has_node(select_path):
			target = root.get_node(select_path)
		elif not walls.is_empty():
			target = walls[0]
	ei.set_main_screen_editor("3D")
	_select(target)
	var vp3 := ei.get_editor_viewport_3d(0)
	if vp3:
		vp3.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	# Bring the "关卡结构" dock tab to the front (the dock may sit inside a wrapper).
	var page: Node = dock
	while page != null and page.get_parent() != null and not (page.get_parent() is TabContainer):
		page = page.get_parent()
	if page != null and page.get_parent() is TabContainer:
		(page.get_parent() as TabContainer).current_tab = page.get_index()
	for i in 60:
		await get_tree().process_frame
	var report := "selected=%s" % (target.name if target else "none")
	if view == "2d":
		ei.set_main_screen_editor("2D")
		for i in 30:
			await get_tree().process_frame
		plan.refresh()
		update_overlays()
		for i in 20:
			await get_tree().process_frame
		report += " plan_items=%d handles_target=%s" % [plan.items.size(), str(_handles(target))]
		report += " " + await _pick_2d_test("PierW1")
	elif view == "pick":
		report += " " + await _pick_test(vp3)
	# Swap tab timing: switch away and back (was ~0.9 s per switch before the queue fix).
	var swap := Time.get_ticks_msec()
	if view != "2d":
		ei.set_main_screen_editor("Script")
		await get_tree().process_frame
		ei.set_main_screen_editor("3D")
		await get_tree().process_frame
	report += " swap_ms=%d" % (Time.get_ticks_msec() - swap)
	for i in 10:
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var img := ei.get_base_control().get_viewport().get_texture().get_image()
	img.convert(Image.FORMAT_RGB8)
	var err := img.save_jpg(ProjectSettings.globalize_path(out), 0.86)
	print("ARCHBUILDER_EDITOR_CAPTURE %s %s %s" % [out, error_string(err), report])
	get_tree().quit()

## Click a piece's plan outline in the 2D tab like a user and report the selection.
func _pick_2d_test(piece_name: String) -> String:
	var target: Dictionary = {}
	for it in plan.items:
		if it.node.name == piece_name:
			target = it
	var vp2 := EditorInterface.get_editor_viewport_2d()
	if target.is_empty() or vp2 == null:
		return "pick2d=no-target"
	plan._sync_view()
	var centre := Vector2.ZERO
	for p in target.outline:
		centre += p
	centre /= float(target.outline.size())
	var container := vp2.get_parent() as Control
	var at: Vector2 = container.get_global_rect().position + plan.to_screen(centre)
	for pressed in [true, false]:
		var ev := InputEventMouseButton.new()
		ev.button_index = MOUSE_BUTTON_LEFT
		ev.pressed = pressed
		ev.position = at
		ev.global_position = at
		Input.parse_input_event(ev)
		for i in 4:
			await get_tree().process_frame
	update_overlays()
	for i in 12:
		await get_tree().process_frame
	var screen := "2D" if plan.in_2d else "other"
	var picked: Array = EditorInterface.get_selection().get_selected_nodes().map(func(n): return str(n.name))
	return "pick2d=%s still_in=%s" % [",".join(picked), screen]

## Click the middle of the 3D viewport like a user and report what the editor selected.
func _pick_test(vp3: SubViewport) -> String:
	var container := vp3.get_parent() as Control if vp3 else null
	if container == null:
		return "pick=no-viewport"
	EditorInterface.get_selection().clear()
	await get_tree().process_frame
	var adopted := Adopt.sweep(EditorInterface.get_edited_scene_root())
	var centre := container.get_global_rect().get_center()
	for pressed in [true, false]:
		var ev := InputEventMouseButton.new()
		ev.button_index = MOUSE_BUTTON_LEFT
		ev.pressed = pressed
		ev.position = centre
		ev.global_position = centre
		Input.parse_input_event(ev)
		for i in 4:
			await get_tree().process_frame
	for i in 10:
		await get_tree().process_frame
	var picked: Array = EditorInterface.get_selection().get_selected_nodes().map(func(n): return "%s(%s)" % [n.name, n.get_script().resource_path.get_file() if n.get_script() else n.get_class()])
	return "late_adopted=%d pick=%s" % [adopted, ",".join(picked) if not picked.is_empty() else "none"]

## The editor restores each scene's 3D camera from .godot/editor/<scene>-editstate-<md5>.cfg.
## Writing that state before opening frames the whole structure from above at 3/4 view.
func _frame_editor_camera(scene: String) -> void:
	var packed := load(scene) as PackedScene
	if packed == null:
		return
	var probe := packed.instantiate()
	var center := Vector3(16, 0, 16)
	var span := 16.0
	var box2 := Rect2(0, 0, 32, 32)
	if probe is LevelStructure3D:
		var lot: Dictionary = probe.derive_lot()
		if not lot.floors.is_empty():
			var box := Rect2(Vector2(lot.floors[0]), Vector2.ONE)
			for c: Vector2i in lot.floors:
				box = box.merge(Rect2(Vector2(c), Vector2.ONE))
			center = Vector3(box.get_center().x, 0.0, box.get_center().y)
			span = maxf(box.size.x, box.size.y)
			box2 = box
	probe.free()
	# Start from the state the editor itself saved (complete keys), override only the camera.
	var file := "res://.godot/editor/%s-editstate-%s.cfg" % [scene.get_file(), scene.md5_text()]
	var state := ConfigFile.new()
	state.load(file)
	var three: Dictionary = state.get_value("editor_states", "3D", {})
	var views: Array = three.get("viewports", [{}])
	if views.is_empty():
		views.append({})
	var v: Dictionary = views[0]
	v["position"] = center
	v["distance"] = span * 1.6
	v["x_rotation"] = 0.95
	v["y_rotation"] = 0.0
	v["orthogonal"] = false
	v["view_type"] = 0
	views[0] = v
	three["viewports"] = views
	three["viewport_mode"] = 1
	state.set_value("editor_states", "3D", three)
	# 2D tab: frame the plan (PlanView.PX canvas pixels per metre) in a ~1280 x 560 view.
	var two: Dictionary = state.get_value("editor_states", "2D", {})
	var z := minf(1240.0 / (box2.size.x * PlanView.PX + 80.0), 380.0 / (box2.size.y * PlanView.PX + 80.0))
	two["zoom"] = z
	two["ofs"] = box2.get_center() * PlanView.PX - Vector2(620, 250) / z
	state.set_value("editor_states", "2D", two)
	state.save(file)
