extends Node3D
## L03 playable slice. One live 60 Hz tick advances input, Godot bodies,
## observation, the typed rule and its evidence, then the view of those bodies.
const SceneRoom = preload("res://scenes/physics_lab/airlock/Room.gd")
const Rules = preload("res://scenes/physics_lab/airlock/Rules.gd")
const DetectiveMotion := preload("res://scenes/physics_lab/airlock/DetectiveMotion.gd")
const DOG_TICKS := 48
const EyeHeight := 1.57
const STEP := 1.0 / 60.0
const RISE_TICKS := 26
const GRACE_TICKS := 60
const LEAD_HOME := Vector3(0, 0, 4.15)
const HALE_HOME := Vector3(1.26, 0, 2.31)
const PROBE_HOME := Vector3(0, .023, 1.79)
const WALK_SPEED := 3.0
const HALE_SPEED := 2.65
const KEYS := {&"air_forward": KEY_W, &"air_back": KEY_S, &"air_left": KEY_A, &"air_right": KEY_D,
	&"air_turn_l": KEY_LEFT, &"air_turn_r": KEY_RIGHT, &"air_up": KEY_UP, &"air_down": KEY_DOWN,
	&"air_trial": KEY_E, &"air_lamp": KEY_F, &"air_request": KEY_C, &"air_share": KEY_Q,
	&"air_manual": KEY_J, &"air_reset": KEY_R}
const AUDIT_WAIT := {&"air_wait": 20, &"air_wait_short": 5, &"air_tick": 1}
const TRAVEL := [&"air_forward", &"air_back", &"air_left", &"air_right"]
const TURNS := [&"air_turn_l", &"air_turn_r", &"air_up", &"air_down"]
const EVENTS := [&"air_trial", &"air_lamp", &"air_request", &"air_share"]
var room := SceneRoom.new()
var rules := Rules.new()
var player: CharacterBody3D
var hale: CharacterBody3D
var probe: CharacterBody3D
var model_hale: Node3D
var hale_motion: DetectiveMotion
var camera: Camera3D
var tick := 0
var frame_flags: Dictionary = {}
var event_trace: Array[Dictionary] = []
var guided := false
var audit := false
var audit_action := &""
var audit_left := 0
var pending: Array[StringName] = []
var reset_queued := false
var pending_mouse := Vector2.ZERO
var yaw := 0.0
var pitch := 0.0
var lamp_on := true
var lift_steps := 0
var lose_at := -1
var lead_warn_at := -1
var hale_warn_at := -1
var lead_visible_ticks := 0
var hale_visible_ticks := 0
var collapsed_at := -1
var sight := false
var dog_seated := false
var door_steps := 0
var cleared := false
var duty := "ON NEAR BANK"
var trial: Dictionary = {}
var fall := {"lead": 0.0, "hale": 0.0, "probe": 0.0}
var messaged := 0
var message := ""
var stage: Node3D
var header: Label
var hint: Label
var radio: Label
var journal: PanelContainer
var notes: Label
var dot: Label
var dog_stroke := 0


func _ready() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg == "--airlock-audit": audit = true
	for code: StringName in KEYS: _bind_key(code, KEYS[code])
	_bind_key(&"air_wait", KEY_NONE)
	_bind_key(&"air_wait_short", KEY_NONE)
	_bind_key(&"air_tick", KEY_NONE)
	get_viewport().msaa_3d = Viewport.MSAA_4X
	_make_ui()
	_build()
	if not audit and DisplayServer.get_name() != "headless": Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _exit_tree() -> void:
	if not audit: Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func _bind_key(action: StringName, physical: Key) -> void:
	if InputMap.has_action(action): return
	InputMap.add_action(action)
	if physical != KEY_NONE:
		var key := InputEventKey.new()
		key.physical_keycode = physical
		InputMap.action_add_event(action, key)


func _build() -> void:
	if is_instance_valid(stage):
		remove_child(stage)
		stage.queue_free()
	stage = Node3D.new()
	add_child(stage)
	room = SceneRoom.new()
	room.make(stage)
	rules = Rules.new()
	tick = 0
	frame_flags = {}
	event_trace.clear()
	pending.clear()
	audit_left = 0
	audit_action = &""
	yaw = 0.0
	pitch = 0.0
	pending_mouse = Vector2.ZERO
	lamp_on = true
	lift_steps = 0
	lose_at = -1
	lead_warn_at = -1
	hale_warn_at = -1
	lead_visible_ticks = 0
	hale_visible_ticks = 0
	collapsed_at = -1
	sight = false
	dog_seated = false
	door_steps = 0
	cleared = false
	duty = "ON NEAR BANK"
	dog_stroke = 0
	trial = {}
	fall = {"lead": 0.0, "hale": 0.0, "probe": 0.0}
	message = ""
	messaged = 0
	player = _body("lead", LEAD_HOME, SceneRoom.ACTORS, .25, 1.72)
	hale = _body("hale", HALE_HOME, SceneRoom.ACTORS, .25, 1.72)
	probe = _body("probe", PROBE_HOME, SceneRoom.PROBE, .116, .26)
	probe.collision_mask = SceneRoom.ENV
	probe.collision_layer = 0
	probe.hide()
	_attach_hale()
	var load_mesh := room.box(Vector3(0,.14,0), Vector3(.235,.225,.31), SceneRoom.GRAPHITE, probe)
	room.box(Vector3(0,.075,0), Vector3(.24,.047,.332), SceneRoom.BRASS, load_mesh.get_parent())
	camera = Camera3D.new()
	camera.keep_aspect = Camera3D.KEEP_WIDTH
	camera.fov = 122.0
	camera.near = .06
	camera.environment = _environment()
	player.add_child(camera)
	camera.position = Vector3(0, EyeHeight, 0)
	camera.make_current()
	room.set_lamp(lamp_on)
	room.set_signal(false, 0)
	journal.hide()
	_refresh_ui()


func _environment() -> Environment:
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color("606b6a")
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color("e5e8e6")
	e.ambient_light_energy = .52
	e.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	e.tonemap_exposure = .92
	e.sdfgi_enabled = true
	e.sdfgi_min_cell_size = .16
	e.ssao_enabled = true
	e.ssao_radius = .75
	return e


func _body(id: String, at: Vector3, layer: int, radius: float, height: float) -> CharacterBody3D:
	var actor := CharacterBody3D.new()
	actor.position = at
	actor.collision_layer = layer
	actor.collision_mask = SceneRoom.ENV | SceneRoom.ACTORS | SceneRoom.GUARD
	actor.set_meta("surface", id)
	var collider := CollisionShape3D.new()
	var capsule := CapsuleShape3D.new()
	capsule.radius = radius
	capsule.height = height
	collider.shape = capsule
	collider.position.y = height * .5
	actor.add_child(collider)
	stage.add_child(actor)
	return actor


func _attach_hale() -> void:
	model_hale = room.kit.node(Vector3.ZERO, hale)
	model_hale.name = "HaleModel"
	_face_hale(LEAD_HOME - HALE_HOME)
	# Use the same R-05 GLB as the MPFB2 native-motion review.
	hale_motion = DetectiveMotion.new()
	hale_motion.attach(model_hale)


func _make_ui() -> void:
	var canvas := CanvasLayer.new()
	canvas.layer = 4
	add_child(canvas)
	var top := VBoxContainer.new()
	top.position = Vector2(28, 23)
	canvas.add_child(top)
	header = _label(top, "03    /    THE OBSERVER AIRLOCK", 23)
	_label(top, "SURVEY SERVICE   ·   LANTERN LINE", 13)
	var center := Control.new()
	canvas.add_child(center)
	center.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	dot = _label(center, "·", 28)
	dot.position = Vector2(-4,-19)
	var footer := PanelContainer.new()
	canvas.add_child(footer)
	footer.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	footer.offset_top = -66
	footer.add_theme_stylebox_override("panel", _panel(Color("242c2be9")))
	var lines := VBoxContainer.new()
	footer.add_child(lines)
	lines.add_theme_constant_override("separation", 2)
	radio = _label(lines, "", 17)
	hint = _label(lines, "", 12)
	journal = PanelContainer.new()
	canvas.add_child(journal)
	journal.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	journal.offset_left = -311
	journal.offset_top = -108
	journal.offset_right = 311
	journal.offset_bottom = 108
	journal.add_theme_stylebox_override("panel", _panel(Color("262e2ef7")))
	notes = _label(journal, "", 18)
	notes.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART


func _label(parent: Node, line: String, size: int) -> Label:
	var label_ := Label.new()
	label_.text = line
	label_.add_theme_font_size_override("font_size", size)
	label_.add_theme_color_override("font_color", Color("f0efea"))
	label_.add_theme_color_override("font_shadow_color", Color("2a302de8"))
	label_.add_theme_constant_override("shadow_offset_x", 1)
	label_.add_theme_constant_override("shadow_offset_y", 1)
	label_.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(label_)
	return label_


func _panel(color: Color) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = color
	style.border_color = Color("778281")
	style.border_width_top = 1
	style.content_margin_left = 28
	style.content_margin_right = 28
	style.content_margin_top = 8
	style.content_margin_bottom = 10
	return style


func _input(event: InputEvent) -> void:
	if event.is_action_pressed(&"air_manual"):
		journal.visible = not journal.visible
		_refresh_ui()
		return
	if event.is_action_pressed(&"air_reset"):
		reset_queued = true
		return
	if audit:
		for action in KEYS.keys() + AUDIT_WAIT.keys():
			if event.is_action_pressed(action): enqueue_audit(action)
		return
	if event is InputEventKey and event.pressed and event.physical_keycode == KEY_ESCAPE:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED and not journal.visible:
		pending_mouse += event.relative
	for action: StringName in EVENTS:
		if event.is_action_pressed(action) and not journal.visible: pending.append(action)


func enqueue_audit(action: StringName) -> bool:
	if not audit or audit_left > 0: return false
	if action in TRAVEL: audit_left = 14
	elif action in TURNS or action in EVENTS: audit_left = 1
	elif AUDIT_WAIT.has(action): audit_left = AUDIT_WAIT[action]
	else: return false
	audit_action = action
	return true


func _physics_process(_delta: float) -> void:
	if reset_queued:
		reset_queued = false
		# MCP observations that follow the reset start at tick zero, with static bodies in space.
		_build()
		return
	if audit and audit_left <= 0: return
	var axes := Vector2.ZERO
	var actions: Array[StringName] = []
	var angles := Vector2.ZERO
	if audit:
		if audit_action in EVENTS: actions.append(audit_action)
		match audit_action:
			&"air_forward": axes.y = 1
			&"air_back": axes.y = -1
			&"air_left": axes.x = -1
			&"air_right": axes.x = 1
			&"air_turn_l": angles.x = 15
			&"air_turn_r": angles.x = -15
			&"air_up": angles.y = 15
			&"air_down": angles.y = -15
		audit_left -= 1
	elif not journal.visible:
		axes = Vector2(Input.get_axis(&"air_left", &"air_right"), Input.get_axis(&"air_back", &"air_forward"))
		angles.x = -pending_mouse.x * .175 - Input.get_axis(&"air_turn_l", &"air_turn_r") * 1.5
		angles.y = -pending_mouse.y * .175 - Input.get_axis(&"air_up", &"air_down") * -1.1
		pending_mouse = Vector2.ZERO
		actions.assign(pending)
		pending.clear()
	_advance(axes.limit_length(), angles, actions)


func _advance(axes: Vector2, angles: Vector2, actions: Array[StringName]) -> void:
	tick += 1
	yaw = wrapf(yaw + angles.x, -180.0, 180.0)
	pitch = clampf(pitch + angles.y, -72.0, 72.0)
	camera.rotation = Vector3(deg_to_rad(pitch), deg_to_rad(yaw), 0)
	var dir := Vector3(axes.x, 0, -axes.y).rotated(Vector3.UP, deg_to_rad(yaw))
	_motor(player, dir * (WALK_SPEED * STEP), "lead")
	if player.position.y < -.66:
		return_to_bank(player, LEAD_HOME, "lead")
		_call("Lead: The catch bed returned me to the near bank.")
	for action in actions:
		if action == &"air_lamp": _switch()
	var eyes := sample(player, yaw, pitch)
	sight = eyes.observable > 0
	_update_span(eyes)
	room.set_signal(lift_steps == RISE_TICKS and (sight or dog_seated), grace_remaining())
	for action in actions:
		match action:
			&"air_trial": _launch_trial()
			&"air_request": _order()
			&"air_share": _share()
	_move_probe()
	_move_hale()
	if dog_seated: door_steps = mini(44, door_steps + 1)
	var open_guard := lift_steps >= RISE_TICKS and (sight or lose_at >= 0 or dog_seated)
	var dog_turn := smoothstep(.30, .85, float(dog_stroke) / DOG_TICKS)
	room.render_state(_lift(), open_guard, dog_turn, door_steps / 44.0,
		not rules.recent("CAUGHT",tick).is_empty(), not rules.recent("SUPPORTED",tick).is_empty())
	if player.position.z < SceneRoom.EXIT_Z - .60 and not cleared \
			and not Rules.forbidden(Rules.LEAD_RULE, Rules.LEAD_ORDER, _fields()):
		cleared = true
		_event("EXIT_CLEARED")
		_call("Airlock cleared. Surveyor's dog seated.")
	frame_flags = {"lead": eyes, "hale": sample(hale, _hale_yaw(), 0.0)}
	_refresh_ui()


func _fields() -> Dictionary:
	return {"span":{"dog_seated":int(dog_seated)},"witness":{"live":int(sight)}}


func _lift() -> float:
	return SceneRoom.DECK_LOW * (1.0 - float(lift_steps) / RISE_TICKS)


func grace_remaining() -> int:
	return 0 if lose_at < 0 else maxi(0, GRACE_TICKS - (tick - lose_at))


func _update_span(eyes: Dictionary) -> void:
	if collapsed_at >= 0:
		lift_steps = maxi(0, lift_steps - 1)
		if lift_steps == 0: collapsed_at = -1
		return
	if dog_seated or sight:
		if lose_at >= 0:
			_event("WITNESS_RESTORED", {"warning_age":tick-lose_at})
		lose_at = -1
		lift_steps = mini(lift_steps + 1, RISE_TICKS)
		return
	if lift_steps == RISE_TICKS and collapsed_at < 0:
		if lose_at < 0:
			lose_at = tick
			lead_warn_at = -1
			hale_warn_at = -1
			lead_visible_ticks = 0
			hale_visible_ticks = 0
			_event("SIGHT_LOST")
		if tick - lose_at < GRACE_TICKS:
			if eyes.caution_hits > 0:
				lead_visible_ticks += 1
				if lead_warn_at < 0:
					lead_warn_at = tick
					_event("WARNING_OBSERVABLE", {"observer":"lead"})
			if sample(hale, _hale_yaw(), 0.0).caution_hits > 0:
				hale_visible_ticks += 1
				if hale_warn_at < 0:
					hale_warn_at = tick
					_event("WARNING_OBSERVABLE", {"observer":"hale"})
			return
		collapsed_at = tick
		_event("DECK_RELEASED", {"lead_observed_ticks":lead_visible_ticks,
			"hale_observed_ticks":hale_visible_ticks})
		lose_at = -1
	lift_steps = maxi(0, lift_steps - 1)
	if lift_steps == 0: collapsed_at = -1


func _motor(actor: CharacterBody3D, horizontal: Vector3, id: String) -> void:
	if horizontal.length_squared() > .0000001:
		var hit := actor.move_and_collide(horizontal, false, .001)
		if hit != null:
			var flat := hit.get_normal() * Vector3(1,0,1)
			if flat.length_squared() > .15:
				var slide := hit.get_remainder().slide(flat.normalized())
				actor.move_and_collide(slide, false, .001)
	fall[id] = maxf(-13, fall[id] - 9.8 * STEP)
	var floor_hit := actor.move_and_collide(Vector3(0, fall[id] * STEP, 0), false, .001)
	if floor_hit != null and floor_hit.get_normal().y > .62: fall[id] = 0.0


func return_to_bank(actor: CharacterBody3D, place: Vector3, id: String) -> void:
	actor.position = place
	actor.reset_physics_interpolation()
	fall[id] = 0.0
	_event("CATCH_RETURN", {"actor":id})


func _face_hale(dir: Vector3) -> void:
	# The R-05 model faces local +Z; Godot camera and sight rays face local -Z.
	model_hale.rotation.y = atan2(dir.x, dir.z)


func _hale_yaw() -> float:
	return wrapf(rad_to_deg(model_hale.rotation.y) + 180.0, -180.0, 180.0)


func _move_hale() -> void:
	var d := Vector3.ZERO
	if duty == "APPROACH":
		if absf(hale.position.x) > .022:
			d = Vector3.LEFT
		else:
			duty = "CROSSING"
			_face_hale(Vector3.FORWARD)
	if duty in ["CROSSING", "HOLDING"]:
		var lane := sample(hale, 0.0, 0.0)
		var safe_signal: bool = lane.far_signal == "PROCEED"
		if hale.position.z > -1.64 and not safe_signal:
			if duty != "HOLDING":
				_call("Hale: Lost the witness. Holding.")
				duty = "HOLDING"
		elif safe_signal or hale.position.z <= -1.64:
			duty = "CROSSING"
			d = Vector3(0,0,-1)
		if hale.position.z <= -1.86:
			duty = "AT DOG"
	if duty == "AT DOG":
		var goal := SceneRoom.FAR_DOG + Vector3(0,0,.64)
		var offset := (goal - hale.position) * Vector3(1,0,1)
		if offset.length() < .104:
			duty = "WORKING DOG"
			dog_stroke = 0
			_call("Hale: Engaging the far dog.")
			_face_hale(Vector3.FORWARD)
		else: d = offset.normalized()
	if duty == "WORKING DOG":
		dog_stroke += 1
		if dog_stroke == DOG_TICKS:
			dog_seated = true
			lose_at = -1
			lift_steps = RISE_TICKS
			duty = "DOG SEATED"
			_event("DOG_SEATED", {"actor":"hale"})
			_call("Hale: Dog seated. Clear the room.")
	if duty == "RETREAT":
		var offset := (HALE_HOME - hale.position) * Vector3(1,0,1)
		if offset.length() < .055: duty = "ON NEAR BANK"
		else: d = offset.normalized()
	if d != Vector3.ZERO:
		_face_hale(d)
	var from := hale.position
	_motor(hale, d * HALE_SPEED * STEP, "hale")
	if hale.position.y < -.65:
		return_to_bank(hale, HALE_HOME, "hale")
		duty = "ON NEAR BANK"
		rules.revision.clear()
		_call("Hale: The lower catch took me. File the test again before departure.")
	elif duty == "HOLDING" and lose_at < 0 and lift_steps < RISE_TICKS and hale.position.z > 1.38:
		duty = "RETREAT"
		rules.revision.clear()
		_call("Hale: Withdrawing to the near bank.")
	var traveled := (hale.position - from) * Vector3(1,0,1)
	var distance := traveled.length()
	hale_motion.advance(distance if distance < .10 else 0.0, duty == "WORKING DOG",
		float(dog_stroke) / DOG_TICKS, STEP)


func _at_bench() -> bool:
	return (player.position - SceneRoom.BENCH).length() < .94


func _switch() -> void:
	if not _at_bench():
		_call("The lamp breaker is on the witness bench.")
		return
	lamp_on = not lamp_on
	room.set_lamp(lamp_on)
	_event("BREAKER", {"on":lamp_on})


func _launch_trial() -> void:
	if not _at_bench():
		_call("The proof load is operated at the witness bench.")
		return
	if not trial.is_empty() or dog_seated or duty != "ON NEAR BANK": return
	if lift_steps != 0 and not (lift_steps == RISE_TICKS and sight):
		_call("Wait for the deck to settle before releasing the load.")
		return
	probe.position = PROBE_HOME
	probe.collision_layer = SceneRoom.PROBE
	probe.show()
	fall.probe = 0.0
	trial = {"start":tick, "positive":sight and lift_steps == RISE_TICKS, "consistent":true}
	_event("LOAD_RELEASED", {"witness":sight})
	_call("Proof load away.")


func _move_probe() -> void:
	if trial.is_empty(): return
	if not _at_bench() or bool(trial.positive) != sight:
		trial.consistent = false
	_motor(probe, Vector3(0,0,-3.55 * STEP), "probe")
	var tray := probe.position.z < -1.62 and probe.position.y > -.035
	var catch_ := probe.position.y < -.36
	if not tray and not catch_ and tick - trial.start < 100: return
	if trial.consistent and (tray and trial.positive or catch_ and not trial.positive):
		rules.add_record(tray, tick, 0, &"proof_load_01", trial.start)
		_event("PROOF_RECORDED", rules.records.back())
		_call("Far tray registered the proof load." if tray else "Lower catch registered the proof load.")
	else:
		_event("PROOF_DISCARDED")
		_call("Discarded: the witness condition changed during the test.")
	if tray or catch_:
		# Leave the load where it actually landed, until the next release.
		probe.collision_layer = 0
	else: probe.hide()
	trial = {}


func _share() -> void:
	if not _at_bench():
		_call("Take the witness position to file a comparison.")
		return
	var caught := rules.recent("CAUGHT",tick)
	var carried := rules.recent("SUPPORTED",tick)
	var refs := [caught.get("id",0), carried.get("id",0)]
	if rules.persuade(Rules.RULE_ID, refs, tick, sight and lift_steps == RISE_TICKS):
		_event("EVIDENCE_ACCEPTED", rules.revision)
		_call("Hale: Both trials logged. I'll take this span under your witness.")
	else:
		_event("EVIDENCE_REJECTED")
		_call(rules.rejection)


func _order() -> void:
	if dog_seated or duty != "ON NEAR BANK" or not trial.is_empty(): return
	if not rules.allows_departure(tick, _fields()):
		_event("ORDER_REFUSED", {"rule":Rules.RULE_ID})
		_call("Hale: My orders forbid taking an unbraced span. Check the proof load.")
		return
	if not sight or lift_steps < RISE_TICKS:
		_event("ORDER_BLOCKED", {"reason":"witness_lift_interlock"})
		_call("Hale: Awaiting the deck.")
		return
	duty = "APPROACH"
	_event("ORDER_ACCEPTED", {"evidence":rules.revision.evidence.duplicate()})
	_call("Hale: Crossing to the dog.")


func _ray(from: Vector3, toward: Vector3, mask: int, excludes: Array[RID]) -> Dictionary:
	var query := PhysicsRayQueryParameters3D.create(from, toward, mask, excludes)
	return get_world_3d().direct_space_state.intersect_ray(query)


func sample(body: CharacterBody3D, horizontal: float, vertical: float) -> Dictionary:
	# The same world query serves human witness and companion warning perception.
	var eye := body.global_position + Vector3.UP * EyeHeight
	var excludes: Array[RID] = [body.get_rid()]
	var stops: Array[String] = []
	var hits := 0
	var caution_hits := 0
	var optical_faces := 0
	var far_signal := "UNOBSERVABLE"
	var lit_tile := _tile_illuminated()
	var basis := Basis.from_euler(Vector3(deg_to_rad(vertical), deg_to_rad(horizontal), 0))
	for column in range(-4,5):
		for row in range(-1,2):
			var beam := Vector3.FORWARD.rotated(Vector3.RIGHT, deg_to_rad(row * 15.0))
			beam = basis * beam.rotated(Vector3.UP, deg_to_rad(column * 15.0))
			var hit := _ray(eye, eye + beam * 10.0,
				SceneRoom.ENV | SceneRoom.ACTORS | SceneRoom.GUARD | SceneRoom.SENSORS, excludes)
			var mark := "UNOBSERVABLE"
			if not hit.is_empty():
				var first: Object = hit.collider
				var surface := str(first.get_meta("surface", "other"))
				mark = surface
				if first == room.target:
					optical_faces += 1
					if lit_tile and hit.normal.z > .9:
						hits += 1
					else: mark = "UNOBSERVABLE"
				if first == room.warning_near or first == room.warning_far: caution_hits += 1
				if first == room.warning_far: far_signal = room.relay
			stops.append(mark)
	return {"first_hits":stops, "observable":hits, "witness_faces":optical_faces, "caution_hits":caution_hits, "far_signal":far_signal}


func _tile_illuminated() -> bool:
	if not room.receiver_lamp.visible: return false
	var origin := room.receiver_lamp.global_position
	var finish := room.target.global_position
	if origin.distance_to(finish) > room.receiver_lamp.omni_range: return false
	var exclude: Array[RID] = []
	var hit := _ray(origin, finish, SceneRoom.ENV, exclude)
	return not hit.is_empty() and hit.collider == room.target


func _event(kind: String, extra: Dictionary = {}) -> void:
	var event := {"tick":tick,"kind":kind}
	event.merge(extra)
	event_trace.append(event)


func _call(line: String) -> void:
	message = line
	messaged = tick


func _refresh_ui() -> void:
	if cleared:
		radio.text = "AIRLOCK CLEARED   /   DOG SEATED"
	elif tick - messaged <= 230 and not message.is_empty():
		radio.text = message
	else:
		radio.text = "SURVEYOR HALE   /   " + duty
	hint.text = "WASD  Walk  ·  Mouse / Arrows  Look  ·  C  Ask Hale to cross  ·  J  Field orders  ·  R  Restart"
	if _at_bench():
		hint.text = "E  Release proof load  ·  F  Lamp breaker  ·  Q  File comparison  ·  C  Ask Hale to cross  ·  J  Field orders"
	if guided: hint.text += "  ·  [ / ]  Gallery"
	notes.text = "FIELD ORDERS   /   J TO CLOSE\n\n%s\n%s\n\nProof slips   /   %s" % [
		Rules.HALE_RULE.label, Rules.LEAD_RULE.label,
		" · ".join(rules.records.map(func(r: Dictionary) -> String: return "#%d %s" % [r.id,r.kind])) if not rules.records.is_empty() else "No trials filed"]


func mcp_observe() -> Dictionary:
	var vector := func(p: Vector3) -> Array[int]: return [roundi(p.x*1000),roundi(p.y*1000),roundi(p.z*1000)]
	return {"plate":3, "mode":"airlock", "tick":tick, "audit_left":audit_left, "view":"eye",
		"lead_mm":vector.call(player.position), "hale_mm":vector.call(hale.position), "probe_mm":vector.call(probe.position),
		"yaw":yaw, "pitch":pitch, "lamp":lamp_on, "sight":sight, "bridge":lift_steps,
		"mesh_top_mm":roundi((room.bridge.position.y + SceneRoom.SPAN_SIZE.y*.5)*1000),
		"span_collider_mm":vector.call(room.bridge.get_child(0).shape.size),
		"span_mesh_mm":vector.call(room.bridge.get_child(1).mesh.size),
		"collider_top_mm":roundi((room.bridge.get_child(0).global_position.y + room.bridge.get_child(0).shape.size.y * .5) * 1000),
		"stop_bar_y_mm":roundi(room.guard.position.y*1000), "loss_tick":lose_at, "remaining":grace_remaining(),
		"warning_samples":[lead_visible_ticks,hale_visible_ticks],
		"hale_model":hale_motion.actor.scene_file_path,
		"hale_clip":String(hale_motion.clip), "dog_stroke":dog_stroke,
		"duty":duty, "dog":dog_seated, "door":door_steps, "cleared":cleared, "trial":trial.duplicate(),
		"perception":frame_flags.duplicate(true), "records":rules.records.duplicate(true),
		"revision":rules.revision.duplicate(true), "events":event_trace.duplicate(true)}
