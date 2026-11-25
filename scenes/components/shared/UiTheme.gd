extends RefCounted
## Unified 1900s Academy UI design tokens shared across HUD, command wheel,
## captions, manual, and rule cards.

const ACCENT := Color("ffbf75")
const ACCENT_SOFT := Color("e8d4b0")
const INK := Color("221c16")
const PANEL_BG := Color(0.045, 0.04, 0.035, 0.72)
const PANEL_BG_DEEP := Color(0.038, 0.033, 0.028, 0.84)
const PARCHMENT := Color("e3cda2")
const PARCHMENT_BORDER := Color("63472b")
const PARCHMENT_INK := Color("31241a")
const TEXT_MAIN := Color("f4ead8")
const TEXT_MUTED := Color("b9a68a")
const WARN := Color("ffcf9a")
const DANGER := Color("ff6a4d")
const DANGER_OUTLINE := Color("2a0b06")
const QUIET := Color("9fd6e8")

static func make_font() -> Font:
	var font := SystemFont.new()
	font.font_names = PackedStringArray(["Microsoft YaHei UI", "PingFang SC", "Noto Sans CJK SC", "DejaVu Sans"])
	if Engine.has_meta("review_font"):
		font.fallbacks = [Engine.get_meta("review_font")]
	return font

static func panel_box(color: Color = PANEL_BG, radius: int = 3, margin := Vector2(14, 9), border_left: int = 0, border_right: int = 0, border_color: Color = ACCENT) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = color
	s.set_corner_radius_all(radius)
	s.content_margin_left = margin.x
	s.content_margin_right = margin.x
	s.content_margin_top = margin.y
	s.content_margin_bottom = margin.y
	if border_left > 0 or border_right > 0:
		s.border_color = border_color
		s.border_width_left = border_left
		s.border_width_right = border_right
	s.shadow_color = Color(0, 0, 0, 0.35)
	s.shadow_size = 8
	return s

static func style_label(label: Label, font: Font, size: int = 15, color: Color = TEXT_MAIN, outline: int = 4) -> void:
	label.add_theme_font_override("font", font)
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_color_override("font_color", color)
	if outline > 0:
		label.add_theme_constant_override("outline_size", outline)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE

## Dark translucent chip with an accent edge on hover, matching the HUD card.
static func style_button(button: Button, font: Font, size: int = 15) -> void:
	button.add_theme_font_override("font", font)
	button.add_theme_font_size_override("font_size", size)
	button.add_theme_color_override("font_color", TEXT_MAIN)
	button.add_theme_color_override("font_hover_color", ACCENT)
	button.add_theme_color_override("font_pressed_color", ACCENT)
	button.add_theme_color_override("font_disabled_color", Color(TEXT_MUTED, 0.55))
	button.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.8))
	button.add_theme_constant_override("outline_size", 3)
	var margin := Vector2(14, 7)
	button.add_theme_stylebox_override("normal", panel_box(PANEL_BG, 3, margin, 3, 0, Color(ACCENT, 0.45)))
	button.add_theme_stylebox_override("hover", panel_box(PANEL_BG_DEEP, 3, margin, 3, 0, ACCENT))
	button.add_theme_stylebox_override("pressed", panel_box(Color(0.10, 0.075, 0.05, 0.9), 3, margin, 3, 0, ACCENT))
	button.add_theme_stylebox_override("disabled", panel_box(Color(PANEL_BG, 0.45), 3, margin, 3, 0, Color(TEXT_MUTED, 0.3)))
	button.add_theme_stylebox_override("focus", StyleBoxEmpty.new())

## Button on a parchment page: ink text, a thin brown rule, accent wash on hover.
static func style_paper_button(button: Button, font: Font, size: int = 16) -> void:
	button.add_theme_font_override("font", font)
	button.add_theme_font_size_override("font_size", size)
	for state in ["font_color", "font_hover_color", "font_pressed_color"]:
		button.add_theme_color_override(state, PARCHMENT_INK)
	button.add_theme_color_override("font_disabled_color", Color(PARCHMENT_INK, 0.4))
	button.alignment = HORIZONTAL_ALIGNMENT_LEFT
	for state in ["normal", "hover", "pressed", "disabled"]:
		var s := StyleBoxFlat.new()
		s.bg_color = {"normal": Color(PARCHMENT_BORDER, 0.08), "hover": Color(ACCENT, 0.42), "pressed": Color(ACCENT, 0.6), "disabled": Color(PARCHMENT_BORDER, 0.03)}[state]
		s.border_color = Color(PARCHMENT_BORDER, 0.55 if state != "disabled" else 0.2)
		s.border_width_left = 3
		s.set_corner_radius_all(2)
		s.content_margin_left = 14
		s.content_margin_right = 14
		s.content_margin_top = 6
		s.content_margin_bottom = 6
		button.add_theme_stylebox_override(state, s)
	button.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
