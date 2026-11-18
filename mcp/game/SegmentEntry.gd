extends "res://tools/testing/TestStoryHost.gd"
## Interactive scenario entry using the production story renderer and controls.
func _ready() -> void:
	var bridge := get_node("/root/GameMcp")
	fixture = preload("res://scenes/components/testing/ScenarioLoader.gd").new()
	if not fixture.read(bridge.scenario_path):
		fixture_error = fixture.error
		push_error(fixture_error)
		return
	if str(fixture.configuration.get("mode", "story")) != "story":
		fixture_error = "Interactive segments require a story fixture. Use the workbench for previews."
		push_error(fixture_error)
		return
	fixture_directory = bridge.assessment_output_directory
	super._ready()

var _received_input := false

func _input(event: InputEvent) -> void:
	if event.is_pressed() and not event.is_echo() and _is_play_input(event): _begin_segment_input()
	super._input(event)

func _is_play_input(event: InputEvent) -> bool:
	if event is InputEventMouseButton: return event.button_index == MOUSE_BUTTON_LEFT
	for action in [&"move_left", &"move_right", &"move_up", &"move_down", &"interact", &"ui_accept"]:
		if event.is_action_pressed(action): return true
	return false

func _begin_segment_input() -> void:
	if _received_input or eng == null or not fixture_error.is_empty(): return
	_received_input = true
	# Survey fixtures start paused for reproducible stills. A playable segment
	# preserves its initial observation, then resumes ordinary production time.
	if fixture.configuration.get("entry", "exploration") == "wake" or eng.s.chapter_complete or eng.s.ending != "": return
	if gathering != null and gathering.active: return # The corridor hands time back on arrival.
	eng.s.playing = true
