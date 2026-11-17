extends "res://tools/testing/TestStoryHost.gd"
## Interactive scenario entry using the production story renderer and controls.
func _ready() -> void:
	var bridge := get_node("/root/GameMcp")
	fixture = preload("res://scenes/components/testing/ScenarioLoader.gd").new()
	if not fixture.read(bridge.scenario_path):
		fixture_error = fixture.error
		push_error(fixture_error)
		return
	fixture_directory = bridge.assessment_output_directory
	super._ready()
	var saved := str(fixture.configuration.get("presentation_snapshot", ""))
	if not saved.is_empty():
		if not checkpoints.restore_file(saved):
			fixture_error = checkpoints.error
			push_error(fixture_error)

var _received_input := false

func begin_segment_input() -> void:
	if _received_input or eng == null or not fixture_error.is_empty(): return
	_received_input = true
	# Survey fixtures start paused for reproducible stills. A playable segment
	# preserves its initial observation, then resumes ordinary production time.
	if fixture.configuration.get("entry", "exploration") != "wake" and (gathering == null or not gathering.active) and (kitchen == null or not kitchen.active) and (opening == null or not opening.active):
		eng.s.playing = true
