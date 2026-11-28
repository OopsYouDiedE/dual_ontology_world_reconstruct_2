extends RefCounted
## Shared modern-minimal theme for the building tools (ArchBuilder + Component Library).
## Flat dark surfaces, one accent colour, rounded controls, quiet borders.
## Type variations used by the tools:
##   TitleLabel / SectionLabel / FieldLabel / HintLabel        (Label)
## Three tiers of emphasis so the eye finds the common action first:
##   1. PrimaryButton  – filled accent, one per area (the next step you usually take)
##   2. Button         – filled neutral (regular actions)
##   3. FlatButton     – muted text only (rare / secondary actions)
##   RailButton (big tool rail), ToolButton (segmented), ChipButton (quick picks), DangerButton
##   TitleLabel / SectionLabel / FieldLabel / HintLabel / KeyLabel (Label)
##   TopBar / SidePanel / RailPanel / FloatingPanel / StatusBar (PanelContainer)

const BG := Color("111318")
const PANEL := Color("181b21")
const SURFACE := Color("22262e")
const SURFACE_HOVER := Color("2b303a")
const BORDER := Color("2e333d")
const TEXT := Color("e7e9ee")
const MUTED := Color("8d95a3")
const ACCENT := Color("4f8cff")
const ACCENT_HOVER := Color("6b9fff")
const DANGER := Color("ef6b62")

static var _cached: Theme

static func get_theme() -> Theme:
	if _cached == null:
		_cached = build()
	return _cached

static func box(color: Color, radius := 6, margins := Vector4(10, 6, 10, 6), border := 0, border_color := BORDER) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = color
	s.set_corner_radius_all(radius)
	s.content_margin_left = margins.x
	s.content_margin_top = margins.y
	s.content_margin_right = margins.z
	s.content_margin_bottom = margins.w
	if border > 0:
		s.set_border_width_all(border)
		s.border_color = border_color
	s.anti_aliasing = true
	return s

static func _focus() -> StyleBoxFlat:
	var s := box(Color(0, 0, 0, 0), 6, Vector4.ZERO, 1, Color(ACCENT, 0.8))
	s.draw_center = false
	return s

static func _button_styles(t: Theme, type: String, normal: Color, hover: Color, pressed: Color) -> void:
	t.set_stylebox("normal", type, box(normal))
	t.set_stylebox("hover", type, box(hover))
	t.set_stylebox("pressed", type, box(pressed))
	t.set_stylebox("hover_pressed", type, box(pressed.lightened(0.08)))
	t.set_stylebox("disabled", type, box(Color(normal, normal.a * 0.4)))
	t.set_stylebox("focus", type, _focus())

static func _font_colors(t: Theme, type: String, color: Color, pressed := Color.WHITE) -> void:
	t.set_color("font_color", type, color)
	t.set_color("font_hover_color", type, color.lightened(0.15))
	t.set_color("font_focus_color", type, color)
	t.set_color("font_pressed_color", type, pressed)
	t.set_color("font_hover_pressed_color", type, pressed)
	t.set_color("font_disabled_color", type, Color(MUTED, 0.5))

static func build() -> Theme:
	var t := Theme.new()
	t.default_font_size = 15
	var clear := Color(0, 0, 0, 0)

	# Labels
	t.set_color("font_color", "Label", TEXT)
	for spec in [["TitleLabel", TEXT, 19], ["SectionLabel", MUTED, 12], ["FieldLabel", MUTED, 13], ["HintLabel", MUTED, 13], ["KeyLabel", Color(1, 1, 1, 0.55), 12]]:
		t.set_type_variation(spec[0], "Label")
		t.set_color("font_color", spec[0], spec[1])
		t.set_font_size("font_size", spec[0], spec[2])

	# Buttons
	_button_styles(t, "Button", SURFACE, SURFACE_HOVER, ACCENT)
	_font_colors(t, "Button", TEXT)
	t.set_type_variation("FlatButton", "Button")
	_button_styles(t, "FlatButton", clear, SURFACE_HOVER, ACCENT)
	_font_colors(t, "FlatButton", MUTED)
	t.set_font_size("font_size", "FlatButton", 14)
	# Tool rail: large, left-aligned, the active tool is a solid accent block.
	t.set_type_variation("RailButton", "Button")
	for state in ["normal", "hover", "pressed", "hover_pressed", "disabled"]:
		var col: Color = {"normal": clear, "hover": SURFACE_HOVER, "pressed": ACCENT, "hover_pressed": ACCENT_HOVER, "disabled": clear}[state]
		t.set_stylebox(state, "RailButton", box(col, 8, Vector4(14, 10, 14, 10)))
	t.set_stylebox("focus", "RailButton", _focus())
	_font_colors(t, "RailButton", TEXT)
	t.set_font_size("font_size", "RailButton", 16)
	# Chips: compact pills for quick picks (recent components).
	t.set_type_variation("ChipButton", "Button")
	for state in ["normal", "hover", "pressed", "hover_pressed"]:
		var chip: Color = {"normal": SURFACE, "hover": SURFACE_HOVER, "pressed": ACCENT, "hover_pressed": ACCENT_HOVER}[state]
		t.set_stylebox(state, "ChipButton", box(chip, 14, Vector4(10, 3, 10, 3)))
	t.set_stylebox("focus", "ChipButton", _focus())
	_font_colors(t, "ChipButton", TEXT)
	t.set_font_size("font_size", "ChipButton", 13)
	t.set_type_variation("ToolButton", "Button")
	_button_styles(t, "ToolButton", clear, SURFACE_HOVER, ACCENT)
	_font_colors(t, "ToolButton", MUTED)
	t.set_type_variation("PrimaryButton", "Button")
	_button_styles(t, "PrimaryButton", ACCENT, ACCENT_HOVER, ACCENT.darkened(0.15))
	for state in ["normal", "hover", "pressed", "hover_pressed"]:
		var big: StyleBoxFlat = t.get_stylebox(state, "PrimaryButton")
		big.content_margin_top = 9
		big.content_margin_bottom = 9
	t.set_font_size("font_size", "PrimaryButton", 16)
	_font_colors(t, "PrimaryButton", Color.WHITE)
	t.set_color("font_hover_color", "PrimaryButton", Color.WHITE)
	t.set_type_variation("DangerButton", "Button")
	_button_styles(t, "DangerButton", clear, Color(DANGER, 0.18), Color(DANGER, 0.35))
	_font_colors(t, "DangerButton", DANGER, Color.WHITE)
	for type in ["MenuButton", "OptionButton"]:
		_font_colors(t, type, TEXT)
	_button_styles(t, "MenuButton", clear, SURFACE_HOVER, SURFACE_HOVER)
	_button_styles(t, "OptionButton", SURFACE, SURFACE_HOVER, SURFACE_HOVER)
	t.set_constant("arrow_margin", "OptionButton", 8)
	for type in ["CheckBox", "CheckButton"]:
		for state in ["normal", "hover", "pressed", "hover_pressed", "disabled"]:
			t.set_stylebox(state, type, box(clear, 6, Vector4(4, 4, 4, 4)))
		t.set_stylebox("focus", type, _focus())
		_font_colors(t, type, TEXT, TEXT)

	# Text input (SpinBox uses LineEdit inside)
	t.set_stylebox("normal", "LineEdit", box(SURFACE, 6, Vector4(10, 6, 10, 6), 1, BORDER))
	t.set_stylebox("focus", "LineEdit", box(Color(0, 0, 0, 0), 6, Vector4(10, 6, 10, 6), 1, ACCENT))
	t.get_stylebox("focus", "LineEdit").draw_center = false
	t.set_stylebox("read_only", "LineEdit", box(PANEL, 6, Vector4(10, 6, 10, 6), 1, BORDER))
	t.set_color("font_color", "LineEdit", TEXT)
	t.set_color("font_placeholder_color", "LineEdit", Color(MUTED, 0.7))
	t.set_color("caret_color", "LineEdit", ACCENT)
	t.set_color("selection_color", "LineEdit", Color(ACCENT, 0.35))
	t.set_color("clear_button_color", "LineEdit", MUTED)

	# Lists
	t.set_stylebox("panel", "ItemList", box(BG, 8, Vector4(4, 4, 4, 4), 1, BORDER))
	t.set_stylebox("focus", "ItemList", StyleBoxEmpty.new())
	t.set_stylebox("selected", "ItemList", box(Color(ACCENT, 0.22), 5))
	t.set_stylebox("selected_focus", "ItemList", box(Color(ACCENT, 0.3), 5))
	t.set_stylebox("hovered", "ItemList", box(SURFACE, 5))
	t.set_stylebox("hovered_selected", "ItemList", box(Color(ACCENT, 0.3), 5))
	t.set_stylebox("hovered_selected_focus", "ItemList", box(Color(ACCENT, 0.36), 5))
	t.set_stylebox("cursor", "ItemList", StyleBoxEmpty.new())
	t.set_stylebox("cursor_unfocused", "ItemList", StyleBoxEmpty.new())
	t.set_color("font_color", "ItemList", Color(TEXT, 0.88))
	t.set_color("font_hovered_color", "ItemList", TEXT)
	t.set_color("font_selected_color", "ItemList", Color.WHITE)
	t.set_color("font_hovered_selected_color", "ItemList", Color.WHITE)
	t.set_color("guide_color", "ItemList", clear)
	t.set_constant("v_separation", "ItemList", 6)
	t.set_constant("line_separation", "ItemList", 2)

	# Tabs: underline style
	var tab_on := box(clear, 0, Vector4(12, 8, 12, 8))
	tab_on.border_width_bottom = 2
	tab_on.border_color = ACCENT
	var tab_off := box(clear, 0, Vector4(12, 8, 12, 8))
	var tab_hover := box(clear, 0, Vector4(12, 8, 12, 8))
	tab_hover.border_width_bottom = 2
	tab_hover.border_color = BORDER
	for type in ["TabContainer", "TabBar"]:
		t.set_stylebox("tab_selected", type, tab_on)
		t.set_stylebox("tab_unselected", type, tab_off)
		t.set_stylebox("tab_hovered", type, tab_hover)
		t.set_stylebox("tab_focus", type, StyleBoxEmpty.new())
		t.set_stylebox("tab_disabled", type, tab_off)
		t.set_color("font_selected_color", type, TEXT)
		t.set_color("font_unselected_color", type, MUTED)
		t.set_color("font_hovered_color", type, TEXT)
		t.set_font_size("font_size", type, 14)
	var tab_panel := box(clear, 0, Vector4.ZERO)
	tab_panel.border_width_top = 1
	tab_panel.border_color = BORDER
	t.set_stylebox("panel", "TabContainer", tab_panel)
	t.set_stylebox("tabbar_background", "TabContainer", StyleBoxEmpty.new())

	# Panels
	t.set_stylebox("panel", "PanelContainer", box(PANEL, 10, Vector4(14, 14, 14, 14), 1, BORDER))
	t.set_stylebox("panel", "Panel", box(PANEL, 10))
	t.set_type_variation("FloatingPanel", "PanelContainer")
	var floating := box(Color(PANEL, 0.94), 12, Vector4(16, 16, 16, 16), 1, BORDER)
	floating.shadow_color = Color(0, 0, 0, 0.35)
	floating.shadow_size = 12
	t.set_stylebox("panel", "FloatingPanel", floating)
	t.set_type_variation("TopBar", "PanelContainer")
	var top := box(PANEL, 0, Vector4(12, 6, 12, 6))
	top.border_width_bottom = 1
	top.border_color = BORDER
	t.set_stylebox("panel", "TopBar", top)
	t.set_type_variation("SidePanel", "PanelContainer")
	var side := box(PANEL, 0, Vector4(12, 8, 12, 10))
	side.border_width_left = 1
	side.border_color = BORDER
	t.set_stylebox("panel", "SidePanel", side)
	t.set_type_variation("RailPanel", "PanelContainer")
	var rail := box(PANEL, 0, Vector4(8, 10, 8, 10))
	rail.border_width_right = 1
	rail.border_color = BORDER
	t.set_stylebox("panel", "RailPanel", rail)
	t.set_type_variation("StatusBar", "PanelContainer")
	var status := box(BG, 0, Vector4(14, 6, 14, 6))
	status.border_width_top = 1
	status.border_color = BORDER
	t.set_stylebox("panel", "StatusBar", status)
	t.set_stylebox("panel", "ScrollContainer", StyleBoxEmpty.new())
	t.set_stylebox("focus", "ScrollContainer", StyleBoxEmpty.new())

	# Separators, splitters, scrollbars
	for spec in [["VSeparator", true], ["HSeparator", false]]:
		var line := StyleBoxLine.new()
		line.color = BORDER
		line.vertical = spec[1]
		line.grow_begin = -6
		line.grow_end = -6
		t.set_stylebox("separator", spec[0], line)
		t.set_constant("separation", spec[0], 12)
	t.set_constant("separation", "HSplitContainer", 6)
	t.set_constant("separation", "VSplitContainer", 6)
	t.set_constant("separation", "HBoxContainer", 6)
	t.set_constant("separation", "VBoxContainer", 8)
	for bar in ["VScrollBar", "HScrollBar"]:
		t.set_stylebox("scroll", bar, box(clear, 4, Vector4(3, 3, 3, 3)))
		t.set_stylebox("scroll_focus", bar, box(clear, 4, Vector4(3, 3, 3, 3)))
		t.set_stylebox("grabber", bar, box(SURFACE_HOVER, 4))
		t.set_stylebox("grabber_highlight", bar, box(MUTED.darkened(0.2), 4))
		t.set_stylebox("grabber_pressed", bar, box(ACCENT, 4))

	# Popups, tooltips, windows
	t.set_stylebox("panel", "PopupMenu", box(SURFACE, 8, Vector4(6, 6, 6, 6), 1, BORDER))
	t.set_stylebox("hover", "PopupMenu", box(Color(ACCENT, 0.25), 5))
	t.set_color("font_color", "PopupMenu", TEXT)
	t.set_color("font_hover_color", "PopupMenu", Color.WHITE)
	t.set_color("font_separator_color", "PopupMenu", MUTED)
	t.set_constant("v_separation", "PopupMenu", 8)
	var sep := StyleBoxLine.new()
	sep.color = BORDER
	t.set_stylebox("separator", "PopupMenu", sep)
	t.set_stylebox("panel", "TooltipPanel", box(SURFACE, 6, Vector4(10, 6, 10, 6), 1, BORDER))
	t.set_color("font_color", "TooltipLabel", TEXT)
	var frame := box(PANEL, 10, Vector4(8, 8, 8, 8), 1, BORDER)
	frame.expand_margin_top = 30
	frame.shadow_color = Color(0, 0, 0, 0.4)
	frame.shadow_size = 16
	t.set_stylebox("embedded_border", "Window", frame)
	t.set_stylebox("embedded_unfocused_border", "Window", frame)
	t.set_color("title_color", "Window", TEXT)
	t.set_stylebox("panel", "AcceptDialog", box(PANEL, 0, Vector4(12, 12, 12, 12)))
	return t
