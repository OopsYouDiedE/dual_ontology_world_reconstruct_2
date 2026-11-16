extends SceneTree
## Pure selection regression: it neither moves a character nor proves a room
## fast-check, sight line, natural play or independent acceptance.
const Host := preload("res://scenes/dual_world/DualWorldMain.gd")
var failures := 0

func _check(condition: bool, label: String) -> void:
	print(("PASS  " if condition else "FAIL  ") + label)
	if not condition: failures += 1

func _initialize() -> void:
	var rooms := {"2F-cross-M":{}, "2F-North-Stair":{}, "1F-Shaft-Monitor":{}, "B-P":{}}
	var source := "2F-cross-M"
	var destination := "1F-Shaft-Monitor"
	var next := "2F-North-Stair"
	_check(Host._exit_heading_room(source, destination, [source, next, destination], rooms) == next, "target route faces the first logical hop")
	_check(Host._exit_heading_room(source, destination, [source, destination], rooms) == destination, "direct path keeps the destination")
	_check(Host._exit_heading_room(source, destination, [], rooms) == destination, "missing path keeps prior behaviour")
	_check(Host._exit_heading_room(source, destination, ["B-P", next, destination], rooms) == destination, "wrong start is rejected")
	_check(Host._exit_heading_room(source, destination, [source, next, "B-P"], rooms) == destination, "wrong final room is rejected")
	_check(Host._exit_heading_room(source, destination, [source, "missing", destination], rooms) == destination, "unknown next room is rejected")
	_check(Host._exit_heading_room(source, destination, [source, source, destination], rooms) == destination, "self hop is rejected")
	_check(Host._exit_heading_room("B-P", destination, ["B-P", source, destination], rooms) == destination, "unrelated origin is unchanged")
	_check(Host._exit_heading_room(source, "B-P", [source, next, "B-P"], rooms) == "B-P", "unrelated destination is unchanged")
	print("RESULT failures=", failures, " acceptance_eligible=false")
	quit(0 if failures == 0 else 1)
