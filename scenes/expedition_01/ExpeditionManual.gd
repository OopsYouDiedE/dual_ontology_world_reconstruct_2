extends RefCounted
## Field manual parchment UI, pagination, and formatting for Expedition-01.

const UiStyle = preload("res://scenes/components/shared/UiTheme.gd")
const R18n = preload("res://scenes/components/shared/R18n.gd")
const Contracts = preload("ExpeditionContracts.gd")

var panel := PanelContainer.new()
var page := RichTextLabel.new()
var controls := Label.new()
var current_page := 0
var has_opened := false

func setup(canvas: CanvasLayer, font: Font) -> void:
	canvas.add_child(panel)
	panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	panel.offset_left = -305
	panel.offset_right = 305
	panel.offset_top = -194
	panel.offset_bottom = 194
	var paper := StyleBoxFlat.new()
	paper.bg_color = UiStyle.PARCHMENT
	paper.border_color = UiStyle.PARCHMENT_BORDER
	paper.set_border_width_all(3)
	paper.set_corner_radius_all(4)
	paper.shadow_color = Color(0, 0, 0, .7)
	paper.shadow_size = 20
	paper.content_margin_left = 34
	paper.content_margin_right = 34
	paper.content_margin_top = 28
	paper.content_margin_bottom = 22
	panel.add_theme_stylebox_override("panel", paper)
	panel.add_child(page)
	page.bbcode_enabled = true
	page.scroll_active = false
	page.add_theme_font_override("normal_font", font)
	page.add_theme_font_override("bold_font", font)
	page.add_theme_color_override("default_color", UiStyle.PARCHMENT_INK)
	page.add_theme_font_size_override("normal_font_size", 18)
	page.add_theme_font_size_override("bold_font_size", 22)
	panel.hide()

	canvas.add_child(controls)
	controls.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	controls.offset_left = -380.
	controls.offset_right = 380.
	controls.offset_top = 201.
	controls.offset_bottom = 282.
	controls.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	controls.mouse_filter = Control.MOUSE_FILTER_IGNORE
	controls.add_theme_font_override("font", font)
	controls.add_theme_font_size_override("font_size", 15)
	controls.add_theme_constant_override("outline_size", 6)
	controls.hide()

func is_open() -> bool:
	return panel.visible

func toggle(annotated: bool, sound_read: bool, light_read: bool) -> bool:
	panel.visible = not panel.visible
	has_opened = true
	if panel.visible:
		current_page = 0
		render(annotated, sound_read, light_read)
	controls.visible = panel.visible
	return panel.visible

func step_page(delta: int, annotated: bool, sound_read: bool, light_read: bool) -> void:
	current_page = posmod(current_page + delta, 5)
	render(annotated, sound_read, light_read)

func render(annotated: bool, sound_read: bool, light_read: bool) -> void:
	var pages := Contracts.manual_pages(annotated, sound_read, light_read)
	page.text = str(pages[clampi(current_page, 0, pages.size() - 1)])
	if current_page == 4 and sound_read and light_read:
		page.append_text("\n\n" + R18n.pick("两处刻文均已核对。", "Both wall inscriptions verified."))
	controls.text = R18n.t("hud.book_controls")
