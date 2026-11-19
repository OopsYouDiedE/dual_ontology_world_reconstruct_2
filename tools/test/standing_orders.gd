extends SceneTree

const Orders := preload("res://scenes/rogue_rules/StandingOrders.gd")

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var editor := Orders.new()
	root.add_child(editor)
	var seen := {"encounter_id": "room-1", "room_type": "Kitchen", "clue": "Steam reaches the spout.",
		"options": ["Follow the kettle", "Follow the false echo"], "observed": true}
	editor.set_context(seen)
	if not _check(editor.try_order(seen).is_empty(), "Automation starts off"): return
	var list: OptionButton = editor.get_child(1).get_child(0)
	var save: Button = editor.get_child(1).get_child(1)
	var remove: Button = editor.get_child(1).get_child(2)
	var action: OptionButton = editor.get_child(4)
	if not _check(action.selected == -1, "No action is preselected"): return
	save.pressed.emit()
	if not _check(editor.orders().is_empty(), "Commit without action does nothing"): return
	action.select(1)
	save.pressed.emit()
	if not _check(editor.orders().size() == 1, "Authoring via UI commits one rule"): return
	var id: int = editor.orders()[0].id
	var later := seen.duplicate(true)
	later.encounter_id = "room-2"
	later.options.reverse()
	for override in [{"at_camp": true}, {"in_guide": true}, {"observed": false}, {"room_type": "Clinic"},
		{"clue": "A different clue"}, {"options": ["Follow the kettle"]}, {"options": ["Follow the false echo", "Follow the false echo"]}]:
		var blocked := later.duplicate(true)
		blocked.merge(override, true)
		if not _check(editor.try_order(blocked).is_empty(), "Blocked, mismatched, or ambiguous context cannot fire"): return
	var result := editor.try_order(later)
	if not _check(result.get("action") == "Follow the false echo" and result.get("option_index") == 0,
		"The wrong action still fires, resolved by exact text against the current order"): return
	if not _check(result.command_beats_saved == 1 and result.action_beats_saved == 0 and result.action_beats == 1,
		"Automation saves the command beat, not the action"): return
	var health := 9
	if result.option_index != later.options.find("Follow the kettle"): health -= 3
	if not _check(health == 6, "Shared resolver applies the usual wrong-action penalty"): return
	if not _check(editor.try_order(later).is_empty(), "Same encounter cannot fire twice"): return
	var next := later.duplicate(true)
	next.encounter_id = "room-3"
	next.clue = "The chain stays fixed."
	next.options = ["Brace the chain", "Catch the loose tail"]
	editor.set_context(next)
	var use_here: CheckButton = editor.get_child(2)
	use_here.button_pressed = true
	action.select(0)
	save.pressed.emit()
	if not _check(editor.orders()[0].id == id and editor.orders()[0].clue == next.clue, "Condition edit retains rule ID"): return
	if not _check(editor.try_order(next).get("action") == "Brace the chain", "Edited condition and action take effect"): return
	remove.pressed.emit()
	if not _check(editor.orders().is_empty() and list.item_count == 1, "Delete removes the order"): return
	editor.reset()
	if not _check(editor.save_order(seen, "Follow the kettle") != -1 and not editor.try_order(seen).is_empty(),
		"Run reset clears consumption tracking"): return
	print("Standing orders: UI author/edit/delete, exact action, gates, and beat accounting passed")
	quit(0)

func _check(ok: bool, message: String) -> bool:
	if not ok:
		push_error(message)
		quit(1)
	return ok
