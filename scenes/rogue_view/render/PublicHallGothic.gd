extends Node3D
## Cathedral-scale Gothic nave architecture, functional zones, and suspended
## brass Foucault Pendulum for the Public Hall (Constant Anchor Nave).
##
## Uses the locked Blue-Prince-inspired HallFinish.gdshader palette (cool slate
## limestone, pale stone ribs, dark walnut wainscoting, warm ochre runner,
## hanging oil lanterns) and UV-mapped Notre-Dame-inspired stained glass.

const HallFinish := preload("res://scenes/blue_prince_lab/HallFinish.gdshader")
const OilLamp := preload("res://scenes/blue_prince_lab/lamp/Lamp.tscn")
const Factory := preload("res://tools/building_construction/BuildingConstruction/Shared/ComponentFactory.gd")

const LANCET_TEX := "res://tools/research/french_gothic_nodes/lancet_register.png"
const ROSE_NORTH_TEX := "res://tools/research/french_gothic_nodes/rose_register.png"
const ROSE_SOUTH_TEX := "res://tools/research/french_gothic_nodes/rose_botanical.png"

const SPRING_H := 4.45
const CROWN_RISE := 2.85
const CROWN_H := SPRING_H + CROWN_RISE

var pendulum_pivot: Node3D
var pendulum_bob: Node3D
var drift_bezel: MeshInstance3D
var essence_light: OmniLight3D
var watch_cot_pos := Vector3.ZERO
var pendulum_world_pos := Vector3.ZERO
var north_gate_pos := Vector3.ZERO

var drifting := true
var _time := 0.0
var _drift_angle := 0.24 # ~14 deg abnormal precession drift

var _mat_wall: ShaderMaterial
var _mat_rib: ShaderMaterial
var _mat_vault: ShaderMaterial
var _mat_plinth: ShaderMaterial
var _mat_wood: ShaderMaterial
var _mat_runner: ShaderMaterial
var _mat_lead: ShaderMaterial
var _mat_brass: StandardMaterial3D

static func install(parent: Node3D, lot: Dictionary, floor_bounds: Rect2i, well: Rect2i, is_drifting: bool = true) -> Node3D:
	var hall := preload("res://scenes/rogue_view/render/PublicHallGothic.gd").new()
	hall.name = "PublicHallGothic"
	hall.drifting = is_drifting
	parent.add_child(hall)
	hall.build(lot, floor_bounds, well)
	return hall

func _make_finish(hex: String, roughness := 0.84, grain := 0.075, is_wood := false, is_runner := false, vault_fill := 0.0) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = HallFinish
	m.set_shader_parameter("pigment", Color(hex))
	m.set_shader_parameter("surface_roughness", roughness)
	m.set_shader_parameter("grain", grain)
	m.set_shader_parameter("wood", 1.0 if is_wood else 0.0)
	m.set_shader_parameter("runner", 1.0 if is_runner else 0.0)
	m.set_shader_parameter("vault_fill", vault_fill)
	m.set_shader_parameter("toon_on", true)
	m.set_shader_parameter("toon_strength", 0.86)
	return m

func _init_materials() -> void:
	# Locked Hall 04 cool slate-blue stone + warm walnut + ochre runner palette
	_mat_wall = _make_finish("4b5868", 0.88, 0.032, false, false, 0.03)
	_mat_rib = _make_finish("8a96a6", 0.80, 0.025, false, false, 0.04)
	_mat_vault = _make_finish("3a4554", 0.92, 0.035, false, false, 0.06)
	_mat_plinth = _make_finish("333b46", 0.86, 0.03, false, false, 0.02)
	_mat_wood = _make_finish("3f2b1f", 0.76, 0.06, true, false, 0.0)
	_mat_runner = _make_finish("ca9857", 0.92, 0.05, false, true, 0.0)
	_mat_lead = _make_finish("1f242b", 0.70, 0.03, false, false, 0.0)

	_mat_runner.set_shader_parameter("emission_gain", 0.34)
	_mat_wall.set_shader_parameter("pale_wash", 0.09)
	_mat_rib.set_shader_parameter("pale_wash", 0.13)
	_mat_vault.set_shader_parameter("pale_wash", 0.10)

	_mat_brass = StandardMaterial3D.new()
	_mat_brass.albedo_color = Color("cfa04c")
	_mat_brass.metallic = 0.72
	_mat_brass.roughness = 0.28

func build(lot: Dictionary, floor_bounds: Rect2i, well: Rect2i) -> void:
	_init_materials()
	var min_x := float(floor_bounds.position.x)
	var max_x := float(floor_bounds.end.x)
	var min_z := float(floor_bounds.position.y)
	var max_z := float(floor_bounds.end.y)
	var span_x := maxf(4.0, max_x - min_x)
	var span_z := maxf(4.0, max_z - min_z)
	var cx := (min_x + max_x) * 0.5
	var cz := (min_z + max_z) * 0.5

	if well.has_area():
		pendulum_world_pos = Vector3(well.position.x + well.size.x * 0.5, 0.0, well.position.y + well.size.y * 0.5)
	else:
		pendulum_world_pos = Vector3(cx, 0.0, cz)
	watch_cot_pos = Vector3(cx - 2.35, 0.0, max_z - 1.25)
	north_gate_pos = Vector3(cx, 0.0, min_z + 0.45)

	var bays_z := maxi(3, roundi(span_z / 4.0))
	var bay_len := span_z / float(bays_z)

	# 1. Single grand clear-span Gothic nave vault (NO center columns!)
	_build_nave_vault_and_ribs(min_x, max_x, min_z, max_z, bays_z, bay_len)

	# 2. Perimeter clustered Gothic piers along West & East walls ONLY
	for iz in range(bays_z + 1):
		var pz := min_z + float(iz) * bay_len
		_build_clustered_pier(Vector3(min_x + 0.16, 0.0, pz), 1.0)
		_build_clustered_pier(Vector3(max_x - 0.16, 0.0, pz), -1.0)

	# 3. Full-height East & West Gothic walls with dark walnut dado + UV-mapped stained glass paired lancets
	var lancet_tex := _load_texture(LANCET_TEX)
	for side_i in 2:
		var is_west := (side_i == 0)
		var wx := min_x + 0.04 if is_west else max_x - 0.04
		var inward_x := 1.0 if is_west else -1.0
		for bi in bays_z:
			var bz0 := min_z + float(bi) * bay_len
			var bz1 := bz0 + bay_len
			_build_side_lancet_bay(wx, inward_x, bz0, bz1, (bi + side_i) % 4, lancet_tex)

	# 4. Full-height North & South pointed gable end walls with recessed doors & UV-mapped Rose Windows
	var rose_north_tex := _load_texture(ROSE_NORTH_TEX)
	var rose_south_tex := _load_texture(ROSE_SOUTH_TEX)
	_build_end_gable_wall(min_x, max_x, min_z + 0.04, 1.0, true, rose_north_tex, lot)
	_build_end_gable_wall(min_x, max_x, max_z - 0.04, -1.0, false, rose_south_tex, lot)

	# 5. Warm ochre ceremonial floor runner framing the central axis (Hall 04 signature)
	_build_floor_runner(cx, min_z, max_z, span_x)

	# 6. Project-authentic hanging oil lanterns along the nave colonnade
	_build_nave_lanterns(min_x, max_x, min_z, bay_len, bays_z)

	# 7. Central suspended brass Foucault Pendulum + flush recessed calibration bezel
	_build_foucault_pendulum(pendulum_world_pos, well)

	# 8. Real ArchBuilder furniture for Watch Cot Alcove & Calibration Lectern
	_build_functional_props(min_z)

func _pointed_arch_y(x_norm: float) -> float:
	# Smooth Notre-Dame pointed arch profile from x_norm in [-1, 1] -> [0, CROWN_RISE]
	var t := 1.0 - absf(clampf(x_norm, -1.0, 1.0))
	return CROWN_RISE * (1.28 * sqrt(maxf(0.0, t)) - 0.28 * t)

func _build_nave_vault_and_ribs(min_x: float, max_x: float, min_z: float, max_z: float, bays_z: int, bay_len: float) -> void:
	var cx := (min_x + max_x) * 0.5
	var hx := (max_x - min_x) * 0.5

	# Continuous smooth pointed barrel/groin vault shell (single clean mesh, zero clipping!)
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var segs_x := 20
	var segs_z := bays_z * 6
	var grid: Array = []
	for iz in range(segs_z + 1):
		var row: Array = []
		var wz := lerpf(min_z, max_z, float(iz) / float(segs_z))
		var bay_local_z := fmod(wz - min_z, bay_len) / bay_len
		var z_groin := 1.0 - absf(bay_local_z * 2.0 - 1.0) # 0 at transverse rib, 1 at bay center
		for ix in range(segs_x + 1):
			var nx := -1.0 + 2.0 * float(ix) / float(segs_x)
			var wx := cx + nx * hx
			var arch_h := _pointed_arch_y(nx)
			# Subtle quadripartite domical lift toward bay center
			var domical := 0.14 * z_groin * (1.0 - absf(nx))
			var wy := SPRING_H + arch_h + domical
			row.append(Vector3(wx, wy, wz))
		grid.append(row)

	for iz in segs_z:
		for ix in segs_x:
			var p00: Vector3 = grid[iz][ix]
			var p10: Vector3 = grid[iz][ix + 1]
			var p11: Vector3 = grid[iz + 1][ix + 1]
			var p01: Vector3 = grid[iz + 1][ix]
			# Downward-facing interior vault soffit
			_add_quad(st, p00, p01, p11, p10)
	st.generate_normals()
	_commit_mesh(st, _mat_vault, "NaveVaultShell")

	# Rib SurfaceTool (transverse ribs, wall ribs, diagonal crossing ribs, central ridge rib)
	var rib_st := SurfaceTool.new()
	rib_st.begin(Mesh.PRIMITIVE_TRIANGLES)

	# Transverse pointed arches at every bay station
	for iz in range(bays_z + 1):
		var wz := min_z + float(iz) * bay_len
		var pts := PackedVector3Array()
		for ix in range(segs_x + 1):
			var nx := -1.0 + 2.0 * float(ix) / float(segs_x)
			pts.append(Vector3(cx + nx * (hx - 0.08), SPRING_H + _pointed_arch_y(nx) - 0.04, wz))
		_sweep_rib(rib_st, pts, 0.11)

	# Diagonal crossing ribs + gilded keystone boss per bay
	for bi in bays_z:
		var z0 := min_z + float(bi) * bay_len
		var z1 := z0 + bay_len
		var zc := (z0 + z1) * 0.5
		for diag in 2:
			var pts := PackedVector3Array()
			for i in range(segs_x + 1):
				var frac := float(i) / float(segs_x)
				var nx := -1.0 + 2.0 * frac
				var wz := lerpf(z0, z1, frac) if diag == 0 else lerpf(z1, z0, frac)
				var z_groin := 1.0 - absf(((wz - z0) / bay_len) * 2.0 - 1.0)
				var wy := SPRING_H + _pointed_arch_y(nx) + 0.14 * z_groin * (1.0 - absf(nx)) - 0.04
				pts.append(Vector3(cx + nx * (hx - 0.10), wy, wz))
			_sweep_rib(rib_st, pts, 0.085)

		# Keystone boss at bay crown
		var boss := MeshInstance3D.new()
		var bm := CylinderMesh.new()
		bm.top_radius = 0.24
		bm.bottom_radius = 0.18
		bm.height = 0.18
		boss.mesh = bm
		boss.position = Vector3(cx, CROWN_H + 0.08, zc)
		boss.material_override = _mat_brass
		add_child(boss)

	# Central ridge rib along Z
	var ridge := PackedVector3Array([Vector3(cx, CROWN_H + 0.02, min_z + 0.06), Vector3(cx, CROWN_H + 0.02, max_z - 0.06)])
	_sweep_rib(rib_st, ridge, 0.075)

	rib_st.generate_normals()
	_commit_mesh(rib_st, _mat_rib, "NaveVaultRibs")

func _build_clustered_pier(pos: Vector3, inward_x: float) -> void:
	var pier := Node3D.new()
	pier.position = pos
	add_child(pier)
	# Plinth tiers
	_box(pier, Vector3(0.0, 0.14, 0.0), Vector3(0.54, 0.28, 0.54), _mat_plinth)
	_box(pier, Vector3(0.0, 0.34, 0.0), Vector3(0.44, 0.14, 0.44), _mat_rib)
	# Core shaft + 3 inward-facing engaged colonnettes
	_box(pier, Vector3(0.0, SPRING_H * 0.5, 0.0), Vector3(0.30, SPRING_H - 0.30, 0.32), _mat_wall)
	for dz in [-0.14, 0.0, 0.14]:
		var cyl := MeshInstance3D.new()
		var cm := CylinderMesh.new()
		cm.top_radius = 0.065
		cm.bottom_radius = 0.065
		cm.height = SPRING_H - 0.52
		cm.radial_segments = 10
		cyl.mesh = cm
		cyl.position = Vector3(inward_x * 0.16, SPRING_H * 0.5, dz)
		cyl.material_override = _mat_rib
		pier.add_child(cyl)
	# 3-tier stepped Gothic capital
	_box(pier, Vector3(inward_x * 0.04, SPRING_H - 0.26, 0.0), Vector3(0.40, 0.10, 0.42), _mat_rib)
	_box(pier, Vector3(inward_x * 0.06, SPRING_H - 0.15, 0.0), Vector3(0.48, 0.11, 0.50), _mat_rib)
	_box(pier, Vector3(inward_x * 0.08, SPRING_H - 0.05, 0.0), Vector3(0.56, 0.10, 0.58), _mat_rib)

func _build_side_lancet_bay(wx: float, inward_x: float, z0: float, z1: float, variant: int, tex: Texture2D) -> void:
	var bay_w := z1 - z0
	var cz := (z0 + z1) * 0.5
	var dado_h := 1.38
	var win_top := SPRING_H + 0.15

	# Lower dark walnut wainscoting dado + stone sill
	_box(self, Vector3(wx, dado_h * 0.5, cz), Vector3(0.18, dado_h, bay_w), _mat_wood)
	_box(self, Vector3(wx + inward_x * 0.06, 0.14, cz), Vector3(0.14, 0.28, bay_w), _mat_plinth)
	_box(self, Vector3(wx + inward_x * 0.08, dado_h, cz), Vector3(0.24, 0.12, bay_w), _mat_rib)

	# Upper stone wall backing behind the lancets
	_box(self, Vector3(wx - inward_x * 0.06, (dado_h + win_top) * 0.5, cz), Vector3(0.12, win_top - dado_h, bay_w), _mat_wall)
	# Top cornice molding
	_box(self, Vector3(wx + inward_x * 0.06, win_top, cz), Vector3(0.22, 0.16, bay_w), _mat_rib)
	# Center stone mullion between paired lancets
	_box(self, Vector3(wx + inward_x * 0.04, (dado_h + win_top) * 0.5, cz), Vector3(0.16, win_top - dado_h, 0.16), _mat_rib)

	# Paired pointed stained-glass lancets with real planar UVs
	var l_span := (bay_w - 0.72) * 0.5
	var lhw := l_span * 0.44
	var spring_y := lerpf(dado_h, win_top, 0.62)
	var peak_y := win_top - 0.18
	var denom := sqrt(1.0 - pow(0.35 / 1.35, 2.0))

	var glass_mat := _make_stained_glass_mat(tex, Color("6c98c4"), 0.52)
	var frame_st := SurfaceTool.new()
	frame_st.begin(Mesh.PRIMITIVE_TRIANGLES)

	for k in 2:
		var lcz := cz + (-0.5 if k == 0 else 0.5) * (l_span + 0.16)
		var curve := PackedVector3Array()
		var steps := 12
		for i in range(steps + 1):
			var lz := -lhw + 2.0 * lhw * float(i) / float(steps)
			var u := (absf(lz) / lhw + 0.35) / 1.35
			var ly := spring_y + (peak_y - spring_y) * sqrt(maxf(0.0, 1.0 - u * u)) / denom
			curve.append(Vector3(wx + inward_x * 0.09, ly, lcz + lz))

		# UV-mapped stained glass pane
		var gst := SurfaceTool.new()
		gst.begin(Mesh.PRIMITIVE_TRIANGLES)
		var normal := Vector3(inward_x, 0.0, 0.0)
		for i in steps:
			var a := curve[i]
			var b := curve[i + 1]
			var u0 := (float(variant) + (float(k) + float(i) / float(steps)) * 0.5) / 4.0
			var u1 := (float(variant) + (float(k) + float(i + 1) / float(steps)) * 0.5) / 4.0
			var v_a := (a.y - dado_h) / (peak_y - dado_h)
			var v_b := (b.y - dado_h) / (peak_y - dado_h)
			var p0 := Vector3(wx + inward_x * 0.03, dado_h + 0.05, a.z)
			var p1 := Vector3(wx + inward_x * 0.03, dado_h + 0.05, b.z)
			var p2 := Vector3(wx + inward_x * 0.03, b.y, b.z)
			var p3 := Vector3(wx + inward_x * 0.03, a.y, a.z)
			if inward_x > 0.0:
				_add_uv_quad(gst, p0, p1, p2, p3, Vector2(u0, 1.0), Vector2(u1, 1.0), Vector2(u1, 1.0 - v_b), Vector2(u0, 1.0 - v_a), normal)
			else:
				_add_uv_quad(gst, p1, p0, p3, p2, Vector2(u1, 1.0), Vector2(u0, 1.0), Vector2(u0, 1.0 - v_a), Vector2(u1, 1.0 - v_b), normal)
		_commit_mesh(gst, glass_mat, "LancetGlass_%d_%d" % [variant, k])

		# Moulded stone pointed arch frame
		var fpath := PackedVector3Array([Vector3(wx + inward_x * 0.09, dado_h + 0.04, lcz - lhw)])
		fpath.append_array(curve)
		fpath.append(Vector3(wx + inward_x * 0.09, dado_h + 0.04, lcz + lhw))
		_sweep_rib(frame_st, fpath, 0.05)

		# Lead transoms
		for frac in [0.36, 0.68]:
			_box(self, Vector3(wx + inward_x * 0.05, lerpf(dado_h, spring_y, frac), lcz), Vector3(0.03, 0.025, lhw * 2.0), _mat_lead)

	frame_st.generate_normals()
	_commit_mesh(frame_st, _mat_rib, "LancetFrames_%d" % variant)

func _build_end_gable_wall(min_x: float, max_x: float, wz: float, inward_z: float, is_north: bool, rose_tex: Texture2D, _lot: Dictionary) -> void:
	var cx := (min_x + max_x) * 0.5
	var hx := (max_x - min_x) * 0.5
	var span_x := max_x - min_x

	# Pointed gable stone wall matching the exact nave vault profile (zero clipping!)
	var wst := SurfaceTool.new()
	wst.begin(Mesh.PRIMITIVE_TRIANGLES)
	var segs := 20
	var normal := Vector3(0.0, 0.0, inward_z)
	for i in segs:
		var nx0 := -1.0 + 2.0 * float(i) / float(segs)
		var nx1 := -1.0 + 2.0 * float(i + 1) / float(segs)
		var x0 := cx + nx0 * hx
		var x1 := cx + nx1 * hx
		var y0 := SPRING_H + _pointed_arch_y(nx0) + 0.12
		var y1 := SPRING_H + _pointed_arch_y(nx1) + 0.12
		var p0 := Vector3(x0, 0.0, wz)
		var p1 := Vector3(x1, 0.0, wz)
		var p2 := Vector3(x1, y1, wz)
		var p3 := Vector3(x0, y0, wz)
		if inward_z > 0.0:
			_add_quad(wst, p0, p3, p2, p1)
		else:
			_add_quad(wst, p1, p2, p3, p0)
	wst.generate_normals()
	_commit_mesh(wst, _mat_wall, "GableWall_" + ("North" if is_north else "South"))

	# Lower walnut wainscoting & horizontal stone stringcourse at y = 2.65m
	_box(self, Vector3(cx, 0.69, wz + inward_z * 0.06), Vector3(span_x, 1.38, 0.12), _mat_wood)
	_box(self, Vector3(cx, 1.40, wz + inward_z * 0.09), Vector3(span_x, 0.12, 0.18), _mat_rib)
	_box(self, Vector3(cx, 2.68, wz + inward_z * 0.09), Vector3(span_x, 0.14, 0.22), _mat_rib)

	# North end: architectural stone surrounds for the two departure gates + central blind arcade sanctuary
	if is_north:
		for gate_x in [min_x + 1.5, max_x - 1.5]:
			_box(self, Vector3(gate_x - 0.64, 1.25, wz + inward_z * 0.12), Vector3(0.18, 2.50, 0.24), _mat_rib)
			_box(self, Vector3(gate_x + 0.64, 1.25, wz + inward_z * 0.12), Vector3(0.18, 2.50, 0.24), _mat_rib)
			var arch := SurfaceTool.new()
			arch.begin(Mesh.PRIMITIVE_TRIANGLES)
			var profile := PackedVector3Array()
			for i in 17:
				var u := (i - 8.0) / 8.0
				profile.append(Vector3(gate_x + u * 0.64, 2.48 + 0.55 * sqrt(1.0 - absf(u)), wz + inward_z * 0.17))
			_sweep_rib(arch, profile, 0.085)
			arch.generate_normals()
			_commit_mesh(arch, _mat_rib, "PortalArchivolt")
			# Recessed oak gate panel so doorway never looks like a black void
			_box(self, Vector3(gate_x, 1.22, wz + inward_z * 0.04), Vector3(1.12, 2.42, 0.08), _mat_wood)
			_box(self, Vector3(gate_x, 1.22, wz + inward_z * 0.09), Vector3(0.06, 2.38, 0.04), _mat_brass)

	# High Notre-Dame 12-spoke Radial Rose Window cleanly seated in the upper gable (y = 4.25m, r = 1.22m)
	var rose_root := Node3D.new()
	rose_root.name = "HallRose_" + ("North" if is_north else "South")
	rose_root.position = Vector3(cx, 4.95, wz + inward_z * 0.10)
	add_child(rose_root)

	var r := 1.42
	var disc_segs := 36
	var glass_mat := _make_stained_glass_mat(rose_tex, Color("6c92c9"), 0.72)

	# UV-mapped circular stained glass disc
	var dst := SurfaceTool.new()
	dst.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in disc_segs:
		var a0 := TAU * float(i) / float(disc_segs)
		var a1 := TAU * float(i + 1) / float(disc_segs)
		var p_c := Vector3(0.0, 0.0, 0.0)
		var p0 := Vector3(cos(a0) * r, sin(a0) * r, 0.0)
		var p1 := Vector3(cos(a1) * r, sin(a1) * r, 0.0)
		var uv_c := Vector2(0.5, 0.5)
		var uv0 := Vector2(0.5 + 0.5 * cos(a0), 0.5 - 0.5 * sin(a0))
		var uv1 := Vector2(0.5 + 0.5 * cos(a1), 0.5 - 0.5 * sin(a1))
		if inward_z > 0.0:
			_add_uv_tri(dst, p_c, p1, p0, uv_c, uv1, uv0, normal)
		else:
			_add_uv_tri(dst, p_c, p0, p1, uv_c, uv0, uv1, normal)
	_commit_mesh(dst, glass_mat, "RoseGlass", rose_root)

	# Radial stonework (outer ring, hub ring, 12 spokes + outer gothic tracery branches)
	var tst := SurfaceTool.new()
	tst.begin(Mesh.PRIMITIVE_TRIANGLES)
	var z_off := inward_z * 0.05
	for ring_r in [r, r * 0.58, r * 0.20]:
		var rpts := PackedVector3Array()
		for i in range(disc_segs + 1):
			var a := TAU * float(i) / float(disc_segs)
			rpts.append(Vector3(cos(a) * ring_r, sin(a) * ring_r, z_off))
		_sweep_rib(tst, rpts, 0.055 if ring_r == r else 0.028)
	for k in 12:
		var a := (float(k) + 0.5) * TAU / 12.0
		var p_in := Vector3(cos(a) * r * 0.20, sin(a) * r * 0.20, z_off)
		var p_out := Vector3(cos(a) * r, sin(a) * r, z_off)
		_sweep_rib(tst, PackedVector3Array([p_in, p_out]), 0.022)
	tst.generate_normals()
	_commit_mesh(tst, _mat_rib, "RoseTracery", rose_root)

	# Soft cool stained-glass spill light inside the gable
	var rlight := OmniLight3D.new()
	rlight.position = Vector3(0.0, -0.1, inward_z * 0.9)
	rlight.light_color = Color("9abce8") if is_north else Color("d8b896")
	rlight.light_energy = 0.55
	rlight.omni_range = 6.5
	rlight.shadow_enabled = false
	rose_root.add_child(rlight)

func _build_floor_runner(cx: float, min_z: float, max_z: float, span: float) -> void:
	for side: float in [-1.0, 1.0]:
		var x := cx + side * span * 0.31
		var z := (min_z + max_z) * 0.5
		_box(self, Vector3(x, 0.012, z), Vector3(1.18, 0.016, max_z - min_z), _mat_runner)
		for hem: float in [-0.56, 0.56]:
			_box(self, Vector3(x + hem, 0.022, z), Vector3(0.022, 0.004, max_z - min_z), _mat_wood)

func _build_nave_lanterns(min_x: float, max_x: float, min_z: float, bay_len: float, bays_z: int) -> void:
	for bi in bays_z:
		var lz := min_z + (float(bi) + 0.5) * bay_len
		for lx in [min_x + 1.55, max_x - 1.55]:
			var lamp := OilLamp.instantiate()
			lamp.hang_length = 1.25
			lamp.light_energy = 1.55
			lamp.shadow_enabled = false
			lamp.scale = Vector3.ONE * 1.32
			lamp.position = Vector3(lx, SPRING_H + 0.90, lz)
			add_child(lamp)

func _build_foucault_pendulum(anchor: Vector3, well: Rect2i) -> void:
	var root := Node3D.new()
	root.name = "FoucaultPendulum"
	root.position = anchor
	add_child(root)

	var ceiling_y := CROWN_H + 0.02

	# Ceiling bronze suspension rosette
	var cap := MeshInstance3D.new()
	var cap_mesh := CylinderMesh.new()
	cap_mesh.top_radius = 0.28
	cap_mesh.bottom_radius = 0.18
	cap_mesh.height = 0.22
	cap.mesh = cap_mesh
	cap.position = Vector3(0.0, ceiling_y, 0.0)
	cap.material_override = _mat_brass
	root.add_child(cap)

	pendulum_pivot = Node3D.new()
	pendulum_pivot.name = "PendulumPivot"
	pendulum_pivot.position = Vector3(0.0, ceiling_y - 0.08, 0.0)
	root.add_child(pendulum_pivot)

	var cable_len := ceiling_y - 1.07
	var cable := MeshInstance3D.new()
	var cable_mesh := CylinderMesh.new()
	cable_mesh.top_radius = 0.010
	cable_mesh.bottom_radius = 0.010
	cable_mesh.height = cable_len
	cable.mesh = cable_mesh
	cable.position = Vector3(0.0, -cable_len * 0.5, 0.0)
	cable.material_override = _mat_lead
	pendulum_pivot.add_child(cable)

	# Heavy turned brass bob + equatorial collar + plumb pointer
	pendulum_bob = Node3D.new()
	pendulum_bob.name = "PendulumBob"
	pendulum_bob.position = Vector3(0.0, -cable_len, 0.0)
	pendulum_bob.scale = Vector3.ONE * 1.65
	pendulum_pivot.add_child(pendulum_bob)

	var sphere := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 0.20
	sm.height = 0.40
	sphere.mesh = sm
	sphere.material_override = _mat_brass
	pendulum_bob.add_child(sphere)

	var equator := MeshInstance3D.new()
	var tm := TorusMesh.new()
	tm.inner_radius = 0.20
	tm.outer_radius = 0.245
	equator.mesh = tm
	equator.material_override = _mat_brass
	pendulum_bob.add_child(equator)

	var needle := MeshInstance3D.new()
	var nm := CylinderMesh.new()
	nm.top_radius = 0.04
	nm.bottom_radius = 0.004
	nm.height = 0.28
	needle.mesh = nm
	needle.position = Vector3(0.0, -0.30, 0.0)
	needle.material_override = _mat_brass
	pendulum_bob.add_child(needle)

	# Sleek flush brass/crimson calibration bezel sitting flat on the MeridianWell rim
	var well_r := (float(well.size.x) * 0.46) if well.has_area() else 1.25
	drift_bezel = MeshInstance3D.new()
	var ring_mesh := TorusMesh.new()
	ring_mesh.inner_radius = well_r - 0.028
	ring_mesh.outer_radius = well_r
	drift_bezel.mesh = ring_mesh
	drift_bezel.position = Vector3(0.0, 0.022, 0.0)
	var ring_mat := StandardMaterial3D.new()
	ring_mat.roughness = 0.35
	ring_mat.metallic = 0.5
	ring_mat.emission_enabled = true
	drift_bezel.material_override = ring_mat
	root.add_child(drift_bezel)

	essence_light = OmniLight3D.new()
	essence_light.position = Vector3(0.0, 0.72, 0.0)
	essence_light.omni_range = 4.2
	essence_light.shadow_enabled = false
	root.add_child(essence_light)
	set_drift_state(drifting)

func set_drift_state(is_drifting: bool) -> void:
	drifting = is_drifting
	if is_instance_valid(drift_bezel) and drift_bezel.material_override is StandardMaterial3D:
		var rm := drift_bezel.material_override as StandardMaterial3D
		rm.albedo_color = Color("9e3a2b") if drifting else Color("4d8f75")
		rm.emission = rm.albedo_color
		rm.emission_energy_multiplier = 0.45 if drifting else 0.22
	if is_instance_valid(essence_light):
		essence_light.light_color = Color("f08a62") if drifting else Color("ffe0a3")
		essence_light.light_energy = 1.25 if drifting else 0.90

func _build_functional_props(min_z: float) -> void:
	# Watch Cot Alcove (using real ArchBuilder RecipeBed + RecipeBankerLamp)
	var cot_root := Node3D.new()
	cot_root.name = "WatchCotAlcove"
	cot_root.position = watch_cot_pos
	add_child(cot_root)
	var bed := Factory.create("res://tools/building_construction/BuildingConstruction/Beds/RecipeBed.gd")
	if bed != null:
		bed.scale = Vector3(0.82, 0.82, 0.82)
		bed.rotation.y = PI * 0.5
		cot_root.add_child(bed)

	# Essence Calibration Lectern (using real ArchBuilder RecipeLectern)
	var lec_root := Node3D.new()
	lec_root.name = "EssenceCalibrationLectern"
	lec_root.position = Vector3(pendulum_world_pos.x, 0.0, min_z + 1.35)
	add_child(lec_root)
	var lectern := Factory.create("res://tools/building_construction/BuildingConstruction/Tables/RecipeReceptionDesk.gd")
	if lectern != null:
		lectern.rotation.y = PI
		lec_root.add_child(lectern)
		var globe := Factory.create("res://tools/building_construction/BuildingConstruction/Props/RecipeArmillary.gd")
		globe.position = Vector3(0.42, 1.08, 0.0)
		globe.scale = Vector3.ONE * 0.52
		lec_root.add_child(globe)

func _make_stained_glass_mat(tex: Texture2D, fallback: Color, _emit_gain: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	if tex != null:
		m.albedo_texture = tex
		m.albedo_color = Color(0.84, 0.87, 0.94, 1.0)
	else:
		m.albedo_color = fallback
	return m

static func _load_texture(path: String) -> Texture2D:
	if ResourceLoader.exists(path):
		return load(path) as Texture2D
	return null

func _commit_mesh(st: SurfaceTool, mat: Material, mesh_name: String, parent: Node3D = null) -> MeshInstance3D:
	var mesh := st.commit()
	var inst := MeshInstance3D.new()
	inst.name = mesh_name
	inst.mesh = mesh
	inst.material_override = mat
	inst.gi_mode = GeometryInstance3D.GI_MODE_STATIC
	(self if parent == null else parent).add_child(inst)
	return inst

static func _add_quad(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3) -> void:
	st.add_vertex(a); st.add_vertex(b); st.add_vertex(c)
	st.add_vertex(a); st.add_vertex(c); st.add_vertex(d)

static func _add_uv_quad(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3, uva: Vector2, uvb: Vector2, uvc: Vector2, uvd: Vector2, n: Vector3) -> void:
	_add_uv_tri(st, a, b, c, uva, uvb, uvc, n)
	_add_uv_tri(st, a, c, d, uva, uvc, uvd, n)

static func _add_uv_tri(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, uva: Vector2, uvb: Vector2, uvc: Vector2, n: Vector3) -> void:
	st.set_normal(n); st.set_uv(uva); st.add_vertex(a)
	st.set_normal(n); st.set_uv(uvb); st.add_vertex(b)
	st.set_normal(n); st.set_uv(uvc); st.add_vertex(c)

static func _sweep_rib(st: SurfaceTool, path: PackedVector3Array, r: float) -> void:
	if path.size() < 2:
		return
	var sides := 6
	var rings: Array = []
	var prev_side := Vector3.ZERO
	for i in path.size():
		var p_prev := path[maxi(i - 1, 0)]
		var p_next := path[mini(i + 1, path.size() - 1)]
		var t := (p_next - p_prev).normalized()
		if t.length_squared() < 1e-6:
			t = Vector3.UP
		var ref := Vector3.UP if absf(t.y) < 0.92 else Vector3.RIGHT
		var side := t.cross(ref).normalized()
		if prev_side.length_squared() > 0.01 and prev_side.dot(side) < 0.0:
			side = -side
		prev_side = side
		var up := side.cross(t).normalized()
		var ring: Array = []
		for k in sides:
			var ang := TAU * float(k) / float(sides)
			ring.append(path[i] + (side * cos(ang) + up * sin(ang)) * r)
		rings.append(ring)
	for i in path.size() - 1:
		for k in sides:
			var kn := (k + 1) % sides
			_add_quad(st, rings[i][k], rings[i][kn], rings[i + 1][kn], rings[i + 1][k])

static func _box(parent: Node3D, p: Vector3, sz: Vector3, mat: Material) -> void:
	var inst := MeshInstance3D.new()
	var b := BoxMesh.new()
	b.size = sz
	inst.mesh = b
	inst.position = p
	inst.material_override = mat
	inst.gi_mode = GeometryInstance3D.GI_MODE_STATIC
	parent.add_child(inst)

func _process(delta: float) -> void:
	if not is_instance_valid(pendulum_pivot):
		return
	_time += delta
	if drifting:
		var base_phase := _time * 1.15
		var stutter := 0.055 * sin(_time * 3.45) * maxf(0.0, sin(base_phase))
		var swing := 0.22 * sin(base_phase) + stutter
		pendulum_pivot.rotation = Vector3(swing * sin(_drift_angle), _drift_angle + 0.04 * sin(_time * 0.4), swing * cos(_drift_angle))
		if is_instance_valid(essence_light):
			essence_light.light_energy = 1.15 + 0.35 * sin(_time * 4.0)
	else:
		var swing := 0.19 * sin(_time * 1.05)
		var slow_precession := fmod(_time * 0.025, TAU)
		pendulum_pivot.rotation = Vector3(swing * sin(slow_precession), slow_precession, swing * cos(slow_precession))
		if is_instance_valid(essence_light):
			essence_light.light_energy = 0.85 + 0.06 * sin(_time * 1.2)
