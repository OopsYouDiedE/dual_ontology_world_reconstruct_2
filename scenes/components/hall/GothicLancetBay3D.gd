@tool
class_name GothicLancetBay3D
extends GothicHallPiece3D
## One wall bay with walnut dado, stone backing, cornice, mullion and a pair of pointed
## stained-glass lancets (with Tyndall beams, halo, window spot and floor caustic).
## Local origin = wall line at the bay's start; the bay runs along +Z for `length`.

@export var length := 4.0:
	set(v): length = v; shape_changed()
## +1 = the interior is toward +X, -1 = toward -X.
@export var inward := 1.0:
	set(v): inward = v; changed()
## Which quarter of the lancet glass sheet this bay shows (0..3).
@export_range(0, 3) var variant := 0:
	set(v): variant = v; changed()
@export var window_top := SPRING_H + 0.15:
	set(v): window_top = v; changed()
@export var glass_texture: Texture2D:
	set(v): glass_texture = v; changed()

func shape_key() -> Array: return [length]
func plan_outline() -> PackedVector2Array: return _rect_outline(Rect2(-0.15, 0, 0.3, length))

func _build() -> void:
	var tex := glass_texture if glass_texture else load_texture(LANCET_TEX)
	var wx := 0.0
	var inward_x := inward
	var z0 := 0.0
	var z1 := length
	var win_top := window_top
	var bay_w := z1 - z0
	var cz := (z0 + z1) * 0.5
	var dado_h := 1.38
	_box(self, Vector3(wx, dado_h * 0.5, cz), Vector3(0.18, dado_h, bay_w), mat("wood"))
	_box(self, Vector3(wx + inward_x * 0.06, 0.14, cz), Vector3(0.14, 0.28, bay_w), mat("plinth"))
	_box(self, Vector3(wx + inward_x * 0.08, dado_h, cz), Vector3(0.24, 0.12, bay_w), mat("rib"))
	var panel_ribs := SurfaceTool.new(); panel_ribs.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in 5:
		var pz := z0 + (i + 0.5) * bay_w / 5.0
		var px := wx + inward_x * 0.125
		var profile := PackedVector3Array([Vector3(px, 0.24, pz - 0.31), Vector3(px, 0.94, pz - 0.31), Vector3(px, 1.09, pz - 0.21), Vector3(px, 1.25, pz), Vector3(px, 1.09, pz + 0.21), Vector3(px, 0.94, pz + 0.31), Vector3(px, 0.24, pz + 0.31)])
		_sweep_rib(panel_ribs, profile, 0.037)
	panel_ribs.generate_normals(); _commit_mesh(panel_ribs, mat("wood"), "WalnutArcade")
	_box(self, Vector3(wx - inward_x * 0.06, (dado_h + win_top) * 0.5, cz), Vector3(0.12, win_top - dado_h, bay_w), mat("wall"))
	_box(self, Vector3(wx + inward_x * 0.06, win_top, cz), Vector3(0.22, 0.16, bay_w), mat("rib"))
	_box(self, Vector3(wx + inward_x * 0.04, (dado_h + win_top) * 0.5, cz), Vector3(0.16, win_top - dado_h, 0.16), mat("rib"))
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
		var fpath := PackedVector3Array([Vector3(wx + inward_x * 0.09, dado_h + 0.04, lcz - lhw)])
		fpath.append_array(curve)
		fpath.append(Vector3(wx + inward_x * 0.09, dado_h + 0.04, lcz + lhw))
		_sweep_rib(frame_st, fpath, 0.05)
		for frac in [0.36, 0.68]:
			_box(self, Vector3(wx + inward_x * 0.05, lerpf(dado_h, spring_y, frac), lcz), Vector3(0.03, 0.025, lhw * 2.0), mat("lead"))
		var u_slice_0 := (float(variant) + float(k) * 0.5) / 4.0
		var u_slice_1 := (float(variant) + (float(k) + 1.0) * 0.5) / 4.0
		var beam_len := 4.4 if win_top < SPRING_H else 7.2
		var beam_dir := Vector3(inward_x, -0.46, 0.14).normalized()
		_build_tyndall_beam(self, Vector3(wx + inward_x * 0.08, lerpf(dado_h, spring_y, 0.58), lcz), beam_dir,
			0.36, 0.80, beam_len, tex, Color("6c98c4"), Vector4(u_slice_0, 0.08, u_slice_1, 0.92), 0.27,
			"LancetBeam_%d_%d" % [variant, k])
	frame_st.generate_normals()
	_commit_mesh(frame_st, mat("rib"), "LancetFrames_%d" % variant)
	var bay_spot := _aimed_spot(self, Vector3(wx + inward_x * 0.36, spring_y, cz), Vector3(inward_x, -0.46, 0.14))
	bay_spot.spot_range = 10.5 if win_top < SPRING_H else 16.5
	bay_spot.spot_angle = 52.0
	bay_spot.spot_attenuation = 1.0
	bay_spot.light_specular = 0.0
	bay_spot.shadow_enabled = false
	if tex != null:
		bay_spot.light_projector = tex
	_window_lights.append({"light": bay_spot, "night": 0.0, "day": 5.6})
	var bay_u0 := float(variant) / 4.0
	var bay_u1 := float(variant + 1) / 4.0
	_build_glass_glow_quad(self, Vector3(wx + inward_x * 0.14, (dado_h + win_top) * 0.5, cz), Vector3(0.0, 0.0, 1.0) * bay_w * 0.92,
		Vector3(0.0, 1.0, 0.0) * (win_top - dado_h) * 1.06, Vector3(inward_x, 0.0, 0.0),
		tex, Color("5a92e0"), Vector4(bay_u0, 0.04, bay_u1, 0.96), 0.30, 0.0, "LancetHalo_%d" % variant)
	if win_top >= SPRING_H:
		_build_glass_glow_quad(self, Vector3(wx + inward_x * 3.15, 0.032, cz + 0.55), Vector3(inward_x, 0.0, 0.12).normalized() * 3.8,
			Vector3(0.0, 0.0, 1.0) * (bay_w * 0.88), Vector3.UP,
			tex, Color("6ca4ee"), Vector4(bay_u0, 0.08, bay_u1, 0.92), 0.36, 0.0, "LancetFloorCaustic_%d" % variant)
