extends Node3D
## All player-facing fixture geometry comes from the authored Blender assets.
const Rooms := preload("Rooms.gd")
const Roster := preload("Roster.gd")
const HallFinish := preload("res://scenes/components/rendering/surfaces/HallFinish.gdshader")
const KIT_PIGMENTS := {"walnut": "53616b", "oxblood": "687884", "dark": "303940", "paper": "d9d5bd", "ivory": "d3d0bf", "ink": "30333a"}
const GOLD := Color("f0cd8b")
var plate_font: SystemFont
var stage := ""
var targets: Array[Dictionary] = []
var fixtures: Node3D
var paper: Node3D
var signal_plate: Label3D
var lamp: SpotLight3D
var axes := {}
var animation: Tween
var _motors := {}
var _tone: AudioStreamPlayer3D
var _arrival: Node3D
var _negative: Node3D
var _released := false
var _settled := false
var _idle_clock := 0.0
var _idle_ring := 0

func install(chapter: String, frame: Transform3D, side_guest: String, variant: bool) -> void:
	stage = chapter
	transform = frame
	var asset := load("res://assets/architecture/night_crossing/%s.glb" % chapter) as PackedScene
	assert(asset, "Missing authored fixture for " + chapter)
	fixtures = asset.instantiate()
	_apply_hall_finish(fixtures)
	add_child(fixtures)
	for part in ["MainAction", "AuxAction", "ReceiptLeaf"]:
		var node := fixtures.find_child(part, true, false) as Node3D
		assert(node, "Missing authored pivot " + part)
		_motors[part] = node
	var title: String = Rooms.TITLES[stage]
	_label(title.to_upper(), Vector3(0, 1.738, 0.359), GOLD, 47, .00275)
	var pamphlet := _label(_folio(variant), Vector3(-.814, 1.298, .401), Color("742b21") if stage == "shutter" else Color("3c2a21"), 29, .00168)
	paper = _motors.ReceiptLeaf
	pamphlet.reparent(paper)
	if stage == "returns":
		_label("REED", Vector3(-.245, 1.13, .469), Color("5d3221"), 17, .00115)
		_label("ASH", Vector3(.25, 1.13, .469), Color("5d3221"), 17, .00115)
	if stage == "wash":
		_label("YARD", Vector3(-.287, 1.594, .444), GOLD, 18, .0019)
		_label("CISTERN", Vector3(.298, 1.594, .444), GOLD, 18, .0019)
	for i in 3:
		var x := (i - 1) * .814
		_label(str(Rooms.FIXTURES[stage][i]), Vector3(x, .814, .355), Color("ffe0a6"), 33, .00195)
		# Approach points lie on the open side of each actual mechanism's face.
		targets.append({"kind":"crossing", "label":Rooms.FIXTURES[stage][i], "index":i, "position":to_global(Vector3(x, 0, .92))})
	signal_plate = _label("NIGHT SERVICE", Vector3(0, .904, .37), Color("ecc080"), 20, .0017)
	var body := StaticBody3D.new()
	add_child(body)
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(2.50, 1.90, .70)
	shape.shape = box
	body.add_child(shape)
	shape.position = Vector3(0, .95, -.03)
	lamp = SpotLight3D.new()
	lamp.light_color = Color("ffe4b7") if stage in ["intake", "hall", "meridian"] else Color("dce4e5")
	lamp.light_energy = 2.9
	lamp.spot_range = 4.9
	lamp.spot_angle = 48.0
	lamp.light_specular = .4
	lamp.shadow_enabled = true
	add_child(lamp)
	lamp.position = Vector3(.35, 2.24, 1.59)
	lamp.look_at(to_global(Vector3(0, 1.11, .31)))
	if not side_guest.is_empty():
		_arrival = Node3D.new()
		add_child(_arrival)
		_arrival.position = Vector3(1.33, 0, .46)
		Roster.attach(_arrival, side_guest)
		var nameplate := _label(side_guest + "  /  " + Roster.edition(side_guest).to_upper(), Vector3(1.40,1.87,.59), GOLD, 25, .0017)
		nameplate.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		nameplate.reparent(_arrival)
	_tone = AudioStreamPlayer3D.new()
	_tone.max_distance = 11.0
	_tone.volume_db = -14.0
	add_child(_tone)
	_tone.position = Vector3(0, 1.20, .55)

func _label(line: String, at: Vector3, tint: Color, size: int, pixel: float) -> Label3D:
	var g := Label3D.new()
	if plate_font == null:
		plate_font = SystemFont.new()
		plate_font.font_names = ["Georgia", "Noto Serif", "DejaVu Serif"]
		plate_font.font_weight = 700
	g.font = plate_font
	g.font_size = size
	g.text = line
	g.pixel_size = pixel
	g.modulate = tint
	g.outline_size = 0
	g.no_depth_test = false
	g.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	g.alpha_cut = Label3D.ALPHA_CUT_DISCARD
	add_child(g)
	g.position = at
	return g

func _folio(variant: bool) -> String:
	match stage:
		"intake": return "THE SLEEPING\nACADEMY\n───────────\nFIELD MANUAL\nIVORY  /  No. 04"
		"returns": return "UNDELIVERABLE\nNIGHT REGISTER\n─────────\nREED     ASH\nLAST: %s" % ("ASH" if variant else "REED")
		"exchange": return "PERMANENT ORDER\n─────────\nALL LINES ANSWER\nON FIRST CALL\nFILED · UNSIGNED"
		"wash": return "PUMP ARCHIVE\n─────────\nDELIVERY LOG\nDRY · %s" % ("CISTERN" if variant else "YARD")
		"lift": return "FREIGHT OFFICE\n─────────\nEMPTY CAGE\nLOAD · %s" % ("YARD" if variant else "HALL")
		"airlock": return "ADMISSION\n─────────\nDEPOSIT PACKETS\nENTER TOGETHER\nDRY WARD"
		"shutter": return "RED AMENDMENT\n─────────\nCROSS BEFORE\nTHE BELL\nC U R A T O R"
		"hall": return "PUBLIC HALL\n─────────\nARRIVAL BOOK\nFILES · DEPOSITIONS\nOUTER WING"
		"darkroom": return "FIXING ROOM\n─────────\nTEST STRIP LEDGER\nLEGIBLE · %s" % ("COPPER" if variant else "BLACK")
		"relay": return "DISPATCH EXCHANGE\n─────────\nRETURN DOCKET\n%s" % ("REPEATED" if variant else "ONE REST")
		"meridian": return "THE DAWN REGISTER\n─────────\nNAMES RECORDED\nBELL RETURN\nSIGN HERE"
	return ""

func react(group: int, action: String, result: Dictionary) -> void:
	if result.is_empty(): return
	if result.clear: _released = true
	if action in ["tie", "mute", "brake", "unload", "bath", "partition", "bleed", "carrier"]: _settled = true
	if animation and animation.is_running(): animation.kill()
	var name := "ReceiptLeaf" if group == 0 else ("MainAction" if group == 1 else "AuxAction")
	var pivot: Node3D = _motors[name]
	var hinge: Vector3 = Vector3.FORWARD
	if name == "ReceiptLeaf" or (group == 1 and stage in ["intake", "darkroom", "airlock", "hall"]) or (group == 2 and stage in ["airlock", "returns"]):
		hinge = Vector3.UP
	elif (group == 2 and stage in ["shutter", "exchange", "lift"]) or (group == 1 and stage in ["exchange", "relay"]):
		hinge = Vector3.RIGHT
	var angle := float(axes.get(name, 0.0))
	var hurt: bool = result.damage > 0
	var amount := (0.19 if hurt else 0.63)
	if action in ["wind", "sequence", "parallel", "carrier", "coupon"]: amount += TAU
	var target := angle + amount
	if action in ["trim_yard", "trim_hall"] and result.clear:
		var weight := fixtures.find_child("BalanceShoe", true, false) as Node3D
		var shift := create_tween()
		shift.tween_property(weight, "position:x", .146 if action == "trim_yard" else -.146, .48)
	if stage == "meridian" and result.clear:
		var bell := fixtures.find_child("DawnBell", true, false) as Node3D
		var stroke := create_tween()
		for i in range(5):
			stroke.tween_property(bell, "rotation:z", (-1.0 if i % 2 else 1.0) * (4 - i) * .048, .24)

	var color := Color("ff725b") if hurt else Color("ffe2a2")
	if result.clear: color = Color("b7dabe")
	animation = create_tween().set_parallel(true)
	animation.tween_method(func(a: float): pivot.rotation = hinge * a, angle, target, .68 if amount > 1.0 else .37).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	animation.tween_property(lamp, "light_color", color, .25)
	axes[name] = target if hinge == Vector3.FORWARD else (0.0 if angle >= .62 else .63)
	if hinge != Vector3.FORWARD:
		animation.chain().tween_method(func(a: float): pivot.rotation = hinge * a, target, float(axes[name]), .25)
	signal_plate.text = "RELEASED" if result.clear else ("RETURN REJECTED" if hurt else "RETURN LOGGED")
	if is_instance_valid(_arrival) and result.clear: _arrival.hide()
	if stage == "darkroom" and result.clear and not is_instance_valid(_negative):
		_negative = Node3D.new()
		add_child(_negative)
		_negative.position = Vector3(1.49, 0, .61)
		Roster.attach(_negative, "detective")
		var mark := _label("EXPOSURE 04  /  CAPTAIN", Vector3(1.49, 1.90, .61), Color("bdb8a4"), 22, .002)
		mark.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		for mesh: MeshInstance3D in _negative.find_children("*", "MeshInstance3D", true, false): mesh.transparency = .32
		var fade := create_tween()
		fade.tween_interval(3.5)
		fade.tween_callback(_negative.hide)
		fade.tween_callback(mark.hide)
	_play(hurt, result.clear)

func turn(beat: int) -> void:
	signal_plate.text = "PAPER TURN  %02d" % (beat + 1)
	_play(false, beat % 2 == 0)

func _play(hurt: bool, success: bool) -> void:
	var audio := AudioStreamWAV.new()
	audio.format = AudioStreamWAV.FORMAT_16_BITS
	audio.mix_rate = 16000
	var pcm := PackedByteArray()
	pcm.resize(7680)
	var fundamental := 185.0 if hurt else (364.0 if success else 286.0)
	for i in 3840:
		var time := i / 16000.0
		var pulse := sin(TAU * fundamental * time) + .48 * sin(TAU * (fundamental * 2.78) * time)
		pcm.encode_s16(i * 2, int(clampf(pulse * exp(-time * (8.0 if success else 19.0)), -1.0, 1.0) * 14500.0))
	audio.data = pcm
	_tone.stream = audio
	_tone.play()




func _process(delta: float) -> void:
	if stage not in ["returns", "exchange", "shutter", "relay", "meridian"] or _released or _settled or not is_instance_valid(_tone): return
	_idle_clock += delta
	if _idle_clock < (0.28 if _idle_ring % 2 else 4.7): return
	_idle_clock = 0.0
	_idle_ring += 1
	_play(false, false)


func mark_released() -> void:
	_released = true
	signal_plate.text = "RELEASED"

static func _apply_hall_finish(root: Node3D) -> void:
	var paints := {}
	for part: MeshInstance3D in root.find_children("*", "MeshInstance3D", true, false):
		if part.mesh == null: continue
		for i in part.mesh.get_surface_count():
			var source := part.get_active_material(i) as StandardMaterial3D
			if source == null or source.transparency != BaseMaterial3D.TRANSPARENCY_DISABLED: continue
			var key := source.resource_name if KIT_PIGMENTS.has(source.resource_name) else "__std_" + str(source.get_instance_id())
			if not paints.has(key):
				var mat := ShaderMaterial.new()
				mat.shader = HallFinish
				var color: Color = Color(KIT_PIGMENTS[key]) if KIT_PIGMENTS.has(key) else source.albedo_color
				mat.set_shader_parameter("pigment", color)
				mat.set_shader_parameter("surface_roughness", source.roughness)
				mat.set_shader_parameter("grain", 0.045 if source.metallic > 0.35 else 0.06)
				mat.set_shader_parameter("wood", 1.0 if key == "walnut" else 0.0)
				mat.set_shader_parameter("pale_wash", 0.08 if key in ["paper", "ivory"] else 0.0)
				mat.set_shader_parameter("toon_on", true)
				mat.set_shader_parameter("toon_strength", 0.86)
				paints[key] = mat
			part.set_surface_override_material(i, paints[key])
