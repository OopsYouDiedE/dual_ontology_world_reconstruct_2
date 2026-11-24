extends Node3D

const Rules = preload("ChronographRules.gd")
const HallFinish := preload("res://scenes/blue_prince_lab/HallFinish.gdshader")
const Factory := preload("res://tools/building_construction/BuildingConstruction/Shared/ComponentFactory.gd")
const TILE := 2.25
const BLUE := Color("73f0db")
const HEAT := Color("ffc077")
const RED := Color("ff8a5e")
const METAL := Color("ba864d")
const INK := Color("222e37")
const LOOKS := [
	["Slate & copper", Color("71808b"), Color("a0a6a6"), Color("ffe6c3"), Color("26333d")],
	["Ivory & patina", Color("a6a698"), Color("c7b89b"), Color("fbe4bb"), Color("263a37")],
	["Midnight registry", Color("505b73"), Color("8893ae"), Color("ffd5c1"), Color("24263b")],
]
var surface: Dictionary = {}
var look := 0
var shell: Node3D
var actor: Node3D
var ghost: Node3D
var carried_raw: Node3D
var carried_key: Node3D
var rack_ore: Node3D
var bridge: Node3D
var beacons: Array[MeshInstance3D] = []
var main_clock_hand: MeshInstance3D
var copper_links: Array[MeshInstance3D] = []
var relay_links: Array[MeshInstance3D] = []
var screen: Node3D
var anchor_dial: Node3D
var plates: Dictionary = {}
var lamps: Dictionary = {}
var blockers: Array[Dictionary] = []
var front_faded := 0
var rewind_rings: Node3D
var slots: Array[MeshInstance3D] = []
var keylight: DirectionalLight3D
var world: WorldEnvironment


func p(cell: Vector2i, y := 0.0) -> Vector3:
	return Vector3(cell.x * TILE, y, cell.y * TILE)


func assemble() -> void:
	if shell != null:
		remove_child(shell)
		shell.queue_free()
	plates.clear()
	lamps.clear()
	blockers.clear()
	slots.clear()
	beacons.clear()
	copper_links.clear()
	relay_links.clear()
	shell = node(Vector3.ZERO, self)
	var stone: Color = LOOKS[look][1]
	var edge: Color = LOOKS[look][2]
	var deep: Color = LOOKS[look][4]
	box(Vector3(2.20, -1.45, -1.0), Vector3(16.3, 0.44, 8.5), deep)
	box(Vector3(2.20, -1.19, -1.0), Vector3(16.18, 0.14, 8.39), METAL.darkened(0.28))
	box(Vector3(2.20, -0.84, -1.0), Vector3(16.0, 0.56, 8.22), deep.lightened(0.05))
	for j in 10:
		box(Vector3(-4.99 + j * 1.6, -0.70, 3.117), Vector3(0.012, 0.21, 0.009), deep)
		box(Vector3(-4.22 + j * 1.6, -0.98, 3.119), Vector3(0.012, 0.20, 0.009), deep)
	box(Vector3(2.20, -0.84, 3.118), Vector3(15.96, 0.014, 0.009), deep)
	for c: Vector2i in Rules.PLACES:
		if c == Rules.SPAN: continue
		var accent := stone
		if c in [Rules.FIRE, Rules.WEST, Rules.ORE, Rules.KILN]: accent = stone.lerp(Color("b88b77"), 0.38)
		if c in [Rules.CALL, Rules.NORTH, Rules.ANCHOR]: accent = stone.lerp(Color("749caa"), 0.56)
		box(p(c, -0.37), Vector3(2.21, 0.71, 2.21), stone.darkened(0.23))
		for dx in [-0.55, 0.55]:
			for dz in [-0.55, 0.55]:
				box(p(c) + Vector3(dx, -0.04, dz), Vector3(1.08, 0.09, 1.08), accent)
				box(p(c) + Vector3(dx, 0.012, dz), Vector3(0.75, 0.012, 0.012), edge.darkened(0.13))
	for pair: Array in Rules.EDGES:
		if Rules.SPAN in pair: continue
		var a := p(pair[0], 0.035)
		var b := p(pair[1], 0.035)
		line_between(a.lerp(b, 0.18), b.lerp(a, 0.18), 0.052, METAL)
		var seam := a.lerp(b, 0.5)
		if not (Rules.FILTER in pair and Rules.KILN in pair):
			for shift: float in [-0.12, 0.12]:
				var offset := (b - a).cross(Vector3.UP).normalized() * shift
				drum(seam + offset, 0.046, 0.02, HEAT.darkened(0.29))
	# Back-wall arcade reads as the engine room's original masonry; no gameplay collision lives in its art.
	for x in [-4.6, -1.8, 1.0, 3.8, 6.6, 9.4]:
		box(Vector3(x, 1.09, -5.05), Vector3(2.78, 2.46, 0.22), deep.lightened(0.17))
		box(Vector3(x, 0.20, -4.91), Vector3(2.75, 0.14, 0.09), METAL.darkened(0.26))
		for j in 4:
			box(Vector3(x, 0.44 + j * 0.45, -4.928), Vector3(2.77, 0.019, 0.024), deep)
		var part := Factory.create(Factory.COMPONENT_ROOT + "Walls/RecipeGothicPointedRib.gd")
		part.recipe_parameters.merge({"dx": 1.32, "rise": 0.91, "radius": 0.095, "segments": 9}, true)
		part.position = Vector3(x, 1.32, -4.80)
		shell.add_child(part)
		for dx in [-1.28, 1.28]:
			box(Vector3(x + dx, 0.57, -4.82), Vector3(0.15, 1.48, 0.27), edge)
		for j in range(-3, 4):
			box(Vector3(x + j * 0.24, 1.29, -4.906), Vector3(0.09, 1.06, 0.035), stone.lerp(BLUE, 0.22))
	# Two foreground piers dissolve against a camera-to-station ray, independent of puzzle logic.
	for q: Vector3 in [Vector3(2.25, 0.90, 3.62), Vector3(8.03, 0.88, 1.52)]:
		var pier := node(q)
		var dims := Vector3(0.63, 1.94, 0.61)
		box(Vector3.ZERO, dims, stone, pier)
		for y in [-0.79, 0.79, 0.98]:
			box(Vector3(0, y, 0), Vector3(0.86, 0.14, 0.82), edge, pier)
		blockers.append({"root": pier, "bounds": AABB(q - Vector3(0.43, 1.0, 0.41), Vector3(0.86, 2.05, 0.82))})
	build_anchor()
	build_clock()
	build_cable([Vector3(-4.5, -0.48, 1.05), Vector3(-4.5, -0.48, 2.0), Vector3(-1.22, -0.48, 2.0),
		Vector3(-1.22, -0.48, 3.15), Vector3(2.90, -0.48, 3.15)], HEAT, copper_links)
	build_cable([Vector3(0.88, -0.48, -4.50), Vector3(3.51, -0.48, -4.50), Vector3(3.51, -0.48, -2.19),
		Vector3(6.75, -0.48, -2.19), Vector3(6.75, -0.48, -1.29)], BLUE, relay_links)
	build_plate(Rules.FIRE, "I  /  FURNACE", HEAT)
	build_plate(Rules.CALL, "II  /  BRIDGE", BLUE)
	build_kiln()
	build_span()
	build_screen()
	var exit := p(Rules.EXIT)
	box(exit + Vector3(0, 0.34, -0.27), Vector3(0.68, 0.67, 0.30), INK)
	box(exit + Vector3(0, 0.66, -0.27), Vector3(0.78, 0.16, 0.42), METAL)
	drum(exit + Vector3(0, 0.75, -0.27), 0.18, 0.08, BLUE, shell, true)
	box(exit + Vector3(0, 0.804, -0.27), Vector3(0.23, 0.035, 0.067), INK)
	stamp("EXIT SOCKET", exit + Vector3(0, 0.09, 0.70))
	actor = token(HEAT, false)
	ghost = token(BLUE, true)
	carried_raw = ore(Vector3(0.32, 0.61, 0.0), actor)
	carried_key = node(Vector3(0.31, 0.64, 0), actor)
	ring(Vector3.ZERO, 0.12, 0.034, HEAT, carried_key, true)
	box(Vector3(0.15, 0, 0), Vector3(0.19, 0.055, 0.064), HEAT, carried_key, true)
	box(Vector3(0.22, 0, 0.04), Vector3(0.055, 0.057, 0.097), HEAT, carried_key, true)


func build_clock() -> void:
	var body := node(Vector3(-1.78, 1.85, -4.45))
	body.rotation.x = PI * 0.5
	drum(Vector3.ZERO, 0.73, 0.22, INK, body)
	drum(Vector3(0, 0.125, 0), 0.64, 0.075, Color("d6ba86"), body)
	ring(Vector3(0, 0.153, 0), 0.62, 0.041, METAL, body)
	for i in 12:
		var rad := i * TAU / 12.0
		var notch := box(Vector3(cos(rad) * 0.50, 0.175, sin(rad) * 0.50),
			Vector3(0.12, 0.01, 0.04), INK, body)
		notch.rotation.y = -rad
	main_clock_hand = box(Vector3(0, 0.192, 0), Vector3(0.78, 0.025, 0.055), INK, body)
	drum(Vector3(0, 0.22, 0), 0.10, 0.06, METAL, body)


func build_cable(points: Array, color: Color, links: Array[MeshInstance3D]) -> void:
	for i in range(1, points.size()):
		var a: Vector3 = points[i - 1]
		var b: Vector3 = points[i]
		var beam := box((a + b) * 0.5, Vector3(0.077, a.distance_to(b), 0.077), color.darkened(0.62))
		beam.quaternion = Quaternion(Vector3.UP, (b - a).normalized())
		links.append(beam)
	for a: Vector3 in points:
		drum(a, 0.108, 0.13, METAL)


func build_anchor() -> void:
	var a := p(Rules.ANCHOR)
	drum(a + Vector3(0, 0.036, 0), 0.78, 0.055, INK)
	ring(a + Vector3(0, 0.078, 0), 0.71, 0.036, METAL)
	anchor_dial = node(a + Vector3(0, 0.091, 0))
	for i in 18:
		var angle := float(i) * TAU / 18.0
		var dash := box(Vector3(cos(angle) * 0.62, 0, sin(angle) * 0.62), Vector3(0.12, 0.048, 0.036), HEAT, anchor_dial)
		dash.rotation.y = -angle
	rewind_rings = node(a)
	for y in [0.17, 0.39, 0.67]:
		ring(Vector3(0, y, 0), 0.80 + y, 0.033, BLUE, rewind_rings, true)
	stamp("RECORD / REWIND", a + Vector3(0, 0.12, 0.83))
	# 22 notches on the south lip form a readable, bounded recording meter.
	for i in Rules.LIMIT:
		slots.append(box(a + Vector3(-0.96 + i * 0.09, 0.085, 1.05), Vector3(0.069, 0.045, 0.1), INK))


func build_plate(c: Vector2i, caption: String, hue: Color) -> void:
	var center := p(c)
	drum(center + Vector3(0, 0.04, 0), 0.72, 0.072, INK)
	var hand := node(center + Vector3(0, 0.16, 0))
	plates[c] = hand
	drum(Vector3.ZERO, 0.60, 0.14, METAL, hand)
	ring(Vector3(0, 0.071, 0), 0.53, 0.038, hue, hand)
	for x in [-0.26, 0.0, 0.26]:
		box(Vector3(x, 0.084, 0), Vector3(0.072, 0.024, 0.37), INK, hand)
	var beacon := node(center + Vector3(-0.73, 0.48, -0.58))
	drum(Vector3(0, -0.20, 0), 0.075, 0.46, METAL, beacon)
	lamps[c] = drum(Vector3.ZERO, 0.136, 0.17, hue, beacon, true)
	stamp(caption, center + Vector3(0, 0.105, 0.84))


func build_kiln() -> void:
	var r := p(Rules.ORE)
	box(r + Vector3(-0.61, 0.28, -0.43), Vector3(0.62, 0.54, 0.46), METAL.darkened(0.40))
	box(r + Vector3(-0.61, 0.57, -0.43), Vector3(0.70, 0.072, 0.57), METAL)
	rack_ore = ore(r + Vector3(-0.61, 0.73, -0.43), shell)
	stamp("ORE RACK", r + Vector3(0, 0.09, 0.71))
	var k := p(Rules.KILN)
	var root := node(k + Vector3(0.69, 0, -0.42))
	box(Vector3(0, 0.37, 0), Vector3(0.70, 0.73, 0.55), INK, root)
	box(Vector3(0, 0.81, 0), Vector3(0.54, 0.19, 0.54), METAL, root)
	drum(Vector3(0, 1.15, 0), 0.12, 0.57, INK, root)
	drum(Vector3(0, 1.46, 0), 0.19, 0.10, METAL, root)
	lamps["kiln"] = box(Vector3(0, 0.42, 0.29), Vector3(0.47, 0.23, 0.065), HEAT, root, true)
	for i in range(-2, 3):
		box(Vector3(i * 0.092, 0.43, 0.333), Vector3(0.026, 0.28, 0.039), INK, root)
	stamp("KILN", k + Vector3(0, 0.09, 0.73))


func build_screen() -> void:
	var a := p(Rules.FILTER, 0.0).lerp(p(Rules.KILN, 0.0), 0.5)
	screen = node(a)
	for x in [-0.80, 0.80]:
		box(Vector3(x, 0.61, 0), Vector3(0.12, 1.19, 0.17), METAL, screen)
	box(Vector3(0, 1.24, 0), Vector3(1.78, 0.095, 0.15), METAL, screen)
	for i in range(-6, 7):
		var ray := box(Vector3(i * 0.112, 0.60, 0), Vector3(0.027, 1.08, 0.025), BLUE, screen, true)
		ray.transparency = 0.56
	stamp("ORE SCREEN", p(Rules.FILTER, 0.06) + Vector3(0, 0, -0.47))


func build_span() -> void:
	var a := p(Rules.SPAN)
	for dz: float in [-1.55, 1.55]:
		box(a + Vector3(0, -0.45, dz), Vector3(2.18, 0.07, 0.21), METAL.darkened(0.30))
	drum(a + Vector3(0, -0.58, 0), 0.75, 0.27, METAL.darkened(0.19))
	drum(a + Vector3(0, -0.25, 0), 0.24, 0.65, INK)
	bridge = node(a)
	for i in 9:
		box(Vector3((i - 4) * 0.25, 0.025, 0), Vector3(0.232, 0.11, 0.93), METAL.darkened(0.10), bridge)
	for z: float in [-0.48, 0.48]:
		line_between(Vector3(-1.15, 0.64, z), Vector3(1.15, 0.64, z), 0.077, METAL, bridge)
		line_between(Vector3(-1.15, 0.01, z), Vector3(1.15, 0.01, z), 0.073, INK, bridge)
		for i in 6:
			var x := -1.1 + i * 0.37
			line_between(Vector3(x, 0.04 if i % 2 == 0 else 0.62, z),
				Vector3(x + 0.37, 0.62 if i % 2 == 0 else 0.04, z), 0.055, METAL, bridge)
	lamps["bridge"] = drum(Vector3(0, 0.72, -0.48), 0.16, 0.12, RED, bridge, true)
	for x: float in [-1.50, 1.50]:
		for z: float in [-0.82, 0.82]:
			var leg := a + Vector3(x, 0.30, z)
			drum(leg - Vector3(0, 0.17, 0), 0.070, 0.33, INK)
			beacons.append(drum(leg, 0.105, 0.14, RED, shell, true))
	stamp("LANDING", p(Rules.LAND, 0.09) + Vector3(0, 0, 0.77))


func draw_state(model: Rules) -> void:
	actor.position = p(model.player)
	ghost.visible = model.echo != Rules.GONE
	if ghost.visible:
		ghost.position = p(model.echo) + (Vector3(-0.36, 0, 0.26) if model.echo == model.player else Vector3.ZERO)
	carried_raw.visible = model.item == Rules.Item.RAW
	carried_key.visible = model.item == Rules.Item.KEY
	rack_ore.visible = model.item == Rules.Item.EMPTY
	anchor_dial.rotation.y = (-model.replay_tick if model.replay_tick >= 0 else model.tick) * 0.041
	main_clock_hand.rotation.y = -anchor_dial.rotation.y
	for cable in copper_links:
		cable.material_override = mat(HEAT if model.on_plate(Rules.FIRE) else HEAT.darkened(0.62), model.on_plate(Rules.FIRE))
	for cable in relay_links:
		cable.material_override = mat(BLUE if model.on_plate(Rules.CALL) else BLUE.darkened(0.62), model.on_plate(Rules.CALL))
	rewind_rings.visible = model.rewind > 0
	rewind_rings.scale = Vector3(1.0, 0.40 + float(model.rewind) / Rules.WARN, 1.0)
	for i in slots.size():
		var playing := model.replay_tick >= 0 and i == maxi(0, ceili(float(model.replay_tick) / Rules.STEP) - 1)
		slots[i].material_override = mat(HEAT if playing else BLUE if i < model.tape.size() - 1 else INK, playing)
	for c: Vector2i in [Rules.FIRE, Rules.CALL]:
		var down := model.on_plate(c)
		plates[c].position.y = 0.078 if down else 0.16
		lamps[c].material_override = mat((HEAT if c == Rules.FIRE else BLUE) if down else INK, down)
	lamps.kiln.material_override = mat(HEAT if model.firing > 0 else Color("9a5946"), model.firing > 0)
	var warning := model.span == Rules.SpanMode.WARNING or model.span == Rules.SpanMode.CLOSING
	lamps.bridge.material_override = mat(RED if warning else BLUE if model.span_walkable() else INK, warning or model.span_walkable())
	for lamp in beacons:
		lamp.material_override = lamps.bridge.material_override
	bridge.rotation.y = 0.0 if model.span_walkable() else PI * 0.5


func cutaway(view: Camera3D, model: Rules) -> void:
	front_faded = 0
	for piece: Dictionary in blockers:
		var faded := false
		for target: Vector2i in [model.player, model.echo, Rules.ANCHOR, Rules.KILN, Rules.LAND, Rules.SPAN, Rules.EXIT]:
			if target == Rules.GONE: continue
			for at: Vector3 in [p(target, 0.51), p(target, 0.13) + Vector3(0, 0, 0.70)]:
				var toward_camera := at + view.global_basis.z * 42.0
				if (piece.bounds as AABB).intersects_segment(toward_camera, at) != null:
					faded = true
					break
			if faded: break
		if faded: front_faded += 1
		for mi: MeshInstance3D in piece.root.get_children():
			if faded:
				if not mi.has_meta("opaque"):
					mi.set_meta("opaque", mi.material_override)
				var cut := cut_material()
				mi.material_override = cut
			elif mi.has_meta("opaque"):
				mi.material_override = mi.get_meta("opaque")
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF if faded else GeometryInstance3D.SHADOW_CASTING_SETTING_ON


func cut_material() -> StandardMaterial3D:
	if not surface.has("cut"):
		var cut := StandardMaterial3D.new()
		cut.albedo_color = Color(0.66, 0.76, 0.80, 0.18)
		cut.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		cut.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		surface["cut"] = cut
	return surface["cut"]


func token(color: Color, is_echo: bool) -> Node3D:
	# A lighthouse-shaped board token, distinct from the game's formal human cast.
	var base := node(Vector3.ZERO)
	drum(Vector3(0, 0.10, 0), 0.30, 0.13, INK if not is_echo else color, base, is_echo)
	drum(Vector3(0, 0.25, 0), 0.18, 0.18, METAL if not is_echo else color, base, is_echo)
	var core := box(Vector3(0, 0.52, 0), Vector3(0.33, 0.43, 0.33), color, base, true)
	if is_echo: core.transparency = 0.30
	for x in [-0.19, 0.19]:
		for z in [-0.19, 0.19]:
			box(Vector3(x, 0.54, z), Vector3(0.056, 0.52, 0.056), color if is_echo else INK, base, is_echo)
	var lid := drum(Vector3(0, 0.81, 0), 0.25, 0.13, color if is_echo else INK, base, is_echo)
	lid.scale.y = 0.72
	drum(Vector3(0, 0.91, 0), 0.075, 0.10, color, base, true)
	return base


func ore(at: Vector3, parent: Node3D) -> Node3D:
	var n := node(at, parent)
	for i in 3:
		var body := box(Vector3(i * 0.09 - 0.08, 0, 0.027 * i), Vector3(0.15, 0.12 + i * 0.021, 0.16), RED.darkened(0.31 + i * 0.06), n)
		body.rotation = Vector3(i * 0.34, i * 0.55, i * 0.24)
	return n


func mat(color: Color, luminous := false) -> Material:
	var key := "%s:%s" % [color, luminous]
	if not surface.has(key):
		var m := ShaderMaterial.new()
		m.shader = HallFinish
		m.set_shader_parameter("pigment", color)
		m.set_shader_parameter("grain", 0.065 if not luminous else 0.0)
		m.set_shader_parameter("toon_on", true)
		m.set_shader_parameter("toon_strength", 0.88)
		m.set_shader_parameter("emission_gain", 0.47 if luminous else 0.0)
		surface[key] = m
	return surface[key]


func node(at: Vector3, parent: Node3D = null) -> Node3D:
	var n := Node3D.new()
	(shell if parent == null else parent).add_child(n)
	n.position = at
	return n


func mesh_at(mesh: Mesh, at: Vector3, color: Color, parent: Node3D, luminous: bool) -> MeshInstance3D:
	var n := MeshInstance3D.new()
	n.mesh = mesh
	n.material_override = mat(color, luminous)
	(shell if parent == null else parent).add_child(n)
	n.position = at
	return n


func box(at: Vector3, size: Vector3, color: Color, parent: Node3D = null, luminous := false) -> MeshInstance3D:
	var b := BoxMesh.new()
	b.size = size
	return mesh_at(b, at, color, parent, luminous)


func drum(at: Vector3, radius: float, length: float, color: Color, parent: Node3D = null, luminous := false) -> MeshInstance3D:
	var drum_mesh := CylinderMesh.new()
	drum_mesh.top_radius = radius
	drum_mesh.bottom_radius = radius
	drum_mesh.radial_segments = 18
	drum_mesh.rings = 0
	drum_mesh.height = length
	return mesh_at(drum_mesh, at, color, parent, luminous)


func ring(at: Vector3, radius: float, thick: float, color: Color, parent: Node3D = null, luminous := false) -> MeshInstance3D:
	var torus := TorusMesh.new()
	torus.inner_radius = radius - thick
	torus.outer_radius = radius + thick
	torus.rings = 24
	torus.ring_segments = 8
	return mesh_at(torus, at, color, parent, luminous)


func line_between(a: Vector3, b: Vector3, width: float, color: Color, parent: Node3D = null) -> void:
	var beam := box((a + b) * 0.5, Vector3(width, a.distance_to(b), width), color, parent)
	beam.quaternion = Quaternion(Vector3.UP, (b - a).normalized())


func stamp(caption: String, at: Vector3) -> void:
	var mark := Label3D.new()
	mark.text = caption
	mark.font_size = 52
	mark.pixel_size = 0.0045
	mark.outline_size = 0
	mark.modulate = Color("fff0ce")
	mark.no_depth_test = false
	mark.rotation.x = -PI * 0.5
	box(at - Vector3(0, 0.025, 0), Vector3(1.70, 0.05, 0.28), INK)
	shell.add_child(mark)
	mark.position = at + Vector3(0, 0.006, 0)
