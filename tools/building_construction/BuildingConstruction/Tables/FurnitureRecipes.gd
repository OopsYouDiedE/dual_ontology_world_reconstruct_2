@tool
extends RefCounted

# Direct port of kit/furniture.py. Z-up recipe coordinates convert at the geometry boundary.
const Sem = preload("res://tools/building_construction/BuildingConstruction/Shared/RecipeSemantics.gd")
const Geo = preload("res://tools/building_construction/BuildingConstruction/Shared/RecipeGeometry.gd")
const EPS = 1e-9

const v__BOOK_COLOURS = ["book_red", "book_blue", "book_green", "wood_dark", "wood_light"]
static func gen__positive(v_values = {}):
	var v_key = null
	var v_value = null
	for tmp_1 in Sem.items(v_values):
		var tmp_2 = tmp_1
		v_key = tmp_2[0]
		v_value = tmp_2[1]
		if Sem.truth(Sem.either_lazy(not Sem.truth(is_finite(v_value)), func(): return ((v_value <= 0)))):
			push_error(str(Sem.mod("%s must be a finite positive number", v_key)))
			return null

static func gen__root(v_name, v_kind, v_parent, v_dimensions = {}):
	var v_key = null
	var v_obj = null
	var v_value = null
	gen__positive(v_dimensions)
	v_obj = Geo.gen_group(v_name, [0, 0, 0], 0, v_parent)
	v_obj["asset_type"] = v_kind
	v_obj["front_axis"] = "-Y"
	for tmp_3 in Sem.items(v_dimensions):
		var tmp_4 = tmp_3
		v_key = tmp_4[0]
		v_value = tmp_4[1]
		v_obj[v_key] = v_value
	return v_obj

static func gen__boxes(v_name, v_specs, v_mat, v_parent, v_bevel = 0):
	var v_cube_faces = null
	var v_cx = null
	var v_cy = null
	var v_cz = null
	var v_depth = null
	var v_face = null
	var v_faces = null
	var v_height = null
	var v_j = null
	var v_start = null
	var v_sx = null
	var v_sy = null
	var v_sz = null
	var v_vertices = null
	var v_width = null
	var v_x = null
	var v_y = null
	var v_z = null
	var tmp_5 = [[], []]
	v_vertices = tmp_5[0]
	v_faces = tmp_5[1]
	v_cube_faces = [[0, 3, 2, 1], [4, 5, 6, 7], [0, 1, 5, 4], [1, 2, 6, 5], [2, 3, 7, 6], [3, 0, 4, 7]]
	for tmp_6 in v_specs:
		var tmp_7 = tmp_6
		var tmp_8 = tmp_7[0]
		v_cx = tmp_8[0]
		v_cy = tmp_8[1]
		v_cz = tmp_8[2]
		var tmp_9 = tmp_7[1]
		v_width = tmp_9[0]
		v_depth = tmp_9[1]
		v_height = tmp_9[2]
		var tmp_10 = [Sem.div(v_width, 2), Sem.div(v_depth, 2), Sem.div(v_height, 2)]
		v_x = tmp_10[0]
		v_y = tmp_10[1]
		v_z = tmp_10[2]
		v_start = Sem.py_len(v_vertices)
		v_vertices = Sem.add(v_vertices, Sem.map_array([[Sem.neg(1), Sem.neg(1), Sem.neg(1)], [1, Sem.neg(1), Sem.neg(1)], [1, 1, Sem.neg(1)], [Sem.neg(1), 1, Sem.neg(1)], [Sem.neg(1), Sem.neg(1), 1], [1, Sem.neg(1), 1], [1, 1, 1], [Sem.neg(1), 1, 1]], func(tmp_11): var tmp_12 = tmp_11[0]; var tmp_13 = tmp_11[1]; var tmp_14 = tmp_11[2]; return [Sem.add(v_cx, Sem.mul(tmp_12, v_x)), Sem.add(v_cy, Sem.mul(tmp_13, v_y)), Sem.add(v_cz, Sem.mul(tmp_14, v_z))]))
		v_faces = Sem.add(v_faces, Sem.map_array(v_cube_faces, func(tmp_15): var tmp_16 = tmp_15; return Sem.py_tuple(Sem.map_array(tmp_16, func(tmp_17): var tmp_18 = tmp_17; return Sem.add(v_start, tmp_18)))))
	return Geo.gen_mesh(v_name, v_vertices, v_faces, v_mat, v_parent, v_bevel)

static func gen__rounded_rect(v_width, v_depth, v_cut):
	var v_a = null
	var v_b = null
	var v_c = null
	var tmp_19 = [Sem.div(v_width, 2), Sem.div(v_depth, 2)]
	v_a = tmp_19[0]
	v_b = tmp_19[1]
	v_c = Sem.py_min(v_cut, Sem.mul(v_a, 0.6), Sem.mul(v_b, 0.6))
	return [[Sem.add(Sem.neg(v_a), v_c), Sem.neg(v_b)], [Sem.sub(v_a, v_c), Sem.neg(v_b)], [v_a, Sem.add(Sem.neg(v_b), v_c)], [v_a, Sem.sub(v_b, v_c)], [Sem.sub(v_a, v_c), v_b], [Sem.add(Sem.neg(v_a), v_c), v_b], [Sem.neg(v_a), Sem.sub(v_b, v_c)], [Sem.neg(v_a), Sem.add(Sem.neg(v_b), v_c)]]

static func gen__ring_solid(v_name, v_rings, v_mat, v_parent):
	var v_a = null
	var v_b = null
	var v_faces = null
	var v_j = null
	var v_level = null
	var v_n = null
	var v_ring = null
	var v_vertices = null
	var v_x = null
	var v_y = null
	var v_z = null
	v_n = Sem.py_len(v_rings[0][1])
	v_vertices = Sem.flat_map(v_rings, func(tmp_20): var tmp_21 = tmp_20[0]; var tmp_22 = tmp_20[1]; return Sem.map_array(tmp_22, func(tmp_23): var tmp_24 = tmp_23[0]; var tmp_25 = tmp_23[1]; return [tmp_24, tmp_25, tmp_21]))
	v_faces = [Sem.py_tuple(Sem.py_reversed(range(v_n)))]
	for tmp_26 in range(Sem.sub(Sem.py_len(v_rings), 1)):
		v_level = tmp_26
		var tmp_27 = [Sem.mul(v_level, v_n), Sem.mul(Sem.add(v_level, 1), v_n)]
		v_a = tmp_27[0]
		v_b = tmp_27[1]
		v_faces = Sem.add(v_faces, Sem.map_array(range(v_n), func(tmp_28): var tmp_29 = tmp_28; return [Sem.add(v_a, tmp_29), Sem.add(v_a, Sem.mod(Sem.add(tmp_29, 1), v_n)), Sem.add(v_b, Sem.mod(Sem.add(tmp_29, 1), v_n)), Sem.add(v_b, tmp_29)]))
	v_faces.append(Sem.py_tuple(range(Sem.mul(Sem.sub(Sem.py_len(v_rings), 1), v_n), Sem.mul(Sem.py_len(v_rings), v_n))))
	return Geo.gen_mesh(v_name, v_vertices, v_faces, v_mat, v_parent, 0)

static func gen__post(v_name, v_x, v_y, v_levels, v_mat, v_parent):
	var v_rings = null
	var v_w = null
	var v_z = null
	v_rings = Sem.map_array(v_levels, func(tmp_30): var tmp_31 = tmp_30[0]; var tmp_32 = tmp_30[1]; return [tmp_31, [[Sem.sub(v_x, Sem.div(tmp_32, 2)), Sem.sub(v_y, Sem.div(tmp_32, 2))], [Sem.add(v_x, Sem.div(tmp_32, 2)), Sem.sub(v_y, Sem.div(tmp_32, 2))], [Sem.add(v_x, Sem.div(tmp_32, 2)), Sem.add(v_y, Sem.div(tmp_32, 2))], [Sem.sub(v_x, Sem.div(tmp_32, 2)), Sem.add(v_y, Sem.div(tmp_32, 2))]]])
	return gen__ring_solid(v_name, v_rings, v_mat, v_parent)

static func gen__cushion(v_name, v_width, v_depth, v_bottom, v_height, v_mat, v_parent):
	var v_cut = null
	var v_rings = null
	v_cut = Sem.mul(Sem.py_min(v_width, v_depth), 0.08)
	v_rings = [[v_bottom, gen__rounded_rect(Sem.mul(v_width, 0.95), Sem.mul(v_depth, 0.95), v_cut)], [Sem.add(v_bottom, Sem.mul(v_height, 0.25)), gen__rounded_rect(v_width, v_depth, v_cut)], [Sem.add(v_bottom, Sem.mul(v_height, 0.78)), gen__rounded_rect(Sem.mul(v_width, 0.98), Sem.mul(v_depth, 0.98), v_cut)], [Sem.add(v_bottom, v_height), gen__rounded_rect(Sem.mul(v_width, 0.91), Sem.mul(v_depth, 0.91), v_cut)]]
	return gen__ring_solid(v_name, v_rings, v_mat, v_parent)

static func gen__panel(v_name, v_x, v_z, v_width, v_height, v_face_y, v_mats, v_parent):
	var v_border = null
	var v_specs = null
	v_border = Sem.mul(Sem.py_min(v_width, v_height), 0.065)
	Geo.gen_box(Sem.add(v_name, "_Field"), [v_x, Sem.sub(v_face_y, 0.004), v_z], [v_width, 0.012, v_height], v_mats["wood_dark"], 0.004, v_parent)
	v_specs = [[[Sem.add(Sem.sub(v_x, Sem.div(v_width, 2)), Sem.div(v_border, 2)), Sem.sub(v_face_y, 0.019), v_z], [v_border, 0.033, v_height]], [[Sem.sub(Sem.add(v_x, Sem.div(v_width, 2)), Sem.div(v_border, 2)), Sem.sub(v_face_y, 0.019), v_z], [v_border, 0.033, v_height]], [[v_x, Sem.sub(v_face_y, 0.019), Sem.add(Sem.sub(v_z, Sem.div(v_height, 2)), Sem.div(v_border, 2))], [v_width, 0.033, v_border]], [[v_x, Sem.sub(v_face_y, 0.019), Sem.sub(Sem.add(v_z, Sem.div(v_height, 2)), Sem.div(v_border, 2))], [v_width, 0.033, v_border]]]
	gen__boxes(Sem.add(v_name, "_Moulding"), v_specs, v_mats["wood"], v_parent, 0.004)

static func gen_book(v_name, v_mats, v_width = 0.075, v_depth = 0.23, v_height = 0.31, v_colour = "book_red", v_parent = null):
	var v_bands = null
	var v_cover = null
	var v_material = null
	var v_root = null
	var v_specs = null
	var v_spine = null
	var v_t = null
	v_root = gen__root(v_name, "book", v_parent, {"width": v_width, "depth": v_depth, "height": v_height})
	v_cover = Sem.py_min(Sem.mul(v_width, 0.13), 0.008)
	v_spine = Sem.py_min(Sem.mul(v_depth, 0.055), 0.014)
	v_material = v_mats[v_colour]
	v_specs = [[[Sem.add(Sem.div(Sem.neg(v_width), 2), Sem.div(v_cover, 2)), 0, Sem.div(v_height, 2)], [v_cover, v_depth, v_height]], [[Sem.sub(Sem.div(v_width, 2), Sem.div(v_cover, 2)), 0, Sem.div(v_height, 2)], [v_cover, v_depth, v_height]], [[0, Sem.add(Sem.div(Sem.neg(v_depth), 2), Sem.div(v_spine, 2)), Sem.div(v_height, 2)], [v_width, v_spine, v_height]]]
	gen__boxes(Sem.add(v_name, "_Binding"), v_specs, v_material, v_root, Sem.py_min(Sem.mul(v_cover, 0.15), 0.001))
	Geo.gen_box(Sem.add(v_name, "_Pages"), [0, Sem.mul(v_spine, 0.35), Sem.div(v_height, 2)], [Sem.sub(v_width, Sem.mul(2, v_cover)), Sem.sub(v_depth, Sem.mul(v_spine, 1.55)), Sem.mul(v_height, 0.94)], v_mats["cream"], 0, v_root)
	v_bands = Sem.map_array([0.17, 0.78, 0.85], func(tmp_33): var tmp_34 = tmp_33; return [[0, Sem.sub(Sem.div(Sem.neg(v_depth), 2), 0.0007), Sem.mul(v_height, tmp_34)], [Sem.mul(v_width, 0.88), 0.002, Sem.mul(v_height, 0.025)]])
	gen__boxes(Sem.add(v_name, "_SpineBands"), v_bands, v_mats["gold"], v_root, 0)
	Geo.gen_box(Sem.add(v_name, "_SpineLabel"), [0, Sem.sub(Sem.div(Sem.neg(v_depth), 2), 0.001), Sem.mul(v_height, 0.56)], [Sem.mul(v_width, 0.55), 0.002, Sem.mul(v_height, 0.105)], v_mats["cream"], 0, v_root)
	return v_root

static func gen__flat_book(v_name, v_mats, v_width, v_depth, v_height, v_colour, v_parent):
	var v_cover = null
	var v_root = null
	var v_specs = null
	var v_t = null
	v_root = gen__root(v_name, "flat_book", v_parent, {"width": v_width, "depth": v_depth, "height": v_height})
	v_cover = Sem.mul(v_height, 0.16)
	v_specs = [[[0, 0, Sem.div(v_cover, 2)], [v_width, v_depth, v_cover]], [[0, 0, Sem.sub(v_height, Sem.div(v_cover, 2))], [v_width, v_depth, v_cover]], [[0, Sem.add(Sem.div(Sem.neg(v_depth), 2), Sem.div(v_cover, 2)), Sem.div(v_height, 2)], [v_width, v_cover, v_height]]]
	gen__boxes(Sem.add(v_name, "_Binding"), v_specs, v_mats[v_colour], v_root, Sem.py_min(0.002, Sem.mul(v_cover, 0.2)))
	Geo.gen_box(Sem.add(v_name, "_Pages"), [0, Sem.mul(v_cover, 0.25), Sem.div(v_height, 2)], [Sem.mul(v_width, 0.96), Sem.sub(v_depth, Sem.mul(v_cover, 1.5)), Sem.sub(v_height, Sem.mul(2, v_cover))], v_mats["cream"], 0, v_root)
	gen__boxes(Sem.add(v_name, "_Bands"), Sem.map_array([Sem.neg(0.3), 0.3], func(tmp_35): var tmp_36 = tmp_35; return [[Sem.mul(v_width, tmp_36), Sem.sub(Sem.div(Sem.neg(v_depth), 2), 0.001), Sem.div(v_height, 2)], [Sem.mul(v_width, 0.023), 0.002, Sem.mul(v_height, 0.8)]]), v_mats["gold"], v_root, 0)
	return v_root

static func gen_books(v_name, v_mats, v_width = 0.34, v_depth = 0.25, v_height = 0.17, v_count = 3, v_seed = 7, v_parent = null):
	var v__ = null
	var v_bottom = null
	var v_child = null
	var v_factor = null
	var v_h = null
	var v_i = null
	var v_rng = null
	var v_root = null
	var v_total = null
	var v_weight = null
	var v_weights = null
	v_root = gen__root(v_name, "books", v_parent, {"width": v_width, "depth": v_depth, "height": v_height})
	v_rng = Sem.RandomSequence.new(v_seed)
	v_count = Sem.py_max(1, int(v_count))
	v_weights = Sem.map_array(range(v_count), func(tmp_37): var tmp_38 = tmp_37; return v_rng.uniform(0.8, 1.2))
	var tmp_39 = [Sem.py_sum(v_weights), 0]
	v_total = tmp_39[0]
	v_bottom = tmp_39[1]
	for tmp_40 in Sem.py_enumerate(v_weights):
		var tmp_41 = tmp_40
		v_i = tmp_41[0]
		v_weight = tmp_41[1]
		v_h = Sem.div(Sem.mul(v_height, v_weight), v_total)
		v_factor = Sem.sub(1, Sem.mul(v_i, 0.035))
		v_child = gen__flat_book(Sem.add(v_name, Sem.mod("_%02d", v_i)), v_mats, Sem.mul(v_width, v_factor), Sem.mul(v_depth, v_factor), v_h, v__BOOK_COLOURS[Sem.mod(v_i, Sem.py_len(v__BOOK_COLOURS))], v_root)
		v_child.location = [Sem.mul(v_rng.uniform(Sem.neg(0.018), 0.018), v_width), Sem.mul(v_rng.uniform(Sem.neg(0.025), 0.025), v_depth), v_bottom]
		v_child.rotation_euler[2] = v_rng.uniform(Sem.neg(0.1), 0.1)
		v_bottom = Sem.add(v_bottom, v_h)
	return v_root

static func gen_open_book(v_name, v_mats, v_width = 0.45, v_depth = 0.3, v_height = 0.055, v_parent = null):
	var v_a = null
	var v_b = null
	var v_cf = null
	var v_csec = null
	var v_cv = null
	var v_faces = null
	var v_ff = null
	var v_j = null
	var v_k = null
	var v_n = null
	var v_page_height = null
	var v_points = null
	var v_root = null
	var v_row_xs = null
	var v_section = null
	var v_side = null
	var v_t = null
	var v_thickness = null
	var v_verts = null
	var v_vv = null
	var v_x = null
	var v_xs = null
	var v_y = null
	var v_yy = null
	var v_z = null
	var v_zs = null
	v_root = gen__root(v_name, "open_book", v_parent, {"width": v_width, "depth": v_depth, "height": v_height})
	for tmp_42 in [Sem.neg(1), 1]:
		v_side = tmp_42
		v_xs = [Sem.mul(Sem.mul(v_side, v_width), 0.5), Sem.mul(Sem.mul(v_side, v_width), 0.25), 0]
		v_zs = [Sem.mul(v_height, 0.64), v_height, Sem.mul(v_height, 0.45)]
		v_section = Sem.add(Sem.py_list(Sem.py_zip(v_xs, v_zs)), Sem.map_array(Sem.py_reversed(Sem.py_list(Sem.py_zip(v_xs, v_zs))), func(tmp_43): var tmp_44 = tmp_43[0]; var tmp_45 = tmp_43[1]; return [tmp_44, Sem.sub(tmp_45, Sem.mul(v_height, 0.22))]))
		v_verts = Sem.flat_map([Sem.mul(Sem.neg(v_depth), 0.47), Sem.mul(v_depth, 0.47)], func(tmp_46): var tmp_47 = tmp_46; return Sem.map_array(v_section, func(tmp_48): var tmp_49 = tmp_48[0]; var tmp_50 = tmp_48[1]; return [tmp_49, tmp_47, tmp_50]))
		v_n = Sem.py_len(v_section)
		v_faces = [Sem.py_tuple(Sem.py_reversed(range(v_n))), Sem.py_tuple(range(v_n, Sem.mul(2, v_n)))]
		v_faces = Sem.add(v_faces, Sem.map_array(range(v_n), func(tmp_51): var tmp_52 = tmp_51; return [tmp_52, Sem.mod(Sem.add(tmp_52, 1), v_n), Sem.add(Sem.mod(Sem.add(tmp_52, 1), v_n), v_n), Sem.add(tmp_52, v_n)]))
		Geo.gen_mesh(Sem.add(v_name, Sem.mod("_PageBlock_%d", v_side)), v_verts, v_faces, v_mats["cream"], v_root, 0)
		v_csec = [[0, 0], [Sem.mul(Sem.mul(v_side, v_width), 0.52), Sem.mul(v_height, 0.2)], [Sem.mul(Sem.mul(v_side, v_width), 0.52), Sem.mul(v_height, 0.32)], [0, Sem.mul(v_height, 0.12)]]
		v_cv = Sem.flat_map([Sem.div(Sem.neg(v_depth), 2), Sem.div(v_depth, 2)], func(tmp_53): var tmp_54 = tmp_53; return Sem.map_array(v_csec, func(tmp_55): var tmp_56 = tmp_55[0]; var tmp_57 = tmp_55[1]; return [tmp_56, tmp_54, tmp_57]))
		v_cf = [[3, 2, 1, 0], [4, 5, 6, 7]]
		v_cf = Sem.add(v_cf, Sem.map_array(range(4), func(tmp_58): var tmp_59 = tmp_58; return [tmp_59, Sem.mod(Sem.add(tmp_59, 1), 4), Sem.add(Sem.mod(Sem.add(tmp_59, 1), 4), 4), Sem.add(tmp_59, 4)]))
		Geo.gen_mesh(Sem.add(v_name, Sem.mod("_Cover_%d", v_side)), v_cv, v_cf, v_mats["book_red"], v_root, 0)
		v_page_height = func(tmp_60):
			v_t = Sem.div(abs(tmp_60), v_width)
			if Sem.truth(((v_t <= 0.25))):
				return Sem.mul(v_height, Sem.add(0.45, Sem.div(Sem.mul(0.55, v_t), 0.25)))
			return Sem.mul(v_height, Sem.sub(1, Sem.div(Sem.mul(0.36, Sem.sub(v_t, 0.25)), 0.25)))
		for tmp_61 in range(6):
			v_j = tmp_61
			v_y = Sem.mul(v_depth, Sem.add(Sem.neg(0.31), Sem.mul(v_j, 0.105)))
			v_row_xs = [Sem.mul(Sem.mul(v_side, v_width), 0.44), Sem.mul(Sem.mul(v_side, v_width), 0.25), Sem.mul(Sem.mul(v_side, v_width), Sem.add(0.065, Sem.mul(0.012, Sem.mod(v_j, 2))))]
			for tmp_62 in range(2):
				v_k = tmp_62
				var tmp_63 = Sem.slice_array(v_row_xs, v_k, Sem.add(v_k, 2), null)
				v_a = tmp_63[0]
				v_b = tmp_63[1]
				v_thickness = Sem.mul(v_depth, 0.009)
				v_points = [[v_a, v_y, Sem.add(v_page_height.call(v_a), 0.0008)], [v_b, v_y, Sem.add(v_page_height.call(v_b), 0.0008)], [v_b, Sem.add(v_y, v_thickness), Sem.add(v_page_height.call(v_b), 0.0008)], [v_a, Sem.add(v_y, v_thickness), Sem.add(v_page_height.call(v_a), 0.0008)]]
				v_vv = Sem.add(v_points, Sem.map_array(v_points, func(tmp_64): var tmp_65 = tmp_64[0]; var tmp_66 = tmp_64[1]; var tmp_67 = tmp_64[2]; return [tmp_65, tmp_66, Sem.sub(tmp_67, 0.0004)]))
				v_ff = [[0, 1, 2, 3], [7, 6, 5, 4], [0, 4, 5, 1], [1, 5, 6, 2], [2, 6, 7, 3], [3, 7, 4, 0]]
				Geo.gen_mesh(Sem.add(v_name, Sem.mod("_Line_%d_%d_%d", [v_side, v_j, v_k])), v_vv, v_ff, v_mats["stone_dark"], v_root, 0)
	return v_root

static func gen_bookshelf(v_name, v_mats, v_width = 2.0, v_depth = 0.42, v_height = 2.55, v_shelves = 4, v_bays = 2, v_fill = 0.78, v_seed = 7, v_parent = null):
	var v_available_height = null
	var v_base = null
	var v_bay = null
	var v_bay_width = null
	var v_bh = null
	var v_book_depth = null
	var v_bw = null
	var v_crown = null
	var v_cx = null
	var v_divider = null
	var v_free = null
	var v_i = null
	var v_index = null
	var v_inner_width = null
	var v_left = null
	var v_level = null
	var v_pitch = null
	var v_post_width = null
	var v_rng = null
	var v_root = null
	var v_shelf_t = null
	var v_side = null
	var v_stack = null
	var v_target = null
	var v_usable = null
	var v_used = null
	var v_volume = null
	var v_x = null
	var v_z = null
	v_root = gen__root(v_name, "bookshelf", v_parent, {"width": v_width, "depth": v_depth, "height": v_height})
	if Sem.truth(Sem.either_lazy(((v_width < 0.4)), func(): return Sem.either_lazy(((v_depth < 0.18)), func(): return ((v_height < 0.65))))):
		push_error(str("bookshelf needs width >= .4, depth >= .18 and height >= .65"))
		return null
	v_rng = Sem.RandomSequence.new(v_seed)
	var tmp_68 = [Sem.py_max(1, int(v_shelves)), Sem.py_max(1, int(v_bays))]
	v_shelves = tmp_68[0]
	v_bays = tmp_68[1]
	v_fill = Sem.py_max(0, Sem.py_min(float(v_fill), 1))
	v_side = Sem.py_min(0.095, Sem.mul(v_width, 0.065))
	v_divider = Sem.mul(v_side, 0.68)
	v_inner_width = Sem.sub(Sem.sub(v_width, Sem.mul(2, v_side)), Sem.mul(Sem.sub(v_bays, 1), v_divider))
	v_bay_width = Sem.div(v_inner_width, v_bays)
	if Sem.truth(((v_bay_width < 0.15))):
		push_error(str("too many bays for bookshelf width"))
		return null
	var tmp_69 = [Sem.mul(v_height, 0.075), Sem.mul(v_height, 0.075)]
	v_base = tmp_69[0]
	v_crown = tmp_69[1]
	v_usable = Sem.sub(Sem.sub(v_height, v_base), v_crown)
	v_pitch = Sem.div(v_usable, v_shelves)
	if Sem.truth(((v_pitch < 0.1))):
		push_error(str("too many shelves for bookshelf height"))
		return null
	Geo.gen_box(Sem.add(v_name, "_Back"), [0, Sem.sub(Sem.div(v_depth, 2), 0.018), Sem.div(v_height, 2)], [Sem.sub(v_width, 0.02), 0.036, Sem.sub(v_height, 0.08)], v_mats["wood_dark"], 0.004, v_root)
	Geo.gen_box(Sem.add(v_name, "_Base"), [0, Sem.neg(0.005), Sem.mul(v_base, 0.45)], [v_width, v_depth, Sem.mul(v_base, 0.9)], v_mats["wood"], 0.012, v_root)
	Geo.gen_box(Sem.add(v_name, "_BaseLip"), [0, Sem.neg(0.012), Sem.mul(v_base, 0.87)], [Sem.mul(v_width, 1.025), Sem.mul(v_depth, 1.05), Sem.mul(v_base, 0.24)], v_mats["wood_light"], 0.009, v_root)
	Geo.gen_box(Sem.add(v_name, "_Cornice"), [0, 0, Sem.sub(v_height, Sem.mul(v_crown, 0.38))], [Sem.mul(v_width, 1.035), Sem.mul(v_depth, 1.1), Sem.mul(v_crown, 0.76)], v_mats["wood"], 0.014, v_root)
	Geo.gen_box(Sem.add(v_name, "_CorniceEdge"), [0, Sem.neg(0.008), Sem.sub(v_height, Sem.mul(v_crown, 0.78))], [Sem.mul(v_width, 1.01), Sem.mul(v_depth, 1.04), Sem.mul(v_crown, 0.2)], v_mats["wood_light"], 0.006, v_root)
	for tmp_70 in range(Sem.add(v_bays, 1)):
		v_i = tmp_70
		v_x = (Sem.add(Sem.div(Sem.neg(v_width), 2), Sem.div(v_side, 2)) if Sem.truth(((v_i == 0))) else (Sem.sub(Sem.div(v_width, 2), Sem.div(v_side, 2)) if Sem.truth(((v_i == v_bays))) else Sem.add(Sem.add(Sem.add(Sem.div(Sem.neg(v_width), 2), v_side), Sem.mul(v_i, v_bay_width)), Sem.mul(Sem.sub(v_i, 0.5), v_divider))))
		v_post_width = (v_side if Sem.truth(((v_i in [0, v_bays]))) else v_divider)
		Geo.gen_box(Sem.add(v_name, Sem.mod("_Stile_%d", v_i)), [v_x, 0, Sem.div(Sem.add(Sem.sub(v_height, v_crown), v_base), 2)], [v_post_width, v_depth, v_usable], v_mats["wood"], 0.008, v_root)
		Geo.gen_box(Sem.add(v_name, Sem.mod("_StileFace_%d", v_i)), [v_x, Sem.sub(Sem.div(Sem.neg(v_depth), 2), 0.008), Sem.div(v_height, 2)], [Sem.mul(v_post_width, 0.65), 0.022, Sem.sub(Sem.sub(v_height, v_base), Sem.mul(v_crown, 0.8))], v_mats["wood_light"], 0.005, v_root)
	for tmp_71 in range(v_bays):
		v_bay = tmp_71
		v_cx = Sem.add(Sem.add(Sem.add(Sem.div(Sem.neg(v_width), 2), v_side), Sem.div(v_bay_width, 2)), Sem.mul(v_bay, Sem.add(v_bay_width, v_divider)))
		for tmp_72 in range(v_shelves):
			v_level = tmp_72
			v_z = Sem.add(v_base, Sem.mul(v_level, v_pitch))
			v_shelf_t = Sem.py_min(0.045, Sem.mul(v_pitch, 0.12))
			Geo.gen_box(Sem.add(v_name, Sem.mod("_Shelf_%d_%d", [v_bay, v_level])), [v_cx, Sem.neg(0.006), Sem.add(v_z, Sem.div(v_shelf_t, 2))], [v_bay_width, Sem.sub(v_depth, 0.025), v_shelf_t], v_mats["wood"], 0.004, v_root)
			Geo.gen_box(Sem.add(v_name, Sem.mod("_ShelfEdge_%d_%d", [v_bay, v_level])), [v_cx, Sem.sub(Sem.div(Sem.neg(v_depth), 2), 0.006), Sem.add(v_z, Sem.mul(v_shelf_t, 0.6))], [v_bay_width, 0.023, Sem.mul(v_shelf_t, 0.65)], v_mats["wood_light"], 0.002, v_root)
			v_left = Sem.add(Sem.sub(v_cx, Sem.div(v_bay_width, 2)), 0.02)
			v_used = 0.0
			v_target = Sem.mul(Sem.sub(v_bay_width, 0.04), v_fill)
			v_available_height = Sem.sub(Sem.sub(v_pitch, v_shelf_t), 0.02)
			v_book_depth = Sem.py_min(Sem.mul(v_depth, 0.69), Sem.mul(v_available_height, 0.78))
			v_index = 0
			while Sem.truth(((v_used < Sem.sub(v_target, 0.025)))):
				v_bw = Sem.py_min(Sem.div(Sem.mul(v_rng.uniform(0.045, 0.085), v_height), 2.55), Sem.sub(v_target, v_used))
				if Sem.truth(((v_bw < 0.018))):
					break
				v_bh = Sem.mul(v_available_height, v_rng.uniform(0.63, 0.94))
				v_volume = gen_book(Sem.add(v_name, Sem.mod("_Book_%d_%d_%02d", [v_bay, v_level, v_index])), v_mats, v_bw, Sem.mul(v_book_depth, v_rng.uniform(0.88, 1)), v_bh, v_rng.choice(v__BOOK_COLOURS), v_root)
				v_volume.location = [Sem.add(Sem.add(v_left, v_used), Sem.div(v_bw, 2)), Sem.add(Sem.add(Sem.add(Sem.div(Sem.neg(v_depth), 2), Sem.div(v_book_depth, 2)), 0.016), v_rng.uniform(0, 0.012)), Sem.add(v_z, v_shelf_t)]
				v_used = Sem.add(v_used, Sem.add(v_bw, 0.003))
				v_index = Sem.add(v_index, 1)
				if Sem.truth(Sem.both_lazy(((Sem.mod(v_index, 4) == 0)), func(): return ((v_used < Sem.mul(v_target, 0.8))))):
					v_used = Sem.add(v_used, v_rng.uniform(0.015, 0.035))
			v_free = Sem.sub(Sem.sub(v_bay_width, 0.05), v_used)
			if Sem.truth(Sem.both_lazy(((v_fill > 0)), func(): return Sem.both_lazy(((v_free > 0.17)), func(): return ((Sem.mod(v_level, 2) == Sem.mod(v_bay, 2)))))):
				v_stack = gen_books(Sem.add(v_name, Sem.mod("_ShelfStack_%d_%d", [v_bay, v_level])), v_mats, Sem.py_min(Sem.sub(v_free, 0.015), 0.27), Sem.mul(v_book_depth, 0.92), Sem.mul(v_available_height, 0.34), 2, Sem.add(Sem.add(v_seed, Sem.mul(v_bay, 29)), Sem.mul(v_level, 11)), v_root)
				v_stack.location = [Sem.sub(Sem.sub(Sem.add(v_cx, Sem.div(v_bay_width, 2)), Sem.div(v_free, 2)), 0.01), Sem.add(Sem.add(Sem.div(Sem.neg(v_depth), 2), Sem.div(v_book_depth, 2)), 0.018), Sem.add(v_z, v_shelf_t)]
	return v_root

static func gen_table(v_name, v_mats, v_width = 1.6, v_depth = 0.85, v_height = 0.78, v_shape = "rect", v_parent = null):
	var v_angle = null
	var v_apron_z = null
	var v_end = null
	var v_i = null
	var v_inset = null
	var v_j = null
	var v_knob = null
	var v_leg_width = null
	var v_levels = null
	var v_points = null
	var v_profile = null
	var v_radius = null
	var v_root = null
	var v_top_t = null
	var v_x = null
	var v_y = null
	v_root = gen__root(v_name, "table", v_parent, {"width": v_width, "depth": v_depth, "height": v_height})
	v_top_t = Sem.mul(v_height, 0.075)
	if Sem.truth(((v_shape in ["round", "octagon"]))):
		v_points = Sem.map_array(range(8), func(tmp_73): var tmp_74 = tmp_73; return [Sem.mul(Sem.div(v_width, 2), cos(Sem.add(Sem.div(Sem.mul(Sem.mul(2, PI), tmp_74), 8), Sem.div(PI, 8)))), Sem.mul(Sem.div(v_depth, 2), sin(Sem.add(Sem.div(Sem.mul(Sem.mul(2, PI), tmp_74), 8), Sem.div(PI, 8))))])
		Geo.gen_polyprism(Sem.add(v_name, "_Top"), v_points, Sem.sub(v_height, v_top_t), v_height, v_mats["wood_light"], v_root)
		Geo.gen_polyprism(Sem.add(v_name, "_TopUndercut"), Sem.map_array(v_points, func(tmp_75): var tmp_76 = tmp_75[0]; var tmp_77 = tmp_75[1]; return [Sem.mul(tmp_76, 0.96), Sem.mul(tmp_77, 0.96)]), Sem.sub(v_height, Sem.mul(v_top_t, 1.45)), Sem.sub(v_height, v_top_t), v_mats["wood"], v_root)
		v_radius = Sem.py_min(v_width, v_depth)
		v_profile = [[Sem.mul(v_radius, 0.17), 0], [Sem.mul(v_radius, 0.19), 0.08], [Sem.mul(v_radius, 0.11), 0.14], [Sem.mul(v_radius, 0.07), Sem.mul(v_height, 0.38)], [Sem.mul(v_radius, 0.09), Sem.mul(v_height, 0.58)], [Sem.mul(v_radius, 0.12), Sem.mul(v_height, 0.66)], [Sem.mul(v_radius, 0.1), Sem.sub(v_height, Sem.mul(v_top_t, 1.45))]]
		Geo.gen_lathe(Sem.add(v_name, "_Pedestal"), v_profile, 8, v_mats["wood"], v_root, [0, 0, 0])
		for tmp_78 in range(4):
			v_i = tmp_78
			v_angle = Sem.add(Sem.div(Sem.mul(v_i, PI), 2), Sem.div(PI, 4))
			v_end = [Sem.mul(Sem.mul(cos(v_angle), v_width), 0.34), Sem.mul(Sem.mul(sin(v_angle), v_depth), 0.34), 0.045]
			Geo.gen_beam(Sem.add(v_name, Sem.mod("_Foot_%d", v_i)), [0, 0, 0.1], v_end, Sem.mul(v_radius, 0.095), 0.075, v_mats["wood"], v_root, 0.006)
		return v_root
	if Sem.truth(((v_shape != "rect"))):
		push_error(str("table shape must be rect, round or octagon"))
		return null
	Geo.gen_box(Sem.add(v_name, "_Top"), [0, 0, Sem.sub(v_height, Sem.div(v_top_t, 2))], [v_width, v_depth, v_top_t], v_mats["wood_light"], Sem.py_min(0.024, Sem.mul(v_top_t, 0.3)), v_root)
	Geo.gen_box(Sem.add(v_name, "_TopUndercut"), [0, 0, Sem.sub(v_height, Sem.mul(v_top_t, 1.2))], [Sem.mul(v_width, 0.96), Sem.mul(v_depth, 0.95), Sem.mul(v_top_t, 0.45)], v_mats["wood_dark"], 0.006, v_root)
	v_leg_width = Sem.mul(Sem.py_min(v_width, v_depth), 0.11)
	v_inset = Sem.mul(v_leg_width, 0.85)
	for tmp_79 in Sem.py_enumerate([Sem.add(Sem.div(Sem.neg(v_width), 2), v_inset), Sem.sub(Sem.div(v_width, 2), v_inset)]):
		var tmp_80 = tmp_79
		v_i = tmp_80[0]
		v_x = tmp_80[1]
		for tmp_81 in Sem.py_enumerate([Sem.add(Sem.div(Sem.neg(v_depth), 2), v_inset), Sem.sub(Sem.div(v_depth, 2), v_inset)]):
			var tmp_82 = tmp_81
			v_j = tmp_82[0]
			v_y = tmp_82[1]
			v_levels = [[0, Sem.mul(v_leg_width, 0.91)], [0.045, Sem.mul(v_leg_width, 0.91)], [0.065, Sem.mul(v_leg_width, 0.64)], [Sem.mul(v_height, 0.48), Sem.mul(v_leg_width, 0.53)], [Sem.mul(v_height, 0.62), Sem.mul(v_leg_width, 0.88)], [Sem.mul(v_height, 0.68), Sem.mul(v_leg_width, 0.88)], [Sem.mul(v_height, 0.72), Sem.mul(v_leg_width, 0.72)], [Sem.sub(v_height, v_top_t), Sem.mul(v_leg_width, 0.95)]]
			gen__post(Sem.add(v_name, Sem.mod("_Leg_%d_%d", [v_i, v_j])), v_x, v_y, v_levels, v_mats["wood"], v_root)
	v_apron_z = Sem.sub(Sem.sub(v_height, v_top_t), Sem.mul(v_height, 0.075))
	gen__boxes(Sem.add(v_name, "_Aprons"), Sem.add(Sem.map_array([Sem.add(Sem.div(Sem.neg(v_depth), 2), v_inset), Sem.sub(Sem.div(v_depth, 2), v_inset)], func(tmp_83): var tmp_84 = tmp_83; return [[0, tmp_84, v_apron_z], [Sem.sub(v_width, v_inset), 0.045, Sem.mul(v_height, 0.15)]]), Sem.map_array([Sem.add(Sem.div(Sem.neg(v_width), 2), v_inset), Sem.sub(Sem.div(v_width, 2), v_inset)], func(tmp_85): var tmp_86 = tmp_85; return [[tmp_86, 0, v_apron_z], [0.045, Sem.sub(v_depth, v_inset), Sem.mul(v_height, 0.15)]])), v_mats["wood"], v_root, 0.005)
	Geo.gen_box(Sem.add(v_name, "_FrontDrawer"), [0, Sem.sub(Sem.add(Sem.div(Sem.neg(v_depth), 2), v_inset), 0.028), v_apron_z], [Sem.mul(v_width, 0.37), 0.018, Sem.mul(v_height, 0.11)], v_mats["wood_light"], 0.005, v_root)
	for tmp_87 in [Sem.mul(Sem.neg(v_width), 0.105), Sem.mul(v_width, 0.105)]:
		v_x = tmp_87
		v_knob = Geo.gen_ico(Sem.add(v_name, "_DrawerKnob"), [v_x, Sem.sub(Sem.add(Sem.div(Sem.neg(v_depth), 2), v_inset), 0.049), v_apron_z], Sem.mul(v_height, 0.012), v_mats["gold"], 1, v_root)
		v_knob.scale = [1, 0.7, 1]
	return v_root

static func gen_chair(v_name, v_mats, v_width = 0.52, v_depth = 0.53, v_height = 0.98, v_seat_height = 0.44, v_arms = false, v_parent = null):
	var v_arm_z = null
	var v_j = null
	var v_leg = null
	var v_root = null
	var v_x = null
	var v_xleg = null
	var v_yb = null
	var v_yf = null
	v_root = gen__root(v_name, "chair", v_parent, {"width": v_width, "depth": v_depth, "height": v_height, "seat_height": v_seat_height})
	if Sem.truth(((v_seat_height >= Sem.mul(v_height, 0.78)))):
		push_error(str("chair back needs height above seat"))
		return null
	v_leg = Sem.mul(Sem.py_min(v_width, v_depth), 0.11)
	var tmp_88 = [Sem.mul(v_width, 0.39), Sem.mul(Sem.neg(v_depth), 0.37), Sem.mul(v_depth, 0.36)]
	v_xleg = tmp_88[0]
	v_yf = tmp_88[1]
	v_yb = tmp_88[2]
	for tmp_89 in [Sem.neg(v_xleg), v_xleg]:
		v_x = tmp_89
		gen__post(Sem.add(v_name, "_FrontLeg"), v_x, v_yf, [[0, Sem.mul(v_leg, 0.7)], [0.045, Sem.mul(v_leg, 0.85)], [Sem.sub(v_seat_height, 0.09), v_leg], [Sem.sub(v_seat_height, 0.02), v_leg]], v_mats["wood"], v_root)
		gen__post(Sem.add(v_name, "_BackPost"), v_x, v_yb, [[0, Sem.mul(v_leg, 0.75)], [v_seat_height, v_leg], [Sem.sub(v_height, 0.07), Sem.mul(v_leg, 0.9)], [v_height, Sem.mul(v_leg, 1.04)]], v_mats["wood"], v_root)
	Geo.gen_box(Sem.add(v_name, "_SeatFrame"), [0, 0, Sem.sub(v_seat_height, 0.08)], [Sem.mul(v_width, 0.97), Sem.mul(v_depth, 0.96), 0.075], v_mats["wood"], 0.012, v_root)
	gen__cushion(Sem.add(v_name, "_Seat"), Sem.mul(v_width, 0.87), Sem.mul(v_depth, 0.87), Sem.sub(v_seat_height, 0.05), 0.05, v_mats["green"], v_root)
	Geo.gen_box(Sem.add(v_name, "_BackTopRail"), [0, v_yb, Sem.sub(v_height, 0.035)], [Sem.mul(v_width, 0.98), Sem.mul(v_leg, 1.12), 0.07], v_mats["wood_light"], 0.01, v_root)
	Geo.gen_box(Sem.add(v_name, "_BackLowerRail"), [0, v_yb, Sem.add(v_seat_height, 0.13)], [Sem.mul(v_width, 0.86), Sem.mul(v_leg, 0.85), 0.055], v_mats["wood"], 0.005, v_root)
	for tmp_90 in Sem.py_enumerate([Sem.mul(Sem.neg(v_width), 0.22), 0, Sem.mul(v_width, 0.22)]):
		var tmp_91 = tmp_90
		v_j = tmp_91[0]
		v_x = tmp_91[1]
		Geo.gen_box(Sem.add(v_name, Sem.mod("_BackSlat_%d", v_j)), [v_x, v_yb, Sem.div(Sem.add(Sem.add(Sem.sub(v_height, 0.07), v_seat_height), 0.155), 2)], [Sem.mul(v_leg, 0.65), Sem.mul(v_leg, 0.64), Sem.sub(Sem.sub(v_height, 0.225), v_seat_height)], v_mats["wood"], 0.005, v_root)
	for tmp_92 in [Sem.neg(v_xleg), v_xleg]:
		v_x = tmp_92
		Geo.gen_beam(Sem.add(v_name, "_Stretcher"), [v_x, v_yf, Sem.mul(v_seat_height, 0.4)], [v_x, v_yb, Sem.mul(v_seat_height, 0.4)], Sem.mul(v_leg, 0.5), Sem.mul(v_leg, 0.5), v_mats["wood"], v_root, 0.003)
	if Sem.truth(v_arms):
		v_arm_z = Sem.add(v_seat_height, 0.2)
		for tmp_93 in [Sem.neg(v_xleg), v_xleg]:
			v_x = tmp_93
			Geo.gen_beam(Sem.add(v_name, "_ArmSupport"), [v_x, v_yf, v_seat_height], [v_x, v_yf, v_arm_z], Sem.mul(v_leg, 0.65), Sem.mul(v_leg, 0.65), v_mats["wood"], v_root, 0.004)
			Geo.gen_box(Sem.add(v_name, "_Arm"), [v_x, Sem.neg(0.01), v_arm_z], [Sem.mul(v_leg, 1.55), Sem.mul(v_depth, 0.86), 0.045], v_mats["wood_light"], 0.009, v_root)
	return v_root

static func gen_bench(v_name, v_mats, v_width = 1.8, v_depth = 0.6, v_height = 1.02, v_seat_height = 0.45, v_parent = null):
	var v_count = null
	var v_i = null
	var v_leg = null
	var v_lx = null
	var v_root = null
	var v_slat_bottom = null
	var v_slat_top = null
	var v_x = null
	var v_yb = null
	var v_yf = null
	v_root = gen__root(v_name, "bench", v_parent, {"width": v_width, "depth": v_depth, "height": v_height, "seat_height": v_seat_height})
	if Sem.truth(((v_seat_height >= Sem.mul(v_height, 0.75)))):
		push_error(str("bench back needs height above seat"))
		return null
	v_leg = Sem.py_min(0.085, Sem.mul(v_width, 0.055), Sem.mul(v_depth, 0.15))
	var tmp_94 = [Sem.sub(Sem.div(v_width, 2), Sem.mul(v_leg, 0.9)), Sem.mul(Sem.neg(v_depth), 0.34), Sem.mul(v_depth, 0.37)]
	v_lx = tmp_94[0]
	v_yf = tmp_94[1]
	v_yb = tmp_94[2]
	for tmp_95 in [Sem.neg(v_lx), v_lx]:
		v_x = tmp_95
		gen__post(Sem.add(v_name, "_FrontLeg"), v_x, v_yf, [[0, Sem.mul(v_leg, 0.85)], [0.045, Sem.mul(v_leg, 0.85)], [0.075, Sem.mul(v_leg, 0.65)], [Sem.add(v_seat_height, 0.22), Sem.mul(v_leg, 0.85)]], v_mats["wood"], v_root)
		gen__post(Sem.add(v_name, "_RearLeg"), v_x, v_yb, [[0, Sem.mul(v_leg, 0.85)], [v_seat_height, v_leg], [Sem.sub(v_height, 0.06), v_leg], [v_height, Sem.mul(v_leg, 1.25)]], v_mats["wood"], v_root)
		Geo.gen_box(Sem.add(v_name, "_ArmRest"), [v_x, 0, Sem.add(v_seat_height, 0.22)], [Sem.mul(v_leg, 1.38), Sem.mul(v_depth, 0.93), 0.055], v_mats["wood_light"], 0.009, v_root)
	Geo.gen_box(Sem.add(v_name, "_SeatBase"), [0, 0, Sem.sub(v_seat_height, 0.1)], [Sem.mul(v_width, 0.96), Sem.mul(v_depth, 0.92), 0.1], v_mats["wood"], 0.012, v_root)
	gen__cushion(Sem.add(v_name, "_LongCushion"), Sem.mul(v_width, 0.88), Sem.mul(v_depth, 0.77), Sem.sub(v_seat_height, 0.065), 0.065, v_mats["green"], v_root)
	Geo.gen_box(Sem.add(v_name, "_BackTopRail"), [0, v_yb, Sem.sub(v_height, 0.065)], [v_width, 0.075, 0.09], v_mats["wood_light"], 0.012, v_root)
	Geo.gen_box(Sem.add(v_name, "_BackBottomRail"), [0, v_yb, Sem.add(v_seat_height, 0.12)], [Sem.mul(v_width, 0.93), 0.055, 0.06], v_mats["wood"], 0.005, v_root)
	var tmp_96 = [Sem.add(v_seat_height, 0.15), Sem.sub(v_height, 0.11)]
	v_slat_bottom = tmp_96[0]
	v_slat_top = tmp_96[1]
	v_count = Sem.py_max(3, Sem.py_round(Sem.div(v_width, 0.2)))
	for tmp_97 in range(v_count):
		v_i = tmp_97
		v_x = Sem.add(Sem.mul(Sem.neg(v_width), 0.39), Sem.div(Sem.mul(Sem.mul(v_width, 0.78), v_i), Sem.sub(v_count, 1)))
		Geo.gen_box(Sem.add(v_name, Sem.mod("_Slat_%02d", v_i)), [v_x, v_yb, Sem.div(Sem.add(v_slat_top, v_slat_bottom), 2)], [0.045, 0.042, Sem.sub(v_slat_top, v_slat_bottom)], v_mats["wood"], 0.004, v_root)
	return v_root

static func gen_reception_desk(v_name, v_mats, v_width = 2.35, v_depth = 0.95, v_height = 1.08, v_panels = 3, v_details = true, v_parent = null):
	var v_a = null
	var v_bx = null
	var v_by = null
	var v_case_h = null
	var v_faces = null
	var v_field_h = null
	var v_field_z = null
	var v_front_y = null
	var v_i = null
	var v_inner_front = null
	var v_mod = null
	var v_outline = null
	var v_panel_pitch = null
	var v_plinth = null
	var v_root = null
	var v_sd = null
	var v_sh = null
	var v_side = null
	var v_side_t = null
	var v_sign = null
	var v_specs = null
	var v_sw = null
	var v_top = null
	var v_top_depth = null
	var v_verts = null
	var v_wall = null
	var v_x = null
	var v_x0 = null
	var v_y = null
	var v_y0 = null
	var v_y1 = null
	var v_z = null
	var v_z0 = null
	v_root = gen__root(v_name, "reception_desk", v_parent, {"width": v_width, "depth": v_depth, "height": v_height})
	v_panels = Sem.py_max(1, int(v_panels))
	v_wall = Sem.py_min(0.09, Sem.mul(v_depth, 0.12))
	v_front_y = Sem.div(Sem.neg(v_depth), 2)
	v_case_h = Sem.sub(v_height, 0.09)
	v_specs = [[[0, Sem.add(v_front_y, Sem.div(v_wall, 2)), Sem.div(v_case_h, 2)], [v_width, v_wall, v_case_h]], [[Sem.add(Sem.div(Sem.neg(v_width), 2), Sem.div(v_wall, 2)), 0, Sem.div(v_case_h, 2)], [v_wall, v_depth, v_case_h]], [[Sem.sub(Sem.div(v_width, 2), Sem.div(v_wall, 2)), 0, Sem.div(v_case_h, 2)], [v_wall, v_depth, v_case_h]]]
	gen__boxes(Sem.add(v_name, "_Carcass"), v_specs, v_mats["wood"], v_root, 0.01)
	v_plinth = Sem.add([[[0, Sem.add(v_front_y, 0.012), 0.065], [Sem.add(v_width, 0.06), Sem.add(v_wall, 0.07), 0.13]]], Sem.map_array([Sem.add(Sem.div(Sem.neg(v_width), 2), 0.015), Sem.sub(Sem.div(v_width, 2), 0.015)], func(tmp_98): var tmp_99 = tmp_98; return [[tmp_99, 0, 0.065], [Sem.add(v_wall, 0.055), Sem.add(v_depth, 0.035), 0.13]]))
	gen__boxes(Sem.add(v_name, "_Plinth"), v_plinth, v_mats["wood_dark"], v_root, 0.009)
	Geo.gen_box(Sem.add(v_name, "_WritingSurface"), [0, 0.035, Sem.sub(v_height, 0.27)], [Sem.sub(v_width, Sem.mul(v_wall, 2)), Sem.sub(Sem.sub(v_depth, v_wall), 0.04), 0.055], v_mats["wood_light"], 0.008, v_root)
	v_top_depth = Sem.py_min(0.3, Sem.mul(v_depth, 0.32))
	v_a = Sem.add(Sem.div(v_width, 2), 0.05)
	var tmp_100 = [Sem.sub(v_front_y, 0.035), Sem.add(Sem.div(v_depth, 2), 0.035)]
	v_y0 = tmp_100[0]
	v_y1 = tmp_100[1]
	var tmp_101 = [Sem.mul(v_top_depth, 0.72), Sem.add(v_y0, v_top_depth)]
	v_side_t = tmp_101[0]
	v_inner_front = tmp_101[1]
	v_outline = [[Sem.neg(v_a), v_y0], [v_a, v_y0], [v_a, v_y1], [Sem.sub(v_a, v_side_t), v_y1], [Sem.sub(v_a, v_side_t), v_inner_front], [Sem.add(Sem.neg(v_a), v_side_t), v_inner_front], [Sem.add(Sem.neg(v_a), v_side_t), v_y1], [Sem.neg(v_a), v_y1]]
	v_top = Geo.gen_polyprism(Sem.add(v_name, "_CounterTop"), v_outline, Sem.sub(v_height, 0.09), v_height, v_mats["wood_light"], v_root)
	v_mod = Geo.add_bevel(v_top, "Counter_edge_highlight", "BEVEL")
	var tmp_102 = [0.016, 1]
	v_mod.width = tmp_102[0]
	v_mod.segments = tmp_102[1]
	v_mod.use_clamp_overlap = true
	var tmp_103 = [Sem.sub(v_height, 0.31), Sem.sub(Sem.div(v_height, 2), 0.015)]
	v_field_h = tmp_103[0]
	v_field_z = tmp_103[1]
	v_panel_pitch = Sem.div(Sem.sub(v_width, 0.17), v_panels)
	for tmp_104 in range(v_panels):
		v_i = tmp_104
		v_x = Sem.add(Sem.add(Sem.div(Sem.neg(v_width), 2), 0.085), Sem.mul(Sem.add(v_i, 0.5), v_panel_pitch))
		gen__panel(Sem.add(v_name, Sem.mod("_FrontPanel_%d", v_i)), v_x, v_field_z, Sem.sub(v_panel_pitch, 0.065), v_field_h, v_front_y, v_mats, v_root)
	for tmp_105 in [Sem.neg(1), 1]:
		v_sign = tmp_105
		v_side = Geo.gen_group(Sem.add(v_name, Sem.mod("_SideDetail_%d", v_sign)), [Sem.div(Sem.mul(v_sign, v_width), 2), 0, 0], Sem.div(Sem.mul(v_sign, PI), 2), v_root)
		gen__panel(Sem.add(v_name, Sem.mod("_SidePanel_%d", v_sign)), 0, v_field_z, Sem.sub(v_depth, 0.18), v_field_h, 0, v_mats, v_side)
	if Sem.truth(v_details):
		var tmp_106 = [Sem.py_min(0.32, Sem.mul(v_width, 0.16)), 0.12, 0.13]
		v_sw = tmp_106[0]
		v_sd = tmp_106[1]
		v_sh = tmp_106[2]
		var tmp_107 = [Sem.mul(Sem.neg(v_width), 0.13), Sem.sub(Sem.add(v_front_y, Sem.mul(v_top_depth, 0.44)), 0.035), v_height]
		v_x0 = tmp_107[0]
		v_y0 = tmp_107[1]
		v_z0 = tmp_107[2]
		v_verts = Sem.flat_map([Sem.div(Sem.neg(v_sw), 2), Sem.div(v_sw, 2)], func(tmp_108): var tmp_109 = tmp_108; return Sem.map_array([[Sem.div(Sem.neg(v_sd), 2), 0], [Sem.div(v_sd, 2), 0], [Sem.div(v_sd, 2), v_sh]], func(tmp_110): var tmp_111 = tmp_110[0]; var tmp_112 = tmp_110[1]; return [Sem.add(v_x0, tmp_109), Sem.add(v_y0, tmp_111), Sem.add(v_z0, tmp_112)]))
		v_faces = [[2, 1, 0], [3, 4, 5], [0, 1, 4, 3], [1, 2, 5, 4], [2, 0, 3, 5]]
		Geo.gen_mesh(Sem.add(v_name, "_BrassSign"), v_verts, v_faces, v_mats["gold"], v_root, 0.003)
		var tmp_113 = [Sem.mul(v_width, 0.3), Sem.sub(Sem.add(v_front_y, Sem.mul(v_top_depth, 0.46)), 0.035)]
		v_bx = tmp_113[0]
		v_by = tmp_113[1]
		Geo.gen_cylinder(Sem.add(v_name, "_BellBase"), [v_bx, v_by, Sem.add(v_height, 0.008)], 0.055, 0.016, v_mats["wood_dark"], 8, v_root)
		Geo.gen_lathe(Sem.add(v_name, "_ServiceBell"), [[0.047, 0], [0.047, 0.015], [0.039, 0.035], [0.023, 0.047], [0.006, 0.051], [0.006, 0.062]], 8, v_mats["gold"], v_root, [v_bx, v_by, Sem.add(v_height, 0.016)])
	return v_root

static func gen__leaf(v_name, v_start, v_end, v_width, v_mat, v_parent):
	var v_cx = null
	var v_cy = null
	var v_cz = null
	var v_dx = null
	var v_dy = null
	var v_ex = null
	var v_ey = null
	var v_ez = null
	var v_faces = null
	var v_length_xy = null
	var v_sx = null
	var v_sy = null
	var v_sz = null
	var v_tx = null
	var v_ty = null
	var v_verts = null
	var tmp_114 = v_start
	v_sx = tmp_114[0]
	v_sy = tmp_114[1]
	v_sz = tmp_114[2]
	var tmp_115 = v_end
	v_ex = tmp_115[0]
	v_ey = tmp_115[1]
	v_ez = tmp_115[2]
	var tmp_116 = [Sem.sub(v_ex, v_sx), Sem.sub(v_ey, v_sy)]
	v_dx = tmp_116[0]
	v_dy = tmp_116[1]
	v_length_xy = Sem.hypot(v_dx, v_dy)
	var tmp_117 = ([Sem.div(Sem.neg(v_dy), v_length_xy), Sem.div(v_dx, v_length_xy)] if Sem.truth(((v_length_xy > 1e-08))) else [1, 0])
	v_tx = tmp_117[0]
	v_ty = tmp_117[1]
	var tmp_118 = [Sem.mul(Sem.add(v_sx, v_ex), 0.5), Sem.mul(Sem.add(v_sy, v_ey), 0.5), Sem.mul(Sem.add(v_sz, v_ez), 0.5)]
	v_cx = tmp_118[0]
	v_cy = tmp_118[1]
	v_cz = tmp_118[2]
	v_verts = [v_start, v_end, [Sem.add(v_cx, Sem.div(Sem.mul(v_tx, v_width), 2)), Sem.add(v_cy, Sem.div(Sem.mul(v_ty, v_width), 2)), v_cz], [Sem.sub(v_cx, Sem.div(Sem.mul(v_tx, v_width), 2)), Sem.sub(v_cy, Sem.div(Sem.mul(v_ty, v_width), 2)), v_cz], [v_cx, v_cy, Sem.add(v_cz, Sem.mul(v_width, 0.14))], [v_cx, v_cy, Sem.sub(v_cz, Sem.mul(v_width, 0.04))]]
	v_faces = [[0, 2, 4], [2, 1, 4], [1, 3, 4], [3, 0, 4], [2, 0, 5], [1, 2, 5], [3, 1, 5], [0, 3, 5]]
	return Geo.gen_mesh(v_name, v_verts, v_faces, v_mat, v_parent, 0)

static func gen_planter(v_name, v_mats, v_width = 0.52, v_height = 0.66, v_flower_count = 7, v_seed = 7, v_parent = null):
	var v_angle = null
	var v_centre = null
	var v_count = null
	var v_end = null
	var v_flower_radius = null
	var v_flower_z = null
	var v_i = null
	var v_obj = null
	var v_outer = null
	var v_petal = null
	var v_pot_h = null
	var v_profile = null
	var v_radius = null
	var v_rng = null
	var v_root = null
	var v_rr = null
	var v_start = null
	var v_theta = null
	var v_x = null
	var v_y = null
	v_root = gen__root(v_name, "planter", v_parent, {"width": v_width, "height": v_height})
	v_rng = Sem.RandomSequence.new(v_seed)
	var tmp_119 = [Sem.mul(v_height, 0.44), Sem.mul(v_width, 0.31)]
	v_pot_h = tmp_119[0]
	v_radius = tmp_119[1]
	v_profile = [[Sem.mul(v_radius, 0.6), 0], [Sem.mul(v_radius, 0.67), Sem.mul(v_pot_h, 0.07)], [Sem.mul(v_radius, 0.91), Sem.mul(v_pot_h, 0.78)], [Sem.mul(v_radius, 0.94), Sem.mul(v_pot_h, 0.84)], [v_radius, Sem.mul(v_pot_h, 0.86)], [v_radius, v_pot_h], [Sem.mul(v_radius, 0.82), v_pot_h], [Sem.mul(v_radius, 0.78), Sem.mul(v_pot_h, 0.81)], [Sem.mul(v_radius, 0.56), Sem.mul(v_pot_h, 0.17)], [0, Sem.mul(v_pot_h, 0.17)]]
	Geo.gen_lathe(Sem.add(v_name, "_Pot"), v_profile, 8, v_mats["stone"], v_root, [0, 0, 0])
	Geo.gen_cylinder(Sem.add(v_name, "_Soil"), [0, 0, Sem.mul(v_pot_h, 0.86)], Sem.mul(v_radius, 0.78), Sem.mul(v_height, 0.018), v_mats["wood_dark"], 8, v_root)
	for tmp_120 in range(10):
		v_i = tmp_120
		v_theta = Sem.add(Sem.div(Sem.mul(Sem.mul(2, PI), v_i), 10), v_rng.uniform(Sem.neg(0.15), 0.15))
		v_outer = Sem.mul(v_width, v_rng.uniform(0.38, 0.48))
		v_start = [Sem.mul(Sem.mul(cos(v_theta), v_width), 0.05), Sem.mul(Sem.mul(sin(v_theta), v_width), 0.05), Sem.mul(v_pot_h, 0.92)]
		v_end = [Sem.mul(cos(v_theta), v_outer), Sem.mul(sin(v_theta), v_outer), Sem.mul(v_height, v_rng.uniform(0.48, 0.68))]
		gen__leaf(Sem.add(v_name, Sem.mod("_Leaf_%02d", v_i)), v_start, v_end, Sem.mul(v_width, v_rng.uniform(0.15, 0.23)), v_mats[("leaf" if Sem.truth(Sem.mod(v_i, 3)) else "green")], v_root)
	v_count = Sem.py_max(0, int(v_flower_count))
	for tmp_121 in range(v_count):
		v_i = tmp_121
		if Sem.truth(((v_i == 0))):
			var tmp_122 = [0, 0, Sem.mul(v_height, 0.89)]
			v_x = tmp_122[0]
			v_y = tmp_122[1]
			v_flower_z = tmp_122[2]
		else:
			v_angle = Sem.add(Sem.div(Sem.mul(Sem.mul(2, PI), Sem.sub(v_i, 1)), Sem.py_max(1, Sem.sub(v_count, 1))), 0.2)
			v_rr = Sem.mul(v_width, (0.23 if Sem.truth(((v_count <= 8))) else 0.29))
			var tmp_123 = [Sem.mul(cos(v_angle), v_rr), Sem.mul(sin(v_angle), v_rr)]
			v_x = tmp_123[0]
			v_y = tmp_123[1]
			v_flower_z = Sem.mul(v_height, Sem.add(0.72, Sem.mul(0.06, sin(Sem.add(Sem.mul(v_angle, 2), 0.4)))))
		v_flower_radius = Sem.py_min(Sem.mul(v_width, 0.115), Sem.mul(v_height, 0.09))
		Geo.gen_beam(Sem.add(v_name, Sem.mod("_Stem_%02d", v_i)), [Sem.mul(v_x, 0.35), Sem.mul(v_y, 0.35), Sem.mul(v_pot_h, 0.85)], [v_x, v_y, v_flower_z], Sem.mul(v_width, 0.012), Sem.mul(v_width, 0.012), v_mats["leaf"], v_root, 0)
		v_centre = Geo.gen_ico(Sem.add(v_name, Sem.mod("_FlowerHeart_%02d", v_i)), [v_x, v_y, Sem.add(v_flower_z, Sem.mul(v_flower_radius, 0.15))], Sem.mul(v_flower_radius, 0.65), v_mats["cream"], 1, v_root)
		v_centre.scale = [1, 1, 0.75]
		for tmp_124 in range(6):
			v_petal = tmp_124
			v_theta = Sem.add(Sem.div(Sem.mul(v_petal, PI), 3), Sem.mul(v_i, 0.37))
			v_rr = Sem.mul(v_flower_radius, 0.65)
			v_obj = Geo.gen_ico(Sem.add(v_name, Sem.mod("_Petal_%02d_%d", [v_i, v_petal])), [Sem.add(v_x, Sem.mul(cos(v_theta), v_rr)), Sem.add(v_y, Sem.mul(sin(v_theta), v_rr)), Sem.add(v_flower_z, Sem.mul(v_rng.uniform(Sem.neg(0.05), 0.08), v_flower_radius))], Sem.mul(v_flower_radius, 0.62), v_mats["cream"], 1, v_root)
			v_obj.scale = [1, 1, 0.7]
		Geo.gen_ico(Sem.add(v_name, Sem.mod("_Pollen_%02d", v_i)), [v_x, v_y, Sem.add(v_flower_z, Sem.mul(v_flower_radius, 0.6))], Sem.mul(v_flower_radius, 0.25), v_mats["wall"], 1, v_root)
	return v_root

static func gen__art_polygon(v_name, v_points, v_face_y, v_mat, v_parent):
	var v_faces = null
	var v_j = null
	var v_n = null
	var v_vertices = null
	var v_x = null
	var v_y = null
	var v_z = null
	v_n = Sem.py_len(v_points)
	v_vertices = Sem.flat_map([0, 0.0008], func(tmp_125): var tmp_126 = tmp_125; return Sem.map_array(v_points, func(tmp_127): var tmp_128 = tmp_127[0]; var tmp_129 = tmp_127[1]; return [tmp_128, Sem.add(v_face_y, tmp_126), tmp_129]))
	v_faces = [Sem.py_tuple(range(v_n)), Sem.py_tuple(Sem.py_reversed(range(v_n, Sem.mul(2, v_n))))]
	v_faces = Sem.add(v_faces, Sem.map_array(range(v_n), func(tmp_130): var tmp_131 = tmp_130; return [tmp_131, Sem.add(tmp_131, v_n), Sem.add(Sem.mod(Sem.add(tmp_131, 1), v_n), v_n), Sem.mod(Sem.add(tmp_131, 1), v_n)]))
	return Geo.gen_mesh(v_name, v_vertices, v_faces, v_mat, v_parent, 0)

static func gen_painting(v_name, v_mats, v_width = 1.05, v_height = 0.85, v_depth = 0.065, v_style = "city", v_seed = 7, v_parent = null):
	var v_a = null
	var v_bh = null
	var v_border = null
	var v_bw = null
	var v_fore = null
	var v_frame = null
	var v_high = null
	var v_i = null
	var v_inner_h = null
	var v_inner_w = null
	var v_low = null
	var v_mountains = null
	var v_near = null
	var v_polygon = null
	var v_rng = null
	var v_root = null
	var v_sr = null
	var v_sun = null
	var v_sun_x = null
	var v_sun_z = null
	var v_tower = null
	var v_tower_w = null
	var v_tower_x = null
	var v_tree_h = null
	var v_tree_w = null
	var v_x = null
	var v_x0 = null
	var v_z = null
	v_root = gen__root(v_name, "painting", v_parent, {"width": v_width, "height": v_height, "depth": v_depth})
	if Sem.truth(((v_style not in ["city", "landscape"]))):
		push_error(str("painting style must be city or landscape"))
		return null
	v_rng = Sem.RandomSequence.new(v_seed)
	v_border = Sem.mul(Sem.py_min(v_width, v_height), 0.075)
	Geo.gen_box(Sem.add(v_name, "_Back"), [0, Sem.mul(v_depth, 0.21), Sem.div(v_height, 2)], [v_width, Sem.mul(v_depth, 0.55), v_height], v_mats["wood_dark"], 0.006, v_root)
	v_frame = [[[Sem.add(Sem.div(Sem.neg(v_width), 2), Sem.div(v_border, 2)), Sem.mul(Sem.neg(v_depth), 0.12), Sem.div(v_height, 2)], [v_border, v_depth, v_height]], [[Sem.sub(Sem.div(v_width, 2), Sem.div(v_border, 2)), Sem.mul(Sem.neg(v_depth), 0.12), Sem.div(v_height, 2)], [v_border, v_depth, v_height]], [[0, Sem.mul(Sem.neg(v_depth), 0.12), Sem.div(v_border, 2)], [v_width, v_depth, v_border]], [[0, Sem.mul(Sem.neg(v_depth), 0.12), Sem.sub(v_height, Sem.div(v_border, 2))], [v_width, v_depth, v_border]]]
	gen__boxes(Sem.add(v_name, "_GoldFrame"), v_frame, v_mats["gold"], v_root, Sem.mul(v_border, 0.13))
	var tmp_132 = [Sem.sub(v_width, Sem.mul(2, v_border)), Sem.sub(v_height, Sem.mul(2, v_border))]
	v_inner_w = tmp_132[0]
	v_inner_h = tmp_132[1]
	var tmp_133 = [Sem.div(v_inner_w, 2), v_border, Sem.sub(v_height, v_border)]
	v_a = tmp_133[0]
	v_low = tmp_133[1]
	v_high = tmp_133[2]
	gen__art_polygon(Sem.add(v_name, "_Sky"), [[Sem.neg(v_a), v_low], [v_a, v_low], [v_a, v_high], [Sem.neg(v_a), v_high]], Sem.mul(Sem.neg(v_depth), 0.08), v_mats["cream"], v_root)
	var tmp_134 = [Sem.mul(v_inner_w, 0.25), Sem.add(v_low, Sem.mul(v_inner_h, 0.75)), Sem.mul(v_inner_h, 0.09)]
	v_sun_x = tmp_134[0]
	v_sun_z = tmp_134[1]
	v_sr = tmp_134[2]
	v_sun = Sem.map_array(range(12), func(tmp_135): var tmp_136 = tmp_135; return [Sem.add(v_sun_x, Sem.mul(v_sr, cos(Sem.div(Sem.mul(Sem.mul(2, PI), tmp_136), 12)))), Sem.add(v_sun_z, Sem.mul(v_sr, sin(Sem.div(Sem.mul(Sem.mul(2, PI), tmp_136), 12))))])
	gen__art_polygon(Sem.add(v_name, "_Sun"), v_sun, Sem.sub(Sem.mul(Sem.neg(v_depth), 0.08), 0.0015), v_mats["wood_light"], v_root)
	v_mountains = [[Sem.neg(v_a), v_low], [v_a, v_low], [v_a, Sem.add(v_low, Sem.mul(v_inner_h, 0.38))], [Sem.mul(v_inner_w, 0.29), Sem.add(v_low, Sem.mul(v_inner_h, 0.53))], [Sem.mul(v_inner_w, 0.12), Sem.add(v_low, Sem.mul(v_inner_h, 0.43))], [Sem.mul(Sem.neg(v_inner_w), 0.1), Sem.add(v_low, Sem.mul(v_inner_h, 0.63))], [Sem.mul(Sem.neg(v_inner_w), 0.31), Sem.add(v_low, Sem.mul(v_inner_h, 0.38))], [Sem.neg(v_a), Sem.add(v_low, Sem.mul(v_inner_h, 0.48))]]
	gen__art_polygon(Sem.add(v_name, "_DistantHills"), v_mountains, Sem.sub(Sem.mul(Sem.neg(v_depth), 0.08), 0.003), v_mats["grout"], v_root)
	if Sem.truth(((v_style == "city"))):
		for tmp_137 in range(7):
			v_i = tmp_137
			v_x0 = Sem.add(Sem.neg(v_a), Sem.div(Sem.mul(v_i, v_inner_w), 7))
			v_bw = Sem.mul(Sem.div(v_inner_w, 7), 1.01)
			v_bh = Sem.mul(v_inner_h, v_rng.uniform(0.22, 0.43))
			v_polygon = [[v_x0, v_low], [Sem.add(v_x0, v_bw), v_low], [Sem.add(v_x0, v_bw), Sem.add(v_low, v_bh)], [Sem.add(v_x0, Sem.mul(v_bw, 0.5)), Sem.add(Sem.add(v_low, v_bh), Sem.mul(v_inner_h, 0.08))], [v_x0, Sem.add(v_low, v_bh)]]
			gen__art_polygon(Sem.add(v_name, Sem.mod("_House_%d", v_i)), v_polygon, Sem.sub(Sem.sub(Sem.mul(Sem.neg(v_depth), 0.08), 0.005), Sem.mul(v_i, 0.00012)), v_mats["stone_dark"], v_root)
		var tmp_138 = [Sem.mul(v_inner_w, 0.06), Sem.mul(v_inner_w, 0.15)]
		v_tower_x = tmp_138[0]
		v_tower_w = tmp_138[1]
		v_tower = [[Sem.sub(v_tower_x, Sem.div(v_tower_w, 2)), v_low], [Sem.add(v_tower_x, Sem.div(v_tower_w, 2)), v_low], [Sem.add(v_tower_x, Sem.div(v_tower_w, 2)), Sem.add(v_low, Sem.mul(v_inner_h, 0.6))], [Sem.add(v_tower_x, Sem.mul(v_tower_w, 0.32)), Sem.add(v_low, Sem.mul(v_inner_h, 0.6))], [Sem.add(v_tower_x, Sem.mul(v_tower_w, 0.27)), Sem.add(v_low, Sem.mul(v_inner_h, 0.77))], [v_tower_x, Sem.add(v_low, Sem.mul(v_inner_h, 0.91))], [Sem.sub(v_tower_x, Sem.mul(v_tower_w, 0.27)), Sem.add(v_low, Sem.mul(v_inner_h, 0.77))], [Sem.sub(v_tower_x, Sem.mul(v_tower_w, 0.32)), Sem.add(v_low, Sem.mul(v_inner_h, 0.6))], [Sem.sub(v_tower_x, Sem.div(v_tower_w, 2)), Sem.add(v_low, Sem.mul(v_inner_h, 0.6))]]
		gen__art_polygon(Sem.add(v_name, "_Tower"), v_tower, Sem.sub(Sem.mul(Sem.neg(v_depth), 0.08), 0.007), v_mats["wood_dark"], v_root)
		v_fore = [[Sem.neg(v_a), v_low], [v_a, v_low], [v_a, Sem.add(v_low, Sem.mul(v_inner_h, 0.12))], [Sem.mul(v_inner_w, 0.2), Sem.add(v_low, Sem.mul(v_inner_h, 0.17))], [Sem.mul(Sem.neg(v_inner_w), 0.18), Sem.add(v_low, Sem.mul(v_inner_h, 0.12))], [Sem.neg(v_a), Sem.add(v_low, Sem.mul(v_inner_h, 0.2))]]
		gen__art_polygon(Sem.add(v_name, "_Foreground"), v_fore, Sem.sub(Sem.mul(Sem.neg(v_depth), 0.08), 0.009), v_mats["wood_dark"], v_root)
	else:
		v_near = [[Sem.neg(v_a), v_low], [v_a, v_low], [v_a, Sem.add(v_low, Sem.mul(v_inner_h, 0.25))], [Sem.mul(v_inner_w, 0.33), Sem.add(v_low, Sem.mul(v_inner_h, 0.35))], [Sem.mul(v_inner_w, 0.1), Sem.add(v_low, Sem.mul(v_inner_h, 0.24))], [Sem.mul(Sem.neg(v_inner_w), 0.15), Sem.add(v_low, Sem.mul(v_inner_h, 0.42))], [Sem.neg(v_a), Sem.add(v_low, Sem.mul(v_inner_h, 0.21))]]
		gen__art_polygon(Sem.add(v_name, "_NearHills"), v_near, Sem.sub(Sem.mul(Sem.neg(v_depth), 0.08), 0.006), v_mats["green"], v_root)
		for tmp_139 in Sem.py_enumerate([Sem.mul(Sem.neg(v_inner_w), 0.34), Sem.mul(Sem.neg(v_inner_w), 0.24), Sem.mul(v_inner_w, 0.34)]):
			var tmp_140 = tmp_139
			v_i = tmp_140[0]
			v_x = tmp_140[1]
			v_tree_h = Sem.mul(v_inner_h, (0.35 if Sem.truth(((v_i == 0))) else 0.26))
			v_tree_w = Sem.mul(v_inner_w, 0.13)
			v_z = Sem.add(v_low, Sem.mul(v_inner_h, 0.09))
			v_polygon = [[Sem.sub(v_x, Sem.mul(v_tree_w, 0.13)), v_z], [Sem.add(v_x, Sem.mul(v_tree_w, 0.13)), v_z], [Sem.add(v_x, Sem.mul(v_tree_w, 0.13)), Sem.add(v_z, Sem.mul(v_tree_h, 0.23))], [Sem.add(v_x, Sem.mul(v_tree_w, 0.5)), Sem.add(v_z, Sem.mul(v_tree_h, 0.23))], [Sem.add(v_x, Sem.mul(v_tree_w, 0.32)), Sem.add(v_z, Sem.mul(v_tree_h, 0.52))], [Sem.add(v_x, Sem.mul(v_tree_w, 0.42)), Sem.add(v_z, Sem.mul(v_tree_h, 0.52))], [v_x, Sem.add(v_z, v_tree_h)], [Sem.sub(v_x, Sem.mul(v_tree_w, 0.42)), Sem.add(v_z, Sem.mul(v_tree_h, 0.52))], [Sem.sub(v_x, Sem.mul(v_tree_w, 0.32)), Sem.add(v_z, Sem.mul(v_tree_h, 0.52))], [Sem.sub(v_x, Sem.mul(v_tree_w, 0.5)), Sem.add(v_z, Sem.mul(v_tree_h, 0.23))], [Sem.sub(v_x, Sem.mul(v_tree_w, 0.13)), Sem.add(v_z, Sem.mul(v_tree_h, 0.23))]]
			gen__art_polygon(Sem.add(v_name, Sem.mod("_Tree_%d", v_i)), v_polygon, Sem.sub(Sem.sub(Sem.mul(Sem.neg(v_depth), 0.08), 0.008), Sem.mul(v_i, 0.0003)), v_mats["wood_dark"], v_root)
	return v_root

static func gen_ladder(v_name, v_mats, v_width = 0.46, v_depth = 0.3, v_height = 2.2, v_rungs = 7, v_parent = null):
	var v_bottom_y = null
	var v_i = null
	var v_rail = null
	var v_root = null
	var v_side = null
	var v_t = null
	var v_top_y = null
	var v_x = null
	var v_y = null
	var v_z = null
	v_root = gen__root(v_name, "ladder", v_parent, {"width": v_width, "depth": v_depth, "height": v_height})
	v_rail = Sem.py_min(Sem.mul(v_width, 0.105), 0.06)
	var tmp_141 = [Sem.mul(Sem.neg(v_depth), 0.43), Sem.mul(v_depth, 0.43)]
	v_bottom_y = tmp_141[0]
	v_top_y = tmp_141[1]
	for tmp_142 in [Sem.neg(1), 1]:
		v_side = tmp_142
		v_x = Sem.mul(v_side, Sem.sub(Sem.div(v_width, 2), Sem.div(v_rail, 2)))
		Geo.gen_beam(Sem.add(v_name, Sem.mod("_Rail_%d", v_side)), [v_x, v_bottom_y, Sem.mul(v_rail, 0.45)], [v_x, v_top_y, Sem.sub(v_height, Sem.mul(v_rail, 0.45))], v_rail, v_rail, v_mats["wood"], v_root, 0.006)
		Geo.gen_box(Sem.add(v_name, Sem.mod("_Shoe_%d", v_side)), [v_x, v_bottom_y, Sem.mul(v_rail, 0.38)], [Sem.mul(v_rail, 1.2), Sem.mul(v_rail, 1.6), Sem.mul(v_rail, 0.76)], v_mats["gold"], 0.003, v_root)
	v_rungs = Sem.py_max(2, int(v_rungs))
	for tmp_143 in range(v_rungs):
		v_i = tmp_143
		v_t = Sem.add(0.1, Sem.div(Sem.mul(0.78, v_i), Sem.sub(v_rungs, 1)))
		var tmp_144 = [Sem.add(v_bottom_y, Sem.mul(Sem.sub(v_top_y, v_bottom_y), v_t)), Sem.mul(v_height, v_t)]
		v_y = tmp_144[0]
		v_z = tmp_144[1]
		Geo.gen_box(Sem.add(v_name, Sem.mod("_Rung_%02d", v_i)), [0, v_y, v_z], [Sem.sub(v_width, v_rail), Sem.mul(v_rail, 1.5), Sem.mul(v_rail, 0.68)], v_mats["wood_light"], 0.004, v_root)
	return v_root

