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
