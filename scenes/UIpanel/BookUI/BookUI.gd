extends Control
## 书本检视器：书页界面渲染在 SubViewport 里，映射到书房舞台的 3D 对开页上；切换页面即翻动书页。
## 翻动方向由 PAGES 的排序决定：往后的页向左翻，往前的页向右翻。
## 舞台接口见 StudyDeskStage3D 的 public API；会话操作经 Main（host）提交。

signal closed
signal page_changed(page_id: String)

const Sound := preload("res://scenes/components/shared/Sound.gd")
const BODY_FONT := preload("res://assets/external/NotoSerifSC/NotoSerifSC.ttf")
const HEADING_FONT := preload("res://assets/external/yujisyuku/YujiSyuku-Regular.ttf")
const PAGES := [
	{"id": "journal", "title": "手记", "node": "JournalPage", "color": Color("6a413c")},
	{"id": "gallery", "title": "图录", "node": "GalleryPage", "color": Color("6a413c")},
	{"id": "save", "title": "存档", "node": "SavePage", "color": Color("505c65")},
	{"id": "settings", "title": "设置", "node": "SettingsPage", "color": Color("6d6f4f")},
]
const LEFT_HALF := Rect2(0.0, 0.0, 0.5, 1.0)
const RIGHT_HALF := Rect2(0.5, 0.0, 0.5, 1.0)
const INK := Color("2b1d14")
const ACCENT := Color("7a2318")
const FAINT := Color(0.24, 0.15, 0.10, 0.85)
const CREAM := Color("f1e6cc")
const NUMERALS := ["一", "二", "三", "四", "五", "六", "七", "八", "九", "十"]

@onready var page_viewport: SubViewport = $PageViewport
@onready var spread: Control = $PageViewport/Spread
@onready var pages_root: Control = $PageViewport/Spread/Pages
@onready var chrome: Control = $PageViewport/Spread/Chrome
@onready var tabs: HBoxContainer = $PageViewport/Spread/Chrome/Tabs
@onready var close_button: Button = $PageViewport/Spread/Chrome/CloseButton
@onready var prev_button: Button = $PageViewport/Spread/Chrome/PrevButton
@onready var next_button: Button = $PageViewport/Spread/Chrome/NextButton
@onready var left_folio: Label = $PageViewport/Spread/Chrome/LeftFolio
@onready var right_folio: Label = $PageViewport/Spread/Chrome/RightFolio

var stage: Node3D
var host: Node
var current := -1
var is_open := false
var in_field := false
var _busy := false
var _tab_buttons: Array[Button] = []
var _snapshot: ImageTexture

func _ready() -> void:
	var journal := preload("res://scenes/UIpanel/BookUI/JournalUI.gd").new()
	journal.name = "JournalPage"
	pages_root.add_child(journal)
	journal.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	# MCP 观察按这个元数据把书页内控件换算到屏幕坐标。
	page_viewport.set_meta("physical_book_view", self)
	spread.theme = _build_theme()
	chrome.draw.connect(_draw_chrome)
	for index in PAGES.size():
		var tab := Button.new()
		tab.text = PAGES[index].title
		tab.toggle_mode = true
		tab.focus_mode = Control.FOCUS_NONE
		tab.custom_minimum_size = Vector2(96, 0)
		tab.pressed.connect(goto_index.bind(index))
		_style_tab(tab, PAGES[index].color)
		tabs.add_child(tab)
		_tab_buttons.append(tab)
	close_button.pressed.connect(close)
	prev_button.pressed.connect(func(): goto_index(current - 1))
	next_button.pressed.connect(func(): goto_index(current + 1))
	for index in PAGES.size(): _page(index).visible = false

func configure(desk_stage: Node3D, main_host: Node) -> void:
	stage = desk_stage
	host = main_host
	stage.set_spread_texture(page_viewport.get_texture())
	for index in PAGES.size():
		var page := _page(index)
		if page.has_method("bind"): page.bind(host)

func page_id() -> String:
	return str(PAGES[current].id) if current >= 0 else ""

func busy() -> bool:
	return _busy

## 推镜并翻开书本，直接停在指定页面。
func open(id: String, from_field := false) -> void:
	if is_open or _busy or stage == null: return
	is_open = true
	in_field = from_field
	_busy = true
	page_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	_show_page(maxi(0, index_of(id)))
	stage.freeze_spread(null, false, false)
	Sound.sfx("page", -8.0, 0.72)
	await stage.open_sequence()
	_busy = false

## 合上书本并拉回镜头，结束后发出 closed。
func close() -> void:
	if not is_open or _busy: return
	_busy = true
	Sound.sfx("page", -8.0, 0.66)
	await stage.close_sequence()
	_finish_close()
	closed.emit()

## 不播放动画直接合上（读档切换现场时使用），不发出 closed。
func close_immediately() -> void:
	if not is_open: return
	stage.snap_closed()
	_finish_close()

func goto_page(id: String) -> void:
	goto_index(index_of(id))

func index_of(id: String) -> int:
	for index in PAGES.size():
		if PAGES[index].id == id: return index
	return -1

func goto_index(index: int) -> void:
	_sync_tabs()
	if not is_open or _busy or index < 0 or index >= PAGES.size() or index == current: return
	_busy = true
	var forward := index > current
	await RenderingServer.frame_post_draw
	_snapshot = ImageTexture.create_from_image(page_viewport.get_texture().get_image())
	var live := page_viewport.get_texture()
	# 冻结、准备书叶与切换页面在同一帧完成，屏幕上不会闪出新页。
	if forward:
		stage.freeze_spread(_snapshot, true, false)
		stage.prepare_leaf(true, _snapshot, RIGHT_HALF, live, LEFT_HALF)
	else:
		stage.freeze_spread(_snapshot, false, true)
		stage.prepare_leaf(false, live, RIGHT_HALF, _snapshot, LEFT_HALF)
	_show_page(index)
	Sound.sfx("page", -3.0, randf_range(0.92, 1.08))
	await stage.play_leaf()
	stage.freeze_spread(null, false, false)
	_snapshot = null
	_busy = false

## Main 在书本打开时把全部输入交给这里。返回 true 表示已处理。
func route_input(event: InputEvent) -> bool:
	if not is_open: return false
	if _busy: return true
	if event.is_action_pressed("cancel") or event.is_action_pressed("ui_cancel"):
		close()
		return true
	if event.is_action_pressed("book_prev"):
		goto_index(current - 1)
		return true
	if event.is_action_pressed("book_next"):
		goto_index(current + 1)
		return true
	if event is InputEventMouseButton and event.pressed and event.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN] and _wheel_turns_pages():
		goto_index(current + (1 if event.button_index == MOUSE_BUTTON_WHEEL_DOWN else -1))
		return true
	if event is InputEventMouse:
		var uv: Vector2 = stage.screen_to_page_uv(event.position)
		var local: InputEventMouse = event.duplicate()
		var point := uv * Vector2(page_viewport.size) if uv.x >= 0.0 else Vector2(-4096.0, -4096.0)
		local.position = point
		local.global_position = point
		page_viewport.push_input(local)
		return true
	page_viewport.push_input(event)
	return true

## MCP：书页内控件是否可见可用。
func is_active() -> bool:
	return is_open and not _busy

## MCP：书页内控件在屏幕上的外接矩形。
func screen_rect_for_control(control: Control, clipped := Rect2()) -> Rect2:
	var rect := clipped if clipped.has_area() else control.get_global_rect()
	var size := Vector2(page_viewport.size)
	var result := Rect2()
	var corners := [rect.position, Vector2(rect.end.x, rect.position.y), rect.end, Vector2(rect.position.x, rect.end.y)]
	for index in corners.size():
		var screen: Vector2 = stage.page_uv_to_screen(corners[index] / size)
		result = Rect2(screen, Vector2.ZERO) if index == 0 else result.expand(screen)
	return result

func _show_page(index: int) -> void:
	current = index
	for page_index in PAGES.size():
		_page(page_index).visible = page_index == index
	_sync_tabs()
	prev_button.disabled = index <= 0
	next_button.disabled = index >= PAGES.size() - 1
	left_folio.text = "— %s —" % NUMERALS[(index * 2) % NUMERALS.size()]
	right_folio.text = "— %s —" % NUMERALS[(index * 2 + 1) % NUMERALS.size()]
	close_button.text = "合上案卷"
	var page := _page(index)
	if page.has_method("on_page_shown"): page.on_page_shown()
	page_changed.emit(page_id())

func _sync_tabs() -> void:
	for index in _tab_buttons.size():
		_tab_buttons[index].set_pressed_no_signal(index == current)

func _finish_close() -> void:
	is_open = false
	_busy = false
	page_viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED

func _page(index: int) -> Control:
	return pages_root.get_node(str(PAGES[index].node))

func _wheel_turns_pages() -> bool:
	var settings := get_node_or_null("/root/GameSettings")
	return settings != null and str(settings.get_value("controls", "wheel_mode")) == "pages"

func _draw_chrome() -> void:
	for page in [Rect2(56.0, 58.0, 652.0, 868.0), Rect2(792.0, 58.0, 652.0, 868.0)]:
		chrome.draw_rect(page, Color(INK, 0.30), false, 2.0)
		chrome.draw_rect(page.grow(-9.0), Color(INK, 0.16), false, 1.0)
		for y in [page.position.y, page.end.y]:
			var center := Vector2(page.get_center().x, y)
			chrome.draw_colored_polygon(PackedVector2Array([center + Vector2(0, -8), center + Vector2(14, 0), center + Vector2(0, 8), center + Vector2(-14, 0)]), Color(ACCENT, 0.75))

func _build_theme() -> Theme:
	var theme := Theme.new()
	var body := FontVariation.new()
	body.base_font = BODY_FONT
	body.variation_embolden = 0.55
	theme.default_font = body
	theme.default_font_size = 25
	theme.set_color("font_color", "Label", INK)
	theme.set_color("font_color", "Button", INK)
	theme.set_color("font_focus_color", "Button", INK)
	theme.set_color("font_hover_color", "Button", ACCENT)
	theme.set_color("font_pressed_color", "Button", ACCENT)
	theme.set_color("font_hover_pressed_color", "Button", ACCENT)
	theme.set_color("font_disabled_color", "Button", Color(INK, 0.3))
	theme.set_stylebox("normal", "Button", _style(Color(INK, 0.0)))
	theme.set_stylebox("hover", "Button", _style(Color(INK, 0.08)))
	theme.set_stylebox("pressed", "Button", _style(Color(ACCENT, 0.13)))
	theme.set_stylebox("hover_pressed", "Button", _style(Color(ACCENT, 0.18)))
	theme.set_stylebox("disabled", "Button", _style(Color(INK, 0.0)))
	var focus := StyleBoxFlat.new()
	focus.draw_center = false
	focus.border_color = Color(ACCENT, 0.7)
	focus.border_width_bottom = 2
	theme.set_stylebox("focus", "Button", focus)
	theme.set_type_variation("HeaderLabel", "Label")
	theme.set_font("font", "HeaderLabel", HEADING_FONT)
	theme.set_font_size("font_size", "HeaderLabel", 60)
	theme.set_type_variation("CaptionLabel", "Label")
	theme.set_font_size("font_size", "CaptionLabel", 22)
	theme.set_color("font_color", "CaptionLabel", FAINT)
	theme.set_type_variation("GroupLabel", "Label")
	theme.set_font_size("font_size", "GroupLabel", 23)
	theme.set_color("font_color", "GroupLabel", ACCENT)
	var track := StyleBoxFlat.new()
	track.bg_color = Color(INK, 0.22)
	track.content_margin_top = 3.0
	track.content_margin_bottom = 3.0
	track.set_corner_radius_all(3)
	var filled := track.duplicate() as StyleBoxFlat
	filled.bg_color = Color(ACCENT, 0.75)
	theme.set_stylebox("slider", "HSlider", track)
	theme.set_stylebox("grabber_area", "HSlider", filled)
	theme.set_stylebox("grabber_area_highlight", "HSlider", filled)
	theme.set_icon("grabber", "HSlider", _dot(ACCENT, 11))
	theme.set_icon("grabber_highlight", "HSlider", _dot(ACCENT.lightened(0.2), 12))
	theme.set_icon("grabber_disabled", "HSlider", _dot(Color(INK, 0.3), 11))
	return theme

func _style_tab(tab: Button, color: Color) -> void:
	for state in ["normal", "hover", "pressed", "hover_pressed", "focus"]:
		var box := StyleBoxFlat.new()
		var raised: bool = state in ["pressed", "hover_pressed"]
		box.bg_color = color.lightened(0.12 if state.begins_with("hover") else 0.0) if state != "focus" else Color.TRANSPARENT
		box.corner_radius_bottom_left = 8
		box.corner_radius_bottom_right = 8
		box.content_margin_top = 18.0 if raised else 6.0
		box.content_margin_bottom = 10.0
		box.content_margin_left = 14.0
		box.content_margin_right = 14.0
		box.shadow_color = Color(0, 0, 0, 0.25)
		box.shadow_size = 2
		tab.add_theme_stylebox_override(state, box)
	for state in ["font_color", "font_hover_color", "font_pressed_color", "font_hover_pressed_color", "font_focus_color"]:
		tab.add_theme_color_override(state, CREAM)
	tab.add_theme_font_size_override("font_size", 22)

static func _style(color: Color) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = color
	box.set_corner_radius_all(6)
	box.content_margin_left = 12.0
	box.content_margin_right = 12.0
	box.content_margin_top = 4.0
	box.content_margin_bottom = 4.0
	return box

static func _dot(color: Color, radius: int) -> ImageTexture:
	var size := radius * 2 + 2
	var image := Image.create(size, size, false, Image.FORMAT_RGBA8)
	var center := Vector2(size, size) * 0.5
	for y in size:
		for x in size:
			var alpha := clampf(float(radius) + 0.5 - Vector2(x + 0.5, y + 0.5).distance_to(center), 0.0, 1.0)
			image.set_pixel(x, y, Color(color, color.a * alpha))
	return ImageTexture.create_from_image(image)
