@tool
extends RefCounted

# Direct port of kit/industrial_props.py. Z-up recipe coordinates convert at the geometry boundary.
const Sem = preload("res://tools/building_construction/BuildingConstruction/Shared/RecipeSemantics.gd")
const Geo = preload("res://tools/building_construction/BuildingConstruction/Shared/RecipeGeometry.gd")
const EPS = 1e-9

static func gen_material_set(v_mats):
	var v_args = null
	var v_colors = null
	var v_key = null
	var v_name = null
	var v_result = null
	return Geo.industrial_palette(v_mats)

static func gen__cylinder_between(v_name, v_a, v_b, v_radius, v_mat, v_parent, v_sides = 8):
	var v_delta = null
	var v_ob = null
	var tmp_1 = [Sem.vector(v_a), Sem.vector(v_b)]
	v_a = tmp_1[0]
	v_b = tmp_1[1]
	v_delta = Sem.sub(v_b, v_a)
	v_ob = Geo.gen_cylinder(v_name, Sem.mul(Sem.add(v_a, v_b), 0.5), v_radius, v_delta.length(), v_mat, v_sides, v_parent)
	v_ob.rotation_euler = Sem.track_euler(v_delta)
	return v_ob

static func gen_ring(v_name, v_outer, v_inner, v_depth, v_mat, v_parent = null, v_sides = 12):
	var v_fs = null
	var v_i = null
	var v_j = null
	var v_radius = null
	var v_vs = null
	var v_z = null
	if Sem.truth(Sem.either_lazy(not Sem.truth(((0 < v_inner) and (v_inner < v_outer))), func(): return ((v_depth <= 0)))):
		push_error(str("Invalid annular dimensions"))
		return null
	v_vs = []
	for tmp_2 in [[v_outer, Sem.div(Sem.neg(v_depth), 2)], [v_outer, Sem.div(v_depth, 2)], [v_inner, Sem.div(Sem.neg(v_depth), 2)], [v_inner, Sem.div(v_depth, 2)]]:
		var tmp_3 = tmp_2
		v_radius = tmp_3[0]
		v_z = tmp_3[1]
		v_vs.append_array(Sem.map_array(range(v_sides), func(tmp_4): var tmp_5 = tmp_4; return [Sem.mul(v_radius, cos(Sem.div(Sem.mul(Sem.mul(2, PI), tmp_5), v_sides))), Sem.mul(v_radius, sin(Sem.div(Sem.mul(Sem.mul(2, PI), tmp_5), v_sides))), v_z]))
	v_fs = []
	for tmp_6 in range(v_sides):
		v_i = tmp_6
		v_j = Sem.mod(Sem.add(v_i, 1), v_sides)
		v_fs.append_array([[v_i, v_j, Sem.add(v_sides, v_j), Sem.add(v_sides, v_i)], [Sem.add(Sem.mul(2, v_sides), v_j), Sem.add(Sem.mul(2, v_sides), v_i), Sem.add(Sem.mul(3, v_sides), v_i), Sem.add(Sem.mul(3, v_sides), v_j)], [v_i, Sem.add(Sem.mul(2, v_sides), v_i), Sem.add(Sem.mul(2, v_sides), v_j), v_j], [Sem.add(v_sides, v_j), Sem.add(Sem.mul(3, v_sides), v_j), Sem.add(Sem.mul(3, v_sides), v_i), Sem.add(v_sides, v_i)]])
	return Geo.gen_mesh(v_name, v_vs, v_fs, v_mat, v_parent, 0)

static func gen_flange(v_name, v_mats, v_radius = 0.12, v_parent = null, v_bolts = 6):
	var v_a = null
	var v_i = null
	var v_m = null
	var v_root = null
	v_m = gen_material_set(v_mats)
	v_root = Geo.gen_group(v_name, [0, 0, 0], 0, v_parent)
	gen_ring(Sem.add(v_name, "_Flange"), Sem.mul(v_radius, 1.65), Sem.mul(v_radius, 0.93), Sem.mul(v_radius, 0.52), v_m["gold"], v_root, 12)
	for tmp_7 in range(v_bolts):
		v_i = tmp_7
		v_a = Sem.div(Sem.mul(Sem.mul(2, PI), v_i), v_bolts)
		Geo.gen_cylinder(Sem.add(v_name, Sem.mod("_Bolt_%02d", v_i)), [Sem.mul(Sem.mul(v_radius, 1.3), cos(v_a)), Sem.mul(Sem.mul(v_radius, 1.3), sin(v_a)), Sem.mul(v_radius, 0.32)], Sem.mul(v_radius, 0.12), Sem.mul(v_radius, 0.22), v_m["iron"], 6, v_root)
	return v_root

static func gen__rounded_nodes(v_nodes, v_radius):
	var v_a = null
	var v_b = null
	var v_c = null
	var v_d = null
	var v_incoming = null
	var v_out = null
	var v_outgoing = null
	var v_p = null
	var v_pts = null
	var v_q0 = null
	var v_q3 = null
	if Sem.truth(Sem.py_any(Sem.map_array(v_nodes, func(tmp_8): var tmp_9 = tmp_8; return (tmp_9 is Dictionary)))):
		return load("res://tools/building_construction/BuildingConstruction/Shared/PathRecipes.gd").gen_sample_path(v_nodes, 5, false)
	v_pts = Sem.map_array(load("res://tools/building_construction/BuildingConstruction/Shared/PathRecipes.gd").gen_clean_polyline(v_nodes, false), func(tmp_10): var tmp_11 = tmp_10; return Sem.vector(tmp_11))
	v_out = [Sem.py_tuple(v_pts[0])]
	for tmp_12 in Sem.py_zip(v_pts, Sem.slice_array(v_pts, 1, null, null), Sem.slice_array(v_pts, 2, null, null)):
		var tmp_13 = tmp_12
		v_a = tmp_13[0]
		v_b = tmp_13[1]
		v_c = tmp_13[2]
		var tmp_14 = [Sem.sub(v_b, v_a).normalized(), Sem.sub(v_c, v_b).normalized()]
		v_incoming = tmp_14[0]
		v_outgoing = tmp_14[1]
		if Sem.truth(((v_incoming.dot(v_outgoing) > 0.995))):
			v_out.append(Sem.py_tuple(v_b))
			continue
		v_d = Sem.py_min(v_radius, Sem.mul(Sem.sub(v_b, v_a).length(), 0.35), Sem.mul(Sem.sub(v_c, v_b).length(), 0.35))
		var tmp_15 = [Sem.sub(v_b, Sem.mul(v_incoming, v_d)), Sem.add(v_b, Sem.mul(v_outgoing, v_d))]
		v_q0 = tmp_15[0]
		v_q3 = tmp_15[1]
		v_out.append_array(load("res://tools/building_construction/BuildingConstruction/Shared/PathRecipes.gd").gen_sample_cubic_bezier(v_q0, Sem.add(v_q0, Sem.mul(Sem.mul(v_incoming, v_d), 0.552)), Sem.sub(v_q3, Sem.mul(Sem.mul(v_outgoing, v_d), 0.552)), v_q3, 5))
	v_out.append(Sem.py_tuple(v_pts[Sem.neg(1)]))
	return load("res://tools/building_construction/BuildingConstruction/Shared/PathRecipes.gd").gen_clean_polyline(v_out, false)

static func gen_pipe_run(v_name, v_mats, v_nodes, v_radius = 0.09, v_sides = 8, v_collars = true, v_parent = null):
	var v_a = null
	var v_axis = null
	var v_bitangent = null
	var v_f = null
	var v_fs = null
	var v_i = null
	var v_j = null
	var v_k = null
	var v_m = null
	var v_normal = null
	var v_p = null
	var v_pos = null
	var v_projected = null
	var v_pts = null
	var v_ref = null
	var v_root = null
	var v_tangent = null
	var v_vs = null
	v_m = gen_material_set(v_mats)
	v_root = Geo.gen_group(v_name, [0, 0, 0], 0, v_parent)
	v_pts = Sem.map_array(gen__rounded_nodes(v_nodes, Sem.mul(v_radius, 2.8)), func(tmp_16): var tmp_17 = tmp_16; return Sem.vector(tmp_17))
	v_vs = []
	v_normal = null
	for tmp_18 in Sem.py_enumerate(v_pts):
		var tmp_19 = tmp_18
		v_i = tmp_19[0]
		v_p = tmp_19[1]
		v_tangent = Sem.sub(v_pts[Sem.py_min(Sem.add(v_i, 1), Sem.sub(Sem.py_len(v_pts), 1))], v_pts[Sem.py_max(Sem.sub(v_i, 1), 0)]).normalized()
		if Sem.truth(((v_normal == null))):
			v_ref = (Sem.vector([0, 0, 1]) if Sem.truth(((abs(v_tangent.z) < 0.9))) else Sem.vector([1, 0, 0]))
			v_normal = v_tangent.cross(v_ref).normalized()
		else:
			v_projected = Sem.sub(v_normal, Sem.mul(v_tangent, v_normal.dot(v_tangent)))
			if Sem.truth(((v_projected.length() < 1e-06))):
				v_projected = v_tangent.cross(Sem.vector([0, 1, 0]))
			v_normal = v_projected.normalized()
		v_bitangent = v_tangent.cross(v_normal).normalized()
		for tmp_20 in range(v_sides):
			v_j = tmp_20
			v_a = Sem.div(Sem.mul(Sem.mul(2, PI), v_j), v_sides)
			v_vs.append(Sem.py_tuple(Sem.add(v_p, Sem.mul(v_radius, Sem.add(Sem.mul(v_normal, cos(v_a)), Sem.mul(v_bitangent, sin(v_a)))))))
	v_fs = [Sem.py_tuple(Sem.py_reversed(range(v_sides)))]
	for tmp_21 in range(Sem.sub(Sem.py_len(v_pts), 1)):
		v_i = tmp_21
		for tmp_22 in range(v_sides):
			v_j = tmp_22
			v_k = Sem.mod(Sem.add(v_j, 1), v_sides)
			v_fs.append([Sem.add(Sem.mul(v_i, v_sides), v_j), Sem.add(Sem.mul(v_i, v_sides), v_k), Sem.add(Sem.mul(Sem.add(v_i, 1), v_sides), v_k), Sem.add(Sem.mul(Sem.add(v_i, 1), v_sides), v_j)])
	v_fs.append(Sem.py_tuple(range(Sem.mul(Sem.sub(Sem.py_len(v_pts), 1), v_sides), Sem.mul(Sem.py_len(v_pts), v_sides))))
	Geo.gen_mesh(Sem.add(v_name, "_Swept_pipe"), v_vs, v_fs, v_m["copper"], v_root, 0)
	if Sem.truth(v_collars):
		for tmp_23 in Sem.py_enumerate([[v_pts[0], Sem.sub(v_pts[1], v_pts[0])], [v_pts[Sem.neg(1)], Sem.sub(v_pts[Sem.neg(1)], v_pts[Sem.neg(2)])]]):
			var tmp_24 = tmp_23
			v_i = tmp_24[0]
			var tmp_25 = tmp_24[1]
			v_pos = tmp_25[0]
			v_axis = tmp_25[1]
			v_f = gen_flange(Sem.add(v_name, Sem.mod("_End_%d", v_i)), v_m, v_radius, v_root, 6)
			v_f.location = v_pos
			v_f.rotation_euler = Sem.track_euler(v_axis)
	v_root["generator"] = "sampled_octagonal_pipe_v1"
	v_root["pipe_radius"] = v_radius
	return v_root

static func gen_gauge(v_name, v_mats, v_radius = 0.2, v_needle_degrees = 42, v_parent = null):
	var v_a = null
	var v_face = null
	var v_hub = null
	var v_i = null
	var v_m = null
	var v_p = null
	var v_q = null
	var v_rim = null
	var v_root = null
	v_m = gen_material_set(v_mats)
	v_root = Geo.gen_group(v_name, [0, 0, 0], 0, v_parent)
	v_rim = Geo.gen_cylinder(Sem.add(v_name, "_Housing"), [0, 0, 0], v_radius, 0.1, v_m["gold"], 12, v_root)
	v_rim.rotation_euler[0] = Sem.div(PI, 2)
	v_face = Geo.gen_cylinder(Sem.add(v_name, "_Cream_face"), [0, Sem.neg(0.058), 0], Sem.mul(v_radius, 0.86), 0.018, v_m["cream"], 12, v_root)
	v_face.rotation_euler[0] = Sem.div(PI, 2)
	for tmp_26 in range(11):
		v_i = tmp_26
		v_a = deg_to_rad(Sem.add(Sem.neg(140), Sem.mul(v_i, 28)))
		v_p = [Sem.mul(Sem.mul(v_radius, 0.66), cos(v_a)), Sem.neg(0.073), Sem.mul(Sem.mul(v_radius, 0.66), sin(v_a))]
		v_q = [Sem.mul(Sem.mul(v_radius, 0.79), cos(v_a)), Sem.neg(0.073), Sem.mul(Sem.mul(v_radius, 0.79), sin(v_a))]
		Geo.gen_beam(Sem.add(v_name, Sem.mod("_Tick_%02d", v_i)), v_p, v_q, Sem.mul(v_radius, 0.035), 0.009, v_m["iron_dark"], v_root, 0.001)
	v_a = deg_to_rad(v_needle_degrees)
	Geo.gen_beam(Sem.add(v_name, "_Pointer"), [Sem.mul(Sem.mul(Sem.neg(v_radius), 0.17), cos(v_a)), Sem.neg(0.088), Sem.mul(Sem.mul(Sem.neg(v_radius), 0.17), sin(v_a))], [Sem.mul(Sem.mul(v_radius, 0.65), cos(v_a)), Sem.neg(0.088), Sem.mul(Sem.mul(v_radius, 0.65), sin(v_a))], Sem.mul(v_radius, 0.055), 0.012, v_m["iron_dark"], v_root, 0.002)
	v_hub = Geo.gen_cylinder(Sem.add(v_name, "_Hub"), [0, Sem.neg(0.09), 0], Sem.mul(v_radius, 0.1), 0.018, v_m["gold"], 8, v_root)
	v_hub.rotation_euler[0] = Sem.div(PI, 2)
	return v_root

static func gen_interlock_handle(v_name, v_mats, v_radius = 0.23, v_parent = null):
	var v_a = null
	var v_i = null
	var v_m = null
	var v_root = null
	var v_wheel = null
	v_m = gen_material_set(v_mats)
	v_root = Geo.gen_group(v_name, [0, 0, 0], 0, v_parent)
	Geo.gen_box(Sem.add(v_name, "_Mount"), [0, 0, 0], [Sem.mul(v_radius, 1.45), 0.08, Sem.mul(v_radius, 1.85)], v_m["iron"], 0.015, v_root)
	gen__cylinder_between(Sem.add(v_name, "_Spindle"), [0, Sem.neg(0.04), 0], [0, Sem.neg(0.2), 0], Sem.mul(v_radius, 0.15), v_m["gold"], v_root, 8)
	v_wheel = Geo.gen_group(Sem.add(v_name, "_Wheel"), [0, Sem.neg(0.21), 0], 0, v_root)
	v_wheel.rotation_euler[0] = Sem.div(PI, 2)
	gen_ring(Sem.add(v_name, "_Rim"), v_radius, Sem.mul(v_radius, 0.81), Sem.mul(v_radius, 0.17), v_m["brick_red"], v_wheel, 12)
	Geo.gen_cylinder(Sem.add(v_name, "_Hub"), [0, 0, 0], Sem.mul(v_radius, 0.24), Sem.mul(v_radius, 0.24), v_m["gold"], 8, v_wheel)
	for tmp_27 in range(5):
		v_i = tmp_27
		v_a = Sem.div(Sem.mul(Sem.mul(v_i, 2), PI), 5)
		Geo.gen_beam(Sem.add(v_name, Sem.mod("_Spoke_%d", v_i)), [0, 0, 0], [Sem.mul(Sem.mul(v_radius, 0.86), cos(v_a)), Sem.mul(Sem.mul(v_radius, 0.86), sin(v_a)), 0], Sem.mul(v_radius, 0.1), Sem.mul(v_radius, 0.1), v_m["brick_red"], v_wheel, 0.003)
	Geo.gen_box(Sem.add(v_name, "_Stop"), [Sem.mul(v_radius, 0.48), Sem.neg(0.1), Sem.mul(Sem.neg(v_radius), 0.56)], [Sem.mul(v_radius, 0.22), 0.14, Sem.mul(v_radius, 0.23)], v_m["gold"], 0.004, v_root)
	v_root["visual_control_part"] = v_wheel.name
	v_root["binding_status"] = "unbound_candidate"
	return v_root

static func gen_valve_station(v_name, v_mats, v_width = 1.25, v_height = 1.35, v_parent = null):
	var v_a = null
	var v_f = null
	var v_g = null
	var v_j = null
	var v_m = null
	var v_root = null
	var v_s = null
	var v_wheel = null
	var v_x = null
	v_m = gen_material_set(v_mats)
	v_root = Geo.gen_group(v_name, [0, 0, 0], 0, v_parent)
	v_s = Sem.div(v_height, 1.35)
	Geo.gen_box(Sem.add(v_name, "_Plinth"), [0, 0, Sem.mul(0.12, v_s)], [v_width, Sem.mul(0.72, v_s), Sem.mul(0.24, v_s)], v_m["masonry_light"], 0.025, v_root)
	Geo.gen_box(Sem.add(v_name, "_Pump_foot"), [Sem.mul(0.28, v_s), 0, Sem.mul(0.32, v_s)], [Sem.mul(0.45, v_s), Sem.mul(0.48, v_s), Sem.mul(0.17, v_s)], v_m["iron"], 0.025, v_root)
	gen__cylinder_between(Sem.add(v_name, "_Main_body"), [Sem.mul(Sem.neg(v_width), 0.44), 0, Sem.mul(0.6, v_s)], [Sem.mul(v_width, 0.44), 0, Sem.mul(0.6, v_s)], Sem.mul(0.2, v_s), v_m["iron"], v_root, 8)
	for tmp_28 in [Sem.mul(Sem.neg(v_width), 0.37), Sem.mul(v_width, 0.37)]:
		v_x = tmp_28
		v_f = gen_flange(Sem.add(v_name, "_Pipe_flange"), v_m, Sem.mul(0.19, v_s), v_root, 6)
		v_f.location = [v_x, 0, Sem.mul(0.6, v_s)]
		v_f.rotation_euler[1] = Sem.div(PI, 2)
	Geo.gen_cylinder(Sem.add(v_name, "_Valve_bell"), [Sem.mul(Sem.neg(0.12), v_s), 0, Sem.mul(0.75, v_s)], Sem.mul(0.22, v_s), Sem.mul(0.37, v_s), v_m["iron"], 8, v_root)
	Geo.gen_cylinder(Sem.add(v_name, "_Valve_collar"), [Sem.mul(Sem.neg(0.12), v_s), 0, Sem.mul(0.97, v_s)], Sem.mul(0.16, v_s), Sem.mul(0.1, v_s), v_m["gold"], 8, v_root)
	Geo.gen_cylinder(Sem.add(v_name, "_Spindle"), [Sem.mul(Sem.neg(0.12), v_s), 0, Sem.mul(1.1, v_s)], Sem.mul(0.055, v_s), Sem.mul(0.24, v_s), v_m["gold"], 8, v_root)
	v_wheel = Geo.gen_group(Sem.add(v_name, "_Wheel"), [Sem.mul(Sem.neg(0.12), v_s), 0, Sem.mul(1.24, v_s)], 0, v_root)
	gen_ring(Sem.add(v_name, "_Wheel_rim"), Sem.mul(0.34, v_s), Sem.mul(0.285, v_s), Sem.mul(0.055, v_s), v_m["brick_red"], v_wheel, 12)
	Geo.gen_cylinder(Sem.add(v_name, "_Wheel_hub"), [0, 0, 0], Sem.mul(0.09, v_s), Sem.mul(0.075, v_s), v_m["gold"], 8, v_wheel)
	for tmp_29 in range(5):
		v_j = tmp_29
		v_a = Sem.div(Sem.mul(Sem.mul(2, PI), v_j), 5)
		Geo.gen_beam(Sem.add(v_name, Sem.mod("_Wheel_spoke_%d", v_j)), [0, 0, 0], [Sem.mul(Sem.mul(0.29, v_s), cos(v_a)), Sem.mul(Sem.mul(0.29, v_s), sin(v_a)), 0], Sem.mul(0.032, v_s), Sem.mul(0.03, v_s), v_m["brick_red"], v_wheel, 0.003)
	v_g = gen_gauge(Sem.add(v_name, "_Pressure"), v_m, Sem.mul(0.17, v_s), 35, v_root)
	v_g.location = [Sem.mul(0.44, v_s), Sem.mul(Sem.neg(0.06), v_s), Sem.mul(1.26, v_s)]
	gen__cylinder_between(Sem.add(v_name, "_Gauge_stem"), [Sem.mul(0.44, v_s), 0, Sem.mul(0.65, v_s)], [Sem.mul(0.44, v_s), 0, Sem.mul(1.18, v_s)], Sem.mul(0.028, v_s), v_m["gold"], v_root, 8)
	Geo.gen_box(Sem.add(v_name, "_Mechanical_stop"), [Sem.mul(Sem.neg(0.12), v_s), Sem.mul(0.14, v_s), Sem.mul(1.01, v_s)], [Sem.mul(0.21, v_s), Sem.mul(0.08, v_s), Sem.mul(0.09, v_s)], v_m["iron_dark"], 0.01, v_root)
	v_root["visual_control_part"] = v_wheel.name
	v_root["binding_status"] = "unbound_candidate"
	return v_root

static func gen_control_console(v_name, v_mats, v_width = 2.3, v_depth = 0.95, v_height = 1.35, v_parent = null):
	var v_a = null
	var v_b = null
	var v_back = null
	var v_base = null
	var v_bolt = null
	var v_bottom = null
	var v_d = null
	var v_front = null
	var v_g = null
	var v_i = null
	var v_m = null
	var v_mat = null
	var v_perimeter = null
	var v_root = null
	var v_slope = null
	var v_top = null
	var v_vs = null
	var v_w = null
	var v_x = null
	var v_xx = null
	var v_y = null
	var v_z = null
	v_m = gen_material_set(v_mats)
	v_root = Geo.gen_group(v_name, [0, 0, 0], 0, v_parent)
	v_bottom = 0.12
	v_front = Sem.mul(v_height, 0.56)
	v_back = v_height
	v_d = Sem.div(v_depth, 2)
	v_w = Sem.div(v_width, 2)
	v_vs = [[Sem.neg(v_w), Sem.neg(v_d), v_bottom], [v_w, Sem.neg(v_d), v_bottom], [v_w, v_d, v_bottom], [Sem.neg(v_w), v_d, v_bottom], [Sem.neg(v_w), Sem.neg(v_d), v_front], [v_w, Sem.neg(v_d), v_front], [v_w, v_d, v_back], [Sem.neg(v_w), v_d, v_back]]
	Geo.gen_mesh(Sem.add(v_name, "_Closed_cabinet"), v_vs, [[3, 2, 1, 0], [0, 1, 5, 4], [1, 2, 6, 5], [2, 3, 7, 6], [3, 0, 4, 7], [4, 5, 6, 7]], v_m["iron"], v_root, 0.018)
	Geo.gen_box(Sem.add(v_name, "_Foot"), [0, 0, 0.08], [Sem.add(v_width, 0.12), Sem.add(v_depth, 0.08), 0.16], v_m["iron_dark"], 0.015, v_root)
	for tmp_30 in [Sem.mul(Sem.neg(v_width), 0.25), Sem.mul(v_width, 0.25)]:
		v_x = tmp_30
		Geo.gen_box(Sem.add(v_name, "_Service_panel"), [v_x, Sem.sub(Sem.neg(v_d), 0.016), Sem.mul(v_front, 0.48)], [Sem.mul(v_width, 0.44), 0.035, Sem.mul(v_front, 0.65)], v_m["wood"], 0.008, v_root)
		for tmp_31 in [Sem.mul(Sem.neg(v_width), 0.18), Sem.mul(v_width, 0.18)]:
			v_xx = tmp_31
			for tmp_32 in [Sem.mul(v_front, 0.22), Sem.mul(v_front, 0.72)]:
				v_z = tmp_32
				v_bolt = Geo.gen_cylinder(Sem.add(v_name, "_Panel_bolt"), [Sem.add(v_x, v_xx), Sem.sub(Sem.neg(v_d), 0.045), v_z], 0.023, 0.02, v_m["gold"], 6, v_root)
				v_bolt.rotation_euler[0] = Sem.div(PI, 2)
	v_slope = Sem.div(Sem.sub(v_back, v_front), v_depth)
	v_top = func(tmp_33):
		return Sem.add(v_front, Sem.mul(Sem.add(tmp_33, v_d), v_slope))
	v_perimeter = [[Sem.neg(v_w), Sem.neg(v_d), Sem.add(v_front, 0.025)], [v_w, Sem.neg(v_d), Sem.add(v_front, 0.025)], [v_w, v_d, Sem.add(v_back, 0.025)], [Sem.neg(v_w), v_d, Sem.add(v_back, 0.025)]]
	for tmp_34 in Sem.py_zip(v_perimeter, Sem.add(Sem.slice_array(v_perimeter, 1, null, null), Sem.slice_array(v_perimeter, null, 1, null))):
		var tmp_35 = tmp_34
		v_a = tmp_35[0]
		v_b = tmp_35[1]
		Geo.gen_beam(Sem.add(v_name, "_Deck_edge"), v_a, v_b, 0.035, 0.035, v_m["gold"], v_root, 0.004)
	for tmp_36 in range(3):
		v_i = tmp_36
		v_x = Sem.mul(Sem.mul(Sem.sub(v_i, 1), v_width), 0.27)
		v_y = Sem.mul(0.14, v_depth)
		v_g = gen_gauge(Sem.add(v_name, Sem.mod("_Gauge_%d", v_i)), v_m, Sem.mul(v_width, 0.083), Sem.add(25, Sem.mul(v_i, 35)), v_root)
		v_g.location = [v_x, v_y, Sem.add(v_top.call(v_y), 0.04)]
		v_g.rotation_euler[0] = Sem.neg(atan2(1, v_slope))
		v_base = Geo.gen_box(Sem.add(v_name, "_Lever_base"), [v_x, Sem.mul(Sem.neg(v_depth), 0.27), Sem.add(v_top.call(Sem.mul(Sem.neg(v_depth), 0.27)), 0.02)], [0.13, 0.15, 0.045], v_m["gold"], 0.005, v_root)
		v_base.rotation_euler[0] = atan(v_slope)
		v_a = [v_x, Sem.mul(Sem.neg(v_depth), 0.27), Sem.add(v_top.call(Sem.mul(Sem.neg(v_depth), 0.27)), 0.05)]
		v_b = [v_x, Sem.mul(Sem.neg(v_depth), 0.37), Sem.add(v_top.call(Sem.mul(Sem.neg(v_depth), 0.27)), 0.24)]
		Geo.gen_beam(Sem.add(v_name, Sem.mod("_Lever_%d", v_i)), v_a, v_b, 0.033, 0.033, v_m["gold"], v_root, 0.004)
		Geo.gen_ico(Sem.add(v_name, Sem.mod("_Lever_knob_%d", v_i)), v_b, 0.055, v_m["wood_light"], 1, v_root)
	for tmp_37 in Sem.py_enumerate([v_m["brick_red"], v_m["book_green"]]):
		var tmp_38 = tmp_37
		v_i = tmp_38[0]
		v_mat = tmp_38[1]
		Geo.gen_ico(Sem.add(v_name, Sem.mod("_Indicator_%d", v_i)), [Sem.mul(Sem.neg(v_width), 0.4), Sem.mul(Sem.neg(v_depth), 0.07), Sem.add(Sem.add(v_top.call(Sem.mul(Sem.neg(v_depth), 0.07)), 0.055), Sem.mul(v_i, 0.09))], 0.045, v_mat, 1, v_root)
	return v_root

static func gen_reaction_vessel(v_name, v_mats, v_radius = 0.72, v_height = 2.7, v_parent = null):
	var v_a = null
	var v_band = null
	var v_glow = null
	var v_h = null
	var v_i = null
	var v_m = null
	var v_p = null
	var v_profile = null
	var v_r = null
	var v_root = null
	var v_rr = null
	var v_x = null
	var v_y = null
	var v_z = null
	v_m = gen_material_set(v_mats)
	v_root = Geo.gen_group(v_name, [0, 0, 0], 0, v_parent)
	var tmp_39 = [v_radius, v_height]
	v_r = tmp_39[0]
	v_h = tmp_39[1]
	v_profile = [[0, 0.2], [Sem.mul(v_r, 0.65), 0.2], [Sem.mul(v_r, 0.9), 0.45], [v_r, 0.64], [v_r, Sem.mul(v_h, 0.71)], [Sem.mul(v_r, 0.83), Sem.mul(v_h, 0.82)], [Sem.mul(v_r, 0.32), Sem.mul(v_h, 0.9)], [Sem.mul(v_r, 0.22), Sem.mul(v_h, 0.91)], [0, Sem.mul(v_h, 0.91)]]
	Geo.gen_lathe(Sem.add(v_name, "_Faceted_vessel"), v_profile, 10, v_m["iron"], v_root, [0, 0, 0])
	for tmp_40 in [[0.58, Sem.mul(v_r, 1.03)], [Sem.mul(v_h, 0.46), Sem.mul(v_r, 1.04)], [Sem.mul(v_h, 0.72), Sem.mul(v_r, 1.02)]]:
		var tmp_41 = tmp_40
		v_z = tmp_41[0]
		v_rr = tmp_41[1]
		v_band = gen_ring(Sem.add(v_name, "_Band"), v_rr, Sem.mul(v_rr, 0.94), 0.1, v_m["gold"], v_root, 10)
		v_band.location[2] = v_z
		for tmp_42 in range(10):
			v_i = tmp_42
			v_a = Sem.add(Sem.div(Sem.mul(Sem.mul(2, PI), v_i), 10), Sem.div(PI, 8))
			v_p = Sem.vector([Sem.mul(v_rr, cos(v_a)), Sem.mul(v_rr, sin(v_a)), v_z])
			gen__cylinder_between(Sem.add(v_name, "_Band_bolt"), v_p, Sem.add(v_p, Sem.mul(Sem.vector([cos(v_a), sin(v_a), 0]), 0.04)), 0.03, v_m["iron_dark"], v_root, 6)
	for tmp_43 in [[Sem.neg(0.52), Sem.neg(0.4)], [0.52, Sem.neg(0.4)], [Sem.neg(0.52), 0.4], [0.52, 0.4]]:
		var tmp_44 = tmp_43
		v_x = tmp_44[0]
		v_y = tmp_44[1]
		Geo.gen_beam(Sem.add(v_name, "_Leg"), [v_x, v_y, 0.1], [Sem.mul(v_x, 0.8), Sem.mul(v_y, 0.8), 0.72], 0.16, 0.16, v_m["iron"], v_root, 0.01)
		Geo.gen_box(Sem.add(v_name, "_Leg_foot"), [v_x, v_y, 0.08], [0.28, 0.28, 0.16], v_m["iron_dark"], 0.015, v_root)
	Geo.gen_cylinder(Sem.add(v_name, "_Chimney"), [0, 0, Sem.mul(v_h, 0.98)], Sem.mul(v_r, 0.2), Sem.mul(v_h, 0.2), v_m["iron_dark"], 8, v_root)
	Geo.gen_cylinder(Sem.add(v_name, "_Chimney_cap"), [0, 0, Sem.mul(v_h, 1.085)], Sem.mul(v_r, 0.28), 0.08, v_m["gold"], 8, v_root)
	Geo.gen_box(Sem.add(v_name, "_Inspection_frame"), [0, Sem.mul(Sem.neg(v_r), 0.98), Sem.mul(v_h, 0.46)], [Sem.mul(v_r, 0.83), 0.09, Sem.mul(v_h, 0.24)], v_m["gold"], 0.03, v_root)
	v_glow = Geo.gen_box(Sem.add(v_name, "_Inspection_glow"), [0, Sem.mul(Sem.neg(v_r), 1.05), Sem.mul(v_h, 0.46)], [Sem.mul(v_r, 0.66), 0.025, Sem.mul(v_h, 0.19)], v_m["emission"], 0.015, v_root)
	if Sem.truth((v_glow is Dictionary and v_glow.has("visible_shadow"))):
		v_glow.visible_shadow = false
	for tmp_45 in [Sem.mul(Sem.neg(v_r), 0.21), 0, Sem.mul(v_r, 0.21)]:
		v_x = tmp_45
		Geo.gen_box(Sem.add(v_name, "_Inspection_bar"), [v_x, Sem.mul(Sem.neg(v_r), 1.08), Sem.mul(v_h, 0.46)], [0.035, 0.035, Sem.mul(v_h, 0.21)], v_m["iron"], 0.003, v_root)
	Geo.gen_box(Sem.add(v_name, "_Inspection_cross"), [0, Sem.mul(Sem.neg(v_r), 1.08), Sem.mul(v_h, 0.46)], [Sem.mul(v_r, 0.72), 0.035, 0.035], v_m["iron"], 0.003, v_root)
	load("res://tools/building_construction/BuildingConstruction/Lighting/LightingRecipes.gd").gen__light(Sem.add(v_name, "_Inspection_practical"), v_root, [0, Sem.mul(Sem.neg(v_r), 1.12), Sem.mul(v_h, 0.46)], "POINT", 8, [1.0, 0.72, 0.4], 0.15, null)
	return v_root

static func gen_caged_lamp(v_name, v_mats, v_height = 0.5, v_light_energy = 22, v_parent = null):
	var v_a = null
	var v_band = null
	var v_core = null
	var v_j = null
	var v_m = null
	var v_root = null
	var v_s = null
	var v_x = null
	var v_y = null
	var v_z = null
	v_m = gen_material_set(v_mats)
	v_root = Geo.gen_group(v_name, [0, 0, 0], 0, v_parent)
	v_s = Sem.div(v_height, 0.5)
	Geo.gen_box(Sem.add(v_name, "_Backplate"), [0, 0.025, 0], [Sem.mul(0.13, v_s), Sem.mul(0.06, v_s), Sem.mul(0.34, v_s)], v_m["iron"], Sem.mul(0.015, v_s), v_root)
	Geo.gen_beam(Sem.add(v_name, "_Bracket"), [0, 0, Sem.mul(0.15, v_s)], [0, Sem.mul(Sem.neg(0.2), v_s), Sem.mul(0.15, v_s)], Sem.mul(0.04, v_s), Sem.mul(0.04, v_s), v_m["gold"], v_root, 0.004)
	Geo.gen_lathe(Sem.add(v_name, "_Cap"), [[0, Sem.mul(0.18, v_s)], [Sem.mul(0.14, v_s), Sem.mul(0.18, v_s)], [Sem.mul(0.14, v_s), Sem.mul(0.23, v_s)], [Sem.mul(0.06, v_s), Sem.mul(0.28, v_s)], [0, Sem.mul(0.28, v_s)]], 8, v_m["gold"], v_root, [0, Sem.mul(Sem.neg(0.2), v_s), 0])
	v_core = Geo.gen_cylinder(Sem.add(v_name, "_Glow"), [0, Sem.mul(Sem.neg(0.2), v_s), Sem.mul(Sem.neg(0.025), v_s)], Sem.mul(0.1, v_s), Sem.mul(0.34, v_s), v_m["emission"], 8, v_root)
	if Sem.truth((v_core is Dictionary and v_core.has("visible_shadow"))):
		v_core.visible_shadow = false
	for tmp_46 in range(6):
		v_j = tmp_46
		v_a = Sem.div(Sem.mul(Sem.mul(v_j, 2), PI), 6)
		v_x = Sem.mul(Sem.mul(0.125, v_s), cos(v_a))
		v_y = Sem.add(Sem.mul(Sem.neg(0.2), v_s), Sem.mul(Sem.mul(0.125, v_s), sin(v_a)))
		Geo.gen_beam(Sem.add(v_name, Sem.mod("_Cage_%d", v_j)), [v_x, v_y, Sem.mul(Sem.neg(0.22), v_s)], [v_x, v_y, Sem.mul(0.17, v_s)], Sem.mul(0.018, v_s), Sem.mul(0.018, v_s), v_m["gold"], v_root, 0.002)
	for tmp_47 in [Sem.mul(Sem.neg(0.22), v_s), Sem.mul(Sem.neg(0.05), v_s), Sem.mul(0.16, v_s)]:
		v_z = tmp_47
		v_band = gen_ring(Sem.add(v_name, "_Cage_band"), Sem.mul(0.14, v_s), Sem.mul(0.12, v_s), Sem.mul(0.022, v_s), v_m["gold"], v_root, 8)
		v_band.location = [0, Sem.mul(Sem.neg(0.2), v_s), v_z]
	Geo.gen_cylinder(Sem.add(v_name, "_Base"), [0, Sem.mul(Sem.neg(0.2), v_s), Sem.mul(Sem.neg(0.24), v_s)], Sem.mul(0.14, v_s), Sem.mul(0.045, v_s), v_m["gold"], 8, v_root)
	load("res://tools/building_construction/BuildingConstruction/Lighting/LightingRecipes.gd").gen__light(Sem.add(v_name, "_Light"), v_root, [0, Sem.mul(Sem.neg(0.24), v_s), Sem.mul(Sem.neg(0.02), v_s)], "POINT", v_light_energy, [1.0, 0.72, 0.4], Sem.mul(0.11, v_s), null)
	return v_root

static func gen_indicator_board(v_name, v_mats, v_width = 0.4, v_height = 1.25, v_kind = "flood", v_parent = null):
	var v_colors = null
	var v_i = null
	var v_m = null
	var v_root = null
	var v_tri = null
	v_m = gen_material_set(v_mats)
	v_root = Geo.gen_group(v_name, [0, 0, 0], 0, v_parent)
	Geo.gen_box(Sem.add(v_name, "_Frame"), [0, 0, Sem.div(v_height, 2)], [v_width, 0.08, v_height], v_m["gold"], 0.015, v_root)
	Geo.gen_box(Sem.add(v_name, "_Face"), [0, Sem.neg(0.05), Sem.div(v_height, 2)], [Sem.mul(v_width, 0.79), 0.025, Sem.mul(v_height, 0.9)], v_m["cream"], 0.006, v_root)
	v_colors = [v_m["book_green"], v_m["gold"], v_m["brick_red"]]
	for tmp_48 in range(3):
		v_i = tmp_48
		Geo.gen_box(Sem.add(v_name, Sem.mod("_Level_%d", v_i)), [0, Sem.neg(0.069), Sem.mul(v_height, Sem.add(0.19, Sem.mul(v_i, 0.3)))], [Sem.mul(v_width, 0.58), 0.018, Sem.mul(v_height, 0.26)], v_colors[v_i], 0.002, v_root)
	for tmp_49 in range(9):
		v_i = tmp_49
		Geo.gen_box(Sem.add(v_name, Sem.mod("_Graduation_%02d", v_i)), [Sem.mul(Sem.neg(v_width), 0.18), Sem.neg(0.085), Sem.mul(v_height, Sem.add(0.08, Sem.mul(0.1, v_i)))], [Sem.mul(v_width, (0.2 if Sem.truth(((Sem.mod(v_i, 3) == 0))) else 0.1)), 0.009, 0.014], v_m["iron_dark"], 0, v_root)
	if Sem.truth(((v_kind == "warning"))):
		v_tri = Geo.gen_polyprism(Sem.add(v_name, "_Warning_triangle"), [[Sem.mul(Sem.neg(v_width), 0.28), Sem.mul(Sem.neg(v_height), 0.12)], [Sem.mul(v_width, 0.28), Sem.mul(Sem.neg(v_height), 0.12)], [0, Sem.mul(v_height, 0.13)]], 0, 0.02, v_m["gold"], v_root)
		v_tri.rotation_euler[0] = Sem.div(PI, 2)
		v_tri.location = [0, Sem.neg(0.095), Sem.mul(v_height, 0.56)]
		Geo.gen_box(Sem.add(v_name, "_Exclamation"), [0, Sem.neg(0.125), Sem.mul(v_height, 0.57)], [0.028, 0.015, Sem.mul(v_height, 0.14)], v_m["iron_dark"], 0.001, v_root)
		Geo.gen_ico(Sem.add(v_name, "_Dot"), [0, Sem.neg(0.125), Sem.mul(v_height, 0.46)], 0.022, v_m["iron_dark"], 1, v_root)
	v_root["visual_indicator_only"] = true
	return v_root

static func gen_schematic(v_name, v_mats, v_width = 2.2, v_height = 1.05, v_parent = null):
	var v_a = null
	var v_b = null
	var v_m = null
	var v_points = null
	var v_r = null
	var v_root = null
	var v_x = null
	var v_z = null
	v_m = gen_material_set(v_mats)
	v_root = Geo.gen_group(v_name, [0, 0, 0], 0, v_parent)
	Geo.gen_box(Sem.add(v_name, "_Board"), [0, 0, 0], [v_width, 0.07, v_height], v_m["cream"], 0.006, v_root)
	for tmp_50 in [Sem.div(Sem.neg(v_width), 2), Sem.div(v_width, 2)]:
		v_x = tmp_50
		Geo.gen_box(Sem.add(v_name, "_Side"), [v_x, Sem.neg(0.045), 0], [0.065, 0.06, Sem.add(v_height, 0.07)], v_m["wood"], 0.005, v_root)
	for tmp_51 in [Sem.div(Sem.neg(v_height), 2), Sem.div(v_height, 2)]:
		v_z = tmp_51
		Geo.gen_box(Sem.add(v_name, "_Edge"), [0, Sem.neg(0.045), v_z], [Sem.add(v_width, 0.07), 0.06, 0.065], v_m["wood"], 0.005, v_root)
	v_points = [[Sem.mul(Sem.neg(0.32), v_width), Sem.neg(0.085), Sem.mul(Sem.neg(0.24), v_height)], [Sem.mul(Sem.neg(0.32), v_width), Sem.neg(0.085), Sem.mul(0.24, v_height)], [Sem.mul(Sem.neg(0.1), v_width), Sem.neg(0.085), Sem.mul(0.24, v_height)], [Sem.mul(Sem.neg(0.1), v_width), Sem.neg(0.085), Sem.mul(0.12, v_height)], [Sem.mul(0.34, v_width), Sem.neg(0.085), Sem.mul(0.12, v_height)]]
	for tmp_52 in Sem.py_zip(v_points, Sem.slice_array(v_points, 1, null, null)):
		var tmp_53 = tmp_52
		v_a = tmp_53[0]
		v_b = tmp_53[1]
		Geo.gen_beam(Sem.add(v_name, "_Printed_pipe"), v_a, v_b, 0.022, 0.012, v_m["wood"], v_root, 0.001)
	for tmp_54 in [Sem.mul(0.04, v_width), Sem.mul(0.2, v_width), Sem.mul(0.34, v_width)]:
		v_x = tmp_54
		Geo.gen_beam(Sem.add(v_name, "_Branch"), [v_x, Sem.neg(0.085), Sem.mul(0.12, v_height)], [v_x, Sem.neg(0.085), Sem.mul(Sem.neg(0.2), v_height)], 0.02, 0.012, v_m["wood"], v_root, 0.001)
		v_r = gen_ring(Sem.add(v_name, "_Symbol"), Sem.mul(v_height, 0.075), Sem.mul(v_height, 0.056), 0.012, v_m["wood"], v_root, 10)
		v_r.rotation_euler[0] = Sem.div(PI, 2)
		v_r.location = [v_x, Sem.neg(0.09), Sem.mul(Sem.neg(0.27), v_height)]
	return v_root

static func gen_pallet(v_name, v_mats, v_width = 1.5, v_depth = 1.1, v_parent = null):
	var v_i = null
	var v_n = null
	var v_root = null
	var v_x = null
	v_root = Geo.gen_group(v_name, [0, 0, 0], 0, v_parent)
	for tmp_55 in [Sem.mul(Sem.neg(v_width), 0.37), 0, Sem.mul(v_width, 0.37)]:
		v_x = tmp_55
		Geo.gen_box(Sem.add(v_name, "_Runner"), [v_x, 0, 0.08], [0.12, v_depth, 0.16], v_mats["wood_dark"], 0.008, v_root)
	v_n = Sem.py_max(4, ceili(Sem.div(v_depth, 0.16)))
	for tmp_56 in range(v_n):
		v_i = tmp_56
		Geo.gen_box(Sem.add(v_name, Sem.mod("_Slat_%02d", v_i)), [0, Sem.add(Sem.div(Sem.neg(v_depth), 2), Sem.div(Sem.mul(Sem.add(v_i, 0.5), v_depth), v_n)), 0.19], [v_width, Sem.sub(Sem.div(v_depth, v_n), 0.025), 0.08], v_mats["wood"], 0.007, v_root)
	return v_root

static func gen_storage_rack(v_name, v_mats, v_width = 2.6, v_depth = 0.85, v_height = 2.5, v_parent = null):
	var v_bag = null
	var v_cap = null
	var v_count = null
	var v_i = null
	var v_m = null
	var v_root = null
	var v_x = null
	var v_y = null
	var v_z = null
	v_root = Geo.gen_group(v_name, [0, 0, 0], 0, v_parent)
	v_m = gen_material_set(v_mats)
	for tmp_57 in [Sem.div(Sem.neg(v_width), 2), Sem.div(v_width, 2)]:
		v_x = tmp_57
		for tmp_58 in [Sem.div(Sem.neg(v_depth), 2), Sem.div(v_depth, 2)]:
			v_y = tmp_58
			Geo.gen_box(Sem.add(v_name, "_Post"), [v_x, v_y, Sem.div(v_height, 2)], [0.12, 0.12, v_height], v_m["wood"], 0.012, v_root)
		Geo.gen_beam(Sem.add(v_name, "_Brace"), [v_x, Sem.div(Sem.neg(v_depth), 2), 0.22], [v_x, Sem.div(v_depth, 2), Sem.sub(v_height, 0.18)], 0.08, 0.08, v_m["wood_dark"], v_root, 0.006)
	for tmp_59 in [0.22, Sem.mul(v_height, 0.53)]:
		v_z = tmp_59
		Geo.gen_box(Sem.add(v_name, "_Shelf"), [0, 0, v_z], [Sem.add(v_width, 0.12), Sem.add(v_depth, 0.08), 0.11], v_m["wood_light"], 0.01, v_root)
		Geo.gen_box(Sem.add(v_name, "_Front_rail"), [0, Sem.sub(Sem.div(Sem.neg(v_depth), 2), 0.02), Sem.sub(v_z, 0.07)], [Sem.add(v_width, 0.12), 0.08, 0.16], v_m["wood"], 0.007, v_root)
		v_count = Sem.py_max(2, int(Sem.div(v_width, 0.55)))
		for tmp_60 in range(v_count):
			v_i = tmp_60
			v_bag = load("res://tools/building_construction/BuildingConstruction/Props/SpecialRecipes.gd").gen_sacks(Sem.add(v_name, Sem.mod("_Grain_%d_%d", [int(Sem.mul(v_z, 100)), v_i])), v_m, 1, v_root)
			v_bag.location = [Sem.add(Sem.add(Sem.mul(Sem.neg(v_width), 0.4), Sem.mul(v_i, Sem.div(Sem.mul(v_width, 0.8), Sem.py_max(1, Sem.sub(v_count, 1))))), 0.24), Sem.neg(0.1), Sem.add(v_z, 0.06)]
	for tmp_61 in [Sem.div(Sem.neg(v_width), 2), Sem.div(v_width, 2)]:
		v_x = tmp_61
		for tmp_62 in [0.22, Sem.mul(v_height, 0.53)]:
			v_z = tmp_62
			v_cap = Geo.gen_cylinder(Sem.add(v_name, "_Fixing"), [v_x, Sem.sub(Sem.div(Sem.neg(v_depth), 2), 0.07), v_z], 0.035, 0.02, v_m["gold"], 6, v_root)
			v_cap.rotation_euler[0] = Sem.div(PI, 2)
	return v_root

static func gen_barrel(v_name, v_mats, v_radius = 0.4, v_height = 0.95, v_parent = null):
	var v_band = null
	var v_m = null
	var v_root = null
	var v_x = null
	var v_y = null
	var v_z = null
	v_root = Geo.gen_group(v_name, [0, 0, 0], 0, v_parent)
	v_m = gen_material_set(v_mats)
	Geo.gen_lathe(Sem.add(v_name, "_Staves"), [[Sem.mul(v_radius, 0.82), 0], [v_radius, Sem.mul(0.18, v_height)], [Sem.mul(v_radius, 1.05), Sem.mul(v_height, 0.5)], [v_radius, Sem.mul(v_height, 0.82)], [Sem.mul(v_radius, 0.82), v_height]], 10, v_m["wood_light"], v_root, [0, 0, 0])
	for tmp_63 in [Sem.mul(v_height, 0.15), Sem.mul(v_height, 0.79)]:
		v_z = tmp_63
		v_band = gen_ring(Sem.add(v_name, "_Hoop"), Sem.mul(v_radius, 1.045), Sem.mul(v_radius, 0.98), 0.07, v_m["gold"], v_root, 10)
		v_band.location[2] = v_z
	Geo.gen_cylinder(Sem.add(v_name, "_Lid"), [0, 0, Sem.add(v_height, 0.01)], Sem.mul(v_radius, 0.83), 0.035, v_m["wood"], 10, v_root)
	for tmp_64 in [Sem.mul(Sem.neg(v_radius), 0.38), 0, Sem.mul(v_radius, 0.38)]:
		v_y = tmp_64
		v_x = sqrt(Sem.sub(Sem.power(Sem.mul(v_radius, 0.8), 2), Sem.mul(v_y, v_y)))
		Geo.gen_box(Sem.add(v_name, "_Lid_joint"), [0, v_y, Sem.add(v_height, 0.03)], [Sem.mul(v_x, 2), 0.012, 0.008], v_m["wood_dark"], 0, v_root)
	return v_root

static func gen_handcart(v_name, v_mats, v_width = 1.1, v_length = 1.6, v_parent = null):
	var v_a = null
	var v_j = null
	var v_m = null
	var v_root = null
	var v_sacks = null
	var v_wheel = null
	var v_x = null
	var v_y = null
	v_root = Geo.gen_group(v_name, [0, 0, 0], 0, v_parent)
	v_m = gen_material_set(v_mats)
	Geo.gen_box(Sem.add(v_name, "_Bed"), [0, 0, 0.48], [v_width, v_length, 0.12], v_m["wood"], 0.015, v_root)
	for tmp_65 in [Sem.div(Sem.neg(v_width), 2), Sem.div(v_width, 2)]:
		v_x = tmp_65
		Geo.gen_box(Sem.add(v_name, "_Side"), [v_x, 0, 0.71], [0.065, v_length, 0.38], v_m["wood_light"], 0.008, v_root)
		for tmp_66 in [Sem.mul(Sem.neg(v_length), 0.42), Sem.mul(v_length, 0.42)]:
			v_y = tmp_66
			Geo.gen_box(Sem.add(v_name, "_Stake"), [v_x, v_y, 0.77], [0.09, 0.09, 0.65], v_m["wood"], 0.008, v_root)
		Geo.gen_beam(Sem.add(v_name, "_Handle"), [v_x, Sem.mul(Sem.neg(v_length), 0.34), 0.45], [v_x, Sem.mul(Sem.neg(v_length), 1.08), 0.19], 0.07, 0.07, v_m["wood"], v_root, 0.008)
		v_wheel = Geo.gen_group(Sem.add(v_name, "_Wheel"), [Sem.add(v_x, Sem.copysign(0.1, v_x)), 0.12, 0.34], 0, v_root)
		v_wheel.rotation_euler[1] = Sem.div(PI, 2)
		gen_ring(Sem.add(v_name, "_Rim"), 0.34, 0.28, 0.08, v_m["wood"], v_wheel, 12)
		Geo.gen_cylinder(Sem.add(v_name, "_Hub"), [0, 0, 0], 0.09, 0.13, v_m["gold"], 8, v_wheel)
		for tmp_67 in range(8):
			v_j = tmp_67
			v_a = Sem.div(Sem.mul(v_j, PI), 4)
			Geo.gen_beam(Sem.add(v_name, "_Spoke"), [0, 0, 0], [Sem.mul(0.29, cos(v_a)), Sem.mul(0.29, sin(v_a)), 0], 0.04, 0.045, v_m["wood_light"], v_wheel, 0.003)
	for tmp_68 in [Sem.neg(0.35), 0.2]:
		v_y = tmp_68
		v_sacks = load("res://tools/building_construction/BuildingConstruction/Props/SpecialRecipes.gd").gen_sacks(Sem.add(v_name, "_Cargo"), v_m, 2, v_root)
		v_sacks.location = [0, v_y, 0.54]
	return v_root

static func gen_platform_scale(v_name, v_mats, v_width = 1.4, v_depth = 1.1, v_parent = null):
	var v_a = null
	var v_pan = null
	var v_root = null
	var v_x = null
	var v_y = null
	v_root = Geo.gen_group(v_name, [0, 0, 0], 0, v_parent)
	gen_pallet(Sem.add(v_name, "_Deck"), v_mats, v_width, v_depth, v_root)
	var tmp_69 = [Sem.mul(Sem.neg(v_width), 0.38), Sem.mul(v_depth, 0.29)]
	v_x = tmp_69[0]
	v_y = tmp_69[1]
	Geo.gen_box(Sem.add(v_name, "_Column"), [v_x, v_y, 0.87], [0.14, 0.14, 1.45], v_mats["wood"], 0.01, v_root)
	Geo.gen_box(Sem.add(v_name, "_Balance"), [Sem.add(v_x, 0.28), v_y, 1.61], [0.84, 0.09, 0.11], v_mats["gold"], 0.008, v_root)
	v_pan = Geo.gen_cylinder(Sem.add(v_name, "_Pan"), [Sem.add(v_x, 0.59), v_y, 1.05], 0.23, 0.035, v_mats["gold"], 8, v_root)
	for tmp_70 in [0, Sem.div(Sem.mul(2, PI), 3), Sem.div(Sem.mul(4, PI), 3)]:
		v_a = tmp_70
		Geo.gen_beam(Sem.add(v_name, "_Pan_hanger"), [Sem.add(v_x, 0.59), v_y, 1.57], [Sem.add(Sem.add(v_x, 0.59), Sem.mul(0.2, cos(v_a))), Sem.add(v_y, Sem.mul(0.2, sin(v_a))), 1.06], 0.012, 0.012, v_mats["gold"], v_root, 0.001)
	return v_root

static func gen_drain_grate(v_name, v_mats, v_width = 0.32, v_length = 4, v_parent = null):
	var v_i = null
	var v_m = null
	var v_root = null
	var v_x = null
	var v_y = null
	v_root = Geo.gen_group(v_name, [0, 0, 0], 0, v_parent)
	v_m = gen_material_set(v_mats)
	Geo.gen_box(Sem.add(v_name, "_Dark_trough"), [0, 0, Sem.neg(0.025)], [v_width, v_length, 0.05], v_m["iron_dark"], 0, v_root)
	for tmp_71 in [Sem.div(Sem.neg(v_width), 2), Sem.div(v_width, 2)]:
		v_x = tmp_71
		Geo.gen_box(Sem.add(v_name, "_Frame"), [v_x, 0, 0.012], [0.035, v_length, 0.035], v_m["gold"], 0.003, v_root)
	for tmp_72 in range(Sem.py_max(1, ceili(Sem.div(v_length, 0.11)))):
		v_i = tmp_72
		v_y = Sem.add(Sem.div(Sem.neg(v_length), 2), Sem.div(Sem.mul(Sem.add(v_i, 0.5), v_length), ceili(Sem.div(v_length, 0.11))))
		Geo.gen_box(Sem.add(v_name, Sem.mod("_Crossbar_%03d", v_i)), [0, v_y, 0.016], [v_width, 0.032, 0.04], v_m["iron"], 0.002, v_root)
	return v_root

static func gen_simple_rail(v_name, v_mats, v_points, v_height = 0.9, v_spacing = 0.8, v_parent = null, v_post_points = null):
	var v_a = null
	var v_b = null
	var v_i = null
	var v_m = null
	var v_p = null
	var v_pts = null
	var v_root = null
	var v_samples = null
	v_root = Geo.gen_group(v_name, [0, 0, 0], 0, v_parent)
	v_m = gen_material_set(v_mats)
	v_pts = load("res://tools/building_construction/BuildingConstruction/Shared/PathRecipes.gd").gen_clean_polyline(v_points, false)
	v_samples = (Sem.map_array(v_post_points, func(tmp_73): var tmp_74 = tmp_73; return Sem.py_tuple(tmp_74)) if Sem.truth(((v_post_points != null))) else load("res://tools/building_construction/BuildingConstruction/Shared/PathRecipes.gd").gen_resample_polyline(v_pts, v_spacing, null, false, true))
	for tmp_75 in Sem.py_enumerate(v_samples):
		var tmp_76 = tmp_75
		v_i = tmp_76[0]
		v_p = tmp_76[1]
		Geo.gen_beam(Sem.add(v_name, Sem.mod("_Post_%02d", v_i)), v_p, [v_p[0], v_p[1], Sem.add(v_p[2], v_height)], 0.055, 0.055, v_m["iron"], v_root, 0.006)
		Geo.gen_box(Sem.add(v_name, Sem.mod("_Foot_%02d", v_i)), [v_p[0], v_p[1], Sem.add(v_p[2], 0.025)], [0.12, 0.12, 0.05], v_m["iron_dark"], 0.008, v_root)
	for tmp_77 in Sem.py_zip(v_pts, Sem.slice_array(v_pts, 1, null, null)):
		var tmp_78 = tmp_77
		v_a = tmp_78[0]
		v_b = tmp_78[1]
		Geo.gen_beam(Sem.add(v_name, "_Top"), [v_a[0], v_a[1], Sem.add(v_a[2], v_height)], [v_b[0], v_b[1], Sem.add(v_b[2], v_height)], 0.07, 0.065, v_m["wood"], v_root, 0.008)
		Geo.gen_beam(Sem.add(v_name, "_Lower"), [v_a[0], v_a[1], Sem.add(v_a[2], 0.13)], [v_b[0], v_b[1], Sem.add(v_b[2], 0.13)], 0.035, 0.035, v_m["iron"], v_root, 0.004)
	return v_root

static func gen_ramp_module(v_name, v_mats, v_width = 3.1, v_length = 8.2, v_rise = 1.4, v_landing = 1.2, v_parent = null):
	var v_a = null
	var v_b = null
	var v_fs = null
	var v_i = null
	var v_m = null
	var v_n = null
	var v_path = null
	var v_profile = null
	var v_rail_path = null
	var v_root = null
	var v_vs = null
	var v_x = null
	var v_y = null
	var v_z = null
	var v_z_at = null
	if Sem.truth(Sem.either_lazy(((v_length <= Sem.mul(2, v_landing))), func(): return ((Sem.py_min(v_width, v_rise, v_landing) <= 0)))):
		push_error(str("Invalid ramp dimensions"))
		return null
	v_m = gen_material_set(v_mats)
	v_root = Geo.gen_group(v_name, [0, 0, 0], 0, v_parent)
	v_profile = [[0, Sem.neg(0.14)], [v_length, Sem.neg(0.14)], [v_length, v_rise], [Sem.sub(v_length, v_landing), v_rise], [v_landing, 0], [0, 0]]
	v_n = Sem.py_len(v_profile)
	v_vs = Sem.flat_map([Sem.div(Sem.neg(v_width), 2), Sem.div(v_width, 2)], func(tmp_79): var tmp_80 = tmp_79; return Sem.map_array(v_profile, func(tmp_81): var tmp_82 = tmp_81[0]; var tmp_83 = tmp_81[1]; return [tmp_80, tmp_82, tmp_83]))
	v_fs = [Sem.py_tuple(Sem.py_reversed(range(v_n))), Sem.py_tuple(range(v_n, Sem.mul(v_n, 2)))]
	v_fs = Sem.add(v_fs, Sem.map_array(range(v_n), func(tmp_84): var tmp_85 = tmp_84; return [tmp_85, Sem.mod(Sem.add(tmp_85, 1), v_n), Sem.add(Sem.mod(Sem.add(tmp_85, 1), v_n), v_n), Sem.add(tmp_85, v_n)]))
	Geo.gen_mesh(Sem.add(v_name, "_Continuous_solid"), v_vs, v_fs, v_m["masonry_light"], v_root, 0)
	v_z_at = func(tmp_86):
		return Sem.mul(v_rise, Sem.py_max(0, Sem.py_min(1, Sem.div(Sem.sub(tmp_86, v_landing), Sem.sub(v_length, Sem.mul(2, v_landing))))))
	for tmp_87 in range(1, 7):
		v_i = tmp_87
		v_y = Sem.add(v_landing, Sem.div(Sem.mul(v_i, Sem.sub(v_length, Sem.mul(2, v_landing))), 7))
		v_z = v_z_at.call(v_y)
		Geo.gen_box(Sem.add(v_name, Sem.mod("_Non_slip_strip_%d", v_i)), [0, v_y, Sem.add(v_z, 0.009)], [Sem.sub(v_width, 0.2), 0.035, 0.018], v_m["iron"], 0.002, v_root)
	for tmp_88 in [Sem.div(Sem.neg(v_width), 2), Sem.div(v_width, 2)]:
		v_x = tmp_88
		v_path = [[v_x, 0, 0], [v_x, v_landing, 0], [v_x, Sem.sub(v_length, v_landing), v_rise], [v_x, v_length, v_rise]]
		for tmp_89 in Sem.py_zip(v_path, Sem.slice_array(v_path, 1, null, null)):
			var tmp_90 = tmp_89
			v_a = tmp_90[0]
			v_b = tmp_90[1]
			Geo.gen_beam(Sem.add(v_name, "_Kerb"), [v_a[0], v_a[1], Sem.add(v_a[2], 0.05)], [v_b[0], v_b[1], Sem.add(v_b[2], 0.05)], 0.1, 0.1, v_m["masonry_dark"], v_root, 0.008)
	v_rail_path = [[Sem.sub(Sem.div(v_width, 2), 0.08), 0.18, 0], [Sem.sub(Sem.div(v_width, 2), 0.08), v_landing, 0], [Sem.sub(Sem.div(v_width, 2), 0.08), Sem.sub(v_length, v_landing), v_rise], [Sem.sub(Sem.div(v_width, 2), 0.08), Sem.sub(v_length, 0.18), v_rise]]
	gen_simple_rail(Sem.add(v_name, "_Handrail"), v_m, v_rail_path, 0.88, 0.9, v_root, null)
	v_root["generator"] = "continuous_ramp_v1"
	v_root["slope"] = Sem.div(v_rise, Sem.sub(v_length, Sem.mul(2, v_landing)))
	v_root["stair_steps"] = 0
	return v_root

static func gen_heavy_lock(v_name, v_mats, v_width = 0.22, v_parent = null):
	var v_key = null
	var v_m = null
	var v_root = null
	var v_s = null
	var v_shackle = null
	v_root = Geo.gen_group(v_name, [0, 0, 0], 0, v_parent)
	v_m = gen_material_set(v_mats)
	v_s = Sem.div(v_width, 0.22)
	Geo.gen_box(Sem.add(v_name, "_Body"), [0, Sem.neg(0.02), 0], [Sem.mul(0.22, v_s), Sem.mul(0.11, v_s), Sem.mul(0.25, v_s)], v_m["gold"], Sem.mul(0.025, v_s), v_root)
	v_shackle = gen_pipe_run(Sem.add(v_name, "_Shackle"), v_m, [[Sem.mul(Sem.neg(0.073), v_s), 0, Sem.mul(0.1, v_s)], [Sem.mul(Sem.neg(0.073), v_s), 0, Sem.mul(0.26, v_s)], [Sem.mul(0.073, v_s), 0, Sem.mul(0.26, v_s)], [Sem.mul(0.073, v_s), 0, Sem.mul(0.1, v_s)]], Sem.mul(0.023, v_s), 8, false, v_root)
	v_key = Geo.gen_cylinder(Sem.add(v_name, "_Keyhole"), [0, Sem.neg(0.082), Sem.mul(Sem.neg(0.01), v_s)], Sem.mul(0.026, v_s), 0.014, v_m["iron_dark"], 8, v_root)
	v_key.rotation_euler[0] = Sem.div(PI, 2)
	Geo.gen_box(Sem.add(v_name, "_Keyslot"), [0, Sem.neg(0.09), Sem.mul(Sem.neg(0.045), v_s)], [Sem.mul(0.022, v_s), 0.012, Sem.mul(0.045, v_s)], v_m["iron_dark"], 0.002, v_root)
	v_root["visual_lock_not_authoritative_state"] = true
	return v_root

static func gen_masonry_joints(v_name, v_mats, v_length, v_height, v_openings = [], v_brick_width = 1.08, v_row_height = 0.47, v_parent = null):
	var v_a = null
	var v_b = null
	var v_box_at = null
	var v_f = null
	var v_free_intervals = null
	var v_fs = null
	var v_hi = null
	var v_i = null
	var v_lo = null
	var v_m = null
	var v_new = null
	var v_o = null
	var v_root = null
	var v_row = null
	var v_rows = null
	var v_spans = null
	var v_start = null
	var v_vs = null
	var v_x = null
	var v_ys = null
	var v_z0 = null
	var v_z1 = null
	v_m = gen_material_set(v_mats)
	v_root = Geo.gen_group(v_name, [0, 0, 0], 0, v_parent)
	v_vs = []
	v_fs = []
	v_box_at = func(tmp_91, tmp_92, tmp_93, tmp_94):
		if Sem.truth(Sem.either_lazy(((Sem.sub(tmp_92, tmp_91) < 0.001)), func(): return ((Sem.sub(tmp_94, tmp_93) < 0.001)))):
			return null
		v_start = Sem.py_len(v_vs)
		v_ys = [Sem.neg(0.018), Sem.neg(0.006)]
		v_vs.append_array([[tmp_91, v_ys[0], tmp_93], [tmp_92, v_ys[0], tmp_93], [tmp_92, v_ys[1], tmp_93], [tmp_91, v_ys[1], tmp_93], [tmp_91, v_ys[0], tmp_94], [tmp_92, v_ys[0], tmp_94], [tmp_92, v_ys[1], tmp_94], [tmp_91, v_ys[1], tmp_94]])
		v_fs.append_array(Sem.map_array([[3, 2, 1, 0], [0, 1, 5, 4], [1, 2, 6, 5], [2, 3, 7, 6], [3, 0, 4, 7], [4, 5, 6, 7]], func(tmp_95): var tmp_96 = tmp_95; return Sem.py_tuple(Sem.map_array(tmp_96, func(tmp_97): var tmp_98 = tmp_97; return Sem.add(v_start, tmp_98)))))
	v_free_intervals = func(tmp_99):
		v_spans = [[0, v_length]]
		for tmp_100 in v_openings:
			v_o = tmp_100
			if Sem.truth(((Sem.sub(v_o.get("bottom", 0), 0.08) <= tmp_99) and (tmp_99 <= Sem.add(Sem.add(v_o.get("bottom", 0), v_o["height"]), 0.08)))):
				v_a = Sem.sub(Sem.sub(v_o["center"], Sem.div(v_o["width"], 2)), 0.12)
				v_b = Sem.add(Sem.add(v_o["center"], Sem.div(v_o["width"], 2)), 0.12)
				v_new = []
				for tmp_101 in v_spans:
					var tmp_102 = tmp_101
					v_lo = tmp_102[0]
					v_hi = tmp_102[1]
					if Sem.truth(Sem.either_lazy(((v_b <= v_lo)), func(): return ((v_a >= v_hi)))):
						v_new.append([v_lo, v_hi])
					else:
						if Sem.truth(((v_a > v_lo))):
							v_new.append([v_lo, Sem.py_min(v_a, v_hi)])
						if Sem.truth(((v_b < v_hi))):
							v_new.append([Sem.py_max(v_b, v_lo), v_hi])
				v_spans = v_new
		return v_spans
	v_rows = Sem.py_max(1, ceili(Sem.div(v_height, v_row_height)))
	for tmp_103 in range(v_rows):
		v_row = tmp_103
		v_z0 = Sem.mul(v_row, v_row_height)
		v_z1 = Sem.py_min(v_height, Sem.add(v_z0, v_row_height))
		if Sem.truth(((v_row > 0))):
			for tmp_104 in v_free_intervals.call(v_z0):
				var tmp_105 = tmp_104
				v_a = tmp_105[0]
				v_b = tmp_105[1]
				v_box_at.call(v_a, v_b, Sem.sub(v_z0, 0.006), Sem.add(v_z0, 0.006))
		v_x = Sem.mul(Sem.mul(Sem.mod(v_row, 2), v_brick_width), 0.5)
		while Sem.truth(((v_x < v_length))):
			if Sem.truth(Sem.both_lazy(((v_x > 0.08)), func(): return Sem.py_all(Sem.map_array(v_openings, func(tmp_106): var tmp_107 = tmp_106; return not Sem.truth(Sem.both_lazy(((Sem.sub(Sem.sub(tmp_107["center"], Sem.div(tmp_107["width"], 2)), 0.12) < v_x) and (v_x < Sem.add(Sem.add(tmp_107["center"], Sem.div(tmp_107["width"], 2)), 0.12))), func(): return Sem.both_lazy(((v_z0 < Sem.add(Sem.add(tmp_107.get("bottom", 0), tmp_107["height"]), 0.08))), func(): return ((v_z1 > Sem.sub(tmp_107.get("bottom", 0), 0.08)))))))))):
				v_box_at.call(Sem.sub(v_x, 0.006), Sem.add(v_x, 0.006), Sem.add(v_z0, 0.006), Sem.sub(v_z1, 0.006))
			v_x = Sem.add(v_x, v_brick_width)
	if Sem.truth(v_vs):
		Geo.gen_mesh(Sem.add(v_name, "_Real_joint_mesh"), v_vs, v_fs, v_m["masonry_dark"], v_root, 0)
	return v_root

