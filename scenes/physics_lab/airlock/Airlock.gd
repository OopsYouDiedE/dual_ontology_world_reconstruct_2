extends Node3D
## L03: two visible bridge surfaces, one permanently solid landing, and two observers.
const Room = preload("res://scenes/physics_lab/airlock/Room.gd")
const Rules = preload("res://scenes/physics_lab/airlock/Rules.gd")
const DetectiveMotion = preload("res://scenes/physics_lab/airlock/DetectiveMotion.gd")
const STEP := 1.0 / 60.0
const GRACE := 60
const STAND := 1.74
const CROUCH := 1.04
const EYE := 1.60
const LOW_EYE := .92
const SPEED := 3.06
const LOW_SPEED := 2.25
const KEYS := {&"air_forward":KEY_W, &"air_back":KEY_S, &"air_left":KEY_A, &"air_right":KEY_D,
	&"air_turn_l":KEY_LEFT, &"air_turn_r":KEY_RIGHT, &"air_up":KEY_UP, &"air_down":KEY_DOWN,
	&"air_talk":KEY_E, &"air_crouch":KEY_CTRL, &"air_reset":KEY_R, &"air_film":KEY_NONE}
var guided := false
var stage: Node3D
var room: Room
var rule: Rules
var lead: CharacterBody3D
var hale: CharacterBody3D
var model: Node3D
var motion: DetectiveMotion
var camera: Camera3D
var yaw := 0.0
var pitch := .012
var hale_forward := Vector3.FORWARD
var raw_look := Vector2.ZERO
var queued_talk := false
var queued_reset := false
var crouched := false
var hale_low := false
var role := "NEAR"
var deck := [false,false]
var last_seen := [-100,-100]
var heard_grace := [false,false]
var witness := [[false,false],[false,false]]
var tick := 0
var held_far := 0
var gate_ticks := 0
var cleared := false
var refuge := Room.LEAD_HOME
var clip: RefCounted
var film_enabled := false
var film_failed := ""
var auto_input := false
var receipts: Array[Dictionary] = []
var subtitle: Label
var hud: Label
var crosshair: Label
var until := 0
var cues: Dictionary = {}


func _ready() -> void:
	for action: StringName in KEYS:
		if InputMap.has_action(action): continue
		InputMap.add_action(action)
		if KEYS[action] == KEY_NONE: continue
		var key := InputEventKey.new()
		key.physical_keycode = KEYS[action]
		InputMap.action_add_event(action,key)
	var args := OS.get_cmdline_user_args()
	film_enabled = args.has("--airlock-film") or args.has("--airlock-film-test") or args.has("--airlock-audit")
	get_viewport().msaa_3d = Viewport.MSAA_4X
	_make_hud()
	_make_cues()
	_reset()
	if args.has("--airlock-film") or args.has("--airlock-film-test"): _start_film()
	if DisplayServer.get_name() != "headless" and not film_enabled: Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _exit_tree() -> void:
	if not film_enabled: Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func _reset() -> void:
	if is_instance_valid(stage):
		remove_child(stage)
		stage.queue_free()
	stage = Node3D.new()
	add_child(stage)
	room = Room.new()
	room.make(stage)
	rule = Rules.new()
	lead = _body("lead",Room.LEAD_HOME)
	hale = _body("hale",Room.HALE_HOME)
	model = Node3D.new()
	hale.add_child(model)
	motion = DetectiveMotion.new()
	motion.attach(model)
	hale_forward = (Room.LEAD_HOME-Room.HALE_HOME).normalized()
	_face_model(hale_forward)
	camera = Camera3D.new()
	camera.fov = 83.0
	camera.near = .048
	camera.environment = _environment()
	lead.add_child(camera)
	camera.position.y = EYE
	camera.make_current()
	yaw = 0.0
	pitch = .012
	_camera_rotation()
	crouched = false
	hale_low = false
	role = "NEAR"
	deck = [false,false]
	last_seen = [-100,-100]
	heard_grace = [false,false]
	witness = [[false,false],[false,false]]
	tick = 0
	held_far = 0
	gate_ticks = 0
	cleared = false
	refuge = Room.LEAD_HOME
	until = 0
	raw_look = Vector2.ZERO
	queued_talk = false
	receipts.clear()
	film_failed = ""
	subtitle.text = ""


func _environment() -> Environment:
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color("24262c")
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color("c6c9d0")
	e.ambient_light_energy = .43
	e.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	e.ssao_enabled = true
	e.ssao_radius = .73
	e.sdfgi_enabled = true
	e.sdfgi_min_cell_size = .16
	e.fog_enabled = true
	e.fog_light_color = Color("3e444d")
	e.fog_light_energy = .38
	e.fog_density = .016
	return e


func _body(id: String, at: Vector3) -> CharacterBody3D:
	var b := CharacterBody3D.new()
	b.name = id
	b.set_meta("surface", id)
	b.collision_layer = Room.ACTOR
	b.collision_mask = Room.WORLD | Room.DECK | Room.ACTOR
	b.floor_snap_length = .06
	b.safe_margin = .001
	b.position = at
	var c := CollisionShape3D.new()
	var s := CapsuleShape3D.new()
	s.radius = .22
	s.height = STAND
	c.shape = s
	c.position.y = STAND*.5
	b.add_child(c)
	stage.add_child(b)
	return b


func _stance(body: CharacterBody3D, low: bool, was_low: bool) -> bool:
	if low == was_low: return low
	var c := body.get_child(0) as CollisionShape3D
	if not low:
		var check := PhysicsShapeQueryParameters3D.new()
		var shape := CapsuleShape3D.new()
		shape.radius = .216
		shape.height = STAND - .046
		check.shape = shape
		check.transform.origin = body.global_position + Vector3.UP * (STAND*.5 + .012)
		check.collision_mask = Room.WORLD
		if not get_world_3d().direct_space_state.intersect_shape(check, 1).is_empty(): return true
	var height := CROUCH if low else STAND
	c.shape.height = height
	c.position.y = height*.5
	return low


func _unhandled_input(e: InputEvent) -> void:
	if e is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED and not auto_input:
		raw_look += e.relative
	if e.is_action_pressed(&"air_talk"): queued_talk = true
	if e.is_action_pressed(&"air_reset"): queued_reset = true
	if e.is_action_pressed(&"air_film") and film_enabled and not is_instance_valid(clip): _start_film()
	if e is InputEventKey and e.pressed and e.keycode == KEY_ESCAPE and not auto_input:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED else Input.MOUSE_MODE_CAPTURED


func _start_film() -> void:
	# Loaded only by the capture / regression harness; player's simulation has no route dependency.
	var script := load("res://scenes/physics_lab/airlock/Walkthrough.gd") as Script
	clip = script.new()
	auto_input = true


func _physics_process(_dt: float) -> void:
	if queued_reset:
		queued_reset = false
		clip = null
		auto_input = false
		_reset()
		return
	if film_enabled and not auto_input and OS.get_cmdline_user_args().has("--airlock-audit"): return
	var moves := Input.get_vector(&"air_left",&"air_right",&"air_forward",&"air_back")
	var angles := Vector2(Input.get_axis(&"air_turn_r",&"air_turn_l"),Input.get_axis(&"air_down",&"air_up")) * STEP * 1.65
	angles -= raw_look * .00265
	raw_look = Vector2.ZERO
	var wants_low := Input.is_action_pressed(&"air_crouch")
	var talk := queued_talk
	queued_talk = false
	if auto_input:
		var cmd: Dictionary = clip.command(self)
		moves = cmd.get("walk",Vector2.ZERO)
		angles = cmd.get("look",Vector2.ZERO)
		wants_low = cmd.get("low",false)
		talk = cmd.get("talk",false)
	_simulate(moves, angles, wants_low, talk)


func _camera_rotation() -> void:
	camera.rotation = Vector3(pitch,yaw,0)


func _simulate(moves: Vector2, angles: Vector2, wants_low: bool, talk: bool) -> void:
	tick += 1
	yaw = wrapf(yaw+angles.x,-PI,PI)
	pitch = clampf(pitch+angles.y,-1.44,1.44)
	_camera_rotation()
	crouched = _stance(lead,wants_low,crouched)
	camera.position.y = move_toward(camera.position.y, LOW_EYE if crouched else EYE, .064)
	var lead_front := -camera.global_transform.basis.z
	var lead_eyes := camera.global_position
	witness[0] = _observe(lead_eyes,lead_front,lead)
	witness[1] = [false,false] if rule.forbidden("observe_lit_span",{"span_lit":true}) else _observe(_hale_eye(),hale_forward,hale)
	for i in range(2):
		if witness[0][i] or witness[1][i]: last_seen[i] = tick
		var live: bool = tick - last_seen[i] < GRACE
		if deck[i] != live:
			_event("FORM" if live else "RELEASE",{"span":i})
			_sound("form" if live else "drop",room.spans[i].focus)
		deck[i] = live
		var age: int = 0 if not live else tick-last_seen[i]
		if age >= 2 and not heard_grace[i]:
			heard_grace[i] = true
			_sound("grace",room.spans[i].focus)
		elif age == 0:
			heard_grace[i] = false
		room.paint(i,live,age)
	_drive(lead,Vector3(moves.x,0,moves.y).rotated(Vector3.UP,yaw), LOW_SPEED if crouched else SPEED)
	var surface := _floor(lead)
	match surface:
		"near": refuge = Room.LEAD_HOME
		"island": refuge = Vector3(-.18,0,-3.55)
		"far": refuge = Room.FAR_WATCH
	if role == "NEAR": _turn_hale(_lead_target())
	if rule.record(surface == "floor_0" and lead.is_on_floor(), witness[0][0], _hale_sees_lead(), surface == "near"):
		_event("COUNTEREXAMPLE")
		_say("Hale: I saw you step into the light. It let you come back.", 288)
	if talk and _can_talk() and rule.speak(true):
		role = "READY"
		_event("RULE_REVISED")
		_say("Hale: Then keep looking. I'll get to the other side of that screen.", 290)
		_sound("reply",hale.position + Vector3.UP)
	_update_hale()
	if lead.position.y < -2.46:
		_return(lead,refuge)
		rule.invalidate_attempt()
	if hale.position.y < -2.46:
		_return(hale, Room.ISLAND_WATCH if role in ["B_LINE","CROSS_B"] else Room.HALE_HOME)
		role = "WATCH_B" if role in ["B_LINE","CROSS_B"] else "READY"
	if role == "FAR":
		gate_ticks = mini(gate_ticks+1,48)
		room.lift_gate(smoothstep(0.0,1.0,float(gate_ticks)/48.0))
		if not cleared and lead.position.x > 7.76 and absf(lead.position.z+3.95) < .66:
			cleared = true
			_sound("reply",lead.position)
			_event("EXIT_CLEARED")
	_refresh()


func _return(who: CharacterBody3D, place: Vector3) -> void:
	who.position = place + Vector3.UP*.021
	who.velocity = Vector3.ZERO
	who.reset_physics_interpolation()
	_event("CATCH_RETURN",{"actor":str(who.name)})
	_say("The lower net returned you to solid ground." if who == lead else "Hale: I'm on solid ground. Watch the span again.",150)


func _drive(who: CharacterBody3D, direction: Vector3, speed: float) -> void:
	who.velocity.x = direction.x * speed
	who.velocity.z = direction.z * speed
	who.velocity.y = -.10 if who.is_on_floor() else maxf(-15.0,who.velocity.y - 9.8*STEP)
	who.move_and_slide()


func _floor(who: CharacterBody3D) -> String:
	var p := who.global_position
	var hit := _ray(p+Vector3.UP*.09,p-Vector3.UP*.10,Room.WORLD|Room.DECK,[])
	return str(hit.collider.get_meta("surface","")) if not hit.is_empty() else ""


func _ray(from: Vector3, to: Vector3, mask: int, omit: Array[RID]) -> Dictionary:
	return get_world_3d().direct_space_state.intersect_ray(PhysicsRayQueryParameters3D.create(from,to,mask,omit))


func _observe(eye: Vector3, forward: Vector3, who: CharacterBody3D) -> Array:
	var found := [false,false]
	var az := atan2(-forward.x,-forward.z)
	var el := asin(clampf(forward.y,-1.0,1.0))
	for column in [0,-1,1,-2,2,-3,3,-4,4]:
		for row in [0,-1,1]:
			var direction := Vector3.FORWARD.rotated(Vector3.RIGHT,el+deg_to_rad(row*13.0)).rotated(Vector3.UP,az+deg_to_rad(column*10.0))
			var hit := _ray(eye,eye+direction*13.0,Room.WORLD|Room.ACTOR|Room.FACET,[who.get_rid()])
			if hit.is_empty(): continue
			for i in range(2):
				var settings := room.spans[i]
				if not found[i] and hit.collider == settings.optic and hit.normal.dot(settings.normal) > .95:
					found[i] = _lit(settings.lamp,hit.position)
			if found == [true,true]: return found
	return found


func _lit(lamp: SpotLight3D, point: Vector3) -> bool:
	var d := point-lamp.global_position
	if not lamp.visible or d.length() > lamp.spot_range: return false
	if d.normalized().dot(-lamp.global_transform.basis.z) < cos(deg_to_rad(lamp.spot_angle)): return false
	return _ray(lamp.global_position,point,Room.WORLD,[]).is_empty()


func _lead_target() -> Vector3:
	return lead.global_position + Vector3.UP*(.72 if crouched else 1.14)


func _hale_eye() -> Vector3:
	return hale.global_position + Vector3.UP*(LOW_EYE if hale_low else EYE)


func _hale_sees_lead() -> bool:
	var target := _lead_target()
	var direction := (target-_hale_eye()).normalized()
	if hale_forward.dot(direction) < .65: return false
	var hit := _ray(_hale_eye(),target,Room.WORLD|Room.ACTOR,[hale.get_rid()])
	return not hit.is_empty() and hit.collider == lead


func _can_talk() -> bool:
	if role != "NEAR" or not rule.counterexample or not _hale_sees_lead() or lead.position.distance_to(hale.position) > 1.70: return false
	return (-camera.global_transform.basis.z).dot((hale.global_position+Vector3.UP*1.39-camera.global_position).normalized()) > .72


func _turn_hale(target: Vector3) -> void:
	var offset := target-_hale_eye()
	if offset.length_squared() > .004: hale_forward = offset.normalized()
	_face_model(hale_forward)


func _face_model(forward: Vector3) -> void:
	model.rotation.y = atan2(forward.x,forward.z)


func _update_hale() -> void:
	var target := hale.position
	var speed := 2.65
	var aim := Vector3.ZERO
	match role:
		"READY":
			if witness[0][0] and _floor(lead) == "near":
				role = "A_LINE"
				_event("FIRST_HANDOFF")
		"A_LINE":
			target = Vector3(-.25,0,.53)
			if _flat(hale.position,target) < .08: role = "CROSS_A"
		"CROSS_A":
			target = Vector3(-.25,0,-3.27)
			if not deck[0]: target = hale.position
			if _flat(hale.position,target) < .08 and hale.position.z < -3.13: role = "ISLAND"
		"ISLAND":
			target = Room.ISLAND_WATCH
			if _flat(hale.position,target) < .077:
				role = "WATCH_B"
				_event("HALE_AT_LANDING")
				_say("Hale: I can see the lower edge from here. Go.",205)
		"WATCH_B":
			aim = Room.B_AIM
			held_far = held_far+1 if witness[0][1] and _floor(lead) == "far" else 0
			if held_far >= 14:
				role = "B_LINE"
				_event("FAR_HANDOFF")
				_say("Hale: You've got it. Keep your eyes there.",172)
		"B_LINE":
			target = Vector3(.91,0,Room.B_LANE)
			if _flat(hale.position,target) < .08: role = "CROSS_B"
		"CROSS_B":
			target = Vector3(6.62,0,Room.B_LANE)
			if not deck[1] and hale.position.x < Room.B_END: target = hale.position
			if _flat(hale.position,target) < .08 and hale.position.x > 6.45:
				role = "FAR"
				_event("HALE_ACROSS")
				_say("Hale: Both across.",180)
				_sound("reply", Vector3(7.5,1.1,-3.95))
	var wants_low := role in ["B_LINE","CROSS_B"] and hale.position.x < 1.81
	hale_low = _stance(hale,wants_low,hale_low)
	if hale_low: speed = 2.26
	var movement := (target - hale.position) * Vector3(1,0,1)
	var dir := movement.normalized() if movement.length() > .036 else Vector3.ZERO
	if aim != Vector3.ZERO: _turn_hale(aim)
	elif dir != Vector3.ZERO:
		_turn_hale(_hale_eye()+dir*2.2+Vector3.DOWN*.62)
	var before := hale.position
	_drive(hale,dir,speed)
	motion.advance((hale.position-before).slide(Vector3.UP).length(),false,0.0,STEP,hale_low,asin(clampf(hale_forward.y,-1.0,1.0)))


func _flat(a: Vector3, b: Vector3) -> float:
	return (a-b).slide(Vector3.UP).length()


func _event(kind: String, data: Dictionary = {}) -> void:
	var e := {"tick":tick,"kind":kind}
	e.merge(data)
	receipts.append(e)


func _make_hud() -> void:
	var layer := CanvasLayer.new()
	layer.layer = 6
	add_child(layer)
	var panel := Control.new()
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(panel)
	panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var label := Label.new()
	label.text = "03   /   THE OBSERVER AIRLOCK"
	label.position = Vector2(26,22)
	label.add_theme_font_size_override("font_size",18)
	label.modulate = Color("e3e3dc")
	panel.add_child(label)
	crosshair = Label.new()
	crosshair.text = "·"
	crosshair.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	crosshair.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	crosshair.add_theme_font_size_override("font_size",26)
	panel.add_child(crosshair)
	crosshair.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	crosshair.offset_left = -12
	crosshair.offset_right = 12
	crosshair.offset_top = -16
	crosshair.offset_bottom = 16
	subtitle = Label.new()
	subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	subtitle.add_theme_font_size_override("font_size",20)
	subtitle.add_theme_constant_override("outline_size",6)
	panel.add_child(subtitle)
	subtitle.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	subtitle.offset_top = -91
	subtitle.offset_bottom = -57
	hud = Label.new()
	hud.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hud.add_theme_font_size_override("font_size",15)
	hud.add_theme_constant_override("outline_size",5)
	panel.add_child(hud)
	hud.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	hud.offset_top = -42
	hud.offset_bottom = -12


func _say(text: String, length: int) -> void:
	subtitle.text = text
	until = tick+length


func _refresh() -> void:
	if tick == 134 and role == "NEAR" and not rule.counterexample:
		_say("Hale: Don't look into that light. It takes anyone who does.",210)
	if tick > until: subtitle.text = ""
	if cleared:
		hud.text = "AIRLOCK CLEARED"
	elif _can_talk():
		hud.text = "E   /   Talk to Hale"
	else:
		hud.text = ("WASD  Move   ·   Mouse  Look   ·   Ctrl  Crouch" if tick < 193 else ("Ctrl  Crouch" if lead.position.z < -3.20 and lead.position.x < 1.25 else ""))
		if guided and tick < 193: hud.text += "   ·   [ / ]  Gallery"
	crosshair.modulate.a = .66 if witness[0].has(true) else .36


func _make_cues() -> void:
	for cue: String in ["form","grace","drop","reply"]:
		var wav := AudioStreamWAV.new()
		wav.format = AudioStreamWAV.FORMAT_16_BITS
		wav.mix_rate = 24000
		var seconds := .59 if cue in ["form","grace"] else .41
		var count := int(wav.mix_rate * seconds)
		var pcm := PackedByteArray()
		pcm.resize(count*2)
		for i in range(count):
			var t := float(i)/wav.mix_rate
			var env := minf(1.0,t*45.0)*pow(1.0-t/seconds,1.6)
			var freq := (68.0+89.0*t) if cue=="form" else ((173.0-128.0*t) if cue=="drop" else (202.0 if cue=="grace" else 109.0))
			var wave := sin(TAU*freq*t)*.72 + sin(TAU*(freq*2.04)*t)*.28
			if cue=="grace": wave *= .25+.75*absf(sin(t*32.0))
			pcm.encode_s16(i*2,int(wave*env*9900.0))
		wav.data = pcm
		cues[cue] = wav


func _sound(cue: String, pos: Vector3) -> void:
	var audio := AudioStreamPlayer3D.new()
	stage.add_child(audio)
	audio.position = pos
	audio.stream = cues[cue]
	audio.unit_size = 4.0
	audio.max_distance = 22.0
	audio.finished.connect(audio.queue_free)
	audio.play()


func mcp_observe() -> Dictionary:
	return {"plate":3,"mode":"airlock","view":"eye","tick":tick,"lead":lead.position,"hale":hale.position,
		"lead_floor":_floor(lead),"hale_floor":_floor(hale),"witness":witness.duplicate(true),"solid":deck.duplicate(),
		"collision":[room.spans[0].solid.collision_layer != 0,room.spans[1].solid.collision_layer != 0],
		"bridge_mesh":[room.spans[0].surface.visible,room.spans[1].surface.visible],
		"crouched":crouched,"role":role,"counterexample":rule.counterexample,"revision":rule.revised,
		"cleared":cleared,"events":receipts.duplicate(true),"film":clip.get("phase") if clip != null else "",
		"phase_age":tick-int(clip.get("since")) if clip != null else 0,
		"film_error":film_failed,"hale_model":motion.actor.scene_file_path}
