@tool
extends RefCounted

# Direct port of kit/stair_exact.py. Z-up recipe coordinates convert at the geometry boundary.
const Sem = preload("res://tools/building_construction/BuildingConstruction/Shared/RecipeSemantics.gd")
const Geo = preload("res://tools/building_construction/BuildingConstruction/Shared/RecipeGeometry.gd")
const EPS = 1e-9

static func gen__profile_mesh(v_profile, v_width):
	var v_faces = null
	var v_i = null
	var v_n = null
	var v_vertices = null
	var v_x = null
	var v_z = null
	v_n = Sem.py_len(v_profile)
	v_vertices = Sem.map_array(v_profile, func(tmp_1): var tmp_2 = tmp_1[0]; var tmp_3 = tmp_1[1]; return [tmp_2, Sem.div(Sem.neg(v_width), 2), tmp_3])
	v_vertices = Sem.add(v_vertices, Sem.map_array(v_profile, func(tmp_4): var tmp_5 = tmp_4[0]; var tmp_6 = tmp_4[1]; return [tmp_5, Sem.div(v_width, 2), tmp_6]))
	v_faces = [Sem.py_tuple(Sem.py_reversed(range(v_n))), Sem.py_tuple(range(v_n, Sem.mul(2, v_n)))]
	v_faces = Sem.add(v_faces, Sem.map_array(range(v_n), func(tmp_7): var tmp_8 = tmp_7; return [tmp_8, Sem.mod(Sem.add(tmp_8, 1), v_n), Sem.add(Sem.mod(Sem.add(tmp_8, 1), v_n), v_n), Sem.add(tmp_8, v_n)]))
	return [v_vertices, v_faces]

static func gen_flight_spec(v_start, v_end, v_width, v_risers = 10):
	var v_a = null
	var v_anchors = null
	var v_angle = null
	var v_b = null
	var v_cap = null
	var v_dx = null
	var v_dy = null
	var v_i = null
	var v_key = null
	var v_lateral = null
	var v_local = null
	var v_n = null
	var v_p = null
	var v_parent_point = null
	var v_profile = null
	var v_rails = null
	var v_rise = null
	var v_riser = null
	var v_run = null
	var v_side = null
	var v_tread = null
	var v_tread_count = null
	var v_ux = null
	var v_uy = null
	var v_value = null
	var v_waist = null
	var v_x = null
	var v_x0 = null
	var v_x1 = null
	var v_y = null
	var v_z = null
	var tmp_9 = [load("res://tools/building_construction/BuildingConstruction/Shared/PathRecipes.gd").gen_point3(v_start), load("res://tools/building_construction/BuildingConstruction/Shared/PathRecipes.gd").gen_point3(v_end)]
	v_a = tmp_9[0]
	v_b = tmp_9[1]
	v_width = float(v_width)
	if Sem.truth(Sem.either_lazy((v_risers is Dictionary), func(): return Sem.either_lazy(((int(v_risers) != v_risers)), func(): return ((int(v_risers) < 2))))):
		push_error(str("A flight needs an integer riser count of at least two"))
		return null
	v_n = int(v_risers)
	if Sem.truth(Sem.either_lazy(not Sem.truth(is_finite(v_width)), func(): return ((v_width <= EPS)))):
		push_error(str("Stair width must be finite and positive"))
		return null
	var tmp_12 = Sem.map_array(range(3), func(tmp_10): var tmp_11 = tmp_10; return Sem.sub(v_b[tmp_11], v_a[tmp_11]))
	v_dx = tmp_12[0]
	v_dy = tmp_12[1]
	v_rise = tmp_12[2]
	v_run = Sem.hypot(v_dx, v_dy)
	if Sem.truth(Sem.either_lazy(((v_run <= EPS)), func(): return ((v_rise <= EPS)))):
		push_error(str("start/end must describe an ascending flight with horizontal run"))
		return null
	v_tread_count = Sem.sub(v_n, 1)
	var tmp_13 = [Sem.div(v_rise, v_n), Sem.div(v_run, v_tread_count)]
	v_riser = tmp_13[0]
	v_tread = tmp_13[1]
	v_cap = Sem.py_min(0.055, Sem.mul(v_riser, 0.4))
	v_waist = Sem.py_max(0.24, Sem.add(Sem.add(v_riser, v_cap), 0.075))
	v_angle = atan2(v_dy, v_dx)
	var tmp_14 = [Sem.div(v_dx, v_run), Sem.div(v_dy, v_run)]
	v_ux = tmp_14[0]
	v_uy = tmp_14[1]
	v_parent_point = func(tmp_15):
		var tmp_16 = tmp_15
		v_x = tmp_16[0]
		v_y = tmp_16[1]
		v_z = tmp_16[2]
		return [Sem.sub(Sem.add(v_a[0], Sem.mul(v_ux, v_x)), Sem.mul(v_uy, v_y)), Sem.add(Sem.add(v_a[1], Sem.mul(v_uy, v_x)), Sem.mul(v_ux, v_y)), Sem.add(v_a[2], v_z)]
	v_profile = [[0.0, Sem.neg(v_waist)], [0.0, Sem.sub(v_riser, v_cap)]]
	v_anchors = []
	for tmp_17 in range(v_tread_count):
		v_i = tmp_17
		var tmp_18 = [Sem.mul(v_i, v_tread), Sem.mul(Sem.add(v_i, 1), v_tread), Sem.mul(Sem.add(v_i, 1), v_riser)]
		v_x0 = tmp_18[0]
		v_x1 = tmp_18[1]
		v_z = tmp_18[2]
		v_profile.append([v_x1, Sem.sub(v_z, v_cap)])
		if Sem.truth(((Sem.add(v_i, 1) < v_tread_count))):
			v_profile.append([v_x1, Sem.sub(Sem.add(v_z, v_riser), v_cap)])
		v_local = {"nose": [v_x0, 0.0, v_z], "center": [Sem.div(Sem.add(v_x0, v_x1), 2), 0.0, v_z], "back": [v_x1, 0.0, v_z], "left": [v_x0, Sem.div(v_width, 2), v_z], "right": [v_x0, Sem.div(Sem.neg(v_width), 2), v_z]}
		v_anchors.append({"index": Sem.add(v_i, 1), "local": v_local, "parent": Sem.from_pairs(Sem.map_array(Sem.items(v_local), func(tmp_19): var tmp_20 = tmp_19[0]; var tmp_21 = tmp_19[1]; return [tmp_20, v_parent_point.call(tmp_21)]))})
	v_profile.append([v_run, Sem.sub(v_rise, v_waist)])
	v_rails = {}
	for tmp_22 in [["left", Sem.div(v_width, 2)], ["right", Sem.div(Sem.neg(v_width), 2)]]:
		var tmp_23 = tmp_22
		v_side = tmp_23[0]
		v_lateral = tmp_23[1]
		v_local = [[0.0, v_lateral, v_riser], [v_run, v_lateral, v_rise]]
		v_rails[v_side] = {"local": v_local, "parent": Sem.map_array(v_local, func(tmp_24): var tmp_25 = tmp_24; return v_parent_point.call(tmp_25))}
	return {"start": Sem.py_list(v_a), "end": Sem.py_list(v_b), "width": v_width, "yaw": v_angle, "risers": v_n, "treads": v_tread_count, "run": v_run, "rise": v_rise, "riser_height": v_riser, "tread": v_tread, "tread_cap": v_cap, "waist": v_waist, "support_profile": v_profile, "step_top_anchors": v_anchors, "railing_baselines": v_rails, "lower_landing": {"local": [0.0, 0.0, 0.0], "parent": Sem.py_list(v_a)}, "upper_landing": {"local": [v_run, 0.0, v_rise], "parent": Sem.py_list(v_b)}, "upper_landing_min_fascia_height": v_riser, "last_riser_owner": "separate_upper_landing"}

static func gen_straight_flight(v_name, v_start, v_end, v_width, v_mats, v_risers = 10, v_parent = null):
	var v_anchor = null
	var v_bevel = null
	var v_faces = null
	var v_key = null
	var v_obj = null
	var v_root = null
	var v_spec = null
	var v_stone = null
	var v_support = null
	var v_vertices = null
	var v_x = null
	var v_y = null
	var v_z = null
	v_spec = gen_flight_spec(v_start, v_end, v_width, v_risers)
	v_root = Geo.gen_group(v_name, v_spec["start"], v_spec["yaw"], v_parent)
	var tmp_26 = gen__profile_mesh(v_spec["support_profile"], v_spec["width"])
	v_vertices = tmp_26[0]
	v_faces = tmp_26[1]
	v_support = Geo.gen_mesh(Sem.add(v_name, "_Closed_Wood_Support"), v_vertices, v_faces, v_mats["wood_dark"], v_root, Sem.py_min(0.006, Sem.mul(v_spec["riser_height"], 0.04)))
	v_support["role"] = "closed_stair_support"
	v_support["static_geometry"] = true
	v_bevel = Sem.py_min(0.01, Sem.mul(v_spec["riser_height"], 0.1), Sem.mul(v_spec["tread"], 0.04), Sem.mul(v_spec["width"], 0.005))
	v_stone = v_mats.get("stair_tread", v_mats["stone"])
	for tmp_27 in v_spec["step_top_anchors"]:
		v_anchor = tmp_27
		var tmp_28 = v_anchor["local"]["center"]
		v_x = tmp_28[0]
		v_y = tmp_28[1]
		v_z = tmp_28[2]
		v_obj = Geo.gen_box(Sem.add(v_name, Sem.mod("_Stone_Tread_%02d", v_anchor["index"])), [v_x, v_y, Sem.sub(v_z, Sem.div(v_spec["tread_cap"], 2))], [v_spec["tread"], v_spec["width"], v_spec["tread_cap"]], v_stone, v_bevel, v_root)
		v_obj["tread_index"] = v_anchor["index"]
		v_obj["finished_tread_z"] = v_z
		v_obj["static_geometry"] = true
	v_root["generator"] = "straight_flight_exact_v1"
	v_root["static_geometry"] = true
	for tmp_29 in ["width", "risers", "treads", "run", "rise", "riser_height", "tread"]:
		v_key = tmp_29
		v_root[v_key] = v_spec[v_key]
	v_root["steps_total"] = v_spec["treads"]
	v_root["finished_top"] = v_spec["end"][2]
	v_root["last_riser_owner"] = v_spec["last_riser_owner"]
	v_root["upper_landing_min_fascia_height"] = v_spec["riser_height"]
	v_root["anchor_space"] = "local = returned root; parent = supplied start/end space"
	v_root["path_nodes"] = JSON.stringify([v_spec["start"], v_spec["end"]])
	v_root["step_top_anchors"] = JSON.stringify(v_spec["step_top_anchors"])
	v_root["railing_baselines"] = JSON.stringify(v_spec["railing_baselines"])
	v_root["landing_anchors"] = JSON.stringify(Sem.from_pairs(Sem.map_array(["lower_landing", "upper_landing"], func(tmp_30): var tmp_31 = tmp_30; return [tmp_31, v_spec[tmp_31]])))
	return v_root

