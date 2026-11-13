extends Control
## 《安眠者有福 · 门的这一侧》——整合入口。
##   · 2D：完整场景地图（房间之间虚线连接）→ 双击进入房间
##   · 3D：真实游戏只显示单个房间（低多边形、昼夜光照、程序化音乐）
##   · 2D 编辑器：单房间蓝图设计，3D 与之共用同一份设计
##   · 规则核心：DualEngine（同一词汇在不同人脑中对应不同事实 → 误会、矛盾与错误行为）
## 全部界面用代码构建，不依赖 .tscn 子节点；可作为独立场景运行，也可由 Main.gd 嵌入。

signal closed

const Data := preload("res://scenes/dual_world/DualData.gd")
const Engine_ := preload("res://scenes/dual_world/DualEngine.gd")
const Geo := preload("res://scenes/dual_world/RoomGeometry.gd")
const DayNight := preload("res://scenes/dual_world/DayNight.gd")
const MapView := preload("res://scenes/dual_world/MapView2D.gd")
const Editor2D := preload("res://scenes/dual_world/BlueprintEditor2D.gd")
const RoomMesh := preload("res://scenes/dual_world/RoomMesh3D.gd")
const Figure := preload("res://scenes/dual_world/ProceduralFigure.gd")
const Score := preload("res://scenes/dual_world/ProceduralScore.gd")

const DESIGN_FILE := "user://dual_world/designs.json"
const SAVE_FILE := "user://dual_world/save_%d.json"
const AUTO_FILE := "user://dual_world/auto.json"
const INK := Color("#221c15")
const PAPER := Color("#eae0c4")
const BRASS := Color("#b89758")
const WOOD := Color("#1d1712")
const WOOD2 := Color("#2a2119")
const LINE := Color("#4a3b2d")
const TEXT := Color("#efe6d6")
const MUTED := Color("#a8957b")

var data: RefCounted
var eng: RefCounted
var score: Node
var view := "map"
var designs: Dictionary = {}
var _room_loaded := ""
var _occ_key := ""
var _modal_key := ""
var _dirty := true
var _panel_cd := 0.0
var _light_cd := 0.0
var _music_cd := 0.0

# 控件
var top_clock: Label
var top_phase: Label
var speed_pick: OptionButton
var auto_btn: Button
## 侦探自动搜证：空闲时搜完所在房间，推演缺证物时自己走去取
var auto_search := true
var _auto_cd := 1.0
var play_btn: Button
var view_btns: Dictionary = {}
var center: Control
var map_view: Control
var room_container: SubViewportContainer
var room_vp: SubViewport
var editor_box: Control
var editor: Control
var left_text: RichTextLabel
var left_actions: VBoxContainer
var right_tabs: TabContainer
var tab_log: RichTextLabel
var tab_ev: RichTextLabel
var tab_know: RichTextLabel
var tab_lex: RichTextLabel
var tab_rel: RichTextLabel
var tab_contract: RichTextLabel
var tab_author: RichTextLabel
var term_pick: OptionButton
var subtitle: Label
var toast: Label
var modal: Control
var editor_status: RichTextLabel
var editor_sel: Label
var kind_pick: OptionButton
var snap_check: CheckBox

# 3D
var sun: DirectionalLight3D
var env: Environment
var cam: Camera3D
var room_mesh: Node3D
var figures_root: Node3D
var figures: Dictionary = {}
var az := 0.65
var pitch := 0.82
var dist := 9.5
var _orbit := false
var _sub_until := 0.0
var _speaker := ""
var _toast_until := 0.0

## 由 Main 在「继续游戏」时设置：进入后直接读取这份存档。
var resume_path := ""
## 测试 / 脚本用：true 时台词不排队、不冻结时间，换房间不走路（沿用旧的瞬时行为）。
var instant_story := false

# 界面（浮层式布局：3D 占满整个画面，信息收进左上角位置卡与右侧案卷抽屉）
var left_card: PanelContainer
var left_body: Control
var drawer: PanelContainer
var drawer_btn: Button
var menu_btn: MenuButton
var room_hint: Label
var fade_rect: ColorRect

# 侦探在 3D 里的行走
const CELL := 0.3
const WALK_SPEED := 3.0
var det_root: Node3D
var det: Node3D
var det_pos := Vector2.ZERO
var det_path: Array = []
var det_done := Callable()
var _det_talk := ""
var _grid: AStarGrid2D
var _transit: Dictionary = {}
var _fade_tween: Tween

# 台词队列：一句一句播，播放期间时间冻结，抉择窗口在台词播完后才弹出
var _sub_queue: Array = []
var _autosave_due := false
var _autosave_cd := 0.0
var _fit_dist := 9.0
const AUTOSAVE_EVENTS := ["beat", "choice", "conflict", "deduction", "evidence", "knowledge", "jump", "room"]


func _ready() -> void:
	data = Data.get_data()
	eng = Engine_.new(data)
	_load_designs()
	_build_ui()
	score = Score.new()
	add_child(score)
	eng.changed.connect(func(why: String):
		_dirty = true
		if why in AUTOSAVE_EVENTS: _autosave_due = true)
	eng.said.connect(_on_said)
	eng.sfx.connect(func(k: String): score.sfx(k))
	set_process(true)
	if resume_path != "" and not _read_save(resume_path):
		_toast("存档无法读取，已从头开始")
	# 正式游戏默认进 3D 房间：侦探在房间里走动；2D 地图是辅助视图
	_set_view("room")
	_dirty = true


func _unhandled_input(event: InputEvent) -> void:
	# 浏览器与桌面端都要求用户手势后才能出声：首次点击或按键时启动合成器
	if event is InputEventMouseButton or event is InputEventKey:
		if score != null and not score._started and score.enabled: score.start()


func _close() -> void:
	_finish_transit_now()
	_write_auto()
	closed.emit()


# ───────────────────────── 构建界面 ─────────────────────────
func _style(bg: Color, border := LINE, radius := 4, margin := 0) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.border_color = border
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(radius)
	sb.set_content_margin_all(margin)
	return sb


func _theme() -> Theme:
	var t := Theme.new()
	t.set_color("font_color", "Label", TEXT)
	t.set_color("font_color", "Button", TEXT)
	t.set_color("font_hover_color", "Button", Color("#fff4dc"))
	t.set_color("font_color", "CheckBox", TEXT)
	t.set_color("default_color", "RichTextLabel", TEXT)
	t.set_stylebox("normal", "Button", _style(Color("#2c2219"), LINE, 5, 6))
	t.set_stylebox("hover", "Button", _style(Color("#3a2d22"), BRASS, 5, 6))
	t.set_stylebox("pressed", "Button", _style(Color("#8a6a2f"), Color("#d9a13a"), 5, 6))
	t.set_stylebox("disabled", "Button", _style(Color("#201a14"), LINE, 5, 6))
	t.set_stylebox("panel", "PanelContainer", _style(WOOD2, LINE, 4, 8))
	for kind in ["MenuButton", "OptionButton"]:
		t.set_color("font_color", kind, TEXT)
		t.set_color("font_hover_color", kind, Color("#fff4dc"))
		t.set_stylebox("normal", kind, _style(Color("#2c2219"), LINE, 5, 6))
		t.set_stylebox("hover", kind, _style(Color("#3a2d22"), BRASS, 5, 6))
		t.set_stylebox("pressed", kind, _style(Color("#8a6a2f"), Color("#d9a13a"), 5, 6))
	t.set_stylebox("panel", "PopupMenu", _style(Color("#1d1712"), BRASS, 4, 6))
	t.set_stylebox("hover", "PopupMenu", _style(Color("#3a2d22"), BRASS, 3, 4))
	t.set_color("font_color", "PopupMenu", TEXT)
	t.set_color("font_hover_color", "PopupMenu", Color("#fff4dc"))
	t.set_font_size("font_size", "TabContainer", 13)
	t.set_color("font_selected_color", "TabContainer", Color("#e9c98a"))
	t.set_color("font_unselected_color", "TabContainer", MUTED)
	return t


func _btn(parent: Node, text: String, cb: Callable, tip := "") -> Button:
	var b := Button.new()
	b.text = text
	b.tooltip_text = tip
	b.pressed.connect(cb)
	b.focus_mode = Control.FOCUS_NONE
	parent.add_child(b)
	return b


func _rich(bb := true) -> RichTextLabel:
	var r := RichTextLabel.new()
	r.bbcode_enabled = bb
	r.scroll_following = false
	r.selection_enabled = true
	r.fit_content = false
	r.size_flags_vertical = Control.SIZE_EXPAND_FILL
	r.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return r


func _build_ui() -> void:
	theme = _theme()
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var bg := ColorRect.new()
	bg.color = Color("#100e0c")
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	var root := VBoxContainer.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.add_theme_constant_override("separation", 0)
	add_child(root)
	# ── 顶栏：只留时间、播放控制、视图切换、案卷与菜单 ──
	var top := PanelContainer.new()
	top.add_theme_stylebox_override("panel", _style(Color("#17120e"), LINE, 0, 6))
	root.add_child(top)
	var tb := HBoxContainer.new()
	tb.add_theme_constant_override("separation", 8)
	top.add_child(tb)
	top_clock = Label.new()
	top_clock.add_theme_color_override("font_color", Color("#e9c98a"))
	tb.add_child(top_clock)
	top_phase = Label.new()
	top_phase.add_theme_color_override("font_color", MUTED)
	top_phase.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top_phase.clip_text = true
	tb.add_child(top_phase)
	play_btn = _btn(tb, "暂停", func(): eng.toggle_play())
	speed_pick = OptionButton.new()
	for sp in [[1.0, "×1"], [2.0, "×2"], [5.0, "×5"], [20.0, "×20"], [60.0, "×60"], [240.0, "×240"]]:
		speed_pick.add_item(sp[1])
		speed_pick.set_item_metadata(speed_pick.item_count - 1, sp[0])
	_sync_speed_pick()
	speed_pick.item_selected.connect(func(i: int): eng.set_speed(float(speed_pick.get_item_metadata(i))))
	tb.add_child(speed_pick)
	auto_btn = _btn(tb, "自动搜证", func(): auto_search = auto_btn.button_pressed,
		"开：侦探会自己走动、搜查所在房间，并去查推演还缺的证物；关：只由你点击证物")
	auto_btn.toggle_mode = true
	auto_btn.button_pressed = auto_search
	for v in [["room", "房间"], ["map", "地图"]]:
		var vb := _btn(tb, v[1], func(): _set_view(v[0], v[0] == "room"))
		vb.toggle_mode = true
		view_btns[v[0]] = vb
	drawer_btn = _btn(tb, "案卷", func(): _toggle_drawer())
	drawer_btn.toggle_mode = true
	drawer_btn.tooltip_text = "日志 / 证物 / 知识 / 词义 / 关系"
	menu_btn = MenuButton.new()
	menu_btn.text = "菜单"
	menu_btn.focus_mode = Control.FOCUS_NONE
	var pm := menu_btn.get_popup()
	pm.add_item("下一节拍", 0)
	pm.add_separator()
	pm.add_check_item("背景音乐", 2)
	pm.set_item_checked(pm.get_item_index(2), true)
	pm.add_check_item("作者视角（显示词义分歧）", 3)
	pm.add_separator()
	pm.add_item("2D 场景编辑器", 5)
	pm.add_separator()
	pm.add_item("存档（槽位 1）", 7)
	pm.add_item("读档（槽位 1）", 8)
	pm.add_separator()
	pm.add_item("返回标题", 9)
	pm.id_pressed.connect(_on_menu)
	tb.add_child(menu_btn)
	# ── 中央：整块画面都给地图 / 3D 房间 / 编辑器 ──
	center = Control.new()
	center.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	center.size_flags_vertical = Control.SIZE_EXPAND_FILL
	center.custom_minimum_size = Vector2(480, 300)
	center.clip_contents = true
	root.add_child(center)
	_build_center()
	# ── 左上：位置卡（房间、在场者、出口、本房证物），可折叠 ──
	left_card = PanelContainer.new()
	left_card.add_theme_stylebox_override("panel", _style(Color(0.09, 0.07, 0.05, 0.84), LINE, 6, 10))
	left_card.set_anchors_preset(Control.PRESET_TOP_LEFT)
	left_card.offset_left = 12
	left_card.offset_top = 12
	left_card.custom_minimum_size = Vector2(250, 0)
	center.add_child(left_card)
	var lv := VBoxContainer.new()
	lv.add_theme_constant_override("separation", 4)
	left_card.add_child(lv)
	var lh := HBoxContainer.new()
	lv.add_child(lh)
	var lt := Label.new()
	lt.text = "当前位置"
	lt.add_theme_color_override("font_color", BRASS)
	lt.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	lh.add_child(lt)
	var fold := _btn(lh, "–", func(): pass)
	fold.custom_minimum_size = Vector2(28, 0)
	fold.pressed.connect(func():
		left_body.visible = not left_body.visible
		fold.text = "–" if left_body.visible else "+")
	left_body = VBoxContainer.new()
	left_body.add_theme_constant_override("separation", 4)
	lv.add_child(left_body)
	left_text = _rich()
	left_text.fit_content = true
	left_text.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	left_body.add_child(left_text)
	var sc := ScrollContainer.new()
	sc.custom_minimum_size = Vector2(0, 150)
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	left_body.add_child(sc)
	left_actions = VBoxContainer.new()
	left_actions.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sc.add_child(left_actions)
	# ── 右侧：案卷抽屉（默认收起） ──
	drawer = PanelContainer.new()
	drawer.add_theme_stylebox_override("panel", _style(Color(0.09, 0.07, 0.05, 0.95), LINE, 6, 8))
	drawer.anchor_left = 1.0
	drawer.anchor_right = 1.0
	drawer.anchor_top = 0.0
	drawer.anchor_bottom = 1.0
	drawer.offset_left = -400
	drawer.offset_right = -12
	drawer.offset_top = 12
	drawer.offset_bottom = -104
	drawer.visible = false
	center.add_child(drawer)
	right_tabs = TabContainer.new()
	drawer.add_child(right_tabs)
	tab_log = _add_tab("日志")
	tab_ev = _add_tab("证物")
	tab_know = _add_tab("知识")
	var lex_box := VBoxContainer.new()
	lex_box.name = "词义"
	right_tabs.add_child(lex_box)
	term_pick = OptionButton.new()
	for k in data.terms:
		term_pick.add_item(str(data.terms[k].word))
		term_pick.set_item_metadata(term_pick.item_count - 1, k)
	term_pick.item_selected.connect(func(_i: int): _dirty = true)
	lex_box.add_child(term_pick)
	tab_lex = _rich()
	lex_box.add_child(tab_lex)
	tab_rel = _add_tab("关系")
	tab_contract = _add_tab("契约")
	tab_author = _add_tab("调试")
	_apply_author_tabs()
	# ── 底部：台词字幕 + 操作提示 ──
	room_hint = Label.new()
	room_hint.text = "点光柱 → 侦探走过去查看  ·  右键拖动旋转  ·  滚轮缩放"
	room_hint.add_theme_font_size_override("font_size", 12)
	room_hint.add_theme_color_override("font_color", Color(MUTED, 0.85))
	room_hint.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	room_hint.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	room_hint.grow_vertical = Control.GROW_DIRECTION_BEGIN
	room_hint.offset_right = -16
	room_hint.offset_bottom = -102
	room_hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	center.add_child(room_hint)
	subtitle = Label.new()
	subtitle.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	subtitle.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	subtitle.add_theme_font_size_override("font_size", 18)
	subtitle.add_theme_stylebox_override("normal", _style(Color(0.06, 0.05, 0.04, 0.9), BRASS, 6, 10))
	subtitle.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	subtitle.offset_left = 60
	subtitle.offset_right = -60
	subtitle.offset_top = -92
	subtitle.offset_bottom = -14
	subtitle.visible = false
	subtitle.mouse_filter = Control.MOUSE_FILTER_STOP
	subtitle.tooltip_text = "点击跳过这一句"
	subtitle.gui_input.connect(func(ev: InputEvent):
		if ev is InputEventMouseButton and ev.pressed and ev.button_index == MOUSE_BUTTON_LEFT: _sub_until = 0.0)
	center.add_child(subtitle)
	toast = Label.new()
	toast.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	toast.offset_top = 60
	toast.add_theme_stylebox_override("normal", _style(Color(0.1, 0.07, 0.04, 0.92), Color("#d9a13a"), 6, 8))
	toast.visible = false
	toast.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(toast)
	modal = Control.new()
	modal.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	modal.visible = false
	add_child(modal)
	for c in data.contract:
		tab_contract.append_text("[color=#e9c98a]%s[/color]  %s\n\n" % [c[0], c[1]])


func _add_tab(name_: String) -> RichTextLabel:
	var r := _rich()
	r.name = name_
	right_tabs.add_child(r)
	return r


func _toggle_drawer() -> void:
	drawer.visible = not drawer.visible
	drawer_btn.button_pressed = drawer.visible
	_dirty = true


## 「调试」页只在作者视角下出现。
func _apply_author_tabs() -> void:
	var idx := right_tabs.get_tab_idx_from_control(tab_author)
	if idx >= 0: right_tabs.set_tab_hidden(idx, not eng.s.author_view)
	if not eng.s.author_view and right_tabs.current_tab == idx: right_tabs.current_tab = 0


func _on_menu(id: int) -> void:
	var pm := menu_btn.get_popup()
	match id:
		0: eng.next_beat()
		2:
			var i := pm.get_item_index(2)
			pm.set_item_checked(i, not pm.is_item_checked(i))
			score.set_enabled(pm.is_item_checked(i))
		3:
			var j := pm.get_item_index(3)
			pm.set_item_checked(j, not pm.is_item_checked(j))
			eng.s.author_view = pm.is_item_checked(j)
			eng.set_door_flags()
			_apply_author_tabs()
			_dirty = true
		5: _set_view("editor")
		7: _save_game(1)
		8: _load_game(1)
		9: _close()


func _build_center() -> void:
	map_view = MapView.new()
	map_view.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center.add_child(map_view)
	map_view.setup(eng)
	map_view.room_selected.connect(func(_id: String): _dirty = true)
	map_view.room_activated.connect(_on_room_activated)
	# 3D 视口
	room_container = SubViewportContainer.new()
	room_container.stretch = true
	room_container.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	room_container.gui_input.connect(_on_3d_input)
	center.add_child(room_container)
	room_vp = SubViewport.new()
	room_vp.msaa_3d = Viewport.MSAA_4X
	room_vp.handle_input_locally = false
	room_container.add_child(room_vp)
	var world := Node3D.new()
	room_vp.add_child(world)
	sun = DirectionalLight3D.new()
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 40.0
	sun.shadow_normal_bias = 1.2
	sun.shadow_bias = 0.06
	world.add_child(sun)
	var we := WorldEnvironment.new()
	env = Environment.new()
	we.environment = env
	world.add_child(we)
	cam = Camera3D.new()
	cam.near = 0.1
	cam.far = 120.0
	cam.fov = 55.0
	world.add_child(cam)
	room_mesh = RoomMesh.new()
	world.add_child(room_mesh)
	figures_root = Node3D.new()
	world.add_child(figures_root)
	det_root = Node3D.new()
	world.add_child(det_root)
	_spawn_detective()
	room_container.resized.connect(_fit_camera)
	# 编辑器
	editor_box = HBoxContainer.new()
	editor_box.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center.add_child(editor_box)
	var ev := VBoxContainer.new()
	ev.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	editor_box.add_child(ev)
	var bar := HFlowContainer.new()
	ev.add_child(bar)
	kind_pick = OptionButton.new()
	var kinds: Array = Geo.prop_kinds()
	kinds.sort()
	for k in kinds:
		if k == "evidence_marker": continue
		kind_pick.add_item("%s（%s）" % [Geo.prop_label(str(k)), k])
		kind_pick.set_item_metadata(kind_pick.item_count - 1, k)
	bar.add_child(kind_pick)
	editor = Editor2D.new()
	editor.size_flags_vertical = Control.SIZE_EXPAND_FILL
	editor.custom_minimum_size = Vector2(300, 240)
	_btn(bar, "添加家具", func(): editor.add_prop(str(kind_pick.get_item_metadata(kind_pick.selected))))
	_btn(bar, "旋转 90°", func(): editor.rotate_selected(90.0))
	_btn(bar, "删除", func(): editor.delete_selected())
	_btn(bar, "撤销", func(): editor.undo())
	_btn(bar, "重做", func(): editor.redo())
	_btn(bar, "加窗", func(): editor.add_opening("rectangular_window"))
	_btn(bar, "加拱门", func(): editor.add_opening("portal_arch"))
	_btn(bar, "重新自动布置", func(): editor.reset_auto())
	snap_check = CheckBox.new()
	snap_check.text = "吸附网格"
	snap_check.button_pressed = true
	snap_check.toggled.connect(func(on: bool):
		editor.snap_on = on
		editor.queue_redraw())
	bar.add_child(snap_check)
	_btn(bar, "保存设计", _save_design)
	_btn(bar, "在 3D 中预览", func():
		_save_design()
		_room_loaded = ""
		_set_view("room"))
	ev.add_child(editor)
	var side := VBoxContainer.new()
	side.custom_minimum_size = Vector2(230, 0)
	editor_box.add_child(side)
	editor_sel = Label.new()
	editor_sel.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	editor_sel.text = "未选中"
	side.add_child(editor_sel)
	editor_status = _rich()
	side.add_child(editor_status)
	editor.design_changed.connect(_update_editor_status)
	editor.selection_changed.connect(func(t: String): editor_sel.text = t if t != "" else "未选中")
	# 换房间时的黑场（盖在 3D 上，不挡 UI）
	fade_rect = ColorRect.new()
	fade_rect.color = Color(0.03, 0.02, 0.02, 1.0)
	fade_rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	fade_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	fade_rect.modulate.a = 0.0
	center.add_child(fade_rect)


# ───────────────────────── 视图切换 ─────────────────────────
func _set_view(v: String, animate := false) -> void:
	if view == "room" and v != "room": _finish_transit_now()
	view = v
	map_view.visible = v == "map"
	room_container.visible = v == "room"
	editor_box.visible = v == "editor"
	left_card.visible = v != "editor"
	room_hint.visible = v == "room"
	for k in view_btns: view_btns[k].button_pressed = k == v
	if v == "room":
		# 从地图双击进入：保留旧房间，让侦探走出去再走进来；其余情况直接建好房间
		if not (animate and _room_loaded != "" and not instant_story): _ensure_room()
		else: _fit_camera()
	if v == "editor": _open_editor(eng.s.room if map_view.selected == "" else map_view.selected)
	_dirty = true


func _on_room_activated(id: String) -> void:
	if id == eng.s.room or eng.enter_room(id):
		_set_view("room", true)


# ───────────────────────── 台词队列 ─────────────────────────
func _on_said(who: String, text: String, kind: String) -> void:
	if instant_story: _sub_queue.clear()
	_sub_queue.append({"who": who, "text": text, "kind": kind})


func _story_busy() -> bool:
	return subtitle.visible or not _sub_queue.is_empty() or not det_path.is_empty()


func _figure_of(who: String) -> Node3D:
	if who == "detective": return det
	return figures.get(who, null)


func _set_talk_pose(who: String, pose: String) -> void:
	if who == "detective": _det_talk = "" if pose == "stand" else pose
	else:
		var f: Node3D = figures.get(who, null)
		if f != null and is_instance_valid(f): f.set_pose(pose)


## 播完当前一句、取下一句。队列非空或字幕在场时，时间冻结（见 _process）。
func _pump_subtitles(now: float) -> void:
	if subtitle.visible and now < _sub_until: return
	if subtitle.visible:
		subtitle.visible = false
		_set_talk_pose(_speaker, "stand")
		if _sub_queue.is_empty(): _dirty = true  # 台词播完，抉择窗口可以弹了
	if _sub_queue.is_empty(): return
	var ln: Dictionary = _sub_queue.pop_front()
	var who: String = ln.who
	var text: String = ln.text
	_speaker = who
	var nm := ""
	if who != "narrator" and data.actor_by_id.has(who): nm = str(data.actor_name(who)) + "："
	subtitle.text = nm + text
	subtitle.visible = true
	_sub_until = now + maxf(2.4, 1.2 + text.length() * 0.075)
	var pose := "talk"
	match str(ln.kind):
		"confront": pose = "argue"
		"truth": pose = "point"
		"think": pose = "think"
	_set_talk_pose(who, pose)


func _toast(text: String) -> void:
	toast.text = text
	toast.visible = true
	_toast_until = Time.get_ticks_msec() / 1000.0 + 2.6


# ───────────────────────── 设计存取 ─────────────────────────
func _load_designs() -> void:
	designs.clear()
	if FileAccess.file_exists(DESIGN_FILE):
		var f := FileAccess.open(DESIGN_FILE, FileAccess.READ)
		var p: Variant = JSON.parse_string(f.get_as_text())
		if p is Dictionary: designs = p


func _design_for(room_id: String) -> Dictionary:
	if designs.has(room_id): return designs[room_id].duplicate(true)
	return Geo.make_design(data.room_by_id[room_id], data)


func _save_design() -> void:
	if editor.design.is_empty(): return
	designs[editor.design.room_id] = editor.design.duplicate(true)
	DirAccess.make_dir_recursive_absolute("user://dual_world")
	var f := FileAccess.open(DESIGN_FILE, FileAccess.WRITE)
	f.store_string(JSON.stringify(designs))
	_toast("设计已保存：" + str(editor.design.name))


func _open_editor(room_id: String) -> void:
	if not data.room_by_id.has(room_id): return
	editor.found = eng.s.evidence
	editor.hour = eng.clock().hour
	editor.set_design(_design_for(room_id), data)
	_update_editor_status()


func _update_editor_status() -> void:
	editor_status.clear()
	for it in editor.issues():
		editor_status.append_text("%s %s\n" % ["[color=#a8c89a]✓[/color]" if it.ok else "[color=#ff7a6a]✗[/color]", it.text])


# ───────────────────────── 存读档 ─────────────────────────
func _write_save(path: String) -> void:
	DirAccess.make_dir_recursive_absolute("user://dual_world")
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f != null: f.store_string(JSON.stringify(eng.save_dict()))


## 自动存档：「继续游戏」读这一份。通关后删除，避免下次继续时直接停在结局上。
func _write_auto() -> void:
	if eng.s.ending != "":
		if FileAccess.file_exists(AUTO_FILE): DirAccess.remove_absolute(AUTO_FILE)
		return
	_write_save(AUTO_FILE)


func _save_game(slot: int) -> void:
	_write_save(SAVE_FILE % slot)
	_toast("已存档至槽位 %d" % slot)
	score.sfx("success")


func _read_save(path: String) -> bool:
	if not FileAccess.file_exists(path): return false
	var f := FileAccess.open(path, FileAccess.READ)
	var p: Variant = JSON.parse_string(f.get_as_text())
	if not (p is Dictionary and eng.load_dict(p)): return false
	_modal_key = ""
	_sub_queue.clear()
	subtitle.visible = false
	_finish_transit_now()
	_room_loaded = ""
	var pm := menu_btn.get_popup()
	pm.set_item_checked(pm.get_item_index(3), bool(eng.s.author_view))
	_apply_author_tabs()
	if view == "room": _ensure_room()
	return true


func _load_game(slot: int) -> void:
	if not FileAccess.file_exists(SAVE_FILE % slot):
		_toast("槽位为空")
		return
	if _read_save(SAVE_FILE % slot): _toast("已读取槽位 %d" % slot)


# ───────────────────────── 3D：单房间 ─────────────────────────
func _transit_active() -> bool:
	return bool(_transit.get("active", false))


func _ensure_room() -> void:
	if _transit_active(): return
	var id: String = eng.s.room
	if id == _room_loaded: return
	_build_room(id)
	_det_to_home()


func _build_room(id: String) -> void:
	_room_loaded = id
	room_mesh.build(_design_for(id), eng.s.evidence)
	_build_grid()
	_occ_key = ""
	_fit_camera()
	room_mesh.refresh_walls(az)
	DayNight.apply(eng.clock().hour, sun, env, room_mesh.lamps, room_mesh.glow_materials)
	_sync_figures(true)


func _aim(distance: float) -> void:
	var c: Vector3 = room_mesh.center()
	var dir := Vector3(sin(az) * cos(pitch), sin(pitch), cos(az) * cos(pitch))
	cam.position = c + dir * distance
	cam.look_at(c, Vector3.UP)


func _update_camera() -> void:
	if room_mesh.design.is_empty(): return
	_aim(dist)
	room_mesh.refresh_walls(az)


## 取景：二分求出能把整间房（含墙高）放进画面的最近距离。一次只看一个房间，所以尽量放大。
func _fit_camera() -> void:
	if room_mesh == null or room_mesh.design.is_empty() or room_container == null: return
	var vs: Vector2 = room_container.size
	if vs.x < 120.0 or vs.y < 120.0: return
	var w: float = room_mesh.design.w
	var d: float = room_mesh.design.d
	var corners: Array = []
	for x in [0.0, w]:
		for z in [0.0, d]:
			for y in [0.0, 1.9]:
				corners.append(Vector3(x, y, z))
	var th := tan(deg_to_rad(cam.fov) * 0.5)
	var aspect := vs.x / vs.y
	var lo := 2.5
	var hi := 60.0
	for i in 22:
		var mid := (lo + hi) * 0.5
		_aim(mid)
		var inv := cam.global_transform.affine_inverse()
		var ok := true
		for p in corners:
			var v: Vector3 = inv * p
			if v.z > -0.1:
				ok = false
				break
			var nx: float = absf(v.x / -v.z) / (th * aspect)
			var ny: float = absf(v.y / -v.z) / th
			if nx > 0.92 or ny > 0.86:
				ok = false
				break
		if ok: hi = mid
		else: lo = mid
	_fit_dist = hi
	dist = hi
	_aim(dist)
	room_mesh.refresh_walls(az)


func _free_slots(n: int) -> Array:
	var ds: Dictionary = room_mesh.design
	var out: Array = []
	var tp := {"id": "slot", "kind": "planter", "x": 0.0, "z": 0.0, "yaw": 0.0, "params": {}}
	var cands: Array = []
	var x := 0.8
	while x < ds.w - 0.8:
		var z := 0.8
		while z < ds.d - 0.8:
			cands.append(Vector2(x, z))
			z += 0.55
		x += 0.55
	var mid := Vector2(ds.w * 0.5, ds.d * 0.5)
	cands.sort_custom(func(a, b): return a.distance_to(mid) < b.distance_to(mid))
	for c in cands:
		tp.x = c.x
		tp.z = c.y
		var ok := true
		for p in ds.props:
			if Geo.prop_dims(p).blocking and Geo.rects_overlap(tp, p, 0.12):
				ok = false
				break
		if ok:
			for o in out:
				if o.distance_to(c) < 0.9: ok = false
		if ok: out.append(c)
		if out.size() >= n: break
	return out


func _sync_figures(force := false) -> void:
	if room_mesh.design.is_empty(): return
	if _transit_active() and not force: return
	var list: Array = eng.actors_in_room(_room_loaded).filter(func(i): return str(i) != "detective")
	var key := ",".join(list.map(func(i): return str(i))) + "@" + _room_loaded
	if key == _occ_key: return
	_occ_key = key
	for c in figures_root.get_children(): c.queue_free()
	figures.clear()
	var slots := _free_slots(list.size() + 1)  # 第 0 个空位留给侦探
	var mid := Vector2(room_mesh.design.w * 0.5, room_mesh.design.d * 0.5)
	for i in mini(list.size(), slots.size() - 1):
		var a: Dictionary = data.actor_by_id[list[i]]
		var f: Node3D = Figure.new()
		f.setup(a, data.rig_spec.get("poses", {}))
		var sp: Vector2 = slots[i + 1]
		f.position = Vector3(sp.x, 0.0, sp.y)
		var to := mid - sp
		f.rotation.y = atan2(to.x, to.y)
		figures_root.add_child(f)
		figures[a.id] = f
		var tag := Label3D.new()
		tag.text = str(a.name)
		tag.font_size = 40
		tag.pixel_size = 0.006
		tag.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		tag.position = Vector3(0, float(a.look.height) + 0.28, 0)
		tag.modulate = Color(str(a.color)).lightened(0.55)
		tag.outline_size = 8
		tag.no_depth_test = true
		f.add_child(tag)


# ───────────────────────── 3D：侦探走路 ─────────────────────────
func _spawn_detective() -> void:
	det = Figure.new()
	det.setup(data.actor_by_id["detective"], data.rig_spec.get("poses", {}))
	det_root.add_child(det)
	# 脚下金色光环 + 名牌：一眼能找到「我」在哪
	var ring := MeshInstance3D.new()
	var tm := TorusMesh.new()
	tm.inner_radius = 0.34
	tm.outer_radius = 0.42
	ring.mesh = tm
	ring.scale = Vector3(1.0, 0.25, 1.0)
	ring.position = Vector3(0, 0.035, 0)
	var rm := StandardMaterial3D.new()
	rm.albedo_color = Color("#d9a13a")
	rm.emission_enabled = true
	rm.emission = Color("#d9a13a")
	rm.emission_energy_multiplier = 1.4
	rm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	ring.material_override = rm
	ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	det.add_child(ring)
	var tag := Label3D.new()
	tag.text = "侦探"
	tag.font_size = 46
	tag.pixel_size = 0.006
	tag.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	tag.position = Vector3(0, float(data.actor_by_id["detective"].look.height) + 0.3, 0)
	tag.modulate = Color("#ffd98a")
	tag.outline_size = 10
	tag.no_depth_test = true
	det.add_child(tag)


func _home_spot() -> Vector2:
	var slots := _free_slots(1)
	if not slots.is_empty(): return slots[0]
	return Vector2(room_mesh.design.w * 0.5, room_mesh.design.d * 0.5)


func _det_to_home() -> void:
	det_path.clear()
	det_done = Callable()
	det_pos = _home_spot()
	det.position = Vector3(det_pos.x, 0.0, det_pos.y)
	det.rotation.y = az  # 正面朝向镜头


func _build_grid() -> void:
	var ds: Dictionary = room_mesh.design
	var cx := int(ceil(float(ds.w) / CELL))
	var cz := int(ceil(float(ds.d) / CELL))
	_grid = AStarGrid2D.new()
	_grid.region = Rect2i(0, 0, cx, cz)
	_grid.cell_size = Vector2(CELL, CELL)
	_grid.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_ONLY_IF_NO_OBSTACLES
	_grid.default_compute_heuristic = AStarGrid2D.HEURISTIC_OCTILE
	_grid.default_estimate_heuristic = AStarGrid2D.HEURISTIC_OCTILE
	_grid.update()
	var margin: float = float(ds.walls[0].thickness) / 2.0 + 0.2
	for ix in cx:
		for iz in cz:
			var px := (ix + 0.5) * CELL
			var pz := (iz + 0.5) * CELL
			var blocked := px < margin or px > float(ds.w) - margin or pz < margin or pz > float(ds.d) - margin
			if not blocked:
				for pr in ds.props:
					if Geo.prop_dims(pr).blocking and Geo.point_in_prop(pr, px, pz, 0.2):
						blocked = true
						break
			if blocked: _grid.set_point_solid(Vector2i(ix, iz), true)


func _cell_of(p: Vector2) -> Vector2i:
	var r: Rect2i = _grid.region
	return Vector2i(clampi(int(floor(p.x / CELL)), 0, r.size.x - 1), clampi(int(floor(p.y / CELL)), 0, r.size.y - 1))


func _nearest_free(c: Vector2i) -> Vector2i:
	if not _grid.is_point_solid(c): return c
	for r in range(1, 9):
		for dx in range(-r, r + 1):
			for dz in range(-r, r + 1):
				if maxi(absi(dx), absi(dz)) != r: continue
				var q := Vector2i(c.x + dx, c.y + dz)
				if _grid.is_in_boundsv(q) and not _grid.is_point_solid(q): return q
	return c


## 房间内绕开家具的路线（网格 A*）；终点本身不在障碍里时才精确走到终点。
func _route(from: Vector2, to: Vector2) -> Array:
	if _grid == null: return [to]
	var a := _nearest_free(_cell_of(from))
	var b := _nearest_free(_cell_of(to))
	var ids: Array[Vector2i] = _grid.get_id_path(a, b)
	var out: Array = []
	for id in ids: out.append(Vector2((id.x + 0.5) * CELL, (id.y + 0.5) * CELL))
	if out.size() > 1: out.pop_front()
	if not _grid.is_point_solid(_cell_of(to)): out.append(to)
	return out


func _go(points: Array, done := Callable()) -> void:
	det_path = points
	det_done = done


func _walk_step(delta: float) -> void:
	if det == null: return
	var moving := not det_path.is_empty()
	if moving:
		var step := WALK_SPEED * delta
		while step > 0.0 and not det_path.is_empty():
			var tgt: Vector2 = det_path[0]
			var dv: Vector2 = tgt - det_pos
			var l := dv.length()
			if l > 0.001:
				det.rotation.y = lerp_angle(det.rotation.y, atan2(dv.x, dv.y), minf(1.0, delta * 14.0))
			if l <= step:
				det_pos = tgt
				step -= l
				det_path.pop_front()
			else:
				det_pos += dv / l * step
				step = 0.0
		det.position = Vector3(det_pos.x, 0.0, det_pos.y)
	det.set_pose("walk" if not det_path.is_empty() else (_det_talk if _det_talk != "" else "stand"))
	if det_path.is_empty() and det_done.is_valid():
		var cb := det_done
		det_done = Callable()
		cb.call()


## 3D 里点证物光柱 / 左侧点证物：侦探先走到跟前，再查看。
func _inspect_walk(eid: String) -> void:
	if view != "room" or instant_story or _transit_active() or not room_mesh.evidence_nodes.has(eid) or _room_loaded != eng.s.room:
		eng.inspect_evidence(eid)
		return
	var n: Node3D = room_mesh.evidence_nodes[eid]
	var target := Vector2(n.global_position.x, n.global_position.z)
	var away := det_pos - target
	if away.length() < 0.05: away = Vector2(0, 1)
	var stand := target + away.normalized() * 0.6
	_go(_route(det_pos, stand), func():
		if _room_loaded != eng.s.room or _transit_active(): return
		det.rotation.y = atan2(target.x - det_pos.x, target.y - det_pos.y)
		eng.inspect_evidence(eid)
		_rebuild_markers())


func _rebuild_markers() -> void:
	room_mesh.build(room_mesh.design, eng.s.evidence)
	_occ_key = ""
	_sync_figures()


func _room_dir(a: String, b: String) -> Vector2:
	var ra: Dictionary = data.room_by_id[a].map
	var rb: Dictionary = data.room_by_id[b].map
	var v := Vector2(float(rb.x) + float(rb.w) * 0.5 - float(ra.x) - float(ra.w) * 0.5, float(rb.y) + float(rb.h) * 0.5 - float(ra.y) - float(ra.h) * 0.5)
	return v.normalized() if v.length() > 0.01 else Vector2(0, 1)


## 选一扇最朝向 dirv 的门：返回 {pos 墙上, inward 朝室内, inner 室内站位, outer 室外站位}。
func _door_for(ds: Dictionary, dirv: Vector2) -> Dictionary:
	var wall: Dictionary = ds.walls[0]
	var segs: Array = Geo.wall_segments(wall)
	var mid := Vector2(float(ds.w) * 0.5, float(ds.d) * 0.5)
	var best: Dictionary = {}
	var best_dot := -INF
	for op in wall.openings:
		if not Geo.is_passable(str(op.type)): continue
		var seg: Dictionary = {}
		for sg in segs:
			if int(sg.index) == int(op.segment): seg = sg
		if seg.is_empty(): continue
		var sa: Vector2 = seg.a
		var sb: Vector2 = seg.b
		var u: Vector2 = (sb - sa) / float(seg.len)
		var pos: Vector2 = sa + u * float(op.center)
		var inward := Vector2(-u.y, u.x)
		if inward.dot(mid - pos) < 0.0: inward = -inward
		var dv: float = (-inward).dot(dirv)
		if dv > best_dot:
			best_dot = dv
			best = {"pos": pos, "inward": inward, "inner": pos + inward * 0.65, "outer": pos - inward * 0.9}
	return best


func _watch_room_change() -> void:
	if view != "room" or _room_loaded == "" or instant_story: return
	if _transit_active():
		if _transit.phase == "exit":
			if eng.s.room == _room_loaded:
				_transit = {}  # 又折回原房间：不走了
				det_path.clear()
				det_done = Callable()
			else: _transit.to = eng.s.room
		return
	if eng.s.room != _room_loaded: _begin_transit(str(eng.s.room))


## 换房间：先在旧房间里走向通往目的地的门，出门后黑场，再从新房间对应的门走进来。
func _begin_transit(to: String) -> void:
	var from := _room_loaded
	var op := _door_for(room_mesh.design, _room_dir(from, to))
	_transit = {"active": true, "from": from, "to": to, "phase": "exit"}
	var hops: Array = eng.path_to(to, from)
	if hops.size() > 2:
		var names: Array = []
		for i in range(1, hops.size() - 1): names.append(str(data.room_by_id[hops[i]].label))
		_toast("途经：" + "、".join(names))
	det_done = Callable()
	if op.is_empty():
		_transit_swap()
		return
	_go(_route(det_pos, op.inner) + [op.pos, op.outer], _transit_exit_done)


func _transit_exit_done() -> void:
	if not _transit_active(): return
	_transit.phase = "fade"
	_fade(1.0, 0.22, _transit_swap)


func _fade(to_alpha: float, duration: float, cb := Callable()) -> void:
	if _fade_tween != null: _fade_tween.kill()
	_fade_tween = create_tween()
	_fade_tween.tween_property(fade_rect, "modulate:a", to_alpha, duration)
	if cb.is_valid(): _fade_tween.tween_callback(cb)


func _transit_swap() -> void:
	if not _transit_active(): return
	var from: String = _transit.from
	var to: String = _transit.to
	_build_room(to)
	_transit.phase = "enter"
	_fade(0.0, 0.3)
	var op := _door_for(room_mesh.design, _room_dir(to, from))
	if op.is_empty():
		_det_to_home()
		_transit_done()
		return
	det_pos = op.outer
	det.position = Vector3(det_pos.x, 0.0, det_pos.y)
	det.rotation.y = atan2(op.inward.x, op.inward.y)
	_go([op.pos, op.inner] + _route(op.inner, _home_spot()), _transit_done)


func _transit_done() -> void:
	_transit = {}
	_dirty = true


## 离开房间视图 / 读档 / 关闭时：直接落位，不再演走路。
func _finish_transit_now() -> void:
	if not _transit_active(): return
	if _fade_tween != null: _fade_tween.kill()
	fade_rect.modulate.a = 0.0
	_transit = {}
	if _room_loaded != str(eng.s.room): _build_room(str(eng.s.room))
	_det_to_home()
	_dirty = true


func _on_3d_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb: InputEventMouseButton = event
		if mb.button_index == MOUSE_BUTTON_RIGHT or mb.button_index == MOUSE_BUTTON_MIDDLE:
			_orbit = mb.pressed
		elif mb.button_index == MOUSE_BUTTON_WHEEL_UP: dist = maxf(3.0, dist * 0.92); _update_camera()
		elif mb.button_index == MOUSE_BUTTON_WHEEL_DOWN: dist = minf(_fit_dist * 1.8, dist * 1.08); _update_camera()
		elif mb.button_index == MOUSE_BUTTON_LEFT and mb.pressed:
			var o := cam.project_ray_origin(mb.position)
			var dr := cam.project_ray_normal(mb.position)
			var eid: String = room_mesh.pick_marker(o, dr)
			if eid != "": _inspect_walk(eid)
	elif event is InputEventMouseMotion and _orbit:
		var mm: InputEventMouseMotion = event
		az -= mm.relative.x * 0.008
		pitch = clampf(pitch + mm.relative.y * 0.006, 0.18, 1.45)
		_update_camera()


# ───────────────────────── 主循环 ─────────────────────────
func _process(delta: float) -> void:
	var now := Time.get_ticks_msec() / 1000.0
	_pump_subtitles(now)
	# 台词在播、侦探在走路时，故事时间冻结：玩家始终看得见「发生了什么」
	var frozen := not instant_story and (_transit_active() or _story_busy())
	if not frozen: eng.tick(delta)
	_watch_room_change()
	_walk_step(delta)
	_auto_search_step(delta)
	if toast.visible and now > _toast_until: toast.visible = false
	for n in eng.notices:
		if now - n.at / 1000.0 < 0.2: _toast(n.text)
	var c: Dictionary = eng.clock()
	top_clock.text = "第 %d 天  %s  %s" % [c.day, c.text, DayNight.label(c.hour)]
	var hold_msg: String = eng.hold_text()
	top_phase.text = hold_msg if hold_msg != "" else "%s · %s" % [eng.phase().title, eng.phase().sub]
	play_btn.text = "继续" if not eng.s.playing else "暂停"
	map_view.hour = c.hour
	_light_cd -= delta
	if _light_cd <= 0.0:
		_light_cd = 0.25
		if view == "room":
			DayNight.apply(c.hour, sun, env, room_mesh.lamps, room_mesh.glow_materials)
		map_view.queue_redraw()
	_music_cd -= delta
	if _music_cd <= 0.0:
		_music_cd = 1.0
		score.set_state(eng.music_state())
	_autosave_cd -= delta
	if _autosave_due and _autosave_cd <= 0.0:
		_autosave_due = false
		_autosave_cd = 2.0
		_write_auto()
	_panel_cd -= delta
	if _dirty and _panel_cd <= 0.0:
		_dirty = false
		_panel_cd = 0.2
		_refresh()
	elif view == "map" and Engine.get_process_frames() % 30 == 0:
		_refresh_left()


# ───────────────────────── 面板 ─────────────────────────
func _name_bb(id: String) -> String:
	if not data.actor_by_id.has(id): return id
	var a: Dictionary = data.actor_by_id[id]
	return "[color=%s]%s[/color]" % [Color(str(a.color)).lightened(0.55).to_html(false), a.name]


func _sync_speed_pick() -> void:
	var idx := 2
	for i in speed_pick.item_count:
		if is_equal_approx(float(speed_pick.get_item_metadata(i)), float(eng.s.speed)): idx = i
	speed_pick.select(idx)


## 侦探空闲时自己搜证：先搜完所在房间，再去查被挂起的推演还缺的证物。
func _auto_search_step(delta: float) -> void:
	_auto_cd -= delta
	if _auto_cd > 0.0 or not auto_search or instant_story: return
	var s: Dictionary = eng.s
	if s.ending != "" or s.waiting or not s.playing or modal.visible or _transit_active() or _story_busy(): return
	if view == "room" and (s.room != _room_loaded or det == null): return
	_auto_cd = 0.7
	var eid: String = eng.next_search_target()
	if eid == "": return
	if str(data.evidence_by_id[eid].room) == s.room: _inspect_walk(eid)
	else: eng.enter_room(str(data.evidence_by_id[eid].room))


func _refresh() -> void:
	_sync_speed_pick()
	_ensure_room_if_needed()
	_refresh_left()
	_refresh_right()
	_sync_modal()
	map_view.selected = map_view.selected if map_view.selected != "" else eng.s.room
	map_view.queue_redraw()


func _ensure_room_if_needed() -> void:
	if view == "room" and not _transit_active():
		_ensure_room()
		_sync_figures()


func _refresh_left() -> void:
	var rid: String = eng.s.room
	var r: Dictionary = data.room_by_id[rid]
	left_text.clear()
	left_text.append_text("[color=#e9c98a][b]%s[/b][/color]  [color=#a8957b]%s · %s区[/color]\n[color=#a8957b]%s[/color]\n" % [r.label, r.floor, r.zone, r.note])
	var here: Array = eng.actors_in_room(rid).filter(func(i): return str(i) != "detective")
	left_text.append_text("[color=#b89758]在场：[/color]" + ("、".join(here.map(func(i): return _name_bb(str(i)))) if not here.is_empty() else "无人"))
	if view == "map" and map_view.selected != "" and map_view.selected != rid:
		var sr: Dictionary = data.room_by_id[map_view.selected]
		left_text.append_text("\n[color=#4f9dde]选中：%s（双击进入）[/color]" % sr.label)
	for c in left_actions.get_children(): c.queue_free()
	var h := Label.new()
	h.text = "出口"
	h.add_theme_color_override("font_color", BRASS)
	left_actions.add_child(h)
	for dr in data.doors:
		var other := ""
		if dr.a == rid: other = dr.b
		elif dr.b == rid: other = dr.a
		if other == "": continue
		var ok: bool = eng.unlocked(dr)
		var b := Button.new()
		b.text = "%s → %s%s" % [dr.get("label", ""), data.room_by_id[other].label, "" if ok else "（锁）"]
		b.disabled = not ok
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.clip_text = true
		b.focus_mode = Control.FOCUS_NONE
		b.pressed.connect(func(): eng.enter_room(other))
		left_actions.add_child(b)
	var evs: Array = data.evidence_by_room.get(rid, [])
	if not evs.is_empty():
		var h2 := Label.new()
		h2.text = "本房证物"
		h2.add_theme_color_override("font_color", BRASS)
		left_actions.add_child(h2)
		for e in evs:
			var got: bool = eng.s.evidence.has(e.id)
			var b2 := Button.new()
			b2.text = ("✓ " if got else "· ") + str(e.label)
			b2.alignment = HORIZONTAL_ALIGNMENT_LEFT
			b2.clip_text = true
			b2.focus_mode = Control.FOCUS_NONE
			b2.pressed.connect(func(): _inspect_walk(str(e.id)))
			left_actions.add_child(b2)


func _refresh_right() -> void:
	var s: Dictionary = eng.s
	var author: bool = s.author_view
	# 日志
	tab_log.clear()
	for i in range(maxi(0, s.log.size() - 80), s.log.size()):
		var l: Dictionary = s.log[i]
		var t: float = l.t
		var tm := "%02d:%02d" % [int(fposmod(t, 1440.0) / 60.0), int(fmod(t, 60.0))]
		var col := "#efe6d6"
		match str(l.kind):
			"beat": col = "#e9c98a"
			"confront": col = "#ea9c8c"
			"knowledge": col = "#d1b3ef"
			"evidence": col = "#a8c89a"
		tab_log.append_text("[color=#a8957b]D%d %s[/color] [color=%s]%s[/color]\n" % [int(t / 1440.0) + 1, tm, col, l.text])
	tab_log.scroll_to_line(maxi(0, tab_log.get_line_count() - 1))
	# 证物
	tab_ev.clear()
	if s.evidence.is_empty(): tab_ev.append_text("[color=#a8957b]尚未取得证物。到各房间里找发光的标记。[/color]")
	for eid in s.evidence:
		var e: Dictionary = data.evidence_by_id[eid]
		var r: Dictionary = eng.read_evidence(eid)
		tab_ev.append_text("[color=#e9c98a][b]%s[/b][/color]  [color=#a8957b]%s[/color]\n%s\n" % [e.label, data.room_by_id[e.room].label, r.text])
		if not r.correct:
			tab_ev.append_text("[color=#ea9c8c]· 这一读法不一定对——似乎还缺一块知识。[/color]\n")
			if author:
				tab_ev.append_text("[color=#6b3fa0]【作者】缺：%s[/color]\n" % "、".join(r.need.map(func(k): return str(data.know_by_id[k].title))))
		tab_ev.append_text("\n")
	# 知识
	tab_know.clear()
	tab_know.append_text("[color=#a8957b]源质知识：第一章全员缺失。补齐后，旧证物会改读。[/color]\n\n")
	for k in data.knowledge:
		if s.knowledge.has(k.id):
			tab_know.append_text("[color=#d1b3ef][b]%s[/b][/color]\n%s\n\n" % [k.title, k.text])
		elif author:
			tab_know.append_text("[color=#6b3fa0]（未得）%s —— 解锁：%s[/color]\n\n" % [k.title, k.unlock])
	# 词义
	var term := str(term_pick.get_item_metadata(maxi(0, term_pick.selected)))
	var td: Dictionary = data.terms[term]
	tab_lex.clear()
	tab_lex.append_text("[color=#e9c98a][b]%s[/b][/color]\n[color=#a8957b]%s[/color]\n\n" % [td.word, td.note if author else "同一个词，在不同人脑里是不同的事实。"])
	var shown := 0
	for a in data.actors:
		if a.id == "demon" and not author: continue
		var known := author
		if not known:
			for cid in s.conflicts:
				var c: Dictionary = data.conflict_by_id[cid]
				if c.word == term and c.parties.has(a.id): known = true
		if known:
			shown += 1
			tab_lex.append_text("%s：%s\n" % [_name_bb(str(a.id)), data.sense_label(str(a.id), term)])
	if shown == 0:
		tab_lex.append_text("[color=#a8957b]（还没有人对这个词产生过分歧。期待落空之前，谁也听不出差别。）[/color]")
	# 关系
	tab_rel.clear()
	for k in s.relations:
		var rel: Dictionary = s.relations[k]
		var pr := str(k).split("|")
		var bar := "█".repeat(int(rel.trust / 10.0)) + "░".repeat(10 - int(rel.trust / 10.0))
		tab_rel.append_text("%s ↔ %s  [color=%s]%s %d%s[/color]\n" % [_name_bb(pr[0]), _name_bb(pr[1]), "#ea9c8c" if rel.trust < 40 else "#a8c89a", bar, int(rel.trust), "  永久受损" if rel.permanent else ""])
		for g in rel.grievances:
			tab_rel.append_text("[color=#a8957b]　　%s[/color]\n" % g.text)
	if s.irreparable:
		tab_rel.append_text("\n[color=#ea9c8c]第一天的真话被各自听成不同事实；事后查明真相也不会复原这几条。[/color]")
	# 调试
	tab_author.clear()
	if not author:
		tab_author.append_text("[color=#a8957b]打开顶栏「作者视角」后，这里显示判定依据。正常游玩不会出现这些内容。[/color]")
	else:
		for i in range(maxi(0, s.debug_log.size() - 60), s.debug_log.size()):
			var dl: Dictionary = s.debug_log[i]
			tab_author.append_text("[color=#6b3fa0][%s][/color] %s\n" % [dl.kind, dl.text])


# ───────────────────────── 模态：推演 / 争执 / 抉择 / 结局 ─────────────────────────
func _clear_modal() -> void:
	for c in modal.get_children(): c.queue_free()


func _modal_shell(title: String, sub: String) -> VBoxContainer:
	_clear_modal()
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.62)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	modal.add_child(dim)
	var pc := PanelContainer.new()
	pc.add_theme_stylebox_override("panel", _style(Color("#eae0c4"), BRASS, 6, 18))
	pc.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	pc.custom_minimum_size = Vector2(620, 0)
	pc.grow_horizontal = Control.GROW_DIRECTION_BOTH
	pc.grow_vertical = Control.GROW_DIRECTION_BOTH
	modal.add_child(pc)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 8)
	pc.add_child(v)
	var t := Label.new()
	t.text = title
	t.add_theme_font_size_override("font_size", 22)
	t.add_theme_color_override("font_color", Color("#7a3a24"))
	v.add_child(t)
	if sub != "":
		var s := Label.new()
		s.text = sub
		s.add_theme_color_override("font_color", Color("#5a4a38"))
		s.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		v.add_child(s)
	modal.visible = true
	return v


func _ink_label(parent: Node, text: String, size := 15) -> Label:
	var l := Label.new()
	l.text = text
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.add_theme_color_override("font_color", INK)
	l.add_theme_font_size_override("font_size", size)
	parent.add_child(l)
	return l


func _sync_modal() -> void:
	# 台词没播完、侦探还在走路时先不弹窗；播完后会重新触发刷新
	if not instant_story and (_transit_active() or _story_busy()): return
	var s: Dictionary = eng.s
	var key := ""
	if s.ending != "": key = "end:" + s.ending
	elif not s.pending_deduction.is_empty(): key = "ded:" + str(s.pending_deduction.id)
	elif s.pending_conflict != "": key = "con:" + str(s.pending_conflict)
	elif not s.pending_choice.is_empty(): key = "cho:" + str(s.pending_choice.beat_id)
	if key == _modal_key: return
	_modal_key = key
	if key == "":
		modal.visible = false
		_clear_modal()
		return
	if key.begins_with("ded:"): _modal_deduction(str(s.pending_deduction.id))
	elif key.begins_with("con:"): _modal_conflict(str(s.pending_conflict))
	elif key.begins_with("cho:"): _modal_choice()
	else: _modal_ending()


func _modal_deduction(did: String) -> void:
	var dd: Dictionary = data.deduction_by_id[did]
	var v := _modal_shell("案卷推演 · " + str(dd.title), str(dd.prompt))
	var checks: Dictionary = {}
	_ink_label(v, "手头的证物（勾选用作依据）：", 13)
	for eid in dd.evidence:
		var cb := CheckBox.new()
		var have: bool = eng.s.evidence.has(eid)
		cb.text = str(data.evidence_by_id[eid].label) if have else "（尚未取得）"
		cb.disabled = not have
		cb.button_pressed = have
		cb.add_theme_color_override("font_color", INK)
		cb.add_theme_color_override("font_disabled_color", Color("#8a7a68"))
		v.add_child(cb)
		checks[eid] = cb
	_ink_label(v, "哪一种先后更说得通？", 13)
	for h in dd.hypotheses:
		var b := Button.new()
		b.text = str(h.label)
		b.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.pressed.connect(func():
			var picked: Array = []
			for k in checks:
				if checks[k].button_pressed and not checks[k].disabled: picked.append(k)
			eng.solve_deduction(did, str(h.id), picked))
		v.add_child(b)


func _modal_conflict(cid: String) -> void:
	var c: Dictionary = data.conflict_by_id[cid]
	var v := _modal_shell("争执 · " + str(c.title), "第 %d 天 · 在场：%s" % [int(c.day), "、".join(c.parties.map(func(i): return data.actor_name(str(i))))])
	for ln in c.lines:
		var who: String = ln[0]
		var l := _ink_label(v, "%s：%s" % [data.actor_name(who), ln[1]])
		if data.actor_by_id.has(who): l.add_theme_color_override("font_color", Color(str(data.actor_by_id[who].color)).darkened(0.25))
	if eng.s.author_view:
		var term: Dictionary = data.terms[c.word]
		var txt := "【作者】关键词「%s」——" % term.word
		for sn in eng.conflict_senses(cid): txt += "%s=%s；" % [sn.name, sn.sense]
		var al := _ink_label(v, txt, 12)
		al.add_theme_color_override("font_color", Color("#6b3fa0"))
	_ink_label(v, "你要怎么回应？", 13)
	for o in eng.conflict_options(cid):
		var b := Button.new()
		b.text = str(o.label)
		b.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.pressed.connect(func(): eng.resolve_conflict(cid, str(o.id)))
		v.add_child(b)
	if not c.get("permanent", false):
		var d := Button.new()
		d.text = "先搁下（义项分歧照旧落空）"
		d.pressed.connect(func(): eng.resolve_conflict(cid, "", true))
		v.add_child(d)


func _modal_choice() -> void:
	var pc: Dictionary = eng.s.pending_choice
	var v := _modal_shell(str(pc.choice.prompt), "")
	for o in pc.choice.options:
		var b := Button.new()
		b.text = str(o.label)
		b.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.pressed.connect(func(): eng.choose(str(pc.beat_id), str(o.id)))
		v.add_child(b)


func _modal_ending() -> void:
	var e: Dictionary = data.endings[eng.s.ending]
	var v := _modal_shell(str(e.title), "")
	_ink_label(v, str(e.text), 16)
	_ink_label(v, "知识 %d/%d · 证物 %d/%d · %s" % [eng.knowledge_count(), data.knowledge.size(), eng.s.found_count, data.evidence.size(), "有不可弥合的裂痕" if eng.s.irreparable else "没有无法回头的关系"], 13)
	var row := HBoxContainer.new()
	v.add_child(row)
	_btn(row, "重新开始", func():
		eng.new_game()
		_modal_key = ""
		_sub_queue.clear()
		_finish_transit_now()
		_room_loaded = ""
		_ensure_room())
	_btn(row, "返回", func(): _close())
