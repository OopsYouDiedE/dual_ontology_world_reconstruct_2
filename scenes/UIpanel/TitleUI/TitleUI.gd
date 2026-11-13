extends Control
## 标题界面：右侧书名与菜单，左侧留给书房 3D 场景。点击桌上的书由 Main 判定。
## 只发出意图信号，由 Main 决定开局、读档或打开书本检视器的哪一页。

signal new_game_requested
signal continue_requested
signal book_requested(page_id: String)
signal quit_requested
signal builder_requested
signal campaign_requested
signal dual_world_requested

const TITLE_FONT := preload("res://assets/external/yujisyuku/YujiSyuku-Regular.ttf")
const BODY_FONT := preload("res://assets/external/NotoSerifSC/NotoSerifSC.ttf")
const LATIN_FONT := preload("res://assets/external/Almendra/Almendra-Regular.ttf")
const Sound := preload("res://scenes/components/shared/Sound.gd")
const CREAM := Color("eadcbd")
const GOLD := Color("c9a45c")
const EMBER := Color("e0794a")

@onready var shade: TextureRect = $Shade
@onready var menu: VBoxContainer = $Menu
@onready var rule: TextureRect = $Menu/Rule
@onready var new_button: Button = $Menu/NewButton
@onready var continue_button: Button = $Menu/ContinueButton
@onready var records_button: Button = $Menu/RecordsButton
@onready var settings_button: Button = $Menu/SettingsButton
@onready var quit_button: Button = $Menu/QuitButton
@onready var hint: Label = $Hint
@onready var fade: ColorRect = $Fade

## 标题显示中、可以接受点击时为 true。
var interactive := false
var _tween: Tween
var _time := 0.0

func _ready() -> void:
	theme = _build_theme()
	var gradient := Gradient.new()
	gradient.offsets = PackedFloat32Array([0.0, 0.5, 1.0])
	gradient.colors = PackedColorArray([Color(GOLD, 0.0), GOLD, Color(GOLD, 0.0)])
	var line := GradientTexture2D.new()
	line.gradient = gradient
	line.width = 256
	line.height = 2
	rule.texture = line
	new_button.pressed.connect(_emit.bind(new_game_requested))
	continue_button.pressed.connect(_emit.bind(continue_requested))
	records_button.pressed.connect(func(): _emit_book("journal"))
	settings_button.pressed.connect(func(): _emit_book("settings"))
	quit_button.pressed.connect(_emit.bind(quit_requested))
	$Menu/BuilderButton.pressed.connect(_emit.bind(builder_requested))
	$Menu/CampaignButton.pressed.connect(_emit.bind(campaign_requested))
	$Menu/DualWorldButton.pressed.connect(_emit.bind(dual_world_requested))
	for button: Button in [new_button, continue_button, records_button, $Menu/CampaignButton, $Menu/DualWorldButton, $Menu/BuilderButton, settings_button, quit_button]:
		button.mouse_entered.connect(func(): Sound.sfx("ui_click", -18.0, 1.4))
	modulate.a = 0.0
	hide()

## 显示标题。first=true 时从全黑淡入。
	_install_title_polish()


func show_title(can_continue: bool, first := false) -> void:
	continue_button.disabled = not can_continue
	show()
	interactive = true
	if _tween != null: _tween.kill()
	_tween = create_tween().set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	if first:
		fade.color.a = 1.0
		modulate.a = 1.0
		menu.modulate.a = 0.0
		hint.modulate.a = 0.0
		_tween.tween_property(fade, "color:a", 0.0, 1.8)
		_tween.parallel().tween_property(menu, "modulate:a", 1.0, 1.2).set_delay(0.6)
		_tween.tween_property(hint, "modulate:a", 1.0, 0.8)
	else:
		fade.color.a = 0.0
		menu.modulate.a = 1.0
		hint.modulate.a = 1.0
		_tween.tween_property(self, "modulate:a", 1.0, 0.45)
	(continue_button if can_continue else new_button).grab_focus.call_deferred()

func hide_title(duration := 0.4) -> void:
	interactive = false
	if _tween != null: _tween.kill()
	_tween = create_tween()
	_tween.tween_property(self, "modulate:a", 0.0, duration)
	_tween.tween_callback(hide)

func _process(delta: float) -> void:
	_time += delta
	# 书名像被火光照着一样缓慢明暗。
	var title := $Menu/TitleLabel as Label
	title.add_theme_color_override("font_shadow_color", Color(EMBER, 0.28 + 0.10 * sin(_time * 0.9)))
	hint.self_modulate.a = 0.55 + 0.25 * sin(_time * 1.6)

func _emit(signal_ref: Signal) -> void:
	if not interactive: return
	Sound.sfx("ui_click", -6.0)
	signal_ref.emit()

func _emit_book(page_id: String) -> void:
	if not interactive: return
	Sound.sfx("ui_click", -6.0)
	book_requested.emit(page_id)

func _build_theme() -> Theme:
	var theme := Theme.new()
	theme.default_font = BODY_FONT
	theme.default_font_size = 28
	theme.set_type_variation("TitleLabel", "Label")
	theme.set_font("font", "TitleLabel", TITLE_FONT)
	theme.set_font_size("font_size", "TitleLabel", 92)
	theme.set_color("font_color", "TitleLabel", CREAM)
	theme.set_constant("shadow_offset_x", "TitleLabel", 0)
	theme.set_constant("shadow_offset_y", "TitleLabel", 0)
	theme.set_constant("shadow_outline_size", "TitleLabel", 18)
	theme.set_type_variation("SubtitleLabel", "Label")
	theme.set_font("font", "SubtitleLabel", LATIN_FONT)
	theme.set_font_size("font_size", "SubtitleLabel", 22)
	theme.set_color("font_color", "SubtitleLabel", Color(GOLD, 0.85))
	theme.set_type_variation("HintLabel", "Label")
	theme.set_font_size("font_size", "HintLabel", 20)
	theme.set_color("font_color", "HintLabel", Color(CREAM, 0.8))
	theme.set_color("font_color", "Button", Color(CREAM, 0.82))
	theme.set_color("font_focus_color", "Button", CREAM)
	theme.set_color("font_hover_color", "Button", GOLD)
	theme.set_color("font_pressed_color", "Button", EMBER)
	theme.set_color("font_disabled_color", "Button", Color(CREAM, 0.25))
	theme.set_font_size("font_size", "Button", 30)
	for state in ["normal", "disabled", "pressed"]:
		theme.set_stylebox(state, "Button", _button_style(Color(0, 0, 0, 0)))
	theme.set_stylebox("hover", "Button", _button_style(Color(GOLD, 0.10)))
	theme.set_stylebox("focus", "Button", _button_style(Color(GOLD, 0.06), true))
	return theme

static func _button_style(color: Color, outlined := false) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = color
	box.content_margin_top = 8.0
	box.content_margin_bottom = 8.0
	if outlined:
		box.border_color = Color(GOLD, 0.45)
		box.border_width_bottom = 1
		box.border_width_top = 1
	return box

## 标题润色：暗角与细颗粒（压住书房背景、聚焦书名）、书名下方副题、菜单项悬停放大。
func _install_title_polish() -> void:
	var vignette := ColorRect.new()
	vignette.name = "TitleVignette"
	vignette.set_anchors_preset(Control.PRESET_FULL_RECT)
	vignette.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var shader := Shader.new()
	shader.code = "shader_type canvas_item;\nuniform float strength = 0.6;\nuniform float grain = 0.03;\nfloat h(vec2 p){return fract(sin(dot(p, vec2(12.9898, 78.233))) * 43758.5453);}\nvoid fragment(){\n\tvec2 uv = UV - 0.5;\n\tfloat v = smoothstep(0.3, 0.95, length(uv * vec2(1.3, 1.0)));\n\tfloat n = h(UV * 913.0 + fract(TIME * 7.0)) - 0.5;\n\tCOLOR = vec4(vec3(0.02, 0.015, 0.01) + n * grain, clamp(v * strength + abs(n) * grain, 0.0, 1.0));\n}\n"
	var material := ShaderMaterial.new()
	material.shader = shader
	vignette.material = material
	add_child(vignette)
	move_child(vignette, 0)
	var title := get_node_or_null("Menu/TitleLabel") as Label
	if title != null and title.get_parent() is BoxContainer:
		var tagline := Label.new()
		tagline.name = "Tagline"
		tagline.text = "五人生活推演 · 建筑与主观认知"
		tagline.horizontal_alignment = title.horizontal_alignment
		tagline.add_theme_font_size_override("font_size", 20)
		tagline.add_theme_color_override("font_color", Color(0.88, 0.8, 0.64, 0.8))
		var font := title.get_theme_font("font")
		if font != null: tagline.add_theme_font_override("font", font)
		title.get_parent().add_child(tagline)
		title.get_parent().move_child(tagline, title.get_index() + 1)
	for node in find_children("*", "Button", true, false):
		var button := node as Button
		button.mouse_entered.connect(_on_title_button_hover.bind(button, true))
		button.mouse_exited.connect(_on_title_button_hover.bind(button, false))

func _on_title_button_hover(button: Button, on: bool) -> void:
	if not is_instance_valid(button): return
	button.pivot_offset = Vector2(0.0, button.size.y * 0.5)
	var tween := button.create_tween().set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	tween.tween_property(button, "scale", Vector2.ONE * (1.06 if on else 1.0), 0.14)
