@tool
extends RefCounted

# Stair layout rules from kit/architecture.py. Z-up recipe coordinates convert at the geometry boundary.
const Sem = preload("res://tools/building_construction/BuildingConstruction/Shared/RecipeSemantics.gd")
const Geo = preload("res://tools/building_construction/BuildingConstruction/Shared/RecipeGeometry.gd")
const EPS = 1e-9

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
