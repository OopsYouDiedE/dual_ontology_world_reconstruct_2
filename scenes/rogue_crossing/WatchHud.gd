extends Control
## Corner watch HUD card, footer action flow, and parchment document overlay for FirstWatch.

const UiStyle := preload("res://scenes/components/shared/UiTheme.gd")

var font: Font
var card: PanelContainer
var place_label: Label
var status_label: Label
var kit_label: Label
var footer: VBoxContainer
var instruction: Label
var flow: HFlowContainer
var overlay: ColorRect
var scroll: ScrollContainer
var sheet: VBoxContainer
var entry: LineEdit
var _hidden_for_opening: Array[Control] = []

func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE

func build() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	font = UiStyle.make_font()
	var vignette := ColorRect.new()
	vignette.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var shade := Shader.new()
	shade.code = UiStyle.VIGNETTE_SHADER
	vignette.material = ShaderMaterial.new()
	vignette.material.shader = shade
	add_child(vignette)
	vignette.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	_build_card()
	_build_footer()
	_build_overlay()

func _build_card() -> void:
	card = PanelContainer.new()
	card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.add_theme_stylebox_override("panel", UiStyle.panel_box(UiStyle.PANEL_BG, 3, Vector2(16, 11), 3, 0, UiStyle.ACCENT))
	add_child(card)
	card.position = Vector2(22, 18)
	var column := VBoxContainer.new()
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_theme_constant_override("separation", 4)
	card.add_child(column)
	place_label = Label.new()
	UiStyle.style_label(place_label, font, 17, UiStyle.ACCENT_SOFT, 0)
	column.add_child(place_label)
	var rule := ColorRect.new()
	rule.color = Color(UiStyle.ACCENT, 0.55)
	rule.custom_minimum_size = Vector2(0, 2)
	rule.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_child(rule)
	status_label = Label.new()
	UiStyle.style_label(status_label, font, 15, UiStyle.TEXT_MAIN, 0)
	column.add_child(status_label)
	kit_label = Label.new()
	UiStyle.style_label(kit_label, font, 14, UiStyle.TEXT_MUTED, 0)
	column.add_child(kit_label)

func _build_footer() -> void:
	footer = VBoxContainer.new()
	footer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	footer.alignment = BoxContainer.ALIGNMENT_END
	footer.add_theme_constant_override("separation", 10)
	add_child(footer)
	footer.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	footer.offset_left = 56
	footer.offset_right = -56
	footer.offset_bottom = -22
	footer.grow_vertical = Control.GROW_DIRECTION_BEGIN
	instruction = Label.new()
	instruction.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	instruction.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	instruction.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	UiStyle.style_label(instruction, font, 18, Color("fff3df"), 0)
	var plate := StyleBoxFlat.new()
	plate.bg_color = Color(.035, .029, .023, .89)
	plate.set_corner_radius_all(4)
	plate.content_margin_left = 18
	plate.content_margin_right = 18
	plate.content_margin_top = 7
	plate.content_margin_bottom = 7
	instruction.add_theme_stylebox_override("normal", plate)
	footer.add_child(instruction)
	flow = HFlowContainer.new()
	flow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	flow.alignment = FlowContainer.ALIGNMENT_CENTER
	flow.add_theme_constant_override("h_separation", 8)
	flow.add_theme_constant_override("v_separation", 6)
	footer.add_child(flow)

func _build_overlay() -> void:
	overlay = ColorRect.new()
	overlay.color = Color(0, 0, 0, .58)
	add_child(overlay)
	overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var center := CenterContainer.new()
	overlay.add_child(center)
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var panel := PanelContainer.new()
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
	center.add_child(panel)
	scroll = ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.custom_minimum_size.x = 660
	panel.add_child(scroll)
	sheet = VBoxContainer.new()
	sheet.custom_minimum_size.x = 636
	sheet.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sheet.add_theme_constant_override("separation", 10)
	scroll.add_child(sheet)
	overlay.hide()

## Width-fit the caption plate: short lines hug their text, long ones wrap inside the footer.
func fit_instruction(viewport_width: float) -> void:
	var widest := 0.0
	for line in instruction.text.split("\n"):
		widest = maxf(widest, font.get_string_size(line, HORIZONTAL_ALIGNMENT_LEFT, -1, 18).x)
	instruction.custom_minimum_size.x = minf(widest + 40.0, maxf(viewport_width - 112.0, 200.0))
	instruction.visible = not instruction.text.is_empty()

func clear_container(row: Node) -> void:
	for c in row.get_children():
		row.remove_child(c)
		c.queue_free()

func add_button(parent: Container, label_text: String, callback: Callable) -> Button:
	var b := Button.new()
	b.focus_mode = Control.FOCUS_NONE
	b.text = label_text
	b.custom_minimum_size.y = 34
	if parent == sheet:
		UiStyle.style_paper_button(b, font)
	else:
		UiStyle.style_button(b, font)
	parent.add_child(b)
	b.pressed.connect(callback)
	return b

func add_sheet_label(text: String, text_size := 16, gold := false) -> void:
	var node := Label.new()
	node.text = text
	node.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	node.custom_minimum_size.x = 636
	node.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	UiStyle.style_label(node, font, text_size, Color("7a4a1c") if gold else UiStyle.PARCHMENT_INK, 0)
	sheet.add_child(node)

func add_margin_entry(initial_text: String, on_submit: Callable) -> LineEdit:
	entry = LineEdit.new()
	entry.text = initial_text
	entry.max_length = 180
	entry.placeholder_text = "Write a brief note for the next captain..."
	entry.add_theme_font_override("font", font)
	entry.add_theme_font_size_override("font_size", 16)
	entry.add_theme_color_override("font_color", UiStyle.PARCHMENT_INK)
	entry.add_theme_color_override("font_placeholder_color", Color(UiStyle.PARCHMENT_INK, 0.45))
	entry.add_theme_color_override("caret_color", UiStyle.PARCHMENT_INK)
	var entry_box := StyleBoxFlat.new()
	entry_box.bg_color = Color("efe0be")
	entry_box.border_color = UiStyle.PARCHMENT_BORDER
	entry_box.set_border_width_all(2)
	entry_box.set_corner_radius_all(3)
	entry_box.content_margin_left = 10
	entry_box.content_margin_right = 10
	entry_box.content_margin_top = 6
	entry_box.content_margin_bottom = 6
	entry.add_theme_stylebox_override("normal", entry_box)
	entry.add_theme_stylebox_override("focus", entry_box)
	entry.text_submitted.connect(func(_text: String): on_submit.call())
	sheet.add_child(entry)
	entry.grab_focus.call_deferred()
	return entry

func open_sheet(title: String, folio: String) -> void:
	clear_container(sheet)
	overlay.show()
	scroll.scroll_vertical = 0
	add_sheet_label(folio, 13, true)
	add_sheet_label(title, 28, true)
	scroll.custom_minimum_size.y = 0
	fit_sheet.call_deferred()

func fit_sheet() -> void:
	if not overlay.visible:
		return
	sheet.size.x = 636
	for child in sheet.get_children():
		if child is Control:
			child.size.x = 636
	scroll.custom_minimum_size.y = minf(sheet.get_combined_minimum_size().y, get_viewport_rect().size.y * .80)
	# Wrapped lines only know their height once the page has its width: measure again after layout.
	await get_tree().process_frame
	if not overlay.visible:
		return
	scroll.custom_minimum_size.y = minf(sheet.get_combined_minimum_size().y, get_viewport_rect().size.y * .80)

func close_sheet() -> void:
	overlay.hide()

func set_flow_disabled(disabled: bool) -> void:
	for node in flow.get_children():
		if node is Button:
			node.disabled = disabled

func update_readout(room_title: String, clock: float, hp: int, nerve: int, party_count: int, supplies: int, pack: Dictionary) -> void:
	place_label.text = "%s    %02d:%02d" % [room_title, floori(clock) % 24, floori(fposmod(clock, 1.0) * 60)]
	status_label.text = "HP %d/9   ·   Nerve %d   ·   Party %d   ·   Crates %d" % [hp, nerve, party_count + 1, supplies]
	kit_label.text = "Felt %d   ·   Ratchets %d" % [pack.felt, pack.ratchet]

func hide_for_opening() -> void:
	_hidden_for_opening.clear()
	for item: Control in [card, footer]:
		if item.visible:
			item.hide()
			_hidden_for_opening.append(item)

func restore_after_opening() -> void:
	for child in _hidden_for_opening:
		if is_instance_valid(child):
			child.show()
	_hidden_for_opening.clear()

func set_sortie_mode(in_sortie: bool) -> void:
	process_mode = Node.PROCESS_MODE_DISABLED if in_sortie else Node.PROCESS_MODE_INHERIT
	visible = not in_sortie
	if not in_sortie:
		overlay.hide()

func visible_buttons(modal_active: bool) -> Array:
	var buttons := []
	var ui: Container = sheet if modal_active else flow
	for node in ui.get_children():
		if node is Button and node.is_visible_in_tree():
			var center: Vector2 = node.get_global_rect().get_center()
			buttons.append({"label": node.text, "x": center.x, "y": center.y, "enabled": not node.disabled})
	return buttons
