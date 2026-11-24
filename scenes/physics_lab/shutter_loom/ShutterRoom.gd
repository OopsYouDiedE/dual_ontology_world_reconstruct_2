extends Node3D

const Finish := preload("res://scenes/blue_prince_lab/HallFinish.gdshader")
const Builder := preload("res://tools/building_construction/BuildingConstruction/Shared/RecipeGeometry.gd")
const Gothic := preload("res://tools/building_construction/production/rule/GothicRecipes.gd")
const STONE := Color("9da3a4")
const TRIM := Color("c0baab")
const DARK := Color("384650")
const COPPER := Color("be915b")
const CLEAR := Color("73d1c8")
const RUST := Color("ed8658")
const INK := Color("121a21")
const DIM := Color("5b6a70")
var plan: Dictionary
var block := BoxMesh.new()
var wall: Node3D
var token: Node3D
var beams := {}
var shadows := {}
var permits := {}
var cues: Array[Node3D] = []
var mats := {}
var cutoff: Array[MeshInstance3D] = []
var bounds: Array[AABB] = []
var faint: StandardMaterial3D
var faded := 0
var beam_mat: StandardMaterial3D
var deck: Node3D
var return_arm: Node3D


func build(layout: Dictionary) -> void:
	plan = layout
	deck = Node3D.new()
	add_child(deck)
	faint = translucent(Color(0.68, 0.85, 0.88, 0.15))
	beam_mat = translucent(Color(1, 0.76, 0.40, 0.29))
	box(deck, Vector3(0, -0.36, 0.32), Vector3(8.00, 0.71, 7.42), DARK)
	box(deck, Vector3(0, -0.54, 0.32), Vector3(8.07, 0.07, 7.49), COPPER.darkened(0.19))
	for x in 12:
		for z in 10:
			var accent := STONE.lerp(TRIM, 0.23 if (x + z) % 2 == 0 else 0.10)
			if z >= 6: accent = accent.lerp(DIM, 0.22)
			box(deck, Vector3(-3.58 + x * 0.65, 0.008, -2.99 + z * 0.73), Vector3(0.641, 0.059, 0.719), accent)
	for z: float in [-0.37, 0.37]:
		box(deck, Vector3(0, 0.055, z), Vector3(7.55, 0.075, 0.095), DARK)
		box(deck, Vector3(0, 0.100, z), Vector3(7.55, 0.026, 0.046), COPPER)
		for i in 15:
			box(deck, Vector3((i - 7) * 0.49, 0.053, z), Vector3(0.075, 0.032, 0.24), DARK)
	for extent: Array in plan.partition_x_spans_cm:
		var width := float(extent[1] - extent[0]) * 0.01
		var center := float(extent[0] + extent[1]) * 0.005
		box(deck, Vector3(center, 0.41, float(plan.partition_z_cm) * 0.01), Vector3(width, 0.80, 0.19), DARK)
		box(deck, Vector3(center, 0.80, float(plan.partition_z_cm) * 0.01), Vector3(width, 0.09, 0.25), TRIM)
	for lane: String in plan.lanes:
		setup_lane(lane)
	build_wall()
	rear_galleries()
	var out := to_world(plan.exit_cm)
	box(deck, out + Vector3(0, 0.18, 0), Vector3(1.19, 0.29, 0.72), DARK)
	arch(out + Vector3(0, 1.58, 0.20), 0.60, 0.62, 0.075)
	for x in [-0.61, 0.61]:
		box(deck, out + Vector3(x, 0.81, 0.21), Vector3(0.17, 1.61, 0.35), TRIM)
	label("GALLERY EXIT", out + Vector3(0, 0.08, -0.65), 0.15, DARK)
	var post := to_world(plan.porch_cm)
	box(deck, post + Vector3(0.69, 0.35, 0.08), Vector3(0.43, 0.68, 0.42), DARK)
	return_arm = Node3D.new()
	deck.add_child(return_arm)
	return_arm.position = post + Vector3(0.69, 0.79, 0.08)
	box(return_arm, Vector3(0, 0.18, 0), Vector3(0.055, 0.34, 0.065), COPPER)
	box(return_arm, Vector3(0, 0.35, 0), Vector3(0.19, 0.068, 0.09), DARK)
	label("THROW LEVER", post + Vector3(0.69, 0.065, -0.50), 0.13, DARK)
	token = Node3D.new()
	deck.add_child(token)
	drum(token, Vector3(0, 0.12, 0), 0.22, 0.16, DARK)
	box(token, Vector3(0, 0.36, 0), Vector3(0.29, 0.39, 0.29), COPPER, true)
	drum(token, Vector3(0, 0.56, 0), 0.20, 0.10, DARK)
	for i in 4:
		var n := Node3D.new()
		deck.add_child(n)
		cues.append(n)
		for j in 5:
			var coil := TorusMesh.new()
			coil.outer_radius = 0.17 + 0.045 * float(j)
			coil.inner_radius = coil.outer_radius - 0.045
			coil.ring_segments = 12
			coil.rings = 18
			mesh(n, coil, Vector3(0, 0.09 * j, 0), mat(CLEAR, true))
		n.visible = false


func rear_galleries() -> void:
	for cx: float in [-2.66, 2.66]:
		for j in 4:
			box(deck, Vector3(cx, 0.105 + 0.23 * j, 3.78), Vector3(2.22, 0.21, 0.23), DIM.lerp(STONE, 0.22 + 0.08 * j))
			box(deck, Vector3(cx, 0.105 + 0.23 * j, 3.63), Vector3(1.93, 0.024, 0.028), DARK)
		arch(Vector3(cx, 0.78, 3.57), 1.0, 0.52, 0.059)
		for dx: float in [-0.99, 0.99]:
			box(deck, Vector3(cx + dx, 0.40, 3.61), Vector3(0.21, 0.80, 0.29), TRIM)
		for dx: float in [-0.50, -0.25, 0.0, 0.25, 0.50]:
			box(deck, Vector3(cx + dx, 0.62, 3.61), Vector3(0.03, 0.60, 0.06), DARK)
		box(deck, Vector3(cx, 0.54, 3.55), Vector3(1.37, 0.04, 0.09), COPPER)
		var x: float = 3.54 * signf(cx)
		for i in 5:
			box(deck, Vector3(x, 0.08, 1.25 + i * 0.40), Vector3(0.34, 0.07, 0.33), DIM)
			box(deck, Vector3(x, 0.124, 1.25 + i * 0.40), Vector3(0.32, 0.02, 0.03), COPPER)


func setup_lane(lane: String) -> void:
	var lm: Dictionary = plan.lanes[lane]
	var origin := to_world(lm.window_cm)
	var receiver := to_world(lm.receiver_cm)
	var caster := to_world(lm.caster_cm)
	var mouth := to_world(lm.mouth_cm)
	var approach := to_world(lm.approach_cm)
	var terminal := box(deck, origin + Vector3(0, 0.67, 0), Vector3(0.57, 1.32, 0.19), DARK)
	cutoff.append(terminal)
	bounds.append(AABB(terminal.position - terminal.scale * 0.5, terminal.scale))
	box(deck, origin + Vector3(0, 0.84, 0.11), Vector3(0.25, 0.11, 0.046), COPPER, true)
	box(deck, origin + Vector3(0, 0.84, -0.11), Vector3(0.25, 0.11, 0.046), COPPER, true)
	box(deck, origin + Vector3(0, 0.09, 0), Vector3(0.77, 0.14, 0.31), TRIM)
	box(deck, origin + Vector3(0, 1.28, 0), Vector3(0.67, 0.09, 0.30), TRIM)
	for side: float in [-1.0, 1.0]:
		box(deck, origin + Vector3(side * 0.26, 0.68, -0.12), Vector3(0.060, 1.1, 0.07), COPPER)
	drum(deck, caster + Vector3(0, 0.39, 0), 0.13, 0.77, TRIM)
	box(deck, caster + Vector3(0, 0.79, 0), Vector3(0.25, 0.17, 0.19), DARK)
	beam(deck, origin + Vector3(0, 0.88, 0.0), to_world(lm.beam_end_cm) + Vector3(0, 0.88, 0.0), beam_mat, lane)
	var verts := PackedVector3Array()
	for xy: Array in lm.shadow_polygon_cm: verts.append(to_world(xy) + Vector3(0, 0.045, 0))
	var polygon := SurfaceTool.new()
	polygon.begin(Mesh.PRIMITIVE_TRIANGLES)
	polygon.set_material(mat(INK))
	for triangle in [[0, 1, 2], [0, 2, 3], [0, 2, 1], [0, 3, 2]]:
		for i: int in triangle: polygon.add_vertex(verts[i])
	polygon.generate_normals()
	shadows[lane] = mesh(deck, polygon.commit(), Vector3.ZERO, mat(INK))
	shadows[lane].cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	for v in [mouth, receiver]:
		box(deck, v + Vector3(0.37, 0.076, 0), Vector3(0.065, 0.036, 0.7), COPPER)
		box(deck, v + Vector3(-0.37, 0.076, 0), Vector3(0.065, 0.036, 0.7), COPPER)
	permits[lane] = drum(deck, mouth + Vector3(0.41, 0.48, 0.42), 0.11, 0.14, DARK)
	drum(deck, mouth + Vector3(0.41, 0.24, 0.42), 0.065, 0.49, DARK)
	label(lane.to_upper() + " MOUTH", approach + Vector3(0, 0.046, -0.38), 0.15, DARK)
	label("RECEIVER", receiver + Vector3(0.19, 0.046, 0.43), 0.13, DARK)


func build_wall() -> void:
	wall = Node3D.new()
	deck.add_child(wall)
	box(wall, Vector3(0, 0.66, 0), Vector3(3.0, 1.25, 0.48), DARK)
	box(wall, Vector3(0, 1.31, 0), Vector3(3.03, 0.12, 0.51), COPPER)
	box(wall, Vector3(0, 0.18, 0), Vector3(3.05, 0.15, 0.54), DARK)
	for i in 6:
		var x := i * 0.5 - 1.25
		box(wall, Vector3(x, 0.71, -0.244), Vector3(0.42, 0.92, 0.08), STONE)
		box(wall, Vector3(x, 0.71, 0.244), Vector3(0.42, 0.92, 0.08), STONE)
		box(wall, Vector3(x, 0.71, -0.299), Vector3(0.05, 0.82, 0.06), COPPER)
	for x in [-1.23, 1.23]:
		for z in [-0.32, 0.32]:
			drum(wall, Vector3(x, 0.17, z), 0.15, 0.12, DARK)
	for x in [-3.56, 3.56]:
		drum(deck, Vector3(x, 0.12, -0.42), 0.12, 0.16, COPPER)


func draw(state: Dictionary, camera: Camera3D) -> void:
	wall.position.x = float(state.rail.wall_x_cm) * 0.01
	return_arm.rotation.z = -wall.position.x * 0.22
	token.position = to_world(state.player.position_cm)
	for lane: String in state.lanes:
		var info: Dictionary = state.lanes[lane]
		var top := Vector3.UP * 0.88
		set_beam(beams[lane], to_world(plan.lanes[lane].window_cm) + top, to_world(info.beam_tip_cm) + top)
		(shadows[lane] as MeshInstance3D).visible = info.shadow_visible
		(permits[lane] as MeshInstance3D).material_override = mat(CLEAR if info.crossing_available else DARK, info.crossing_available)
	for i in cues.size():
		var spot := cues[i]
		spot.visible = i < state.cues.size()
		if not spot.visible: continue
		var cue: Dictionary = state.cues[i]
		spot.position = to_world(cue.position_cm) + Vector3.UP * 0.09
		var color := RUST if cue.kind == "ink_ridge" else CLEAR if cue.kind == "threshold_scuff" else Color("f1e0bc")
		var pulse := 0.92 + 0.10 * cos((state.tick - cue.start_tick) * 0.12)
		spot.scale = Vector3(pulse, 0.55 if cue.kind == "ink_ridge" else 1.4, pulse)
		for p: MeshInstance3D in spot.get_children(): p.material_override = mat(color, true)
	faded = 0
	for i in cutoff.size():
		var hidden := false
		for at in [token.position, wall.position, to_world(plan.lanes.west.receiver_cm), to_world(plan.lanes.east.receiver_cm)]:
			if bounds[i].intersects_segment(at + camera.global_basis.z * 40.0, at + Vector3.UP * 0.1) != null:
				hidden = true
				break
		faded += int(hidden)
		cutoff[i].material_override = faint if hidden else mat(DARK)
		cutoff[i].cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF if hidden else GeometryInstance3D.SHADOW_CASTING_SETTING_ON


func to_world(xz: Array) -> Vector3:
	return Vector3(float(xz[0]) * 0.01, 0, float(xz[1]) * 0.01)


func translucent(color: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	return m


func mat(c: Color, lit: bool = false) -> ShaderMaterial:
	var k := "%s:%s" % [c, lit]
	if not mats.has(k):
		var m := ShaderMaterial.new()
		m.shader = Finish
		m.set_shader_parameter("pigment", c)
		m.set_shader_parameter("toon_on", true)
		m.set_shader_parameter("toon_strength", 0.86)
		m.set_shader_parameter("grain", 0.058)
		m.set_shader_parameter("emission_gain", 0.42 if lit else 0.0)
		mats[k] = m
	return mats[k]


func mesh(root: Node3D, shape: Mesh, at: Vector3, material: Material) -> MeshInstance3D:
	var n := MeshInstance3D.new()
	n.mesh = shape
	n.material_override = material
	root.add_child(n)
	n.position = at
	return n


func box(root: Node3D, at: Vector3, size: Vector3, c: Color, lit: bool = false) -> MeshInstance3D:
	var n := mesh(root, block, at, mat(c, lit))
	n.scale = size
	return n


func drum(root: Node3D, at: Vector3, radius: float, length: float, c: Color, lit: bool = false) -> MeshInstance3D:
	var d := CylinderMesh.new()
	d.top_radius = radius
	d.bottom_radius = radius
	d.height = length
	d.radial_segments = 18
	return mesh(root, d, at, mat(c, lit))


func arch(at: Vector3, width: float, rise: float, thick: float) -> void:
	var m := mat(TRIM)
	var model := Builder.finish(Gothic.gen_gothic_pointed_rib("Gallery arch", {"stone": m, "cream": m}, width, 0, rise, thick, 10))
	deck.add_child(model)
	model.position = at


func beam(root: Node3D, start: Vector3, end: Vector3, material: Material, lane: String) -> void:
	var n := mesh(root, block, Vector3.ZERO, material)
	n.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	beams[lane] = n
	set_beam(n, start, end)


func set_beam(n: MeshInstance3D, start: Vector3, end: Vector3) -> void:
	var delta := end - start
	n.scale = Vector3(0.073, delta.length(), 0.073)
	n.quaternion = Quaternion(Vector3.UP, delta.normalized())
	n.position = start.lerp(end, 0.5)


func label(title: String, at: Vector3, size: float, c: Color) -> void:
	var l := Label3D.new()
	l.text = title
	l.font_size = 64
	l.pixel_size = size / 64.0
	l.modulate = c
	l.outline_size = 0
	l.rotation.x = -PI * 0.5
	# Porch lies at -Z; orient the lettering to read from this access side.
	l.rotate_y(PI)
	deck.add_child(l)
	l.position = at
