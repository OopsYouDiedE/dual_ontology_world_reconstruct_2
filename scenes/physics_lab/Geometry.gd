extends RefCounted
## Room-specific geometry built from the same limestone/graphite kit.

const EngineModel = preload("res://scenes/physics_lab/Model.gd")
const CHALK := Color("d9d9d4")
const PORCELAIN := Color("e9e8e3")
const STONE := Color("babdbd")
const LEAD := Color("414950")
const SEAM := Color("687077")
const ALLOY := Color("8e9a99")
const SAND := Color("a39a8f")
const WITNESS := Color("c8d3cf")
const INK := Color("363d42")
var root: Node3D
var moving: Dictionary
var materials: Dictionary = {}


func build(parent: Node3D, room: int) -> void:
	root = parent
	moving = {}
	if room not in [2, 3, 5, 6]:
		floor_panel(0, 0, 0, 11.0, 7.0)
	wall(Vector3(0, 1.45, -3.5), 11.0, 3.1, 0.24)
	wall(Vector3(-5.45, 1.12, -0.15), 0.19, 2.45, 6.55)
	for x: float in [-4.8, -3.2, -1.6, 0.0, 1.6, 3.2, 4.8]:
		box(Vector3(x, 1.38, -3.37), Vector3(0.015, 2.97, 0.012), SEAM)
	for x: float in [-4.2, 0.0, 4.2]:
		box(Vector3(x, 2.78, -3.36), Vector3(0.85, 0.034, 0.05), PORCELAIN)
	label("PLATE %02d    /    EXPERIMENTAL GALLERIES" % (room + 1), Vector3(0, 2.25, -3.34), 0.116)
	match room:
		0: optics()
		1: waves()
		2: observer()
		3: portals()
		4: sorter()
		5: shaft()
		6: alchemy()
		7: induction()
		8: clocks()
		9: tape()


func mat(color: Color) -> StandardMaterial3D:
	if not materials.has(color):
		var m := StandardMaterial3D.new()
		m.albedo_color = color
		m.roughness = 0.83
		if color.a < 1.0:
			m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			m.cull_mode = BaseMaterial3D.CULL_DISABLED
		materials[color] = m
	return materials[color]


func piece(mesh: Mesh, at: Vector3, color: Color, parent: Node3D = null) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat(color)
	(root if parent == null else parent).add_child(mi)
	mi.position = at
	if color.a < 1.0: mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return mi


func box(at: Vector3, size: Vector3, color: Color, parent: Node3D = null) -> MeshInstance3D:
	var mesh := BoxMesh.new()
	mesh.size = size
	return piece(mesh, at, color, parent)


func node(at: Vector3, parent: Node3D = null) -> Node3D:
	var n := Node3D.new()
	(root if parent == null else parent).add_child(n)
	n.position = at
	return n


func sphere(at: Vector3, r: float, color: Color, parent: Node3D = null) -> MeshInstance3D:
	var mesh := SphereMesh.new()
	mesh.radius = r
	mesh.height = 2.0 * r
	mesh.radial_segments = 14
	mesh.rings = 8
	return piece(mesh, at, color, parent)


func cylinder(at: Vector3, radius: float, length: float, color: Color, parent: Node3D = null) -> MeshInstance3D:
	var mesh := CylinderMesh.new()
	mesh.top_radius = radius
	mesh.bottom_radius = radius
	mesh.height = length
	mesh.radial_segments = 20
	return piece(mesh, at, color, parent)


func line(a: Vector3, b: Vector3, thickness: float, color: Color, parent: Node3D = null) -> MeshInstance3D:
	var d := b - a
	var mi := cylinder((a + b) / 2.0, thickness, maxf(d.length(), 0.001), color, parent)
	if d.length_squared() > 0.00001: mi.quaternion = Quaternion(Vector3.UP, d.normalized())
	return mi


func ring(at: Vector3, radius: float, thickness: float, color: Color, parent: Node3D = null) -> MeshInstance3D:
	var mesh := TorusMesh.new()
	mesh.inner_radius = radius - thickness
	mesh.outer_radius = radius + thickness
	mesh.ring_segments = 32
	mesh.rings = 8
	return piece(mesh, at, color, parent)


func label(text: String, at: Vector3, height: float, parent: Node3D = null) -> Label3D:
	var l := Label3D.new()
	l.text = text
	l.font_size = 64
	l.pixel_size = height / 64.0
	l.outline_size = 0
	l.modulate = INK
	(root if parent == null else parent).add_child(l)
	l.position = at
	return l


func floor_panel(x: float, y: float, z: float, width: float, depth: float) -> void:
	box(Vector3(x, y - 0.23, z), Vector3(width, 0.46, depth), CHALK)
	box(Vector3(x, y - 0.38, z), Vector3(width + 0.018, 0.024, depth + 0.018), SEAM)
	for u in range(1, ceili(width / 1.1)):
		var xx := x - width / 2.0 + u * 1.1
		box(Vector3(xx, y + 0.001, z), Vector3(0.016, 0.004, depth), STONE)
	for v in range(1, ceili(depth / 1.1)):
		var zz := z - depth / 2.0 + v * 1.1
		box(Vector3(x, y + 0.002, zz), Vector3(width, 0.004, 0.016), STONE)


func wall(at: Vector3, width: float, height: float, depth: float) -> void:
	box(at, Vector3(width, height, depth), CHALK)
	box(at + Vector3(0, height / 2.0, 0), Vector3(width + 0.042, 0.055, depth + 0.052), PORCELAIN)


func portal_frame(at: Vector3, span: float, height: float, parent: Node3D = null) -> void:
	for sign_: float in [-1.0, 1.0]:
		box(at + Vector3(sign_ * span / 2.0, height / 2.0, 0), Vector3(0.22, height, 0.27), PORCELAIN, parent)
		box(at + Vector3(sign_ * (span / 2.0 - 0.12), height / 2.0, 0), Vector3(0.045, height, 0.23), LEAD, parent)
	box(at + Vector3(0, height, 0), Vector3(span + 0.23, 0.20, 0.31), PORCELAIN, parent)
	box(at + Vector3(0, height - 0.12, 0.015), Vector3(span - 0.2, 0.045, 0.27), LEAD, parent)
	box(at, Vector3(span, 0.045, 0.38), SEAM, parent)


func rails(a: Vector3, b: Vector3, span: float) -> void:
	var side := (b - a).cross(Vector3.UP).normalized()
	for i: float in [-1.0, 1.0]:
		var offset := side * i * span / 2.0
		line(a + offset, b + offset, 0.029, LEAD)
	for i in range(13):
		var p := a.lerp(b, i / 12.0)
		line(p - side * span / 2.0, p + side * span / 2.0, 0.014, SEAM)


func pad(at: Vector3, text: String, parent: Node3D = null) -> Node3D:
	var n := node(at, parent)
	box(Vector3(0, 0.043, 0), Vector3(0.91, 0.087, 0.76), LEAD, n)
	box(Vector3(0, 0.112, 0), Vector3(0.78, 0.055, 0.65), PORCELAIN, n)
	var sign_ := label(text, Vector3(0, 0.146, 0.04), 0.19, n)
	sign_.rotation.x = -PI / 2.0
	return n


func person(at: Vector3, tint: Color = STONE) -> Node3D:
	var n := node(at)
	sphere(Vector3(0, 1.42, 0), 0.15, tint, n)
	box(Vector3(0, 1.04, 0), Vector3(0.37, 0.47, 0.23), tint, n)
	for x: float in [-0.10, 0.10]:
		line(Vector3(x, 0.13, 0.035), Vector3(x, 0.86, 0), 0.075, tint, n)
	for x: float in [-0.27, 0.27]:
		line(Vector3(x, 0.75, 0.04), Vector3(x * 0.68, 1.23, 0), 0.060, tint, n)
	return n


func optics() -> void:
	rails(Vector3(-4.8, 0.065, 0), Vector3(4.8, 0.065, 0), 0.91)
	line(Vector3(0, 0.063, 0), Vector3(0, 0.063, 2.55), 0.019, SEAM)
	for i in range(3):
		var pane := node(Vector3((i - 1) * 2.25, 0, 0))
		pane.rotation.y = PI / 2.0
		portal_frame(Vector3.ZERO, 1.95, 2.15, pane)
		box(Vector3(0, 1.08, 0), Vector3(1.70, 2.00, 0.035), Color("91a29a35"), pane)
		var axis := node(Vector3(0, 1.10, 0.052), pane)
		for k in range(-2, 3):
			line(Vector3(k * 0.24, -0.49, 0.0), Vector3(k * 0.24, 0.49, 0.0), 0.013, SEAM, axis)
		axis.rotation.z = i * PI / 4.0
		if i == 1:
			moving.pane = pane
			moving.axis = axis
		label(["0°", "AXIS", "90°"][i], Vector3(0, 2.38, 0.0), 0.21, pane)
	box(Vector3(-4.55, 0.57, 0), Vector3(0.55, 1.12, 0.85), LEAD)
	box(Vector3(4.43, 0.81, 0), Vector3(0.28, 1.60, 1.65), SEAM)
	moving.detector = box(Vector3(4.58, 0.81, 0), Vector3(0.025, 1.21, 1.29), LEAD)
	box(Vector3(3.9, 0.57, 2.05), Vector3(1.75, 1.12, 1.02), PORCELAIN)
	box(Vector3(3.9, 1.09, 2.05), Vector3(1.80, 0.028, 1.06), SEAM)
	label("DETECTOR", Vector3(3.9, 0.72, 2.58), 0.14)
	line(Vector3(-4.27, 1.08, 0), Vector3(2.24, 1.08, 0), 0.015, ALLOY)
	moving.beam = line(Vector3(2.25, 1.08, 0), Vector3(4.30, 1.08, 0), 0.032, WITNESS)
	portal_frame(Vector3(3.83, 0, -2.05), 1.60, 1.03)
	moving.optic_gate = box(Vector3(3.83, 0.49, -2.05), Vector3(1.50, 0.94, 0.15), SEAM)


func waves() -> void:
	# Two identical lanes expose the reflector offset side by side.
	for z: float in [-1.27, 1.27]:
		rails(Vector3(-3.8, 0.035, z), Vector3(3.9, 0.035, z), 1.40)
		portal_frame(Vector3(3.74, 0.0, z), 1.64, 1.84)
		var reflector := box(Vector3(-3.45, 0.82, z), Vector3(0.22, 1.63, 1.56), PORCELAIN)
		if z > 0.0: moving.reflector = reflector
	for x: float in [0.0, 1.0]:
		pad(Vector3(x, 0.008, 2.55), "N" if x == 0.0 else "A")
	moving.wave = []
	for j in range(2):
		for i in range(41):
			moving.wave.append(box(Vector3((i - 20) * 0.175, 0.12, -1.27 + 2.54 * j), Vector3(0.039, 0.024, 1.30), ALLOY))
	moving.marker = person(Vector3(0, 0, 2.55), SAND)
	label("REFERENCE", Vector3(-2.1, 0.22, -2.09), 0.14)
	label("ADJUSTABLE", Vector3(-2.1, 0.22, 2.15), 0.14)


func observer() -> void:
	floor_panel(-3.3, 0, 0, 4.4, 7.0)
	floor_panel(3.3, 0, 0, 4.4, 7.0)
	floor_panel(0, -1.23, 0, 2.2, 7.0)
	for x: float in [-1.12, 1.12]:
		box(Vector3(x, 0.01, 0), Vector3(0.047, 0.022, 6.95), LEAD)
		for z: float in [-2.0, 2.0]:
			box(Vector3(x, 0.54, z), Vector3(0.14, 1.06, 0.70), PORCELAIN)
	var deck := node(Vector3.ZERO)
	box(Vector3(0, 0.01, 0), Vector3(2.20, 0.22, 2.30), SEAM, deck)
	for i in range(12):
		box(Vector3(-1.04 + i * 0.19, 0.134, 0), Vector3(0.13, 0.031, 2.18), PORCELAIN, deck)
	moving.deck = deck
	moving.countdown = []
	for i in range(8):
		moving.countdown.append(box(Vector3(-1.45, 0.038, -0.95 + 0.27 * i), Vector3(0.32, 0.06, 0.115), LEAD))
	moving.gaze = person(Vector3(-3.0, 0.0, 2.2), SAND)
	moving.cross = person(Vector3(-3.25, 0.0, 0), ALLOY)
	moving.eye = sphere(Vector3(-3.0, 1.54, 2.2), 0.07, LEAD)
	moving.sight = line(Vector3(-3, 1.54, 2.2), Vector3(0, 0.04, 0), 0.012, SEAM)
	pad(Vector3(3.1, 0, 0), "II")
	portal_frame(Vector3(3.1, 0, -2.14), 1.6, 2.16)
	moving.twin = box(Vector3(3.1, 0.99, -2.15), Vector3(1.43, 1.96, 0.15), SEAM)
	label("LINKED SHUTTER", Vector3(3.1, 2.40, -2.14), 0.155)
	label("OBSERVATION BAY", Vector3(-3.1, 0.42, 2.87), 0.17)


func portals() -> void:
	floor_panel(0, 0, 0, 9.5, 6.5)
	floor_panel(-1.9, 2.0, -1.85, 5.7, 2.45)
	for i in range(8):
		box(Vector3(3.18 - i * 0.30, 0.125 + i * 0.125, -1.95), Vector3(0.32, 0.25 + i * 0.25, 1.36), CHALK)
		box(Vector3(3.18 - i * 0.30, 0.251 + i * 0.25, -1.95), Vector3(0.31, 0.025, 1.36), SEAM)
	moving.visits = []
	moving.arcs = []
	var p := EngineModel.PORTALS
	for i in range(8):
		var at: Vector3 = p[i]
		var n := node(at)
		var span := 1.16 if i < 4 else 0.91
		portal_frame(Vector3.ZERO, span, 1.77 if i < 4 else 1.46, n)
		portal_frame(Vector3(0, 0, -0.35), span * 0.83, 1.55 if i < 4 else 1.24, n)
		pad(Vector3(0, 0.02, 0.56), str(i % 4 + 1), n)
		for mark in range(i % 4 + 1):
			box(Vector3(-0.19 + 0.12 * mark, 0.14, 0.81), Vector3(0.043, 0.013, 0.135), LEAD, n)
		moving.visits.append(n)
		moving.arcs.append(ring(at + Vector3(0, 0.15, 0.56), 0.50, 0.019, LEAD))
		label("%s / %d" % ["I" if i < 4 else "II", i % 4 + 1], Vector3(0, 1.98 if i < 4 else 1.66, 0.11), 0.16, n)
	moving.traveler = person(p[0] + Vector3(0, 0, 0.55), SAND)
	moving.probe = sphere(Vector3.ZERO, 0.12, WITNESS)
	moving.portals = p


func sorter() -> void:
	for side: float in [-1.0, 1.0]:
		var x := side * 2.44
		box(Vector3(x, 0.15, -0.35), Vector3(4.25, 0.29, 3.65), STONE)
		for z: float in [-2.16, 1.48]:
			box(Vector3(x, 0.45, z), Vector3(4.25, 0.62, 0.09), PORCELAIN)
		box(Vector3(side * 4.57, 0.45, -0.35), Vector3(0.10, 0.63, 3.65), PORCELAIN)
		label("RESERVOIR " + ("I" if side < 0.0 else "II"), Vector3(x, 0.71, 1.56), 0.16)
	for z: float in [-1.43, 0.74]:
		box(Vector3(0, 0.78, z), Vector3(0.24, 1.6, 1.45), PORCELAIN)
	var gate := node(Vector3(0, 0.23, -0.35))
	box(Vector3(0, 0.52, 0), Vector3(0.18, 1.05, 0.71), LEAD, gate)
	for z: float in [-0.21, -0.06, 0.09, 0.24]:
		box(Vector3(0.102, 0.52, z), Vector3(0.025, 0.98, 0.018), STONE, gate)
	moving.gate = gate
	moving.ball = sphere(Vector3(-3.0, 0.50, -0.35), 0.22, SEAM)
	moving.reservoir = []
	for i in range(12):
		var sign_ := -1.0 if i < 6 else 1.0
		moving.reservoir.append(sphere(Vector3(sign_ * (0.56 + (i % 3) * 0.82), 0.47, 0.73 - (i % 6 / 3) * 0.7), 0.15, ALLOY))
	moving.counter = label("", Vector3(0, 0.37, 2.71), 0.18)
	pad(Vector3(0, 0.0, 2.13), "MEM")
	portal_frame(Vector3(3.70, 0.0, -2.62), 1.38, 1.92)
	moving.pressure_gate = box(Vector3(3.70, 0.90, -2.63), Vector3(1.23, 1.78, 0.13), SEAM)


func shaft() -> void:
	floor_panel(-2.75, 0, 0, 5.5, 6.7)
	floor_panel(3.80, 3.0, -0.55, 3.3, 3.7)
	floor_panel(0.25, -1.05, -0.55, 3.8, 3.7)
	for x: float in [-1.0, 1.7]:
		line(Vector3(x, -1.0, -1.80), Vector3(x, 4.3, -1.80), 0.038, LEAD)
		for i in range(10):
			var y := i * 0.49 - 0.5
			line(Vector3(x - 0.35, y, -1.82), Vector3(x, y + 0.20, -1.82), 0.017, SEAM)
			line(Vector3(x + 0.35, y, -1.82), Vector3(x, y + 0.20, -1.82), 0.017, SEAM)
	portal_frame(Vector3(3.5, 3.0, -1.6), 1.57, 1.90)
	var cage := node(Vector3(0.96, 0.0, -0.25))
	box(Vector3(0, -0.109, 0), Vector3(2.33, 0.218, 2.20), SEAM, cage)
	for x: float in [-1.12, 1.12]:
		box(Vector3(x, 0.74, -0.98), Vector3(0.075, 1.45, 0.075), LEAD, cage)
		box(Vector3(x, 1.02, 0), Vector3(0.07, 0.072, 1.96), LEAD, cage)
	box(Vector3(0, 1.47, -0.98), Vector3(2.3, 0.075, 0.075), LEAD, cage)
	moving.cage = cage
	label("FIELD-FREE POCKET", Vector3(1.00, 0.23, 2.87), 0.175)
	pad(Vector3(0.95, -0.97, 1.45), "VOID")
	for z: float in [1.05, 2.03]:
		line(Vector3(0.96, 0, z), Vector3(0.96, 4.3, z), 0.020, ALLOY)
	var sign_ := node(Vector3(-3.7, 0.15, 1.95))
	moving.arrow = label("↓", Vector3(0, 1.26, 0.04), 0.59, sign_)
	pad(Vector3(-2.7, 0, 0.6), "I")
	pad(Vector3(3.35, 3, 0.56), "II")
	moving.loads = []
	for i in range(2):
		var n := node(Vector3(-3.32 - i * 0.75, 0.26, 0.73))
		box(Vector3.ZERO, Vector3(0.52, 0.52, 0.51), ALLOY if i == 0 else SAND, n)
		label("A" if i == 0 else "B", Vector3(0, 0.0, 0.259), 0.24, n)
		moving.loads.append(n)


func alchemy() -> void:
	floor_panel(-3.14, 0, 0, 4.72, 7.0)
	floor_panel(3.87, 0, 0, 3.26, 7.0)
	floor_panel(0.71, -1.23, 0, 3.15, 7.0)
	var dock := node(Vector3(0.71, 0, 0.0))
	box(Vector3(0, -0.095, 0), Vector3(3.05, 0.19, 1.57), LEAD, dock)
	for i in range(9):
		box(Vector3(-1.38 + i * 0.345, 0.012, 0), Vector3(0.29, 0.028, 1.50), PORCELAIN, dock)
	moving.drawbridge = dock
	portal_frame(Vector3(3.32, 0, -0.9), 1.54, 2.10)
	rails(Vector3(-4.76, 0.075, -2.07), Vector3(-2.0, 0.075, 2.25), 0.51)
	moving.forms = []
	moving.latches = []
	for i in range(3):
		var at := Vector3(-4.18 + i * 0.93, 0.0, -1.22 + i * 1.37)
		var n := node(at)
		box(Vector3(0, 0.21, 0), Vector3(0.86, 0.42, 0.87), CHALK, n)
		var d := ring(Vector3(0, 0.445, 0), 0.271, 0.047, [LEAD, ALLOY, SAND][i], n)
		if i == 0: d.rotation.x = PI / 2.0
		if i == 2:
			for j in range(3): box(Vector3(0.25 - j * 0.25, 0.57, -0.26), Vector3(0.022, 0.26, 0.022), SEAM, n)
		label(["FIELD", "BATH", "KILN"][i], Vector3(0, 0.23, 0.463), 0.14, n)
		var gate := box(Vector3(2.78, 0.85, 0.22 - i * 0.36), Vector3(0.13, 1.71, 0.27), SEAM)
		moving.latches.append(gate)
		moving.forms.append(at + Vector3(0, 0.77, 0))
	moving.stock = box(Vector3(-4.7, 0.32, -1.95), Vector3(0.52, 0.52, 0.52), STONE)
	moving.form_label = label("RAW", Vector3(0, 0, 0.27), 0.135, moving.stock)


func induction() -> void:
	rails(Vector3(-3.5, 0.060, -2.5), Vector3(-3.5, 0.060, 2.5), 1.24)
	for i in range(9):
		var hoop := ring(Vector3(-3.5, 1.0, (i - 4) * 0.17), 0.78, 0.034, LEAD)
		hoop.rotation.x = PI / 2.0
	moving.magnet = box(Vector3(-3.5, 0.86, -2.5), Vector3(0.60, 0.58, 0.78), SAND)
	box(Vector3(0, 0.19, 0.20), Vector3(0.606, 0.037, 0.032), LEAD, moving.magnet)
	label("PICKUP COIL", Vector3(-3.5, 1.95, 0), 0.16)
	box(Vector3(1.45, 0.05, 0), Vector3(4.75, 0.09, 4.35), STONE)
	for x in range(7):
		for z in range(6):
			var at := Vector3(-0.62 + 0.70 * x, 0.106, -1.82 + 0.72 * z)
			ring(at, 0.074, 0.012, SEAM)
	moving.hall = label("", Vector3(1.34, 0.38, 2.35), 0.21)
	moving.probe = sphere(Vector3(1.46, 0.27, 1.45), 0.17, LEAD)
	portal_frame(Vector3(4.40, 0.0, -2.65), 1.35, 1.93)
	moving.gate = box(Vector3(4.40, 0.89, -2.66), Vector3(1.23, 1.78, 0.14), SEAM)


func clocks() -> void:
	rails(Vector3(-2.0, 0.06, -1.56), Vector3(2.0, 0.06, -1.56), 0.58)
	for x: float in [-2.0, 2.0]:
		box(Vector3(x, 0.49, -1.56), Vector3(0.42, 0.98, 0.53), SEAM)
		box(Vector3(x, 1.09, -1.56), Vector3(0.78, 0.38, 0.46), PORCELAIN)
		label("A" if x < 0.0 else "B", Vector3(x, 1.09, -1.32), 0.25)
	moving.signal_a = sphere(Vector3(-2.0, 1.12, -1.49), 0.124, WITNESS)
	moving.signal_b = sphere(Vector3(2.0, 1.12, -1.61), 0.124, SAND)
	moving.ruler = box(Vector3(0, 0.34, -0.73), Vector3(4.0, 0.085, 0.13), LEAD)
	for x in range(-4, 5): box(Vector3(x * 0.5, 0.36, -0.59), Vector3(0.015, 0.01, 0.12), SEAM)
	pad(Vector3(-1.7, 0, 1.41), "ECHO")
	pad(Vector3(1.7, 0, 1.41), "NOW")
	moving.player = person(Vector3(-1.7, 0.14, 1.41), SAND)
	moving.echo = person(Vector3.ZERO, Color("819e999f"))
	for i in range(4):
		for x: float in [-0.31, 0.31]:
			box(Vector3(x, 0.29 + i * 0.30, 0.13), Vector3(0.033, 0.122, 0.037), LEAD, moving.echo)
	label("ECHO", Vector3(0, 1.80, 0.21), 0.16, moving.echo)
	moving.order_a = label("—", Vector3(-2, 1.57, -1.56), 0.20)
	moving.order_b = label("—", Vector3(2, 1.57, -1.56), 0.20)
	portal_frame(Vector3(3.95, 0, -0.34), 1.38, 1.92)
	moving.gate = box(Vector3(3.95, 0.88, -0.36), Vector3(1.22, 1.76, 0.13), SEAM)


func tape() -> void:
	rails(Vector3(-4.58, 0.074, 0.2), Vector3(4.57, 0.074, 0.2), 1.15)
	moving.writer = node(Vector3(0, 0, 0.20))
	portal_frame(Vector3.ZERO, 1.42, 1.67, moving.writer)
	moving.writer.rotation.y = PI / 2.0
	box(Vector3(0.12, 1.19, 0), Vector3(1.10, 0.20, 0.19), LEAD, moving.writer)
	moving.cells = []
	moving.bits = []
	moving.top_bits = []
	for i in range(5):
		var x := tape_x(i)
		pad(Vector3(x, 0.020, 0.2), "%02d" % i)
		var n := node(Vector3(x, 0.28, 0.20))
		box(Vector3.ZERO, Vector3(0.57, 0.47, 0.63), PORCELAIN, n)
		moving.cells.append(n)
		moving.bits.append(label("", Vector3(0, 0.015, 0.319), 0.30, n))
		var top_digit := label("", Vector3(0.0, 0.242, 0.11), 0.28, n)
		top_digit.rotation.x = -PI / 2.0
		moving.top_bits.append(top_digit)
	moving.cursor = ring(Vector3(tape_x(0), 0.081, 0.2), 0.48, 0.025, LEAD)
	label("FEED STOCK", Vector3(-4.02, 0.25, 1.60), 0.15)
	pad(Vector3(-4.02, 0, 2.13), "0/1")
	label("BLANK / HALT", Vector3(tape_x(4), 0.23, 1.35), 0.15)
	pad(Vector3(tape_x(4), 0, 2.10), "END")
	moving.parity = label("Q0", Vector3(0, 2.24, 0.49), 0.24)


static func tape_x(i: int) -> float:
	return (i - 2.0) * 1.64


func update(model: EngineModel) -> void:
	var s: Dictionary = model.s
	match model.room:
		0:
			moving.pane.position.z = 0.0 if s.inserted else 2.13
			moving.axis.rotation.z = deg_to_rad(s.angle)
			moving.beam.visible = s.power > 0.0
			moving.optic_gate.position.y = 1.76 if s.passed else 0.49
			moving.detector.material_override = mat(WITNESS if s.power > 0.0 else LEAD)
		1:
			moving.reflector.position.x = -3.45 + s.mirror_offset
			moving.marker.position.x = s.zone
			for i in range(moving.wave.size()):
				var bar: MeshInstance3D = moving.wave[i]
				var offset: float = s.mirror_offset if i >= 41 else 0.0
				bar.position.y = 0.13 + 0.105 * EngineModel.envelope(bar.position.x, offset) * sin(model.tick * TAU / 60.0)
				bar.scale.y = 1.0 if s.warning == 0 or model.tick % 16 < 8 else 2.0
		2:
			moving.deck.position = Vector3(0, 0, 0) if s.bridge else Vector3(0, -1.24, -1.39 + s.phase * 2.78)
			for i in range(8):
				var notch: MeshInstance3D = moving.countdown[i]
				notch.material_override = mat(STONE if s.warning > 0 and i < floori(s.warning / 5.0) else LEAD)
				notch.position.y = 0.049 if s.warning > 0 else 0.038
			moving.eye.material_override = mat(WITNESS if s.lit else LEAD)
			moving.sight.visible = s.hits > 0
			moving.twin.position.y = 0.99 if s.twin_shutter == 1 else 2.84
			moving.gaze.rotation.y = 2.20 if s.gaze else 0.0
			moving.cross.position.x = 3.08 if s.partner == 1 else (-3.25 if s.crossing < 0 else lerpf(-3.25, 3.08, s.crossing / 80.0))
		3:
			var where_: int = s.sector + 4 * s.layer
			moving.traveler.position = moving.portals[where_] + Vector3(0, 0.0, 0.56)
			moving.traveler.rotation.y = deg_to_rad(s.yaw)
			for i in range(8): moving.arcs[i].visible = i == where_
			moving.probe.visible = s.probe_layer >= 0
			if s.probe_layer >= 0: moving.probe.position = moving.portals[s.probe_sector + 4 * s.probe_layer] + Vector3(0, 0.93, 0.58)
		4:
			moving.gate.position.y = 1.34 if s.gate > 0 else 0.23
			var speed := EngineModel.speed_class(s.sample)
			var phase: float = s.age / 60.0
			var x: float = lerpf(-2.0 - 2.0 * speed, 0.0, minf(phase, 1.0))
			if phase > 1.0: x = ((1.0 if s.transmitted else -1.0) * (2.0 + 2.0 * speed)) * (phase - 1.0)
			moving.ball.position = Vector3(x, 0.54 + absf(sin(s.age * 0.067)) * 0.41, -0.35)
			moving.ball.material_override = mat(LEAD if speed == 1 else SAND)
			for i in range(12): moving.reservoir[i].visible = i % 6 < (s.left if i < 6 else s.right)
			moving.counter.text = "%02d  :  %02d  /  SAMPLE ENERGY" % [s.energy_l, s.energy_r]
			moving.pressure_gate.position.y = 2.83 if s.passed else 0.90
		5:
			moving.cage.position = Vector3(0.96, s.height, 1.35 if s.pocket else -0.25)
			moving.arrow.text = "↓" if s.gravity < 0 else "↑"
			for i in range(2):
				var location: int = s.loads[i]
				moving.loads[i].position = [Vector3(-3.32 - i * 0.75, 0.27, 0.73), Vector3(3.35 + i * 0.72, 3.27, 0.56), Vector3(0.96, s.height + 0.29, moving.cage.position.z)][location]
		6:
			var raw := Vector3(-4.7, 0.32, -1.95)
			if s.form == 0: moving.stock.position = raw
			else:
				var from: Vector3 = raw if s.form == 1 else moving.forms[s.form - 2]
				moving.stock.position = from.lerp(moving.forms[s.form - 1], s.progress)
			moving.stock.material_override = mat([STONE, SEAM, ALLOY, PORCELAIN][s.form])
			moving.form_label.modulate = PORCELAIN if s.form == 1 else INK
			moving.form_label.text = ["RAW", "MAG", "FLOAT", "LIT"][s.form]
			for i in range(3): moving.latches[i].position.y = 2.65 if s.latched[i] else 0.85
			moving.drawbridge.position.y = 0.0 if s.passed else -1.04
		7:
			moving.magnet.position.z = s.magnet
			moving.probe.position = Vector3(1.46 + s.probe_x, 0.27, 1.45 - s.probe_z)
			moving.hall.text = "FIELD  ⊙" if s.polarity > 0 else "FIELD  ⊗"
			moving.gate.position.y = 2.81 if s.hold > 0 else 0.89
		8:
			moving.signal_a.visible = s.age >= 0 and s.age < 80
			moving.signal_b.visible = s.age >= 20 and s.age < 100
			moving.signal_a.position.x = lerpf(-2, 2, clampf(s.age / 80.0, 0, 1))
			moving.signal_b.position.x = lerpf(2, -2, clampf((s.age - 20) / 80.0, 0, 1))
			moving.order_a.text = " / ".join(s.arrival_l)
			moving.order_b.text = " / ".join(s.arrival_r)
			moving.ruler.scale.x = s.length_ratio
			moving.player.position.x = -1.70 if s.player == 0 else 1.70
			moving.echo.visible = s.echo >= 0
			moving.echo.position = Vector3(-1.70 if s.echo == 0 else 1.70, 0.14, 1.41)
			moving.gate.position.y = 2.73 if s.passed else 0.88
		9:
			for i in range(5):
				var symbol := str(s.tape[i]) if i < 4 else "□"
				moving.bits[i].text = symbol
				moving.top_bits[i].text = symbol
			moving.cursor.position.x = tape_x(s.cursor)
			moving.writer.position.x = tape_x(s.head)
			moving.parity.position.x = tape_x(s.head)
			moving.parity.text = s.halt if s.halt in ["ACCEPT", "REJECT"] else "Q%d" % s.parity
