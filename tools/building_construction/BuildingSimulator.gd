extends Control
## Native Godot host for the original Web ArchBuilder wall workflow.
const State = preload("ArchitectState.gd")
const Components = preload("BuildingConstruction/Shared/ComponentFactory.gd")
const Geo = preload("BuildingConstruction/Shared/ArchitectGeometry.gd")
const Wall = preload("BuildingConstruction/Walls/WallPathGeometry.gd")
const Floor = preload("BuildingConstruction/Floors/ArchitectFloor.gd")
const Stair = preload("BuildingConstruction/Stairs/ArchitectStair.gd")
const Railing = preload("BuildingConstruction/Railings/ArchitectRailing.gd")
const WebProps = preload("BuildingConstruction/Props/ArchitectProps.gd")
const Footprint = preload("BuildingConstruction/Props/PropFootprint.gd")
const Furnish = preload("AutoFurnish.gd")
const RoomLibrary = preload("res://scenes/components/world/RoomLibrary.gd")
const SANS_FONT := preload("res://assets/external/NotoSansSC/NotoSansSC[wght].ttf")
const STYLES = {"classical":"古典护墙板（踢脚＋腰线＋顶线）","dado":"半高木护墙","stone":"原石砌块墙","plain":"素面粉刷墙"}
const OPENINGS = {"arched_window":"半圆拱窗","rectangular_window":"矩形多格窗","round_window":"圆形牛眼窗","double_door":"双开实木大门","closed_door":"单开平顶木门","arched_closed_door":"单开拱顶木门","portal_arch":"敞开式拱形门洞"}
const FLOOR_STYLES = {"octagonal_tile":"八角拼花砖","parquet_wood":"胡桃木拼花","stone_slab":"原石大板","plain_grout":"素面灰石"}
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
var art_room: Node3D

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
	if room>=0: text += "   ·   房间 %d（%.1f m²）" % [room+1,state.layer().roomFaces[room].get("area",0.0)]
	text += "   ·   吸附 %s" % ("自由" if state.grid_snap<=0 else "%.2f m" % state.grid_snap)
	cursor_label.text = text

func _ready() -> void:
	get_viewport().gui_embed_subwindows = true
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://tools/building_construction/candidates"))
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	state.new_layer()
	state.remember()
	rooms = JSON.parse_string(FileAccess.get_file_as_string("res://tools/building_construction/architect_rooms.json"))
	for room in rooms:
		if room.id=="R01": state.restore(JSON.stringify(room)); state.remember(); break
	catalog = JSON.parse_string(FileAccess.get_file_as_string("res://tools/building_construction/catalog.json"))
	prop_presets = JSON.parse_string(FileAccess.get_file_as_string("res://tools/building_construction/architect_prop_presets.json"))
	_make_ui()
	refresh()
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
func number(parent: Node, text: String, value: float, callback: Callable, step := 0.1, minimum := -10000.0, maximum := 10000.0) -> SpinBox:
	var row = HBoxContainer.new()
	parent.add_child(row)
	var caption = label(row,text)
	caption.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var item = SpinBox.new()
	item.min_value = minimum
	item.max_value = maximum
	# HTML number inputs retain arbitrary source values; step only affects arrows.
	item.step = 0.0
	item.custom_arrow_step = step
	item.value = value
	item.custom_minimum_size.x = 125
	row.add_child(item)
	item.value_changed.connect(callback)
	return item
func choice(parent: Node, text: String, options: Dictionary, current: String, callback: Callable) -> OptionButton:
	label(parent,text)
	var item = OptionButton.new()
	parent.add_child(item)
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
	label(parent,title)
	var edit = LineEdit.new()
	edit.text = value
	parent.add_child(edit)
	edit.text_submitted.connect(callback)
	edit.focus_exited.connect(func(): callback.call(edit.text))
func page(tabs: TabContainer, title: String) -> VBoxContainer:
	var scroll = ScrollContainer.new()
	scroll.name = title
	tabs.add_child(scroll)
	var column = VBoxContainer.new()
	column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	column.add_theme_constant_override("separation",8)
	scroll.add_child(column)
	return column

func _make_ui() -> void:
	var theme = Theme.new()
	# 编辑器原先用 Godot 内置字体 14px：中文细、糊、按钮文字溢出。改用项目自带的 NotoSansSC 16px。
	theme.default_font = SANS_FONT
	theme.default_font_size = 16
	theme.set_font_size("font_size", "Button", 15)
	theme.set_font_size("font_size", "TabContainer", 15)
	self.theme = theme
	var root = VBoxContainer.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(root)
	var header = HBoxContainer.new()
	root.add_child(header)
	label(header,"ArchBuilder · 建筑构建器")
	button(header,"双联视口",func(): blueprint.show(); view3.show())
	button(header,"仅 2D",func(): blueprint.show(); view3.hide())
	button(header,"仅 3D",func(): blueprint.hide(); view3.show())
	header.add_child(VSeparator.new())
	button(header,"撤销",func(): if state.undo(-1): refresh(),"Ctrl+Z")
	button(header,"重做",func(): if state.undo(1): refresh(),"Ctrl+Shift+Z / Ctrl+Y")
	header.add_child(VSeparator.new())
	# 文件操作收进菜单：顶栏只留常用按钮，避免 20 个按钮挤一行（实机截图问题）。
	var file_menu = MenuButton.new()
	file_menu.text = "文件 ▾"
	file_menu.tooltip_text = "导入 / 保存 / 导出（JSON、YAML、Godot 场景）"
	var fmp = file_menu.get_popup()
	fmp.add_item("导入 JSON／YAML…", 0)
	fmp.add_item("保存 JSON…", 1)
	fmp.add_item("保存 YAML…", 2)
	fmp.add_item("导出 Godot 场景…", 3)
	fmp.add_separator()
	fmp.add_item("清空场景（可撤销）", 4)
	fmp.id_pressed.connect(func(id: int):
		if id == 0: open_file("import")
		elif id == 1: open_file("json")
		elif id == 2: open_file("yaml")
		elif id == 3: open_file("scene")
		elif id == 4: clear_dialog())
	header.add_child(file_menu)
	button(header,"角色模型",func():
		var gallery = preload("res://tools/characters/CharacterGallery.tscn").instantiate()
		add_child(gallery))
	button(header,"生活模拟",func():
		state.sync_rooms()
		var main = get_tree().current_scene
		if main.has_method("open_life"): main.open_life(state.data.duplicate(true))
		else:
			var preview = preload("res://scenes/main/Main.tscn").instantiate()
			add_child(preview)
			preview.open_life(state.data.duplicate(true)))
	var body = HBoxContainer.new()
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_child(body)
	var center = VBoxContainer.new()
	center.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.add_child(center)
	var actions = HBoxContainer.new()
	center.add_child(actions)
	for spec in [["select","选择 V"],["wall","绘墙 W"],["floor","地板"],["opening","门窗 O"],["railing","栏杆"],["prop","家具 P"]]:
		var tool_button = Button.new()
		tool_button.text = spec[1]
		tool_button.toggle_mode = true
		tool_button.button_pressed = spec[0]=="select"
		tool_button.tooltip_text = "Esc 回到选择工具"
		tool_button.pressed.connect(func(): set_tool(spec[0]))
		actions.add_child(tool_button)
		tool_buttons[spec[0]] = tool_button
	actions.add_child(VSeparator.new())
	choice(actions,"吸附",{"0":"自由","0.1":"0.10m","0.2":"0.20m","0.5":"0.50m","1":"1m"},"0.2",func(v): state.grid_snap = float(v))
	button(actions,"居中 (F)",reset_views,"把当前建筑移到画面中央")
	var view_menu = MenuButton.new()
	view_menu.text = "视图 ▾"
	view_menu.tooltip_text = "线框 / 完成闭合 / 开放折线 / 显示隐藏"
	var vmp = view_menu.get_popup()
	vmp.add_item("线框开关", 0)
	vmp.add_item("完成／闭合当前折线", 1)
	vmp.add_item("开放折线（保留开口）", 2)
	vmp.add_item("显示／隐藏构件…", 3)
	vmp.add_item("剖面：隐藏朝相机墙（开）", 4)
	vmp.id_pressed.connect(func(id: int):
		if id == 0: wireframe = not wireframe; update_wireframe()
		elif id == 1: finish_path(tool!="railing")
		elif id == 2: finish_path(false)
		elif id == 3: show_visibility()
		elif id == 4:
			auto_cutaway = not auto_cutaway
			vmp.set_item_text(4, "剖面：隐藏朝相机墙（%s）" % ("开" if auto_cutaway else "关"))
			apply_visibility())
	actions.add_child(view_menu)
	cursor_label = label(actions,"")
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
	var side = VBoxContainer.new()
	side.custom_minimum_size.x = 350
	body.add_child(side)
	var tabs = TabContainer.new()
	tabs.custom_minimum_size.y = 410
	tabs.size_flags_vertical = Control.SIZE_EXPAND_FILL
	side.add_child(tabs)
	var floors = page(tabs,"地面")
	layer_select = OptionButton.new()
	floors.add_child(layer_select)
	layer_select.item_selected.connect(func(index):
		state.data.activeLayerId = layer_select.get_item_metadata(index)
		if auto_y: sync_wall("baseY",state.layer().y)
		refresh_layers())
	button(floors,"新增楼层",func(): state.new_layer(); state.remember(); refresh_layers())
	ui_fields.layer_y = number(floors,"楼层高度 (m)",0,func(v):
		state.layer().y = v
		if auto_y: sync_wall("baseY",v)
		commit())
	ui_fields.floor_style = choice(floors,"地板铺装",FLOOR_STYLES,"octagonal_tile",func(v): state.layer().style = v; commit())
	button(floors,"在 2D 放线绘制地板",func(): set_tool("floor"))
	label(floors,"高度相差 ≤0.3m 的地板会自动合并，不会重叠")
	var walls = page(tabs,"墙体")
	check(walls,"自动跟随图层标高",true,func(v): auto_y = v; if v: sync_wall("baseY",state.layer().get("y",0)))
	choice(walls,"立面风格",STYLES,"classical",func(v): wall_params.style = v)
	for spec in [["height","墙高 (m)",0.1],["thickness","墙厚 (m)",0.02],["baseY","起始高度 (m)",0.1]]:
		var key = spec[0]
		ui_fields[key] = number(walls,spec[1],wall_params[key],func(v): sync_wall(key,v),spec[2])
	label(walls,"墙两侧自动贴合房间；端点与交点共用节点")
	check(walls,"转角与端点生成独立装饰立柱",true,func(v): wall_params.hasPillars = v)
	button(walls,"在 2D 手动放线绘墙",func(): set_tool("wall"))
	button(walls,"闭合墙环",func(): finish_path(true))
	button(walls,"开放墙体折线",func(): finish_path(false))
	button(walls,"沿地板边界生成贴合墙体",func():
		if state.auto_walls(wall_params): refresh()
		else: status.text = "请先绘制地板；已有墙网房间请直接编辑墙体")
	var openings = page(tabs,"门窗")
	choice(openings,"构件样式",OPENINGS,opening_params.type,func(v):
		opening_params.type = v
		opening_params.bottom = 0.85 if "window" in v else 0.0
		ui_fields.op_bottom.set_value_no_signal(opening_params.bottom)
		ui_fields.op_rise.get_parent().visible = "arched" in v)
	for spec in [["width","洞宽 (m)"],["height","洞高 (m)"],["bottom","离地高 (m)"],["rise","拱高 (m)"]]:
		var key = spec[0]
		ui_fields["op_"+key] = number(openings,spec[1],opening_params[key],func(v): opening_params[key] = v)
	button(openings,"点击墙段安装门窗",func(): set_tool("opening"))
	var stairs = page(tabs,"梯栏")
	for key in ["rise","run","risers","width","yaw"]:
		number(stairs,{"rise":"总高","run":"水平总长","risers":"踏步数","width":"梯宽","yaw":"朝向角度"}[key],stair_params[key],func(v): stair_params[key] = v,1 if key=="risers" else 0.1,1 if key=="risers" else 0.01)
	choice(stairs,"楼梯扶手",{"both":"双侧","left":"左侧","right":"右侧","none":"无"},"both",func(v): stair_params.railingPos = v)
	button(stairs,"放置直跑楼梯",spawn_stair)
	number(stairs,"独立栏杆高度",0.9,func(v): rail_params.height = v)
	number(stairs,"栏杆立杆间距",0.18,func(v): rail_params.spacing = v,0.02,0.02)
	button(stairs,"在 2D 放线绘制栏杆",func(): set_tool("railing"))
	var props = page(tabs,"陈设")
	choice(props,"原版家具／灯具",prop_names(),web_prop_kind,func(v): web_prop_kind = v; refresh_prop_fields())
	prop_fields = VBoxContainer.new()
	props.add_child(prop_fields)
	refresh_prop_fields()
	number(props,"位置 X",0,func(v): prop_position.x = v)
	number(props,"位置 Z",0,func(v): prop_position.y = v)
	number(props,"朝向角度",0,func(v): prop_yaw = v,15)
	button(props,"按参数放置原版家具",func(): prop_entry = {}; place_prop(prop_position))
	button(props,"在 2D 放置原版家具",func(): prop_entry = {}; set_tool("prop"))
	label(props,"原生组件库（可搜索）")
	var filter = LineEdit.new()
	filter.placeholder_text = "搜索组件…"
	filter.clear_button_enabled = true
	filter.text_changed.connect(func(text): component_filter = text; refresh_component_list())
	props.add_child(filter)
	component_list = ItemList.new()
	component_list.custom_minimum_size.y = 150
	component_list.item_selected.connect(func(index):
		prop_entry = component_list.get_item_metadata(index)
		prop_params = prop_entry.get("defaults",{}).duplicate(true))
	props.add_child(component_list)
	refresh_component_list()
	# Original web furniture remains the default selection.
	button(props,"在 2D 点选放置组件",func(): set_tool("prop"))
	button(props,"打开组件库",func(): get_tree().change_scene_to_file("res://tools/building_construction/ComponentLibrary.tscn"))
	var furnish_page = page(tabs,"自动布置")
	var furnish_help = label(furnish_page,"按房间类型沿墙摆放家具：背靠墙面、避开门洞、互不重叠，全部在范围内，可 Ctrl+Z 撤销。")
	furnish_help.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	furnish_help.custom_minimum_size.x = 300
	choice(furnish_page,"房间类型",Furnish.template_names(),furnish_template,func(v): furnish_template = v)
	label(furnish_page,"目标房间（由墙体围合）")
	furnish_room = OptionButton.new()
	furnish_page.add_child(furnish_room)
	furnish_clear = check(furnish_page,"先清除该房间内现有家具",true,func(_v): pass)
	button(furnish_page,"布置所选房间",func(): furnish_rooms([furnish_room.selected]))
	button(furnish_page,"布置当前图层全部房间",func(): furnish_rooms(range(furnish_room.item_count)))
	button(furnish_page,"清除所选房间内的家具",clear_room_props)
	furnish_report = label(furnish_page,"")
	furnish_report.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	furnish_report.custom_minimum_size.x = 300
	var presets = page(tabs,"房间")
	label(presets,"已导入旧编辑器的 %d 个房间（含家具）" % rooms.size())
	var room_select = OptionButton.new()
	room_select.custom_minimum_size.x = 260
	room_select.clip_text = true
	presets.add_child(room_select)
	for room in rooms: room_select.add_item(str(room.id)+" · "+str(room.name))
	if rooms.size()>1: room_select.select(1)
	button(presets,"载入已设计房间",func():
		if state.restore(JSON.stringify(rooms[room_select.selected])):
			hidden_parts.clear()
			state.remember()
			refresh()
			reset_views())
	label(presets,"原版房间美术（保留碰撞与交互槽）")
	var art_select := OptionButton.new()
	presets.add_child(art_select)
	for identity in RoomLibrary.rooms(): art_select.add_item(identity)
	button(presets,"查看原版房间",func(): show_art_room(art_select.get_item_text(art_select.selected)))
	button(presets,"返回参数化建筑",clear_art_room)
	outline = ItemList.new()
	outline.custom_minimum_size.y = 125
	side.add_child(outline)
	outline.item_selected.connect(func(index): state.selected = outline.get_item_metadata(index).duplicate(); refresh_inspector())
	var edit_actions = HBoxContainer.new()
	side.add_child(edit_actions)
	button(edit_actions,"独立参数窗口（E）",show_parameters)
	button(edit_actions,"删除",delete_selected)
	var scroll = ScrollContainer.new()
	scroll.custom_minimum_size.y = 220
	side.add_child(scroll)
	inspector = VBoxContainer.new()
	inspector.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(inspector)
	status = label(root,"")
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
	tool = value
	drawing = []
	for key in tool_buttons: tool_buttons[key].set_pressed_no_signal(key==tool)
	if tool=="wall" and auto_y: sync_wall("baseY",state.layer().get("y",0))
	update_status()
func update_status() -> void:
	status.text = {"select":"选择：左键点选/拖拽 · 双击节点或按 E 编辑 · Delete 删除 · Ctrl+Z 撤销 · F 居中", "wall":"绘墙：依次点击节点；点击起点或 Enter 闭合；开放折线按钮保留开口", "floor":"绘地板：依次点击顶点，点击起点或 Enter 完成", "opening":"安装门窗：点击已有墙段；选择模式下可沿墙拖动", "railing":"绘栏杆：依次点击节点，Enter 完成", "prop":"在 2D 点击放置当前组件"}.get(tool,tool)+"  |  节点："+str(drawing.size())
func finish_path(close: bool) -> void:
	if drawing.size()<2: return
	var active = state.layer()
	if tool=="floor":
		if drawing.size()>=3:
			var points = []
			for p in drawing: points.append([p[0],p[1]])
			state.add_floor(points)
	elif tool=="wall":
		var points = []
		for p in drawing: points.append([p[0],p[2],p[1]])
		var closed = close and drawing.size()>=3
		if closed: points.append(points[0].duplicate())
		var wall = wall_params.duplicate(true)
		wall.merge({"id":state.uid("wall"),"name":"墙体 #"+str(state.data.walls.size()+1),"points":points,"closed":closed,"openings":[]},true)
		state.data.walls.append(wall)
	elif tool=="railing":
		var points = []
		for p in drawing: points.append([p[0],active.get("y",0),p[1]])
		var rail = rail_params.duplicate()
		rail.merge({"id":state.uid("rail"),"name":"木栏杆 #"+str(state.data.railings.size()+1),"points":points})
		state.data.railings.append(rail)
	set_tool("select")
	commit()
func insert_floor_node(point: Vector2, tolerance: float) -> void:
	for li in range(state.data.layers.size()):
		for pi in range(state.data.layers[li].polygons.size()):
			var poly = state.data.layers[li].polygons[pi]
			for i in range(poly.size()):
				var a = poly[i]
				var b = poly[(i+1)%poly.size()]
				var hit = state.project(point,Vector2(a[0],a[1]),Vector2(b[0],b[1]))
				if hit.dist<=tolerance:
					poly.insert(i+1,[state.snap(hit.point.x),state.snap(hit.point.y)])
					state.selected = {"kind":"floorNode","layerIndex":li,"polyIndex":pi,"ptIndex":i+1}
					commit()
					return
func spawn_stair() -> void:
	var stair = stair_params.duplicate(true)
	stair.merge({"id":state.uid("st"),"name":"直跑梯 #"+str(state.data.stairs.size()+1),"x":1.2,"y":state.layer().get("y",0),"z":1.2,"nosing":0.03})
	state.data.stairs.append(stair)
	state.selected = {"kind":"stair","index":state.data.stairs.size()-1}
	commit()
func refresh_component_list() -> void:
	component_list.clear()
	for entry in catalog.items:
		if not entry.get("recipe",false) and not str(entry.path).get_file().begins_with("Recipe"): continue
		var title = str(entry.label)
		if component_filter!="" and not (title+" "+str(entry.id)).containsn(component_filter): continue
		component_list.add_item(title)
		component_list.set_item_metadata(component_list.item_count-1,entry)

## Push a wall-hugging or wall-mounted piece flush against the nearest wall face.
func snap_prop(item: Dictionary, point: Vector2) -> void:
	if str(item.get("kind",""))=="native_recipe": return
	var f = Footprint.info(item)
	var wants = f.mount==Footprint.WALL or str(item.kind) in Footprint.AGAINST_WALL
	if not wants: return
	var reach = 0.45 if f.mount==Footprint.WALL else f.d*0.5+0.4
	var hit = state.wall_snap(point,reach,float(state.layer().get("y",0)))
	if hit.is_empty(): return
	Footprint.against_wall(item,hit.point,hit.normal,hit.half)

func place_prop(point: Vector2) -> void:
	var layer_y = float(state.layer().get("y",0))
	var item: Dictionary
	if prop_entry.is_empty():
		item = {"id":state.uid("prop"),"name":prop_presets[web_prop_kind].name,"kind":web_prop_kind,"x":state.snap(point.x),"y":layer_y,"z":state.snap(point.y),"yaw":prop_yaw,"params":prop_params.duplicate(true)}
		# Hanging heights are preset offsets above the active floor (the stored value is absolute, like the room data).
		var mount_field = Footprint.MOUNT_FIELD.get(web_prop_kind,"")
		if mount_field!="" and prop_params.has(mount_field):
			item.y = Geo.js_round((layer_y+float(prop_params[mount_field]))*100)/100
			item.params[mount_field] = item.y
		if not Input.is_key_pressed(KEY_ALT): snap_prop(item,point)
	else:
		item = {"id":state.uid("prop"),"name":prop_entry.label,"kind":"native_recipe","path":prop_entry.path,"x":state.snap(point.x),"y":layer_y,"z":state.snap(point.y),"yaw":prop_yaw,"params":prop_params.duplicate(true)}
	state.data.props.append(item)
	state.selected = {"kind":"prop","index":state.data.props.size()-1}
	commit()

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
func commit() -> void:
	state.remember()
	refresh()
## Scalar edits: keep the inspector (and its keyboard focus) alive, rebuild only the 3D parts that changed.
func commit_light() -> void:
	state.remember()
	conflicts = state.prop_conflicts()
	request_rebuild()
	refresh_layers()
	refresh_outline()
	update_status()
func delete_selected() -> void:
	state.delete_selected()
	refresh()
func refresh() -> void:
	clear_art_room()
	conflicts = state.prop_conflicts()
	rebuild()
	refresh_layers()
	refresh_outline()
	refresh_inspector()
	update_status()

func clear_art_room() -> void:
	if is_instance_valid(art_room):
		art_room.get_parent().remove_child(art_room)
		art_room.queue_free()
	art_room = null
	if is_instance_valid(candidates): candidates.show()

func show_art_room(identity: String) -> void:
	var replacement := RoomLibrary.instantiate(identity)
	if replacement == null:
		status.text = "房间载入失败：" + identity
		return
	clear_art_room()
	art_room = replacement
	candidates.get_parent().add_child(art_room)
	candidates.hide()
	wire_mesh.hide()
	var bounds := AABB()
	var initialized := false
	for mesh: MeshInstance3D in art_room.find_children("*", "MeshInstance3D", true, false):
		var box: AABB = mesh.global_transform * mesh.get_aabb()
		bounds = bounds.merge(box) if initialized else box
		initialized = true
	if initialized:
		target = bounds.get_center()
		distance = maxf(bounds.size.length(), 8.0)
		_update_camera()
	status.text = "原版房间 " + identity + " · %d 个实例 · 只读美术视图；参数化建筑可继续编辑。" % art_room.get_child_count()
func rebuild() -> void:
	state.sync_rooms()
	# Only items whose data changed are rebuilt; untouched parts keep their meshes (big win while dragging).
	var used = {}
	for item in state.data.layers: sync_part("layers",item,func(i): return Floor.build(i),used)
	for item in state.data.walls: sync_part("walls",item,func(i): return Wall.build(i),used)
	for item in state.data.stairs: sync_part("stairs",item,func(i): return Stair.build(i),used)
	for item in state.data.railings: sync_part("railings",item,func(i): return Railing.build(i),used)
	for item in state.data.props: sync_part("props",item,build_prop,used)
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
		var node = Components.create(str(item.path))
		if node == null: return null
		for key in item.params: node.set(key,item.params[key])
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
	visibility_window.title = "3D 显示／隐藏"
	visibility_window.size = Vector2i(490,650)
	visibility_window.close_requested.connect(func(): visibility_window.hide())
	add_child(visibility_window)
	var scroll = ScrollContainer.new()
	scroll.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	visibility_window.add_child(scroll)
	var box = VBoxContainer.new()
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(box)
	label(box,"仅影响 3D 视图；完整结构始终保留并导出。")
	button(box,"全部显示",func(): hidden_parts.clear(); apply_visibility(); show_visibility())
	for category in {"walls":"墙体（含门窗）","layers":"地面","stairs":"楼梯","railings":"栏杆","props":"家具与灯具"}:
		visibility_check(box,{"walls":"墙体（含门窗）","layers":"地面","stairs":"楼梯","railings":"栏杆","props":"家具与灯具"}[category],category)
	for wall in state.data.walls:
		label(box,str(wall.name))
		for i in range(wall.points.size()-1):
			visibility_check(box,"墙段 %d · %s → %s" % [i+1,str(wall.points[i]),str(wall.points[i+1])],str(wall.id)+"/Segment_"+str(i))
	for spec in [["layers","地面"],["stairs","楼梯"],["railings","栏杆"],["props","家具与灯具"]]:
		label(box,spec[1])
		for item in state.data[spec[0]]: visibility_check(box,str(item.get("name",item.id)),str(item.id))
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
		layer_select.add_item(item.name+" · Y="+str(item.y))
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
			outline.add_item("房间 · "+state.data.layers[li].name+" #"+str(pi+1)+("  %.1f m²" % face.area if face.has("area") else ""))
			outline.set_item_metadata(outline.item_count-1,{"kind":"floorPoly","layerIndex":li,"polyIndex":pi})
	for spec in [["walls","wall","wallIndex"],["stairs","stair","index"],["railings","railing","railIndex"],["props","prop","index"]]:
		for i in range(state.data[spec[0]].size()):
			var item = state.data[spec[0]][i]
			outline.add_item(("⚠ " if spec[0]=="props" and conflicts.has(i) else "")+str(item.get("name",item.id)))
			outline.set_item_metadata(outline.item_count-1,{"kind":spec[1],spec[2]:i})
			if spec[0]=="walls":
				for oi in range(item.openings.size()):
					outline.add_item("  └ 门窗 · "+str(OPENINGS.get(item.openings[oi].type, item.openings[oi].type)))
					outline.set_item_metadata(outline.item_count-1,{"kind":"opening","wallIndex":i,"opIndex":oi})
func refresh_furnish_rooms() -> void:
	if furnish_room==null: return
	var keep = furnish_room.selected
	furnish_room.clear()
	var active = state.layer()
	if active.has("roomFaces"):
		for i in range(active.roomFaces.size()):
			var face = active.roomFaces[i]
			furnish_room.add_item("房间 %d · %.1f m² · 邻接 %d" % [i+1,face.get("area",0.0),face.get("neighbors",[]).size()])
	if furnish_room.item_count>0: furnish_room.select(clampi(keep,0,furnish_room.item_count-1))

func active_layer_index() -> int:
	for i in range(state.data.layers.size()):
		if state.data.layers[i].id==state.data.activeLayerId: return i
	return 0

func furnish_rooms(indices: Array) -> void:
	var layer_index = active_layer_index()
	var layer = state.data.layers[layer_index]
	if not layer.has("roomFaces") or layer.roomFaces.is_empty() or indices.is_empty() or furnish_room.item_count==0:
		furnish_report.text = "当前图层没有由墙体围成的房间。先绘制闭合墙环。"
		return
	if furnish_clear.button_pressed:
		var doomed = {}
		for ri in indices:
			for pi in state.props_in_room(layer_index,ri): doomed[pi] = true
		var order = doomed.keys()
		order.sort()
		order.reverse()
		for pi in order: state.data.props.remove_at(pi)
	var total = 0
	var failed = []
	for ri in indices:
		var existing = state.data.props.filter(func(prop): return state.prop_layer_index(prop)==layer_index)
		var added = Furnish.furnish(furnish_template,layer.roomFaces[ri],float(layer.y),state.data.walls,existing,prop_presets)
		state.data.props.append_array(added)
		total += added.size()
		if added.size()<4: failed.append(ri+1)
	state.selected = {}
	commit()
	furnish_report.text = "已布置 %d 件家具（%s）。" % [total,Furnish.TEMPLATES[furnish_template].label]+("  房间 %s 过小，只放下少量家具。" % str(failed) if not failed.is_empty() else "")

func clear_room_props() -> void:
	var layer_index = active_layer_index()
	if furnish_room.item_count==0: return
	var found = state.props_in_room(layer_index,furnish_room.selected)
	found.reverse()
	for pi in found: state.data.props.remove_at(pi)
	state.selected = {}
	commit()
	furnish_report.text = "已清除 %d 件家具。" % found.size()

func clear_children(parent: Node) -> void:
	for child in parent.get_children():
		parent.remove_child(child)
		child.queue_free()
func refresh_inspector() -> void:
	clear_children(inspector)
	fill_parameters(inspector)
func fill_parameters(parent: Node) -> void:
	var s = state.selected
	if s.is_empty(): label(parent,"选择墙体、节点或门窗查看参数"); return
	label(parent,"选中："+str(s.kind))
	if s.kind in ["wall","wallNode"]:
		var wall = state.data.walls[s.wallIndex]
		text_field(parent,"名称",wall.name,func(v): wall.name = v; commit_light())
		choice(parent,"立面风格",STYLES,wall.get("style","classical"),func(v): wall.style = v; commit_light())
		for key in ["height","thickness"]:
			number(parent,"墙高" if key=="height" else "墙厚",wall[key],func(v): wall[key] = v; commit_light(),0.1 if key=="height" else 0.02,0.05)
		number(parent,"整墙标高 Y",wall.get("baseY",0),func(v): state.set_wall_y(wall,v); commit())
		check(parent,"装饰立柱",wall.get("hasPillars",true),func(v): wall.hasPillars = v; commit_light())
		var indices = [s.ptIndex] if s.kind=="wallNode" else range(wall.points.size()-(1 if wall.closed else 0))
		for index in indices:
			label(parent,"节点 #"+str(index+1))
			for axis in range(3):
				number(parent,["X","Y","Z"][axis],wall.points[index][axis],func(v): state.set_node(wall,index,axis,v); commit_light())
	elif s.kind=="opening":
		var wall = state.data.walls[s.wallIndex]
		var op = wall.openings[s.opIndex]
		choice(parent,"门窗类型",OPENINGS,op.type,func(v): op.type = v; commit_light())
		for spec in [["segment","所在墙段（从 0 起）"],["center","沿墙中心距离"],["width","洞宽"],["height","洞高"],["bottom","离地高"],["rise","拱高"]]:
			var key = spec[0]
			number(parent,spec[1],op.get(key,0.4),func(v): op[key] = int(v) if key=="segment" else v; commit_light(),1 if key=="segment" else 0.1,0,wall.points.size()-2 if key=="segment" else 10000)
	elif s.kind in ["floorPoly","floorNode"]:
		var layer = state.data.layers[s.layerIndex]
		text_field(parent,"图层名称",layer.name,func(v): layer.name = v; commit_light())
		number(parent,"图层标高",layer.y,func(v): layer.y = v; commit_light())
		choice(parent,"铺装风格",FLOOR_STYLES,layer.style,func(v): layer.style = v; commit_light())
		if s.kind=="floorNode":
			var pt = layer.roomFaces[s.polyIndex].nodes[s.ptIndex] if layer.has("roomFaces") else layer.polygons[s.polyIndex][s.ptIndex]
			for axis in range(2): number(parent,["X","Z"][axis],pt[axis],func(v):
				state.move_room_node(s.layerIndex,s.polyIndex,s.ptIndex,v if axis==0 else pt[0],v if axis==1 else pt[1]); commit_light())
	elif s.kind in ["railing","railingNode"]:
		var rail = state.data.railings[s.railIndex]
		number(parent,"栏杆高度",rail.height,func(v): rail.height = v; commit_light(),0.1,0.12)
		number(parent,"立杆间距",rail.get("spacing",0.18),func(v): rail.spacing = v; commit_light(),0.02,0.02)
		if s.kind=="railingNode":
			for axis in range(3): number(parent,["X","Y","Z"][axis],rail.points[s.ptIndex][axis],func(v): rail.points[s.ptIndex][axis] = v; commit_light())
	elif s.kind in ["stair","prop"]:
		var item = state.data.stairs[s.index] if s.kind=="stair" else state.data.props[s.index]
		text_field(parent,"名称",item.get("name",item.id),func(v): item.name = v; commit_light())
		for key in (["x","y","z","yaw","rise","run","risers","width","nosing"] if s.kind=="stair" else ["x","y","z","yaw"]):
			number(parent,key,item.get(key,0),func(v): item[key] = v; commit_light(),1 if key=="risers" else 0.1,1 if key=="risers" else -10000)
		if s.kind=="prop":
			if conflicts.has(s.index): label(parent,"⚠ 与其他家具重叠" if conflicts[s.index]=="overlap" else "⚠ 位于房间之外")
			var mount_field = Footprint.MOUNT_FIELD.get(str(item.kind),"")
			for field in prop_presets.get(item.kind,{"fields":[]}).fields:
				number(parent,field.label,item.params.get(field.id,field.val),func(v):
					item.params[field.id] = v
					if field.id==mount_field: item.y = v
					commit_light(),field.step)
			if item.kind=="native_recipe":
				var defaults = {}
				for entry in catalog.items:
					if entry.path==item.get("path",""): defaults = entry.get("defaults",{}); break
				for key in defaults:
					var value = item.params.get(key,defaults[key])
					if value is float or value is int:
						number(parent,str(key),value,func(v): item.params[key] = v; commit_light(),0.1)
					elif value is bool:
						check(parent,str(key),value,func(v): item.params[key] = v; commit_light())
		if s.kind=="stair": choice(parent,"扶手",{"both":"双侧","left":"左侧","right":"右侧","none":"无"},item.get("railingPos","both"),func(v): item.railingPos = v; commit_light())
func show_parameters() -> void:
	if state.selected.is_empty(): return
	if is_instance_valid(modal): modal.queue_free()
	modal = Window.new()
	modal.title = "独立参数编辑"
	modal.size = Vector2i(420,620)
	modal.close_requested.connect(func(): modal.queue_free())
	add_child(modal)
	var scroll = ScrollContainer.new()
	scroll.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	modal.add_child(scroll)
	var column = VBoxContainer.new()
	column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(column)
	fill_parameters(column)
	button(column,"关闭",func(): modal.queue_free())
	modal.popup_centered()
func open_file(action: String) -> void:
	file_action = action
	file_dialog.file_mode = FileDialog.FILE_MODE_OPEN_FILE if action=="import" else FileDialog.FILE_MODE_SAVE_FILE
	file_dialog.filters = PackedStringArray(["*.tscn ; Godot 场景"] if action=="scene" else (["*.yaml ; ArchBuilder YAML"] if action=="yaml" else ["*.json,*.yaml,*.yml ; ArchBuilder JSON / YAML"]))
	file_dialog.current_dir = ProjectSettings.globalize_path("res://tools/building_construction/candidates")
	file_dialog.current_file = "BuildingCandidate.tscn" if action=="scene" else ("BuildingCandidate.yaml" if action=="yaml" else "BuildingCandidate.json")
	file_dialog.popup_centered(Vector2i(850,600))
func _file_selected(path: String) -> void:
	if file_action=="import":
		if state.restore(FileAccess.get_file_as_string(path)):
			state.remember()
			refresh()
			reset_views()
		else: status.text = "JSON／YAML 场景格式无效"
	elif file_action in ["json","yaml"]:
		var file = FileAccess.open(path,FileAccess.WRITE)
		if file: file.store_string(preload("ArchitectYaml.gd").dump(state.data)+"\n" if file_action=="yaml" else JSON.stringify(state.data,"  ")); status.text = "已保存："+path
	else:
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
		status.text = "已导出候选："+path if error==OK else "导出失败："+error_string(error)
func clear_dialog() -> void:
	var dialog = ConfirmationDialog.new()
	dialog.dialog_text = "清空当前场景？可以撤销。"
	add_child(dialog)
	dialog.confirmed.connect(func():
		state.data = {"activeLayerId":null,"layers":[],"walls":[],"stairs":[],"railings":[],"props":[]}
		state.selected = {}
		state.new_layer()
		set_tool("select")
		commit()
		dialog.queue_free())
	dialog.canceled.connect(func(): dialog.queue_free())
	dialog.popup_centered()
func _on_blueprint_resized() -> void:
	if blueprint != null and blueprint.size.x > 200.0 and blueprint.size.y > 200.0:
		reset_views()


func reset_views() -> void:
	var min_x = INF
	var max_x = -INF
	var min_z = INF
	var max_z = -INF
	var max_y = 3.6
	for layer in state.data.layers:
		for poly in layer.polygons:
			for pt in poly:
				min_x = min(min_x,pt[0]); max_x = max(max_x,pt[0])
				min_z = min(min_z,pt[1]); max_z = max(max_z,pt[1])
	for wall in state.data.walls:
		max_y = max(max_y,wall.get("baseY",0)+wall.get("height",3.6))
		for pt in wall.points:
			min_x = min(min_x,pt[0]); max_x = max(max_x,pt[0])
			min_z = min(min_z,pt[2]); max_z = max(max_z,pt[2])
	for prop in state.data.props:
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
	_update_camera()
func _update_camera() -> void:
	camera.position = target+Vector3(sin(orbit.x)*cos(orbit.y),sin(orbit.y),cos(orbit.x)*cos(orbit.y))*distance
	camera.look_at(target)
	if auto_cutaway and candidates != null: apply_visibility()
func _camera_input(event: InputEvent) -> void:
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
	var sel = state.selected
	if sel.get("kind","") not in ["prop","stair"]: return
	var item = state.data.props[sel.index] if sel.kind=="prop" else state.data.stairs[sel.index]
	item.x = Geo.js_round((item.x+delta.x)*100)/100
	item.z = Geo.js_round((item.z+delta.y)*100)/100
	commit_light()
	refresh_inspector()

func duplicate_selected() -> void:
	var sel = state.selected
	if sel.get("kind","")!="prop": return
	var copy = state.data.props[sel.index].duplicate(true)
	copy.id = state.uid("prop")
	copy.x += 0.4
	copy.z += 0.4
	state.data.props.append(copy)
	state.selected = {"kind":"prop","index":state.data.props.size()-1}
	commit()

func _unhandled_key_input(event: InputEvent) -> void:
	if not event is InputEventKey or not event.pressed: return
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
		KEY_R:
			var s = state.selected
			if s.get("kind","") in ["prop","stair"]:
				var item = state.data.props[s.index] if s.kind=="prop" else state.data.stairs[s.index]
				item.yaw = fposmod(item.get("yaw",0)+(45 if s.kind=="prop" else 90),360)
				commit()
