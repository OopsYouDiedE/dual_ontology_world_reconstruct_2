@tool
extends RefCounted
## Procedural French Gothic architectural recipes ported from
## tools/research/french_gothic_nodes/ (assembly.py, full_structure.py, wall_lining.py)
## into native ArchBuilder Z-up RecipeGeometry space.

const Geo = preload("../../BuildingConstruction/Shared/RecipeGeometry.gd")

static func _tube(label: String, path: Array, radius: float, mat, parent, sides: int = 8):
	if path.size() < 2:
		return null
	var verts: Array = []
	var faces: Array = []
	var n_pts := path.size()
	var prev_side := Vector3.ZERO
	for i in n_pts:
		var p_curr := Geo.vec(path[i])
		var p_prev := Geo.vec(path[maxi(i - 1, 0)])
		var p_next := Geo.vec(path[mini(i + 1, n_pts - 1)])
		var tangent := (p_next - p_prev).normalized()
		if tangent.length_squared() < 1e-6:
			tangent = Vector3(0.0, 0.0, 1.0)
		var ref := Vector3(0.0, 1.0, 0.0) if absf(tangent.y) < 0.92 else Vector3(1.0, 0.0, 0.0)
		var side := tangent.cross(ref).normalized()
		if prev_side.length_squared() > 0.01 and prev_side.dot(side) < 0.0:
			side = -side
		prev_side = side
		var up := side.cross(tangent).normalized()
		for k in sides:
			var ang := TAU * float(k) / float(sides)
			var pt := p_curr + (side * cos(ang) + up * sin(ang)) * radius
			verts.append([pt.x, pt.y, pt.z])
	for i in n_pts - 1:
		var r0 := i * sides
		var r1 := (i + 1) * sides
		for k in sides:
			var kn := (k + 1) % sides
			faces.append([r0 + k, r0 + kn, r1 + kn, r1 + k])
	var start_cap: Array = []
	var end_cap: Array = []
	for k in sides:
		start_cap.append(sides - 1 - k)
		end_cap.append((n_pts - 1) * sides + k)
	faces.append(start_cap)
	faces.append(end_cap)
	return Geo.gen_mesh(label, verts, faces, mat, parent, 0)

static func _qbez(p0: Vector3, p1: Vector3, p2: Vector3, t: float) -> Vector3:
	var u := 1.0 - t
	return p0 * (u * u) + p1 * (2.0 * u * t) + p2 * (t * t)

static func _pointed_rib_path(dx: float, dy: float, rise: float, segs: int, sign_dir: float, z0: float = 0.0) -> Array:
	var p0 := Vector3(dx * sign_dir, dy * sign_dir, z0)
	var p1 := Vector3(dx * sign_dir, dy * sign_dir, z0 + rise * 0.64)
	var p2 := Vector3(0.0, 0.0, z0 + rise)
	var pts: Array = []
	for i in range(segs + 1):
		var v := _qbez(p0, p1, p2, float(i) / float(segs))
		pts.append([v.x, v.y, v.z])
	return pts

## Direct port of FG | Pointed rib (assembly.py).
static func gen_gothic_pointed_rib(label: String, mats: Dictionary, dx: float = 2.1, dy: float = 0.0, rise: float = 1.6, radius: float = 0.12, segments: int = 12, parent = null):
	var group = Geo.gen_group(label, [0, 0, 0], 0, parent)
	var segs := maxi(4, int(segments))
	var r := clampf(float(radius), 0.03, 0.5)
	var mat = mats.get("cream", mats.stone)
	_tube(label + "_HalfA", _pointed_rib_path(dx, dy, rise, segs, -1.0), r, mat, group, 8)
	_tube(label + "_HalfB", _pointed_rib_path(dx, dy, rise, segs, 1.0), r, mat, group, 8)
	return group

## Direct port of FG | Interior arcade and ribs + FG2 | Vault web patch (full_structure.py).
static func gen_gothic_vault_bay(label: String, mats: Dictionary, span_x: float = 4.2, span_y: float = 4.2, spring_height: float = 3.6, crown_rise: float = 1.8, rib_radius: float = 0.11, web_res: int = 11, parent = null):
	var group = Geo.gen_group(label, [0, 0, 0], 0, parent)
	var hx := maxf(0.8, float(span_x) * 0.5)
	var hy := maxf(0.8, float(span_y) * 0.5)
	var sh := maxf(1.8, float(spring_height))
	var rise := maxf(0.4, float(crown_rise))
	var rr := clampf(float(rib_radius), 0.04, 0.28)
	var res := clampi(int(web_res), 5, 21)
	var stone = mats.get("stone", mats.cream)
	var trim = mats.get("cream", stone)
	var dark = mats.get("stone_dark", stone)

	# 4 corner clustered columns (pier + 4 engaged shafts + stepped base & capital)
	var col_r := clampf(minf(hx, hy) * 0.10, 0.14, 0.30)
	for sx: float in [-1.0, 1.0]:
		for sy: float in [-1.0, 1.0]:
			var cx := sx * hx
			var cy := sy * hy
			var tag := "%s_Pier_%d_%d" % [label, int(sx), int(sy)]
			Geo.gen_cylinder(tag + "_Core", [cx, cy, sh * 0.5], col_r, sh, stone, 12, group)
			Geo.gen_cylinder(tag + "_Plinth", [cx, cy, 0.14], col_r * 1.45, 0.28, dark, 12, group)
			Geo.gen_cylinder(tag + "_Cap", [cx, cy, sh - 0.14], col_r * 1.48, 0.28, trim, 12, group)
			for ang_i in 4:
				var a := float(ang_i) * PI * 0.5
				Geo.gen_cylinder("%s_Shaft_%d" % [tag, ang_i], [cx + cos(a) * col_r * 0.88, cy + sin(a) * col_r * 0.88, sh * 0.5], col_r * 0.34, sh - 0.36, trim, 8, group)

	# Perimeter pointed transverse/longitudinal ribs
	for sy: float in [-1.0, 1.0]:
		var r_grp = Geo.gen_group("%s_TransRib_%d" % [label, int(sy)], [0.0, sy * hy, sh], 0, group)
		_tube("A", _pointed_rib_path(hx, 0.0, rise, 10, -1.0), rr, trim, r_grp, 8)
		_tube("B", _pointed_rib_path(hx, 0.0, rise, 10, 1.0), rr, trim, r_grp, 8)
	for sx: float in [-1.0, 1.0]:
		var l_grp = Geo.gen_group("%s_LongRib_%d" % [label, int(sx)], [sx * hx, 0.0, sh], 0, group)
		_tube("A", _pointed_rib_path(0.0, hy, rise, 10, -1.0), rr, trim, l_grp, 8)
		_tube("B", _pointed_rib_path(0.0, hy, rise, 10, 1.0), rr, trim, l_grp, 8)

	# Diagonal crossing ribs + keystone boss
	var d_grp = Geo.gen_group(label + "_DiagRibs", [0.0, 0.0, sh], 0, group)
	for sy: float in [-1.0, 1.0]:
		_tube("DA_%d" % int(sy), _pointed_rib_path(hx, sy * hy, rise, 12, -1.0), rr * 0.92, trim, d_grp, 8)
		_tube("DB_%d" % int(sy), _pointed_rib_path(hx, sy * hy, rise, 12, 1.0), rr * 0.92, trim, d_grp, 8)
	Geo.gen_cylinder(label + "_Keystone", [0.0, 0.0, sh + rise - 0.04], rr * 2.2, 0.22, trim, 10, group)

	# Groin vault web patch with underside soffit:
	# u = min(|x|, |y|), t = sqrt(1 - u), z = rise * t * (1.28 - 0.28 * t)
	var top_verts: Array = []
	var bot_verts: Array = []
	for iy in res:
		var ny := -1.0 + 2.0 * float(iy) / float(res - 1)
		for ix in res:
			var nx := -1.0 + 2.0 * float(ix) / float(res - 1)
			var u := minf(absf(nx), absf(ny))
			var t := sqrt(maxf(0.0, 1.0 - u))
			var z := sh + 0.06 + rise * t * (1.28 - 0.28 * t)
			top_verts.append([nx * hx, ny * hy, z])
			bot_verts.append([nx * hx, ny * hy, z - 0.08])
	var web_verts: Array = top_verts + bot_verts
	var web_faces: Array = []
	var offset := res * res
	for iy in res - 1:
		for ix in res - 1:
			var a := iy * res + ix
			var b := a + 1
			var c := a + res + 1
			var d := a + res
			web_faces.append([a, b, c, d])
			web_faces.append([offset + d, offset + c, offset + b, offset + a])
	Geo.gen_mesh(label + "_VaultWeb", web_verts, web_faces, stone, group, 0)
	return group

## Direct port of wall_lining.py Paired lancets + lower blind arcade + engaged shafts.
static func gen_gothic_lancet_bay(label: String, mats: Dictionary, width: float = 3.0, height: float = 4.65, sill_height: float = 1.15, bay_variant: int = 0, parent = null):
	var group = Geo.gen_group(label, [0, 0, 0], 0, parent)
	var w := maxf(1.6, float(width))
	var hw_bay := w * 0.5
	var top := maxf(2.4, float(height))
	var sill := clampf(float(sill_height), 0.45, top * 0.42)
	var ashlar = mats.get("stone", mats.cream)
	var mould = mats.get("cream", ashlar)
	var lead = mats.get("stone_dark", mats.wood_dark)
	var glass = mats.get("glass", mats.cream)

	# Ashlar dado, sill moulding, cornice moulding
	Geo.gen_box(label + "_Dado", [0.0, 0.045, sill * 0.5], [w, 0.23, sill], ashlar, 0.008, group)
	Geo.gen_box(label + "_SillMould", [0.0, -0.005, sill - 0.065], [w + 0.04, 0.35, 0.13], mould, 0.008, group)
	Geo.gen_box(label + "_Cornice", [0.0, 0.005, top + 0.08], [w + 0.06, 0.33, 0.16], mould, 0.008, group)

	# Flanking piers & paired engaged shafts + 3-tier stepped capitals
	var sx_scale := w / 3.0
	for side: float in [-1.0, 1.0]:
		var px := side * (hw_bay - 0.11 * sx_scale)
		Geo.gen_box("%s_Pier_%d" % [label, int(side)], [px, -0.01, top * 0.5], [0.22 * sx_scale, 0.30, top], ashlar, 0.008, group)
		Geo.gen_box("%s_PierBase_%d" % [label, int(side)], [px, -0.035, 0.12], [0.28 * sx_scale, 0.35, 0.24], mould, 0.006, group)
		var cx := side * (hw_bay - 0.12 * sx_scale)
		for off: float in [-0.06 * sx_scale, 0.06 * sx_scale]:
			_tube("%s_Shaft_%d_%d" % [label, int(side), int(signf(off))], [[cx + off, -0.17, 0.24], [cx + off, -0.17, top - 0.32]], 0.052, mould, group, 8)
		var caps := [[0.0, 0.27], [0.09, 0.32], [0.18, 0.39]]
		for ci in caps.size():
			var cw: float = caps[ci][1] * sx_scale
			Geo.gen_box("%s_Cap_%d_%d" % [label, int(side), ci], [cx, -0.06, top - 0.30 + caps[ci][0]], [cw, 0.34, 0.09], mould, 0.005, group)

	# Lower blind arcade (3 pointed niches along dado)
	var arc_hw := 0.34 * sx_scale
	var arc_h0 := sill * 0.18
	var arc_h1 := sill * 0.57
	var arc_rise := sill * 0.25
	for acx: float in [-0.84 * sx_scale, 0.0, 0.84 * sx_scale]:
		var path: Array = [[acx - arc_hw, -0.12, arc_h0], [acx - arc_hw, -0.12, arc_h1]]
		for step_i in 9:
			var tt := -1.0 + 2.0 * float(step_i) / 8.0
			var az := arc_h1 + arc_rise * pow(maxf(0.0, 1.0 - absf(tt)), 0.7)
			path.append([acx + tt * arc_hw, -0.12, az])
		path.append([acx + arc_hw, -0.12, arc_h0])
		_tube("%s_BlindArc_%d" % [label, int(round(acx * 10.0))], path, 0.04, mould, group, 8)

	# Central mullion pier between paired lancets
	Geo.gen_box(label + "_CenterPier", [0.0, 0.05, (sill + top) * 0.5], [0.14 * sx_scale, 0.18, top - sill], ashlar, 0.006, group)

	# Paired pointed lancets
	var spring := lerpf(sill, top, 0.51)
	var peak := lerpf(sill, top, 0.88)
	var lhw := 0.58 * sx_scale
	var denom := sqrt(1.0 - pow(0.35 / 1.35, 2.0))
	for k in 2:
		var lcx := (-0.66 if k == 0 else 0.66) * sx_scale
		var curve: Array = []
		var steps := 14
		for i in range(steps + 1):
			var lx := -lhw + 2.0 * lhw * float(i) / float(steps)
			var u := (absf(lx) / lhw + 0.35) / 1.35
			var lz := spring + (peak - spring) * sqrt(maxf(0.0, 1.0 - u * u)) / denom
			curve.append([lcx + lx, -0.09, lz])
		var frame_path: Array = [[lcx - lhw, -0.09, sill]] + curve + [[lcx + lhw, -0.09, sill]]
		_tube("%s_LancetFrame_%d" % [label, k], frame_path, 0.042, mould, group, 8)

		# Spandrel ashlar above arch & glazed lancet pane
		var sp_verts: Array = []
		var sp_faces: Array = []
		var gl_verts: Array = []
		var gl_faces: Array = []
		for i in steps:
			var a: Array = curve[i]
			var b: Array = curve[i + 1]
			var sv := sp_verts.size()
			sp_verts.append_array([
				[a[0], -0.045, a[2]], [b[0], -0.045, b[2]], [b[0], -0.045, top], [a[0], -0.045, top],
				[a[0], 0.14, a[2]], [b[0], 0.14, b[2]], [b[0], 0.14, top], [a[0], 0.14, top],
			])
			sp_faces.append_array([
				[sv, sv + 1, sv + 2, sv + 3],
				[sv + 7, sv + 6, sv + 5, sv + 4],
				[sv, sv + 4, sv + 5, sv + 1],
			])
			var gv := gl_verts.size()
			gl_verts.append_array([[a[0], 0.04, sill], [b[0], 0.04, sill], [b[0], 0.04, b[2]], [a[0], 0.04, a[2]]])
			gl_faces.append([gv, gv + 1, gv + 2, gv + 3])
		Geo.gen_mesh("%s_Spandrel_%d" % [label, k], sp_verts, sp_faces, ashlar, group, 0)
		Geo.gen_mesh("%s_Glass_%d" % [label, k], gl_verts, gl_faces, glass, group, 0)

		# Lead horizontal transoms
		var t_levels := [lerpf(sill, spring, 0.45), lerpf(sill, spring, 0.88)]
		if (bay_variant & 1) == 1:
			t_levels.append(lerpf(spring, peak, 0.42))
		for ti in t_levels.size():
			_tube("%s_Lead_%d_%d" % [label, k, ti], [[lcx - lhw, -0.012, t_levels[ti]], [lcx + lhw, -0.012, t_levels[ti]]], 0.011, lead, group, 6)
	return group

## Direct port of wall_lining.py Radial rose window (12-spoke branching tracery).
static func gen_gothic_rose_window(label: String, mats: Dictionary, width: float = 3.0, height: float = 4.65, sill_height: float = 1.15, radius: float = 1.24, spokes: int = 12, parent = null):
	var group = Geo.gen_group(label, [0, 0, 0], 0, parent)
	var w := maxf(2.0, float(width))
	var hw := w * 0.5
	var top := maxf(2.6, float(height))
	var sill := clampf(float(sill_height), 0.4, top * 0.42)
	var cz := (sill + top) * 0.5
	var max_r := minf(hw - 0.14, (top - sill) * 0.5 - 0.12)
	var r := clampf(float(radius), 0.45, max_r)
	var n_spokes := clampi(int(spokes), 6, 18)
	var ashlar = mats.get("stone", mats.cream)
	var mould = mats.get("cream", ashlar)
	var glass = mats.get("glass", mats.cream)

	# Dado & cornice
	Geo.gen_box(label + "_Dado", [0.0, 0.045, sill * 0.5], [w, 0.23, sill], ashlar, 0.008, group)
	Geo.gen_box(label + "_Sill", [0.0, -0.005, sill - 0.065], [w + 0.04, 0.35, 0.13], mould, 0.008, group)
	Geo.gen_box(label + "_Cornice", [0.0, 0.005, top + 0.08], [w + 0.06, 0.33, 0.16], mould, 0.008, group)

	# Ashlar surround from circular reveal to rectangular boundary
	var segs := 32
	var sur_verts: Array = []
	var sur_faces: Array = []
	for i in segs:
		var a0 := TAU * float(i) / float(segs)
		var a1 := TAU * float(i + 1) / float(segs)
		var d0 := Vector2(cos(a0), sin(a0))
		var d1 := Vector2(cos(a1), sin(a1))
		var r_out0 := minf(hw / maxf(absf(d0.x), 1e-6), ((top - cz) if d0.y >= 0.0 else (cz - sill)) / maxf(absf(d0.y), 1e-6))
		var r_out1 := minf(hw / maxf(absf(d1.x), 1e-6), ((top - cz) if d1.y >= 0.0 else (cz - sill)) / maxf(absf(d1.y), 1e-6))
		var p_in0 := Vector2(r * d0.x, cz + r * d0.y)
		var p_out0 := Vector2(r_out0 * d0.x, cz + r_out0 * d0.y)
		var p_out1 := Vector2(r_out1 * d1.x, cz + r_out1 * d1.y)
		var p_in1 := Vector2(r * d1.x, cz + r * d1.y)
		var sv := sur_verts.size()
		sur_verts.append_array([
			[p_in0.x, -0.05, p_in0.y], [p_out0.x, -0.05, p_out0.y], [p_out1.x, -0.05, p_out1.y], [p_in1.x, -0.05, p_in1.y],
			[p_in0.x, 0.14, p_in0.y], [p_out0.x, 0.14, p_out0.y], [p_out1.x, 0.14, p_out1.y], [p_in1.x, 0.14, p_in1.y],
		])
		sur_faces.append_array([
			[sv, sv + 1, sv + 2, sv + 3],
			[sv + 7, sv + 6, sv + 5, sv + 4],
			[sv, sv + 3, sv + 7, sv + 4],
		])
	Geo.gen_mesh(label + "_Surround", sur_verts, sur_faces, ashlar, group, 0)

	# Rim ring & hub ring
	for rr_idx in 2:
		var rad := r if rr_idx == 0 else r * 0.19
		var ring_pts: Array = []
		for i in range(segs + 1):
			var a := TAU * float(i) / float(segs)
			ring_pts.append([rad * cos(a), -0.072, cz + rad * sin(a)])
		_tube("%s_Ring_%d" % [label, rr_idx], ring_pts, 0.022 if rr_idx == 0 else 0.018, mould, group, 8)

	# Radial branching mullions
	var half_step := PI / float(n_spokes)
	for k in n_spokes:
		var a := (float(k) + 0.5) * TAU / float(n_spokes)
		var pt := func(frac: float, ang: float) -> Array:
			return [r * frac * cos(ang), -0.065, cz + r * frac * sin(ang)]
		_tube("%s_Spoke_%d" % [label, k], [pt.call(0.19, a), pt.call(0.58, a), pt.call(1.0, a)], 0.014, mould, group, 6)
		for side: float in [-1.0, 1.0]:
			_tube("%s_Branch_%d_%d" % [label, k, int(side)], [
				pt.call(0.58, a),
				pt.call(0.74, a + side * half_step * 0.18),
				pt.call(0.80, a + side * half_step * 0.42),
				pt.call(0.83, a + side * half_step),
			], 0.010, mould, group, 6)

	# Stained glass disc
	var gl_verts: Array = [[0.0, 0.032, cz]]
	var gl_faces: Array = []
	for i in segs:
		var a := TAU * float(i) / float(segs)
		gl_verts.append([r * cos(a), 0.032, cz + r * sin(a)])
	for i in segs:
		gl_faces.append([0, 1 + i, 1 + ((i + 1) % segs)])
	Geo.gen_mesh(label + "_RoseGlass", gl_verts, gl_faces, glass, group, 0)
	return group

## Direct port of FG2 | Flying buttresses (full_structure.py).
static func gen_gothic_flying_buttress(label: String, mats: Dictionary, projection: float = 2.4, height: float = 4.5, rib_radius: float = 0.24, parent = null):
	var group = Geo.gen_group(label, [0, 0, 0], 0, parent)
	var proj := clampf(float(projection), 1.0, 4.0)
	var h := clampf(float(height), 2.8, 8.0)
	var r := clampf(float(rib_radius), 0.10, 0.40)
	var stone = mats.get("stone", mats.cream)
	var trim = mats.get("cream", stone)
	var dark = mats.get("stone_dark", stone)

	# Outer pier + stepped base + 4-sided pinnacle cap
	Geo.gen_box(label + "_Pier", [proj, 0.0, h * 0.5], [0.74, 0.80, h], stone, 0.012, group)
	Geo.gen_box(label + "_PierBase", [proj, 0.0, 0.22], [0.92, 0.96, 0.44], dark, 0.012, group)
	var pin_h := 1.35
	var pr := 0.42
	var pin_verts := [
		[proj - pr, -pr, h], [proj + pr, -pr, h], [proj + pr, pr, h], [proj - pr, pr, h],
		[proj, 0.0, h + pin_h],
	]
	var pin_faces := [[3, 2, 1, 0], [0, 1, 4], [1, 2, 4], [2, 3, 4], [3, 0, 4]]
	Geo.gen_mesh(label + "_Pinnacle", pin_verts, pin_faces, trim, group, 0)

	# Flying arch quadratic Bezier from pier to upper wall
	var p0 := Vector3(proj, 0.0, h * 0.91)
	var p1 := Vector3(proj * 0.55, 0.0, h * 1.29)
	var p2 := Vector3(0.0, 0.0, h * 1.56)
	var pts: Array = []
	for i in 13:
		var v := _qbez(p0, p1, p2, float(i) / 12.0)
		pts.append([v.x, v.y, v.z])
	_tube(label + "_Flyer", pts, r, trim, group, 8)
	return group
