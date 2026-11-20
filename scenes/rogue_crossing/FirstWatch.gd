extends Control
## The Night Watch. Graph connectivity, apparatus state and resident autonomy are independent systems.
const House := preload("res://scenes/rogue/HouseMap.cs")
const Room := preload("res://scenes/rogue_view/RogueRoomView.tscn")
const Crossing := preload("Crossing.gd")
const Rooms := preload("Rooms.gd")
const Cast := preload("Roster.gd")
const Witnesses := preload("HallWitnesses.gd")
const Crew := preload("res://scenes/rogue_rules/ExpeditionCrew.gd")
const Camp := preload("res://scenes/rogue_camp/CampResidents.gd")
const MARGINS := "user://night_watch_margins.txt"

var house: RefCounted
var room_view
var run_seed: int
var current := ""
var phase := "approach"
var rooms := {}
var cleared := {}
var destinations := PackedStringArray()
var party: Array[String] = []
var roster: Array[String] = []
var agreed := {}
var facts := {}
var depositions := {}
var camp_reached := false
var prospect := 0
var hp := 9
var nerve := 100
var clock := 4.0
var message := ""
var handbook := false
var moves := 0
var crew := Crew.new()
var camp := Camp.new()
var camp_actors: Node3D
var camp_time := 0.0
var margins := ""
var inherited := false
var _no_save := false
var modal := ""
var _acting := -1
var _performing := false
var _watch_number := 0
var _flow: HFlowContainer
var _status: Label
var _instruction: Label
var _overlay: ColorRect
var _sheet: VBoxContainer
var _scroll: ScrollContainer
var _entry: LineEdit
var _lab: Node3D

func _ready() -> void:
	if "--architecture-lab" in OS.get_cmdline_user_args():
		mouse_filter = MOUSE_FILTER_IGNORE
		var lab: GDScript = load("res://scenes/blue_prince_lab/Hall.gd")
		_lab = lab.new()
		add_child(_lab)
		return
	_make_hud()
	_no_save = "--no-rule-save" in OS.get_cmdline_user_args()
	if not _no_save and FileAccess.file_exists(MARGINS): margins = FileAccess.get_file_as_string(MARGINS).left(180)
	var chosen_seed := int(randi())
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--run-seed=") and arg.get_slice("=", 1).is_valid_int(): chosen_seed = int(arg.get_slice("=", 1))
	new_run(chosen_seed)

func _style(fill: Color, border: Color, padding := 7) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = fill
	s.border_color = border
	s.set_border_width_all(1)
	s.set_corner_radius_all(4)
	for side in [SIDE_LEFT, SIDE_RIGHT, SIDE_TOP, SIDE_BOTTOM]: s.set_content_margin(side, padding)
	return s

func _make_hud() -> void:
	var skin := Theme.new()
	skin.default_font_size = 16
	for state in ["normal", "hover", "pressed", "focus", "disabled"]:
		var tint := Color("192827") if state == "normal" else (Color("423a2b") if state != "disabled" else Color("192020"))
		skin.set_stylebox(state, "Button", _style(tint, Color("706759")))
	skin.set_color("font_color", "Label", Color("e9d9bd"))
	theme = skin
	var backdrop := ColorRect.new()
	backdrop.color = Color("111816")
	backdrop.mouse_filter = MOUSE_FILTER_IGNORE
	add_child(backdrop)
	backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var hud := VBoxContainer.new()
	add_child(hud)
	hud.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	hud.offset_left = 18
	hud.offset_right = -18
	hud.offset_top = 10
	hud.offset_bottom = -10
	hud.add_theme_constant_override("separation", 7)
	_status = Label.new()
	_status.add_theme_font_size_override("font_size", 17)
	hud.add_child(_status)
	room_view = Room.instantiate()
	room_view.expedition_view = true
	room_view.campaign_view = true
	room_view.field_model = Cast.attach
	room_view.size_flags_vertical = SIZE_EXPAND_FILL
	hud.add_child(room_view)
	room_view.exit_selected.connect(travel)
	room_view.crossing_selected.connect(_inspect)
	room_view.witness_selected.connect(_take_deposition)
	_instruction = Label.new()
	_instruction.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_instruction.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hud.add_child(_instruction)
	_flow = HFlowContainer.new()
	_flow.alignment = FlowContainer.ALIGNMENT_CENTER
	hud.add_child(_flow)
	_overlay = ColorRect.new()
	_overlay.color = Color(.025, .034, .030, .72)
	add_child(_overlay)
	_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var center := CenterContainer.new()
	_overlay.add_child(center)
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", _style(Color("202721"), Color("a88953"), 21))
	center.add_child(panel)
	_scroll = ScrollContainer.new()
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_scroll.custom_minimum_size.x = 650
	panel.add_child(_scroll)
	_sheet = VBoxContainer.new()
	_sheet.size_flags_horizontal = SIZE_EXPAND_FILL
	_sheet.add_theme_constant_override("separation", 10)
	_scroll.add_child(_sheet)
	_overlay.hide()

func _clear(row: Node) -> void:
	for c in row.get_children():
		row.remove_child(c)
		c.queue_free()

func _button(parent: Container, label: String, callback: Callable) -> Button:
	var b := Button.new()
	b.focus_mode = FOCUS_NONE
	b.text = label
	b.custom_minimum_size.y = 32
	parent.add_child(b)
	b.pressed.connect(callback)
	return b

func _label(text: String, size := 16, gold := false) -> void:
	var node := Label.new()
	node.text = text
	node.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	node.add_theme_font_size_override("font_size", size)
	if gold: node.add_theme_color_override("font_color", Color("f2ca82"))
	_sheet.add_child(node)

func _open(kind: String, title: String, folio: String) -> void:
	_clear(_sheet)
	modal = kind
	_overlay.show()
	_scroll.scroll_vertical = 0
	room_view.set_modal(true)
	_label(folio, 13, true)
	_label(title, 28, true)
	# Limit the document to 80% of the window; a long crew register scrolls inside it.
	_scroll.custom_minimum_size.y = 0
	_fit_sheet.call_deferred()

func _fit_sheet() -> void:
	if modal.is_empty(): return
	_scroll.custom_minimum_size.y = minf(_sheet.get_combined_minimum_size().y, get_viewport_rect().size.y * .80)

func _close() -> void:
	modal = ""
	_acting = -1
	_overlay.hide()
	room_view.set_modal(phase in ["lost", "won"])

func new_run(value: int) -> void:
	_close()
	_leave_hall()
	run_seed = value
	house = House.new()
	assert(house.generate_watch(value), "The watch topology must have a connected solution")
	current = house.start_room()
	room_view.set_instance_id("")
	phase = "approach"
	rooms.clear()
	cleared.clear()
	party.clear()
	roster.clear()
	agreed.clear()
	facts.clear()
	depositions.clear()
	camp_reached = false
	prospect = 0
	hp = 9
	nerve = 100
	clock = 4.0
	moves = 0
	crew = Crew.new()
	camp = Camp.new()
	handbook = false
	inherited = false
	_performing = false
	_watch_number += 1
	message = ""
	_refresh()

func _stage() -> String:
	return house.room_stage(current)

func _variant() -> bool:
	return ((str(run_seed) + "/" + current + "/" + _stage()).sha256_buffer()[0] & 1) == 0

func _room() -> Crossing:
	if not rooms.has(current): rooms[current] = Crossing.new(_stage(), _variant())
	return rooms[current]

func _survivor() -> String:
	var index: int = Array(house.recruit_rooms()).find(current)
	return Cast.encounter(run_seed, index) if index >= 0 and not cleared.has(current) else ""

func _protocol(member: String) -> String:
	return agreed.get(member, Cast.edition(member))

func _protocols() -> Array[String]:
	var result: Array[String] = ["Ivory"]
	for id in party: result.append(_protocol(id))
	return result

func _can_agree() -> bool:
	if not camp_reached or _stage() != "relay" or party.is_empty(): return false
	if _protocols().all(func(p): return p == "Ivory"): return false
	if depositions.size() >= 2 and facts.size() >= 2: return true
	return prospect >= 4 and party.all(func(id): return crew.people[id].trust >= 3 and crew.people[id].stress < 3)

func _input(event: InputEvent) -> void:
	if _lab or _performing or not event is InputEventKey or not event.pressed or event.echo or house == null: return
	if event.physical_keycode == KEY_TAB and handbook:
		if modal == "guide": _close()
		else: _read_guide()
	elif event.physical_keycode == KEY_ESCAPE and not modal.is_empty(): _close()
	else: return
	get_viewport().set_input_as_handled()

func _read_guide() -> void:
	if _performing: return
	_open("guide", "Night watch field manual", "ACADEMY PRESS  /  IVORY  /  No. 04")
	for line in Rooms.IVORY: _label(line)
	for id in party:
		var edition := _protocol(id)
		_label("%s · %s copy" % [id, edition], 15, true)
		_label("  ·  ".join(Rooms.VERSIONS[edition]), 14)
	if not margins.is_empty(): _label("Inherited pencil note / " + margins, 14)
	_button(_sheet, "Fold manual · Tab", _close)

func _inspect(group: int) -> void:
	if _performing or phase in ["won", "lost"] or not modal.is_empty() or group not in [0, 1, 2]: return
	var r := _room()
	var title: String = Rooms.FIXTURES[_stage()][group]
	_open("apparatus", title, "%s   /   %s" % [Rooms.TITLES[_stage()].to_upper(), "FILED" if cleared.has(current) else "NIGHT SERVICE"])
	_acting = group
	_label(r.read(group))
	if group == 0 and _stage() == "intake":
		_label("FROM THE PREFACE", 13, true)
		for line in Rooms.IVORY: _label(line, 15)
	if _stage() in ["exchange", "airlock", "relay"]:
		for id in party:
			var edition := _protocol(id)
			_label("%s / %s: %s" % [id, edition, Rooms.VERSIONS[edition][1 if _stage() == "airlock" else 0]], 14, true)
		if _stage() == "relay" and not _can_agree() and _protocols().any(func(p): return p != "Ivory"):
			_label("A joint order needs two depositions and two field traces, or the crew’s confidence in your record.", 13)
	for option: Dictionary in r.options(group, _protocols(), _can_agree()):
		_button(_sheet, option.text, _act.bind(current, group, option.id))
	_button(_sheet, "Put it down · Esc", _close)

func _act(room_id: String, group: int, id: String) -> void:
	if _performing or room_id != current or modal != "apparatus" or _acting != group or cleared.has(current): return
	var r := _room()
	var result := r.act(group, id, _protocols(), _can_agree(), depositions.size())
	if result.is_empty(): return
	_close()
	room_view.show_crossing_action(group, id, result)
	message = result.line
	if result.get("agree", false):
		for member in party: agreed[member] = "Ivory"
	if result.damage > 0:
		hp = maxi(0, hp - int(result.damage))
		nerve = maxi(10, nerve - 12 * int(result.damage))
		crew.pressure(party, 1)
		if phase == "expedition" and not party.is_empty() and crew.people[party[-1]].stress >= 3:
			var rear: String = party.pop_back()
			crew.wound(rear, 24.0)
			message += " %s falls back to the Hall clinic." % rear
		message += "  −%d health. The crossing is still closed." % result.damage
		if hp == 0: phase = "lost"
	elif result.clear:
		var reservations: Array = result.manifest
		if not reservations.is_empty() and not party.is_empty():
			var watch := _watch_number
			_performing = true
			room_view.set_modal(true)
			for beat in range(1 + int(reservations[-1].beat)):
				var operations := PackedStringArray()
				var actors := {}
				for i in reservations.size():
					var occupant: Dictionary = reservations[i]
					if occupant.beat != beat: continue
					var who := "Captain" if i == 0 else party[i - 1]
					operations.append("%s · %s" % [who, occupant.operation])
					if i > 0: actors[who] = occupant.slot
				_instruction.text = "Turn %d   /   %s" % [beat + 1, "     ·     ".join(operations)]
				room_view.show_crossing_turn(actors, beat)
				await get_tree().create_timer(.62).timeout
				if watch != _watch_number: return
			_performing = false
		var survivor := _survivor()
		cleared[current] = true
		if r.looked and _stage() not in ["intake", "hall", "meridian"]: facts[_stage()] = true
		if r.moves.size() <= 4: prospect += 1
		crew.supplies += result.bonus + (0 if _stage() == "intake" else 1)
		clock += float(result.minutes) / 60.0
		if _stage() == "intake": handbook = true
		if _stage() == "meridian": phase = "won"
		if not survivor.is_empty() and not roster.has(survivor):
			_recruit(survivor, true)
			message += "  %s joins with the %s copy." % [survivor, _protocol(survivor)]
		if not r.report.is_empty():
			var stances := PackedStringArray(["Captain"])
			stances.append_array(PackedStringArray(party))
			for i in mini(stances.size(), r.report.size()): message += "\n%s: %s" % [stances[i], r.report[i]]
	_refresh()

func _recruit(id: String, deploy := false) -> void:
	if not roster.has(id):
		roster.append(id)
		crew.recruit(id)
	if deploy and not party.has(id) and party.size() < 3 and crew.deployable(id): party.append(id)

func _take_deposition(id: String) -> void:
	if phase != "camp" or not modal.is_empty() or id not in Cast.NAMES: return
	depositions[id] = true
	_open("witness", id + " · " + Cast.job(id), "SIGNED DEPOSITION   /   %s COPY" % _protocol(id).to_upper())
	_label(Cast.witness(id))
	_label("Filed in your evidence wallet. Two independent signatures will open the witness route.", 14)
	if not roster.has(id): _button(_sheet, "Recruit to the Hall roster", _hall_recruit.bind(id))
	_button(_sheet, "Return to the Hall", _close)

func _hall_recruit(id: String) -> void:
	if phase != "camp" or id not in Cast.NAMES: return
	_recruit(id)
	_close()
	message = id + " signs into the Hall roster. Assign their expedition duty in Crew & facilities."
	_refresh()

func _team() -> void:
	if phase != "camp": return
	_open("crew", "Hall roll call", "CREW AND FACILITIES   /   %d CRATES" % crew.supplies)
	for id in roster:
		var b := _button(_sheet, "%s · %s · %s" % ["Stand down" if party.has(id) else "Deploy", id, _protocol(id)], _deploy.bind(id))
		b.disabled = not crew.deployable(id) or (party.size() >= 3 and not party.has(id))
	_label("Speak to a witness in the room to record their account or add them to the roster.", 14)
	for name in crew.upgrades:
		var b := _button(_sheet, "%s / %s" % [name, "installed" if crew.upgrades[name] else "3 crates"], _improve.bind(name))
		b.disabled = crew.upgrades[name] or crew.supplies < 3
	_button(_sheet, "Back to the floor", _close)

func _deploy(id: String) -> void:
	if phase != "camp" or id not in roster: return
	if party.has(id): party.erase(id)
	else: _recruit(id, true)
	_team()
	_refresh()

func _improve(name: String) -> void:
	if phase != "camp" or not crew.build(name): return
	if name == "Watch lamp": nerve = 100
	_team()
	_refresh()

func _leave_hall() -> void:
	camp.leave_camp()
	if is_instance_valid(camp_actors): camp_actors.queue_free()
	camp_actors = null
	camp_time = 0.0

func _enter_hall() -> void:
	if is_instance_valid(camp_actors): return
	var layout: Dictionary = room_view.camp_layout(Cast.NAMES)
	assert(layout.people.size() == Cast.NAMES.size(), "The Hall must seat all original actors")
	if not camp.setup("Captain", layout.graph, layout.people, layout.objects) or not camp.enter_camp(): return
	camp_actors = Witnesses.new()
	room_view.get_node("RoomViewport").add_child(camp_actors)
	_update_hall(0.0)

func _update_hall(dt: float) -> void:
	var rows: Array[Dictionary] = camp_actors.sync(camp.snapshot().residents, dt)
	room_view.set_witness_targets(rows)

func travel(index: int) -> void:
	if _performing or phase in ["lost", "won"] or not modal.is_empty() or not cleared.has(current) or index < 0 or index >= destinations.size(): return
	_leave_hall()
	current = destinations[index]
	moves += 1
	clock += .20
	message = ""
	if current == house.camp_room():
		phase = "camp"
		camp_reached = true
		hp = 9
		nerve = 100 if crew.upgrades["Watch lamp"] else 90
		crew.return_to_camp()
	else: phase = "expedition" if camp_reached else "approach"
	_refresh()

func _death_note() -> void:
	if phase != "lost" or inherited: return
	_open("margin", "Leave a pencil note", "THE NEXT WATCH WILL INHERIT THIS COPY")
	_label("Write one instruction from what you saw at %s." % Rooms.TITLES[_stage()])
	_entry = LineEdit.new()
	_entry.text = margins
	_entry.max_length = 180
	_sheet.add_child(_entry)
	_button(_sheet, "Leave it in the margin", _file_note)
	_button(_sheet, "Close", _close)

func _file_note() -> void:
	if inherited or modal != "margin" or phase != "lost": return
	margins = _entry.text.strip_edges()
	if not _no_save:
		var file := FileAccess.open(MARGINS, FileAccess.WRITE)
		if file: file.store_string(margins)
	inherited = true
	_close()
	_refresh()

func _refresh() -> void:
	_clear(_flow)
	var alive := phase not in ["lost", "won"]
	destinations = PackedStringArray(house.exits(current)) if cleared.has(current) and alive else PackedStringArray()
	var labels := []
	for id in house.exits(current): labels.append("%s / %s" % [Rooms.TITLES[house.room_stage(id)], id.get_slice("_", 1)] if "_" in id else Rooms.TITLES[house.room_stage(id)])
	room_view.set_hour(clock)
	room_view.set_instance_id(current)
	room_view.release_routes(cleared.has(current))
	var title: String = Rooms.TITLES[_stage()]
	var path := "res://content/academy_lots/%s.xml" % house.template_id(current)
	var err: Error = room_view.set_blueprint_room(title, labels, path)
	assert(err == OK, "Missing native room blueprint " + path)
	room_view.set_crossing(_stage(), _survivor(), _variant(), nerve, cleared.has(current))
	room_view.set_field_party([] if phase == "camp" else party)
	room_view.set_modal(not modal.is_empty() or not alive)
	if phase == "camp": _enter_hall()
	_status.text = "THE SLEEPING ACADEMY     /     %s     ·     HP %d/9     Nerve %d     Party %d     Crates %d     ·     %02d:%02d" % ["NIGHT WATCH" if phase != "camp" else "PUBLIC HALL", hp, nerve, party.size() + 1, crew.supplies, floori(clock) % 24, floori(fposmod(clock, 1.0) * 60)]
	if phase == "won":
		_instruction.text = message + "\nMorning. The Hall has a name for everyone who returned."
	elif phase == "lost":
		_instruction.text = message + "\nYour watch ends here. Leave a margin for the next captain."
		if not inherited: _button(_flow, "Edit field margin", _death_note)
	else:
		_instruction.text = message if not message.is_empty() else Rooms.BRIEF[_stage()]
		if cleared.has(current): _instruction.text += "\nPassage open · Follow a named doorway and press E."
		if handbook: _button(_flow, "Field manual · Tab", _read_guide).disabled = _performing
		if phase == "camp": _button(_flow, "Crew & facilities", _team)
	if not alive:
		_button(_flow, "Replay this watch", new_run.bind(run_seed))
		_button(_flow, "Start a new watch", func(): new_run(int(randi())))

func _process(dt: float) -> void:
	if phase != "camp" or not is_instance_valid(camp_actors): return
	crew.rest(dt)
	if not modal.is_empty(): return
	camp_time += dt
	if camp_time >= Camp.TICK_SECONDS:
		camp_time = fmod(camp_time, Camp.TICK_SECONDS)
		camp.step()
		_update_hall(Camp.TICK_SECONDS)

func mcp_observe() -> Dictionary:
	if is_instance_valid(_lab): return _lab.snapshot()
	var buttons := []
	var ui: Container = _flow if modal.is_empty() else _sheet
	for node in ui.get_children():
		if node is Button:
			var center: Vector2 = node.get_global_rect().get_center()
			buttons.append({"label":node.text, "x":center.x, "y":center.y, "enabled":not node.disabled})
	var r := _room()
	return {"phase":phase, "stage":_stage(), "room":current, "camp":house.camp_room(), "goal":house.goal_room(),
		"seed":run_seed, "moves":moves, "health":hp, "nerve":nerve, "supplies":crew.supplies, "modal":modal,
		"roster":roster, "party":party, "protocols":_protocols(), "depositions":depositions.keys(), "facts":facts.keys(),
		"exits":Array(destinations), "cleared":cleared.keys(), "route":r.route, "actions":r.moves, "reports":r.report,
		"walk_grid":room_view.viewport_routes(), "witness_count":camp_actors.actors.size() if is_instance_valid(camp_actors) else 0,
		"handbook":handbook, "performing":_performing, "buttons":buttons, "prompt":_instruction.text, "player_observation":room_view.player_observation()}
