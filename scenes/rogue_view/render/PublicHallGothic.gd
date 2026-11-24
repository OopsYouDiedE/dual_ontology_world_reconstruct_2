extends Node3D
## Cathedral-scale Gothic architectural shell, functional zones, and suspended
## brass Foucault Pendulum for the Public Hall (Constant Anchor Nave).
## Built directly from the integrated Notre-Dame-inspired GothicRecipes pipeline.

const Gothic = preload("res://tools/building_construction/production/rule/GothicRecipes.gd")
const Geo = preload("res://tools/building_construction/BuildingConstruction/Shared/RecipeGeometry.gd")
const Painted = preload("res://scenes/components/rendering/surfaces/PaintedSurface.gd")

const LANCET_TEX := "res://tools/research/french_gothic_nodes/lancet_register.png"
const ROSE_NORTH_TEX := "res://tools/research/french_gothic_nodes/rose_register.png"
const ROSE_SOUTH_TEX := "res://tools/research/french_gothic_nodes/rose_botanical.png"

const SPRING_HEIGHT := 3.65
const CROWN_RISE := 2.15
const TOTAL_HEIGHT := SPRING_HEIGHT + CROWN_RISE

var pendulum_pivot: Node3D
var pendulum_bob: Node3D
var drift_ring: MeshInstance3D
var essence_light: OmniLight3D
var watch_cot_pos := Vector3.ZERO
var pendulum_world_pos := Vector3.ZERO
var north_gate_pos := Vector3.ZERO

var drifting := true
var _time := 0.0
var _drift_angle := 0.24 # ~14 deg abnormal precession drift when uncalibrated

static func install(parent: Node3D, lot: Dictionary, floor_bounds: Rect2i, well: Rect2i, is_drifting: bool = true) -> Node3D:
	var hall := preload("res://scenes/rogue_view/render/PublicHallGothic.gd").new()
	hall.name = "PublicHallGothic"
	hall.drifting = is_drifting
	parent.add_child(hall)
	hall.build(lot, floor_bounds, well)
	return hall

func build(_lot: Dictionary, floor_bounds: Rect2i, well: Rect2i) -> void:
	var min_x := float(floor_bounds.position.x)
	var max_x := float(floor_bounds.end.x)
	var min_z := float(floor_bounds.position.y)
	var max_z := float(floor_bounds.end.y)
	var span_x := maxf(4.0, max_x - min_x)
	var span_z := maxf(4.0, max_z - min_z)
	var cx := (min_x + max_x) * 0.5
	var cz := (min_z + max_z) * 0.5

	# Anchors for the opening cutscene & functional zones
	if well.has_area():
		pendulum_world_pos = Vector3(well.position.x + well.size.x * 0.5, 0.0, well.position.y + well.size.y * 0.5)
	else:
		pendulum_world_pos = Vector3(cx, 0.0, cz)
	watch_cot_pos = Vector3(cx - 1.8, 0.0, max_z - 1.35)
	north_gate_pos = Vector3(cx, 0.0, min_z + 0.5)

	var mats: Dictionary = Geo.outdoor_palette(Geo.industrial_palette(Geo.gen_palette()))

	# 1. Upper clerestory masonry wall extension (from 2.45m original wall up to SPRING_HEIGHT + 0.4m)
	_build_clerestory_walls(min_x, max_x, min_z, max_z)

	# 2. Quadripartite Gothic vault bays (2 x 2 grid covering the 10m x 8m hall)
	var cols := maxi(2, roundi(span_x / 5.0))
	var rows := maxi(2, roundi(span_z / 4.2))
	var bay_w := span_x / float(cols)
	var bay_d := span_z / float(rows)
	for ix in cols:
		for iz in rows:
			var bx := min_x + (float(ix) + 0.5) * bay_w
			var bz := min_z + (float(iz) + 0.5) * bay_d
			var record = Gothic.gen_gothic_vault_bay(
				"HallVault_%d_%d" % [ix, iz],
				mats,
				bay_w,
				bay_d,
				SPRING_HEIGHT,
				CROWN_RISE,
				0.105,
				9
			)
			var node: Node3D = Geo.finish(record)
			node.position = Vector3(bx, 0.0, bz)
			add_child(node)
			_apply_gothic_materials(node, null)

	# 3. Side wall French Gothic paired lancets + lower blind arcades (West & East walls)
	var lancet_tex := _load_texture(LANCET_TEX)
	var side_bays := maxi(2, roundi(span_z / 2.7))
	var side_w := (span_z - 0.3) / float(side_bays)
	for side_i in 2:
		var is_west := (side_i == 0)
		var wx := min_x + 0.14 if is_west else max_x - 0.14
		var rot_y := -PI * 0.5 if is_west else PI * 0.5
		for bi in side_bays:
			var wz := min_z + 0.15 + (float(bi) + 0.5) * side_w
			var rec = Gothic.gen_gothic_lancet_bay(
				"SideLancet_%s_%d" % ["W" if is_west else "E", bi],
				mats,
				side_w,
				SPRING_HEIGHT + 0.75,
				1.15,
				(bi + side_i) % 4
			)
			var bay_node: Node3D = Geo.finish(rec)
			bay_node.position = Vector3(wx, 0.0, wz)
			bay_node.rotation.y = rot_y
			add_child(bay_node)
			_apply_gothic_materials(bay_node, lancet_tex, true)

	# 4. North & South high radial Rose Windows (above departure gates & awakening alcove)
	var rose_north_tex := _load_texture(ROSE_NORTH_TEX)
	var rose_south_tex := _load_texture(ROSE_SOUTH_TEX)
	for end_i in 2:
		var is_north := (end_i == 0)
		var ez := min_z + 0.16 if is_north else max_z - 0.16
		var rot_y := 0.0 if is_north else PI
		var rec = Gothic.gen_gothic_rose_window(
			"HallRose_%s" % ("North" if is_north else "South"),
			mats,
			3.4,
			3.4,
			0.35,
			1.18,
			12
		)
		var rose_node: Node3D = Geo.finish(rec)
		rose_node.position = Vector3(cx, 2.35, ez)
		rose_node.rotation.y = rot_y
		add_child(rose_node)
		_apply_gothic_materials(rose_node, rose_north_tex if is_north else rose_south_tex, true)

	# 5. Central Suspended Brass Foucault Pendulum (Constant Anchor Apparatus)
	_build_foucault_pendulum(pendulum_world_pos)

	# 6. Functional Zone Props: Watch Cot (Awakening Alcove) & Essence Calibration Lectern
	_build_watch_cot(watch_cot_pos)
	_build_calibration_lectern(Vector3(pendulum_world_pos.x + 2.25, 0.0, min_z + 1.45))

func _build_clerestory_walls(min_x: float, max_x: float, min_z: float, max_z: float) -> void:
	var stone_mat := Painted.make(Color("9d8f79"), 0.90)
	var band_h := TOTAL_HEIGHT - 2.40 + 0.35
	var mid_y := 2.40 + band_h * 0.5
	var sx := max_x - min_x
	var sz := max_z - min_z
	var cx := (min_x + max_x) * 0.5
	var cz := (min_z + max_z) * 0.5
	var walls := [
		[Vector3(cx, mid_y, min_z - 0.05), Vector3(sx + 0.3, band_h, 0.24)],
		[Vector3(cx, mid_y, max_z + 0.05), Vector3(sx + 0.3, band_h, 0.24)],
		[Vector3(min_x - 0.05, mid_y, cz), Vector3(0.24, band_h, sz + 0.3)],
		[Vector3(max_x + 0.05, mid_y, cz), Vector3(0.24, band_h, sz + 0.3)],
		[Vector3(cx, TOTAL_HEIGHT + 0.28, cz), Vector3(sx + 0.4, 0.22, sz + 0.4)],
	]
	for w in walls:
		var m := MeshInstance3D.new()
		var box := BoxMesh.new()
		box.size = w[1]
		m.mesh = box
		m.position = w[0]
		m.material_override = stone_mat
		m.gi_mode = GeometryInstance3D.GI_MODE_STATIC
		add_child(m)

func _build_foucault_pendulum(anchor: Vector3) -> void:
	var root := Node3D.new()
	root.name = "FoucaultPendulum"
	root.position = anchor
	add_child(root)

	var brass := StandardMaterial3D.new()
	brass.albedo_color = Color("cfa152")
	brass.metallic = 0.72
	brass.roughness = 0.28

	var iron := Painted.make(Color("2d3338"), 0.85)
	var ceiling_y := TOTAL_HEIGHT - 0.15

	# Ceiling suspension rosette
	var cap := MeshInstance3D.new()
	var cap_mesh := CylinderMesh.new()
	cap_mesh.top_radius = 0.34
	cap_mesh.bottom_radius = 0.22
	cap_mesh.height = 0.24
	cap.mesh = cap_mesh
	cap.position = Vector3(0.0, ceiling_y, 0.0)
	cap.material_override = brass
	root.add_child(cap)

	# Swinging pivot at ceiling keystone
	pendulum_pivot = Node3D.new()
	pendulum_pivot.name = "PendulumPivot"
	pendulum_pivot.position = Vector3(0.0, ceiling_y - 0.08, 0.0)
	root.add_child(pendulum_pivot)

	var cable_len := ceiling_y - 0.62
	var cable := MeshInstance3D.new()
	var cable_mesh := CylinderMesh.new()
	cable_mesh.top_radius = 0.011
	cable_mesh.bottom_radius = 0.011
	cable_mesh.height = cable_len
	cable.mesh = cable_mesh
	cable.position = Vector3(0.0, -cable_len * 0.5, 0.0)
	cable.material_override = iron
	pendulum_pivot.add_child(cable)

	# Heavy brass bob + essence core ring + pointer tip
	pendulum_bob = Node3D.new()
	pendulum_bob.name = "PendulumBob"
	pendulum_bob.position = Vector3(0.0, -cable_len, 0.0)
	pendulum_pivot.add_child(pendulum_bob)

	var sphere := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 0.22
	sm.height = 0.44
	sphere.mesh = sm
	sphere.material_override = brass
	pendulum_bob.add_child(sphere)

	var equator := MeshInstance3D.new()
	var tm := TorusMesh.new()
	tm.inner_radius = 0.22
	tm.outer_radius = 0.27
	equator.mesh = tm
	equator.material_override = brass
	pendulum_bob.add_child(equator)

	var needle := MeshInstance3D.new()
	var nm := CylinderMesh.new()
	nm.top_radius = 0.045
	nm.bottom_radius = 0.005
	nm.height = 0.26
	needle.mesh = nm
	needle.position = Vector3(0.0, -0.30, 0.0)
	needle.material_override = brass
	pendulum_bob.add_child(needle)

	# Floor calibration compass ring & abnormal drift indicator
	drift_ring = MeshInstance3D.new()
	var ring_mesh := TorusMesh.new()
	ring_mesh.inner_radius = 0.88
	ring_mesh.outer_radius = 0.96
	drift_ring.mesh = ring_mesh
	drift_ring.position = Vector3(0.0, 0.03, 0.0)
	var ring_mat := StandardMaterial3D.new()
	ring_mat.albedo_color = Color("d85b42") if drifting else Color("77c7a5")
	ring_mat.emission_enabled = true
	ring_mat.emission = ring_mat.albedo_color
	ring_mat.emission_energy_multiplier = 1.4 if drifting else 0.55
	drift_ring.material_override = ring_mat
	root.add_child(drift_ring)

	# Subtle essence glow tied to pendulum stability
	essence_light = OmniLight3D.new()
	essence_light.position = Vector3(0.0, 0.55, 0.0)
	essence_light.omni_range = 4.6
	essence_light.shadow_enabled = false
	root.add_child(essence_light)
	set_drift_state(drifting)

func set_drift_state(is_drifting: bool) -> void:
	drifting = is_drifting
	if is_instance_valid(drift_ring) and drift_ring.material_override is StandardMaterial3D:
		var rm := drift_ring.material_override as StandardMaterial3D
		rm.albedo_color = Color("e05b42") if drifting else Color("77c7a5")
		rm.emission = rm.albedo_color
		rm.emission_energy_multiplier = 1.5 if drifting else 0.55
	if is_instance_valid(essence_light):
		essence_light.light_color = Color("ff8c66") if drifting else Color("ffe2a8")
		essence_light.light_energy = 1.65 if drifting else 1.10

func _build_watch_cot(pos: Vector3) -> void:
	var cot := Node3D.new()
	cot.name = "WatchCotAlcove"
	cot.position = pos
	add_child(cot)
	var wood := Painted.make(Color("5c4234"), 0.88)
	var cloth := Painted.make(Color("7b857e"), 0.92)
	var brass := Painted.make(Color("b6904d"), 0.45)

	# Folding cot frame + blanket + pillow
	_box(cot, Vector3(0.0, 0.34, 0.0), Vector3(1.85, 0.14, 0.82), wood)
	_box(cot, Vector3(0.04, 0.45, 0.0), Vector3(1.74, 0.10, 0.76), cloth)
	_box(cot, Vector3(-0.62, 0.54, 0.0), Vector3(0.36, 0.11, 0.58), Painted.make(Color("cfc4ae"), 0.92))
	for lx in [-0.82, 0.82]:
		for lz in [-0.34, 0.34]:
			_box(cot, Vector3(lx, 0.17, lz), Vector3(0.07, 0.34, 0.07), wood)

	# Bedside stool with lantern & field manual
	_box(cot, Vector3(-1.22, 0.28, -0.10), Vector3(0.42, 0.56, 0.42), wood)
	_box(cot, Vector3(-1.22, 0.62, -0.10), Vector3(0.14, 0.22, 0.14), brass)
	var lamp := OmniLight3D.new()
	lamp.position = Vector3(-1.22, 0.92, -0.10)
	lamp.light_color = Color("ffd59a")
	lamp.light_energy = 1.2
	lamp.omni_range = 3.8
	lamp.shadow_enabled = false
	cot.add_child(lamp)

func _build_calibration_lectern(pos: Vector3) -> void:
	var lectern := Node3D.new()
	lectern.name = "EssenceCalibrationLectern"
	lectern.position = pos
	add_child(lectern)
	var oak := Painted.make(Color("4e392d"), 0.88)
	var brass := Painted.make(Color("c99e50"), 0.40)
	var dial := Painted.make(Color("d9ceb4"), 0.85)
	_box(lectern, Vector3(0.0, 0.55, 0.0), Vector3(0.56, 1.10, 0.44), oak)
	_box(lectern, Vector3(0.0, 1.14, 0.0), Vector3(0.64, 0.07, 0.50), brass)
	_box(lectern, Vector3(0.0, 1.20, 0.02), Vector3(0.46, 0.03, 0.34), dial)

static func _box(parent: Node3D, p: Vector3, sz: Vector3, mat: Material) -> void:
	var inst := MeshInstance3D.new()
	var b := BoxMesh.new()
	b.size = sz
	inst.mesh = b
	inst.position = p
	inst.material_override = mat
	parent.add_child(inst)

static func _load_texture(path: String) -> Texture2D:
	if ResourceLoader.exists(path):
		return load(path) as Texture2D
	return null

func _apply_gothic_materials(node: Node3D, glass_tex: Texture2D, is_window: bool = false) -> void:
	var stone_mat := Painted.make(Color("b6a68d"), 0.91)
	var trim_mat := Painted.make(Color("d7c8ae"), 0.88)
	var lead_mat := Painted.make(Color("24282e"), 0.85)
	var glass_mat: StandardMaterial3D = null
	if is_window:
		glass_mat = StandardMaterial3D.new()
		if glass_tex != null:
			glass_mat.albedo_texture = glass_tex
			glass_mat.emission_texture = glass_tex
		else:
			glass_mat.albedo_color = Color("4f7fa6")
		glass_mat.emission_enabled = true
		glass_mat.emission = Color("a9c7e8") if glass_tex == null else Color.WHITE
		glass_mat.emission_energy_multiplier = 0.55
		glass_mat.roughness = 0.25

	for mi in node.find_children("*", "MeshInstance3D", true, false):
		var m := mi as MeshInstance3D
		m.gi_mode = GeometryInstance3D.GI_MODE_STATIC
		var lname := m.name.to_lower()
		if is_window and ("glass" in lname or "roseglass" in lname):
			m.material_override = glass_mat
		elif "lead" in lname or "plinth" in lname:
			m.material_override = lead_mat
		elif "rib" in lname or "cap" in lname or "shaft" in lname or "mould" in lname or "ring" in lname or "spoke" in lname or "branch" in lname or "frame" in lname or "blindarc" in lname or "keystone" in lname:
			m.material_override = trim_mat
		else:
			m.material_override = stone_mat

func _process(delta: float) -> void:
	if not is_instance_valid(pendulum_pivot):
		return
	_time += delta
	if drifting:
		# Abnormal precession drift + slight hesitation in the southern quadrant
		var base_phase := _time * 1.15
		var stutter := 0.055 * sin(_time * 3.45) * maxf(0.0, sin(base_phase))
		var swing := 0.24 * sin(base_phase) + stutter
		pendulum_pivot.rotation = Vector3(swing * sin(_drift_angle), _drift_angle + 0.05 * sin(_time * 0.4), swing * cos(_drift_angle))
		if is_instance_valid(essence_light):
			essence_light.light_energy = 1.45 + 0.45 * sin(_time * 4.2)
	else:
		# Smooth calibrated Foucault precession
		var swing := 0.20 * sin(_time * 1.05)
		var slow_precession := fmod(_time * 0.025, TAU)
		pendulum_pivot.rotation = Vector3(swing * sin(slow_precession), slow_precession, swing * cos(slow_precession))
		if is_instance_valid(essence_light):
			essence_light.light_energy = 1.05 + 0.08 * sin(_time * 1.2)
