extends HBoxContainer
## Starts the pinned upstream client on the user's explicit build-mode request.
var room_binding: Callable
var worker := Thread.new()
var launch := Button.new()
var feedback := Label.new()

func _ready() -> void:
	alignment = BoxContainer.ALIGNMENT_CENTER
	launch.text = "Open FreeSO build tools"
	launch.pressed.connect(_open_builder)
	add_child(launch)
	feedback.text = "Original lot editor and SimAntics client"
	add_child(feedback)
	set_process(false)

func _open_builder() -> void:
	if OS.get_name() != "Windows":
		feedback.text = "The FreeSO client launcher requires Windows."
		return
	launch.disabled = true
	feedback.text = "Checking the FreeSO installation…"
	var script := ProjectSettings.globalize_path("res://tools/freeso/freeso.ps1")
	var binding: Dictionary = room_binding.call()
	var result := worker.start(_invoke.bind(script, binding.room, binding.directory))
	if result != OK:
		feedback.text = "Could not start the FreeSO launcher."
		launch.disabled = false
		return
	set_process(true)

func _invoke(script: String, room_id: String, lot_directory: String) -> String:
	var output := []
	var args := PackedStringArray(["-NoProfile", "-NonInteractive", "-ExecutionPolicy", "Bypass", "-File", script, "-Action", "Launch", "-RoomId", room_id, "-LotDirectory", lot_directory])
	var code := OS.execute("powershell.exe", args, output, true, false)
	if code == 0: return "FreeSO client launched. Enter the native sandbox lot to build and run its residents."
	return "FreeSO unavailable. Run tools/freeso/freeso.ps1 -Action Check for missing files."

func _process(_delta: float) -> void:
	if worker.is_alive(): return
	feedback.text = str(worker.wait_to_finish())
	launch.disabled = false
	set_process(false)

func _exit_tree() -> void:
	if worker.is_started(): worker.wait_to_finish()
