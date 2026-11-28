extends Control
## Native Godot host for the original Web ArchBuilder wall workflow.
const State = preload("ArchitectState.gd")
const RoomPlan = preload("RoomPlan.gd")
const Space = preload("res://scenes/components/life/BuildingSpace.gd")
const Components = preload("BuildingConstruction/Shared/ComponentFactory.gd")
const Geo = preload("BuildingConstruction/Shared/ArchitectGeometry.gd")
const Wall = preload("production/line/WallPathGeometry.gd")
const Floor = preload("BuildingConstruction/Floors/ArchitectFloor.gd")
const Stair = preload("BuildingConstruction/Stairs/ArchitectStair.gd")
const Railing = preload("BuildingConstruction/Railings/ArchitectRailing.gd")
const WebProps = preload("BuildingConstruction/Props/ArchitectProps.gd")
const Footprint = preload("BuildingConstruction/Props/PropFootprint.gd")
const Furnish = preload("AutoFurnish.gd")
const DisplayNames = preload("ArchitectDisplayNames.gd")
const ToolTheme = preload("ToolTheme.gd")
const STYLES = {"classical":"Classical Trim","dado":"Half-Height Paneling","stone":"Rough Stone Blocks","plain":"Plain Plaster"}
const OPENINGS = {"arched_window":"Arched Window","rectangular_window":"Rectangular Multi-Pane Window","round_window":"Round Window","double_door":"Double Wooden Door","closed_door":"Wooden Door","arched_closed_door":"Arched Wooden Door","portal_arch":"Open Archway"}
const FLOOR_STYLES = {"octagonal_tile":"Octagonal Tile","parquet_wood":"Walnut Parquet","stone_slab":"Stone Slabs","plain_grout":"Plain Gray Stone"}
var state = State.new()
var tool = "select"
var drawing: Array = []
var wall_params = {"height":3.6,"thickness":0.28,"baseY":0.0,"style":"classical","hasPillars":true}
var opening_params = {"type":"arched_window","width":1.4,"height":2.3,"bottom":0.85,"rise":0.4}
var rail_params = {"height":0.9,"spacing":0.18}
var stair_params = {"rise":2.4,"run":3.2,"risers":12,"width":1.2,"railingPos":"both","yaw":0.0}
var auto_y = true
var blueprint: Control
var candidates: Node3D
var wireframe = false
var auto_cutaway = true  # 剖面：自动隐藏朝相机的墙段，露出室内（3D 截图里墙挡住室内的问题）
var hidden_parts: Dictionary = {}
var visibility_window: Window
var wire_mesh: MeshInstance3D
var camera: Camera3D
var view3: SubViewportContainer
var viewport3: SubViewport
var inspector: VBoxContainer
var outline: ItemList
var layer_select: OptionButton
var status: Label
var modal: Window
var file_dialog: FileDialog
var file_action = ""
var orbit = Vector2(-0.7,0.8)
var distance = 18.0
var target = Vector3(4,0,3)
var rooms: Array = []
var ui_fields: Dictionary = {}
var catalog: Dictionary = {}
var prop_presets: Dictionary = {}
var web_prop_kind = "wall_lantern"
var prop_fields: VBoxContainer
var prop_entry: Dictionary = {}
var prop_params: Dictionary = {}
var prop_position = Vector2.ZERO
var prop_yaw = 0.0
var conflicts: Dictionary = {}
var tool_buttons: Dictionary = {}
var furnish_clear: CheckBox
var cursor_label: Label
var part_cache: Dictionary = {}
var rebuild_pending = false
var furnish_template = "bedroom"
var furnish_room: OptionButton
var furnish_report: Label
var component_list: ItemList
var component_filter = ""
var gesture_build: RefCounted
var pending_build: RefCounted
var pending_window: ConfirmationDialog
var settings_tabs: TabContainer
const MAIN_PAGES = ["Walls","Openings","Furniture","Floors"]
const MORE_PAGES = ["Stairs","Layout","Furnish","Rooms"]
const TOOL_PAGES = {"wall":"Walls","floor":"Floors","opening":"Openings","prop":"Furniture","railing":"Stairs"}
var layout_seed := 47
var layout_pairs := 2

func _process(_dt: float) -> void:
	# Drag handlers only request a rebuild; it runs at most once per frame.
	if rebuild_pending:
		rebuild_pending = false
		rebuild()

func request_rebuild() -> void: rebuild_pending = true

func update_cursor(point: Vector2) -> void:
	if cursor_label==null: return
	var text = "X %.2f   Z %.2f" % [point.x,point.y]
	var room = state.room_at(point)
	if room>=0: text += "   ·   Room %d (%.1f m²)" % [room+1,state.layer().roomFaces[room].get("area",0.0)]
	text += "   ·   Snap %s" % ("Off" if state.grid_snap<=0 else "%.2f m" % state.grid_snap)
	cursor_label.text = text

func _ready() -> void:
	add_child(preload("res://mcp/building/GodotControl.gd").new())
	get_viewport().gui_embed_subwindows = true
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://tools/building_construction/candidates"))
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	state.new_layer()
	state.remember()
	rooms = JSON.parse_string(FileAccess.get_file_as_string("res://tools/building_construction/architect_rooms.json"))
	for room in rooms:
		if room.id=="R01": state.restore(JSON.stringify(room)); state.remember(); break
	catalog = Components.load_catalog()
	prop_presets = JSON.parse_string(FileAccess.get_file_as_string("res://tools/building_construction/architect_prop_presets.json"))
	_make_ui()
	refresh()
	update_status()
	# 等布局真正完成再 fit：原先只等一帧，blueprint.size 还是 0/很小，
	# reset_views 算出的 zoom/pan 把房间缩到左上角（实机截图：2D 房间只有一小块）。
	await get_tree().process_frame
	await get_tree().process_frame
	reset_views()
	if blueprint != null:
		blueprint.resized.connect(_on_blueprint_resized)

func button(parent: Node, text: String, callback: Callable, tip := "") -> Button:
	var item = Button.new()
	item.text = text
	item.tooltip_text = tip
	item.pressed.connect(callback)
	parent.add_child(item)
	return item
func label(parent: Node, text: String) -> Label:
	var item = Label.new()
	item.text = text
	parent.add_child(item)
	return item
func styled(control: Control, variation: String) -> Control:
	control.theme_type_variation = variation
	return control
## Muted, wrapping helper text.
func hint(parent: Node, text: String) -> Label:
	var item: Label = styled(label(parent,text),"HintLabel")
	item.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	item.custom_minimum_size.x = 200
	return item
## Small muted heading that groups the controls below it.
func section(parent: Node, text: String) -> Label:
	var item: Label = styled(label(parent,text),"SectionLabel")
	item.custom_minimum_size.y = 22
	item.uppercase = true
	item.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
	return item
func primary(parent: Node, text: String, callback: Callable, tip := "") -> Button:
	return styled(button(parent,text,callback,tip),"PrimaryButton")
func move_first(control: Control) -> Control:
	control.get_parent().move_child(control, 0)
	return control
func flat(parent: Node, text: String, callback: Callable, tip := "") -> Button:
	return styled(button(parent,text,callback,tip),"FlatButton")
func number(parent: Node, text: String, value: float, callback: Callable, step := 0.1, minimum := -10000.0, maximum := 10000.0, decimal_step := 0.001) -> SpinBox:
	var row = HBoxContainer.new()
	parent.add_child(row)
	var caption = label(row,text)
	caption.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	caption.clip_text = true
	var item = SpinBox.new()
	item.min_value = minimum
	item.max_value = maximum
	# Format editor coordinates to millimetres. Opening the inspector does not round saved values.
	item.step = decimal_step
	item.custom_arrow_step = step
	item.value = value
	item.custom_minimum_size.x = 125
	row.add_child(item)
	item.value_changed.connect(callback)
	return item
func choice(parent: Node, text: String, options: Dictionary, current: String, callback: Callable) -> OptionButton:
	# Label and picker share one row, like number(): the panel reads as a property sheet.
	var row = HBoxContainer.new()
	parent.add_child(row)
	var caption = label(row,text)
	caption.size_flags_horizontal = Control.SIZE_EXPAND_FILL if not parent is HBoxContainer else 0
	caption.clip_text = not parent is HBoxContainer
	var item = OptionButton.new()
	item.custom_minimum_size.x = 96 if parent is HBoxContainer else 170
	item.clip_text = true
	row.add_child(item)
	for key in options:
		item.add_item(options[key])
		item.set_item_metadata(item.item_count-1,key)
		if key==current: item.select(item.item_count-1)
	item.item_selected.connect(func(index): callback.call(item.get_item_metadata(index)))
	return item
func check(parent: Node, text: String, value: bool, callback: Callable) -> CheckBox:
	var item = CheckBox.new()
	item.text = text
	item.button_pressed = value
	parent.add_child(item)
	item.toggled.connect(callback)
	return item
func text_field(parent: Node, title: String, value: String, callback: Callable) -> void:
	styled(label(parent,title),"FieldLabel")
	var edit = LineEdit.new()
	var shown := DisplayNames.english(value)
	edit.text = shown
	parent.add_child(edit)
	edit.text_submitted.connect(func(name):
		if name != shown: callback.call(name))
	edit.focus_exited.connect(func():
		if edit.text != shown: callback.call(edit.text))
func page(tabs: TabContainer, title: String) -> VBoxContainer:
	var scroll = ScrollContainer.new()
	scroll.name = title
	tabs.add_child(scroll)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	var margin = MarginContainer.new()
	margin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for side in ["left","right","top","bottom"]: margin.add_theme_constant_override("margin_"+side, 4 if side!="top" else 12)
	scroll.add_child(margin)
	var column = VBoxContainer.new()
	column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	column.add_theme_constant_override("separation",10)
	margin.add_child(column)
	return column

func _make_ui() -> void:
	# 现代简洁风：两个建筑工具共用 ToolTheme（深色平面 + 单一强调色 + 圆角）。
	self.theme = ToolTheme.get_theme()
	var backdrop = ColorRect.new()
	backdrop.color = ToolTheme.BG
	backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	backdrop.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(backdrop)
	var root = VBoxContainer.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.add_theme_constant_override("separation",0)
	add_child(root)
	# 顶栏（三级层次）：标题 · 撤销/重做（常用，二级）· File/View 菜单 …… 右侧视图切换与低频工具菜单。
	var top_bar = styled(PanelContainer.new(),"TopBar")
	root.add_child(top_bar)
	var header = HBoxContainer.new()
	top_bar.add_child(header)
	styled(label(header,"ArchBuilder"),"TitleLabel")
	header.add_child(VSeparator.new())
	button(header,"Undo",func(): if state.undo(-1): refresh(),"Ctrl+Z")
	button(header,"Redo",func(): if state.undo(1): refresh(),"Ctrl+Shift+Z / Ctrl+Y")
	# 文件操作收进菜单：顶栏只留常用按钮。
	var file_menu = MenuButton.new()
	file_menu.text = "File ▾"
	file_menu.tooltip_text = "Import, save, or export JSON, YAML, or a Godot scene."
	var fmp = file_menu.get_popup()
	fmp.add_item("Import JSON or YAML…", 0)
	fmp.add_item("Save JSON…", 1)
	fmp.add_item("Save YAML…", 2)
	fmp.add_item("Export Godot Scene…", 3)
	fmp.add_separator()
	fmp.add_item("Clear Scene (Undoable)", 4)
	fmp.id_pressed.connect(func(id: int):
		if id == 0: open_file("import")
		elif id == 1: open_file("json")
		elif id == 2: open_file("yaml")
		elif id == 3: open_file("scene")
		elif id == 4: clear_dialog())
	header.add_child(file_menu)
	var view_menu = MenuButton.new()
	view_menu.text = "View ▾"
	view_menu.tooltip_text = "Wireframe, path tools, and visibility."
	var vmp = view_menu.get_popup()
	vmp.add_item("Toggle Wireframe", 0)
	vmp.add_item("Close Current Path", 1)
	vmp.add_item("Finish Open Path", 2)
	vmp.add_item("Show or Hide Components…", 3)
	vmp.add_item("Cutaway: On", 4)
	vmp.id_pressed.connect(func(id: int):
		if id == 0: wireframe = not wireframe; update_wireframe()
		elif id == 1: finish_path(tool!="railing")
		elif id == 2: finish_path(false)
		elif id == 3: show_visibility()
		elif id == 4:
			auto_cutaway = not auto_cutaway
			vmp.set_item_text(4, "Cutaway: %s" % ("On" if auto_cutaway else "Off"))
			apply_visibility())
	header.add_child(view_menu)
	var spacer = Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(spacer)
	var view_group = ButtonGroup.new()
	for spec in [["Split",true,true],["2D",true,false],["3D",false,true]]:
		var view_button: Button = styled(button(header,spec[0],func(): blueprint.visible = spec[1]; view3.visible = spec[2],"Show the 2D plan and/or the 3D preview"),"ToolButton")
		view_button.toggle_mode = true
		view_button.button_group = view_group
		view_button.button_pressed = spec[0]=="Split"
	header.add_child(VSeparator.new())
	# 低频工具收进菜单，不和绘制主流程抢注意力。
	var more_menu = MenuButton.new()
	more_menu.text = "Tools ▾"
	more_menu.tooltip_text = "Less frequent tools: generated layouts and the structure lab."
	more_menu.get_popup().add_item("Generate Layout…", 0)
	more_menu.get_popup().add_item("Structure Lab", 1)
	more_menu.get_popup().id_pressed.connect(func(id: int):
		if id == 0: preview_generated_layout()
		elif id == 1 and not has_node("StructureLab"): add_child(preload("production/building/StructureLab.tscn").instantiate()))
	header.add_child(more_menu)
	var body = HBoxContainer.new()
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation",0)
	root.add_child(body)
	# 左侧工具栏：最常用的绘制工具放大、竖排、带快捷键；当前工具是一整块蓝色。
	var rail_panel = styled(PanelContainer.new(),"RailPanel")
	body.add_child(rail_panel)
	var rail = VBoxContainer.new()
	rail.custom_minimum_size.x = 132
	rail.add_theme_constant_override("separation",4)
	rail_panel.add_child(rail)
	var tool_group = ButtonGroup.new()
	section(rail,"DRAW")
	for spec in [["select","Select","V"],["wall","Wall","W"],["floor","Floor",""],["opening","Opening","O"],["prop","Furniture","P"],["__more"],["railing","Railing",""]]:
		if spec[0] == "__more":
			section(rail,"MORE")
			continue
		var tool_button = Button.new()
		tool_button.text = spec[1]
		tool_button.alignment = HORIZONTAL_ALIGNMENT_LEFT
		tool_button.theme_type_variation = "RailButton"
		tool_button.toggle_mode = true
		tool_button.button_group = tool_group
		tool_button.button_pressed = spec[0]=="select"
		tool_button.tooltip_text = ("Shortcut: %s. " % spec[2] if spec[2] != "" else "") + "Press Esc to return to Select."
		tool_button.pressed.connect(func(): set_tool(spec[0]))
		rail.add_child(tool_button)
		if spec[2] != "":
			var key: Label = styled(Label.new(),"KeyLabel")
			key.text = spec[2]
			key.mouse_filter = Control.MOUSE_FILTER_IGNORE
			key.set_anchors_and_offsets_preset(Control.PRESET_RIGHT_WIDE)
			key.offset_left = -26
			key.offset_right = -10
			key.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
			key.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
			tool_button.add_child(key)
		tool_buttons[spec[0]] = tool_button
	var center_margin = MarginContainer.new()
	center_margin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for side_name in ["left","right","top","bottom"]: center_margin.add_theme_constant_override("margin_"+side_name,8)
	body.add_child(center_margin)
	var center = VBoxContainer.new()
	center.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	center_margin.add_child(center)
	# 视图上方只留一条细的情境栏：吸附、居中、光标坐标。
	var actions = HBoxContainer.new()
	center.add_child(actions)
	choice(actions,"Snap",{"0":"Off","0.1":"0.10m","0.2":"0.20m","0.5":"0.50m","1":"1m"},"0.2",func(v): state.grid_snap = float(v))
	flat(actions,"Center",reset_views,"Center the building in the view. Shortcut: F")
	cursor_label = styled(label(actions,""),"HintLabel")
	cursor_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cursor_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	cursor_label.clip_text = true
	var views = HSplitContainer.new()
	views.size_flags_vertical = Control.SIZE_EXPAND_FILL
	center.add_child(views)
	blueprint = preload("ArchitectBlueprint.tscn").instantiate()
	blueprint.editor = self
	blueprint.custom_minimum_size.x = 320
	blueprint.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	views.add_child(blueprint)
	view3 = SubViewportContainer.new()
	view3.stretch = true
	view3.custom_minimum_size.x = 320
	view3.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	views.add_child(view3)
	viewport3 = SubViewport.new()
	viewport3.size = Vector2i(520,720)
	viewport3.own_world_3d = true
	viewport3.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	view3.add_child(viewport3)
	var world = Node3D.new()
	viewport3.add_child(world)
	candidates = Node3D.new()
	candidates.name = "ArchBuilderRoot"
	world.add_child(candidates)
	wire_mesh = MeshInstance3D.new()
	world.add_child(wire_mesh)
	var environment = WorldEnvironment.new()
	var env = Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color("12151a")
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color("ffedd3")
	env.ambient_light_energy = 0.55
	environment.environment = env
	world.add_child(environment)
	var light = DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-50,-35,0)
	light.light_color = Color("ffe5c5")
	light.light_energy = 1.0
	light.shadow_enabled = true
	world.add_child(light)
	camera = Camera3D.new()
	camera.fov = 42
	world.add_child(camera)
	view3.gui_input.connect(_camera_input)
	_update_camera()
	var side_panel = styled(PanelContainer.new(),"SidePanel")
	body.add_child(side_panel)
	var side = VBoxContainer.new()
	side.custom_minimum_size.x = 372
	side_panel.add_child(side)
	# 设置页导航：4 个常用页平铺，4 个低频页收进 More ▾。选工具时自动跳到对应设置页。
	var tab_grid = HBoxContainer.new()
	tab_grid.add_theme_constant_override("separation",2)
	side.add_child(tab_grid)
	var tabs = TabContainer.new()
	tabs.tabs_visible = false
	tabs.custom_minimum_size.y = 220
	tabs.size_flags_vertical = Control.SIZE_EXPAND_FILL
	side.add_child(tabs)
	var floors = page(tabs,"Floors")
	layer_select = OptionButton.new()
	floors.add_child(layer_select)
	layer_select.item_selected.connect(func(index):
		state.data.activeLayerId = layer_select.get_item_metadata(index)
		if auto_y: sync_wall("baseY",state.layer().y)
		refresh_layers())
	button(floors,"Add Floor",func(): edit_build(func(draft): draft.new_layer(), true))
	ui_fields.layer_y = number(floors,"Floor Height (m)",0,func(v):
		if edit_build(func(draft): draft.layer().y = v) and auto_y: sync_wall("baseY",v))
	ui_fields.floor_style = choice(floors,"Floor Finish",FLOOR_STYLES,"octagonal_tile",func(v): edit_build(func(draft): draft.layer().style = v))
	move_first(primary(floors,"Draw Floor in 2D",func(): set_tool("floor")))
	hint(floors,"Nearby floors merge within 0.3 m.")
	var walls = page(tabs,"Walls")
	check(walls,"Match Floor Elevation",true,func(v): auto_y = v; if v: sync_wall("baseY",state.layer().get("y",0)))
	choice(walls,"Wall Finish",STYLES,"classical",func(v): wall_params.style = v)
	for spec in [["height","Wall Height (m)",0.1],["thickness","Wall Thickness (m)",0.02],["baseY","Base Height (m)",0.1]]:
		var key = spec[0]
		ui_fields[key] = number(walls,spec[1],wall_params[key],func(v): sync_wall(key,v),spec[2])
	hint(walls,"Adjacent rooms share wall junctions.")
	check(walls,"Decorative Corner and End Columns",true,func(v): wall_params.hasPillars = v)
	move_first(primary(walls,"Draw Walls in 2D",func(): set_tool("wall")))
	var path_row = HBoxContainer.new()
	walls.add_child(path_row)
	walls.move_child(path_row, 1)
	flat(path_row,"Close Loop  (Enter)",func(): finish_path(true)).size_flags_horizontal = Control.SIZE_EXPAND_FILL
	flat(path_row,"Finish Open",func(): finish_path(false)).size_flags_horizontal = Control.SIZE_EXPAND_FILL
	button(walls,"Build Walls Around Floor",func():
		var draft: RefCounted = state.fork_candidate()
		if draft.auto_walls(wall_params): preview_build(draft, "Walls from Floor")
		else: status.text = "Draw a floor first, or edit the existing walls directly.")
	var layout := page(tabs,"Layout")
	number(layout,"Seed",layout_seed,func(v): layout_seed = int(v),1,0,2147483647,1.0)
	number(layout,"Room pairs",layout_pairs,func(v): layout_pairs = int(v),1,1,4,1.0)
	hint(layout,"Generate rooms on both sides of one shared hall.")
	move_first(primary(layout,"Preview New Layout",preview_generated_layout))
	var openings = page(tabs,"Openings")
	choice(openings,"Opening Type",OPENINGS,opening_params.type,func(v):
		opening_params.type = v
		opening_params.bottom = 0.85 if "window" in v else 0.0
		ui_fields.op_bottom.set_value_no_signal(opening_params.bottom)
		ui_fields.op_rise.get_parent().visible = "arched" in v)
	for spec in [["width","Width (m)"],["height","Height (m)"],["bottom","Height Above Floor (m)"],["rise","Arch Rise (m)"]]:
		var key = spec[0]
		ui_fields["op_"+key] = number(openings,spec[1],opening_params[key],func(v): opening_params[key] = v)
	move_first(primary(openings,"Place Opening on Wall",func(): set_tool("opening")))
	var stairs = page(tabs,"Stairs")
	for key in ["rise","run","risers","width","yaw"]:
		number(stairs,{"rise":"Rise (m)","run":"Run (m)","risers":"Steps","width":"Width (m)","yaw":"Rotation (deg)"}[key],stair_params[key],func(v): stair_params[key] = v,1 if key=="risers" else 0.1,1 if key=="risers" else (-360.0 if key=="yaw" else 0.1), 360.0 if key=="yaw" else 10000.0, 1.0 if key=="risers" else 0.01)
	choice(stairs,"Stair handrail",{"both":"Both sides","left":"Left","right":"Right","none":"None"},"both",func(v): stair_params.railingPos = v)
	move_first(primary(stairs,"Preview Straight Stair",spawn_stair))
	number(stairs,"Railing height (m)",0.9,func(v): rail_params.height = v)
	number(stairs,"Post spacing (m)",0.18,func(v): rail_params.spacing = v,0.02,0.02)
	button(stairs,"Draw Railing in 2D",func(): set_tool("railing"))
	var props = page(tabs,"Furniture")
	section(props,"COMPONENT LIBRARY")
	var filter = LineEdit.new()
	filter.placeholder_text = "Search components…"
	filter.clear_button_enabled = true
	filter.text_changed.connect(func(text): component_filter = text; refresh_component_list())
	props.add_child(filter)
	component_list = ItemList.new()
	component_list.custom_minimum_size.y = 150
	component_list.item_selected.connect(func(index):
		prop_entry = component_list.get_item_metadata(index)
		prop_params = Components.parameter_defaults(prop_entry))
	props.add_child(component_list)
	refresh_component_list()
	primary(props,"Place Component in 2D",func(): set_tool("prop"))
	button(props,"Open Component Library",func(): get_tree().change_scene_to_file("res://tools/building_construction/ComponentLibrary.tscn"))
	section(props,"BUILT-IN FIXTURES")
	choice(props,"Fixture",prop_names(),web_prop_kind,func(v): web_prop_kind = v; refresh_prop_fields())
	prop_fields = VBoxContainer.new()
	props.add_child(prop_fields)
	refresh_prop_fields()
	number(props,"Position X",0,func(v): prop_position.x = v)
	number(props,"Position Z",0,func(v): prop_position.y = v)
	number(props,"Rotation (deg)",0,func(v): prop_yaw = v,15)
	button(props,"Place Fixture in 2D",func(): prop_entry = {}; set_tool("prop"))
	flat(props,"Preview at Coordinates",func(): prop_entry = {}; place_prop(prop_position))
	var furnish_page = page(tabs,"Furnish")
	var furnish_help = hint(furnish_page,"Preview furniture by room type. Placement keeps furniture inside the room and clear of doorways and other objects.")
	furnish_help.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	furnish_help.custom_minimum_size.x = 300
	choice(furnish_page,"Room type",Furnish.template_names(),furnish_template,func(v): furnish_template = v)
	label(furnish_page,"Enclosed room")
	furnish_room = OptionButton.new()
	furnish_page.add_child(furnish_room)
	furnish_clear = check(furnish_page,"Replace existing furniture in selected rooms",true,func(_v): pass)
	primary(furnish_page,"Preview Selected Room",func(): furnish_rooms([furnish_room.selected]))
	button(furnish_page,"Preview All Rooms on Floor",func(): furnish_rooms(range(furnish_room.item_count)))
	button(furnish_page,"Preview Clearing Selected Room",clear_room_props)
	furnish_report = label(furnish_page,"")
	furnish_report.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	furnish_report.custom_minimum_size.x = 300
	var presets = page(tabs,"Rooms")
	hint(presets,"%d furnished room presets" % rooms.size())
	var room_select = OptionButton.new()
	room_select.custom_minimum_size.x = 260
	room_select.clip_text = true
	presets.add_child(room_select)
	for room in rooms: room_select.add_item(str(room.id)+" · "+DisplayNames.name_of(room))
	if rooms.size()>1: room_select.select(1)
	primary(presets,"Load Room Preset",func():
		load_build(JSON.stringify(rooms[room_select.selected])))
	settings_tabs = tabs
	var tab_index := {}
	for i in tabs.get_tab_count(): tab_index[tabs.get_tab_title(i)] = i
	var tab_buttons := {}
	for title in MAIN_PAGES:
		var tab_button: Button = styled(button(tab_grid,title,func(): tabs.current_tab = tab_index[title]),"ToolButton")
		tab_button.toggle_mode = true
		tab_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		tab_buttons[tab_index[title]] = tab_button
	var more_pages = MenuButton.new()
	more_pages.text = "More ▾"
	more_pages.tooltip_text = "Stairs, generated layouts, auto-furnish and room presets."
	for title in MORE_PAGES: more_pages.get_popup().add_item(title, tab_index[title])
	more_pages.get_popup().id_pressed.connect(func(id: int): tabs.current_tab = id)
	tab_grid.add_child(more_pages)
	var sync_tabs = func(i: int):
		for j in tab_buttons: tab_buttons[j].set_pressed_no_signal(j == i)
		var in_more: bool = not tab_buttons.has(i)
		more_pages.text = (tabs.get_tab_title(i) + " ▾") if in_more else "More ▾"
		more_pages.add_theme_color_override("font_color", ToolTheme.ACCENT_HOVER if in_more else ToolTheme.MUTED)
	tabs.tab_changed.connect(sync_tabs)
	tabs.current_tab = tab_index["Walls"]
	sync_tabs.call(tabs.current_tab)
	# 设置页与“选中/属性”之间可拖动分隔：编辑选中物体时把属性区拉大。
	side.remove_child(tabs)
	var side_split = VSplitContainer.new()
	side_split.size_flags_vertical = Control.SIZE_EXPAND_FILL
	side.add_child(side_split)
	side_split.add_child(tabs)
	var selection_area = VBoxContainer.new()
	selection_area.size_flags_vertical = Control.SIZE_EXPAND_FILL
	side_split.add_child(selection_area)
	side = selection_area
	section(side,"SELECTION")
	outline = ItemList.new()
	outline.custom_minimum_size.y = 80
	side.add_child(outline)
	outline.item_selected.connect(func(index): state.selected = outline.get_item_metadata(index).duplicate(); refresh_inspector())
	var edit_actions = HBoxContainer.new()
	side.add_child(edit_actions)
	button(edit_actions,"Edit Properties  (E)",show_parameters).size_flags_horizontal = Control.SIZE_EXPAND_FILL
	styled(button(edit_actions,"Delete",delete_selected),"DangerButton")
	var scroll = ScrollContainer.new()
	scroll.custom_minimum_size.y = 80
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	side.add_child(scroll)
	inspector = VBoxContainer.new()
	inspector.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(inspector)
	var status_bar = styled(PanelContainer.new(),"StatusBar")
	root.add_child(status_bar)
	status = styled(label(status_bar,""),"HintLabel")
	status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	file_dialog = FileDialog.new()
	file_dialog.access = FileDialog.ACCESS_FILESYSTEM
	file_dialog.use_native_dialog = false
	file_dialog.file_selected.connect(_file_selected)
	add_child(file_dialog)

func sync_wall(key: String, value: float) -> void:
	wall_params[key] = value
	if ui_fields.has(key): ui_fields[key].set_value_no_signal(value)
	if key=="baseY":
		for p in drawing: p[2] = value
func set_tool(value: String) -> void:
	if gesture_build != null: blueprint.end_drag(false)
	tool = value
	drawing = []
	for key in tool_buttons: tool_buttons[key].set_pressed_no_signal(key==tool)
	if tool=="wall" and auto_y: sync_wall("baseY",state.layer().get("y",0))
	# 选工具 = 打开它的设置页，常用参数总在手边。
	if settings_tabs != null and TOOL_PAGES.has(tool):
		for i in settings_tabs.get_tab_count():
			if settings_tabs.get_tab_title(i) == TOOL_PAGES[tool]: settings_tabs.current_tab = i
	update_status()
func update_status() -> void:
	status.text = {"select":"Select or drag with the left mouse button. Double-click a node or press E to edit. Delete removes, Ctrl+Z undoes, F centers.", "wall":"Place wall nodes. Click the start or press Enter to close, or choose Finish Open Path.", "floor":"Place floor vertices. Click the start or press Enter to finish.", "opening":"Click a wall to place an opening. In Select mode, drag it along the wall.", "railing":"Place railing nodes and press Enter to finish.", "prop":"Click in 2D to place the selected component."}.get(tool,tool)+"  |  Nodes: "+str(drawing.size())
func display_state() -> RefCounted:
	return pending_build if pending_build != null else (gesture_build if gesture_build != null else state)

func preview_generated_layout() -> void:
	if pending_build != null: return
	var draft: RefCounted = state.fork_candidate()
	if not draft.restore(JSON.stringify(RoomPlan.build(layout_seed,layout_pairs))): return
	preview_build(draft, "New Layout · Seed %d" % layout_seed, 2 * layout_pairs + 1, true)

func preview_opening(point: Vector2) -> void:
	if pending_build != null: return
	var draft: RefCounted = state.fork_candidate()
	if draft.add_opening(point,opening_params): preview_build(draft, "Door or Window")
	else: status.text = draft.message

func preview_build(draft: RefCounted, title: String, expected_rooms := -1, fit_view := false, details := "") -> void:
	if pending_build != null: return
	draft.sync_rooms()
	var space := Space.new()
	var active: Dictionary = draft.layer()
	var access := {"groups": 0, "unusable": 0, "grid_limit": false}
	if not active.is_empty():
		space.setup(draft.data,draft.data.layers.find(active))
		access = space.room_access()
	var text := "%d enclosed %s · %d %s" % [space.rooms.size(),
		"space" if space.rooms.size() == 1 else "spaces",access.groups,
		"connected group" if access.groups == 1 else "connected groups"]
	if access.unusable > 0: text += " · %d without standing room" % access.unusable
	if access.grid_limit: text += " · navigation grid limit exceeded"
	if not details.is_empty(): text += "\n" + details
	if fit_view: text += "\nApplying replaces the current draft. Undo restores it."
	var can_apply: bool = not access.grid_limit and (expected_rooms < 0 or (space.rooms.size() == expected_rooms and access.groups == 1 and access.unusable == 0))
	if not can_apply: text += "\nThis candidate did not pass validation."
	pending_build = draft
	rebuild()
	if fit_view: reset_views(true)
	blueprint.queue_redraw()
	pending_window = ConfirmationDialog.new()
	pending_window.title = title
	pending_window.dialog_text = text
	pending_window.ok_button_text = "Apply Build"
	pending_window.cancel_button_text = "Discard Preview"
	pending_window.exclusive = true
	add_child(pending_window)
	pending_window.get_ok_button().disabled = not can_apply
	pending_window.confirmed.connect(func(): close_build_preview(can_apply,fit_view))
	pending_window.canceled.connect(func(): close_build_preview(false,fit_view))
	pending_window.popup_centered(Vector2i(465,128))

func close_build_preview(apply: bool, fit_view: bool) -> void:
	if pending_build == null: return
	var accepted: bool = apply and state.accept_candidate(pending_build)
	pending_build = null
	pending_window.hide()
	pending_window.queue_free()
	pending_window = null
	refresh()
	if fit_view: reset_views(accepted)
	status.text = "Build applied · one undo step" if accepted else "Build preview discarded · draft unchanged"

func finish_path(close: bool) -> void:
	if pending_build != null or drawing.size()<2: return
	if tool == "floor" and drawing.size() < 3: return
	if tool not in ["floor", "wall", "railing"]: return
	var draft: RefCounted = state.fork_candidate()
	var active: Dictionary = draft.layer()
	if tool=="floor":
		if drawing.size()>=3:
			var points = []
			for p in drawing: points.append([p[0],p[1]])
			draft.add_floor(points)
	elif tool=="wall":
		var points = []
		for p in drawing: points.append([p[0],p[2],p[1]])
		var closed = close and drawing.size()>=3
		if closed: points.append(points[0].duplicate())
		var wall = wall_params.duplicate(true)
		wall.merge({"id":draft.uid("wall"),"name":"Wall #"+str(draft.data.walls.size()+1),"points":points,"closed":closed,"openings":[]},true)
		draft.data.walls.append(wall)
	elif tool=="railing":
		var points = []
		for p in drawing: points.append([p[0],active.get("y",0),p[1]])
		var rail = rail_params.duplicate()
		rail.merge({"id":draft.uid("rail"),"name":"Wood Railing #"+str(draft.data.railings.size()+1),"points":points})
		draft.data.railings.append(rail)
	var title := {"wall": "Wall Path", "floor": "Floor Outline", "railing": "Railing"}
	var candidate_title: String = title[tool]
	set_tool("select")
	preview_build(draft,candidate_title)
func insert_plan_node(point: Vector2, tolerance: float) -> void:
	if pending_build != null or gesture_build != null: return
	var draft: RefCounted = state.fork_candidate()
	if draft.insert_wall_node(point, tolerance):
		commit_edit(draft, true)
		return
	for li in range(draft.data.layers.size()):
		for pi in range(draft.data.layers[li].polygons.size()):
			var poly = draft.data.layers[li].polygons[pi]
			for i in range(poly.size()):
				var a = poly[i]
				var b = poly[(i+1)%poly.size()]
				var hit = state.project(point,Vector2(a[0],a[1]),Vector2(b[0],b[1]))
				if hit.dist<=tolerance:
					poly.insert(i+1,[state.snap(hit.point.x),state.snap(hit.point.y)])
					draft.selected = {"kind":"floorNode","layerIndex":li,"polyIndex":pi,"ptIndex":i+1}
					commit_edit(draft, true)
					return
func spawn_stair() -> void:
	if pending_build != null or state.layer().is_empty(): return
	var draft: RefCounted = state.fork_candidate()
	var stair = stair_params.duplicate(true)
	stair.merge({"id":draft.uid("st"),"name":"Straight Stair #"+str(draft.data.stairs.size()+1),"x":1.2,"y":draft.layer().get("y",0),"z":1.2,"nosing":0.03})
	draft.data.stairs.append(stair)
	draft.selected = {"kind":"stair","index":draft.data.stairs.size()-1}
	preview_build(draft, "Place Stair", -1, false, "Geometry preview only. Landing access is not checked.")
func refresh_component_list() -> void:
	component_list.clear()
	for entry in catalog.items:
		if not entry.get("recipe",false) and not str(entry.path).get_file().begins_with("Recipe"): continue
		var title = str(entry.label)
		if component_filter!="" and not (title+" "+str(entry.id)).containsn(component_filter): continue
		component_list.add_item(title)
		component_list.set_item_metadata(component_list.item_count-1,entry)

## Push a wall-hugging or wall-mounted piece flush against the nearest wall face.
func snap_prop(item: Dictionary, point: Vector2, draft: RefCounted) -> void:
	if str(item.get("kind",""))=="native_recipe": return
	var f = Footprint.info(item)
	var wants = f.mount==Footprint.WALL or str(item.kind) in Footprint.AGAINST_WALL
	if not wants: return
	var reach = 0.45 if f.mount==Footprint.WALL else f.d*0.5+0.4
	var hit = draft.wall_snap(point,reach,float(draft.layer().get("y",0)))
	if hit.is_empty(): return
	Footprint.against_wall(item,hit.point,hit.normal,hit.half)

func place_prop(point: Vector2) -> void:
	if pending_build != null or state.layer().is_empty(): return
	var draft: RefCounted = state.fork_candidate()
	var layer_y = float(draft.layer().get("y",0))
	var item: Dictionary
	if prop_entry.is_empty():
		item = {"id":draft.uid("prop"),"name":prop_presets[web_prop_kind].name,"kind":web_prop_kind,"x":draft.snap(point.x),"y":layer_y,"z":draft.snap(point.y),"yaw":prop_yaw,"params":prop_params.duplicate(true)}
		# Hanging heights are preset offsets above the active floor (the stored value is absolute, like the room data).
		var mount_field = Footprint.MOUNT_FIELD.get(web_prop_kind,"")
		if mount_field!="" and prop_params.has(mount_field):
			item.y = Geo.js_round((layer_y+float(prop_params[mount_field]))*100)/100
			item.params[mount_field] = item.y
		if not Input.is_key_pressed(KEY_ALT): snap_prop(item,point,draft)
	else:
		item = {"id":draft.uid("prop"),"name":prop_entry.label,"kind":"native_recipe","path":prop_entry.path,"x":draft.snap(point.x),"y":layer_y,"z":draft.snap(point.y),"yaw":prop_yaw,"params":prop_params.duplicate(true)}
	draft.data.props.append(item)
	draft.selected = {"kind":"prop","index":draft.data.props.size()-1}
	preview_build(draft, "Place Furniture or Fixture")

func prop_names() -> Dictionary:
	var names = {}
	for key in prop_presets: names[key] = prop_presets[key].name
	return names
func refresh_prop_fields() -> void:
	clear_children(prop_fields)
	prop_params = {}
	for field in prop_presets[web_prop_kind].fields:
		prop_params[field.id] = field.val
		number(prop_fields,field.label,field.val,func(v): prop_params[field.id] = v,field.step)
# Each command edits a private draft. Scalar commits keep the focused control alive.
func commit_edit(draft: RefCounted, full_refresh := false) -> bool:
	if not state.accept_candidate(draft):
		refresh()
		status.text = "Edit discarded because the draft changed."
		return false
	if full_refresh:
		refresh()
	else:
		conflicts = state.prop_conflicts()
		request_rebuild()
		refresh_layers()
		refresh_outline()
		update_status()
	return true

func edit_build(edit: Callable, full_refresh := false) -> bool:
	if pending_build != null or gesture_build != null: return false
	var draft: RefCounted = state.fork_candidate()
	edit.call(draft)
	return commit_edit(draft, full_refresh)

func set_build_field(path: Array, value: Variant) -> void:
	edit_build(func(draft):
		var item: Variant = draft.data
		for key in path.slice(0, -1):
			if item is Dictionary and not item.has(key): return
			if item is Array and (not key is int or key < 0 or key >= item.size()): return
			item = item[key]
		if item is Array and (not path[-1] is int or path[-1] < 0 or path[-1] >= item.size()): return
		item[path[-1]] = value)

func delete_selected() -> void:
	if not state.selected.is_empty(): edit_build(func(draft): draft.delete_selected(), true)

func refresh() -> void:
	conflicts = state.prop_conflicts()
	rebuild()
	refresh_layers()
	refresh_outline()
	refresh_inspector()
	update_status()

func rebuild() -> void:
	var shown := display_state()
	shown.sync_rooms()
	# Only items whose data changed are rebuilt; untouched parts keep their meshes (big win while dragging).
	var used = {}
	for item in shown.data.layers: sync_part("layers",item,func(i): return Floor.build(i),used)
	for item in shown.data.walls: sync_part("walls",item,func(i): return Wall.build(i),used)
	for item in shown.data.stairs: sync_part("stairs",item,func(i): return Stair.build(i),used)
	for item in shown.data.railings: sync_part("railings",item,func(i): return Railing.build(i),used)
	for item in shown.data.props: sync_part("props",item,build_prop,used)
	for key in part_cache.keys():
		if used.has(key): continue
		var stale = part_cache[key].node
		if is_instance_valid(stale):
			candidates.remove_child(stale)
			stale.queue_free()
		part_cache.erase(key)
	apply_visibility()

func build_prop(item: Dictionary) -> Node3D:
	if item.get("path","")!="":
		var entry := {"path": item.path}
		for candidate in catalog.get("items", []):
			if candidate.path == item.path:
				entry = candidate
				break
		var node := Components.create_entry(entry, item.params)
		if node == null: return null
		node.position = Vector3(item.x,item.get("y",0),item.z)
		node.rotation.y = deg_to_rad(item.get("yaw",0))
		return node
	# Web prop builders are registered below, preserving their own source dimensions.
	return WebProps.build(item)

func sync_part(category: String, item: Dictionary, builder: Callable, used: Dictionary) -> void:
	var key = category+"|"+str(item.get("id",""))
	while used.has(key): key += "'"
	used[key] = true
	var signature = hash(var_to_str(item))
	if part_cache.has(key) and part_cache[key].sig==signature and is_instance_valid(part_cache[key].node): return
	if part_cache.has(key) and is_instance_valid(part_cache[key].node):
		candidates.remove_child(part_cache[key].node)
		part_cache[key].node.queue_free()
	var node = builder.call(item)
	if node==null: part_cache.erase(key); return
	add_view_part(node,category,item)
	part_cache[key] = {"sig":signature,"node":node}

func add_view_part(node: Node3D, category: String, item: Dictionary) -> void:
	node.set_meta("view_category",category)
	node.set_meta("view_id",str(item.id))
	candidates.add_child(node)

func _cutaway_hidden() -> Dictionary:
	var out: Dictionary = {}
	if not auto_cutaway or camera == null or candidates == null: return out
	var cam_dir: Vector3 = camera.position - target
	cam_dir.y = 0.0
	if cam_dir.length() < 0.01: return out
	cam_dir = cam_dir.normalized()
	for node in candidates.get_children():
		if str(node.get_meta("view_category", "")) != "walls": continue
		var wall: Dictionary = node.get_meta("wall_path", {})
		var pts: Array = wall.get("points", [])
		var wid := str(node.get_meta("view_id", ""))
		for i in range(pts.size() - 1):
			var mid := Vector3((float(pts[i][0]) + float(pts[i + 1][0])) * 0.5, 0.0, (float(pts[i][2]) + float(pts[i + 1][2])) * 0.5)
			var rel: Vector3 = mid - target
			rel.y = 0.0
			if rel.dot(cam_dir) > 0.4:
				out[wid + "/Segment_" + str(i)] = true
	return out


func apply_visibility() -> void:
	var cutaway := _cutaway_hidden()
	for node in candidates.get_children():
		var category = str(node.get_meta("view_category",""))
		var id = str(node.get_meta("view_id",""))
		node.visible = not hidden_parts.has(category) and not hidden_parts.has(id)
		if category!="walls": continue
		var wall: Dictionary = node.get_meta("wall_path")
		var count = wall.points.size()-1
		for child in node.get_children():
			if str(child.name).begins_with("Segment_"):
				child.visible = not hidden_parts.has(id+"/"+str(child.name)) and not cutaway.has(id+"/"+str(child.name))
			elif child.has_meta("wall_joint"):
				var joint = int(child.get_meta("wall_joint"))
				var before = (joint-1+count)%count
				var after = joint%count
				child.visible = not (hidden_parts.has(id+"/Segment_"+str(before)) and hidden_parts.has(id+"/Segment_"+str(after)))
	update_wireframe()

func visibility_check(parent: Node, caption: String, key: String) -> void:
	check(parent,caption,not hidden_parts.has(key),func(shown):
		if shown: hidden_parts.erase(key)
		else: hidden_parts[key] = true
		apply_visibility())

func show_visibility() -> void:
	if is_instance_valid(visibility_window): visibility_window.queue_free()
	visibility_window = Window.new()
	visibility_window.title = "3D Visibility"
	visibility_window.size = Vector2i(490,650)
	visibility_window.close_requested.connect(func(): visibility_window.hide())
	add_child(visibility_window)
	var scroll = ScrollContainer.new()
	scroll.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	visibility_window.add_child(scroll)
	var box = VBoxContainer.new()
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(box)
	label(box,"Only affects the 3D preview. Exports always include the full building.")
	button(box,"Show All",func(): hidden_parts.clear(); apply_visibility(); show_visibility())
	for category in {"walls":"Walls and Openings","layers":"Floors","stairs":"Stairs","railings":"Railing","props":"Furniture and Lighting"}:
		visibility_check(box,{"walls":"Walls and Openings","layers":"Floors","stairs":"Stairs","railings":"Railing","props":"Furniture and Lighting"}[category],category)
	for wall in state.data.walls:
		label(box,DisplayNames.name_of(wall))
		for i in range(wall.points.size()-1):
			visibility_check(box,"Wall Segment %d · %s → %s" % [i+1,str(wall.points[i]),str(wall.points[i+1])],str(wall.id)+"/Segment_"+str(i))
	for spec in [["layers","Floors"],["stairs","Stairs"],["railings","Railing"],["props","Furniture and Lighting"]]:
		label(box,spec[1])
		for item in state.data[spec[0]]: visibility_check(box,DisplayNames.name_of(item),str(item.id))
	visibility_window.popup_centered()

func view_mesh_shown(node: Node3D) -> bool:
	var current: Node = node
	while current!=candidates:
		if current is Node3D and not current.visible: return false
		current = current.get_parent()
	return true

func update_wireframe() -> void:
	candidates.visible = not wireframe
	wire_mesh.visible = wireframe
	if not wireframe: return
	# Compatibility renderer has no viewport wireframe mode. Draw the same triangle edges.
	var surface = SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_LINES)
	var count = 0
	for node in candidates.find_children("*","MeshInstance3D",true,false):
		if node.mesh==null or not view_mesh_shown(node): continue
		for si in range(node.mesh.get_surface_count()):
			var arrays = node.mesh.surface_get_arrays(si)
			if arrays.is_empty(): continue
			var vertices = arrays[Mesh.ARRAY_VERTEX]
			var indices = arrays[Mesh.ARRAY_INDEX]
			if indices==null or indices.is_empty(): indices = range(vertices.size())
			var mat = node.material_override if node.material_override else node.mesh.surface_get_material(si)
			var color = mat.albedo_color if mat is StandardMaterial3D else Color.WHITE
			for i in range(0,indices.size()-2,3):
				for edge in [[0,1],[1,2],[2,0]]:
					for index in edge:
						surface.set_color(color)
						surface.add_vertex(node.global_transform*vertices[indices[i+index]])
						count += 1
	var line_mat = StandardMaterial3D.new()
	line_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	line_mat.vertex_color_use_as_albedo = true
	surface.set_material(line_mat)
	wire_mesh.mesh = surface.commit() if count>0 else null

func refresh_layers() -> void:
	refresh_furnish_rooms()
	layer_select.clear()
	for item in state.data.layers:
		layer_select.add_item(DisplayNames.name_of(item)+" · Y="+str(item.y))
		layer_select.set_item_metadata(layer_select.item_count-1,item.id)
		if item.id==state.data.activeLayerId: layer_select.select(layer_select.item_count-1)
	if not state.layer().is_empty(): ui_fields.layer_y.set_value_no_signal(state.layer().y)
	for index in range(ui_fields.floor_style.item_count):
		if ui_fields.floor_style.get_item_metadata(index)==state.layer().get("style","octagonal_tile"): ui_fields.floor_style.select(index)
func refresh_outline() -> void:
	outline.clear()
	for li in range(state.data.layers.size()):
		for pi in range(state.data.layers[li].polygons.size()):
			var face = state.data.layers[li].roomFaces[pi] if state.data.layers[li].has("roomFaces") and pi<state.data.layers[li].roomFaces.size() else {}
			outline.add_item("Room · "+DisplayNames.name_of(state.data.layers[li])+" #"+str(pi+1)+("  %.1f m²" % face.area if face.has("area") else ""))
			outline.set_item_metadata(outline.item_count-1,{"kind":"floorPoly","layerIndex":li,"polyIndex":pi})
	for spec in [["walls","wall","wallIndex"],["stairs","stair","index"],["railings","railing","railIndex"],["props","prop","index"]]:
		for i in range(state.data[spec[0]].size()):
			var item = state.data[spec[0]][i]
			outline.add_item(("⚠ " if spec[0]=="props" and conflicts.has(i) else "")+DisplayNames.name_of(item))
			outline.set_item_metadata(outline.item_count-1,{"kind":spec[1],spec[2]:i})
			if spec[0]=="walls":
				for oi in range(item.openings.size()):
					outline.add_item("  └ Opening · "+str(OPENINGS.get(item.openings[oi].type, item.openings[oi].type)))
					outline.set_item_metadata(outline.item_count-1,{"kind":"opening","wallIndex":i,"opIndex":oi})
func refresh_furnish_rooms() -> void:
	if furnish_room==null: return
	var keep = furnish_room.selected
	furnish_room.clear()
	var active = state.layer()
	if active.has("roomFaces"):
		for i in range(active.roomFaces.size()):
			var face = active.roomFaces[i]
			furnish_room.add_item("Room %d · %.1f m² · %d neighbors" % [i+1,face.get("area",0.0),face.get("neighbors",[]).size()])
	if furnish_room.item_count>0: furnish_room.select(clampi(keep,0,furnish_room.item_count-1))

func active_layer_index() -> int:
	for i in range(state.data.layers.size()):
		if state.data.layers[i].id==state.data.activeLayerId: return i
	return 0

func furnish_rooms(indices: Array) -> void:
	if pending_build != null: return
	var layer_index := active_layer_index()
	var draft: RefCounted = state.fork_candidate()
	var layer: Dictionary = draft.layer()
	var faces: Array = layer.get("roomFaces", [])
	if faces.is_empty() or indices.is_empty() or furnish_room.item_count == 0:
		furnish_report.text = "Draw an enclosed room on this floor first."
		return
	var selected_rooms: Array[int] = []
	for ri in indices:
		if ri >= 0 and ri < faces.size() and ri not in selected_rooms: selected_rooms.append(ri)
	if selected_rooms.is_empty(): return
	var removed := 0
	if furnish_clear.button_pressed:
		var doomed := {}
		for ri in selected_rooms:
			for pi in draft.props_in_room(layer_index,ri): doomed[pi] = true
		var order := doomed.keys()
		order.sort()
		order.reverse()
		for pi in order: draft.data.props.remove_at(pi)
		removed = order.size()
	var total := 0
	for ri in selected_rooms:
		var existing: Array = draft.data.props.filter(func(prop): return draft.prop_layer_index(prop) == layer_index)
		var added: Array = Furnish.furnish(furnish_template, faces[ri], float(layer.y), draft.data.walls, existing, prop_presets)
		draft.data.props.append_array(added)
		total += added.size()
	if total == 0:
		furnish_report.text = "No furniture fits the selected rooms."
		return
	draft.selected = {}
	preview_build(draft, "Auto Furnish", -1, false, "%d new fixtures · %d existing fixtures removed" % [total, removed])

func clear_room_props() -> void:
	if pending_build != null or furnish_room.item_count == 0: return
	var draft: RefCounted = state.fork_candidate()
	var found: Array = draft.props_in_room(active_layer_index(),furnish_room.selected)
	if found.is_empty(): return
	found.reverse()
	for pi in found: draft.data.props.remove_at(pi)
	draft.selected = {}
	preview_build(draft, "Clear Room Furniture", -1, false, "%d existing fixtures removed" % found.size())

func clear_children(parent: Node) -> void:
	for child in parent.get_children():
		parent.remove_child(child)
		child.queue_free()
func refresh_inspector() -> void:
	clear_children(inspector)
	fill_parameters(inspector)
func fill_parameters(parent: Node) -> void:
	var s = state.selected
	if s.is_empty(): hint(parent,"Select a component to view its properties."); return
	styled(label(parent,str(s.kind).capitalize()),"TitleLabel")
	if s.kind in ["wall","wallNode"]:
		var wall = state.data.walls[s.wallIndex]
		text_field(parent,"Name",wall.name,func(v): set_build_field(["walls",s.wallIndex,"name"],v))
		choice(parent,"Wall Finish",STYLES,wall.get("style","classical"),func(v): set_build_field(["walls",s.wallIndex,"style"],v))
		for key in ["height","thickness"]:
			number(parent,"Wall Height" if key=="height" else "Wall Thickness",wall[key],func(v): set_build_field(["walls",s.wallIndex,key],v),0.1 if key=="height" else 0.02,0.05)
		number(parent,"Wall Elevation Y",wall.get("baseY",0),func(v): edit_build(func(draft): draft.set_wall_y(draft.data.walls[s.wallIndex],v), true))
		check(parent,"Decorative Columns",wall.get("hasPillars",true),func(v): set_build_field(["walls",s.wallIndex,"hasPillars"],v))
		var indices = [s.ptIndex] if s.kind=="wallNode" else range(wall.points.size()-(1 if wall.closed else 0))
		for index in indices:
			section(parent,"NODE #"+str(index+1))
			for axis in range(3):
				number(parent,["X","Y","Z"][axis],wall.points[index][axis],func(v): edit_build(func(draft): draft.set_node(draft.data.walls[s.wallIndex],index,axis,v)))
	elif s.kind=="opening":
		var wall = state.data.walls[s.wallIndex]
		var op = wall.openings[s.opIndex]
		choice(parent,"Opening Type",OPENINGS,op.type,func(v): set_build_field(["walls",s.wallIndex,"openings",s.opIndex,"type"],v))
		for spec in [["segment","Wall Segment (Starts at 0)"],["center","Distance Along Wall"],["width","Opening Width"],["height","Opening Height"],["bottom","Height Above Floor"],["rise","Arch Rise"]]:
			var key = spec[0]
			number(parent,spec[1],op.get(key,0.4),func(v): set_build_field(["walls",s.wallIndex,"openings",s.opIndex,key],int(v) if key=="segment" else v),1 if key=="segment" else 0.1,0,wall.points.size()-2 if key=="segment" else 10000,1.0 if key=="segment" else 0.001)
	elif s.kind in ["floorPoly","floorNode"]:
		var layer = state.data.layers[s.layerIndex]
		text_field(parent,"Floor Name",layer.name,func(v): set_build_field(["layers",s.layerIndex,"name"],v))
		number(parent,"Floor Elevation",layer.y,func(v): set_build_field(["layers",s.layerIndex,"y"],v))
		choice(parent,"Floor Finish",FLOOR_STYLES,layer.style,func(v): set_build_field(["layers",s.layerIndex,"style"],v))
		if s.kind=="floorNode":
			var pt = layer.roomFaces[s.polyIndex].nodes[s.ptIndex] if layer.has("roomFaces") else layer.polygons[s.polyIndex][s.ptIndex]
			for axis in range(2): number(parent,["X","Z"][axis],pt[axis],func(v):
				edit_build(func(draft):
					var floor: Dictionary = draft.data.layers[s.layerIndex]
					if s.polyIndex >= floor.polygons.size(): return
					var nodes: Array = floor.roomFaces[s.polyIndex].nodes if floor.get("roomFaces", []).size() > s.polyIndex else floor.polygons[s.polyIndex]
					if s.ptIndex >= nodes.size(): return
					var current: Array = nodes[s.ptIndex]
					draft.move_room_node(s.layerIndex,s.polyIndex,s.ptIndex,v if axis==0 else current[0],v if axis==1 else current[1])))
	elif s.kind in ["railing","railingNode"]:
		var rail = state.data.railings[s.railIndex]
		number(parent,"Railing Height",rail.height,func(v): set_build_field(["railings",s.railIndex,"height"],v),0.1,0.12)
		number(parent,"Post Spacing",rail.get("spacing",0.18),func(v): set_build_field(["railings",s.railIndex,"spacing"],v),0.02,0.02)
		if s.kind=="railingNode":
			for axis in range(3): number(parent,["X","Y","Z"][axis],rail.points[s.ptIndex][axis],func(v): set_build_field(["railings",s.railIndex,"points",s.ptIndex,axis],v))
	elif s.kind in ["stair","prop"]:
		var collection := "stairs" if s.kind=="stair" else "props"
		var item = state.data[collection][s.index]
		text_field(parent,"Name",item.get("name",item.id),func(v): set_build_field([collection,s.index,"name"],v))
		for key in (["x","y","z","yaw","rise","run","risers","width","nosing"] if s.kind=="stair" else ["x","y","z","yaw"]):
			number(parent,key,item.get(key,0),func(v): set_build_field([collection,s.index,key],v),1 if key=="risers" else 0.1,1 if key=="risers" else -10000,10000,1.0 if key=="risers" else 0.001)
		if s.kind=="prop":
			if conflicts.has(s.index): label(parent,"⚠ Overlaps Other Furniture" if conflicts[s.index]=="overlap" else "⚠ Outside the Room")
			var mount_field = Footprint.MOUNT_FIELD.get(str(item.kind),"")
			for field in prop_presets.get(item.kind,{"fields":[]}).fields:
				number(parent,field.label,item.params.get(field.id,field.val),func(v):
					edit_build(func(draft):
						var piece: Dictionary = draft.data.props[s.index]
						piece.params[field.id] = v
						if field.id==mount_field: piece.y = v),field.step)
			if item.kind=="native_recipe":
				var defaults = {}
				for entry in catalog.items:
					if entry.path==item.get("path",""): defaults = Components.parameter_defaults(entry); break
				for key in defaults:
					var value = item.params.get(key,defaults[key])
					if value is float or value is int:
						number(parent,str(key),value,func(v): set_build_field([collection,s.index,"params",key],v),0.1)
					elif value is bool:
						check(parent,str(key),value,func(v): set_build_field([collection,s.index,"params",key],v))
		if s.kind=="stair": choice(parent,"Handrail",{"both":"Both Sides","left":"Left","right":"Right","none":"None"},item.get("railingPos","both"),func(v): set_build_field([collection,s.index,"railingPos"],v))
func show_parameters() -> void:
	if state.selected.is_empty(): return
	if is_instance_valid(modal): modal.queue_free()
	modal = Window.new()
	modal.transient = true
	modal.exclusive = true
	modal.title = "Component Properties"
	modal.size = Vector2i(420,620)
	modal.close_requested.connect(func(): modal.queue_free())
	add_child(modal)
	var scroll = ScrollContainer.new()
	scroll.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var modal_bg = ColorRect.new()
	modal_bg.color = ToolTheme.PANEL
	modal_bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	modal.add_child(modal_bg)
	scroll.offset_left = 12; scroll.offset_top = 12; scroll.offset_right = -12; scroll.offset_bottom = -12
	modal.add_child(scroll)
	var column = VBoxContainer.new()
	column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(column)
	fill_parameters(column)
	button(column,"Close",func(): modal.queue_free())
	modal.popup_centered()
func load_build(text: String) -> bool:
	if pending_build != null or gesture_build != null: return false
	var draft: RefCounted = state.fork_candidate()
	if not draft.restore(text): return false
	hidden_parts.clear()
	if not commit_edit(draft, true): return false
	reset_views()
	return true

func open_file(action: String) -> void:
	if pending_build != null or gesture_build != null: return
	file_action = action
	file_dialog.file_mode = FileDialog.FILE_MODE_OPEN_FILE if action=="import" else FileDialog.FILE_MODE_SAVE_FILE
	file_dialog.filters = PackedStringArray(["*.tscn ; Godot Scene"] if action=="scene" else (["*.yaml ; ArchBuilder YAML"] if action=="yaml" else ["*.json,*.yaml,*.yml ; ArchBuilder JSON / YAML"]))
	file_dialog.current_dir = ProjectSettings.globalize_path("res://tools/building_construction/candidates")
	file_dialog.current_file = "BuildingCandidate.tscn" if action=="scene" else ("BuildingCandidate.yaml" if action=="yaml" else "BuildingCandidate.json")
	file_dialog.popup_centered(Vector2i(850,600))
func _file_selected(path: String) -> void:
	if pending_build != null or gesture_build != null: return
	if file_action=="import":
		if not load_build(FileAccess.get_file_as_string(path)): status.text = "Invalid JSON or YAML scene."
	elif file_action in ["json","yaml"]:
		var file = FileAccess.open(path,FileAccess.WRITE)
		if file: file.store_string(preload("ArchitectYaml.gd").dump(state.data)+"\n" if file_action=="yaml" else JSON.stringify(state.data,"  ")); status.text = "Saved: "+path
	else:
		# A scalar command might have committed since the last deferred mesh rebuild.
		rebuild_pending = false
		rebuild()
		var copy = candidates.duplicate()
		copy.visible = true
		for node in copy.find_children("*","Node3D",true,false): node.visible = true
		var script = GDScript.new()
		script.source_code = "extends Node3D\n@export var authored_scene: Dictionary = {}\n"
		var error = script.reload()
		if error==OK: error = ResourceSaver.save(script,path.get_basename()+".gd")
		copy.set_script(script)
		copy.set("authored_scene",state.data.duplicate(true))
		for child in copy.find_children("*","",true,false): child.owner = copy
		var packed = PackedScene.new()
		if error==OK: error = packed.pack(copy)
		if error==OK: error = ResourceSaver.save(packed,path)
		copy.free()
		status.text = "Exported preview: "+path if error==OK else "Export failed: "+error_string(error)
func clear_dialog() -> void:
	var dialog = ConfirmationDialog.new()
	dialog.dialog_text = "Clear this scene? You can undo this change."
	add_child(dialog)
	dialog.confirmed.connect(func():
		set_tool("select")
		edit_build(func(draft):
			draft.data = {"activeLayerId":null,"layers":[],"walls":[],"stairs":[],"railings":[],"props":[]}
			draft.selected = {}
			draft.new_layer(), true)
		dialog.queue_free())
	dialog.canceled.connect(func(): dialog.queue_free())
	dialog.popup_centered()
func _on_blueprint_resized() -> void:
	if blueprint != null and blueprint.size.x > 200.0 and blueprint.size.y > 200.0:
		reset_views()


func reset_views(fit_plan := false) -> void:
	var shown := display_state()
	var min_x = INF
	var max_x = -INF
	var min_z = INF
	var max_z = -INF
	var max_y = 3.6
	for layer in shown.data.layers:
		for poly in layer.polygons:
			for pt in poly:
				min_x = min(min_x,pt[0]); max_x = max(max_x,pt[0])
				min_z = min(min_z,pt[1]); max_z = max(max_z,pt[1])
	for wall in shown.data.walls:
		max_y = max(max_y,wall.get("baseY",0)+wall.get("height",3.6))
		for pt in wall.points:
			min_x = min(min_x,pt[0]); max_x = max(max_x,pt[0])
			min_z = min(min_z,pt[2]); max_z = max(max_z,pt[2])
	for prop in shown.data.props:
		min_x = min(min_x,prop.x-0.5); max_x = max(max_x,prop.x+0.5)
		min_z = min(min_z,prop.z-0.5); max_z = max(max_z,prop.z+0.5)
	if not is_finite(min_x): min_x = -4.0; max_x = 4.0; min_z = -7.0; max_z = 0.0; max_y = 3.6
	var cx = (min_x+max_x)*0.5
	var cz = (min_z+max_z)*0.5
	blueprint.zoom = maxf(16,minf(58,minf(blueprint.size.x*0.75/maxf(0.1,max_x-min_x+2),blueprint.size.y*0.75/maxf(0.1,max_z-min_z+2))))
	blueprint.pan = blueprint.size*0.5-Vector2(cx,cz)*blueprint.zoom
	var span = maxf(maxf(max_x-min_x,max_z-min_z),7)
	var target_y = minf(4,max_y*0.4)
	var dist = maxf(span*1.05,10)
	target = Vector3(cx,target_y,cz)
	var delta = Vector3(dist*0.85,dist*0.72-target_y,dist*0.95)
	distance = delta.length()
	orbit = Vector2(atan2(delta.x,delta.z),asin(delta.y/distance))
	if fit_plan:
		var aspect := float(viewport3.size.x) / maxf(float(viewport3.size.y),1.0)
		var half_vertical := deg_to_rad(camera.fov * 0.5)
		var half_fit := minf(half_vertical, atan(tan(half_vertical) * aspect))
		var radius := Vector3((max_x-min_x)*0.5,maxf(target_y,max_y-target_y),(max_z-min_z)*0.5).length()
		distance = maxf(distance, radius * 1.12 / sin(maxf(half_fit,0.05)))
	_update_camera()
func _update_camera() -> void:
	camera.position = target+Vector3(sin(orbit.x)*cos(orbit.y),sin(orbit.y),cos(orbit.x)*cos(orbit.y))*distance
	camera.look_at(target)
	if auto_cutaway and candidates != null: apply_visibility()
func _camera_input(event: InputEvent) -> void:
	if has_node("StructureLab"): return
	if event is InputEventMouseMotion:
		if event.button_mask&MOUSE_BUTTON_MASK_RIGHT:
			if event.shift_pressed: target += Vector3(-event.relative.x,0,-event.relative.y)*distance*0.002
			else: orbit += Vector2(-event.relative.x,event.relative.y)*0.006; orbit.y = clampf(orbit.y,0.05,1.5)
			_update_camera()
	elif event is InputEventMouseButton and event.pressed:
		if event.button_index==MOUSE_BUTTON_WHEEL_UP: distance = maxf(2,distance*0.9)
		elif event.button_index==MOUSE_BUTTON_WHEEL_DOWN: distance = minf(300,distance*1.1)
		_update_camera()
func nudge_selected(delta: Vector2) -> void:
	var sel: Dictionary = state.selected
	if sel.get("kind", "") not in ["prop", "stair"]: return
	if edit_build(func(draft):
		var item: Dictionary = draft.data.props[sel.index] if sel.kind == "prop" else draft.data.stairs[sel.index]
		item.x = Geo.js_round((item.x + delta.x) * 100) / 100
		item.z = Geo.js_round((item.z + delta.y) * 100) / 100):
		refresh_inspector()

func duplicate_selected() -> void:
	var sel: Dictionary = state.selected
	if sel.get("kind", "") not in ["prop", "stair"]: return
	edit_build(func(draft):
		var collection: Array = draft.data.props if sel.kind == "prop" else draft.data.stairs
		var copy: Dictionary = collection[sel.index].duplicate(true)
		copy.id = draft.uid("prop" if sel.kind == "prop" else "st")
		copy.x += 0.4
		copy.z += 0.4
		collection.append(copy)
		draft.selected = {"kind": sel.kind, "index": collection.size() - 1}, true)

func rotate_selected() -> void:
	var sel: Dictionary = state.selected
	if sel.get("kind", "") not in ["prop", "stair"]: return
	edit_build(func(draft):
		var item: Dictionary = draft.data.props[sel.index] if sel.kind == "prop" else draft.data.stairs[sel.index]
		item.yaw = fposmod(item.get("yaw", 0) + (45 if sel.kind == "prop" else 90), 360), true)

func _unhandled_key_input(event: InputEvent) -> void:
	if has_node("StructureLab"): return
	if pending_build != null: return
	if not event is InputEventKey or not event.pressed: return
	if gesture_build != null:
		if event.keycode == KEY_ESCAPE: blueprint.end_drag(false)
		return
	if get_viewport().gui_get_focus_owner() is LineEdit: return
	var command = event.is_command_or_control_pressed()
	var step = 1.0 if event.shift_pressed else 0.1
	if event.keycode in [KEY_LEFT,KEY_RIGHT,KEY_UP,KEY_DOWN]:
		nudge_selected(Vector2(float(event.keycode==KEY_RIGHT)-float(event.keycode==KEY_LEFT),float(event.keycode==KEY_DOWN)-float(event.keycode==KEY_UP))*step)
		return
	if event.echo: return
	match event.keycode:
		KEY_DELETE,KEY_BACKSPACE: delete_selected()
		KEY_ESCAPE:
			if drawing.is_empty(): state.selected = {}
			set_tool("select")
			refresh_inspector()
		KEY_ENTER: finish_path(tool!="railing")
		KEY_E: show_parameters()
		KEY_F: reset_views()
		KEY_V: set_tool("select")
		KEY_W: if not command: set_tool("wall")
		KEY_O: set_tool("opening")
		KEY_P: set_tool("prop")
		KEY_D: if command: duplicate_selected()
		KEY_Z:
			if command and state.undo(1 if event.shift_pressed else -1): refresh()
		KEY_Y:
			if command and state.undo(1): refresh()
		KEY_R: rotate_selected()
