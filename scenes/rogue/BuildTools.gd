extends HBoxContainer
## Opens the project's native building workbench in a separate Godot window.

const ARCHBUILDER := "res://tools/building_construction/BuildingSimulator.tscn"
# Legacy caller can still assign this while Run drops its old FreeSO binding.
# ArchBuilder never reads it.
@warning_ignore("unused_variable")
var room_binding: Callable
var _architect_pid := -1
var _feedback := Label.new()

func _ready() -> void:
	alignment = BoxContainer.ALIGNMENT_CENTER
	var button := Button.new()
	button.text = "Open ArchBuilder"
	button.pressed.connect(open_archbuilder)
	add_child(button)
	add_child(_feedback)

## Returns the running PID, or -1 if it could not start.
func open_archbuilder() -> int:
	if _architect_pid > 0 and OS.is_process_running(_architect_pid):
		_feedback.text = "ArchBuilder is already open."
		return _architect_pid
	if not OS.has_feature("editor"):
		_feedback.text = "Open ArchBuilder from the Godot project checkout."
		return -1
	_architect_pid = OS.create_instance(PackedStringArray([
		"--path", ProjectSettings.globalize_path("res://"), ARCHBUILDER,
	]))
	_feedback.text = "ArchBuilder opened in a separate window." if _architect_pid > 0 else "Could not start ArchBuilder."
	return _architect_pid
