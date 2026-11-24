extends Node3D

const Finish := preload("res://scenes/blue_prince_lab/HallFinish.gdshader")
const Geo := preload("res://tools/building_construction/BuildingConstruction/Shared/RecipeGeometry.gd")
const Gothic := preload("res://tools/building_construction/production/rule/GothicRecipes.gd")
const WARM := Color("efad62")
const COOL := Color("7dded5")
const PAPER := Color("d5c3a2")
const RED := Color("ef795f")
const IRON := Color("32424e")
const SLATE := Color("697986")
const SPACE := 1.18
const SPAN := 12.1
var board: Dictionary
var bays: Array
var mats := {}
var pins := {}
var cured := {}
var carts := {}
var arrows: Array[MeshInstance3D] = []
var ghosts: Array[Node3D] = []
var focus_nodes: Array[Node3D] = []
var focus_boxes: Array[AABB] = []
var faded := 0
var drum: Node3D
var furniture: Node3D
var material_exception: StandardMaterial3D
var block := BoxMesh.new()


func build(layout: Dictionary) -> void:
	board = layout
	bays = board.bays
	furniture = Node3D.new()
	add_child(furniture)
	material_exception = StandardMaterial3D.new()
	material_exception.albedo_color = Color(0.54, 0.73, 0.80, 0.15)
	material_exception.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material_exception.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_table("ink", WARM)
	_table("lift", COOL)
	var n := Node3D.new()
	add_child(n)
	n.position = Vector3(0, 0.7, -3.82)
	cylinder(n, Vector3.ZERO, 0.90, 1.08, IRON, false)
	drum = Node3D.new()
	n.add_child(drum)
	cylinder(drum, Vector3(0, 0.53, 0), 0.78, 0.15, WARM, false)
	for i in 18:
		var a := i * TAU / 18
		var cog := box(drum, Vector3(cos(a) * 0.75, 0.55, sin(a) * 0.75), Vector3(0.21, 0.14, 0.17), WARM.darkened(0.25))
		cog.rotation.y = -a
	cylinder(drum, Vector3(0, 0.62, 0), 0.62, 0.08, IRON, false)
	bar(drum, Vector3(-0.47, 0.70, 0), Vector3(0.47, 0.70, 0), 0.10, WARM)
	label(furniture, "REVERSE DRUM", Vector3(0, 0.11, -2.45), 0.23, Color("d4bd8e"))
	# Spare overlay meshes are shown only for the active three routes and 40-tick ghosts.
	for i in 5:
		arrows.append(box(furniture, Vector3.ZERO, Vector3.ONE, PAPER, true))
		arrows[-1].visible = false
	for i in 2:
		var gh := make_cart(COOL, true)
		gh.visible = false
		ghosts.append(gh)


func place(layer: String, bay: int) -> Vector3:
	var off := -SPAN * 0.5 if layer == "ink" else SPAN * 0.5
	if bay == board.turn: return Vector3(off + 4.72, 0.10, 5.18)
	if bay == board.exit: return Vector3(off - 4.72, 0.10, -5.18)
	if bay < 0: return Vector3(off, 0.1, 0)
	var data: Dictionary = bays[bay]
	return Vector3(off + (data.x - (board.width - 1) * 0.5) * SPACE, 0.10,
		(data.y - (board.height - 1) * 0.5) * SPACE)


func _table(deck: String, accent: Color) -> void:
	var gx := -SPAN * 0.5 if deck == "ink" else SPAN * 0.5
	box(furniture, Vector3(gx, -0.41, 0), Vector3(11.4, 0.81, 11.3), IRON)
	box(furniture, Vector3(gx, -0.66, 0), Vector3(11.55, 0.10, 11.46), WARM.darkened(0.28))
	for i in 9:
		box(furniture, Vector3(gx - 5.61 + i * 1.40, -0.25, 5.665), Vector3(0.06, 0.41, 0.07), SLATE.darkened(0.28))
	for i in 4:
		var x := gx - 4.12 + i * 2.75
		box(furniture, Vector3(x, 0.42, -5.48), Vector3(2.74, 0.84, 0.20), SLATE.darkened(0.18))
		var m := material(SLATE.lightened(0.25))
		var g := Geo.finish(Gothic.gen_gothic_pointed_rib("Crown", {"stone": m, "cream": m}, 1.32, 0, 0.9, 0.07, 8))
		g.position = Vector3(x, 0.80, -5.42)
		furniture.add_child(g)
		for j in [-1.3, 1.3]:
			box(furniture, Vector3(x + j, 0.42, -5.38), Vector3(0.14, 0.81, 0.28), SLATE.lightened(0.20))
	for data: Dictionary in bays:
		var b: int = data.id
		var at := place(deck, b)
		var tiling := SLATE.lerp(accent, 0.13 if (data.x + data.y) % 2 == 0 else 0.22)
		box(furniture, at - Vector3(0, 0.077, 0), Vector3(1.14, 0.13, 1.14), tiling)
		for port in 3:
			var target: int = data[deck][port]
			if target == board.hold: continue
			var dest := place(deck, target)
			var vec := dest - at
			var side := vec.cross(Vector3.UP).normalized() * 0.036
			for sideway in [Vector3.ZERO, side]:
				bar(furniture, at + vec * 0.20 + sideway, dest - vec * 0.20 + sideway, 0.026, accent.darkened(0.52))
		label(furniture, str(b + 1).pad_zeros(2), at + Vector3(0.23, 0.014, 0.34), 0.18, PAPER)
		var socket := cylinder(furniture, at + Vector3(0, 0.025, 0), 0.198, 0.08, IRON, false)
		var face := cylinder(furniture, at + Vector3(0, 0.078, 0), 0.12, 0.055, accent, true)
		face.visible = false
		if deck == "ink": pins[b] = face
		else: cured[b] = face
		socket.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var terminal := place(deck, board.turn if deck == "ink" else board.exit)
	box(furniture, terminal - Vector3(0, 0.08, 0), Vector3(0.92, 0.19, 0.78), IRON)
	cylinder(furniture, terminal + Vector3(0, 0.13, 0), 0.31, 0.25, accent, true)
	label(furniture, "TURN" if deck == "ink" else "EXIT", terminal + Vector3(0, 0.045, 0.54), 0.17, PAPER)
	label(furniture, "I  /  INK GANTRY" if deck == "ink" else "II  /  LIFT GANTRY", Vector3(gx, 0.13, 5.20), 0.32, accent)
	carts[deck] = make_cart(accent, false)
	var pier := box(furniture, Vector3(gx + 3.72, 0.65, 5.08), Vector3(0.42, 1.54, 0.43), SLATE.lightened(0.07))
	focus_nodes.append(pier)
	focus_boxes.append(AABB(pier.position - Vector3(0.22, 0.78, 0.22), Vector3(0.44, 1.56, 0.44)))


func render(s: Dictionary, preview: Dictionary, camera: Camera3D) -> void:
	for b in bays.size():
		(pins[b] as MeshInstance3D).visible = s.pins[b] >= 0
		(cured[b] as MeshInstance3D).visible = s.cured[b]
		if s.pins[b] >= 0:
			(pins[b] as MeshInstance3D).material_override = material([WARM, Color("fbd69d"), Color("f08166")][s.pins[b]], true)
	carts.ink.position = place("ink", s.ink_bay)
	carts.lift.position = place("lift", s.lift_bay)
	if not s.in_flight.is_empty():
		var route: Dictionary = s.in_flight
		var from := place(route.deck, route.from)
		var dest := place(route.deck, route.to) if route.to != board.hold else from + Vector3(0.26, 0, 0.12)
		var fraction := float(s.tick - route.start_tick) / float(route.end_tick - route.start_tick)
		carts[route.deck].position = from.lerp(dest, fraction)
	drum.rotation.y = (float(s.tick) * (-0.19 if s.phase == "rewind" else 0.064))
	for gh in ghosts: gh.visible = false
	for a in arrows: a.visible = false
	if s.phase == "record" and s.in_flight.is_empty() and s.ink_bay >= 0:
		for i in 3:
			var dest: int = bays[s.ink_bay].ink[i]
			if dest == board.hold: continue
			var a := place("ink", s.ink_bay)
			var b := place("ink", dest)
			var picked: bool = preview.get("action", "") == "port_%d" % i and preview.get("ok", false)
			var c := WARM if picked else PAPER.darkened(0.34)
			link(arrows[i], a.lerp(b, 0.22) + Vector3.UP * 0.08, b.lerp(a, 0.18) + Vector3.UP * 0.08, 0.072 if picked else 0.035, c)
	if preview.get("ok", false):
		for i in 2:
			var frame: Dictionary = preview.frames[(i + 1) * 20 - 1]
			var event: Dictionary = frame.event
			if event.is_empty() or (i == 1 and preview.action != "rewind"): continue
			var dest: Vector3 = place(event.deck, event.to) if event.to != board.hold else place(event.deck, event.from) + Vector3(0.28, 0, 0.13)
			ghosts[i].position = dest + Vector3(0, 0.08, 0)
			ghosts[i].visible = true
			link(arrows[3 + i], place(event.deck, event.from) + Vector3.UP * 0.17, dest + Vector3.UP * 0.17, 0.052,
				RED if frame.phase == "failed" else COOL)
	cut_away(camera)


func cut_away(view: Camera3D) -> void:
	faded = 0
	for i in focus_boxes.size():
		var hidden := false
		for target: Vector3 in [carts.ink.position + Vector3.UP * 0.22, carts.lift.position + Vector3.UP * 0.22,
			place("ink", board.turn), place("lift", board.exit)]:
			if focus_boxes[i].intersects_segment(target + view.global_basis.z * 60.0, target) != null:
				hidden = true
				break
		faded += int(hidden)
		focus_nodes[i].material_override = material_exception if hidden else material(SLATE.lightened(0.07))
		focus_nodes[i].cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF if hidden else GeometryInstance3D.SHADOW_CASTING_SETTING_ON


func make_cart(hue: Color, ghost: bool) -> Node3D:
	var n := Node3D.new()
	furniture.add_child(n)
	box(n, Vector3(0, 0.16, 0), Vector3(0.44, 0.14, 0.54), hue.darkened(0.20), ghost)
	cylinder(n, Vector3(0, 0.30, 0), 0.16, 0.30, hue, true)
	cylinder(n, Vector3(0, 0.49, 0), 0.23, 0.11, hue.lightened(0.11), true)
	if ghost:
		for part: MeshInstance3D in n.get_children():
			part.material_override = material_exception
			part.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return n


func material(color: Color, lit: bool = false) -> ShaderMaterial:
	var k := "%s:%s" % [color, lit]
	if not mats.has(k):
		var m := ShaderMaterial.new()
		m.shader = Finish
		m.set_shader_parameter("pigment", color)
		m.set_shader_parameter("toon_on", true)
		m.set_shader_parameter("toon_strength", 0.86)
		m.set_shader_parameter("grain", 0.052)
		m.set_shader_parameter("emission_gain", 0.40 if lit else 0.0)
		mats[k] = m
	return mats[k]


func box(parent: Node3D, at: Vector3, dims: Vector3, c: Color, lit: bool = false) -> MeshInstance3D:
	var m := MeshInstance3D.new()
	m.mesh = block
	parent.add_child(m)
	m.position = at
	m.scale = dims
	m.material_override = material(c, lit)
	return m


func cylinder(parent: Node3D, at: Vector3, radius: float, length: float, c: Color, lit: bool) -> MeshInstance3D:
	var m := MeshInstance3D.new()
	var shape := CylinderMesh.new()
	shape.top_radius = radius
	shape.bottom_radius = radius
	shape.height = length
	shape.radial_segments = 16
	shape.rings = 0
	m.mesh = shape
	m.material_override = material(c, lit)
	parent.add_child(m)
	m.position = at
	return m


func bar(parent: Node3D, a: Vector3, b: Vector3, width: float, c: Color) -> void:
	var m := box(parent, (a + b) * 0.5, Vector3(width, a.distance_to(b), width), c)
	m.quaternion = Quaternion(Vector3.UP, (b - a).normalized())
	m.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


func link(m: MeshInstance3D, a: Vector3, b: Vector3, width: float, c: Color) -> void:
	m.position = (a + b) * 0.5
	m.quaternion = Quaternion(Vector3.UP, (b - a).normalized())
	m.scale = Vector3(width, a.distance_to(b), width)
	m.material_override = material(c, true)
	m.visible = true


func label(parent: Node3D, title: String, at: Vector3, unit: float, c: Color) -> void:
	var text := Label3D.new()
	text.text = title
	text.font_size = 52
	text.pixel_size = unit / 52.0
	text.modulate = c
	text.outline_size = 2
	text.rotation.x = -PI * 0.5
	parent.add_child(text)
	text.position = at
