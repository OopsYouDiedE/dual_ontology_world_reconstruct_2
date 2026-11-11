@tool
extends RefCounted
## Plain-paper native controls. The shared book owns geometry and lighting.
## 1890s casebook palette: laid paper, iron-gall ink, oxblood rubrication, brass.
const COLOR_PRIMARY := Color("6d2a20")      # oxblood rubric
const COLOR_ON_PRIMARY := Color("f3ead6")
const COLOR_SURFACE := Color("eadfc6")      # laid paper
const COLOR_SURFACE_VARIANT := Color("dccba6")
const COLOR_ON_SURFACE := Color("2b2219")   # iron-gall ink
const COLOR_OUTLINE := Color("8a7458")
const COLOR_ERROR := Color("8a3b2e")
const COLOR_WARNING := Color("8b6c3a")      # brass
const COLOR_SUCCESS := Color("4a5d43")
const INK_SOFT := Color("5a4a38")
const PAPER_SHADOW := Color(0.08, 0.05, 0.02, 0.35)

static func apply(parent: Control, scale := 1.0) -> void:
	var theme_copy := Theme.new()
	var size_scale: float = clampf(scale, 0.8, 1.8)
	var plain := false
	var contrast := false
	if parent.is_inside_tree():
		var settings: Node = parent.get_node_or_null("/root/GameSettings")
		if settings != null:
			var text_scale: Variant = settings.get_value("accessibility", "text_scale")
			if text_scale != null: size_scale *= float(text_scale)
			var ui_scale: Variant = settings.get_value("graphics", "ui_scale")
			if ui_scale != null: size_scale *= float(ui_scale)
			plain = bool(settings.get_value("accessibility", "plain_fonts"))
			contrast = bool(settings.get_value("accessibility", "high_contrast"))
	var font_path := "res://assets/external/NotoSerifSC/NotoSerifSC.ttf"
	if plain and ResourceLoader.exists("res://assets/external/NotoSansSC/NotoSansSC[wght].ttf"):
		font_path = "res://assets/external/NotoSansSC/NotoSansSC[wght].ttf"
	if ResourceLoader.exists(font_path):
		var font := FontVariation.new()
		font.base_font = load(font_path)
		font.variation_opentype = {TextServerManager.get_primary_interface().name_to_tag("wght"): 420.0}
		theme_copy.default_font = font
		for kind in ["Label", "Button", "OptionButton", "CheckButton", "CheckBox", "LineEdit", "TextEdit", "SpinBox", "PopupMenu", "TooltipLabel"]:
			theme_copy.set_font("font", kind, font)
		for kind in ["normal_font", "bold_font", "italics_font", "bold_italics_font"]:
			theme_copy.set_font(kind, "RichTextLabel", font)
	theme_copy.default_font_size = roundi(24.0 * size_scale)
	var ink := Color("121b16") if contrast else COLOR_ON_SURFACE
	var empty := StyleBoxEmpty.new()
	for type_name in ["PanelContainer", "Panel"]: theme_copy.set_stylebox("panel", type_name, empty)
	for type_name in ["Label", "RichTextLabel", "Button", "OptionButton", "CheckButton", "CheckBox", "LineEdit", "TextEdit", "SpinBox"]:
		theme_copy.set_color("font_color", type_name, ink)
		theme_copy.set_color("default_color", type_name, ink)
		theme_copy.set_color("font_hover_color", type_name, COLOR_PRIMARY)
		theme_copy.set_color("font_focus_color", type_name, ink)
		theme_copy.set_color("font_pressed_color", type_name, COLOR_ON_PRIMARY)
		theme_copy.set_color("font_disabled_color", type_name, Color("75644f"))
		theme_copy.set_font_size("font_size", type_name, theme_copy.default_font_size)
	for type_name in ["Button", "OptionButton", "CheckButton", "CheckBox"]:
		for state in ["normal", "hover", "pressed", "disabled", "focus"]:
			theme_copy.set_stylebox(state, type_name, ledger_button_box(state))
	for type_name in ["LineEdit", "TextEdit"]:
		var edit := _box(Color(0.95,0.93,0.87,0.35), 14, 12)
		edit.border_width_bottom = 1
		edit.border_color = Color("a6ab97")
		theme_copy.set_stylebox("normal", type_name, edit)
		theme_copy.set_stylebox("read_only", type_name, empty)
		theme_copy.set_color("caret_color", type_name, ink)
		theme_copy.set_color("selection_color", type_name, Color(0.35,0.45,0.37,0.22))
	var line := StyleBoxLine.new()
	line.color = Color(0.35,0.40,0.32,0.25)
	line.thickness = 1
	theme_copy.set_stylebox("separator", "HSeparator", line)
	for type_name in ["HSlider", "HScrollBar", "VScrollBar"]:
		theme_copy.set_stylebox("slider", type_name, _box(Color("c9caba"), 0, 2))
		theme_copy.set_stylebox("grabber_area", type_name, _box(COLOR_PRIMARY, 0, 2))
		theme_copy.set_stylebox("grabber_area_highlight", type_name, _box(COLOR_PRIMARY.lightened(0.12), 0, 3))
	var popup := _box(COLOR_SURFACE.lightened(0.035), 12, 10)
	popup.border_color = COLOR_OUTLINE
	popup.set_border_width_all(1)
	theme_copy.set_stylebox("panel", "PopupMenu", popup)
	theme_copy.set_color("font_color", "PopupMenu", ink)
	theme_copy.set_font_size("font_size", "PopupMenu", theme_copy.default_font_size)
	parent.theme = theme_copy

static func _box(color: Color, horizontal := 12.0, vertical := 8.0) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = color
	box.content_margin_left = horizontal
	box.content_margin_right = horizontal
	box.content_margin_top = vertical
	box.content_margin_bottom = vertical
	return box

static func prepare_button(button: BaseButton) -> void:
	button.custom_minimum_size = button.custom_minimum_size.max(Vector2(44, 44))
	button.focus_mode = Control.FOCUS_ALL
	button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND

static func create_card() -> PanelContainer:
	var card := PanelContainer.new()
	card.add_theme_stylebox_override("panel", _box(Color(0,0,0,0), 12, 12))
	return card

static func create_badge(text: String, severity := "info") -> PanelContainer:
	var badge := PanelContainer.new()
	var tint := COLOR_PRIMARY
	if severity in ["critical", "danger", "error"]: tint = COLOR_ERROR
	elif severity == "warning": tint = COLOR_WARNING
	var box := _box(Color(tint, 0.08), 10, 5)
	box.border_width_left = 2
	box.border_color = tint
	badge.add_theme_stylebox_override("panel", box)
	var label := Label.new()
	label.text = text
	label.add_theme_color_override("font_color", tint)
	label.add_theme_font_size_override("font_size", 20)
	badge.add_child(label)
	return badge

## A printed card resting on the desk: paper ground, ink hairline, heavier foot rule.
static func ledger_panel(alpha := 0.97) -> StyleBoxFlat:
	var box := _box(Color(COLOR_SURFACE, alpha), 18, 14)
	box.border_color = INK_SOFT
	box.set_border_width_all(1)
	box.border_width_bottom = 3
	box.shadow_color = PAPER_SHADOW
	box.shadow_size = 3
	box.shadow_offset = Vector2(3, 4)
	box.anti_aliasing = false
	return box

## Ruled ledger entries. No rounding, no glow: state is shown by ink, wash and rubric.
static func ledger_button_box(state := "normal") -> StyleBoxFlat:
	var box := _box(Color(0, 0, 0, 0), 12, 6)
	box.anti_aliasing = false
	box.border_color = Color(INK_SOFT, 0.45)
	box.border_width_bottom = 1
	match state:
		"hover":
			box.bg_color = Color(COLOR_SURFACE_VARIANT, 0.85)
			box.border_color = INK_SOFT
		"pressed":
			box.bg_color = COLOR_PRIMARY
			box.border_color = COLOR_PRIMARY
		"selected":
			box.bg_color = Color(COLOR_SURFACE_VARIANT, 0.9)
			box.border_color = COLOR_PRIMARY
			box.border_width_left = 4
		"disabled":
			box.border_color = Color(INK_SOFT, 0.2)
		"focus":
			box.border_color = COLOR_PRIMARY
			box.border_width_bottom = 2
	return box

static func style_ledger_button(button: Button, font: Font = null, font_size := 15, selected := false) -> void:
	for state in ["normal", "hover", "pressed", "disabled", "focus"]:
		button.add_theme_stylebox_override(state, ledger_button_box(state))
	if selected:
		button.add_theme_stylebox_override("normal", ledger_button_box("selected"))
	button.add_theme_color_override("font_color", COLOR_ON_SURFACE)
	button.add_theme_color_override("font_hover_color", COLOR_PRIMARY)
	button.add_theme_color_override("font_focus_color", COLOR_ON_SURFACE)
	button.add_theme_color_override("font_pressed_color", COLOR_ON_PRIMARY)
	button.add_theme_color_override("font_disabled_color", Color(INK_SOFT, 0.55))
	button.add_theme_font_size_override("font_size", font_size)
	button.alignment = HORIZONTAL_ALIGNMENT_LEFT
	if font != null: button.add_theme_font_override("font", font)
	prepare_button(button)
