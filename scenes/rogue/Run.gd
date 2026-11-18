extends Control
## A single seeded expedition. Revisits never regenerate rooms or pay rewards twice.
const House = preload("res://scenes/rogue/HouseMap.cs")
const Room = preload("res://scenes/rogue_view/RogueRoomView.tscn")
var house
var run_seed: int
var current := ""
var cleared := {}
var hp := 9

const Guide = preload("res://scenes/rogue_rules/FieldGuide.gd")
var roster: Array = []
var party: Array = []
var journal: Array = []
var duties := {}
var camp_reached := false
var phase := "approach"
var message := ""
var moves := 0
var ended := false
var room_view
var camp_watch = preload("res://scenes/rogue_rules/CampWatch.gd").new()
var stats := Label.new()
var instruction := Label.new()
var choices := HFlowContainer.new()
var destinations := PackedStringArray()
var lot_directory := "res://.runtime/freeso/lots"
var lot_stamp := -1
var lot_check := 0.0

func _ready() -> void:
	var layout := VBoxContainer.new()
	add_child(layout)
	layout.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	layout.add_theme_constant_override("separation", 8)
	stats.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	stats.add_theme_font_size_override("font_size", 20)
	layout.add_child(stats)
	var build_tools := preload("res://scenes/rogue/BuildTools.gd").new()
	build_tools.room_binding = func(): return {"room": current, "directory": ProjectSettings.globalize_path(lot_directory)}
	layout.add_child(build_tools)

	layout.add_child(camp_watch)
	room_view = Room.instantiate()
	room_view.size_flags_vertical = Control.SIZE_EXPAND_FILL
	layout.add_child(room_view)
	room_view.exit_selected.connect(travel)
	instruction.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	instruction.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	layout.add_child(instruction)
	choices.alignment = FlowContainer.ALIGNMENT_CENTER
	layout.add_child(choices)
	var margin := Control.new()
	margin.custom_minimum_size.y = 8
	layout.add_child(margin)
	var initial_seed := randi()
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--lot-dir="):
			lot_directory = arg.trim_prefix("--lot-dir=")
		if arg.begins_with("--run-seed=") and arg.get_slice("=", 1).is_valid_int():
			initial_seed = int(arg.get_slice("=", 1))
	new_run(initial_seed)

func new_run(value: int) -> void:
	run_seed = value
	house = House.new()
	if not house.generate(value):
		ended = true
		instruction.text = "The floor could not form. Start a new expedition."
		_buttons_clear()
		_button("New expedition", func(): new_run(randi()))
		return
	current = house.start_room()
	cleared = {current: true}
	hp = 9
	roster.clear()
	party.clear()
	journal.clear()

	duties.clear()
	camp_reached = false
	phase = "approach"
	message = "You enter the academy alone. Look for a lit window."
	moves = 0
	ended = false
	_refresh()

func _buttons_clear() -> void:
	for child in choices.get_children():
		choices.remove_child(child)
		child.queue_free()

func _button(text: String, callback: Callable) -> void:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(130, 42)
	b.pressed.connect(callback)
	choices.add_child(b)

func _label(id: String) -> String:
	return str(house.template_id(id)).replace("_", " ").capitalize()

func _door_tag(id: String) -> String:
	if id == house.camp_room(): return "Camp"
	if id == house.goal_room(): return "Dome"
	if id == house.start_room(): return "Entry"
	return ("A" if id.begins_with("approach") else "E") + id.get_slice("_", 1)

func _event() -> Dictionary:
	return Guide.encounter(run_seed, current)

func _refresh() -> void:
	_buttons_clear()
	destinations.clear()
	stats.text = "THE SLEEPING ACADEMY   |   Health %d/9   ·   Team %d/4   ·   Field rules %d   |   Seed %d" % [hp, party.size()+1, journal.size(), run_seed]
	camp_watch.set_camp(phase == "camp", lot_directory.path_join(current + ".json"))
	if ended:
		room_view.set_room("Daybreak" if phase == "won" else "Lost expedition", [])
		instruction.text = "The morning bell rings. Your team returns with its field guide." if phase == "won" else "The corridor forgets your names. The expedition ends here."
		_button("New expedition", func(): new_run(randi()))
		_button("Replay seed", func(): new_run(run_seed))
		return
	if current != house.goal_room() and not cleared.has(current):
		_present_room([])
		var event := _event()
		instruction.text = message + "\n" + event.clue
		for i in range(event.options.size()):
			_button(event.options[i], resolve.bind(i))
		if party.has(event.helper) and not duties.has(event.helper):
			_button("Assign " + event.helper, _assign.bind(event.helper))
		return
	destinations = house.exits(current)
	var labels := []
	for id in destinations: labels.append(_door_tag(id))
	_present_room(labels)
	instruction.text = message
	if phase == "camp":
		instruction.text += "\nBase camp · Choose up to three companions. Off duty, residents follow the FreeSO lot's own routines."
		for name_value in roster:
			if party.has(name_value): _button("Drop " + name_value, _toggle.bind(name_value))
			elif party.size() < 3: _button("Add " + name_value, _toggle.bind(name_value))
	if current == house.goal_room():
		instruction.text += "\nThe observatory needs three distinct recorded rules to wake the academy."
		if journal.size() >= 3: _button("Wake the house", _finish)
	if phase == "camp": _button("Meet the team", _team_info)
	if not journal.is_empty(): _button("Field guide", _read_guide)
	for i in destinations.size():
		_button("%s · %s" % [destinations[i], _label(destinations[i])], travel.bind(i))

func _team_info() -> void:
	_buttons_clear()
	destinations.clear()
	_present_room([])
	var lines := PackedStringArray(["TEAM ROSTER · Select companions at camp; assign their specialty in the field."])
	for person in roster:
		lines.append("%s  ·  %s" % [person, Guide.SKILLS[person]])
	instruction.text = "\n".join(lines)
	_button("Back to camp", _refresh)

func _read_guide() -> void:
	_buttons_clear()
	destinations.clear()
	_present_room([])
	instruction.text = "FIELD GUIDE\n" + "\n".join(journal)
	_button("Close guide", _refresh)

func _finish() -> void:
	if current != house.goal_room() or journal.size() < 3: return
	phase = "won"
	ended = true
	_refresh()

func _toggle(member: String) -> void:
	if phase != "camp" or not roster.has(member): return
	if party.has(member): party.erase(member)
	elif party.size() < 3: party.append(member)
	_refresh()

func _assign(member: String) -> void:
	var event := _event()
	if not party.has(member) or duties.has(member) or event.helper != member: return
	duties[member] = true
	resolve(event.safe, member)

func resolve(option: int, member: String = "") -> void:
	if ended or cleared.has(current): return
	var event := _event()
	if option < 0 or option >= event.options.size(): return
	var safe: bool = option == event.safe
	if not safe: hp = maxi(0, hp - 3)
	message = ("You lead the team through safely. " if member.is_empty() else member + " carries out your order. ") if safe else "The academy takes 3 health. "
	message += event.rule
	if not journal.has(event.rule): journal.append(event.rule)
	cleared[current] = true
	if hp <= 0:
		phase = "lost"
		ended = true
	_refresh()

func travel(index: int) -> void:
	if ended or index < 0 or index >= destinations.size(): return
	current = destinations[index]
	moves += 1
	message = "Choose the next crossing."
	var recruit_index: int = Array(house.recruit_rooms()).find(current)
	if recruit_index >= 0 and not roster.has(Guide.NAMES[recruit_index]):
		var found: String = Guide.NAMES[recruit_index]
		roster.append(found)
		party.append(found)
		message = found + " steps out of the empty classroom and joins you."
	if current == house.camp_room():
		camp_reached = true
		phase = "camp"
		cleared[current] = true
		hp = 9
		duties.clear()
		for i in range(2, Guide.NAMES.size()):
			if not roster.has(Guide.NAMES[i]): roster.append(Guide.NAMES[i])
		message = "The common room is warm. Your team rests here."
	else:
		phase = "expedition" if camp_reached else "approach"
	_refresh()

func mcp_observe() -> Dictionary:
	var buttons := []
	for b in choices.get_children():
		if b is Button:
			var center: Vector2 = b.get_global_rect().get_center()
			buttons.append({"label": b.text, "x": center.x, "y": center.y})
	return {"seed": run_seed, "room": current, "camp": house.camp_room(), "goal": house.goal_room(), "recruits": Array(house.recruit_rooms()), "phase": phase, "health": hp, "roster":roster, "party":party, "journal":journal,
		"moves": moves, "ended": ended, "exits": Array(destinations), "cleared": cleared.keys(), "prompt": instruction.text, "buttons": buttons}

func _present_room(labels: Array) -> void:
	var path := lot_directory.path_join(current + ".json")
	var title := _label(current) + "  /  " + current
	lot_stamp = -1
	if FileAccess.file_exists(path):
		lot_stamp = FileAccess.get_modified_time(path)
		if room_view.set_freeso_room(title, labels, path) != OK:
			push_warning("Unreadable FreeSO room projection: " + path)
	else:
		room_view.set_room(title, labels)

func _process(delta: float) -> void:
	if ended or current.is_empty(): return
	lot_check += delta
	if lot_check < 1.0: return
	lot_check = 0.0
	var path := lot_directory.path_join(current + ".json")
	var stamp := int(FileAccess.get_modified_time(path)) if FileAccess.file_exists(path) else -1
	if stamp != lot_stamp:
		var labels := []
		for id in destinations: labels.append(_door_tag(id))
		_present_room(labels)
