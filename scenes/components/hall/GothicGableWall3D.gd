@tool
class_name GothicGableWall3D
extends GothicHallPiece3D
## Full-height pointed gable end wall matching the vault profile, with walnut wainscot,
## stringcourses, optional departure portals, and a stained-glass rose window (tracery,
## rose spot, halo, Tyndall beam, floor caustic). Local origin = west end of the wall line;
## the wall runs along +X for `width`; `inward` (±1) is the room side along Z.

@export var width := 10.0:
	set(v): width = v; shape_changed()
@export var inward := 1.0:
	set(v): inward = v; changed()
## North palette (cool) and naming; false = south palette (warm).
@export var north := true:
	set(v): north = v; changed()
@export var portals := true:
	set(v): portals = v; changed()
## Distance of each portal from the wall ends.
@export var portal_inset := 1.5:
	set(v): portal_inset = v; changed()
@export var rose_height := 6.28:
	set(v): rose_height = v; changed()
@export var rose_texture: Texture2D:
	set(v): rose_texture = v; changed()

func shape_key() -> Array: return [width]
func plan_outline() -> PackedVector2Array: return _rect_outline(Rect2(0, -0.1, width, 0.3))

func _build() -> void:
	var rose_tex := rose_texture if rose_texture else load_texture(ROSE_NORTH_TEX if north else ROSE_SOUTH_TEX)
	var min_x := 0.0
	var max_x := width
	var wz := 0.0
	var inward_z := inward
	var is_north := north
	var cx := (min_x + max_x) * 0.5
	var hx := (max_x - min_x) * 0.5
	var span_x := max_x - min_x
	var tag := "North" if is_north else "South"
	var wst := SurfaceTool.new()
	wst.begin(Mesh.PRIMITIVE_TRIANGLES)
	var segs := 20
	var normal := Vector3(0.0, 0.0, inward_z)
	for i in segs:
		var nx0 := -1.0 + 2.0 * float(i) / float(segs)
		var nx1 := -1.0 + 2.0 * float(i + 1) / float(segs)
		var x0 := cx + nx0 * hx
		var x1 := cx + nx1 * hx
		var p0 := Vector3(x0, 0.0, wz)
		var p1 := Vector3(x1, 0.0, wz)
		var p2 := Vector3(x1, SPRING_H + pointed_arch_y(nx1) + 0.12, wz)
		var p3 := Vector3(x0, SPRING_H + pointed_arch_y(nx0) + 0.12, wz)
		if inward_z > 0.0:
			_add_quad(wst, p0, p3, p2, p1)
		else:
			_add_quad(wst, p1, p2, p3, p0)
	wst.generate_normals()
	_commit_mesh(wst, mat("wall"), "GableWall_" + tag)
	_box(self, Vector3(cx, 0.69, wz + inward_z * 0.06), Vector3(span_x, 1.38, 0.12), mat("wood"))
	_box(self, Vector3(cx, 1.40, wz + inward_z * 0.09), Vector3(span_x, 0.12, 0.18), mat("rib"))
	_box(self, Vector3(cx, 2.68, wz + inward_z * 0.09), Vector3(span_x, 0.14, 0.22), mat("rib"))
	if portals:
		for gate_x in [min_x + portal_inset, max_x - portal_inset]:
			_box(self, Vector3(gate_x - 0.64, 1.25, wz + inward_z * 0.12), Vector3(0.18, 2.50, 0.24), mat("rib"))
			_box(self, Vector3(gate_x + 0.64, 1.25, wz + inward_z * 0.12), Vector3(0.18, 2.50, 0.24), mat("rib"))
			var arch := SurfaceTool.new()
			arch.begin(Mesh.PRIMITIVE_TRIANGLES)
			var profile := PackedVector3Array()
			for i in 17:
				var u := (i - 8.0) / 8.0
				profile.append(Vector3(gate_x + u * 0.64, 2.48 + 0.55 * sqrt(1.0 - absf(u)), wz + inward_z * 0.17))
			_sweep_rib(arch, profile, 0.085)
			arch.generate_normals()
			_commit_mesh(arch, mat("rib"), "PortalArchivolt")
			for i in 16:
				var height := minf(profile[i].y, profile[i + 1].y)
				var px := (profile[i].x + profile[i + 1].x) * 0.5
				_box(self, Vector3(px, height * 0.5, wz + inward_z * 0.205), Vector3(0.079, height, 0.055), mat("wood"))
			for dx: float in [-0.31, 0.31]:
				for h: float in [0.46, 1.88]:
					_box(self, Vector3(gate_x + dx, h, wz + inward_z * 0.25), Vector3(0.54, 0.072, 0.055), mat("brass"))
			_box(self, Vector3(gate_x, 1.42, wz + inward_z * 0.25), Vector3(0.045, 2.84, 0.055), mat("brass"))
	var rose_root := Node3D.new()
	rose_root.name = "HallRose_" + tag
	rose_root.position = Vector3(cx, rose_height, wz + inward_z * 0.10)
	add_child(rose_root)
	var r := 1.95
	var disc_segs := 36
	var glass_mat := _make_stained_glass_mat(rose_tex, Color("6c92c9"), 0.72)
	var dst := SurfaceTool.new()
	dst.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in disc_segs:
		var a0 := TAU * float(i) / float(disc_segs)
		var a1 := TAU * float(i + 1) / float(disc_segs)
		var p0 := Vector3(cos(a0) * r, sin(a0) * r, 0.0)
		var p1 := Vector3(cos(a1) * r, sin(a1) * r, 0.0)
		var uv0 := Vector2(0.5 + 0.5 * cos(a0), 0.5 - 0.5 * sin(a0))
		var uv1 := Vector2(0.5 + 0.5 * cos(a1), 0.5 - 0.5 * sin(a1))
		if inward_z > 0.0:
			_add_uv_tri(dst, Vector3.ZERO, p1, p0, Vector2(0.5, 0.5), uv1, uv0, normal)
		else:
			_add_uv_tri(dst, Vector3.ZERO, p0, p1, Vector2(0.5, 0.5), uv0, uv1, normal)
	_commit_mesh(dst, glass_mat, "RoseGlass", rose_root)
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
		_sweep_rib(tst, PackedVector3Array([Vector3(cos(a) * r * 0.20, sin(a) * r * 0.20, z_off), Vector3(cos(a) * r, sin(a) * r, z_off)]), 0.022)
	tst.generate_normals()
	_commit_mesh(tst, mat("rib"), "RoseTracery", rose_root)
	var tint := Color("b8d8ff") if is_north else Color("ffe0b2")
	var rlight := OmniLight3D.new()
	rlight.position = Vector3(0.0, -0.1, inward_z * 0.9)
	rlight.light_color = Color("9abce8") if is_north else Color("d8b896")
	rlight.light_energy = 0.55
	rlight.light_specular = 0.0
	rlight.omni_range = 13.0
	rlight.shadow_enabled = false
	rose_root.add_child(rlight)
	_window_lights.append({"light": rlight, "night": 0.0, "day": 3.4, "tint": tint})
	var rose_dir := Vector3(0.0, -0.46, inward_z).normalized()
	_build_tyndall_beam(rose_root, Vector3(0.0, -0.06, inward_z * 0.16), rose_dir,
		1.42, 2.55, 12.2, rose_tex, Color("7fa6de") if is_north else Color("d8b088"),
		Vector4(0.0, 0.0, 1.0, 1.0), 0.38, "RoseBeam_" + tag)
	var rose_spot := _aimed_spot(rose_root, Vector3(0.0, 0.0, inward_z * 0.45), rose_dir)
	rose_spot.spot_range = 24.0
	rose_spot.spot_angle = 48.0
	rose_spot.spot_attenuation = 0.95
	rose_spot.light_specular = 0.0
	rose_spot.shadow_enabled = false
	if rose_tex != null:
		rose_spot.light_projector = rose_tex
	_window_lights.append({"light": rose_spot, "night": 0.0, "day": 7.2, "tint": tint})
	var rose_halo_s := r * 2.55
	_build_glass_glow_quad(rose_root, Vector3(0.0, 0.0, inward_z * 0.14), Vector3(1.0, 0.0, 0.0) * rose_halo_s, Vector3(0.0, 1.0, 0.0) * rose_halo_s,
		Vector3(0.0, 0.0, inward_z), rose_tex, Color("74a8f0") if is_north else Color("f2be84"),
		Vector4(0.0, 0.0, 1.0, 1.0), 0.36, 1.0, "RoseHalo_" + tag)
	_build_glass_glow_quad(self, Vector3(cx, 0.035, wz + inward_z * 6.8), Vector3(1.0, 0.0, 0.0) * 5.2, Vector3(0.0, 0.0, 1.0) * 5.6,
		Vector3.UP, rose_tex, Color("84b6ff") if is_north else Color("f4c48e"),
		Vector4(0.0, 0.0, 1.0, 1.0), 0.32, 1.0, "RoseFloorCaustic_" + tag)
