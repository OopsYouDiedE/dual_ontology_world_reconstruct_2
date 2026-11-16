extends Node
## Formal room exploration keeps its world HUD small; the physical book owns menus.
var host: Control
var shell: Node
var book_open := false
var _return_playing := false
var _return_process_mode := Node.PROCESS_MODE_INHERIT


func bind(owner_host: Control) -> void:
	host = owner_host
	var parent := host.get_parent()
	if parent != null and parent.has_method("_open_book_page"):
		shell = parent
		shell.book_ui.closed.connect(_restore_field)
	apply()


static func hide_chrome(owner_host: Control) -> void:
	for key in ["top_bar", "left_card", "room_hint", "drawer"]:
		var control: Control = owner_host.get(key)
		if is_instance_valid(control): control.visible = false
	if is_instance_valid(owner_host.drawer_btn): owner_host.drawer_btn.button_pressed = false


func apply() -> void:
	if host.view == "room" and not host.instant_story:
		hide_chrome(host)


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
