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
const VoiceSynth := preload("res://scenes/components/shared/VoiceSynth.gd")
const UiStyle := preload("res://scenes/components/shared/UiTheme.gd")
const Hud := preload("WatchHud.gd")
const Storage := preload("WatchStorage.gd")
const FirstExpedition := preload("res://scenes/expedition_01/Sortie.tscn")
const HallOpening := preload("HallOpeningSequence.gd")
const DualInteractionHud := preload("res://scenes/components/shared/DualModeInteractionHud.gd")

const MARGINS := Storage.MARGINS
const FIRST_SEAL := Storage.FIRST_SEAL
const FIRST_BRIEF := "03:38 · 公共大厅。可先观察中央傅科摆或与霍铎交谈，再前往北翼门廊。"

var first_sortie
var first_returned := false
var pendulum_measured := false
var pendulum_note_recorded := false
var pendulum_measured_sec := 8.1
var field_notes: Array[String] = []
var _wrpg_panel: PanelContainer
var _wrpg_title: Label
var _wrpg_body: Label
var _wrpg_choices: VBoxContainer
var _wrpg_actions: Array[Callable] = []
var _opening: CanvasLayer
var _opening_played := false
var dual_ui: DualModeInteractionHud

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
var _hall_voice: Node
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
	if _performing or house == null:
		return
	if _handle_dual_ui_input(event):
		get_viewport().set_input_as_handled()
		return
	if not event is InputEventKey or not event.pressed or event.echo:
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

func _speak_hall_mumble(text: String, speaker_profile: String = "resident") -> void:
	if not is_instance_valid(_hall_voice):
		_hall_voice = VoiceSynth.new()
		add_child(_hall_voice)
	_hall_voice.speak_line(text, speaker_profile)

func _take_deposition(id: String) -> void:
	if phase != "camp" or not modal.is_empty():
		return
	# Foucault Pendulum observation & single-pass period measurement
	if id == "FoucaultPendulum":
		_open_pendulum_sheet()
		return

	# Pre-sortie Hale: Compact WRPG dialogue menu (no full-screen dossier!)
	if id == "Hale" and not first_returned:
		if is_instance_valid(hall_hale) and hall_hale.has_meta("animation_player"):
			(hall_hale.get_meta("animation_player") as AnimationPlayer).play(&"signal", 0.25)
		var line := R18n.pick(
			"大厅里没有任何外力损坏，只有北门门缝在往里渗白雾和海盐味。整点前我们得进北翼查一趟。",
			"Nothing in the Hall is damaged—only the north archway is leaking mist and sea-salt air. We should check the North Wing before the hour bell."
		)
		_speak_hall_mumble(line, "hale")
		var opts: Array[Dictionary] = []
		if pendulum_measured:
			opts.append({"label": R18n.pick("询问关于傅科摆周期与偏心的事", "Ask about the Foucault pendulum"), "cb": _ask_hale_pendulum})
		opts.append({"label": R18n.pick("与霍铎一同进入北翼", "Enter the North Wing with Hale"), "cb": _depart_first})
		opts.append({"label": R18n.pick("先在大厅观察", "Step back"), "cb": _close_wrpg})
		_open_wrpg(R18n.pick("霍铎（Hale）", "Hale"), line, opts)
		return

	if id not in Cast.NAMES:
		return
	depositions[id] = true
	var ed := _protocol(id)
	var ed_disp := Cast.edition_localized(ed, R18n.is_en())
	var job_disp := Cast.job_localized(id, R18n.is_en())
	var acct := Cast.witness(id)
	var v_prof := "elder" if (Cast.NAMES.find(id) % 3 == 0) else "resident"
	_speak_hall_mumble(acct, v_prof)

	_open(
		"witness",
		"%s · %s" % [id, job_disp],
		R18n.pick("已录证词   /   %s守则副本", "SIGNED DEPOSITION   /   %s COPY") % (ed.to_upper() if R18n.is_en() else ed_disp)
	)
	_label(acct)
	if roster.has(id) and crew.people.has(id):
		var member = crew.people[id]
		var status_str := R18n.pick("待命可出征", "Ready to deploy") if crew.deployable(id) else str(crew.status(id))
		_label(R18n.pick("当前状态：%s   ·   信任 %d   ·   压力 %d   ·   出征小队 %d/3", "Status: %s   ·   Trust %d   ·   Stress %d   ·   Party %d/3") % [status_str, member.trust, member.stress, party.size()], 14, true)
	else:
		_label(R18n.pick("证词已收入档案夹。集齐两份独立签名可在中继站下达联合指令。", "Filed in your evidence wallet. Two independent signatures can support a common relay order."), 14)

	# One-stop recruit & direct party deploy right inside the resident conversation
	if not roster.has(id):
		_button(_sheet, R18n.pick("招募进入大厅名册", "Recruit to the Hall roster"), _hall_recruit.bind(id, false))
		if party.size() < 3:
			_button(_sheet, R18n.pick("招募并直接编入出征小队（%d/3）", "Recruit & deploy to party (%d/3)") % party.size(), _hall_recruit.bind(id, true))
	else:
		if party.has(id):
			_button(_sheet, R18n.pick("移出出征小队（留厅休整）", "Stand down from party"), _toggle_party_from_sheet.bind(id))
		else:
			var dep_btn := _button(_sheet, R18n.pick("编入本次出征小队（%d/3）", "Deploy to expedition party (%d/3)") % party.size(), _toggle_party_from_sheet.bind(id))
			dep_btn.disabled = not crew.deployable(id) or party.size() >= 3
	_button(_sheet, R18n.pick("返回大厅", "Return to the Hall"), _close)

func _toggle_party_from_sheet(id: String) -> void:
	if phase != "camp" or id not in roster:
		return
	if party.has(id):
		party.erase(id)
		message = R18n.pick("%s 已退回大厅休整。", "%s stands down to rest in the Hall.") % id
	elif party.size() < 3 and crew.deployable(id):
		party.append(id)
		message = R18n.pick("%s 已编入本次出征小队（%d/3）。", "%s joins your expedition party (%d/3).") % [id, party.size()]
	_close()
	_refresh()

func _hall_recruit(id: String, also_deploy := false) -> void:
	if phase != "camp" or id not in Cast.NAMES:
		return
	if not roster.has(id):
		roster.append(id)
		crew.recruit(id)
	if also_deploy and not party.has(id) and party.size() < 3 and crew.deployable(id):
		party.append(id)
		message = R18n.pick("%s 已入册并编入出征小队（%d/3）。", "%s signs into the Hall roster and joins your party (%d/3).") % [id, party.size()]
	else:
		message = R18n.pick("%s 已签入大厅名册，可在「人员与设施」或再次交谈时编入小队。", "%s signs into the Hall roster. Assign their expedition duty in Crew & facilities.") % id
	_close()
	_refresh()

func _team() -> void:
	if phase != "camp":
		return
	_open("crew", R18n.pick("大厅点名与设施", "Hall roll call"), R18n.pick("人员与设施   /   %d 补给箱", "CREW AND FACILITIES   /   %d CRATES") % crew.supplies)
	_button(_sheet, R18n.pick("返回大厅", "Back to the floor"), _close)
	for id in roster:
		var state_note := "" if crew.deployable(id) else (" · " + crew.status(id))
		var act_label := R18n.pick("退回休整", "Stand down") if party.has(id) else R18n.pick("编入出征", "Deploy")
		var ed_disp := Cast.edition_localized(_protocol(id), R18n.is_en())
		var b := _button(_sheet, "%s · %s · %s%s" % [act_label, id, ed_disp, state_note], _deploy.bind(id))
		b.disabled = not crew.deployable(id) or (party.size() >= 3 and not party.has(id))
	_label(R18n.pick("在大厅中走近任意居民按 E 即可录证词、招募或直接编队。", "Speak to a witness in the room to record their account, recruit, or deploy directly."), 14)
	for name in crew.upgrades:
		var status_txt := R18n.pick("已安装", "installed") if crew.upgrades[name] else R18n.pick("需 3 补给箱", "3 crates")
		var b := _button(_sheet, "%s / %s" % [name, status_txt], _improve.bind(name))
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
	hall_hale = Node3D.new()
	hall_hale.name = "HallHale"
	room_view.mount_viewport_node(hall_hale)
	hall_hale.position = anchors.gate + Vector3(1.15, 0.0, 1.3)
	hall_hale.rotation.y = 0.35
	HeroCast.attach_hero(hall_hale, "hale")
	var hale_tag := Label3D.new()
	hale_tag.text = "Hale"
	hale_tag.modulate = Color("f4dca8")
	hale_tag.pixel_size = 0.0022
	hale_tag.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	hale_tag.position.y = 1.94
	hall_hale.add_child(hale_tag)
	var hale_target: Array[Dictionary] = [
		{"kind": "witness", "id": "Hale", "label": R18n.pick("霍铎 (Hale)", "Hale"), "position": hall_hale.position},
		{"kind": "witness", "id": "FoucaultPendulum", "label": R18n.pick("傅科摆", "Foucault Pendulum"), "position": anchors.pendulum + Vector3(0.0, 0.85, 0.0)},
	]
	room_view.set_witness_targets(hale_target)

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
			_instruction.text = R18n.pick("大厅傅科摆周期异常，霍铎正在等你。可先观测傅科摆，或走近与他交谈。", FIRST_BRIEF)
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
	_sync_dual_ui()
	if phase == "camp" and is_instance_valid(hall_hale) and is_instance_valid(room_view) and is_instance_valid(room_view._player):
		var p_pos: Vector3 = room_view._player.position
		var d := Vector2(p_pos.x - hall_hale.position.x, p_pos.z - hall_hale.position.z)
		if d.length() < 4.5 and d.length() > 0.35:
			hall_hale.rotation.y = lerp_angle(hall_hale.rotation.y, atan2(d.x, d.y), 1.0 - exp(-5.0 * dt))
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
		_instruction.text = R18n.pick("大厅傅科摆周期异常，霍铎正在等你。可先观测傅科摆，或走近与他交谈。", FIRST_BRIEF)
		_hud.fit_instruction(get_viewport_rect().size.x)


## ---- Compact Western-RPG Bottom Action Menu (Pendulum & Hale) ----
func _ensure_wrpg_menu() -> void:
	if is_instance_valid(_wrpg_panel):
		return
	var font := UiStyle.make_font()
	_wrpg_panel = PanelContainer.new()
	_wrpg_panel.name = "WrpgActionMenu"
	_wrpg_panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	_wrpg_panel.offset_left = -310.0
	_wrpg_panel.offset_right = 310.0
	_wrpg_panel.offset_bottom = -28.0
	_wrpg_panel.offset_top = -230.0
	_wrpg_panel.grow_vertical = Control.GROW_DIRECTION_BEGIN
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.055, 0.065, 0.085, 0.90)
	sb.border_color = Color("cfa04c")
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(3)
	sb.content_margin_left = 20
	sb.content_margin_right = 20
	sb.content_margin_top = 14
	sb.content_margin_bottom = 14
	_wrpg_panel.add_theme_stylebox_override("panel", sb)
	add_child(_wrpg_panel)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 8)
	_wrpg_panel.add_child(vbox)

	_wrpg_title = Label.new()
	UiStyle.style_label(_wrpg_title, font, 15, Color("f0c475"), 2)
	vbox.add_child(_wrpg_title)

	_wrpg_body = Label.new()
	_wrpg_body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	UiStyle.style_label(_wrpg_body, font, 14, Color("e6e1d6"), 2)
	vbox.add_child(_wrpg_body)

	var sep := HSeparator.new()
	sep.modulate = Color(0.81, 0.63, 0.30, 0.45)
	vbox.add_child(sep)

	_wrpg_choices = VBoxContainer.new()
	_wrpg_choices.add_theme_constant_override("separation", 5)
	vbox.add_child(_wrpg_choices)
	_wrpg_panel.hide()

func _open_wrpg(title: String, body: String, options: Array[Dictionary]) -> void:
	_ensure_wrpg_menu()
	modal = "wrpg"
	room_view.set_modal(true)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_wrpg_title.text = title
	_wrpg_body.text = body
	for c in _wrpg_choices.get_children():
		c.queue_free()
	_wrpg_actions.clear()
	var font := UiStyle.make_font()
	for i in options.size():
		var opt: Dictionary = options[i]
		var cb: Callable = opt.cb
		_wrpg_actions.append(cb)
		var btn := Button.new()
		btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
		btn.text = "[%d]  %s" % [i + 1, str(opt.label)]
		btn.add_theme_font_override("font", font)
		btn.add_theme_font_size_override("font_size", 14)
		btn.add_theme_color_override("font_color", Color("f2efe9"))
		btn.add_theme_color_override("font_hover_color", Color("f0c475"))
		var b_norm := StyleBoxFlat.new()
		b_norm.bg_color = Color(0.11, 0.13, 0.17, 0.72)
		b_norm.content_margin_left = 12; b_norm.content_margin_right = 12
		b_norm.content_margin_top = 6; b_norm.content_margin_bottom = 6
		var b_hov := b_norm.duplicate() as StyleBoxFlat
		b_hov.bg_color = Color(0.22, 0.19, 0.13, 0.92)
		b_hov.border_color = Color("cfa04c"); b_hov.set_border_width_all(1)
		btn.add_theme_stylebox_override("normal", b_norm)
		btn.add_theme_stylebox_override("hover", b_hov)
		btn.add_theme_stylebox_override("pressed", b_hov)
		btn.pressed.connect(cb)
		_wrpg_choices.add_child(btn)
	if is_instance_valid(_instruction):
		_instruction.hide()
	if is_instance_valid(_flow):
		_flow.hide()
	_wrpg_panel.show()

func _close_wrpg() -> void:
	if is_instance_valid(_wrpg_panel):
		_wrpg_panel.hide()
	if is_instance_valid(_instruction):
		_instruction.show()
	if is_instance_valid(_flow):
		_flow.show()
	_wrpg_actions.clear()
	if modal == "wrpg":
		modal = ""
		room_view.set_modal(false)

func _unhandled_key_input(event: InputEvent) -> void:
	if modal != "wrpg" or not event is InputEventKey or not event.pressed or event.echo:
		return
	var code := (event as InputEventKey).physical_keycode
	if code == KEY_ESCAPE:
		_close_wrpg()
		get_viewport().set_input_as_handled()
		return
	var idx := -1
	match code:
		KEY_1: idx = 0
		KEY_2: idx = 1
		KEY_3: idx = 2
		KEY_4: idx = 3
	if idx >= 0 and idx < _wrpg_actions.size():
		_wrpg_actions[idx].call()
		get_viewport().set_input_as_handled()

func _hall_pendulum_period() -> float:
	var gothic: Node = room_view.find_child("PublicHallGothic", true, false) if is_instance_valid(room_view) else null
	if gothic != null and gothic.has_method("get_pendulum_period_sec"):
		return float(gothic.get_pendulum_period_sec())
	return 7.0 if first_returned else 8.1

func _open_pendulum_sheet() -> void:
	var title := R18n.pick("傅科摆 · 观测选项", "Foucault Pendulum")
	var opts: Array[Dictionary] = []
	if pendulum_measured:
		var traj := R18n.pick("摆迹掠过中心铜钉", "crosses center pin") if first_returned else R18n.pick("摆迹绕开中心铜钉", "misses center pin")
		var body := R18n.pick("实测周期：%.1f 秒（%s）；悬索与摆锤完好无损。", "Measured: %.1f s (%s). Wire and bob undamaged.") % [pendulum_measured_sec, traj]
		if not pendulum_note_recorded:
			opts.append({"label": R18n.pick("在笔记上记载这件事", "Record in notebook"), "cb": _record_pendulum_note})
		if not first_returned:
			opts.append({"label": R18n.pick("询问霍铎关于傅科摆的事", "Ask Hale about the pendulum"), "cb": _ask_hale_pendulum})
		opts.append({"label": R18n.pick("离开", "Step back"), "cb": _close_wrpg})
		_open_wrpg(title, body, opts)
	else:
		var body := R18n.pick("悬索与摆锤无外力损伤；深石板刻度盘周圈 24 根立柱已有两根倒伏。", "Wire and brass bob are intact; two of twenty-four perimeter pegs lie tipped on the dark slate.")
		opts.append({"label": R18n.pick("统计周期", "Measure period"), "cb": _begin_pendulum_judge})
		opts.append({"label": R18n.pick("离开", "Step back"), "cb": _close_wrpg})
		_open_wrpg(title, body, opts)

func _begin_pendulum_judge() -> void:
	_open_wrpg(
		R18n.pick("统计周期 · 判定起点", "Measure Period · Mark Pass"),
		R18n.pick("观察前方摆锤，在它掠过最低点时确认一次，随后将自动完成一个完整往返周期。", "Watch the bob ahead and mark one pass at the lowest point—one full cycle will then complete automatically."),
		[
			{"label": R18n.pick("确认：摆锤已过最低点（开始计时）", "Mark pass now"), "cb": _run_pendulum_cycle_anim},
			{"label": R18n.pick("取消", "Cancel"), "cb": _close_wrpg},
		]
	)

func _run_pendulum_cycle_anim() -> void:
	var watch := _watch_number
	_open_wrpg(
		R18n.pick("统计周期 · 单周期观测中……", "Measuring Period · 1 Full Cycle..."),
		R18n.pick("怀表计时中：摆锤正荡向远端折返点……", "Pocket watch ticking: bob sweeping to the far apex..."),
		[{"label": R18n.pick("中止观测", "Cancel"), "cb": _close_wrpg}]
	)
	await get_tree().create_timer(0.95).timeout
	if watch != _watch_number or modal != "wrpg":
		return
	if is_instance_valid(_wrpg_body):
		_wrpg_body.text = R18n.pick("怀表计时中：摆锤回摆，完成 1 个完整周期……", "Pocket watch ticking: bob returning to complete 1 full cycle...")
	await get_tree().create_timer(0.95).timeout
	if watch != _watch_number or modal != "wrpg":
		return
	pendulum_measured = true
	pendulum_measured_sec = _hall_pendulum_period()
	_open_pendulum_sheet()

func _record_pendulum_note() -> void:
	if not pendulum_note_recorded:
		pendulum_note_recorded = true
		var entry := R18n.pick(
			"03:38 · 公共大厅傅科摆完好无损，实测完整周期 %.1f 秒，摆迹绕开中心铜钉。",
			"03:38 · Public Hall Foucault pendulum intact; measured %.1f s per cycle, missing center pin."
		) % pendulum_measured_sec
		field_notes.append(entry)
		message = R18n.pick("已记入随身笔记（%.1f 秒）。", "Recorded in notebook (%.1f s).") % pendulum_measured_sec
	_open_pendulum_sheet()

func _ask_hale_pendulum() -> void:
	var line := R18n.pick(
		"你也掐出来 %.1f 秒了？按大厅 12.24 米摆长和标准重力算，正常周期该是 7.0 秒，且必经中心铜钉。仪器没坏却走慢偏心，说明出问题的是这间大厅本身。",
		"You timed %.1f s too? With a 12.24 m cable under standard gravity, its normal period is 7.0 s and it always crosses the center pin. It's not the pendulum—it's the Hall."
	) % pendulum_measured_sec
	_speak_hall_mumble(line, "hale")
	var opts: Array[Dictionary] = []
	if not pendulum_note_recorded:
		opts.append({"label": R18n.pick("在笔记上记载这件事", "Record in notebook"), "cb": _record_pendulum_note})
	opts.append({"label": R18n.pick("与霍铎一同进入北翼", "Enter the North Wing with Hale"), "cb": _depart_first})
	opts.append({"label": R18n.pick("返回大厅", "Step back"), "cb": _close_wrpg})
	_open_wrpg(R18n.pick("霍铎（Hale） · 关于傅科摆", "Hale · On the Pendulum"), line, opts)


## ---- Dual-Mode Three-State Spatial Interaction UI (Unified Across Hall & All Campaign Rooms) ----
func _ensure_dual_ui() -> void:
	if is_instance_valid(dual_ui):
		return
	dual_ui = DualInteractionHud.new()
	add_child(dual_ui)
	if is_instance_valid(room_view):
		room_view.unified_hud_active = true
		if not ("FoucaultPendulum" in room_view.suppressed_prompt_ids):
			room_view.suppressed_prompt_ids.append("FoucaultPendulum")

func _sync_dual_ui() -> void:
	_ensure_dual_ui()
	var can_show: bool = (
		phase not in ["lost", "won", "first_expedition"]
		and modal.is_empty()
		and not _performing
		and not (is_instance_valid(_opening) and _opening.active)
		and is_instance_valid(room_view)
		and is_instance_valid(room_view._player)
		and not room_view.is_plan_open()
	)
	if not can_show:
		dual_ui.sync_groups(null, Rect2(), Vector2.ONE, Vector3.ZERO, [], false)
		return
	var cam: Camera3D = room_view._player.camera()
	var groups: Array[Dictionary] = []

	if phase == "camp":
		var anchors: Dictionary = room_view.hall_opening_anchors()
		if not anchors.is_empty():
			var pend_base: Vector3 = anchors.pendulum
			var pin_pos := pend_base + Vector3(0.0, 0.14, 0.0)
			var ring_pos := pend_base + Vector3(-1.35, 0.08, 0.35)
			var hale_pos := (hall_hale.position + Vector3(0.0, 1.45, 0.0)) if is_instance_valid(hall_hale) else (pend_base + Vector3(1.25, 0.35, -0.35))
			var note_verb := R18n.pick("查看笔记记录", "Review note") if pendulum_note_recorded else R18n.pick("记入笔记", "Record in notebook")
			var measure_verb := R18n.pick("重新测周期 (%.1fs)" % pendulum_measured_sec, "Re-measure (%.1fs)" % pendulum_measured_sec) if pendulum_measured else R18n.pick("统计周期", "Measure period")
			var hale_verb := R18n.pick("询问霍铎", "Ask Hale")
			groups.append({
				"id": "FoucaultPendulum",
				"title": R18n.pick("傅科摆", "Foucault Pendulum"),
				"anchor_world": pin_pos,
				"hotspots": [
					{
						"id": "pin",
						"part_name": R18n.pick("中心铜钉", "Center Brass Pin"),
						"verb": measure_verb,
						"world_pos": pin_pos,
						"callback": _begin_pendulum_judge,
					},
					{
						"id": "ring",
						"part_name": R18n.pick("刻度外环", "Outer Degree Ring"),
						"verb": note_verb,
						"world_pos": ring_pos,
						"callback": _dual_ui_record_note,
					},
					{
						"id": "hale",
						"part_name": R18n.pick("询问霍铎", "Ask Hale"),
						"verb": hale_verb,
						"world_pos": hale_pos,
						"callback": _dual_ui_ask_hale,
					},
				],
			})

	# Append all remaining active room targets (Hale, 16 residents, crossing stations, fixtures, exits)
	var exclude := PackedStringArray(["FoucaultPendulum"])
	if phase == "camp" and not first_returned:
		exclude.append("Hale")  # Hale already wired in Foucault group + direct talk
	groups.append_array(room_view.unified_room_targets(exclude))
	dual_ui.sync_groups(cam, room_view._pixels.get_global_rect(), Vector2(room_view._viewport.size), room_view._player.position, groups, true)

func _dual_ui_record_note() -> void:
	if not pendulum_measured:
		if is_instance_valid(dual_ui):
			dual_ui.show_toast(R18n.pick("先对准中心铜钉按 E 统计周期，再记入笔记", "Measure the pendulum period first before recording"))
		return
	_record_pendulum_note()

func _dual_ui_ask_hale() -> void:
	if pendulum_measured:
		_ask_hale_pendulum()
	else:
		_take_deposition("Hale")

func _handle_dual_ui_input(event: InputEvent) -> bool:
	if not is_instance_valid(dual_ui) or not dual_ui.active_enabled or not modal.is_empty():
		return false
	return dual_ui.handle_input(event, true)
