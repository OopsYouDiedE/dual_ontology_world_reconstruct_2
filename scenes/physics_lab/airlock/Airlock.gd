extends Node3D
## L03: two visible bridge surfaces, one permanently solid landing, and two observers.
const Room = preload("res://scenes/physics_lab/airlock/Room.gd")
const Rules = preload("res://scenes/physics_lab/airlock/Rules.gd")
const DetectiveMotion = preload("res://scenes/physics_lab/airlock/DetectiveMotion.gd")
const STEP := 1.0 / 60.0
const Span = preload("res://scenes/physics_lab/airlock/Span.gd")
const STAND := 1.74
const CROUCH := 1.04
const EYE := 1.60
const LOW_EYE := .92
const SPEED := 3.06
const LOW_SPEED := 2.25
const KEY_LOOK_SPEED := 3.10
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
var cue_head: Node3D
var cue_boot: Node3D
var hale_optics: Dictionary = {}
var head_memory: Dictionary = {}
var boot_memory: Dictionary = {}
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
var spans := [Span.new(),Span.new()]
var red_signal := [false,false]
var red_voices: Array[AudioStreamPlayer3D] = [null,null]
var trial_at := 0
var offer := 0
var offer_open := false
var book_open := false
var book: PanelContainer
var book_text: Label
var attempted_tread := false
var stalemate := false
var local_hale: Dictionary = {}
var last_policy := ""
var searched := false
var red_after_panic := false
var exchange := false
var failed := ""
var witness := [[false,false],[false,false]]
var tick := 0
var gate_ticks := 0
var cleared := false
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
	camera.fov = 89.0
	camera.near = .048
	camera.environment = _environment()
	lead.add_child(camera)
	camera.position.y = EYE
	camera.set_cull_mask_value(2,false)
	_make_lead_marks()
	camera.make_current()
	yaw = 0.0
	pitch = .012
	_camera_rotation()
	crouched = false
	hale_low = false
	role = "NEAR"
	deck = [false,false]
	spans = [Span.new(),Span.new()]
	red_signal = [false,false]
	red_voices = [null,null]
	trial_at = 0
	offer = 0
	offer_open = false
	book_open = false
	book.hide()
	attempted_tread = false
	stalemate = false
	local_hale = {}
	hale_optics = {}
	head_memory = {}
	boot_memory = {}
	last_policy = ""
	searched = false
	red_after_panic = false
	exchange = false
	failed = ""
	witness = [[false,false],[false,false]]
	tick = 0
	gate_ticks = 0
	cleared = false
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
	if e is InputEventKey and e.pressed and not e.echo:
		if e.physical_keycode == KEY_TAB and not auto_input:
			book_open = not book_open
			if not book_open: offer_open = false
		if offer_open and e.physical_keycode in [KEY_1,KEY_2,KEY_3]:
			offer = e.physical_keycode - KEY_1 + 1
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
	var angles := Vector2(Input.get_axis(&"air_turn_r",&"air_turn_l"),Input.get_axis(&"air_down",&"air_up")) * STEP * KEY_LOOK_SPEED
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
		offer = cmd.get("offer",0)
		book_open = cmd.get("book",false)
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
	if not failed.is_empty(): return
	cue_head.position.y = camera.position.y - .09
	cue_head.rotation.y = yaw
	for plate: Node3D in cue_head.get_children(): plate.force_update_transform()
	cue_boot.force_update_transform()
	witness[0] = _observe(lead_eyes,lead_front,lead)
	# One common visual acquisition also feeds Hale's policy. No player-directed rays.
	hale_optics = _sample(_hale_eye(),hale_forward,hale,true)
	witness[1] = hale_optics.spans
	if not _tick_spans(): return
	_drive(lead,Vector3(moves.x,0,moves.y).rotated(Vector3.UP,yaw), LOW_SPEED if crouched else SPEED)
	local_hale = _hale_percept(0 if role in ["NEAR","A_LINE","CROSS_A"] else 1)
	_trial(talk and _can_talk())
	_update_hale()
	if minf(lead.position.y,hale.position.y) < -2.46:
		_fail("FALL",lead.position if lead.position.y < hale.position.y else hale.position)
		return
	if gate_ticks > 0 or (_floor(lead) == "far" and _floor(hale) == "far"):
		gate_ticks = mini(gate_ticks+1,48)
		room.lift_gate(smoothstep(0.0,1.0,float(gate_ticks)/48.0))
		if not cleared and lead.position.x > 7.76 and absf(lead.position.z+3.95) < .66:
			cleared = true
			_sound("reply",lead.position)
			_event("EXIT_CLEARED")
	_refresh()


func _tick_spans() -> bool:
	var broken := -1
	for i in range(2):
		var span = spans[i]
		var old_red: int = span.red
		var old_dark: int = span.dark
		span.step(int(witness[0][i])+int(witness[1][i]))
		var focus: Vector3 = room.spans[i].focus
		if deck[i] != span.solid:
			_event("FORM" if span.solid else "RELEASE",{"span":i})
			_sound("form" if span.solid else "drop",focus)
		red_signal[i] = span.red > 0
		if span.red == 1:
			if role == "WATCH_B":
				_say("[A rising drone.]",48)
			_event("RED",{"span":i})
			red_voices[i] = _sound("red",focus)
		if old_red > 0 and span.red == 0:
			if is_instance_valid(red_voices[i]): red_voices[i].queue_free()
			red_voices[i] = null
			_event("RED_CLEARED",{"span":i,"held":old_red})
		if span.dark == 1:
			_event("NO_EYES",{"span":i})
			_sound("grace",focus)
		if old_dark > 0 and old_dark < Span.GRACE and span.dark == 0 and span.solid:
			_event("EYES_RETURNED",{"span":i,"gap":old_dark,"lead":witness[0][i],"hale":witness[1][i]})
			if i == 1 and exchange and witness[0][i] and not witness[1][i]:
				exchange = false
				_event("FAR_HANDOFF",{"gap":old_dark})
		if span.red > Span.RED_LIMIT and broken == -1: broken = i
		deck[i] = span.solid
		room.paint(i,span.solid,span.dark,span.red,room.spans[i].lamp.visible)
		if i == 1: room.paint_relay(span.dark,span.red > 0)
	if broken != -1:
		_fail("DOUBLE_GAZE",room.spans[broken].focus,broken)
		return false
	return true


func _fail(reason: String, at: Vector3, span := -1) -> void:
	failed = reason
	_event("DEAD",{"cause":reason,"span":span})
	_sound("death" if reason == "DOUBLE_GAZE" else "drop",at)
	_say("It saw you both." if reason == "DOUBLE_GAZE" else "The dark did not hold.",99999)
	_refresh()


func _tread_in_view() -> bool:
	var middle := room.tread_reference.global_position
	if not camera.is_position_in_frustum(middle): return false
	# The physical tips must frame the visible gap; the same point carries the real tread when solid.
	for tip: Node3D in room.tread_reference.get_children():
		if not camera.is_position_in_frustum(tip.global_position): return false
		if not _ray(camera.global_position,tip.global_position,Room.WORLD|Room.ACTOR,[lead.get_rid()]).is_empty(): return false
	return _ray(camera.global_position,middle,Room.WORLD|Room.ACTOR,[lead.get_rid()]).is_empty()


func _trial(talk: bool) -> void:
	if role == "WAIT_B":
		# The first-hand demonstration is the dark threshold within sight, then a retreat onto stone.
		var at_lintel := lead.position.x > .70 and absf(lead.position.z-Room.B_LANE) < .43
		if at_lintel and not deck[1] and not rule.revised and not attempted_tread and not book_open and not offer_open and _tread_in_view():
			attempted_tread = true
			var referent := room.tread_reference.global_position
			_event("TREAD_DARK",{"clause":Rules.TREAD.id,"point":referent,"screen":camera.unproject_position(referent)})
		if attempted_tread and not at_lintel and _floor(lead) == "island" and not stalemate:
			stalemate = true
			_event("ORIGINAL_RULES_STALL",{"player":Rules.TREAD.id,"hale":Rules.TABOO.id})
			_say("Hale: P-03 brought you back. H-03 keeps me here.",235)
		if not talk and offer == 0: return
		if talk and not _can_talk(): return
		if rule.distorted and talk:
			rule.ground()
			_event("GROUNDED")
			_say("Hale: Read it back to me. The original wording.",215)
		elif rule.counterexample:
			if offer != 0:
				var proposed := offer
				offer = 0
				if _can_talk() and rule.speak(true,"P-03" if proposed == 3 else "H-03","TOWARD" if proposed == 2 else "AWAY"):
					offer_open = false
					book_open = false
					_event("RULE_REVISED",{"clause":Rules.TABOO.id,"allowed":rule.ast.allowed_heads})
					_say("Hale: I'll write that exception under H-03.",200)
				else:
					_event("OFFER_REJECTED",{"choice":proposed})
					_say("Hale: That's not what we saw.",165)
			elif talk and not rule.revised:
				offer_open = true
				book_open = true
		elif talk and not rule.revised:
			if not stalemate:
				_say("Hale: I won't look into it. Compare our field copies.",180)
				return
			rule.begin_trial()
			searched = false
			red_after_panic = false
			trial_at = tick
			role = "TRIAL_WAIT"
			_event("TRIAL_REQUESTED")
			_say("Hale: One look, from stone. If it reddens, we stop.",140)
			_sound("reply",hale.position + Vector3.UP)
	elif role == "TRIAL_WAIT" and tick-trial_at >= 39:
		role = "TRIAL_LOOK"
		_turn_hale(_watch_b())
	elif role == "TRIAL_LOOK":
		var result := rule.sample_trial(local_hale)
		if result == "DISTORTED":
			_event("RULE_DISTORTED")
			_say("Hale: No. Look with me. It needs to see us both.",215)
		elif result == "EVIDENCE":
			role = "WAIT_B"
			_event("COUNTEREXAMPLE",{"remaining":rule.hypotheses.duplicate()})
			_say("Hale: It went white. And it stayed white.",230)
			_sound("knock",hale.position+Vector3.UP)
		if role != "TRIAL_LOOK": return
		if rule.distorted:
			var reaction := rule.decide(local_hale,"TAKE")
			_policy(reaction)
			if reaction == "SEARCH":
				searched = true
				_turn_hale(Room.ISLAND_TRIAL + Vector3.UP*1.84)
			elif reaction == "JOIN":
				if searched and not red_after_panic:
					red_after_panic = true
					_event("FALSE_RULE_GLANCE")
				_turn_hale(_watch_b())
		if tick-trial_at >= 258:
			role = "WAIT_B"
			if not rule.distorted: _say("Hale: I didn't see enough to change it.",175)


func _policy(decision: String) -> void:
	if decision == last_policy: return
	last_policy = decision
	_event("HALE_DECISION",{"action":decision,"stage":role,"head":local_hale.get("head"),"bank":local_hale.get("bank"),
		"head_hit":local_hale.get("head_hit",{}),"boot_hit":local_hale.get("boot_hit",{}),"span_hit":local_hale.get("span_hit",{})})


func _hale_percept(span: int) -> Dictionary:
	var through := hale_optics.get("head",{}) as Dictionary
	var boot := hale_optics.get("boot",{}) as Dictionary
	if not through.is_empty(): head_memory = through
	if not boot.is_empty(): boot_memory = boot
	# A brief overlap window between the visible boot and the turn of the face.
	# Fresh orientation is mandatory; a past glimpse cannot prove where the head points now.
	if not boot_memory.is_empty() and tick-int(boot_memory.tick) > 9: boot_memory = {}
	var pose := Rules.NONE
	if not through.is_empty():
		var toward: Vector3 = (room.spans[span].focus-through.point).slide(Vector3.UP).normalized()
		var dot: float = toward.dot(through.direction)
		pose = "AWAY" if dot < .19 else ("TOWARD" if dot > .69 else "SIDE")
	var optic: Dictionary = hale_optics.get("optic",[{},{}])[span]
	return {"head":pose,"bank":boot_memory.get("bank",Rules.NONE),
		"color":room.spans[span].aspect if not optic.is_empty() else Rules.NONE,
		"heard_red":red_signal[span] and _hale_eye().distance_to(room.spans[span].focus) < 6.0,
		"head_hit":through,"boot_hit":boot_memory,"span_hit":optic}


func _make_lead_marks() -> void:
	# Two outward faces of a field helmet crest; the first-person camera omits its own marks.
	# Hit normals and the sampled painted face suffice to infer pose. Do not read global pose.
	cue_head = Node3D.new()
	lead.add_child(cue_head)
	for face in ["visor","nape","right","left"]:
		var plate := StaticBody3D.new()
		plate.collision_layer = Room.CUE
		plate.collision_mask = 0
		cue_head.add_child(plate)
		plate.set_meta("signal",face)
		plate.position = {"visor":Vector3(0,0,-.239),"nape":Vector3(0,0,.239),"right":Vector3(.239,0,0),"left":Vector3(-.239,0,0)}[face]
		plate.rotation.y = {"visor":PI,"nape":0.0,"right":PI/2.0,"left":-PI/2.0}[face]
		var quad := QuadMesh.new()
		quad.size = Vector2(.47,.43)
		var visual := room.kit.piece(quad,Vector3.ZERO,Color("aababb") if face == "visor" else Color("878076"),plate)
		visual.layers = 2
		var shell := CollisionShape3D.new()
		shell.shape = quad.create_trimesh_shape()
		plate.add_child(shell)
	cue_boot = StaticBody3D.new()
	lead.add_child(cue_boot)
	cue_boot.collision_layer = Room.CUE
	cue_boot.collision_mask = 0
	cue_boot.set_meta("signal","boots")
	cue_boot.position.y = .19
	var size := Vector3(.47,.29,.47)
	var visual := room.kit.box(Vector3.ZERO,size,Color("847e74"),cue_boot)
	visual.layers = 2
	var box := BoxShape3D.new()
	box.size = size
	var shell := CollisionShape3D.new()
	shell.shape = box
	cue_boot.add_child(shell)


func _sample_bank(contact: Vector3) -> String:
	# A visible low boot mark inside the known stone footprint, with a conservative edge margin.
	# This classifier gets only the optical hit point, never the lead body's contact or position.
	if contact.y < .035 or contact.y > .34: return Rules.NONE
	for bank in ["island", "far"]:
		if room.stone_bounds[bank].grow(-.23).has_point(Vector2(contact.x,contact.z)): return bank
	return Rules.NONE


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
	return _sample(eye,forward,who,false).spans


func _sample(eye: Vector3, forward: Vector3, who: CharacterBody3D, marks: bool) -> Dictionary:
	var sampled := {"spans":[false,false],"optic":[{},{}],"head":{},"boot":{}}
	var az := atan2(-forward.x,-forward.z)
	var el := asin(clampf(forward.y,-1.0,1.0))
	var idx := -1
	var mask := Room.WORLD|Room.ACTOR|Room.FACET|(Room.CUE if marks else 0)
	for column in [0,-1,1,-2,2,-3,3,-4,4]:
		for row in [0,-1,1]:
			idx += 1
			var direction := Vector3.FORWARD.rotated(Vector3.RIGHT,el+deg_to_rad(row*13.0)).rotated(Vector3.UP,az+deg_to_rad(column*15.0))
			var hit := _ray(eye,eye+direction*13.0,mask,[who.get_rid()])
			if hit.is_empty(): continue
			for i in range(2):
				var settings := room.spans[i]
				if not sampled.spans[i] and hit.collider == settings.optic and hit.normal.dot(settings.normal) > .95:
					if _lit(settings.lamp,hit.position,false,hit.normal):
						sampled.spans[i] = true
						sampled.optic[i] = _receipt_hit(idx,"span-%d" % i,settings.lamp,hit)
			if not marks: continue
			var cue: String = hit.collider.get_meta("signal","")
			if cue.is_empty(): continue
			if (cue == "boots" and not sampled.boot.is_empty()) or (cue != "boots" and not sampled.head.is_empty()): continue
			for n in range(room.cue_lights.size()):
				var lamp := room.cue_lights[n]
				if not _lit(lamp,hit.position,true,hit.normal): continue
				var reading := _receipt_hit(idx,"landing-%d" % n,lamp,hit)
				reading.mark = cue
				if cue == "boots":
					reading.bank = _sample_bank(hit.position)
					if reading.bank != Rules.NONE: sampled.boot = reading
				else:
					reading.direction = hit.normal.rotated(Vector3.UP,{"visor":0.0,"nape":PI,"right":PI/2.0,"left":-PI/2.0}[cue])
					sampled.head = reading
				break
	return sampled


func _receipt_hit(idx: int, source: String, lamp: SpotLight3D, hit: Dictionary) -> Dictionary:
	var normal: Vector3 = hit.normal
	return {"ray":idx,"tick":tick,"light":source,"point":hit.position,"normal":normal,
		"incidence":normal.dot((lamp.global_position-hit.position).normalized())}


func _lit(lamp: SpotLight3D, point: Vector3, outer_mark := false, normal := Vector3.ZERO) -> bool:
	var d := point-lamp.global_position
	if not lamp.visible or lamp.light_energy <= 0.0 or d.length() > lamp.spot_range: return false
	if d.normalized().dot(-lamp.global_transform.basis.z) < cos(deg_to_rad(lamp.spot_angle)): return false
	if normal != Vector3.ZERO and normal.dot(-d.normalized()) <= .02: return false
	var omit: Array[RID] = []
	if outer_mark: omit.append(lead.get_rid())
	return _ray(lamp.global_position,point+normal*.004,Room.WORLD|Room.ACTOR|(Room.CUE if outer_mark else 0),omit).is_empty()


func _hale_eye() -> Vector3:
	return hale.global_position + Vector3.UP*(LOW_EYE if hale_low else EYE)


func _hale_sees_lead() -> bool:
	return not local_hale.get("head_hit",{}).is_empty() or (not head_memory.is_empty() and tick-int(head_memory.tick) <= 6)


func _can_talk() -> bool:
	if role != "WAIT_B" or not _hale_sees_lead() or lead.position.distance_to(hale.position) > 1.60: return false
	return (-camera.global_transform.basis.z).dot((hale.global_position+Vector3.UP*1.39-camera.global_position).normalized()) > .69


func _watch_b() -> Vector3:
	return _hale_eye() + Vector3(6.0,-1.275,.185)


func _inspect_far() -> Vector3:
	return _hale_eye() + Vector3(6.0,-1.275,0.0)


func _turn_hale(target: Vector3) -> void:
	var offset := target-_hale_eye()
	if offset.length_squared() > .004: hale_forward = offset.normalized()
	_face_model(hale_forward)


func _face_model(forward: Vector3) -> void:
	model.rotation.y = atan2(forward.x,forward.z)


func _hale_feels_footing(target: Vector3) -> bool:
	var step_to := hale.position + (target-hale.position).slide(Vector3.UP).normalized()*.26
	return not _ray(step_to+Vector3.UP*.20,step_to-Vector3.UP*.09,Room.WORLD|Room.DECK,[]).is_empty()




func _update_hale() -> void:
	var target := hale.position
	var speed := 2.65
	var aim := Vector3.ZERO
	match role:
		"NEAR":
			# Walk only after contacting a solid threshold; his ban on looking remains in force.
			role = "A_LINE"
		"A_LINE":
			target = Vector3(-.25,0,.53)
			aim = Vector3(-.25,4.0,-3.7)
			if _flat(hale.position,target) < .08:
				role = "CROSS_A"
				_event("FIRST_HANDOFF")
		"CROSS_A":
			target = Vector3(-.25,0,-3.27)
			aim = Vector3(-.25,3.4,-4.95)
			if not rule.permits_step(_hale_feels_footing(target)): target = hale.position
			if _flat(hale.position,target) < .08 and hale.position.z < -3.13: role = "ISLAND"
		"ISLAND":
			target = Room.ISLAND_WATCH
			aim = Vector3(.25,2.2,-4.15)
			if _flat(hale.position,target) < .077:
				role = "WAIT_B"
				_event("HALE_AT_LANDING")
				_say("Hale: Second span. H-03 still applies.",230)
		"WAIT_B":
			# Sweep the actual ray lattice down across the companion's stance and back.
			aim = Room.ISLAND_TRIAL + Vector3.UP * 1.84 if not rule.revised or tick % 31 >= 12 else Vector3(.29,.18,-2.73)
			var action := rule.decide(local_hale,"TAKE")
			_policy(action)
			if action in ["TAKE","JOIN"]:
				role = "WATCH_B"
				aim = _watch_b()
				_event("HALE_TAKES_B")
		"WATCH_B":
			aim = _watch_b()
			var decision := rule.decide(local_hale,"GIVE")
			_policy(decision)
			if decision == "RECOIL":
				role = "RETRY_B"
				aim = _inspect_far()
				_event("HALE_RECOILS")
				_say("Hale: Stone. Pull back.",130)
			elif decision == "GIVE":
				role = "B_LINE"
				exchange = true
				# The next optical sample, not the knock, determines the loss of support.
				aim = Vector3(.93,1.58,-5.0)
				_event("BLIND_SIGNAL")
				_sound("knock",hale.position + Vector3.UP)
				_say("[A knock.]",54)
		"RETRY_B":
			aim = _inspect_far()
			var action := rule.decide(local_hale,"TAKE")
			_policy(action)
			if action == "TAKE":
				role = "WATCH_B"
				aim = _watch_b()
				_event("HALE_RETAKES_B")
		"B_LINE":
			target = Vector3(.91,0,Room.B_LANE)
			aim = Vector3(.93,1.58,-5.0)
			if _flat(hale.position,target) < .08: role = "CROSS_B"
		"CROSS_B":
			target = Vector3(6.62,0,Room.B_LANE)
			if not rule.permits_step(_hale_feels_footing(target)) and _floor(hale) == "island": target = hale.position
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
	book = PanelContainer.new()
	book.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(book)
	book.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	book.offset_left = -347
	book.offset_right = 347
	book.offset_top = -183
	var page := StyleBoxFlat.new()
	page.bg_color = Color("242729f2")
	page.set_border_width_all(1)
	page.border_color = Color("7e8580")
	page.content_margin_left = 28
	page.content_margin_right = 28
	page.content_margin_top = 23
	page.content_margin_bottom = 23
	book.add_theme_stylebox_override("panel",page)
	book_text = Label.new()
	book_text.add_theme_font_size_override("font_size",18)
	book_text.custom_minimum_size.x = 630
	book_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	book.add_child(book_text)


func _say(text: String, length: int) -> void:
	subtitle.text = text
	until = tick+length


func _refresh() -> void:
	book.visible = (book_open or offer_open) and failed.is_empty() and not cleared
	if book.visible:
		book_text.text = "FIELD COPIES   /   L03     [TAB]\n\nP-03   YOUR COPY\n" + Rules.TREAD.notice
		book_text.text += "\n" + Rules.player_notice() + "\n\nH-03   HALE'S COPY\n" + Rules.TABOO.notice
		if rule.revised: book_text.text += "\nPencilled exception: " + Rules.SINGLE_EXCEPTION
		if offer_open: book_text.text += "\n\nPROPOSE AN AMENDMENT\n[1] H-03: Look only while I face away.\n[2] H-03: Allow both of us to look.\n[3] P-03: Cross without seeing the tread."
	if tick == 75 and role in ["NEAR","A_LINE"]:
		_say("Hale: I've got a different copy. Keep both close.",204)
	if tick > until: subtitle.text = ""
	if not failed.is_empty():
		hud.text = "R   /   Restart airlock"
	elif cleared:
		hud.text = "AIRLOCK CLEARED"
	elif _can_talk():
		hud.text = ("E   /   Ground Hale" if rule.distorted else ("E   /   Compare the evidence" if rule.counterexample else "E   /   Speak to Hale")) + "   ·   Tab  Field copies"
	else:
		hud.text = ("WASD  Move   ·   Mouse  Look   ·   Ctrl  Crouch   ·   Tab  Field copies" if tick < 193 else ("Ctrl  Crouch" if lead.position.z < -3.20 and lead.position.x < 1.25 else ""))
		if guided and tick < 193: hud.text += "   ·   [ / ]  Gallery"
	crosshair.modulate.a = .66 if witness[0].has(true) else .36


func _make_cues() -> void:
	for cue: String in ["form","grace","drop","reply","red","death","knock"]:
		var wav := AudioStreamWAV.new()
		wav.format = AudioStreamWAV.FORMAT_16_BITS
		wav.mix_rate = 24000
		var seconds := (.68 if cue == "red" else (.59 if cue in ["form","grace"] else .41))
		var count := int(wav.mix_rate * seconds)
		var pcm := PackedByteArray()
		pcm.resize(count*2)
		for i in range(count):
			var t := float(i)/wav.mix_rate
			var env := minf(1.0,t*45.0)*pow(1.0-t/seconds,1.6)
			var freq := (68.0+89.0*t) if cue=="form" else ((173.0-128.0*t) if cue=="drop" else (202.0 if cue=="grace" else 109.0))
			var wave := sin(TAU*freq*t)*.72 + sin(TAU*(freq*2.04)*t)*.28
			if cue=="grace": wave *= .25+.75*absf(sin(t*32.0))
			if cue == "red":
				wave = sin(TAU*91.0*t + 1.8*sin(TAU*26.0*t))*.63 + sin(TAU*347.0*t)*.23
				env = minf(1.0,t*100.0)*(1.0-.50*t/seconds)
			elif cue == "death": wave = sin(TAU*(67.0-32.0*t)*t) * .92
			elif cue == "knock": wave = sin(TAU*162.0*t)*pow(maxf(0.0,1.0-fmod(t,.12)*16.0),2.0)
			pcm.encode_s16(i*2,int(wave*env*9900.0))
		wav.data = pcm
		cues[cue] = wav


func _sound(cue: String, pos: Vector3) -> AudioStreamPlayer3D:
	if DisplayServer.get_name() == "headless": return null
	var audio := AudioStreamPlayer3D.new()
	stage.add_child(audio)
	audio.position = pos
	audio.stream = cues[cue]
	audio.unit_size = 4.0
	audio.max_distance = 22.0
	audio.finished.connect(audio.queue_free)
	audio.play()
	return audio


func mcp_observe() -> Dictionary:
	return {"plate":3,"mode":"airlock","view":"eye","tick":tick,"lead":lead.position,"hale":hale.position,
		"lead_floor":_floor(lead),"hale_floor":_floor(hale),"witness":witness.duplicate(true),"solid":deck.duplicate(),
		"collision":[room.spans[0].solid.collision_layer != 0,room.spans[1].solid.collision_layer != 0],
		"bridge_mesh":[room.spans[0].surface.visible,room.spans[1].surface.visible],
		"crouched":crouched,"role":role,"counterexample":rule.counterexample,"revision":rule.revised,
		"ast":rule.ast,"hale_percept":local_hale,"hypotheses":rule.hypotheses,"player_ast":Rules.PLAYER,"panic":rule.panic,"distorted":rule.distorted,"failed":failed,
		"subtitle":subtitle.text,"book":book.visible,"offer_open":offer_open,"stalemate":stalemate,"dark":[spans[0].dark,spans[1].dark],"red":[spans[0].red,spans[1].red],
		"cleared":cleared,"events":receipts.duplicate(true),"film":clip.get("phase") if clip != null else "",
		"phase_age":tick-int(clip.get("since")) if clip != null else 0,
		"film_error":film_failed,"hale_model":motion.actor.scene_file_path}
