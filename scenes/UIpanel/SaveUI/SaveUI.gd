extends Control
## 书本检视器中的存档对开页：左页列出记录页，右页显示详情与写入、读取、撕去。
## 记录的读写全部经 Main 会话接口：save_slots()、can_save()、save_to_slot()、load_slot()、delete_slot()。

const CONFIRM_SECONDS := 3.0

@onready var slot_list: VBoxContainer = $SlotList
@onready var slot_title: Label = $SlotTitle
@onready var detail: Label = $Detail
@onready var write_button: Button = $Actions/WriteButton
@onready var load_button: Button = $Actions/LoadButton
@onready var delete_button: Button = $Actions/DeleteButton
@onready var status: Label = $Status

var host: Node
var _slots: Array = []
var _selected := "auto"
var _group := ButtonGroup.new()
## 需要再按一次确认的操作："write" / "load" / "delete"
var _armed := ""
var _armed_until := 0.0

func _ready() -> void:
	write_button.pressed.connect(func(): _confirm("write"))
	load_button.pressed.connect(func(): _confirm("load"))
	delete_button.pressed.connect(func(): _confirm("delete"))

func bind(main_host: Node) -> void:
	host = main_host

## BookUI 翻到本页时调用。
func on_page_shown() -> void:
	status.text = ""
	_disarm()
	refresh()

func refresh() -> void:
	_slots = host.save_slots() if host != null else []
	for child in slot_list.get_children():
		slot_list.remove_child(child)
		child.queue_free()
	for slot: Dictionary in _slots:
		var button := Button.new()
		button.toggle_mode = true
		button.button_group = _group
		button.alignment = HORIZONTAL_ALIGNMENT_LEFT
		button.custom_minimum_size.y = 76
		button.text = "%s\n%s" % [slot.label, _summary(slot)]
		button.button_pressed = str(slot.id) == _selected
		button.pressed.connect(_select.bind(str(slot.id)))
		slot_list.add_child(button)
	_show_detail()

func _select(id: String) -> void:
	_selected = id
	status.text = ""
	_disarm()
	_show_detail()

func _show_detail() -> void:
	var slot := _slot(_selected)
	var can_save: bool = host != null and host.can_save()
	var manual := str(slot.get("kind", "")) == "manual"
	var exists := bool(slot.get("exists", false))
	slot_title.text = str(slot.get("label", ""))
	if exists:
		detail.text = "场所　%s\n时刻　%s\n记于　%s" % [slot.get("place", "—"), slot.get("game_time", "—"), _local_time(int(slot.get("saved_at", 0)))]
		if not manual: detail.text += "\n\n离开生活场景或退出时更新这一页。"
	elif manual:
		detail.text = "这一页还空着。" + ("\n可以把当前生活进度写在这里。" if can_save else "\n开始生活后，才能把进度写在这里。")
	else:
		detail.text = "还没有自动记录。\n离开生活场景时会自动写下。"
	write_button.visible = manual
	write_button.disabled = not can_save
	load_button.disabled = not exists
	delete_button.visible = manual
	delete_button.disabled = not exists
	_label_buttons()

func _confirm(action: String) -> void:
	var slot := _slot(_selected)
	var needs_confirm: bool = action == "delete" or (action == "write" and bool(slot.get("exists", false))) or (action == "load" and host != null and host.can_save())
	if needs_confirm and (_armed != action or Time.get_ticks_msec() / 1000.0 > _armed_until):
		_armed = action
		_armed_until = Time.get_ticks_msec() / 1000.0 + CONFIRM_SECONDS
		status.text = {"write": "再按一次，覆盖这一页。", "load": "再按一次读取；当前未记下的进度会丢失。", "delete": "再按一次，撕去这一页。"}[action]
		_label_buttons()
		return
	_disarm()
	var error := ""
	match action:
		"write": error = host.save_to_slot(_selected)
		"load": error = host.load_slot(_selected)
		"delete": error = host.delete_slot(_selected)
	if not is_inside_tree(): return
	status.text = error if not error.is_empty() else {"write": "已写入。", "load": "正在读取……", "delete": "已撕去。"}[action]
	refresh()

func _disarm() -> void:
	_armed = ""
	_label_buttons()

func _label_buttons() -> void:
	write_button.text = "确认覆盖" if _armed == "write" else "写入此页"
	load_button.text = "确认读取" if _armed == "load" else "读取"
	delete_button.text = "确认撕去" if _armed == "delete" else "撕去"

func _process(_delta: float) -> void:
	if not _armed.is_empty() and Time.get_ticks_msec() / 1000.0 > _armed_until:
		status.text = ""
		_disarm()

func _slot(id: String) -> Dictionary:
	for slot: Dictionary in _slots:
		if str(slot.id) == id: return slot
	return {}

func _summary(slot: Dictionary) -> String:
	if not bool(slot.get("exists", false)): return "空白"
	return "%s　%s" % [slot.get("game_time", "—"), slot.get("place", "—")]

static func _local_time(unix: int) -> String:
	if unix <= 0: return "—"
	var bias := int(Time.get_time_zone_from_system().get("bias", 0)) * 60
	var time := Time.get_datetime_dict_from_unix_time(unix + bias)
	return "%04d-%02d-%02d %02d:%02d" % [time.year, time.month, time.day, time.hour, time.minute]
