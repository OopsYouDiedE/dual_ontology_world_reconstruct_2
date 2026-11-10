@tool
extends RefCounted

# Direct port of kit/flooring.py. Z-up recipe coordinates convert at the geometry boundary.
const Sem = preload("res://tools/building_construction/BuildingConstruction/Shared/RecipeSemantics.gd")
const Geo = preload("res://tools/building_construction/BuildingConstruction/Shared/RecipeGeometry.gd")
const EPS = 1e-9

static func gen_clip_rect(v_polygon, v_bounds):
	var v_a = null
	var v_area = null
	var v_axis = null
	var v_b = null
	var v_bound = null
	var v_clean = null
	var v_ina = null
	var v_inb = null
	var v_p = null
	var v_result = null
	var v_sign = null
	var v_source = null
	var v_t = null
	var v_va = null
	var v_vb = null
	var v_xmax = null
	var v_xmin = null
	var v_ymax = null
	var v_ymin = null
	var tmp_1 = v_bounds
	v_xmin = tmp_1[0]
	v_xmax = tmp_1[1]
	v_ymin = tmp_1[2]
	v_ymax = tmp_1[3]
	v_result = Sem.py_list(v_polygon)
	for tmp_2 in [[0, v_xmin, 1], [0, v_xmax, Sem.neg(1)], [1, v_ymin, 1], [1, v_ymax, Sem.neg(1)]]:
		var tmp_3 = tmp_2
		v_axis = tmp_3[0]
		v_bound = tmp_3[1]
		v_sign = tmp_3[2]
		var tmp_4 = [v_result, []]
		v_source = tmp_4[0]
		v_result = tmp_4[1]
		if Sem.truth(not Sem.truth(v_source)):
			break
		for tmp_5 in Sem.py_zip(v_source, Sem.add(Sem.slice_array(v_source, 1, null, null), Sem.slice_array(v_source, null, 1, null))):
			var tmp_6 = tmp_5
			v_a = tmp_6[0]
			v_b = tmp_6[1]
			v_va = Sem.mul(Sem.sub(v_a[v_axis], v_bound), v_sign)
			v_vb = Sem.mul(Sem.sub(v_b[v_axis], v_bound), v_sign)
			var tmp_7 = [((v_va >= Sem.neg(1e-09))), ((v_vb >= Sem.neg(1e-09)))]
			v_ina = tmp_7[0]
			v_inb = tmp_7[1]
			if Sem.truth(v_ina):
				v_result.append(v_a)
			if Sem.truth(((v_ina != v_inb))):
				v_t = Sem.div(Sem.sub(v_bound, v_a[v_axis]), Sem.sub(v_b[v_axis], v_a[v_axis]))
				v_result.append([Sem.add(v_a[0], Sem.mul(v_t, Sem.sub(v_b[0], v_a[0]))), Sem.add(v_a[1], Sem.mul(v_t, Sem.sub(v_b[1], v_a[1])))])
	v_clean = []
	for tmp_8 in v_result:
		v_p = tmp_8
		if Sem.truth(Sem.either_lazy(not Sem.truth(v_clean), func(): return ((Sem.dist(v_p, v_clean[Sem.neg(1)]) > 1e-08)))):
			v_clean.append(v_p)
	if Sem.truth(Sem.both_lazy(((Sem.py_len(v_clean) > 2)), func(): return ((Sem.dist(v_clean[0], v_clean[Sem.neg(1)]) < 1e-08)))):
		v_clean.pop_back()
	if Sem.truth(((Sem.py_len(v_clean) < 3))):
		return []
	v_area = Sem.mul(Sem.py_sum(Sem.map_array(Sem.py_zip(v_clean, Sem.add(Sem.slice_array(v_clean, 1, null, null), Sem.slice_array(v_clean, null, 1, null))), func(tmp_9): var tmp_10 = tmp_9[0]; var tmp_11 = tmp_9[1]; return Sem.sub(Sem.mul(tmp_10[0], tmp_11[1]), Sem.mul(tmp_10[1], tmp_11[0])))), 0.5)
	return (v_clean if Sem.truth(((v_area > 1e-09))) else [])

static func gen_inset_convex(v_poly, v_distance):
	var v_a = null
	var v_b = null
	var v_den = null
	var v_dx = null
	var v_dy = null
	var v_i = null
	var v_length = null
	var v_lines = null
	var v_nx = null
	var v_ny = null
	var v_out = null
	var v_p = null
	var v_q = null
	var v_t = null
	var v_v = null
	var v_w = null
	v_lines = []
	for tmp_12 in Sem.py_zip(v_poly, Sem.add(Sem.slice_array(v_poly, 1, null, null), Sem.slice_array(v_poly, null, 1, null))):
		var tmp_13 = tmp_12
		v_a = tmp_13[0]
		v_b = tmp_13[1]
		var tmp_14 = [Sem.sub(v_b[0], v_a[0]), Sem.sub(v_b[1], v_a[1])]
		v_dx = tmp_14[0]
		v_dy = tmp_14[1]
		v_length = Sem.hypot(v_dx, v_dy)
		var tmp_15 = [Sem.div(Sem.neg(v_dy), v_length), Sem.div(v_dx, v_length)]
		v_nx = tmp_15[0]
		v_ny = tmp_15[1]
		v_lines.append([[Sem.add(v_a[0], Sem.mul(v_nx, v_distance)), Sem.add(v_a[1], Sem.mul(v_ny, v_distance))], [v_dx, v_dy]])
	v_out = []
	for tmp_16 in Sem.py_enumerate(v_lines):
		var tmp_17 = tmp_16
		v_i = tmp_17[0]
		var tmp_18 = tmp_17[1]
		v_p = tmp_18[0]
		v_v = tmp_18[1]
		var tmp_19 = v_lines[Sem.sub(v_i, 1)]
		v_q = tmp_19[0]
		v_w = tmp_19[1]
		v_den = Sem.sub(Sem.mul(v_v[0], v_w[1]), Sem.mul(v_v[1], v_w[0]))
		v_t = Sem.div(Sem.sub(Sem.mul(Sem.sub(v_q[0], v_p[0]), v_w[1]), Sem.mul(Sem.sub(v_q[1], v_p[1]), v_w[0])), v_den)
		v_out.append([Sem.add(v_p[0], Sem.mul(v_t, v_v[0])), Sem.add(v_p[1], Sem.mul(v_t, v_v[1]))])
	return v_out

static func gen__ring(v_batch, v_outer, v_inner, v_z = 0.038):
	var v_ix0 = null
	var v_ix1 = null
	var v_iy0 = null
	var v_iy1 = null
	var v_ox0 = null
	var v_ox1 = null
	var v_oy0 = null
	var v_oy1 = null
	var v_p = null
	var tmp_20 = v_outer
	v_ox0 = tmp_20[0]
	v_ox1 = tmp_20[1]
	v_oy0 = tmp_20[2]
	v_oy1 = tmp_20[3]
	var tmp_21 = v_inner
	v_ix0 = tmp_21[0]
	v_ix1 = tmp_21[1]
	v_iy0 = tmp_21[2]
	v_iy1 = tmp_21[3]
	for tmp_22 in [[[v_ox0, v_oy0], [v_ox1, v_oy0], [v_ix1, v_iy0], [v_ix0, v_iy0]], [[v_ox1, v_oy0], [v_ox1, v_oy1], [v_ix1, v_iy1], [v_ix1, v_iy0]], [[v_ox1, v_oy1], [v_ox0, v_oy1], [v_ix0, v_iy1], [v_ix1, v_iy1]], [[v_ox0, v_oy1], [v_ox0, v_oy0], [v_ix0, v_iy0], [v_ix0, v_iy1]]]:
		v_p = tmp_22
		v_batch.prism(v_p, 0.012, v_z)

static func gen_tiled_floor(v_name, v_mats, v_width = 8, v_depth = 6, v_tile = 0.8, v_cut = 0.12, v_grout = 0.012, v_border = 0.42, v_seed = 12, v_parent = null):
	var v__ = null
	var v_a = null
	var v_b = null
	var v_batch = null
	var v_bounds = null
	var v_col = null
	var v_d = null
	var v_diamond = null
	var v_diamonds = null
	var v_i = null
	var v_j = null
	var v_octagon = null
	var v_poly = null
	var v_rect = null
	var v_rings = null
	var v_rng = null
	var v_root = null
	var v_s = null
	var v_shapes = null
	var v_x = null
	var v_y = null
	if Sem.truth(not Sem.truth(Sem.both_lazy(((0 < v_cut) and (v_cut < Sem.div(v_tile, 2))), func(): return Sem.both_lazy(((0 <= v_grout) and (v_grout < Sem.div(v_cut, 2))), func(): return Sem.both_lazy(((v_border >= 0.35)), func(): return ((Sem.py_min(v_width, v_depth) > Sem.mul(2, v_border)))))))):
		push_error(str("invalid tile dimensions / border"))
		return null
	v_root = Geo.gen_group(v_name, [0, 0, 0], 0, v_parent)
	v_root["generator"] = "tiled_floor"
	v_root["tile_size"] = v_tile
	v_root["grout_width"] = v_grout
	Geo.gen_box(Sem.add(v_name, "_Foundation"), [0, 0, Sem.neg(0.13)], [v_width, v_depth, 0.26], v_mats["stone_dark"], 0.035, v_root)
	Geo.gen_box(Sem.add(v_name, "_Grout"), [0, 0, 0.006], [v_width, v_depth, 0.012], v_mats["grout"], 0, v_root)
	v_rect = func(tmp_23):
		return [Sem.add(Sem.div(Sem.neg(v_width), 2), tmp_23), Sem.sub(Sem.div(v_width, 2), tmp_23), Sem.add(Sem.div(Sem.neg(v_depth), 2), tmp_23), Sem.sub(Sem.div(v_depth, 2), tmp_23)]
	v_rings = [[0, 0.1, "stone"], [0.1, 0.17, "stone_dark"], [0.17, 0.29, "stone"], [0.29, 0.35, "stone_dark"], [0.35, v_border, "stone"]]
	for tmp_24 in v_rings:
		var tmp_25 = tmp_24
		v_a = tmp_25[0]
		v_b = tmp_25[1]
		v_col = tmp_25[2]
		v_batch = Geo.Batch.new()
		gen__ring(v_batch, v_rect.call(v_a), v_rect.call(v_b), 0.038)
		v_batch.finish(Sem.add(Sem.add(v_name, "_Border_"), str(v_a)), v_mats[v_col], v_root)
	v_bounds = v_rect.call(v_border)
	v_shapes = Sem.map_array(range(5), func(tmp_26): var tmp_27 = tmp_26; return Geo.Batch.new())
	v_diamonds = Geo.Batch.new()
	v_rng = Sem.RandomSequence.new(v_seed)
	var tmp_28 = [v_tile, v_cut]
	v_s = tmp_28[0]
	v_d = tmp_28[1]
	v_octagon = [[v_d, 0], [Sem.sub(v_s, v_d), 0], [v_s, v_d], [v_s, Sem.sub(v_s, v_d)], [Sem.sub(v_s, v_d), v_s], [v_d, v_s], [0, Sem.sub(v_s, v_d)], [0, v_d]]
	v_diamond = [[0, Sem.neg(v_d)], [v_d, 0], [0, v_d], [Sem.neg(v_d), 0]]
	v_octagon = gen_inset_convex(v_octagon, Sem.div(v_grout, 2))
	v_diamond = gen_inset_convex(v_diamond, Sem.div(v_grout, 2))
	for tmp_29 in range(Sem.sub(floori(Sem.div(v_bounds[0], v_s)), 1), Sem.add(ceili(Sem.div(v_bounds[1], v_s)), 1)):
		v_i = tmp_29
		for tmp_30 in range(Sem.sub(floori(Sem.div(v_bounds[2], v_s)), 1), Sem.add(ceili(Sem.div(v_bounds[3], v_s)), 1)):
			v_j = tmp_30
			v_poly = gen_clip_rect(Sem.map_array(v_octagon, func(tmp_31): var tmp_32 = tmp_31[0]; var tmp_33 = tmp_31[1]; return [Sem.add(tmp_32, Sem.mul(v_i, v_s)), Sem.add(tmp_33, Sem.mul(v_j, v_s))]), v_bounds)
			v_shapes[v_rng.randrange(5)].prism(v_poly, 0.012, 0.04)
			v_poly = gen_clip_rect(Sem.map_array(v_diamond, func(tmp_34): var tmp_35 = tmp_34[0]; var tmp_36 = tmp_34[1]; return [Sem.add(tmp_35, Sem.mul(v_i, v_s)), Sem.add(tmp_36, Sem.mul(v_j, v_s))]), v_bounds)
			v_diamonds.prism(v_poly, 0.012, 0.04)
	for tmp_37 in Sem.py_enumerate(v_shapes):
		var tmp_38 = tmp_37
		v_i = tmp_38[0]
		v_b = tmp_38[1]
		v_b.finish(Sem.add(Sem.add(v_name, "_Octagons_"), str(v_i)), v_mats[Sem.add("tile_", str(v_i))], v_root, 0.004)
	v_diamonds.finish(Sem.add(v_name, "_Diamond_inlays"), v_mats["stone_dark"], v_root, 0.003)
	return v_root

