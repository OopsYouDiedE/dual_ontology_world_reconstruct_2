extends Node
## Compact field navigation for the shared story host.
var host: Control
var shell: Node
var book_open := false
var _return_playing := false
var _return_process_mode := Node.PROCESS_MODE_INHERIT
var _route_panel: PanelContainer
var _map_button: Button
var _case_button: Button
var _title_button: Button
var _objective: Label
var _map_open := false
var _map_return_playing := false
var _case_open := false
var _summary_case := false
var _objective_key := ""


func bind(owner_host: Control) -> void:
	host = owner_host
	var parent := host.get_parent()
	if parent != null and parent.has_method("_open_book_page"):
		shell = parent
		shell.book_ui.closed.connect(_restore_field)
	_build_field_navigation()
	apply()


static func hide_chrome(owner_host: Control) -> void:
	for key in ["top_bar", "left_card", "room_hint", "drawer"]:
		var control: Control = owner_host.get(key)
		if is_instance_valid(control): control.visible = false
	if is_instance_valid(owner_host.drawer_btn): owner_host.drawer_btn.button_pressed = false


func _build_field_navigation() -> void:
	_route_panel = PanelContainer.new()
	_route_panel.name = "FieldNavigation"
	_route_panel.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT)
	_route_panel.offset_left = 18.0
	_route_panel.offset_bottom = -18.0
	_route_panel.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_route_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_route_panel.add_theme_stylebox_override("panel", host._style(Color("#211911e8"), Color("#7c6642"), 6, 7))
	var body := VBoxContainer.new()
	body.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_route_panel.add_child(body)
	_objective = Label.new()
	_objective.name = "FieldObjective"
	_objective.set_meta("text_category", "prompt")
	_objective.custom_minimum_size.x = 340.0
	_objective.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_objective.add_theme_font_size_override("font_size", 14)
	body.add_child(_objective)
	var bar := HBoxContainer.new()
	bar.add_theme_constant_override("separation", 8)
	body.add_child(bar)
	_map_button = host._btn(bar, "Map", _toggle_map, "Choose a reachable room")
	_case_button = host._btn(bar, "Case File", _toggle_case_file)
	# Detached fixtures have no title shell to return to.
	_title_button = host._btn(bar, "Return to Title", host._close, "Save progress and return to the title")
	_title_button.visible = is_instance_valid(shell)
	host.center.add_child(_route_panel)


func apply() -> void:
	if _route_panel == null: return
	if host.instant_story: _route_panel.hide(); return
	if host.view == "room":
		host.top_bar.hide()
		host.left_card.hide()
		host.room_hint.hide()
		if not _case_open: host.drawer.hide()
	if _map_open and host.view != "map":
		_map_open = false
		host.eng.s.playing = _map_return_playing
	var controller: Node = null
	for candidate in [host.opening, host.gathering, host.kitchen]:
		if is_instance_valid(candidate) and candidate.active:
			controller = candidate
			break
	var directed := is_instance_valid(controller)
	var staged: bool = host._cine or host._transit_active() or host._story_busy() or (directed and controller.phase != "free")
	_route_panel.visible = not (staged or host.modal.visible or book_open) and host.view in ["room", "map"] and (not directed or is_instance_valid(shell))
	if not _route_panel.visible: return
	var suffix := "Room" if host.view == "map" else "Map"
	if _map_button.text != suffix: _map_button.text = suffix
	_map_button.visible = not (_summary_case or directed)
	_case_button.visible = host.view == "room" and not directed
	_case_button.text = "Back to Summary" if _summary_case else ("Close Case File" if _case_open else "Case File")
	_title_button.visible = host.view == "room" and not _summary_case and is_instance_valid(shell)
	_objective.visible = host.view == "room" and not directed and (not host.eng.s.hold.is_empty() or not host.eng.s.story_gate.is_empty() or not host.eng.s.postponed.is_empty())
	if _objective.visible:
		var state: Dictionary = host.eng.s
		var key := "%s|%s|%d" % [host._active_investigation(), str(state.story_gate.get("room", "")), state.evidence.size()]
		if key != _objective_key:
			_objective_key = key
			_objective.text = host._objective_text()
	else:
		_objective_key = ""


func _toggle_map() -> void:
	if host.view == "map":
		host._set_view("room")
		return
	if _case_open: _toggle_case_file()
	_map_return_playing = bool(host.eng.s.playing)
	_map_open = true
	host.eng.s.playing = false
	host._set_view("map")


func show_summary_case() -> void:
	_summary_case = true
	_set_case_open(true)


func _toggle_case_file() -> void:
	_set_case_open(not _case_open)
	if _summary_case and not _case_open:
		_summary_case = false
		host.restore_summary()


func _set_case_open(open: bool) -> void:
	_case_open = open
	host.drawer.visible = open
	host.drawer_btn.set_pressed_no_signal(open)
	host._dirty = true


func open_book(page: String) -> bool:
	if not is_instance_valid(shell): return false
	if shell.book_ui.busy(): return true
	if book_open:
		shell.book_ui.goto_page(page)
		return true
	_return_playing = bool(host.eng.s.playing)
	_return_process_mode = host.process_mode
	book_open = true
	host.eng.s.playing = false
	host.hide()
	shell._open_book_page(page)
	if not shell.book_ui.is_open:
		_restore_field()
		return false
	shell.book_ui.in_field = true
	host.process_mode = Node.PROCESS_MODE_DISABLED
	return true


func _restore_field() -> void:
	if not book_open or not is_instance_valid(host): return
	book_open = false
	# Main's earlier closed callback runs first; return this session to the room.
	if is_instance_valid(shell):
		shell.title_ui.hide_title(0.0)
		shell.stage.set_active(false)
	host.process_mode = _return_process_mode
	host.eng.s.playing = _return_playing
	host.show()
	apply()
