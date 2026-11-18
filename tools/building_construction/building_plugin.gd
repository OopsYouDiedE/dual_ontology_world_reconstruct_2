@tool
extends EditorPlugin

const Components = preload("BuildingConstruction/Shared/ComponentFactory.gd")

var dock: VBoxContainer
var category: OptionButton
var items: ItemList
var catalog: Dictionary
var entries: Array = []

func _enter_tree() -> void:
	var file := FileAccess.open("res://tools/building_construction/catalog.json", FileAccess.READ)
	if file == null:
		push_error("无法读取建筑组件目录")
		return
	var data = JSON.parse_string(file.get_as_text())
	if not data is Dictionary:
		push_error("建筑组件目录格式无效")
		return
	catalog = data
	dock = VBoxContainer.new()
	dock.name = "建筑组件"
	category = OptionButton.new()
	dock.add_child(category)
	for key in catalog.categories:
		category.add_item(str(catalog.categories[key]))
		category.set_item_metadata(category.item_count - 1, key)
	items = ItemList.new()
	items.custom_minimum_size = Vector2(220, 260)
	items.size_flags_vertical = Control.SIZE_EXPAND_FILL
	dock.add_child(items)
	var button := Button.new()
	button.text = "添加到当前场景"
	dock.add_child(button)
	category.item_selected.connect(_refresh)
	button.pressed.connect(_add_selected)
	add_control_to_dock(DOCK_SLOT_RIGHT_UL, dock)
	_refresh(0)

func _exit_tree() -> void:
	if dock:
		remove_control_from_docks(dock)
		dock.free()

func _refresh(index: int) -> void:
	items.clear()
	entries.clear()
	var selected = category.get_item_metadata(index)
	for entry in catalog.items:
		if entry.category == selected:
			entries.append(entry)
			items.add_item(str(entry.label))

func _add_selected() -> void:
	var selected := items.get_selected_items()
	var root := get_editor_interface().get_edited_scene_root()
	if selected.is_empty() or root == null:
		push_warning("请先打开场景并选择建筑组件。")
		return
	var path: String = entries[selected[0]].path
	var instance := Components.create(path)
	if instance == null:
		push_error("无法加载建筑组件：" + path)
		return
	for key in entries[selected[0]].get("defaults", {}):
		instance.set(key, entries[selected[0]].defaults[key])
	var undo := get_undo_redo()
	undo.create_action("添加建筑组件")
	undo.add_do_method(root, "add_child", instance, true)
	undo.add_do_method(instance, "set_owner", root)
	undo.add_do_reference(instance)
	undo.add_undo_method(root, "remove_child", instance)
	undo.commit_action()
	get_editor_interface().get_selection().clear()
	get_editor_interface().get_selection().add_node(instance)
