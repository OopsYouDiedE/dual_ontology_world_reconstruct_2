@tool
extends RefCounted

# Direct port of kit/architecture.py. Z-up recipe coordinates convert at the geometry boundary.
const Sem = preload("res://tools/building_construction/BuildingConstruction/Shared/RecipeSemantics.gd")
const Geo = preload("res://tools/building_construction/BuildingConstruction/Shared/RecipeGeometry.gd")
const EPS = 1e-9

static func gen__opening(v_spec, v_length, v_wall_height):
	var v_count = null
	var v_i = null
	var v_o = null
	v_o = Sem.py_dict(v_spec)
	v_o["width"] = float(v_o["width"])
	v_o["height"] = float(v_o["height"])
	v_o["bottom"] = float(v_o.get("bottom", 0))
	v_o["center"] = float(v_o["center"])
	v_o["shape"] = v_o.get("shape", "rect")
	if Sem.truth(((v_o["shape"] not in ["rect", "arch"]))):
		push_error(str("Opening shape must be rect or arch"))
		return null
	if Sem.truth(Sem.either_lazy(((Sem.py_min(v_o["width"], v_o["height"]) <= 0)), func(): return ((v_o["bottom"] < Sem.neg(EPS))))):
		push_error(str("Opening dimensions must be positive and above wall base"))
		return null
	if Sem.truth(Sem.either_lazy(((Sem.sub(v_o["center"], Sem.div(v_o["width"], 2)) < Sem.neg(EPS))), func(): return ((Sem.add(v_o["center"], Sem.div(v_o["width"], 2)) > Sem.add(v_length, EPS))))):
		push_error(str("Opening lies outside its wall segment"))
		return null
	if Sem.truth(((Sem.add(v_o["bottom"], v_o["height"]) > Sem.add(v_wall_height, EPS)))):
		push_error(str("Opening is taller than its wall"))
		return null
	if Sem.truth(((v_o["shape"] == "arch"))):
		v_o["rise"] = float((v_o.get("rise") if Sem.truth(((v_o.get("rise") != null))) else Sem.div(v_o["width"], 2)))
		if Sem.truth(not Sem.truth(((0 < v_o["rise"]) and (v_o["rise"] <= v_o["height"])))):
			push_error(str("Arch rise must be positive and at most its opening height"))
			return null
		v_count = Sem.py_max(4, int(v_o.get("segments", 10)))
		v_o["_roof"] = Sem.map_array(range(Sem.add(v_count, 1)), func(tmp_1): var tmp_2 = tmp_1; return [Sem.add(v_o["center"], Sem.mul(Sem.div(v_o["width"], 2), cos(Sem.mul(PI, Sem.sub(1, Sem.div(tmp_2, v_count)))))), Sem.add(Sem.sub(Sem.add(v_o["bottom"], v_o["height"]), v_o["rise"]), Sem.mul(v_o["rise"], sin(Sem.mul(PI, Sem.sub(1, Sem.div(tmp_2, v_count))))))])
	else:
		v_o["_roof"] = [[Sem.sub(v_o["center"], Sem.div(v_o["width"], 2)), Sem.add(v_o["bottom"], v_o["height"])], [Sem.add(v_o["center"], Sem.div(v_o["width"], 2)), Sem.add(v_o["bottom"], v_o["height"])]]
	return v_o

static func gen__roof(v_o, v_x):
	var v_a = null
	var v_b = null
	var v_index = null
	var v_p = null
	var v_points = null
	var v_t = null
	v_points = v_o["_roof"]
	v_index = Sem.py_min(Sem.sub(Sem.py_len(v_points), 2), Sem.py_max(0, Sem.sub(Sem.bisect_right(Sem.map_array(v_points, func(tmp_3): var tmp_4 = tmp_3; return tmp_4[0]), v_x), 1)))
	var tmp_5 = Sem.slice_array(v_points, v_index, Sem.add(v_index, 2), null)
	v_a = tmp_5[0]
	v_b = tmp_5[1]
	v_t = Sem.py_max(0.0, Sem.py_min(1.0, Sem.div(Sem.sub(v_x, v_a[0]), Sem.sub(v_b[0], v_a[0]))))
	return Sem.add(v_a[1], Sem.mul(v_t, Sem.sub(v_b[1], v_a[1])))

static func gen__wall_shell(v_name, v_length, v_height, v_thickness, v_openings, v_mat, v_parent, v_base_slope = 0):
	var v__ = null
	var v_a = null
	var v_area = null
	var v_b = null
	var v_bottom = null
	var v_boundary = null
	var v_center = null
	var v_clean = null
	var v_count = null
	var v_cursor0 = null
	var v_cursor1 = null
	var v_edge = null
	var v_edge_counts = null
	var v_edge_directions = null
	var v_face = null
	var v_faces = null
	var v_front_faces = null
	var v_gaps = null
	var v_hi0 = null
	var v_hi1 = null
	var v_holes = null
	var v_i = null
	var v_ids = null
	var v_index_map = null
	var v_key = null
	var v_levels = null
	var v_lo0 = null
	var v_lo1 = null
	var v_o = null
	var v_p = null
	var v_strips = null
	var v_top0 = null
	var v_top1 = null
	var v_uses = null
	var v_vertex = null
	var v_vertices = null
	var v_x = null
	var v_x0 = null
	var v_x1 = null
	var v_xm = null
	var v_xs = null
	var v_z = null
	v_xs = Sem.py_sorted(Sem.py_set(Sem.add([0.0, v_length], Sem.flat_map(v_openings, func(tmp_6): var tmp_7 = tmp_6; return Sem.map_array(tmp_7["_roof"], func(tmp_8): var tmp_9 = tmp_8; return Sem.py_round(tmp_9[0], 10))))), null, false)
	v_strips = []
	v_levels = {}
	for tmp_10 in Sem.py_zip(v_xs, Sem.slice_array(v_xs, 1, null, null)):
		var tmp_11 = tmp_10
		v_x0 = tmp_11[0]
		v_x1 = tmp_11[1]
		if Sem.truth(((Sem.sub(v_x1, v_x0) < EPS))):
			continue
		v_xm = Sem.div(Sem.add(v_x0, v_x1), 2)
		v_holes = Sem.py_sorted(Sem.flat_map(v_openings, func(tmp_12): var tmp_13 = tmp_12; return ([tmp_13] if Sem.truth(((tmp_13["_roof"][0][0] < v_xm) and (v_xm < tmp_13["_roof"][Sem.neg(1)][0]))) else [])), func(v_o): return v_o["bottom"], false)
		var tmp_14 = 0.0
		v_cursor0 = tmp_14
		v_cursor1 = tmp_14
		v_gaps = []
		for tmp_15 in v_holes:
			v_o = tmp_15
			v_bottom = v_o["bottom"]
			var tmp_16 = [gen__roof(v_o, v_x0), gen__roof(v_o, v_x1)]
			v_top0 = tmp_16[0]
			v_top1 = tmp_16[1]
			if Sem.truth(((v_bottom < Sem.sub(Sem.py_max(v_cursor0, v_cursor1), EPS)))):
				push_error(str(Sem.add("Overlapping wall openings need separate valid intervals: ", v_name)))
				return null
			if Sem.truth(((v_bottom > Sem.add(Sem.py_min(v_cursor0, v_cursor1), EPS)))):
				v_gaps.append([v_cursor0, v_cursor1, v_bottom, v_bottom])
			var tmp_17 = [v_top0, v_top1]
			v_cursor0 = tmp_17[0]
			v_cursor1 = tmp_17[1]
		if Sem.truth(((v_height > Sem.add(Sem.py_min(v_cursor0, v_cursor1), EPS)))):
			v_gaps.append([v_cursor0, v_cursor1, v_height, v_height])
		for tmp_18 in v_gaps:
			var tmp_19 = tmp_18
			v_lo0 = tmp_19[0]
			v_lo1 = tmp_19[1]
			v_hi0 = tmp_19[2]
			v_hi1 = tmp_19[3]
			v_levels[v_x0] = Sem.py_set(v_levels.get(v_x0, []) + [v_lo0, v_hi0])
			v_levels[v_x1] = Sem.py_set(v_levels.get(v_x1, []) + [v_lo1, v_hi1])
		v_strips.append([v_x0, v_x1, v_gaps])
	var tmp_20 = [[], [], {}]
	v_vertices = tmp_20[0]
	v_front_faces = tmp_20[1]
	v_index_map = tmp_20[2]
	v_vertex = func(tmp_21, tmp_22):
		v_key = [Sem.py_round(tmp_21, 8), Sem.py_round(tmp_22, 8)]
		if Sem.truth(((v_key not in v_index_map))):
			v_index_map[v_key] = Sem.py_len(v_vertices)
			v_vertices.append([tmp_21, Sem.div(Sem.neg(v_thickness), 2), Sem.add(tmp_22, Sem.mul(v_base_slope, tmp_21))])
		return v_index_map[v_key]
	for tmp_23 in v_strips:
		var tmp_24 = tmp_23
		v_x0 = tmp_24[0]
		v_x1 = tmp_24[1]
		v_gaps = tmp_24[2]
		for tmp_25 in v_gaps:
			var tmp_26 = tmp_25
			v_lo0 = tmp_26[0]
			v_lo1 = tmp_26[1]
			v_hi0 = tmp_26[2]
			v_hi1 = tmp_26[3]
			v_boundary = [[v_x0, v_lo0], [v_x1, v_lo1]]
			v_boundary = Sem.add(v_boundary, Sem.flat_map(Sem.py_sorted(v_levels[v_x1], null, false), func(tmp_27): var tmp_28 = tmp_27; return ([[v_x1, tmp_28]] if Sem.truth(((Sem.add(v_lo1, EPS) < tmp_28) and (tmp_28 < Sem.sub(v_hi1, EPS)))) else [])))
			v_boundary = Sem.add(v_boundary, [[v_x1, v_hi1], [v_x0, v_hi0]])
			v_boundary = Sem.add(v_boundary, Sem.flat_map(Sem.py_sorted(v_levels[v_x0], null, true), func(tmp_29): var tmp_30 = tmp_29; return ([[v_x0, tmp_30]] if Sem.truth(((Sem.add(v_lo0, EPS) < tmp_30) and (tmp_30 < Sem.sub(v_hi0, EPS)))) else [])))
			v_clean = []
			for tmp_31 in v_boundary:
				v_p = tmp_31
				if Sem.truth(Sem.either_lazy(not Sem.truth(v_clean), func(): return ((Sem.dist(v_p, v_clean[Sem.neg(1)]) > EPS)))):
					v_clean.append(v_p)
			if Sem.truth(Sem.both_lazy(((Sem.py_len(v_clean) > 1)), func(): return ((Sem.dist(v_clean[0], v_clean[Sem.neg(1)]) < EPS)))):
				v_clean.pop_back()
			if Sem.truth(((Sem.py_len(v_clean) < 3))):
				continue
			v_center = v_vertex.call(Sem.div(Sem.add(v_x0, v_x1), 2), Sem.div(Sem.add(Sem.add(Sem.add(v_lo0, v_lo1), v_hi0), v_hi1), 4))
			v_ids = Sem.map_array(v_clean, func(tmp_32): var tmp_33 = tmp_32; return v_vertex.callv(tmp_33))
			for tmp_34 in range(Sem.py_len(v_ids)):
				v_i = tmp_34
				var tmp_35 = [v_clean[v_i], v_clean[Sem.mod(Sem.add(v_i, 1), Sem.py_len(v_ids))]]
				v_a = tmp_35[0]
				v_b = tmp_35[1]
				v_area = Sem.sub(Sem.mul(Sem.sub(v_a[0], v_vertices[v_center][0]), Sem.sub(v_b[1], Sem.div(Sem.add(Sem.add(Sem.add(v_lo0, v_lo1), v_hi0), v_hi1), 4))), Sem.mul(Sem.sub(v_b[0], v_vertices[v_center][0]), Sem.sub(v_a[1], Sem.div(Sem.add(Sem.add(Sem.add(v_lo0, v_lo1), v_hi0), v_hi1), 4))))
				if Sem.truth(((abs(v_area) > EPS))):
					v_front_faces.append([v_center, v_ids[v_i], v_ids[Sem.mod(Sem.add(v_i, 1), Sem.py_len(v_ids))]])
	if Sem.truth(not Sem.truth(v_front_faces)):
		push_error(str(Sem.add("Wall has no remaining solid area: ", v_name)))
		return null
	v_edge_counts = {}
	v_edge_directions = {}
	for tmp_36 in v_front_faces:
		v_face = tmp_36
		for tmp_37 in Sem.py_zip(v_face, Sem.add(Sem.slice_array(v_face, 1, null, null), Sem.slice_array(v_face, null, 1, null))):
			var tmp_38 = tmp_37
			v_a = tmp_38[0]
			v_b = tmp_38[1]
			v_key = Sem.py_tuple(Sem.py_sorted([v_a, v_b], null, false))
			v_edge_counts[v_key] = Sem.add(v_edge_counts.get(v_key, 0), 1)
			v_edge_directions[v_key] = [v_a, v_b]
	v_count = Sem.py_len(v_vertices)
	v_vertices = Sem.add(v_vertices, Sem.map_array(v_vertices, func(tmp_39): var tmp_40 = tmp_39[0]; var tmp_41 = tmp_39[1]; var tmp_42 = tmp_39[2]; return [tmp_40, Sem.div(v_thickness, 2), tmp_42]))
	v_faces = Sem.add(Sem.py_list(v_front_faces), Sem.map_array(v_front_faces, func(tmp_43): var tmp_44 = tmp_43; return Sem.py_tuple(Sem.map_array(Sem.py_reversed(tmp_44), func(tmp_45): var tmp_46 = tmp_45; return Sem.add(tmp_46, v_count)))))
	for tmp_47 in Sem.items(v_edge_counts):
		var tmp_48 = tmp_47
		v_edge = tmp_48[0]
		v_uses = tmp_48[1]
		if Sem.truth(((v_uses == 1))):
			var tmp_49 = v_edge_directions[v_edge]
			v_a = tmp_49[0]
			v_b = tmp_49[1]
			v_faces.append([v_a, Sem.add(v_a, v_count), Sem.add(v_b, v_count), v_b])
		else:
			if Sem.truth(((v_uses != 2))):
				push_error(str(Sem.add("Invalid wall surface adjacency: ", v_name)))
				return null
	return Geo.gen_mesh(v_name, v_vertices, v_faces, v_mat, v_parent, 0)

static func gen__free_spans(v_length, v_openings, v_low, v_high, v_pad = 0.065):
	var v_a = null
	var v_b = null
	var v_bottom = null
	var v_cursor = null
	var v_cuts = null
	var v_half = null
	var v_o = null
	var v_q = null
	var v_spans = null
	var v_spring = null
	var v_top = null
	v_cuts = []
	for tmp_50 in v_openings:
		v_o = tmp_50
		var tmp_51 = [v_o["bottom"], Sem.add(v_o["bottom"], v_o["height"])]
		v_bottom = tmp_51[0]
		v_top = tmp_51[1]
		if Sem.truth(Sem.either_lazy(((v_high <= v_bottom)), func(): return ((v_low >= v_top)))):
			continue
		v_half = Sem.div(v_o["width"], 2)
		if Sem.truth(((v_o["shape"] == "arch"))):
			v_spring = Sem.sub(v_top, v_o["rise"])
			if Sem.truth(((v_low > v_spring))):
				v_q = Sem.py_min(1.0, Sem.div(Sem.sub(v_low, v_spring), v_o["rise"]))
				v_half = Sem.mul(v_half, sqrt(Sem.py_max(0.0, Sem.sub(1, Sem.mul(v_q, v_q)))))
		v_cuts.append([Sem.py_max(0.0, Sem.sub(Sem.sub(v_o["center"], v_half), v_pad)), Sem.py_min(v_length, Sem.add(Sem.add(v_o["center"], v_half), v_pad))])
	var tmp_52 = [0.0, []]
	v_cursor = tmp_52[0]
	v_spans = tmp_52[1]
	for tmp_53 in Sem.py_sorted(v_cuts, null, false):
		var tmp_54 = tmp_53
		v_a = tmp_54[0]
		v_b = tmp_54[1]
		if Sem.truth(((v_a > Sem.add(v_cursor, EPS)))):
			v_spans.append([v_cursor, v_a])
		v_cursor = Sem.py_max(v_cursor, v_b)
	if Sem.truth(((v_cursor < Sem.sub(v_length, EPS)))):
		v_spans.append([v_cursor, v_length])
	return v_spans

static func gen__rail_band(v_name, v_length, v_z, v_band_height, v_depth, v_thickness, v_openings, v_mat, v_parent):
	var v_a = null
	var v_b = null
	var v_j = null
	for tmp_55 in Sem.py_enumerate(gen__free_spans(v_length, v_openings, Sem.sub(v_z, Sem.div(v_band_height, 2)), Sem.add(v_z, Sem.div(v_band_height, 2)), 0.065)):
		var tmp_56 = tmp_55
		v_j = tmp_56[0]
		var tmp_57 = tmp_56[1]
		v_a = tmp_57[0]
		v_b = tmp_57[1]
		if Sem.truth(((Sem.sub(v_b, v_a) > 0.025))):
			Geo.gen_box(Sem.add(Sem.add(v_name, "_"), str(v_j)), [Sem.div(Sem.add(v_a, v_b), 2), Sem.add(Sem.sub(Sem.div(Sem.neg(v_thickness), 2), Sem.div(v_depth, 2)), 0.002), v_z], [Sem.sub(v_b, v_a), v_depth, v_band_height], v_mat, 0.006, v_parent)

static func gen__panels(v_name, v_length, v_bottom, v_top, v_thickness, v_openings, v_mats, v_parent, v_target = 1.0):
	var v_a = null
	var v_b = null
	var v_border = null
	var v_center = null
	var v_face_y = null
	var v_gap = null
	var v_height = null
	var v_j = null
	var v_n = null
	var v_prefix = null
	var v_side = null
	var v_span = null
	var v_span_index = null
	var v_width = null
	v_height = Sem.sub(v_top, v_bottom)
	if Sem.truth(((v_height < 0.18))):
		return null
	for tmp_58 in Sem.py_enumerate(gen__free_spans(v_length, v_openings, v_bottom, v_top, 0.12)):
		var tmp_59 = tmp_58
		v_span_index = tmp_59[0]
		var tmp_60 = tmp_59[1]
		v_a = tmp_60[0]
		v_b = tmp_60[1]
		v_span = Sem.sub(Sem.sub(v_b, v_a), 0.09)
		if Sem.truth(((v_span < 0.2))):
			continue
		v_n = Sem.py_max(1, Sem.py_round(Sem.div(v_span, v_target)))
		var tmp_61 = [0.055, 0.035]
		v_gap = tmp_61[0]
		v_border = tmp_61[1]
		v_width = Sem.div(Sem.sub(v_span, Sem.mul(Sem.sub(v_n, 1), v_gap)), v_n)
		for tmp_62 in range(v_n):
			v_j = tmp_62
			v_center = Sem.add(Sem.add(Sem.add(v_a, 0.045), Sem.mul(v_j, Sem.add(v_width, v_gap))), Sem.div(v_width, 2))
			v_prefix = Sem.add(v_name, Sem.mod("_%d_%d", [v_span_index, v_j]))
			v_face_y = Sem.sub(Sem.div(Sem.neg(v_thickness), 2), 0.014)
			Geo.gen_box(Sem.add(v_prefix, "_Recess"), [v_center, v_face_y, Sem.div(Sem.add(v_bottom, v_top), 2)], [v_width, 0.026, v_height], v_mats["wood_dark"], 0.006, v_parent)
			for tmp_63 in [Sem.neg(1), 1]:
				v_side = tmp_63
				Geo.gen_box(Sem.add(Sem.add(v_prefix, "_Stile_"), str(v_side)), [Sem.add(v_center, Sem.div(Sem.mul(v_side, Sem.sub(v_width, v_border)), 2)), Sem.sub(v_face_y, 0.022), Sem.div(Sem.add(v_bottom, v_top), 2)], [v_border, 0.036, v_height], v_mats["wood_light"], 0.005, v_parent)
				Geo.gen_box(Sem.add(Sem.add(v_prefix, "_Rail_"), str(v_side)), [v_center, Sem.sub(v_face_y, 0.022), Sem.add(Sem.div(Sem.add(v_bottom, v_top), 2), Sem.div(Sem.mul(v_side, Sem.sub(v_height, v_border)), 2))], [v_width, 0.036, v_border], v_mats["wood_light"], 0.005, v_parent)
			if Sem.truth(Sem.both_lazy(((v_width > 0.48)), func(): return ((v_height > 0.48)))):
				Geo.gen_box(Sem.add(v_prefix, "_Field"), [v_center, Sem.sub(v_face_y, 0.004), Sem.div(Sem.add(v_bottom, v_top), 2)], [Sem.sub(v_width, 0.12), 0.025, Sem.sub(v_height, 0.12)], v_mats["wood"], 0.01, v_parent)

static func gen_wall_path(v_name, v_points, v_height, v_thickness, v_mats, v_openings = [], v_panel_height = 1.05, v_parent = null):
	var v_a = null
	var v_a1 = null
	var v_a2 = null
	var v_after = null
	var v_anchors = null
	var v_angle = null
	var v_b = null
	var v_before = null
	var v_closed = null
	var v_depth = null
	var v_direction = null
	var v_dx = null
	var v_dy = null
	var v_dz = null
	var v_following = null
	var v_h = null
	var v_i = null
	var v_j = null
	var v_layer = null
	var v_length = null
	var v_local_x = null
	var v_mat = null
	var v_o = null
	var v_opening = null
	var v_ops = null
	var v_p = null
	var v_pillar = null
	var v_pillar_points = null
	var v_previous = null
	var v_pts = null
	var v_root = null
	var v_segment = null
	var v_turn = null
	var v_v = null
	var v_y = null
	var v_z = null
	v_pts = (load("res://tools/building_construction/BuildingConstruction/Shared/PathRecipes.gd").gen_sample_path(v_points, 12, false) if Sem.truth(Sem.py_any(Sem.map_array(v_points, func(tmp_64): var tmp_65 = tmp_64; return (tmp_65 is Dictionary)))) else load("res://tools/building_construction/BuildingConstruction/Shared/PathRecipes.gd").gen_clean_polyline(v_points, false))
	var tmp_66 = [float(v_height), float(v_thickness)]
	v_height = tmp_66[0]
	v_thickness = tmp_66[1]
	if Sem.truth(Sem.either_lazy(not Sem.truth(Sem.py_all(Sem.map_array([v_height, v_thickness], func(tmp_67): var tmp_68 = tmp_67; return is_finite(tmp_68)))), func(): return ((Sem.py_min(v_height, v_thickness) <= 0)))):
		push_error(str("Wall height and thickness must be positive"))
		return null
	for tmp_69 in v_openings:
		v_opening = tmp_69
		if Sem.truth(not Sem.truth(((0 <= int(v_opening.get("segment", 0))) and (int(v_opening.get("segment", 0)) < Sem.sub(Sem.py_len(v_pts), 1))))):
			push_error(str("Opening refers to an absent wall segment"))
			return null
	v_root = Geo.gen_group(v_name, [0, 0, 0], 0, v_parent)
	v_root["generator"] = "wall_path_v1"
	v_root["path_nodes"] = JSON.stringify(v_pts)
	v_anchors = []
	for tmp_70 in Sem.py_enumerate(Sem.py_zip(v_pts, Sem.slice_array(v_pts, 1, null, null))):
		var tmp_71 = tmp_70
		v_i = tmp_71[0]
		var tmp_72 = tmp_71[1]
		v_a = tmp_72[0]
		v_b = tmp_72[1]
		var tmp_75 = Sem.map_array(range(3), func(tmp_73): var tmp_74 = tmp_73; return Sem.sub(v_b[tmp_74], v_a[tmp_74]))
		v_dx = tmp_75[0]
		v_dy = tmp_75[1]
		v_dz = tmp_75[2]
		v_length = Sem.hypot(v_dx, v_dy)
		if Sem.truth(((v_length < EPS))):
			push_error(str("Wall segments cannot be vertical"))
			return null
		v_angle = atan2(v_dy, v_dx)
		v_segment = Geo.gen_group(Sem.add(v_name, Sem.mod("_Segment_%02d", v_i)), v_a, v_angle, v_root)
		v_ops = Sem.flat_map(v_openings, func(tmp_76): var tmp_77 = tmp_76; return ([gen__opening(tmp_77, v_length, v_height)] if Sem.truth(((int(tmp_77.get("segment", 0)) == v_i))) else []))
		gen__wall_shell(Sem.add(v_name, Sem.mod("_Solid_%02d", v_i)), v_length, v_height, v_thickness, v_ops, v_mats["wood"], v_segment, Sem.div(v_dz, v_length))
		if Sem.truth(((abs(v_dz) < EPS))):
			gen__rail_band(Sem.add(v_name, Sem.mod("_Skirting_%02d", v_i)), v_length, 0.085, 0.17, 0.085, v_thickness, v_ops, v_mats["wood_dark"], v_segment)
			gen__rail_band(Sem.add(v_name, Sem.mod("_SkirtingBead_%02d", v_i)), v_length, 0.18, 0.035, 0.1, v_thickness, v_ops, v_mats["wood_light"], v_segment)
			gen__rail_band(Sem.add(v_name, Sem.mod("_Dado_%02d", v_i)), v_length, v_panel_height, 0.09, 0.12, v_thickness, v_ops, v_mats["wood"], v_segment)
			gen__rail_band(Sem.add(v_name, Sem.mod("_DadoHighlight_%02d", v_i)), v_length, Sem.add(v_panel_height, 0.055), 0.025, 0.145, v_thickness, v_ops, v_mats["wood_light"], v_segment)
			gen__panels(Sem.add(v_name, Sem.mod("_LowerPanel_%02d", v_i)), v_length, 0.235, Sem.sub(v_panel_height, 0.11), v_thickness, v_ops, v_mats, v_segment, 1.0)
			gen__panels(Sem.add(v_name, Sem.mod("_UpperPanel_%02d", v_i)), v_length, Sem.add(v_panel_height, 0.16), Sem.sub(v_height, 0.35), v_thickness, v_ops, v_mats, v_segment, 1.25)
			for tmp_78 in Sem.py_enumerate([[Sem.sub(v_height, 0.25), 0.055, 0.1, v_mats["wood_light"]], [Sem.sub(v_height, 0.16), 0.12, 0.145, v_mats["wood"]], [Sem.sub(v_height, 0.065), 0.075, 0.205, v_mats["wood_light"]], [Sem.sub(v_height, 0.012), 0.04, 0.245, v_mats["wood"]]]):
				var tmp_79 = tmp_78
				v_layer = tmp_79[0]
				var tmp_80 = tmp_79[1]
				v_z = tmp_80[0]
				v_h = tmp_80[1]
				v_depth = tmp_80[2]
				v_mat = tmp_80[3]
				gen__rail_band(Sem.add(v_name, Sem.mod("_Cornice_%02d_%d", [v_i, v_layer])), v_length, v_z, v_h, v_depth, v_thickness, v_ops, v_mat, v_segment)
		for tmp_81 in Sem.py_enumerate(v_ops):
			var tmp_82 = tmp_81
			v_j = tmp_82[0]
			v_o = tmp_82[1]
			v_local_x = v_o["center"]
			v_anchors.append({"segment": v_i, "opening": v_j, "location": [Sem.add(v_a[0], Sem.div(Sem.mul(v_local_x, v_dx), v_length)), Sem.add(v_a[1], Sem.div(Sem.mul(v_local_x, v_dy), v_length)), Sem.add(Sem.add(v_a[2], Sem.div(Sem.mul(v_local_x, v_dz), v_length)), v_o["bottom"])], "rotation": v_angle, "front_offset": Sem.div(Sem.neg(v_thickness), 2), "width": v_o["width"], "height": v_o["height"], "shape": v_o["shape"], "rise": v_o.get("rise")})
	v_closed = Sem.both_lazy(((Sem.py_len(v_pts) > 3)), func(): return ((Sem.dist(v_pts[0], v_pts[Sem.neg(1)]) < EPS)))
	v_pillar_points = (Sem.slice_array(v_pts, null, Sem.neg(1), null) if Sem.truth(v_closed) else v_pts)
	for tmp_83 in Sem.py_enumerate(v_pillar_points):
		var tmp_84 = tmp_83
		v_i = tmp_84[0]
		v_p = tmp_84[1]
		if Sem.truth(Sem.both_lazy(((v_i == 0)), func(): return not Sem.truth(v_closed))):
			v_direction = [Sem.sub(v_pts[1][0], v_p[0]), Sem.sub(v_pts[1][1], v_p[1])]
		else:
			if Sem.truth(Sem.both_lazy(((v_i == Sem.sub(Sem.py_len(v_pillar_points), 1))), func(): return not Sem.truth(v_closed))):
				v_direction = [Sem.sub(v_p[0], v_pts[Sem.sub(v_i, 1)][0]), Sem.sub(v_p[1], v_pts[Sem.sub(v_i, 1)][1])]
			else:
				v_previous = v_pillar_points[Sem.mod(Sem.sub(v_i, 1), Sem.py_len(v_pillar_points))]
				v_following = v_pillar_points[Sem.mod(Sem.add(v_i, 1), Sem.py_len(v_pillar_points))]
				v_before = [Sem.sub(v_p[0], v_previous[0]), Sem.sub(v_p[1], v_previous[1])]
				v_after = [Sem.sub(v_following[0], v_p[0]), Sem.sub(v_following[1], v_p[1])]
				var tmp_85 = [atan2(v_before[1], v_before[0]), atan2(v_after[1], v_after[0])]
				v_a1 = tmp_85[0]
				v_a2 = tmp_85[1]
				v_turn = atan2(sin(Sem.sub(v_a2, v_a1)), cos(Sem.sub(v_a2, v_a1)))
				if Sem.truth(((abs(v_turn) < deg_to_rad(14)))):
					continue
				v_direction = [Sem.add(cos(v_a1), cos(v_a2)), Sem.add(sin(v_a1), sin(v_a2))]
		v_pillar = Geo.gen_group(Sem.add(v_name, Sem.mod("_Pilaster_%02d", v_i)), v_p, atan2(v_direction[1], v_direction[0]), v_root)
		v_y = Sem.sub(Sem.div(Sem.neg(v_thickness), 2), 0.055)
		Geo.gen_box("Pilaster_Shaft", [0, v_y, Sem.div(v_height, 2)], [0.245, 0.145, Sem.py_max(0.1, Sem.sub(v_height, 0.16))], v_mats["wood"], 0.016, v_pillar)
		Geo.gen_box("Pilaster_Foot", [0, Sem.sub(v_y, 0.01), 0.13], [0.35, 0.22, 0.26], v_mats["wood_dark"], 0.016, v_pillar)
		Geo.gen_box("Pilaster_BaseBand", [0, Sem.sub(v_y, 0.015), 0.3], [0.3, 0.205, 0.075], v_mats["wood_light"], 0.008, v_pillar)
		Geo.gen_box("Pilaster_Capital", [0, Sem.sub(v_y, 0.025), Sem.sub(v_height, 0.19)], [0.34, 0.235, 0.15], v_mats["wood"], 0.012, v_pillar)
		Geo.gen_box("Pilaster_Abacus", [0, Sem.sub(v_y, 0.035), Sem.sub(v_height, 0.065)], [0.43, 0.285, 0.1], v_mats["wood_light"], 0.012, v_pillar)
	v_root["opening_anchors"] = JSON.stringify(v_anchors)
	return v_root

static func gen__profile_prism(v_name, v_profile, v_half_width, v_mat, v_parent):
	var v_clean = null
	var v_faces = null
	var v_i = null
	var v_n = null
	var v_p = null
	var v_vertices = null
	var v_x = null
	var v_z = null
	v_clean = []
	for tmp_86 in v_profile:
		v_p = tmp_86
		if Sem.truth(Sem.either_lazy(not Sem.truth(v_clean), func(): return ((Sem.dist(v_p, v_clean[Sem.neg(1)]) > EPS)))):
			v_clean.append(v_p)
	v_n = Sem.py_len(v_clean)
	v_vertices = Sem.add(Sem.map_array(v_clean, func(tmp_87): var tmp_88 = tmp_87[0]; var tmp_89 = tmp_87[1]; return [tmp_88, Sem.neg(v_half_width), tmp_89]), Sem.map_array(v_clean, func(tmp_90): var tmp_91 = tmp_90[0]; var tmp_92 = tmp_90[1]; return [tmp_91, v_half_width, tmp_92]))
	v_faces = [Sem.py_tuple(Sem.py_reversed(range(v_n))), Sem.py_tuple(range(v_n, Sem.mul(2, v_n)))]
	v_faces = Sem.add(v_faces, Sem.map_array(range(v_n), func(tmp_93): var tmp_94 = tmp_93; return [tmp_94, Sem.mod(Sem.add(tmp_94, 1), v_n), Sem.add(Sem.mod(Sem.add(tmp_94, 1), v_n), v_n), Sem.add(tmp_94, v_n)]))
	return Geo.gen_mesh(v_name, v_vertices, v_faces, v_mat, v_parent, 0)

static func gen_staircase(v_name, v_points, v_width, v_mats, v_step_rise = 0.18, v_landing_depth = null, v_parent = null):
	var v_a = null
	var v_b = null
	var v_cap = null
	var v_count = null
	var v_depth = null
	var v_dx = null
	var v_dy = null
	var v_dz = null
	var v_flight = null
	var v_index = null
	var v_j = null
	var v_length = null
	var v_level = null
	var v_nosing = null
	var v_p = null
	var v_profile = null
	var v_pts = null
	var v_riser = null
	var v_root = null
	var v_run = null
	var v_side = null
	var v_total_steps = null
	var v_waist = null
	var v_z = null
	v_pts = load("res://tools/building_construction/BuildingConstruction/Shared/PathRecipes.gd").gen_clean_polyline(v_points, false)
	if Sem.truth(Sem.either_lazy(((v_width <= 0)), func(): return ((v_step_rise <= 0)))):
		push_error(str("Stair width and riser height must be positive"))
		return null
	v_root = Geo.gen_group(v_name, [0, 0, 0], 0, v_parent)
	v_root["generator"] = "staircase_v1"
	v_root["path_nodes"] = JSON.stringify(v_pts)
	v_total_steps = 0
	v_cap = 0.055
	v_nosing = 0.025
	for tmp_95 in Sem.py_enumerate(Sem.py_zip(v_pts, Sem.slice_array(v_pts, 1, null, null))):
		var tmp_96 = tmp_95
		v_index = tmp_96[0]
		var tmp_97 = tmp_96[1]
		v_a = tmp_97[0]
		v_b = tmp_97[1]
		var tmp_100 = Sem.map_array(range(3), func(tmp_98): var tmp_99 = tmp_98; return Sem.sub(v_b[tmp_99], v_a[tmp_99]))
		v_dx = tmp_100[0]
		v_dy = tmp_100[1]
		v_dz = tmp_100[2]
		v_run = Sem.hypot(v_dx, v_dy)
		if Sem.truth(((v_run < EPS))):
			push_error(str("Stair segments need a horizontal run"))
			return null
		v_flight = Geo.gen_group(Sem.add(v_name, Sem.mod("_Flight_%02d", v_index)), v_a, atan2(v_dy, v_dx), v_root)
		if Sem.truth(((abs(v_dz) < EPS))):
			v_length = (Sem.py_max(v_run, float(v_landing_depth)) if Sem.truth(((v_landing_depth != null))) else v_run)
			Geo.gen_box("Landing_Solid", [Sem.div(v_run, 2), 0, Sem.neg(0.15)], [v_length, v_width, 0.3], v_mats["wood"], 0.012, v_flight)
			Geo.gen_box("Landing_Surface", [Sem.div(v_run, 2), 0, Sem.div(Sem.neg(v_cap), 2)], [Sem.add(v_length, 0.04), Sem.add(v_width, 0.07), v_cap], v_mats.get("stair_tread", v_mats["stone"]), 0.012, v_flight)
			for tmp_101 in [Sem.neg(1), 1]:
				v_side = tmp_101
				Geo.gen_box(Sem.add("Landing_Edge_", str(v_side)), [Sem.div(v_run, 2), Sem.mul(v_side, Sem.add(Sem.div(v_width, 2), 0.018)), Sem.neg(0.1)], [Sem.add(v_length, 0.03), 0.065, 0.14], v_mats["wood_light"], 0.008, v_flight)
			continue
		v_count = Sem.py_max(1, ceili(Sem.div(abs(v_dz), v_step_rise)))
		var tmp_102 = [Sem.div(v_dz, v_count), Sem.div(v_run, v_count)]
		v_riser = tmp_102[0]
		v_depth = tmp_102[1]
		if Sem.truth(((v_depth < 0.12))):
			push_error(str("Stair treads are too shallow; increase run or riser height"))
			return null
		v_waist = Sem.py_max(0.24, Sem.add(abs(v_riser), 0.07))
		v_profile = [[0, Sem.neg(v_cap)]]
		for tmp_103 in range(v_count):
			v_j = tmp_103
			v_level = Sem.sub(Sem.mul(Sem.add(v_j, 1), v_riser), v_cap)
			v_profile.append_array([[Sem.mul(v_j, v_depth), v_level], [Sem.mul(Sem.add(v_j, 1), v_depth), v_level]])
		v_profile.append_array([[v_run, Sem.sub(v_dz, v_waist)], [0, Sem.neg(v_waist)]])
		gen__profile_prism("Stair_Solid_Sides", v_profile, Sem.div(v_width, 2), v_mats["wood_dark"], v_flight)
		for tmp_104 in range(v_count):
			v_j = tmp_104
			v_z = Sem.mul(Sem.add(v_j, 1), v_riser)
			Geo.gen_box(Sem.mod("Tread_%02d", v_j), [Sem.sub(Sem.mul(Sem.add(v_j, 0.5), v_depth), Sem.div(v_nosing, 2)), 0, Sem.sub(v_z, Sem.div(v_cap, 2))], [Sem.add(v_depth, v_nosing), Sem.add(v_width, 0.07), v_cap], v_mats.get("stair_tread", v_mats["stone"]), 0.01, v_flight)
			Geo.gen_box(Sem.mod("Nosing_%02d", v_j), [Sem.sub(Sem.mul(v_j, v_depth), Sem.div(v_nosing, 2)), 0, Sem.sub(v_z, 0.018)], [0.034, Sem.add(v_width, 0.09), 0.035], v_mats.get("stair_nosing", v_mats["stone"]), 0.007, v_flight)
		for tmp_105 in [Sem.neg(1), 1]:
			v_side = tmp_105
			Geo.gen_beam(Sem.add("Stringer_", str(v_side)), [0, Sem.mul(v_side, Sem.add(Sem.div(v_width, 2), 0.022)), Sem.neg(0.12)], [v_run, Sem.mul(v_side, Sem.add(Sem.div(v_width, 2), 0.022)), Sem.sub(v_dz, 0.12)], 0.07, 0.16, v_mats["wood"], v_flight, 0.008)
		v_total_steps = Sem.add(v_total_steps, v_count)
	v_root["steps_total"] = v_total_steps
	v_root["width"] = float(v_width)
	v_root["finished_top"] = Sem.py_max(Sem.map_array(v_pts, func(tmp_106): var tmp_107 = tmp_106; return tmp_107[2]))
	return v_root

static func gen__handrail(v_name, v_points, v_width, v_depth, v_z_offset, v_mat, v_parent):
	var v_faces = null
	var v_i = null
	var v_j = null
	var v_l = null
	var v_left = null
	var v_r = null
	var v_right = null
	var v_vertices = null
	var tmp_108 = [load("res://tools/building_construction/BuildingConstruction/Shared/PathRecipes.gd").gen_offset_polyline(v_points, Sem.div(Sem.neg(v_width), 2), 2.5, false), load("res://tools/building_construction/BuildingConstruction/Shared/PathRecipes.gd").gen_offset_polyline(v_points, Sem.div(v_width, 2), 2.5, false)]
	v_left = tmp_108[0]
	v_right = tmp_108[1]
	v_vertices = []
	for tmp_109 in Sem.py_zip(v_left, v_right):
		var tmp_110 = tmp_109
		v_l = tmp_110[0]
		v_r = tmp_110[1]
		v_vertices = Sem.add(v_vertices, [[v_r[0], v_r[1], Sem.sub(Sem.add(v_r[2], v_z_offset), Sem.div(v_depth, 2))], [v_l[0], v_l[1], Sem.sub(Sem.add(v_l[2], v_z_offset), Sem.div(v_depth, 2))], [v_l[0], v_l[1], Sem.add(Sem.add(v_l[2], v_z_offset), Sem.div(v_depth, 2))], [v_r[0], v_r[1], Sem.add(Sem.add(v_r[2], v_z_offset), Sem.div(v_depth, 2))]])
	v_faces = [[3, 2, 1, 0], Sem.py_tuple(range(Sem.sub(Sem.py_len(v_vertices), 4), Sem.py_len(v_vertices)))]
	for tmp_111 in range(Sem.sub(Sem.py_len(v_points), 1)):
		v_i = tmp_111
		for tmp_112 in range(4):
			v_j = tmp_112
			v_faces.append([Sem.add(Sem.mul(4, v_i), v_j), Sem.add(Sem.mul(4, v_i), Sem.mod(Sem.add(v_j, 1), 4)), Sem.add(Sem.mul(4, Sem.add(v_i, 1)), Sem.mod(Sem.add(v_j, 1), 4)), Sem.add(Sem.mul(4, Sem.add(v_i, 1)), v_j)])
	return Geo.gen_mesh(v_name, v_vertices, v_faces, v_mat, v_parent, 0.006)

static func gen_railing(v_name, v_points, v_mats, v_height = 0.88, v_spacing = 0.22, v_parent = null, v_end_posts = [true, true]):
	var v_angle = null
	var v_balusters = null
	var v_base = null
	var v_distance = null
	var v_embed = null
	var v_h = null
	var v_i = null
	var v_index = null
	var v_intervals = null
	var v_j = null
	var v_lengths = null
	var v_lu = null
	var v_lv = null
	var v_newel_indices = null
	var v_p = null
	var v_post = null
	var v_profile = null
	var v_pts = null
	var v_q = null
	var v_root = null
	var v_total_length = null
	var v_u = null
	var v_v = null
	var v_x = null
	var v_y = null
	v_pts = load("res://tools/building_construction/BuildingConstruction/Shared/PathRecipes.gd").gen_clean_polyline(v_points, false)
	if Sem.truth(Sem.either_lazy(((v_height <= 0.35)), func(): return ((v_spacing <= 0)))):
		push_error(str("Railing needs positive spacing and a useful height"))
		return null
	v_root = Geo.gen_group(v_name, [0, 0, 0], 0, v_parent)
	v_root["generator"] = "railing_v1"
	v_root["path_nodes"] = JSON.stringify(v_pts)
	gen__handrail("Mitered_Handrail", v_pts, 0.105, 0.065, v_height, v_mats["wood"], v_root)
	gen__handrail("Handrail_Lower_Bead", v_pts, 0.075, 0.028, Sem.sub(v_height, 0.052), v_mats["wood_light"], v_root)
	v_newel_indices = ([0] if Sem.truth(v_end_posts[0]) else [])
	for tmp_113 in range(1, Sem.sub(Sem.py_len(v_pts), 1)):
		v_i = tmp_113
		v_u = Sem.py_tuple(Sem.map_array(range(3), func(tmp_114): var tmp_115 = tmp_114; return Sem.sub(v_pts[v_i][tmp_115], v_pts[Sem.sub(v_i, 1)][tmp_115])))
		v_v = Sem.py_tuple(Sem.map_array(range(3), func(tmp_116): var tmp_117 = tmp_116; return Sem.sub(v_pts[Sem.add(v_i, 1)][tmp_117], v_pts[v_i][tmp_117])))
		var tmp_122 = [sqrt(Sem.py_sum(Sem.map_array(v_u, func(tmp_118): var tmp_119 = tmp_118; return Sem.mul(tmp_119, tmp_119)))), sqrt(Sem.py_sum(Sem.map_array(v_v, func(tmp_120): var tmp_121 = tmp_120; return Sem.mul(tmp_121, tmp_121))))]
		v_lu = tmp_122[0]
		v_lv = tmp_122[1]
		v_angle = acos(Sem.py_max(Sem.neg(1.0), Sem.py_min(1.0, Sem.div(Sem.py_sum(Sem.map_array(Sem.py_zip(v_u, v_v), func(tmp_123): var tmp_124 = tmp_123[0]; var tmp_125 = tmp_123[1]; return Sem.mul(tmp_124, tmp_125))), Sem.mul(v_lu, v_lv)))))
		if Sem.truth(((v_angle > deg_to_rad(14)))):
			v_newel_indices.append(v_i)
	if Sem.truth(v_end_posts[1]):
		v_newel_indices.append(Sem.sub(Sem.py_len(v_pts), 1))
	v_lengths = load("res://tools/building_construction/BuildingConstruction/Shared/PathRecipes.gd").gen_polyline_lengths(v_pts, false, false)
	v_total_length = v_lengths[Sem.neg(1)]
	v_intervals = Sem.py_max(1, ceili(Sem.div(v_total_length, v_spacing)))
	v_balusters = 0
	for tmp_126 in range(1, v_intervals):
		v_j = tmp_126
		v_distance = Sem.div(Sem.mul(v_total_length, v_j), v_intervals)
		if Sem.truth(Sem.py_any(Sem.map_array(v_newel_indices, func(tmp_127): var tmp_128 = tmp_127; return ((abs(Sem.sub(v_distance, v_lengths[tmp_128])) < 0.1))))):
			continue
		v_index = Sem.py_min(Sem.sub(Sem.py_len(v_pts), 2), Sem.py_max(0, Sem.sub(Sem.bisect_right(v_lengths, v_distance), 1)))
		v_base = load("res://tools/building_construction/BuildingConstruction/Shared/PathRecipes.gd").gen_point_at_distance(v_pts, v_distance, v_lengths, false)
		v_embed = (0.19 if Sem.truth(((abs(Sem.sub(v_pts[Sem.add(v_index, 1)][2], v_pts[v_index][2])) > EPS))) else 0.025)
		v_h = Sem.sub(Sem.add(v_height, v_embed), 0.075)
		v_profile = [[0, 0], [0.037, 0], [0.037, Sem.mul(0.09, v_h)], [0.022, Sem.mul(0.16, v_h)], [0.019, Sem.mul(0.31, v_h)], [0.036, Sem.mul(0.41, v_h)], [0.024, Sem.mul(0.49, v_h)], [0.024, Sem.mul(0.76, v_h)], [0.033, Sem.mul(0.82, v_h)], [0.023, Sem.mul(0.89, v_h)], [0.023, v_h], [0, v_h]]
		Geo.gen_lathe(Sem.mod("Baluster_%03d", v_j), v_profile, 6, v_mats["wood_light"], v_root, [v_base[0], v_base[1], Sem.sub(v_base[2], v_embed)])
		v_balusters = Sem.add(v_balusters, 1)
	for tmp_129 in v_newel_indices:
		v_i = tmp_129
		v_p = v_pts[v_i]
		v_post = Geo.gen_group(Sem.mod("Newel_%02d", v_i), v_p, 0, v_root)
		Geo.gen_box("Newel_Shaft", [0, 0, Sem.sub(Sem.div(v_height, 2), 0.025)], [0.14, 0.14, Sem.add(v_height, 0.05)], v_mats["wood"], 0.012, v_post)
		Geo.gen_box("Newel_Base", [0, 0, 0.075], [0.205, 0.205, 0.15], v_mats["wood_dark"], 0.012, v_post)
		Geo.gen_box("Newel_Collar", [0, 0, Sem.sub(v_height, 0.04)], [0.19, 0.19, 0.08], v_mats["wood_light"], 0.008, v_post)
		Geo.gen_box("Newel_Cap", [0, 0, Sem.add(v_height, 0.035)], [0.225, 0.225, 0.07], v_mats["wood"], 0.01, v_post)
		Geo.gen_lathe("Newel_Finial", [[0, 0], [0.065, 0], [0.09, 0.045], [0.075, 0.11], [0.035, 0.15], [0, 0.15]], 8, v_mats["wood_light"], v_post, [0, 0, Sem.add(v_height, 0.07)])
	v_root["balusters_total"] = v_balusters
	return v_root

