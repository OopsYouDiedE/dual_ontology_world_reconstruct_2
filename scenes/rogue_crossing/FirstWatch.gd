extends Control
## The Night Watch. Orchestrates seeded expedition runs, crossing choices, camp autonomy, and first-sortie transitions.

const House := preload("res://scenes/rogue/HouseMap.cs")
const Room := preload("res://scenes/rogue_view/RogueRoomView.tscn")
const Crossing := preload("Crossing.gd")
const Rooms := preload("Rooms.gd")
const Cast := preload("Roster.gd")
const Witnesses := preload("HallWitnesses.gd")
const HeroCast := preload("ProductionCast.gd")
const Crew := preload("res://scenes/rogue_rules/ExpeditionCrew.gd")
const Camp := preload("res://scenes/rogue_camp/CampResidents.gd")
const R18n := preload("res://scenes/components/shared/R18n.gd")
const UiStyle := preload("res://scenes/components/shared/UiTheme.gd")
const Hud := preload("WatchHud.gd")
const Storage := preload("WatchStorage.gd")
const FirstExpedition := preload("res://scenes/expedition_01/Sortie.tscn")
const HallOpening := preload("HallOpeningSequence.gd")

const MARGINS := Storage.MARGINS
const FIRST_SEAL := Storage.FIRST_SEAL
const FIRST_BRIEF := "The Essence is drifting. Hale is waiting at the north gate: go down the well together and bring back the spare core."

var first_sortie
var first_returned := false
var _opening: CanvasLayer
var _opening_played := false

var pack := {"felt": 0, "ratchet": 0}
var recalled := false
var house: RefCounted
var room_view
var run_seed: int
var current := ""
var phase := "camp"
var rooms := {}
var cleared := {}
var destinations := PackedStringArray()
var party: Array[String] = []
var roster: Array[String] = []
var agreed := {}
var facts := {}
var depositions := {}
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
var hall_hale: Node3D
var camp_time := 0.0
var margins := ""
var inherited := false
var _no_save := false
var modal := ""
var _acting := -1
var _performing := false
var _watch_number := 0

var _storage := Storage.new()
var _backdrop: ColorRect
var _hud: Hud
var _flow: HFlowContainer
var _status: Label
var _place: Label
var _kit: Label
var _card: PanelContainer
var _footer: VBoxContainer
var _font: Font
var _instruction: Label
var _overlay: ColorRect
var _sheet: VBoxContainer
var _scroll: ScrollContainer
var _entry: LineEdit

func _ready() -> void:
	if "--lang=en" in OS.get_cmdline_user_args():
		R18n.set_locale("en")
	else:
		R18n.set_locale("zh")
	_no_save = "--no-rule-save" in OS.get_cmdline_user_args()
	_storage = Storage.new(_no_save)
	margins = _storage.load_margins()
	first_returned = _storage.has_first_seal() or ("--post-first-sortie" in OS.get_cmdline_user_args())
	_make_hud()
	resized.connect(_on_viewport_resized)
	var chosen_seed := int(randi())
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--run-seed=") and arg.get_slice("=", 1).is_valid_int():
			chosen_seed = int(arg.get_slice("=", 1))
	new_run(chosen_seed)

func _make_hud() -> void:
	_backdrop = ColorRect.new()
	_backdrop.color = Color("111816")
	_backdrop.mouse_filter = MOUSE_FILTER_IGNORE
	add_child(_backdrop)
	_backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	room_view = Room.instantiate()
	room_view.expedition_view = true
	room_view.campaign_view = true
	room_view.field_model = Cast.attach
	add_child(room_view)
	room_view.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	room_view.exit_selected.connect(travel)
	room_view.crossing_selected.connect(_inspect)
	room_view.witness_selected.connect(_take_deposition)

	_hud = Hud.new()
	add_child(_hud)
	_hud.build()
	_font = _hud.font
	_card = _hud.card
	_place = _hud.place_label
	_status = _hud.status_label
	_kit = _hud.kit_label
	_footer = _hud.footer
	_instruction = _hud.instruction
	_flow = _hud.flow
	_overlay = _hud.overlay
	_scroll = _hud.scroll
	_sheet = _hud.sheet

	var skin := Theme.new()
	skin.default_font = _font
	skin.default_font_size = 16
	skin.set_color("font_color", "Label", UiStyle.TEXT_MAIN)
	theme = skin

	_opening = HallOpening.new()
	add_child(_opening)
	_opening.finished.connect(_on_opening_finished)

func _button(parent: Container, label: String, callback: Callable) -> Button:
	return _hud.add_button(parent, label, callback) if is_instance_valid(_hud) else null

func _label(text: String, text_size := 16, gold := false) -> void:
	if is_instance_valid(_hud):
		_hud.add_sheet_label(text, text_size, gold)

func _open(kind: String, title: String, folio: String) -> void:
	if is_instance_valid(room_view) and room_view.has_method("close_plan"):
		room_view.close_plan()
	modal = kind
	if is_instance_valid(_hud):
		_hud.open_sheet(title, folio)
	room_view.set_modal(true)

func _on_viewport_resized() -> void:
	if not is_instance_valid(_hud):
		return
	_hud.fit_instruction(get_viewport_rect().size.x)
	if not modal.is_empty():
		_hud.fit_sheet()

func _close() -> void:
	modal = ""
	_acting = -1
	if is_instance_valid(_hud):
		_hud.close_sheet()
	room_view.set_modal(_performing or phase in ["lost", "won"])

func new_run(value: int) -> void:
	if is_instance_valid(_opening) and _opening.active:
		_opening.skip()
	_close()
	_leave_hall()
	run_seed = value
	house = House.new()
	if not house.generate_expedition(value):
		push_error("Expedition chart could not be seated")
		return
	current = house.start_room()
	room_view.set_instance_id("")
	phase = "camp"
	rooms.clear()
	cleared.clear()
	cleared[current] = true
	recalled = false
	pack = {"felt": 0, "ratchet": 0}
	party.clear()
	roster.clear()
	agreed.clear()
	facts.clear()
	depositions.clear()
	prospect = 0
	hp = 9
	nerve = 100
	clock = 4.0
	moves = 0
	crew = Crew.new()
	camp = Camp.new()
	handbook = true
	inherited = false
	_performing = false
	_watch_number += 1
	_opening_played = false
	message = ""
	_refresh()

func _stage() -> String:
	return house.room_stage(current)

func _variant() -> bool:
	if current in ["turntable", house.goal_room()]:
		return false
	return ((str(run_seed) + "/" + current + "/" + _stage()).sha256_buffer()[0] & 1) == 0

func _room() -> Crossing:
	if not rooms.has(current):
		rooms[current] = Crossing.new(_stage(), _variant())
	return rooms[current]

func _protocol(member: String) -> String:
	return agreed.get(member, Cast.edition(member))

func _protocols() -> Array[String]:
	var result: Array[String] = ["Ivory"]
	for id in party:
		result.append(_protocol(id))
	return result

func _can_agree() -> bool:
	if _stage() != "relay" or party.is_empty():
		return false
	if _protocols().all(func(p): return p == "Ivory"):
		return false
	if depositions.size() >= 2 and facts.size() >= 2:
		return true
	return prospect >= 4 and party.all(func(id): return crew.people[id].trust >= 3 and crew.people[id].stress < 3)

func _input(event: InputEvent) -> void:
	if is_instance_valid(first_sortie) or (is_instance_valid(_opening) and _opening.active):
		return
	if _performing or not event is InputEventKey or not event.pressed or event.echo or house == null:
		return
	if event.physical_keycode == KEY_F8:
		R18n.toggle_locale()
		_refresh()
	elif event.physical_keycode == KEY_TAB and handbook and modal != "margin":
		if modal == "guide":
			_close()
		else:
			_read_guide()
	elif event.physical_keycode == KEY_ESCAPE:
		if not modal.is_empty():
			_close()
		elif is_instance_valid(room_view) and room_view.has_method("is_plan_open") and room_view.is_plan_open():
			room_view.close_plan()
		else:
			return
	else:
		return
	get_viewport().set_input_as_handled()

func _read_guide() -> void:
	if _performing:
		return
	_open("guide", "Night watch field manual", "ACADEMY PRESS  /  IVORY  /  No. 04")
	for line in Rooms.IVORY:
		_label(line)
	for id in party:
		var edition := _protocol(id)
		_label("%s · %s copy" % [id, edition], 15, true)
		_label("  ·  ".join(Rooms.VERSIONS[edition]), 14)
	if not margins.is_empty():
		_label("Inherited pencil note / " + margins, 14)
	_button(_sheet, "Fold manual · Tab", _close)

func _inspect(group: int) -> void:
	if _performing or phase in ["won", "lost"] or not modal.is_empty() or group not in [0, 1, 2]:
		return
	var r := _room()
	var title: String = Rooms.FIXTURES[_stage()][group]
	_open("apparatus", title, "%s   /   %s" % [Rooms.TITLES[_stage()].to_upper(), "FILED" if cleared.has(current) else "NIGHT SERVICE"])
	_acting = group
	_label(r.read(group))
	if _stage() in ["exchange", "airlock", "relay"]:
		for id in party:
			var edition := _protocol(id)
			_label("%s / %s: %s" % [id, edition, Rooms.VERSIONS[edition][1 if _stage() == "airlock" else 0]], 14, true)
		if _stage() == "relay" and not _can_agree() and _protocols().any(func(p): return p != "Ivory"):
			_label("A joint order needs two depositions and two field traces, or the crew’s confidence in your record.", 13)
	if not cleared.has(current):
		for tool in pack:
			if r.tool_group(tool) == group:
				var b := _button(_sheet, r.tool_label(tool), _act.bind(current, group, tool))
				b.disabled = pack[tool] < 1 or r.flags.has("felt") or r.flags.has("ratchet")
		for option: Dictionary in r.options(group, _protocols(), _can_agree()):
			_button(_sheet, option.text, _act.bind(current, group, option.id))
	_button(_sheet, "Put it down · Esc", _close)

func _act(room_id: String, group: int, id: String) -> void:
	if _performing or room_id != current or modal != "apparatus" or _acting != group or cleared.has(current):
		return
	var r := _room()
	var result := r.use_tool(group, id, pack) if pack.has(id) else r.act(group, id, _protocols(), _can_agree(), depositions.size())
	if result.is_empty():
		return
	_close()
	room_view.show_crossing_action(group, id, result)
	message = result.line
	if result.get("agree", false):
		for member in party:
			agreed[member] = "Ivory"
	if result.damage > 0:
		hp = maxi(0, hp - int(result.damage))
		nerve = maxi(10, nerve - 12 * int(result.damage))
		crew.pressure(party, 1)
		if phase == "expedition" and not party.is_empty() and crew.people[party[-1]].stress >= 3:
			var rear: String = party.pop_back()
			crew.wound(rear, 24.0)
			message += " %s falls back to the Hall clinic." % rear
		message += "  −%d health. The crossing is still closed." % result.damage
		if hp == 0:
			phase = "lost"
	elif result.clear:
		var reservations: Array = result.manifest
		if not reservations.is_empty() and not party.is_empty():
			var watch := _watch_number
			_performing = true
			if is_instance_valid(_hud):
				_hud.set_flow_disabled(true)
			room_view.set_modal(true)
			for beat in range(1 + int(reservations[-1].beat)):
				var operations := PackedStringArray()
				var actors := {}
				for i in reservations.size():
					var occupant: Dictionary = reservations[i]
					if occupant.beat != beat:
						continue
					var who := "Captain" if i == 0 else party[i - 1]
					operations.append("%s · %s" % [who, occupant.operation])
					if i > 0:
						actors[who] = occupant.slot
				if is_instance_valid(_hud):
					_instruction.text = "Turn %d   /   %s" % [beat + 1, "     ·     ".join(operations)]
					_hud.fit_instruction(get_viewport_rect().size.x)
				room_view.show_crossing_turn(actors, beat)
				await get_tree().create_timer(.62).timeout
				if watch != _watch_number:
					return
			_performing = false
		cleared[current] = true
		var reward := _reward(current)
		if not reward.is_empty():
			pack[reward] += 1
			message += "  Packed one " + reward + "."
		if r.looked and _stage() != "meridian":
			facts[_stage()] = true
		if r.moves.size() <= 4:
			prospect += 1
		crew.supplies += result.bonus + 1
		clock += float(result.minutes) / 60.0
		if _stage() == "meridian":
			phase = "won"
		if not r.report.is_empty():
			var stances := PackedStringArray(["Captain"])
			stances.append_array(PackedStringArray(party))
			for i in mini(stances.size(), r.report.size()):
				message += "\n%s: %s" % [stances[i], r.report[i]]
	_refresh()

func _take_deposition(id: String) -> void:
	if phase != "camp" or not modal.is_empty() or id not in Cast.NAMES:
		return
	depositions[id] = true
	_open("witness", id + " · " + Cast.job(id), "SIGNED DEPOSITION   /   %s COPY" % _protocol(id).to_upper())
	_label(Cast.witness(id))
	_label("Filed in your evidence wallet. Two independent signatures can support a common relay order.", 14)
	if not roster.has(id):
		_button(_sheet, "Recruit to the Hall roster", _hall_recruit.bind(id))
	_button(_sheet, "Return to the Hall", _close)

func _hall_recruit(id: String) -> void:
	if phase != "camp" or id not in Cast.NAMES:
		return
	if not roster.has(id):
		roster.append(id)
		crew.recruit(id)
	_close()
	message = id + " signs into the Hall roster. Assign their expedition duty in Crew & facilities."
	_refresh()

func _team() -> void:
	if phase != "camp":
		return
	_open("crew", "Hall roll call", "CREW AND FACILITIES   /   %d CRATES" % crew.supplies)
	_button(_sheet, "Back to the floor", _close)
	for id in roster:
		var state_note := "" if crew.deployable(id) else (" · " + crew.status(id))
		var b := _button(_sheet, "%s · %s · %s%s" % ["Stand down" if party.has(id) else "Deploy", id, _protocol(id), state_note], _deploy.bind(id))
		b.disabled = not crew.deployable(id) or (party.size() >= 3 and not party.has(id))
	_label("Speak to a witness in the room to record their account or add them to the roster.", 14)
	for name in crew.upgrades:
		var b := _button(_sheet, "%s / %s" % [name, "installed" if crew.upgrades[name] else "3 crates"], _improve.bind(name))
		b.disabled = crew.upgrades[name] or crew.supplies < 3

func _deploy(id: String) -> void:
	if phase != "camp" or id not in roster:
		return
	if party.has(id):
		party.erase(id)
	elif party.size() < 3 and crew.deployable(id):
		party.append(id)
	_team()
	_refresh()

func _improve(name: String) -> void:
	if phase != "camp" or not crew.build(name):
		return
	if name == "Watch lamp":
		nerve = 100
	_team()
	_refresh()

func _leave_hall() -> void:
	camp.leave_camp()
	if is_instance_valid(camp_actors):
		camp_actors.queue_free()
	camp_actors = null
	camp_time = 0.0

func _enter_hall() -> void:
	if not first_returned:
		_post_hall_hale()
		return
	if is_instance_valid(hall_hale):
		hall_hale.queue_free()
	if is_instance_valid(camp_actors):
		return
	var layout: Dictionary = room_view.camp_layout(Cast.NAMES)
	assert(layout.people.size() == Cast.NAMES.size(), "The Hall must seat all original actors")
	if not camp.setup("Captain", layout.graph, layout.people, layout.objects) or not camp.enter_camp():
		return
	camp_actors = Witnesses.new()
	room_view.mount_viewport_node(camp_actors)
	_update_hall(0.0)

func _post_hall_hale() -> void:
	if is_instance_valid(hall_hale):
		return
	var anchors: Dictionary = room_view.hall_opening_anchors()
	if anchors.is_empty():
		return
	var none: Array[Dictionary] = []
	room_view.set_witness_targets(none)
	hall_hale = Node3D.new()
	hall_hale.name = "HallHale"
	room_view.mount_viewport_node(hall_hale)
	hall_hale.position = anchors.gate + Vector3(1.15, 0.0, 1.3)
	hall_hale.rotation.y = 0.35
	HeroCast.attach_hero(hall_hale, "hale")

func _update_hall(dt: float) -> void:
	var rows: Array[Dictionary] = camp_actors.sync(camp.snapshot().residents, dt)
	room_view.set_witness_targets(rows)

func _set_hall_active(active: bool) -> void:
	var mode := Node.PROCESS_MODE_INHERIT if active else Node.PROCESS_MODE_DISABLED
	for node in [_backdrop, room_view]:
		if is_instance_valid(node):
			node.process_mode = mode
			node.visible = active
	if is_instance_valid(_hud):
		_hud.set_sortie_mode(not active)

func _depart_first() -> void:
	_close()
	if is_instance_valid(room_view) and room_view.has_method("close_plan"):
		room_view.close_plan()
	phase = "first_expedition"
	room_view.set_modal(true)
	_set_hall_active(false)
	if is_instance_valid(hall_hale):
		hall_hale.queue_free()
	hall_hale = null
	first_sortie = FirstExpedition.instantiate()
	first_sortie.returned.connect(_return_first, CONNECT_DEFERRED)
	add_child(first_sortie)

func _return_first() -> void:
	first_sortie.queue_free()
	first_sortie = null
	first_returned = true
	_storage.mark_first_seal()
	_set_hall_active(true)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	phase = "camp"
	message = "Hale filed the source. The expedition chart is open."
	_refresh()

func travel(index: int) -> void:
	if _performing or phase in ["lost", "won"] or not modal.is_empty() or not cleared.has(current) or index < 0 or index >= destinations.size():
		return
	if not first_returned and phase == "camp":
		_depart_first()
		return
	_leave_hall()
	var previous := current
	current = destinations[index]
	if previous == "turntable" and current == house.camp_room():
		recalled = true
	moves += 1
	clock += .20
	message = ""
	if current == house.camp_room():
		phase = "camp"
		hp = 9
		nerve = 100 if crew.upgrades["Watch lamp"] else 90
		crew.return_to_camp()
	else:
		phase = "expedition"
	_refresh()

func _death_note() -> void:
	if phase != "lost" or inherited:
		return
	_open("margin", "Leave a pencil note", "THE NEXT WATCH WILL INHERIT THIS COPY")
	_label("Write one instruction from what you saw at %s." % Rooms.TITLES[_stage()])
	if is_instance_valid(_hud):
		_entry = _hud.add_margin_entry(margins, _file_note)
	_button(_sheet, "Leave it in the margin", _file_note)
	_button(_sheet, "Close", _close)

func _file_note() -> void:
	if inherited or modal != "margin" or phase != "lost":
		return
	margins = _entry.text.strip_edges()
	_storage.save_margins(margins)
	inherited = true
	_close()
	_refresh()

func _reward(id: String) -> String:
	if id.begins_with("west_"):
		return "felt"
	if id.begins_with("east_"):
		return "ratchet"
	return ""

func _routes() -> PackedStringArray:
	if phase == "camp" and recalled:
		return PackedStringArray(["turntable"])
	var choices := PackedStringArray(house.forward(current))
	if phase == "camp" and not first_returned:
		return choices.slice(0, 1)
	if current == "turntable" and not recalled:
		choices.append(house.camp_room())
	return choices

func _route_name(id: String) -> String:
	if phase == "camp" and not first_returned:
		return R18n.pick("首次出征 · Hale", "First Expedition · Hale")
	if id == house.camp_room():
		return R18n.pick("返回大厅 · 休整", "Return to camp · recover")
	if id == "turntable":
		return R18n.pick("折返闸", "Return Junction")
	var reward := _reward(id)
	return Rooms.TITLES[house.room_stage(id)] + (" / +1 " + reward if reward else "")

func _chart() -> void:
	if _performing:
		return
	_open("chart", "Expedition chart", "PUBLIC HALL   /   WATCH %d" % run_seed)
	_button(_sheet, "Fold chart", _close)
	if phase == "camp" and not first_returned:
		_label("Public Hall  →  Immersion Arcade  →  Archive  →  Source Caisson", 16)
		return
	var map := preload("RouteChart.gd").new()
	map.chart = house
	map.here = current
	map.visited = cleared
	map.custom_minimum_size = Vector2(600, 160)
	_sheet.add_child(map)
	_label("West: felt protects salvage for camp upgrades. East: a ratchet locks a shaft for fast passage. Fit one tool per room, or save it for the bell. The junction tram offers one return and resumes here.", 15)
	for id in [house.camp_room(), "west_1", "east_1", "west_2", "east_2", "turntable", "west_3", "east_3"]:
		var names := PackedStringArray()
		for dest in house.forward(id):
			names.append(_route_name(dest))
		_label(("HERE · " if id == current else "") + ("Return Junction" if id == "turntable" else Rooms.TITLES[house.room_stage(id)]) + "   →   " + "  |  ".join(names), 14, id == current)

func _refresh() -> void:
	if is_instance_valid(_hud):
		_hud.clear_container(_flow)
	var alive := phase not in ["lost", "won"]
	destinations = _routes() if cleared.has(current) and alive else PackedStringArray()
	var labels := []
	for id in _routes():
		labels.append(_route_name(id))
	room_view.set_hour(clock)
	room_view.set_instance_id(current)
	room_view.release_routes(cleared.has(current))
	var title: String = "Return Junction" if current == "turntable" else Rooms.TITLES[_stage()]
	var path := "res://content/academy_lots/%s.xml" % house.template_id(current)
	if phase == "camp":
		path = "res://content/academy_lots/public_nave.xml"
	var err: Error = room_view.set_blueprint_room(title, labels, path)
	assert(err == OK, "Missing native room blueprint " + path)
	if phase != "camp":
		room_view.set_crossing(_stage(), "", _variant(), nerve, cleared.has(current))
	room_view.set_field_party([] if phase == "camp" else party)
	room_view.set_modal(not modal.is_empty() or not alive)
	if phase == "camp":
		room_view.set_pendulum_drifting(not first_returned)
		_enter_hall()
		if not first_returned and not _opening_played and not _should_skip_opening():
			play_hall_opening.call_deferred()
	if not is_instance_valid(_hud):
		return
	_hud.update_readout(R18n.pick("公共大厅", "Public Hall") if phase == "camp" else title, clock, hp, nerve, party.size(), crew.supplies, pack)
	if phase == "won":
		_instruction.text = message + "\nMorning. The Hall has a name for everyone who returned."
	elif phase == "lost":
		_instruction.text = message + "\nYour watch ends here. Leave a margin for the next captain."
		if not inherited:
			_button(_flow, "Edit field margin", _death_note)
	else:
		_instruction.text = message if not message.is_empty() else Rooms.BRIEF[_stage()]
		if current == "turntable" and message.is_empty():
			_instruction.text = "The return tram is behind this shutter. Release the drawbar to board or push on."
		if cleared.has(current):
			_instruction.text += R18n.pick("\n通道已开启 · 前往标牌门洞按 E 出发。", "\nPassage open · Follow a named doorway and press E.")
		if phase == "camp" and message.is_empty():
			_instruction.text = R18n.pick("选择一条补给路线。出发前可与大厅居民交谈招募队员。", "Choose a supply route. Speak to a resident to recruit before leaving.")
		if phase == "camp" and not first_returned:
			_instruction.text = R18n.pick("源质正在漂移。Hale 在北门等你：两人一起下井，取回备用源核。", FIRST_BRIEF)
		for i in destinations.size():
			_button(_flow, _route_name(destinations[i]), travel.bind(i))
		_button(_flow, R18n.pick("路线图", "Route chart"), _chart).disabled = _performing
		if handbook:
			_button(_flow, R18n.pick("外勤手册 · Tab", "Field manual · Tab"), _read_guide).disabled = _performing
		if phase == "camp" and first_returned:
			_button(_flow, R18n.pick("人员与设施", "Crew & facilities"), _team)
	if not alive:
		_button(_flow, "Replay this watch", new_run.bind(run_seed))
		_button(_flow, "Start a new watch", func(): new_run(int(randi())))
	_hud.fit_instruction(get_viewport_rect().size.x)

func _process(dt: float) -> void:
	if phase != "camp" or not is_instance_valid(camp_actors):
		return
	crew.rest(dt)
	if not modal.is_empty():
		return
	camp_time += dt
	if camp_time >= Camp.TICK_SECONDS:
		camp_time = fmod(camp_time, Camp.TICK_SECONDS)
		camp.step()
		_update_hall(Camp.TICK_SECONDS)

func mcp_observe() -> Dictionary:
	if is_instance_valid(first_sortie):
		return first_sortie.mcp_observe()
	var opening_active: bool = is_instance_valid(_opening) and bool(_opening.active)
	var buttons := _hud.visible_buttons(not modal.is_empty()) if (is_instance_valid(_hud) and not opening_active) else []
	var r := _room()
	return {"phase": phase, "stage": _stage(), "room": current, "camp": house.camp_room(), "goal": house.goal_room(),
		"pack": pack.duplicate(), "recalled": recalled, "seed": run_seed, "moves": moves, "health": hp, "nerve": nerve, "supplies": crew.supplies, "modal": modal,
		"roster": roster, "party": party, "protocols": _protocols(), "depositions": depositions.keys(), "facts": facts.keys(),
		"exits": Array(destinations), "cleared": cleared.keys(), "route": r.route, "actions": r.moves, "reports": r.report,
		"walk_grid": room_view.viewport_routes(), "witness_count": camp_actors.actors.size() if is_instance_valid(camp_actors) else 0,
		"handbook": handbook, "performing": _performing, "buttons": buttons, "prompt": _instruction.text if is_instance_valid(_hud) else "", "player_observation": room_view.player_observation()}

func _should_skip_opening() -> bool:
	return DisplayServer.get_name() == "headless" or "--skip-intro" in OS.get_cmdline_user_args()

func play_hall_opening(force := false) -> bool:
	if not is_instance_valid(_opening) or (_opening_played and not force):
		return false
	var anchors: Dictionary = room_view.hall_opening_anchors()
	if anchors.is_empty():
		return false
	_opening_played = true
	room_view.set_modal(true)
	if is_instance_valid(_hud):
		_hud.hide_for_opening()
	room_view.set_cinematic(true)
	if is_instance_valid(hall_hale):
		hall_hale.hide()
	room_view.place_player(anchors.cot + HallOpening.STAND_EYE * Vector3(1, 0, 1), Vector3(1, 0, 0.35))
	_opening.start(anchors.viewport, anchors.camera, anchors.cot, anchors.pendulum, anchors.gate, room_view.set_essence_instability)
	return true

func skip_hall_opening() -> void:
	if is_instance_valid(_opening) and _opening.active:
		_opening.skip()

func _on_opening_finished() -> void:
	if is_instance_valid(_hud):
		_hud.restore_after_opening()
	room_view.set_cinematic(false)
	if is_instance_valid(hall_hale):
		hall_hale.show()
	room_view.set_essence_instability(room_view.essence_baseline())
	room_view.set_modal(not modal.is_empty() or phase in ["lost", "won"])
	if phase == "camp" and not first_returned and is_instance_valid(_hud):
		_instruction.text = R18n.pick("源质正在漂移。Hale 在北门等你：两人一起下井，取回备用源核。", FIRST_BRIEF)
		_hud.fit_instruction(get_viewport_rect().size.x)
