extends Node3D
## Forward+ first-person projection of the authoritative lockstep worker.

const Fixtures := preload("res://scenes/rule_evaluation/Fixtures.gd")
const FieldFilm := preload("res://scenes/rule_evaluation/FieldFilm.gd")
const Cast := preload("res://scenes/rogue_crossing/Roster.gd")
const MM := 0.001
const WAIT := {"type":"Wait"}
const CAMP_EYE := Vector3(0, 1.62, 5.55)
const ACTIONS := {&"eval_next_review": KEY_PAGEUP, &"eval_prev_review": KEY_PAGEDOWN,
	&"eval_use": KEY_E, &"eval_probe": KEY_F, &"eval_crouch": KEY_C, &"eval_notebook": KEY_TAB,
	&"eval_cycle": KEY_Z, &"eval_query": KEY_R, &"eval_evidence": KEY_P, &"eval_previous_evidence": KEY_O, &"eval_logic_proof": KEY_Y,
	&"eval_left": KEY_Q, &"eval_right": KEY_T, &"eval_pause": KEY_SPACE, &"eval_hint": KEY_H}

var _film: FieldFilm
var _film_seed := 1
var _pipe: FileAccess
var _packet := {}
var _render := {}
var _obs := {}
var _objects := {}
var _actors := {}
var _actor_targets := {}
var _view: Camera3D
var _room: Node3D
var _moving_mark: MeshInstance3D
var _level := -1
var _frames := 0
var _review := false
var _paused := false
var _show_hint := false
var _turn_input := 0.0
var _pitch := 0.0
var _target_yaw := 0.0
var _target_cam := Vector3.ZERO
var _selected := 0
var _cycle := 0
var _focus := ""
var _choice := ""
var _spot: SpotLight3D
var _target_objects := {}
var _latest := ""
var _queued: Array = []
var _header: Label
var _subhead: Label
var _interaction: Label
var _focus_panel: PanelContainer
var _party: Label
var _footer: Label
var _warning: Label
var _warning_panel: PanelContainer
var _notebook: PanelContainer
var _journal: RichTextLabel
var _entry: LineEdit
var _evidence_selected := -1

func _ready() -> void:
	Engine.physics_ticks_per_second = 60
	for key: StringName in ACTIONS:
		if not InputMap.has_action(key):
			InputMap.add_action(key)
			var event := InputEventKey.new()
			event.physical_keycode = ACTIONS[key]
			InputMap.action_add_event(key, event)
	var options := {}
	for arg: String in OS.get_cmdline_user_args():
		var kv := arg.trim_prefix("--").split("=", true, 1)
		options[kv[0]] = kv[1] if kv.size() == 2 else true
	_review = options.has("eval-review")
	_paused = options.has("eval-paused") or options.has("eval-film")
	if options.has("eval-film"):
		_film = FieldFilm.new(str(options["eval-film"]), str(options["eval-film-receipt"]))
		_film_seed = int(options.get("run-seed", "1"))
	var args := PackedStringArray(["-u", ProjectSettings.globalize_path("res://core/rule_evaluation/bridge.py"),
		"--seed", str(options.get("run-seed", "1"))])
	if _review: args.append("--review")
	if _film != null:
		args.append_array(PackedStringArray(["--film", str(options.get("eval-film-mode", "admitted"))]))
	if options.has("eval-rehearse-warning"):
		args.append_array(PackedStringArray(["--rehearse-warning",str(options["eval-rehearse-warning"])]))
	var handle := OS.execute_with_pipe(str(options.get("python", "python")), args, true)
	if handle.is_empty():
		push_error("Cannot start evaluator. Supply --python=C:/.../python.exe")
		get_tree().quit(1)
		return
	_pipe = handle.stdio
	_view = Camera3D.new()
	_view.fov = 72
	_view.near = 0.07
	_view.far = 45
	_view.current = true
	add_child(_view)
	_setup_environment()
	_setup_ui()
	_receive()
	if not _review and _film == null:
		_notebook.show()
		_draw_notebook()
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

func _setup_environment() -> void:
	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color("182427")
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color("ccd9e4")
	environment.ambient_light_energy = 0.34
	environment.tonemap_mode = Environment.TONE_MAPPER_ACES
	environment.tonemap_exposure = 1.03
	environment.sdfgi_enabled = true
	environment.sdfgi_use_occlusion = true
	environment.sdfgi_energy = 0.44
	environment.sdfgi_min_cell_size = 0.15
	environment.ssao_enabled = true
	environment.ssao_intensity = 1.25
	var world_env := WorldEnvironment.new()
	world_env.environment = environment
	add_child(world_env)
	if RenderingServer.get_current_rendering_method() == "forward_plus":
		get_viewport().use_taa = true

func _label(parent: Node, value: String, size: int, color := Color("ede9d9")) -> Label:
	var item := Label.new()
	item.text = value
	item.mouse_filter = Control.MOUSE_FILTER_IGNORE
	item.add_theme_font_size_override("font_size", size)
	item.add_theme_color_override("font_color", color)
	parent.add_child(item)
	return item

func _style(background := Color("152022ec"), border := Color("728380")) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = background
	s.border_color = border
	s.border_width_top = 1
	s.border_width_bottom = 1
	s.content_margin_left = 15
	s.content_margin_right = 15
	s.content_margin_top = 8
	s.content_margin_bottom = 8
	return s

func _setup_ui() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)
	var root := Control.new()
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(root)
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var cards := PanelContainer.new()
	cards.position = Vector2(24, 22)
	cards.mouse_filter = Control.MOUSE_FILTER_IGNORE
	cards.add_theme_stylebox_override("panel", _style())
	root.add_child(cards)
	var stack := VBoxContainer.new()
	stack.add_theme_constant_override("separation", 2)
	cards.add_child(stack)
	_subhead = _label(stack, "ACADEMY EXPEDITION  /  FIELD EVALUATION", 13, Color("b1c8bc"))
	_header = _label(stack, "Awaiting field ledger", 28)
	_party = _label(stack, "", 13, Color("ecd5a1"))
	var footer_panel := PanelContainer.new()
	root.add_child(footer_panel)
	footer_panel.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	footer_panel.offset_left = 24
	footer_panel.offset_right = -24
	footer_panel.offset_top = -63
	footer_panel.offset_bottom = -19
	footer_panel.add_theme_stylebox_override("panel", _style())
	footer_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_footer = _label(footer_panel, "", 15, Color("d9e2d4"))
	_footer.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	var cross := _label(root, "+", 23, Color("f4eadc"))
	cross.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	cross.position -= Vector2(6, 16)
	cross.visible = _film == null
	var focus_panel := PanelContainer.new()
	root.add_child(focus_panel)
	focus_panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	focus_panel.offset_left = -270
	focus_panel.offset_right = 270
	focus_panel.offset_top = -130
	focus_panel.offset_bottom = -78
	focus_panel.add_theme_stylebox_override("panel", _style(Color("172123da")))
	focus_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_interaction = _label(focus_panel, "", 16)
	_interaction.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_interaction.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_focus_panel = focus_panel
	_warning_panel = PanelContainer.new()
	root.add_child(_warning_panel)
	_warning_panel.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	_warning_panel.offset_left = -426
	_warning_panel.offset_right = -24
	_warning_panel.offset_top = 22
	_warning_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_warning_panel.add_theme_stylebox_override("panel", _style(Color("31201bf5"), Color("e19165")))
	_warning = _label(_warning_panel, "", 19, Color("ffbc96"))
	_warning.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_warning_panel.hide()
	_notebook = PanelContainer.new()
	root.add_child(_notebook)
	_notebook.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_notebook.offset_left = 127
	_notebook.offset_top = 121
	_notebook.offset_right = -127
	_notebook.offset_bottom = -133
	_notebook.add_theme_stylebox_override("panel", _style(Color("17201ffb")))
	var rows := VBoxContainer.new()
	_notebook.add_child(rows)
	_label(rows, "FIELD NOTEBOOK / TYPED RULES AND RADIO", 19)
	_journal = RichTextLabel.new()
	_journal.bbcode_enabled = false
	_journal.selection_enabled = true
	_journal.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_journal.add_theme_font_size_override("normal_font_size", 15)
	rows.add_child(_journal)
	_entry = LineEdit.new()
	_entry.placeholder_text = 'Send a typed action: {"type":"QueryCompanion","agent_id":1}'
	_entry.text_submitted.connect(_submit_action)
	rows.add_child(_entry)
	_notebook.hide()

func _exit_tree() -> void:
	if _pipe != null and _pipe.is_open():
		_pipe.store_line('{"op":"quit"}')
		_pipe.flush()
		_pipe.close()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

func _send(message: Dictionary) -> void:
	if _pipe == null: return
	_pipe.store_line(JSON.stringify(message))
	_pipe.flush()
	_receive()

func _receive() -> void:
	var raw: Variant = JSON.parse_string(_pipe.get_line())
	if not raw is Dictionary:
		push_error("Rule-evaluation worker was disconnected")
		get_tree().quit(1)
		return
	if raw.has("error"):
		_latest = str(raw.error)
		if _packet.is_empty():
			push_error(_latest)
			get_tree().quit(1)
		return
	_packet = raw
	_render = _packet.visual
	_obs = _packet.observation
	_latest = str(_render.get("last_result", ""))
	var rebuild := int(_render.level) != _level
	if rebuild:
		_level = int(_render.level)
		_cycle = 0
		_focus = ""
		_selected = 0
		_evidence_selected = -1
		_build()
	_apply(rebuild or _review)
	_draw_notebook()

func _build() -> void:
	if is_instance_valid(_room):
		remove_child(_room)
		_room.queue_free()
	_room = Node3D.new()
	_room.name = "RenderedChamber"
	add_child(_room)
	_objects.clear()
	_target_objects.clear()
	_spot = null
	if _level == 11:
		Fixtures.encasement(_room, 11.0, 15.0, _level, "Main Camp Hall / Expedition Complete")
		Fixtures.archive_plate(_room, Vector3(-3.79, 2.24, 12.63), Rect2i(0, 298, 480, 270), "04  /  FOREST CAMP")
		Fixtures.archive_plate(_room, Vector3(3.79, 2.24, 12.63), Rect2i(480, 0, 480, 270), "02  /  WEST CHAPEL")
		var wood := Fixtures.matte(Color("7f5c43"))
		var cloth := Fixtures.matte(Color("a8734e"))
		Fixtures.box(_room, Vector3(0, 0.02, 9), Vector3(4.0, 0.04, 7.8), cloth)
		for x: float in [-2.3, 2.3]:
			Fixtures.box(_room, Vector3(x, 0.51, 8.4), Vector3(1.1, 0.20, 4.3), wood)
			for z: float in [6.9, 10.0]:
				Fixtures.box(_room, Vector3(x, 0.26, z), Vector3(0.75, 0.52, 0.16), wood)
		var chart := Fixtures.matte(Color("d0bb8b"))
		var iron := Fixtures.matte(Color("343b3d"), 0.14)
		Fixtures.box(_room, Vector3(0, 0.62, 11.5), Vector3(3.00, 1.24, 0.68), wood)
		Fixtures.box(_room, Vector3(0, 2.85, 12.7), Vector3(4.8, 1.44, 0.17), iron)
		Fixtures.box(_room, Vector3(0, 2.85, 12.58), Vector3(4.58, 1.23, 0.07), chart)
		for x: float in [-1.74,-0.86,0.0,0.86,1.74]:
			Fixtures.box(_room,Vector3(x,2.68,12.529),Vector3(0.39,0.06,0.02),iron)
			Fixtures.box(_room,Vector3(x,2.93,12.533),Vector3(0.17,0.17,0.02),iron)
		for x: float in [-2.0,2.0]:
			Fixtures.box(_room,Vector3(x,1.11,12.7),Vector3(0.13,2.10,0.14),wood)
		Fixtures.print_on(_room, "EXPEDITION RETURNED", Vector3(0, 3.18, 12.525), Color("fff1ce"), 0.005)
		Fixtures.print_on(_room, "F I E L D  M A P   /   C H A M B E R S   0 1 — 1 0", Vector3(0,2.47,12.522),Color("212b28"),0.0027)
		return
	var size: Array = _render.size
	var portal := Vector3.INF
	var span := 1.7
	for e: Dictionary in _render.entities:
		if e.entity_id == "exit":
			portal = _point(e.primitive_geometry.position)
			span = float(e.primitive_geometry.size[0])*MM
	Fixtures.encasement(_room, float(size[0])*MM, float(size[1])*MM, _level, _room_heading(), portal, span)
	for e: Dictionary in _render.entities:
		var holder := Fixtures.make(_room, e, bool(_render.separate_exit_leaf))
		_objects[e.entity_id] = holder
		if e.entity_class in ["counterweight", "shutter"] and e.has("travel") and absf(float(e.travel[1])) >= 650:
			var load_size := _point(e.primitive_geometry.size)
			var cables := Node3D.new()
			_room.add_child(cables)
			var steel := Fixtures.matte(Color("55534c"), 0.52)
			for x: float in [-0.31, 0.31]:
				Fixtures.box(cables, Vector3(x*load_size.x, 0.5, load_size.z*0.18), Vector3(0.042, 1.02, 0.042), steel)
			holder["suspension"] = cables
			holder["load_height"] = load_size.y
		if e.entity_id == "latch" and e.has("mount"):
			var p := _point(e.mount)
			Fixtures.box(_room,p + Vector3(0,0.40,0),Vector3(1.30,0.80,0.67),Fixtures.matte(Color("58635c"),0.12))
	if _objects.has("projector") and _objects.has("reticle"):
		_spot = SpotLight3D.new()
		_spot.light_energy = 1.40
		_spot.spot_range = 6.0
		_spot.spot_angle = 14.0
		_spot.light_color = Color("f4c26d")
		_spot.shadow_enabled = true
		_room.add_child(_spot)
	_moving_mark = Fixtures.disk(_room, Vector3.ZERO, 0.11, 0.035, Fixtures.light_mat(Color("d7ed87")))
	_moving_mark.hide()

func _attach_actor(id: int) -> void:
	var display := Node3D.new()
	display.name = "Teammate%d" % id
	add_child(display)
	var body := Node3D.new()
	display.add_child(body)
	if not Cast.attach(body, "Ione" if id == 1 else "Silas"):
		Fixtures.box(body, Vector3(0, 0.85, 0), Vector3(0.47,1.7,0.32), Fixtures.matte(Color("829e91")))
	var tag := Label3D.new()
	tag.text = "1  HALE" if id == 1 else "2  FINCH"
	tag.position.y = 1.95
	tag.pixel_size = 0.0025
	tag.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	tag.modulate = Color("f2d3b5") if id == 1 else Color("bfdcea")
	display.add_child(tag)
	_actors[id] = {"root":display, "body":body, "tag":tag, "anim":body.get_meta("animation_player", null)}

func _point(x: Array) -> Vector3:
	return Vector3(float(x[0]),float(x[1]),float(x[2])) * MM

func _room_heading() -> String:
	var title := str(_render.title)
	if _level < 1 or _level > 10: return title
	for separator: String in [" | ", " · ", " / "]:
		if title.contains(separator):
			return "%02d / %s" % [_level, title.get_slice(separator, 1)]
	return "%02d / %s" % [_level, title]

func _apply(snap: bool) -> void:
	_header.text = _room_heading()
	_subhead.text = "LOCKSTEP  /  60 Hz      |      STEP %05d     |     %s" % [int(_render.tick), _packet.get("review", "FIELD EXERCISE")]
	_warning_panel.visible = bool(_obs.get("warning", false))
	_warning.text = "OVERPRESSURE  /  RELIEVE THE YOKE" if _level == 4 else "MECHANICAL FAULT  /  STOP"
	if _level != 4 and _warning_panel.visible:
		for e: Dictionary in _render.get("entities", []):
			if e.entity_id == "alarm" and not str(e.label).is_empty():
				_warning.text = str(e.label).to_upper()
	_footer.text = "PgUp / PgDn  Review verified actions   •   Tab  Field notebook" if _review else "WASD  Walk      Mouse  Look      E  Operate      Z  Cycle      C  Crouch      F  Probe      Tab  Notebook      Space  Pause"
	for id in _actors: _actors[id].root.hide()
	if _level == 11:
		_target_cam = CAMP_EYE
		_view.position = _target_cam
		_target_yaw = 0.0
		_pitch = -0.01
		_party.text = "ALL TEN CHAMBERS CLEARED"
		for id in [1,2]:
			if not _actors.has(id): _attach_actor(id)
			var crew := _actors[id].root as Node3D
			var go := Vector3(-1.72 if id==1 else 1.72,0.0,9.15+float(id)*0.2)
			_actor_targets[id] = go
			crew.position = go
			crew.rotation.y = 2.81 if id==1 else -2.81
			crew.show()
			var actor_body := _actors[id].body as Node3D
			actor_body.scale = Vector3.ONE
			var anim := _actors[id].anim as AnimationPlayer
			if anim and anim.has_animation(&"idle"): anim.play(&"idle",0.14)
		return
	var local: Dictionary = _render.actors[0]
	var eye_height := 0.94 if local.pose == "crouch" else 1.56
	_target_cam = Vector3(float(local.pos[0])*MM, eye_height, float(local.pos[1])*MM)
	_target_yaw = deg_to_rad(float(local.yaw))
	if snap:
		_view.position = _target_cam
		if _review: _pitch = -0.035
	var party := PackedStringArray(["● LEAD" if _selected == 0 else "LEAD"])
	for e: Dictionary in _render.entities:
		var holder: Dictionary = _objects[e.entity_id]
		var model := holder.root as Node3D
		var point := _point(e.primitive_geometry.position)
		_target_objects[e.entity_id] = point
		if snap: model.position = point
		var pointer := holder.get("pointer") as Node3D
		if pointer and e.has("mount"):
			pointer.position = _point(e.mount) - point
		var door := holder.get("slide") as Node3D
		if door:
			door.position.x = float(holder.span) if _render.exit_open else 0.0
		var flag := holder.get("flag") as Node3D
		if flag:
			flag.visible = int(e.whitebox_state.get("selected", 0)) == 1
		if not e.lit and e.entity_class != "reticle":
			var blackout := Fixtures.matte(Color("030505"))
			for n in model.find_children("*", "MeshInstance3D", true, false):
				if not n.has_meta("original"):
					n.set_meta("original", n.material_override)
				n.material_override = blackout
		else:
			for n in model.find_children("*", "MeshInstance3D", true, false):
				if n.has_meta("original"):
					n.material_override = n.get_meta("original")
		for n in model.find_children("*", "Label3D", true, false): n.visible = bool(e.lit) or e.entity_class == "reticle"
		var state: Dictionary = e.whitebox_state
		var gauge := holder.get("gauge") as Node3D
		if gauge:
			gauge.rotation.z = deg_to_rad(120.0-1.7*float(state.pressure_kpa))
		var on: bool = bool(_render.exit_open) if e.entity_id == "exit" else _signal_on(e, state)
		var mark := holder.get("mark") as MeshInstance3D
		if mark:
			var glow: StandardMaterial3D = holder.indicator
			var color := Fixtures.GREEN if on else Fixtures.AMBER
			if e.entity_id == "alarm":
				color = Color("ff4732") if _render.alarm else Color("51322c")
			if e.entity_class == "reticle": color = Color("ffda63") if e.lit else Color("3c372c")
			if e.entity_class == "lamp": color = Color("f5d68b") if on else Color("362f26")
			glow.albedo_color = color
			glow.emission = color
			glow.emission_energy_multiplier = 1.6 if (e.entity_class == "reticle" and e.lit) or (e.entity_id == "alarm" and _render.alarm) else 0.58
		var lever := holder.get("lever") as Node3D
		if lever:
			var goal := deg_to_rad(-21.0 if on else 0.0)
			holder["lever_rotation"] = goal
			if snap: lever.rotation.z = goal
		var rotor := holder.get("rotor") as Node3D
		if rotor:
			var period := maxi(1, int(state.get("period", state.get("period_ticks", 240))))
			var phase := (int(_render.room_tick) + int(state.get("offset",state.get("offset_ticks",0)))) % period
			rotor.rotation.z = TAU * float(phase) / float(period)
	if _spot:
		var lens: Vector3 = _target_objects.projector + Vector3(0,0.275,0)
		var receptor: Vector3 = _target_objects.reticle + Vector3(0,0.197,0)
		_spot.position = lens + (receptor-lens).normalized()*0.66
		_spot.look_at(receptor,Vector3.UP)
		for e: Dictionary in _render.entities:
			if e.entity_id == "reticle": _spot.visible = bool(e.lit)
	if _moving_mark != null:
		_moving_mark.visible = _render.probe != null
		if _moving_mark.visible: _moving_mark.position = _point(_render.probe.point)
	for a: Dictionary in _render.actors.slice(1):
		var id := int(a.agent_id)
		if not _actors.has(id): _attach_actor(id)
		var cast: Dictionary = _actors[id]
		var target := Vector3(float(a.pos[0])*MM, 0, float(a.pos[1])*MM)
		var actor_root := cast.root as Node3D
		var prior: Vector3 = _actor_targets.get(id, target)
		_actor_targets[id] = target
		if snap: actor_root.position = target
		actor_root.visible = Vector2(target.x-_target_cam.x,target.z-_target_cam.z).length_squared() > 0.27
		actor_root.rotation.y = deg_to_rad(float(a.yaw))
		var recent: Variant = _render.last_interaction
		if a.motion == "operate" and recent is Dictionary and int(recent.actor) == id:
			var fixture: Vector3 = _target_objects.get(recent.action.target_entity_id, target)
			if Vector2(fixture.x - target.x, fixture.z - target.z).length_squared() > 0.02:
				actor_root.rotation.y = atan2(fixture.x - target.x, fixture.z - target.z)
		elif prior.distance_to(target) > 0.03:
			actor_root.rotation.y = atan2(target.x - prior.x, target.z - prior.z)
		var body := cast.body as Node3D
		body.scale.y = 0.64 if a.pose == "crouch" else 1.0
		var anim := cast.anim as AnimationPlayer
		if anim:
			var motion: StringName = &"interact" if a.motion == "operate" else (&"walk" if (a.motion in ["walk","creep"] or (not snap and prior.distance_to(target) > 0.035)) else &"idle")
			if motion == &"interact" and _render.last_interaction != null and str(_render.last_interaction.action.op_type) in ["turn", "retract", "release", "mesh", "throw", "shift"] and anim.has_animation(&"operate"):
				motion = &"operate"
			if anim.has_animation(motion) and (anim.current_animation != motion):
				anim.play(motion, 0.14)
				if _review and motion in [&"interact", &"operate"]:
					anim.seek(0.24, true)
					anim.pause()
		party.append(("● " if _selected == id else "") + ("1  HALE" if id == 1 else "2  FINCH") + "  P%d S%d" % [int(a.panic_band), int(a.sanity_band)])
	_party.text = "     /     ".join(party)

func _signal_on(e: Dictionary, state: Dictionary) -> bool:
	const CHANNELS := {"latch":"latched", "selector":"live", "vent":"bled", "receiver":"charged",
		"release":"thrown", "handle":"released", "reticle":"", "console":"armed", "clutch":"engaged", "capstan":"stroked", "bolt":"extended", "projector":"powered"}
	if e.entity_id == "reticle": return bool(e.lit)
	var preferred := str(CHANNELS.get(e.entity_id, ""))
	if preferred != "": return int(state.get(preferred, 0)) == 1
	for key: String in ["active", "occupied", "selected", "braced", "charged", "driven", "meshed", "raised", "turned", "retained", "secured"]:
		if state.has(key): return int(state[key]) == 1
	return false

func _process(delta: float) -> void:
	if _view == null: return
	_view.position = _view.position.lerp(_target_cam, minf(1.0,delta*8.0))
	_view.rotation = Vector3(_pitch, PI + _target_yaw + deg_to_rad(_turn_input), 0.0)
	for key in _target_objects:
		if _objects.has(key):
			var fixture := _objects[key].root as Node3D
			fixture.position = fixture.position.lerp(_target_objects[key], minf(1.0, delta*12.0))
			var lever: Node3D = _objects[key].get("lever")
			if lever:
				lever.rotation.z = lerpf(lever.rotation.z, float(_objects[key].get("lever_rotation", 0.0)), minf(1.0, delta*14.0))
			var cables: Node3D = _objects[key].get("suspension")
			if cables:
				cables.position = fixture.position + Vector3.UP * float(_objects[key].load_height)
				cables.scale.y = maxf(0.012, 4.18 - cables.position.y)
	for id in _actor_targets:
		if _actors.has(id):
			var node := _actors[id].root as Node3D
			node.position = node.position.lerp(_actor_targets[id], minf(1.0,delta*9.0))
	if _film != null:
		_film.advance(self)
		return
	_update_focus()
	_focus_panel.visible = not _notebook.visible and not _interaction.text.is_empty()

func _update_focus() -> void:
	if _obs.get("status", "") != "RUNNING":
		_interaction.text = "Camp reached." if _level == 11 else "Expedition ended. Restart the scene to try again."
		return
	var emergency: Variant = _render.get("emergency")
	if emergency is Dictionary:
		_focus = emergency.target_entity_id
		_choice = emergency.op_type
		_interaction.text = "E  %s   /   EMERGENCY CONTROL" % _choice.to_upper().replace("_", " ")
		return
	var nearest: Dictionary = {}
	var best := 0.81
	var forward: Vector3 = -_view.global_basis.z
	for e: Dictionary in _render.entities:
		if not bool(e.lit) or e.operations.is_empty(): continue
		var p := _point(e.primitive_geometry.position)
		var height: float = float(e.primitive_geometry.size[1])*MM
		p.y += minf(1.40, height*0.72)
		var offset := p - _view.position
		if offset.length() > (3.1 if _selected == 0 else 9.5): continue
		var q := forward.dot(offset.normalized())
		if q > best and not _occluded(e.entity_id,p):
			nearest = e
			best = q
	if nearest.is_empty():
		_focus = ""
		_choice = ""
		var recent: Variant = _render.get("last_interaction")
		if recent is Dictionary and int(_render.tick)-int(recent.tick) <= 45:
			_interaction.text = "%s  /  %s logged" % [str(recent.action.target_entity_id).capitalize(), str(recent.action.op_type).capitalize()]
		else: _interaction.text = "PAUSED" if _paused else ""
		return
	if _focus != nearest.entity_id:
		_focus = nearest.entity_id
		_cycle = 0
	var ops: Array = nearest.operations
	_choice = str(ops[_cycle % ops.size()])
	var description := "E %s" % _choice.to_upper().replace("_"," ")
	if _focus == "exit" and not _render.exit_open: description = "INTERLOCKED"
	if ops.size() > 1: description += "  •  Z OPTIONS"
	var recent: Variant = _render.get("last_interaction")
	var confirmation := ""
	if recent is Dictionary and int(_render.tick)-int(recent.tick) <= 40:
		confirmation = "  /  %s logged" % str(recent.action.op_type).replace("_"," ")
	_interaction.text = "%s   •   %s%s" % [str(nearest.label).split(" | ")[0], description, confirmation]

func _occluded(ignore: String, end: Vector3) -> bool:
	for e: Dictionary in _render.entities:
		if e.entity_id == ignore or not e.primitive_geometry.solid: continue
		var center := _point(e.primitive_geometry.position)
		var size := _point(e.primitive_geometry.size)
		var bound := AABB(center-Vector3(size.x*0.5,0,size.z*0.5),size)
		var res: Variant = bound.intersects_segment(_view.position, end)
		if res is Vector3 and res.distance_squared_to(_view.position) > 0.005 and res.distance_squared_to(end) > 0.035:
			return true
	return false

func _draw_notebook() -> void:
	if not _notebook.visible: return
	var companions: Array = _obs.get("companions", [])
	var text := PackedStringArray([
		"0 Lead  /  1 Hale  /  2 Finch     Select then direct movement and fixture actions.",
		"Close this notebook to use the radio: R queries selected crew, O cycles evidence, P submits a record, Y submits alternate proof.",
		"H toggles optional commissioning notes."])
	if _show_hint:
		text.append("\nCOMMISSIONING NOTES")
		text.append(str(_render.get("hint", "Return complete.")))
	text.append("\nYOUR HANDBOOK / LOCALLY POSTED RULES")
	for r: Dictionary in _obs.get("manual", []) + _obs.get("room_rules", []): text.append(_pretty_rule(r))
	for companion: Dictionary in companions:
		text.append("\n%s  |  PANIC %d/10  |  SANITY %d/10" % [companion.name, companion.panic_band, companion.sanity_band])
		for r: Dictionary in companion.declared_rules: text.append(_pretty_rule(r))
		if not companion.standoff.is_empty(): text.append("Holding: " + str(companion.standoff))
	var response: Variant = _obs.get("probe_response")
	if response is Dictionary:
		text.append("\nPROBE RESPONSE   %s   •   %s = %d" % [response.fixture, str(response.field).replace("_"," "), int(response.value)])
	text.append("\nSTABLE WITNESS RECORDS")
	var rows := _evidence_rows()
	for i in range(rows.size()):
		var sample: Dictionary = rows[i]
		text.append(("● " if i == posmod(_evidence_selected, rows.size()) else "  ") + "%s  /  %s  %s" % [sample.id, sample.action.op_type, sample.action.target_entity_id])
		for rule_id: String in sample.get("deductions", {}):
			text.append("    Dry-cycle handoff evidence  /  %s" % rule_id)
	for pending: Dictionary in _obs.get("evidence_pending", []):
		text.append("  %s  /  %s  %s  /  developing until tick %d" % [pending.id, pending.action.op_type,
			pending.action.target_entity_id, int(pending.ready_tick)])
	var logic: Array = _obs.get("logic_proofs", [])
	if not logic.is_empty():
		text.append("\nDOCUMENTED PHASE PROOFS  /  Y to radio the selected operator")
		for proof: Dictionary in logic:
			text.append("  %s  /  %s" % ["Hale" if int(proof.agent_id) == 1 else "Finch", proof.rule_node_id])
			text.append("    Window: %s" % JSON.stringify(_as_integer_values(proof.window)))
			text.append("    Records: %s" % ", ".join(PackedStringArray(proof.evidence_ref)))
	var equipment: Dictionary = _obs.get("equipment", {})
	text.append("\nOBSERVED EQUIPMENT / WHITEBOX TRANSFER FUNCTIONS")
	for id: String in equipment:
		var doc: Dictionary = equipment[id]
		var ops: Dictionary = doc.get("operations", {})
		var clock: Array = doc.get("periodic", [])
		var interlock: Array = doc.get("interlock", [])
		if ops.is_empty() and clock.is_empty() and interlock.is_empty(): continue
		text.append("  %s  /  %s" % [id, str(doc.label)])
		for cycle: Dictionary in clock:
			text.append("    %s  •  (room tick + %d) mod %d < %d" % [cycle.field, int(cycle.offset), int(cycle.period), int(cycle.window)])
		if not interlock.is_empty():
			text.append("    Door guard  %s" % JSON.stringify(_as_integer_values(interlock)))
		for verb: String in ops:
			text.append("    %s  •  if %s  →  %s" % [verb, JSON.stringify(_as_integer_values(ops[verb].when)), JSON.stringify(_as_integer_values(ops[verb].effects))])
	var last_scroll := _journal.get_v_scroll_bar().value
	_journal.text = "\n".join(text)
	_journal.get_v_scroll_bar().set_value_no_signal(last_scroll)

func _pretty_rule(r: Dictionary) -> String:
	return "%s  |  %s  %s  if  %s%s" % [r.rule_id, r.modality, JSON.stringify(r.action), JSON.stringify(_as_integer_values(r.condition)),
		"  /  EVIDENCE ACCEPTED" if r.has("exceptions") else ""]

func _evidence_rows() -> Array:
	return _obs.get("evidence", [])

func _action_for_selected(act: Dictionary) -> Dictionary:
	if _selected == 0: return act
	return {"type":"CommandCompanion", "agent_id":_selected, "action_spec":act}

func _proof() -> void:
	if _selected <= 0: return
	var samples := _evidence_rows()
	if samples.is_empty(): return
	var chosen: Dictionary = samples[posmod(_evidence_selected, samples.size())]
	var companions: Array = _obs.get("companions", [])
	for r: Dictionary in companions[_selected-1].declared_rules:
		if r.action.get("target_entity_id", "") == chosen.action.target_entity_id and r.action.get("op_type", "") == chosen.action.op_type:
			_queued.append({"type":"PersuadeWithEvidence", "agent_id":_selected, "rule_node_id":r.rule_id,
				"proposed_ast_patch":{"mode":"EXEMPT_ACTION"}, "evidence_ref":[chosen.id]})
			return

func _documented_proof() -> void:
	for proof: Dictionary in _obs.get("logic_proofs", []):
		if int(proof.agent_id) != _selected: continue
		var dry_record_exists := _evidence_rows().any(func(sample: Dictionary) -> bool:
			return sample.get("deductions", {}).has(proof.rule_node_id))
		if dry_record_exists: continue
		_queued.append({"type":"PersuadeWithEvidence", "agent_id":_selected, "rule_node_id":proof.rule_node_id,
			"proposed_ast_patch":{"mode":proof.mode}, "evidence_ref":proof.evidence_ref})
		return

func _as_integer_values(v: Variant) -> Variant:
	if v is float and v == floorf(v): return int(v)
	if v is Array:
		var converted: Array = []
		for item: Variant in v: converted.append(_as_integer_values(item))
		return converted
	if v is Dictionary:
		var converted := {}
		for key in v: converted[key] = _as_integer_values(v[key])
		return converted
	return v

func _submit_action(raw: String) -> void:
	var packet: Variant = _as_integer_values(JSON.parse_string(raw))
	if _review: return
	if packet is Dictionary or packet is Array:
		_entry.clear()
		_send({"op":"step", "action":packet})
	else:
		_entry.placeholder_text = "Expected an action object or an ordered action array."

func _input(event: InputEvent) -> void:
	if _view == null or _film != null: return
	if _notebook.visible and not _entry.has_focus() and event.is_action_pressed(&"eval_hint"):
		_show_hint = not _show_hint
		_draw_notebook()
		get_viewport().set_input_as_handled()
		return
	if event.is_action_pressed(&"eval_notebook"):
		_notebook.visible = not _notebook.visible
		if _notebook.visible:
			_draw_notebook()
			Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		else:
			_entry.release_focus()
			if not _review and not _paused: Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
		get_viewport().set_input_as_handled()
		return
	if _review:
		if event.is_action_pressed(&"eval_next_review"): _send({"op":"review_next"})
		if event.is_action_pressed(&"eval_prev_review"): _send({"op":"review_prev"})
		return
	if event is InputEventKey and event.pressed and not event.echo and not _entry.has_focus():
		if event.physical_keycode >= KEY_0 and event.physical_keycode <= KEY_2:
			_selected = mini(event.physical_keycode - KEY_0, _render.get("actors", []).size()-1)
			_selected = maxi(0, _selected)
			_apply(false)
		if event.physical_keycode == KEY_ESCAPE:
			Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	if _notebook.visible or _obs.get("status", "") != "RUNNING": return
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT and not _paused:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		_turn_input = clampf(_turn_input - event.relative.x * 0.20, -178.0, 178.0)
		_pitch = clampf(_pitch - event.relative.y * 0.0026, -0.83, 0.61)
	if event.is_action_pressed(&"eval_pause"): _paused = not _paused
	if event.is_action_pressed(&"eval_left"): _turn_input += 15.0
	if event.is_action_pressed(&"eval_right"): _turn_input -= 15.0
	if event.is_action_pressed(&"eval_cycle"): _cycle += 1
	if event.is_action_pressed(&"eval_use") and not _focus.is_empty() and (_focus != "exit" or _render.exit_open):
		var act := {"type":"Interact", "target_entity_id":_focus, "op_type":_choice}
		_queued.append(act if _render.get("emergency") is Dictionary else _action_for_selected(act))
	if event.is_action_pressed(&"eval_crouch"):
		var pose := "stand" if _render.actors[_selected].pose == "crouch" else "crouch"
		_queued.append(_action_for_selected({"type":"SetPose", "pose":pose}))
	if event.is_action_pressed(&"eval_probe"):
		var probe := {"type":"DeployProbe", "dir_vec":[0,0]}
		if not _focus.is_empty(): probe.target_entity_id = _focus
		_queued.append(_action_for_selected(probe))
	if event.is_action_pressed(&"eval_query") and _selected:
		_queued.append({"type":"QueryCompanion", "agent_id":_selected})
	if event.is_action_pressed(&"eval_previous_evidence"): _evidence_selected -= 1
	if event.is_action_pressed(&"eval_evidence"): _proof()
	if event.is_action_pressed(&"eval_logic_proof"): _documented_proof()

func _physics_process(_delta: float) -> void:
	if _review or _paused or _view == null or _notebook.visible or _obs.get("status", "") != "RUNNING": return
	_frames += 1
	if _frames % 20 != 0: return
	var packet: Array = []
	if absf(_turn_input) >= 0.51:
		var amount := clampi(roundi(_turn_input), -178, 178)
		packet.append({"type":"RotateYaw", "delta_angle":amount})
		_turn_input -= float(amount)
	var movement := Input.get_vector(&"move_left", &"move_right", &"move_down", &"move_up")
	if movement.length_squared() > 0.03:
		var yaw := _target_yaw + deg_to_rad(float(packet[0].delta_angle)) if not packet.is_empty() else _target_yaw
		var x := -movement.x * cos(yaw) + movement.y * sin(yaw)
		var z := movement.x * sin(yaw) + movement.y * cos(yaw)
		packet.append(_action_for_selected({"type":"Move", "dir_vec":[roundi(x*950),roundi(z*950)],
			"speed_ratio":55 if _render.actors[_selected].pose == "crouch" else 80, "duration_ticks":20}))
	while not _queued.is_empty() and packet.size() < 6: packet.append(_queued.pop_front())
	_send({"op":"step", "action":packet if not packet.is_empty() else WAIT})

func mcp_observe() -> Dictionary:
	return {"status":_obs.get("status", "STARTING"), "level":_level, "review":_packet.get("review", ""),
		"tick":_render.get("tick", 0), "exit_open":_render.get("exit_open", false), "focus":_focus,
		"last_result":_latest, "paused":_paused, "notebook_visible":_notebook.visible,"commissioning_notes":_show_hint,"emergency_operation":_render.get("emergency"), "observation":_obs}
