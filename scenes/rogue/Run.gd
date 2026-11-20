extends Control
## The topology solver owns the main route. Run composes encounters, crew, and the optional sliding wing.
const House = preload("res://scenes/rogue/HouseMap.cs")
const Room = preload("res://scenes/rogue_view/RogueRoomView.tscn")
const Guide = preload("res://scenes/rogue_rules/FieldGuide.gd")
const Rules = preload("res://scenes/rogue_rules/NightRules.gd")
const Crew = preload("res://scenes/rogue_rules/ExpeditionCrew.gd")
const Wing = preload("res://scenes/rogue/SlidingWing.gd")
const Camp = preload("res://scenes/rogue_camp/CampResidents.gd")
const CampActors = preload("res://scenes/rogue_view/CampActors.gd")

const Visit := preload("res://scenes/blue_prince_lab/vesper/VesperVisit.gd")
var vesper: Visit
var vesper_recovered := false
var vesper_progress: RefCounted
var architecture_lab: Node3D
var house
var run_seed: int
var current := ""
var cleared := {}
var visited := {}
var hp := 9
var stability := 100
var roster: Array = []
var party: Array = []
var journal: Array = []
var notes: Array[String] = []
var camp_reached := false
var phase := "approach"
var message := ""
var inspected := false
var presentation := ""
var reading := false
var moves := 0
var elapsed_hour := 4.0
var ended := false
var room_view
var crew := Crew.new()
var wing := Wing.new()
var camp := Camp.new()
var camp_ready := false
var camp_active := false
var camp_seconds := 0.0
var camp_actors
var camp_watch: Label
var stats: Label
var instruction: Label
var choices: HFlowContainer
var destinations := PackedStringArray()
var _modal_layer: ColorRect
var _sheet: VBoxContainer
var _modal_kind := ""
var _rain_hold := 0.0
var _rain_exposure := 0.0
var _death_stage := ""
var _legacy_written := false
var _legacy_input: LineEdit
var _quiet := false
var _audio: AudioStreamPlayer

func _ready() -> void:
	if "--architecture-lab" in OS.get_cmdline_user_args():
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		var script: GDScript = load("res://scenes/blue_prince_lab/Hall.gd")
		architecture_lab = script.new()
		add_child(architecture_lab)
		return
	var theme_pack := Theme.new()
	theme_pack.default_font_size = 16
	for state in ["normal", "hover", "pressed", "focus", "disabled"]:
		var fills := {"normal": "1b272b", "hover": "354447", "pressed": "45392d", "focus": "1b272b", "disabled": "161f23"}
		var style := _panel_style(Color(fills[state]), Color("b38f66") if state in ["hover", "focus"] else Color("465859"))
		style.content_margin_left = 11
		style.content_margin_right = 11
		style.content_margin_top = 7
		style.content_margin_bottom = 7
		theme_pack.set_stylebox(state, "Button", style)
	theme_pack.set_color("font_color", "Label", Color("e0d6c5"))
	theme = theme_pack
	var back := ColorRect.new()
	back.color = Color("0c1217")
	back.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(back)
	back.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var layout := VBoxContainer.new()
	add_child(layout)
	layout.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	layout.offset_left = 18
	layout.offset_right = -18
	layout.offset_top = 10
	layout.offset_bottom = -10
	layout.add_theme_constant_override("separation", 7)
	stats = Label.new()
	stats.add_theme_font_size_override("font_size", 18)
	stats.add_theme_color_override("font_color", Color("d4bb95"))
	layout.add_child(stats)
	camp_watch = Label.new()
	camp_watch.add_theme_font_size_override("font_size", 14)
	layout.add_child(camp_watch)
	room_view = Room.instantiate()
	room_view.expedition_view = true
	room_view.size_flags_vertical = Control.SIZE_EXPAND_FILL
	layout.add_child(room_view)
	room_view.exit_selected.connect(travel)
	room_view.landmark_inspected.connect(_inspect)
	room_view.lane_selected.connect(resolve)
	instruction = Label.new()
	instruction.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	instruction.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	layout.add_child(instruction)
	choices = HFlowContainer.new()
	choices.alignment = FlowContainer.ALIGNMENT_CENTER
	layout.add_child(choices)
	_create_overlay()
	_quiet = "--no-rule-save" in OS.get_cmdline_user_args()
	if _quiet: notes.assign([Rules.FIRST_NOTE])
	else: notes = Rules.load_notes()
	if not DisplayServer.get_name() == "headless": _start_ambience()
	var initial_seed := randi()
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--run-seed=") and arg.get_slice("=", 1).is_valid_int():
			initial_seed = int(arg.get_slice("=", 1))
	new_run(initial_seed)

func _panel_style(fill: Color, edge: Color) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = fill
	style.border_color = edge
	style.set_border_width_all(1)
	style.set_corner_radius_all(5)
	return style

func _create_overlay() -> void:
	_modal_layer = ColorRect.new()
	_modal_layer.color = Color(0.025, 0.036, 0.048, 0.82)
	add_child(_modal_layer)
	_modal_layer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var center := CenterContainer.new()
	_modal_layer.add_child(center)
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var card := PanelContainer.new()
	center.add_child(card)
	card.custom_minimum_size.x = 720
	var style := _panel_style(Color("19252a"), Color("b38f66"))
	style.content_margin_left = 26
	style.content_margin_right = 26
	style.content_margin_top = 20
	style.content_margin_bottom = 20
	card.add_theme_stylebox_override("panel", style)
	_sheet = VBoxContainer.new()
	_sheet.add_theme_constant_override("separation", 12)
	card.add_child(_sheet)
	_modal_layer.hide()

func new_run(value: int) -> void:
	if vesper: _leave_vesper()
	vesper_recovered=false
	vesper_progress=null
	_close_sheet()
	_leave_camp()
	camp = Camp.new()
	crew = Crew.new()
	wing.reset(value)
	camp_ready = false
	run_seed = value
	house = House.new()
	if not house.generate(value):
		ended = true
		instruction.text = "The floor could not form. Start a new expedition."
		_clear(choices)
		_button("New expedition", func(): new_run(randi()))
		return
	current = house.start_room()
	room_view.set_instance_id("")
	cleared = {current: true}
	visited = {current: true}
	hp = 9
	stability = 100
	roster.clear()
	party.clear()
	journal.clear()
	camp_reached = false
	phase = "approach"
	message = "Find the Public Hall. WASD to move, click the scene to look, E to inspect, Esc to release the cursor."
	inspected = false
	moves = 0
	elapsed_hour = 4.0
	ended = false
	_death_stage = ""
	_legacy_written = false
	_reset_rain()
	_refresh()
	_read_guide()

func _clear(container: Node) -> void:
	for child in container.get_children():
		container.remove_child(child)
		child.queue_free()

func _button(text: String, callback: Callable, parent: Container = null) -> Button:
	var b := Button.new()
	b.text = text
	b.focus_mode = Control.FOCUS_NONE
	b.custom_minimum_size = Vector2(105, 38)
	b.pressed.connect(callback)
	(choices if parent == null else parent).add_child(b)
	return b

func _template(id: String) -> String:
	return str(Wing.TEMPLATES.get(id, house.template_id(id)))

func _stage() -> String:
	return house.room_stage(current)

func _label(id: String) -> String:
	if id == house.camp_room(): return "Public Hall"
	if id == house.goal_room(): return "Observatory"
	if id.begins_with("fold_"): return "Folding " + id.trim_prefix("fold_").capitalize()
	match house.room_stage(id):
		"echo": return "Echo Corridor"
		"rain": return "Time Rain"
		"rewrite": return "Curator's Threshold"
	return str({"foyer":"Grand Stair Hall", "kitchen":"Hot Kitchen", "lecture":"Lecture Theatre", "dining":"Refectory", "living_hall":"Living Hall", "clinic":"Infirmary", "valve_gallery":"Valve Gallery", "service_stair":"Service Stairs"}.get(_template(id), "Unknown room"))

func _door_tag(id: String) -> String:
	if id == house.camp_room(): return "Hall"
	if id == house.goal_room(): return "Observatory"
	if id == house.start_room(): return "Entry"
	if id.begins_with("fold_"): return id.trim_prefix("fold_").capitalize()
	return ("A" if id.begins_with("approach") else "E") + id.get_slice("_", 1)

func _variant() -> bool:
	return Rules.truth(run_seed, current, _stage())

func _event() -> Dictionary:
	var special := Rules.encounter(_stage(), _variant())
	if not special.is_empty(): return special
	var event := Guide.encounter(run_seed, current, _template(current))
	if phase == "expedition" and party.size() >= 2:
		var rear: String = party.back()
		var original: String = event.options[event.safe]
		event.clue += "\nThe rear guard’s echo moves before they do. Use the verified signal, then send the crew through one at a time."
		event.options[event.safe] = original + " · cross in single file"
		event.options.append(original + " · follow " + rear + "’s echo together")
	return event

func _inspect() -> void:
	if ended or not _modal_kind.is_empty() or inspected or cleared.has(current) or current == house.goal_room(): return
	inspected = true
	room_view._release_mouse()
	_refresh()

func _input(event: InputEvent) -> void:
	if vesper:
		if event is InputEventKey and event.pressed and not event.echo and event.physical_keycode == KEY_ESCAPE:
			_leave_vesper()
			get_viewport().set_input_as_handled()
		return
	if is_instance_valid(architecture_lab) or not event is InputEventKey or not event.pressed or event.echo or choices == null: return
	if event.physical_keycode == KEY_TAB and not ended:
		if _modal_kind == "guide": _close_sheet()
		else: _read_guide()
	elif event.physical_keycode == KEY_ESCAPE and not _modal_kind.is_empty():
		_close_sheet()
	else: return
	get_viewport().set_input_as_handled()

func _refresh() -> void:
	_clear(choices)
	destinations.clear()
	_update_stats()
	camp_watch.visible = phase == "camp"
	if ended:
		_present_room([])
		room_view._release_mouse()
		instruction.text = "The morning bell rings. The academy remembers your names." if phase == "won" else message + "\nAt dawn, another captain finds your field card. You may leave exactly one change."
		if phase == "lost" and not _legacy_written: _button("Edit inherited card", _legacy_sheet)
		_button("New expedition", func(): new_run(randi()))
		_button("Replay seed", func(): new_run(run_seed))
		return
	if current != house.goal_room() and not cleared.has(current):
		_present_room([])
		var event := _event()
		if not inspected:
			instruction.text = message + "\n" + event.objective + " · Approach and press E, or inspect below."
			_button("Inspect room", _inspect)
		else:
			instruction.text = event.clue
			if not message.is_empty() and message != "Choose the next crossing.": instruction.text = message + "\n" + instruction.text
			for i in event.options.size():
				_button(event.options[i], resolve.bind(i))
			if party.has(event.helper) and crew.deployable(event.helper):
				_button("Ask " + event.helper, _assign.bind(event.helper))
			if phase == "expedition" and not party.is_empty():
				_button("Leave " + str(party.back()) + " to hold the door", _betray.bind(party.back()))
		_button("Field card · Tab", _read_guide)
		return
	destinations = PackedStringArray(house.exits(current))
	if camp_reached: destinations.append_array(PackedStringArray(wing.exits(current)))
	var labels := []
	for id in destinations: labels.append(_door_tag(id))
	_present_room(labels)
	instruction.text = message
	if phase == "camp":
		_enter_camp()
		instruction.text += "\nSafe ground · Manage the crew, build facilities, or slide the wing on the survey table."
		_button("Crew & facilities", _team_info)
		_button("Sliding wing", _board_sheet)
		_button("Vesper Index · filed" if vesper_recovered else "Investigate Vesper Index", _open_vesper)
	var survivor := _field_candidate()
	if not survivor.is_empty():
		instruction.text += "\n%s emerges from cover and waits for your answer." % survivor
		_button("Invite " + survivor, _invite_field.bind(survivor))
	if current == house.goal_room():
		instruction.text += "\nRead three distinct learned rules to wake the academy."
		if journal.size() >= 3: _button("Wake the house", _finish)
	_button("Field card · Tab", _read_guide)
	for i in destinations.size():
		_button("Enter · %s [%s]" % [_label(destinations[i]), _door_tag(destinations[i])], travel.bind(i)).set_meta("destination", destinations[i])

func _sheet_label(text: String, size: int = 16, accent: bool = false) -> void:
	var row := Label.new()
	row.text = text
	row.custom_minimum_size.x = 670
	row.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	row.add_theme_font_size_override("font_size", size)
	if accent: row.add_theme_color_override("font_color", Color("eccda5"))
	_sheet.add_child(row)

func _open_sheet(kind: String, title: String, subtitle: String) -> void:
	_clear(_sheet)
	_modal_kind = kind
	reading = kind == "guide"
	_modal_layer.show()
	room_view.set_modal(true)
	_sheet_label(subtitle, 13, true)
	_sheet_label(title, 28, true)

func _close_sheet() -> void:
	_modal_kind = ""
	reading = false
	_modal_layer.hide()
	room_view.set_modal(false)

func _read_guide() -> void:
	_open_sheet("guide", "Keep this card dry.", "FIELD CARD   /   AUTHORISED COPY   ·   TAB TO CLOSE")
	for line in Rules.ORIGINAL: _sheet_label(line)
	if _stage() == "rewrite" and inspected:
		_sheet_label("RED INK · The Curator: CROSS BEFORE THE BELL.", 16, true)
	if not notes.is_empty(): _sheet_label("INHERITED MARGIN\n" + "\n".join(notes), 14, true)
	if vesper_recovered: _sheet_label("ARCHIVE EVIDENCE · E. Vale signed for the same key in 1903 and 1907.", 14)
	if not journal.is_empty(): _sheet_label("VERIFIED IN THE FIELD · %d distinct rules" % journal.size(), 14)
	_button("Fold card · Tab", _close_sheet, _sheet)

func _legacy_sheet() -> void:
	_open_sheet("legacy", "Write for the next captain.", "AFTER DEATH   /   ONE EDIT PER EXPEDITION")
	_sheet_label("Leave a warning, or edit the suggested wording below.")
	_legacy_input = LineEdit.new()
	_legacy_input.max_length = 160
	_legacy_input.text = Rules.death_note(_death_stage)
	_sheet.add_child(_legacy_input)
	if not notes.is_empty(): _sheet_label("Last margin entry: " + notes.back(), 14)
	_button("Add proposed rule", _edit_note.bind("add"), _sheet).disabled = notes.size() >= 4
	_button("Replace last margin rule", _edit_note.bind("replace"), _sheet).disabled = notes.is_empty()
	_button("Erase last margin rule", _edit_note.bind("erase"), _sheet).disabled = notes.is_empty()
	_button("Leave the card unchanged", _close_sheet, _sheet)

func _edit_note(action: String) -> void:
	if not ended or phase != "lost" or _legacy_written or _modal_kind != "legacy": return
	var wording := _legacy_input.text.strip_edges()
	if action in ["add", "replace"] and wording.is_empty():
		_sheet_label("Write a warning before saving.")
		return
	var next := notes.duplicate()
	match action:
		"add":
			if next.size() >= 4: return
			next.append(wording)
		"replace":
			if next.is_empty(): return
			next[next.size() - 1] = wording
		"erase":
			if next.is_empty(): return
			next.pop_back()
		_: return
	if not _quiet and not Rules.save_notes(next):
		_sheet_label("Could not save the field card. No edit was applied.")
		return
	notes = next
	_legacy_written = true
	_close_sheet()
	_refresh()
	instruction.text = "The ink dries. Your edit will be on the next field card."

func _team_info() -> void:
	if phase != "camp": return
	_open_sheet("crew", "The Public Hall", "SAFE GROUND   /   %d SUPPLY CRATES" % crew.supplies)
	for id: String in Guide.NAMES:
		var row := HBoxContainer.new()
		_sheet.add_child(row)
		var label := Label.new()
		label.text = "%s · %s\n%s" % [id, crew.status(id) if roster.has(id) else "available to recruit", Guide.SKILLS[id]]
		label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		label.add_theme_font_size_override("font_size", 14)
		row.add_child(label)
		if not roster.has(id):
			_button("Recruit", _invite_hall.bind(id), row)
			continue
		var b := _button("Stay in hall" if party.has(id) else "Deploy", _toggle.bind(id), row)
		b.disabled = not crew.deployable(id) or (party.size() >= 3 and not party.has(id))
		if crew.people[id].trust < 2 and crew.deployable(id):
			_button("Make amends · 1", _amend.bind(id), row).disabled = crew.supplies < 1
	var build := HBoxContainer.new()
	_sheet.add_child(build)
	for facility in crew.upgrades:
		var placed: bool = crew.upgrades[facility]
		var b := _button(facility + (" · Built" if placed else " · 3 crates"), _build.bind(facility), build)
		b.disabled = placed or crew.supplies < 3
	_sheet_label("Infirmary doubles treatment speed. The watch lamp steadies the next expedition.", 14)
	_button("Back to hall", _close_sheet, _sheet)

func _toggle(member: String) -> void:
	if phase != "camp" or not crew.deployable(member): return
	if party.has(member): party.erase(member)
	elif party.size() < 3: party.append(member)
	_update_stats()
	_team_info()

func _amend(member: String) -> void:
	if phase != "camp" or not crew.deployable(member) or crew.supplies < 1 or crew.people[member].trust >= 2: return
	crew.supplies -= 1
	crew.people[member].trust = 2
	_update_stats()
	_team_info()

func _build(facility: String) -> void:
	if phase != "camp" or not crew.build(facility): return
	if facility == "Watch lamp": stability = 100
	_update_stats()
	_team_info()

func _board_sheet() -> void:
	if phase != "camp": return
	_open_sheet("board", "Survey of the Sliding Wing", "PUBLIC HALL   /   THE ROOMS MOVE, NOT JUST THE MAP")
	_sheet_label("Click a tile next to the empty space. Letters mark door sides; touching doors must face each other.", 15)
	var grid := GridContainer.new()
	grid.columns = 3
	_sheet.add_child(grid)
	for i in wing.tiles.length():
		var tile: String = wing.tiles[i]
		var b := _button(Wing.LEGEND[tile], _slide.bind(i), grid)
		b.custom_minimum_size.x = 210
		b.disabled = not wing.can_slide(i)
		if tile in ["C", "G"]: b.add_theme_color_override("font_disabled_color", Color("e7ba80"))
	_sheet_label("A continuous route reaches the Observatory." if wing.connected() else "The Observatory is not connected. The normal expedition remains open.", 15, true)
	var row := HBoxContainer.new()
	_sheet.add_child(row)
	_button("Reset layout", func(): wing.restore(); _refresh(); _board_sheet(), row)
	_button("Back to hall", _close_sheet, row)

func _slide(index: int) -> void:
	if phase != "camp" or not wing.slide(index): return
	_refresh()
	_board_sheet()

func _assign(member: String) -> void:
	var event := _event()
	if ended or not inspected or cleared.has(current) or not party.has(member) or event.helper != member: return
	if not crew.willing(member):
		message = member + " refuses. Give them time to rest, or solve it yourself."
		_refresh()
		return
	crew.people[member].spent = true
	crew.people[member].stress += 1
	message = member + ": “" + str(event.hint) + "”"
	if _stage() in ["rain", "rewrite"]:
		_refresh()
		return
	resolve(event.safe, member)

func _betray(member: String) -> void:
	if phase != "expedition" or ended or not inspected or cleared.has(current) or not party.has(member): return
	if not crew.willing(member):
		message = member + " sees your hand on the latch and refuses to go first."
		_refresh()
		return
	crew.abandon(member, party)
	party.erase(member)
	_complete(_event(), member + " is hurt holding the door and will need the clinic. The others saw what you did.")

func resolve(option: int, member: String = "") -> void:
	if ended or not _modal_kind.is_empty() or not inspected or cleared.has(current): return
	var event := _event()
	if option < 0 or option >= event.options.size(): return
	var stage := _stage()
	if stage == "rain":
		if room_view.lane_at_feet() != option or (option == 0 and _rain_hold < 1.35):
			message = "Stand at the end of the selected strip. On brass, wait for the lamp to steady."
			_refresh()
			return
	var shortcut := stage == "rewrite" and option == 1 and _variant()
	if option == event.safe or shortcut:
		var line: String = member + " reads the room for you. " + message if not member.is_empty() else "The door yields."
		match stage:
			"echo":
				if option == 1:
					room_view.repeat_threshold()
					line = "You turn back. The same corridor returns, but this time the two clocks agree."
			"rain": line = "The lamp steadies. The rain leaves the brass untouched."
			"rewrite":
				if shortcut:
					crew.supplies += 2
					line = "The double seal holds. You beat the bell and recover two extra crates."
				else:
					elapsed_hour += 1.5
					stability = maxi(18, stability - 8)
					line = "The original rule gets you through. It costs you time; the cache shuts as the bell rings."
		_complete(event, line)
		return
	var damage := 9 if stage == "rewrite" else 3
	if stage == "rain": damage = 4
	hp = maxi(0, hp - damage)
	stability = maxi(0, stability - (24 if stage == "rain" else 20))
	crew.pressure(party, 2)
	if not party.is_empty() and phase == "expedition":
		var injured: String = party.pop_back()
		crew.wound(injured, 22.0)
		message = "%s retreats to the Hall injured." % injured
	else: message = ""
	if hp <= 0:
		_death_stage = stage
		phase = "lost"
		ended = true
		message = "The shutter closes before the bell. The red ink is still wet." if stage == "rewrite" else "The academy takes the last of your strength."
		_refresh()
	else:
		_complete(event, "The crossing costs %d health. %s" % [damage, message], false)

func _complete(event: Dictionary, line: String, clean: bool = true) -> void:
	message = line
	if not journal.has(event.rule): journal.append(event.rule)
	if clean: crew.supplies += 1
	cleared[current] = true
	_refresh()

func _finish() -> void:
	if current != house.goal_room() or journal.size() < 3 or not camp_reached: return
	phase = "won"
	ended = true
	_refresh()

func _field_candidate() -> String:
	if phase != "approach" or not cleared.has(current): return ""
	var index: int = Array(house.recruit_rooms()).find(current)
	if index < 0: return ""
	var id: String = Guide.NAMES[index]
	return "" if roster.has(id) else id

func _invite_field(id: String) -> void:
	if ended or not _modal_kind.is_empty() or id.is_empty() or _field_candidate() != id: return
	_recruit(id, true)
	message = id + " agrees to walk with you."
	_refresh()

func _invite_hall(id: String) -> void:
	if ended or phase != "camp" or _modal_kind != "crew" or id not in Guide.NAMES or roster.has(id): return
	_recruit(id, false)
	_team_info()

func _recruit(id: String, deploy: bool) -> void:
	if roster.has(id): return
	roster.append(id)
	crew.recruit(id)
	if deploy: party.append(id)

func travel(index: int) -> void:
	if ended or not _modal_kind.is_empty() or index < 0 or index >= destinations.size(): return
	_leave_camp()
	current = destinations[index]
	visited[current] = true
	inspected = false
	_reset_rain()
	moves += 1
	elapsed_hour += 0.4
	message = "Choose the next crossing."
	if current == house.camp_room():
		var first := not camp_reached
		camp_reached = true
		phase = "camp"
		cleared[current] = true
		hp = 9
		stability = 100 if crew.upgrades["Watch lamp"] else 90
		crew.return_to_camp()
		message = "The Public Hall is warm. The wall clock begins to move again." if first else "Back on safe ground."
	else:
		phase = "expedition" if camp_reached else "approach"
	_refresh()

func _update_stats() -> void:
	var district := "THE APPROACH" if not camp_reached else ("PUBLIC HALL" if phase == "camp" else "EXPEDITION")
	var hour := fposmod(elapsed_hour, 24.0)
	stats.text = "THE SLEEPING ACADEMY  /  %s     ·     HP %d/9     Nerve %d/100     Team %d/4     Crates %d     ·     %02d:%02d" % [district, hp, stability, party.size() + 1, crew.supplies, floori(hour), floori(fposmod(hour, 1.0) * 60.0)]

func _present_room(labels: Array) -> void:
	room_view.set_hour(elapsed_hour)
	room_view.set_instance_id(current)
	var xml := "res://content/academy_lots/%s.xml" % _template(current)
	if room_view.set_blueprint_room(_label(current), labels, xml) == OK:
		presentation = "blueprint"
	else:
		presentation = "unavailable"
		room_view.set_room("Missing academy blueprint: " + _label(current), [])
	room_view.set_night(_stage(), _variant(), inspected and not ended and not cleared.has(current), stability, phase == "camp")
	room_view.set_field_party([] if phase == "camp" else party)
	room_view.set_inspection_target(not ended and not inspected and not cleared.has(current) and current != house.goal_room())
	room_view.set_modal(not _modal_kind.is_empty() or ended)
	if is_instance_valid(_audio): _audio.pitch_scale = 1.38 if _stage() == "rain" else (0.73 if phase == "camp" else 1.0)

func _open_vesper() -> void:
	if phase != "camp" or vesper or not _modal_kind.is_empty(): return
	room_view.set_modal(true)
	room_view.get_parent().hide()
	vesper=Visit.new()
	if vesper_progress and not vesper_progress.crossed: vesper.puzzle.rules=vesper_progress
	vesper.puzzle.recovered.connect(_file_vesper)
	vesper.puzzle.return_requested.connect(_leave_vesper, CONNECT_DEFERRED)
	add_child(vesper)

func _file_vesper() -> void:
	if vesper_recovered: return
	vesper_recovered=true
	crew.supplies+=1

func _leave_vesper() -> void:
	vesper_progress=vesper.puzzle.rules
	remove_child(vesper)
	vesper.queue_free()
	vesper=null
	room_view.get_parent().show()
	room_view.set_modal(false)
	if vesper_recovered: message="Night register filed: the same key was signed for twice. +1 supply recovered."
	_refresh()

func _enter_camp() -> void:
	if camp_active: return
	if not camp_ready:
		var layout: Dictionary = room_view.camp_layout(Guide.NAMES)
		camp_ready = camp.setup("Captain", layout.graph, layout.people, layout.objects)
	if not camp_ready or not camp.enter_camp():
		camp_watch.text = "The Hall is quiet."
		return
	camp_active = true
	camp_actors = CampActors.new()
	room_view.get_node("RoomViewport").add_child(camp_actors)
	_update_camp(0.0)

func _leave_camp() -> void:
	if not camp_active: return
	camp.leave_camp()
	camp_active = false
	camp_seconds = 0.0
	if is_instance_valid(camp_actors): camp_actors.queue_free()

func _update_camp(seconds: float) -> void:
	var rows: Dictionary = camp.snapshot().residents
	camp_actors.sync(rows, seconds)
	var lines := PackedStringArray()
	for id: String in rows:
		var row: Dictionary = rows[id]
		lines.append("%s: %s" % [id, row.job.get("object_id", "resting") if not roster.has(id) or crew.deployable(id) else crew.status(id)])
	camp_watch.text = "  ·  ".join(lines)

func _reset_rain() -> void:
	_rain_hold = 0.0
	_rain_exposure = 0.0

func _process(delta: float) -> void:
	if house == null or ended: return
	if phase == "camp" and crew.rest(delta) and _modal_kind == "crew": _team_info()
	if camp_active:
		camp_seconds += delta
		if camp_seconds >= Camp.TICK_SECONDS:
			camp.step()
			camp_seconds -= Camp.TICK_SECONDS
			_update_camp(Camp.TICK_SECONDS)
	if _stage() != "rain" or not inspected or cleared.has(current) or not room_view.is_walking_view(): return
	match room_view.lane_at_feet():
		0:
			if _rain_hold < 1.35:
				_rain_hold += delta
				if _rain_hold >= 1.35: instruction.text = "The lamp has steadied. Press E to cross, or confirm below."
		1:
			_rain_hold = 0.0
			_rain_exposure += delta
			if _rain_exposure < 1.0: return
			_rain_exposure -= 1.0
			elapsed_hour += 0.23
			stability = maxi(0, stability - 3)
			room_view.set_hour(elapsed_hour)
			room_view.set_night("rain", _variant(), true, stability, false)
			_update_stats()
		_:
			_rain_hold = 0.0

func _start_ambience() -> void:
	# Generate a periodic low mechanical hum without external audio assets or a sharp loop seam.
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = 12000
	stream.loop_mode = AudioStreamWAV.LOOP_FORWARD
	stream.loop_end = 48000
	var pcm := PackedByteArray()
	pcm.resize(stream.loop_end * 2)
	for i in stream.loop_end:
		var t := float(i) / stream.mix_rate
		var wave := (sin(TAU * 49.0 * t) * 0.57 + sin(TAU * 73.5 * t) * 0.27) * (0.68 + 0.32 * sin(TAU * 0.25 * t))
		pcm.encode_s16(i * 2, roundi(wave * 3800.0))
	stream.data = pcm
	_audio = AudioStreamPlayer.new()
	_audio.stream = stream
	_audio.volume_db = -17.0
	add_child(_audio)
	_audio.play()

func mcp_observe() -> Dictionary:
	if is_instance_valid(architecture_lab): return architecture_lab.snapshot()
	if vesper: return {"phase":phase, "modal":"vesper", "vesper":vesper.puzzle.snapshot(), "filed":vesper_recovered}
	var buttons := []
	var roots: Array[Node] = []
	roots.append(choices if _modal_kind.is_empty() else _sheet)
	while not roots.is_empty():
		for node in roots.pop_front().get_children():
			if node is Button:
				var point: Vector2 = node.get_global_rect().get_center()
				buttons.append({"label": node.text, "x": point.x, "y": point.y, "destination": node.get_meta("destination", ""), "enabled": not node.disabled})
			elif node is Container: roots.append(node)
	return {"seed": run_seed, "room": current, "camp": house.camp_room(), "goal": house.goal_room(), "recruits": Array(house.recruit_rooms()), "phase": phase,
		"health": hp, "nerve": stability, "roster": roster, "party": party, "crew": crew.people.duplicate(true), "journal": journal, "modal": _modal_kind,
		"presentation": presentation, "template": _template(current), "player_observation": room_view.player_observation(), "moves": moves, "ended": ended,
		"exits": Array(destinations), "cleared": cleared.keys(), "prompt": instruction.text, "buttons": buttons, "stage": _stage(), "wing": wing.tiles}
