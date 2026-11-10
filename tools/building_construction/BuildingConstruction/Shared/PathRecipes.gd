@tool
extends RefCounted

# Direct port of kit/paths.py. Z-up recipe coordinates convert at the geometry boundary.
const Sem = preload("res://tools/building_construction/BuildingConstruction/Shared/RecipeSemantics.gd")
const Geo = preload("res://tools/building_construction/BuildingConstruction/Shared/RecipeGeometry.gd")
const EPS = 1e-9

static func gen_point3(v_value):
	var v_p = null
	var v_v = null
	if Sem.truth((v_value is Dictionary)):
		v_value = v_value.get("position", v_value.get("pos", v_value.get("co")))
	if Sem.truth(Sem.either_lazy(((v_value == null)), func(): return ((Sem.py_len(v_value) < 2)))):
		push_error(str("A path point needs at least x and y coordinates"))
		return null
	v_p = [float(v_value[0]), float(v_value[1]), (float(v_value[2]) if Sem.truth(((Sem.py_len(v_value) > 2))) else 0.0)]
	if Sem.truth(not Sem.truth(Sem.py_all(Sem.map_array(v_p, func(tmp_1): var tmp_2 = tmp_1; return is_finite(tmp_2))))):
		push_error(str("Path coordinates must be finite"))
		return null
	return v_p

static func gen__sub(v_a, v_b):
	var v_x = null
	var v_y = null
	return Sem.py_tuple(Sem.map_array(Sem.py_zip(v_a, v_b), func(tmp_3): var tmp_4 = tmp_3[0]; var tmp_5 = tmp_3[1]; return Sem.sub(tmp_4, tmp_5)))

static func gen__length(v_v):
	var v_x = null
	return sqrt(Sem.py_sum(Sem.map_array(v_v, func(tmp_6): var tmp_7 = tmp_6; return Sem.mul(tmp_7, tmp_7))))

static func gen__unit(v_v):
	var v_length = null
	var v_x = null
	v_length = gen__length(v_v)
	if Sem.truth(((v_length < EPS))):
		push_error(str("Cannot normalize a zero-length path direction"))
		return null
	return Sem.py_tuple(Sem.map_array(v_v, func(tmp_8): var tmp_9 = tmp_8; return Sem.div(tmp_9, v_length)))

static func gen__cross(v_a, v_b):
	return [Sem.sub(Sem.mul(v_a[1], v_b[2]), Sem.mul(v_a[2], v_b[1])), Sem.sub(Sem.mul(v_a[2], v_b[0]), Sem.mul(v_a[0], v_b[2])), Sem.sub(Sem.mul(v_a[0], v_b[1]), Sem.mul(v_a[1], v_b[0]))]

static func gen_clean_polyline(v_points, v_closed = false):
	var v_p = null
	var v_result = null
	var v_value = null
	v_result = []
	for tmp_10 in v_points:
		v_value = tmp_10
		v_p = gen_point3(v_value)
		if Sem.truth(Sem.either_lazy(not Sem.truth(v_result), func(): return ((gen__length(gen__sub(v_p, v_result[Sem.neg(1)])) > EPS)))):
			v_result.append(v_p)
	if Sem.truth(Sem.both_lazy(v_closed, func(): return Sem.both_lazy(((Sem.py_len(v_result) > 1)), func(): return ((gen__length(gen__sub(v_result[0], v_result[Sem.neg(1)])) < EPS))))):
		v_result.pop_back()
	if Sem.truth(((Sem.py_len(v_result) < (3 if Sem.truth(v_closed) else 2)))):
		push_error(str("A path requires distinct points"))
		return null
	return v_result

static func gen_sample_cubic_bezier(v_p0, v_p1, v_p2, v_p3, v_segments = 12):
	var v_axis = null
	var v_controls = null
	var v_i = null
	var v_j = null
	var v_p = null
	var v_result = null
	var v_t = null
	var v_u = null
	var v_weights = null
	v_controls = Sem.map_array([v_p0, v_p1, v_p2, v_p3], func(tmp_11): var tmp_12 = tmp_11; return gen_point3(tmp_12))
	v_segments = Sem.py_max(1, int(v_segments))
	v_result = []
	for tmp_13 in range(Sem.add(v_segments, 1)):
		v_i = tmp_13
		v_t = Sem.div(v_i, v_segments)
		v_u = Sem.sub(1, v_t)
		v_weights = [Sem.mul(Sem.mul(v_u, v_u), v_u), Sem.mul(Sem.mul(Sem.mul(3, v_u), v_u), v_t), Sem.mul(Sem.mul(Sem.mul(3, v_u), v_t), v_t), Sem.mul(Sem.mul(v_t, v_t), v_t)]
		v_result.append(Sem.py_tuple(Sem.map_array(range(3), func(tmp_14): var tmp_15 = tmp_14; return Sem.py_sum(Sem.map_array(range(4), func(tmp_16): var tmp_17 = tmp_16; return Sem.mul(v_weights[tmp_17], v_controls[tmp_17][tmp_15]))))))
	return v_result

static func gen_sample_path(v_nodes, v_curve_segments = 12, v_closed = false):
	var v_a = null
	var v_b = null
	var v_h0 = null
	var v_h1 = null
	var v_i = null
	var v_p0 = null
	var v_p3 = null
	var v_pair_count = null
	var v_result = null
	var v_segment = null
	if Sem.truth((v_nodes is Dictionary)):
		v_closed = Sem.truth(v_nodes.get("closed", v_closed))
		v_nodes = v_nodes["nodes"]
	if Sem.truth(((Sem.py_len(v_nodes) < 2))):
		push_error(str("A sampled path needs at least two nodes"))
		return null
	v_result = []
	v_pair_count = (Sem.py_len(v_nodes) if Sem.truth(v_closed) else Sem.sub(Sem.py_len(v_nodes), 1))
	for tmp_18 in range(v_pair_count):
		v_i = tmp_18
		var tmp_19 = [v_nodes[v_i], v_nodes[Sem.mod(Sem.add(v_i, 1), Sem.py_len(v_nodes))]]
		v_a = tmp_19[0]
		v_b = tmp_19[1]
		var tmp_20 = [gen_point3(v_a), gen_point3(v_b)]
		v_p0 = tmp_20[0]
		v_p3 = tmp_20[1]
		v_h0 = (v_a.get("handle_out") if Sem.truth((v_a is Dictionary)) else null)
		v_h1 = (v_b.get("handle_in") if Sem.truth((v_b is Dictionary)) else null)
		v_segment = (gen_sample_cubic_bezier(v_p0, Sem.either_lazy(v_h0, func(): return v_p0), Sem.either_lazy(v_h1, func(): return v_p3), v_p3, v_curve_segments) if Sem.truth(Sem.either_lazy(((v_h0 != null)), func(): return ((v_h1 != null)))) else [v_p0, v_p3])
		v_result.append_array((v_segment if Sem.truth(not Sem.truth(v_result)) else Sem.slice_array(v_segment, 1, null, null)))
	return gen_clean_polyline(v_result, v_closed)

static func gen_polyline_lengths(v_points, v_closed = false, v_planar = false):
	var v_a = null
	var v_b = null
	var v_cumulative = null
	var v_delta = null
	var v_length = null
	var v_pts = null
	v_pts = gen_clean_polyline(v_points, v_closed)
	if Sem.truth(v_closed):
		v_pts = Sem.add(v_pts, [v_pts[0]])
	v_cumulative = [0.0]
	for tmp_21 in Sem.py_zip(v_pts, Sem.slice_array(v_pts, 1, null, null)):
		var tmp_22 = tmp_21
		v_a = tmp_22[0]
		v_b = tmp_22[1]
		v_delta = gen__sub(v_b, v_a)
		v_length = (Sem.hypot(v_delta[0], v_delta[1]) if Sem.truth(v_planar) else gen__length(v_delta))
		v_cumulative.append(Sem.add(v_cumulative[Sem.neg(1)], v_length))
	return v_cumulative

static func gen_arc_length(v_points, v_closed = false, v_planar = false):
	return gen_polyline_lengths(v_points, v_closed, v_planar)[Sem.neg(1)]

static func gen__lookup(v_points, v_distance, v_closed = false, v_cumulative = null):
	var v_a = null
	var v_b = null
	var v_d = null
	var v_i = null
	var v_length = null
	var v_lengths = null
	var v_position = null
	var v_pts = null
	var v_t = null
	var v_total = null
	v_pts = gen_clean_polyline(v_points, v_closed)
	v_lengths = (v_cumulative if Sem.truth(((v_cumulative != null))) else gen_polyline_lengths(v_pts, v_closed, false))
	if Sem.truth(v_closed):
		v_pts = Sem.add(v_pts, [v_pts[0]])
	v_total = v_lengths[Sem.neg(1)]
	v_d = (Sem.mod(float(v_distance), v_total) if Sem.truth(v_closed) else Sem.py_max(0.0, Sem.py_min(float(v_distance), v_total)))
	v_i = Sem.py_min(Sem.sub(Sem.py_len(v_pts), 2), Sem.py_max(0, Sem.sub(Sem.bisect_right(v_lengths, v_d), 1)))
	v_length = Sem.sub(v_lengths[Sem.add(v_i, 1)], v_lengths[v_i])
	v_t = (Sem.div(Sem.sub(v_d, v_lengths[v_i]), v_length) if Sem.truth(((v_length > EPS))) else 0.0)
	v_position = Sem.py_tuple(Sem.map_array(Sem.py_zip(v_pts[v_i], v_pts[Sem.add(v_i, 1)]), func(tmp_23): var tmp_24 = tmp_23[0]; var tmp_25 = tmp_23[1]; return Sem.add(tmp_24, Sem.mul(Sem.sub(tmp_25, tmp_24), v_t))))
	return [v_position, gen__unit(gen__sub(v_pts[Sem.add(v_i, 1)], v_pts[v_i]))]

static func gen_point_at_distance(v_points, v_distance, v_cumulative = null, v_closed = false):
	return gen__lookup(v_points, v_distance, v_closed, v_cumulative)[0]

static func gen_frame_at_distance(v_points, v_distance, v_closed = false):
	var v_horizontal = null
	var v_position = null
	var v_right = null
	var v_tangent = null
	var v_up = null
	var tmp_26 = gen__lookup(v_points, v_distance, v_closed, null)
	v_position = tmp_26[0]
	v_tangent = tmp_26[1]
	v_horizontal = Sem.hypot(v_tangent[0], v_tangent[1])
	v_right = ([Sem.div(v_tangent[1], v_horizontal), Sem.div(Sem.neg(v_tangent[0]), v_horizontal), 0.0] if Sem.truth(((v_horizontal > EPS))) else [1.0, 0.0, 0.0])
	v_up = gen__unit(gen__cross(v_right, v_tangent))
	return [v_position, v_tangent, v_right, v_up]

static func gen_resample_polyline(v_points, v_spacing = null, v_count = null, v_closed = false, v_include_end = true):
	var v_i = null
	var v_intervals = null
	var v_lengths = null
	var v_pts = null
	var v_total = null
	v_pts = gen_clean_polyline(v_points, v_closed)
	v_total = gen_arc_length(v_pts, v_closed, false)
	if Sem.truth(Sem.both_lazy(((v_spacing != null)), func(): return ((v_count != null)))):
		push_error(str("Specify spacing OR count"))
		return null
	if Sem.truth(((v_count != null))):
		v_count = Sem.py_max((3 if Sem.truth(v_closed) else 2), int(v_count))
		v_intervals = (v_count if Sem.truth(v_closed) else Sem.sub(v_count, 1))
	else:
		v_spacing = (0.2 if Sem.truth(((v_spacing == null))) else float(v_spacing))
		if Sem.truth(((v_spacing <= 0))):
			push_error(str("Path sample spacing must be positive"))
			return null
		v_intervals = Sem.py_max(1, ceili(Sem.div(v_total, v_spacing)))
		v_count = (v_intervals if Sem.truth(v_closed) else Sem.add(v_intervals, 1))
	if Sem.truth(Sem.both_lazy(not Sem.truth(v_closed), func(): return not Sem.truth(v_include_end))):
		v_count = Sem.sub(v_count, 1)
	v_lengths = gen_polyline_lengths(v_pts, v_closed, false)
	return Sem.map_array(range(v_count), func(tmp_27): var tmp_28 = tmp_27; return gen_point_at_distance(v_pts, Sem.div(Sem.mul(tmp_28, v_total), v_intervals), v_lengths, v_closed))

static func gen_offset_polyline(v_points, v_distance, v_miter_limit = 2.5, v_closed = false):
	var v_a = null
	var v_b = null
	var v_denominator = null
	var v_dx = null
	var v_dy = null
	var v_factor = null
	var v_i = null
	var v_length = null
	var v_normals = null
	var v_p = null
	var v_pts = null
	var v_result = null
	var v_vx = null
	var v_vy = null
	v_pts = gen_clean_polyline(v_points, v_closed)
	v_normals = []
	for tmp_29 in Sem.py_zip(v_pts, Sem.add(Sem.slice_array(v_pts, 1, null, null), ([v_pts[0]] if Sem.truth(v_closed) else []))):
		var tmp_30 = tmp_29
		v_a = tmp_30[0]
		v_b = tmp_30[1]
		var tmp_31 = [Sem.sub(v_b[0], v_a[0]), Sem.sub(v_b[1], v_a[1])]
		v_dx = tmp_31[0]
		v_dy = tmp_31[1]
		v_length = Sem.hypot(v_dx, v_dy)
		if Sem.truth(((v_length < EPS))):
			push_error(str("Horizontal offset cannot follow a vertical segment"))
			return null
		v_normals.append([Sem.div(v_dy, v_length), Sem.div(Sem.neg(v_dx), v_length)])
	v_result = []
	for tmp_32 in Sem.py_enumerate(v_pts):
		var tmp_33 = tmp_32
		v_i = tmp_33[0]
		v_p = tmp_33[1]
		if Sem.truth(Sem.both_lazy(not Sem.truth(v_closed), func(): return ((v_i == 0)))):
			var tmp_34 = v_normals[0]
			v_vx = tmp_34[0]
			v_vy = tmp_34[1]
		else:
			if Sem.truth(Sem.both_lazy(not Sem.truth(v_closed), func(): return ((v_i == Sem.sub(Sem.py_len(v_pts), 1))))):
				var tmp_35 = v_normals[Sem.neg(1)]
				v_vx = tmp_35[0]
				v_vy = tmp_35[1]
			else:
				var tmp_36 = [v_normals[Sem.mod(Sem.sub(v_i, 1), Sem.py_len(v_normals))], v_normals[Sem.mod(v_i, Sem.py_len(v_normals))]]
				v_a = tmp_36[0]
				v_b = tmp_36[1]
				var tmp_37 = [Sem.add(v_a[0], v_b[0]), Sem.add(v_a[1], v_b[1])]
				v_vx = tmp_37[0]
				v_vy = tmp_37[1]
				v_length = Sem.hypot(v_vx, v_vy)
				if Sem.truth(((v_length < EPS))):
					var tmp_38 = v_b
					v_vx = tmp_38[0]
					v_vy = tmp_38[1]
				else:
					var tmp_39 = [Sem.div(v_vx, v_length), Sem.div(v_vy, v_length)]
					v_vx = tmp_39[0]
					v_vy = tmp_39[1]
					v_denominator = Sem.add(Sem.mul(v_vx, v_a[0]), Sem.mul(v_vy, v_a[1]))
					v_factor = Sem.py_min(float(v_miter_limit), Sem.div(1, Sem.py_max(EPS, v_denominator)))
					var tmp_40 = [Sem.mul(v_vx, v_factor), Sem.mul(v_vy, v_factor)]
					v_vx = tmp_40[0]
					v_vy = tmp_40[1]
		v_result.append([Sem.add(v_p[0], Sem.mul(v_distance, v_vx)), Sem.add(v_p[1], Sem.mul(v_distance, v_vy)), v_p[2]])
	return v_result

