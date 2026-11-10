@tool
extends RefCounted

# Direct port of kit/lighting.py. Z-up recipe coordinates convert at the geometry boundary.
const Sem = preload("res://tools/building_construction/BuildingConstruction/Shared/RecipeSemantics.gd")
const Geo = preload("res://tools/building_construction/BuildingConstruction/Shared/RecipeGeometry.gd")
const EPS = 1e-9

static func gen__light(v_name, v_parent, v_location, v_kind = "POINT", v_energy = 12.0, v_color = [1.0, 0.72, 0.4], v_size = 0.1, v_size_y = null):
	var v_data = null
	var v_obj = null
	return Geo.fixture_light(v_name, v_parent, v_location, v_kind, v_energy, v_color, v_size, v_size_y)

static func gen__unshadowed_emitter(v_obj):
	v_obj["casts_shadow"] = false
	return v_obj

static func gen_wall_lantern(v_name, v_mats, v_height = 0.65, v_parent = null, v_light = true, v_light_energy = 12.0):
	var v_anchor = null
	var v_angle = null
	var v_arm = null
	var v_body = null
	var v_core = null
	var v_core_profile = null
	var v_cy = null
	var v_following = null
	var v_gold = null
	var v_j = null
	var v_k = null
	var v_r = null
	var v_r0 = null
	var v_r1 = null
	var v_root = null
	var v_s = null
	var v_z = null
	var v_z0 = null
	var v_z1 = null
	if Sem.truth(((v_height <= 0))):
		push_error(str("Lantern height must be positive"))
		return null
	v_root = Geo.gen_group(v_name, [0, 0, 0], 0, v_parent)
	v_root["kind"] = "wall_lantern"
	v_root["fixture_height"] = v_height
	v_s = Sem.div(v_height, 0.65)
	v_gold = v_mats["gold"]
	Geo.gen_box(Sem.add(v_name, "_Mount"), [0, Sem.mul(Sem.neg(0.028), v_s), Sem.mul(0.05, v_s)], [Sem.mul(0.115, v_s), Sem.mul(0.055, v_s), Sem.mul(0.34, v_s)], v_gold, Sem.mul(0.012, v_s), v_root)
	Geo.gen_box(Sem.add(v_name, "_Mount_inset"), [0, Sem.mul(Sem.neg(0.062), v_s), Sem.mul(0.05, v_s)], [Sem.mul(0.07, v_s), Sem.mul(0.018, v_s), Sem.mul(0.25, v_s)], v_mats["wood_dark"], Sem.mul(0.007, v_s), v_root)
	v_arm = [[0, Sem.mul(Sem.neg(0.06), v_s), Sem.mul(0.18, v_s)], [0, Sem.mul(Sem.neg(0.145), v_s), Sem.mul(0.285, v_s)], [0, Sem.mul(Sem.neg(0.3), v_s), Sem.mul(0.285, v_s)], [0, Sem.mul(Sem.neg(0.3), v_s), Sem.mul(0.205, v_s)]]
	for tmp_1 in range(Sem.sub(Sem.py_len(v_arm), 1)):
		v_j = tmp_1
		Geo.gen_beam(Sem.add(Sem.add(v_name, "_Bracket_"), str(v_j)), v_arm[v_j], v_arm[Sem.add(v_j, 1)], Sem.mul(0.026, v_s), Sem.mul(0.026, v_s), v_gold, v_root, Sem.mul(0.004, v_s))
	v_cy = Sem.mul(Sem.neg(0.3), v_s)
	v_body = [[Sem.mul(0.066, v_s), Sem.mul(Sem.neg(0.235), v_s)], [Sem.mul(0.118, v_s), Sem.mul(Sem.neg(0.145), v_s)], [Sem.mul(0.118, v_s), Sem.mul(0.095, v_s)], [Sem.mul(0.073, v_s), Sem.mul(0.185, v_s)]]
	v_core_profile = [[0, v_body[0][1]]]
	v_core_profile = Sem.add(v_core_profile, Sem.map_array(v_body, func(tmp_2): var tmp_3 = tmp_2[0]; var tmp_4 = tmp_2[1]; return [Sem.mul(tmp_3, 0.91), tmp_4]))
	v_core_profile = Sem.add(v_core_profile, [[0, v_body[Sem.neg(1)][1]]])
	v_core = Geo.gen_lathe(Sem.add(v_name, "_Emitting_core"), v_core_profile, 6, v_mats["emission"], v_root, [0, v_cy, 0])
	gen__unshadowed_emitter(v_core)
	for tmp_5 in range(6):
		v_j = tmp_5
		v_angle = Sem.add(Sem.div(Sem.mul(Sem.mul(2, PI), v_j), 6), Sem.div(PI, 8))
		for tmp_6 in range(Sem.sub(Sem.py_len(v_body), 1)):
			v_k = tmp_6
			var tmp_7 = v_body[v_k]
			v_r0 = tmp_7[0]
			v_z0 = tmp_7[1]
			var tmp_8 = v_body[Sem.add(v_k, 1)]
			v_r1 = tmp_8[0]
			v_z1 = tmp_8[1]
			Geo.gen_beam(Sem.add(Sem.add(Sem.add(Sem.add(v_name, "_Rib_"), str(v_j)), "_"), str(v_k)), [Sem.mul(v_r0, cos(v_angle)), Sem.add(v_cy, Sem.mul(v_r0, sin(v_angle))), v_z0], [Sem.mul(v_r1, cos(v_angle)), Sem.add(v_cy, Sem.mul(v_r1, sin(v_angle))), v_z1], Sem.mul(0.016, v_s), Sem.mul(0.016, v_s), v_gold, v_root, Sem.mul(0.002, v_s))
		for tmp_9 in [1, 2]:
			v_k = tmp_9
			var tmp_10 = v_body[v_k]
			v_r = tmp_10[0]
			v_z = tmp_10[1]
			v_following = Sem.add(Sem.div(Sem.mul(Sem.mul(2, PI), Sem.add(v_j, 1)), 6), Sem.div(PI, 8))
			Geo.gen_beam(Sem.add(Sem.add(Sem.add(Sem.add(v_name, "_Ring_"), str(v_k)), "_"), str(v_j)), [Sem.mul(v_r, cos(v_angle)), Sem.add(v_cy, Sem.mul(v_r, sin(v_angle))), v_z], [Sem.mul(v_r, cos(v_following)), Sem.add(v_cy, Sem.mul(v_r, sin(v_following))), v_z], Sem.mul(0.018, v_s), Sem.mul(0.018, v_s), v_gold, v_root, Sem.mul(0.002, v_s))
	Geo.gen_lathe(Sem.add(v_name, "_Top_cap"), [[0, Sem.mul(0.174, v_s)], [Sem.mul(0.082, v_s), Sem.mul(0.174, v_s)], [Sem.mul(0.142, v_s), Sem.mul(0.205, v_s)], [Sem.mul(0.142, v_s), Sem.mul(0.227, v_s)], [Sem.mul(0.045, v_s), Sem.mul(0.32, v_s)], [Sem.mul(0.022, v_s), Sem.mul(0.325, v_s)], [0, Sem.mul(0.325, v_s)]], 6, v_gold, v_root, [0, v_cy, 0])
	Geo.gen_lathe(Sem.add(v_name, "_Bottom_cap"), [[0, Sem.mul(Sem.neg(0.31), v_s)], [Sem.mul(0.026, v_s), Sem.mul(Sem.neg(0.285), v_s)], [Sem.mul(0.08, v_s), Sem.mul(Sem.neg(0.25), v_s)], [Sem.mul(0.088, v_s), Sem.mul(Sem.neg(0.215), v_s)], [0, Sem.mul(Sem.neg(0.215), v_s)]], 6, v_gold, v_root, [0, v_cy, 0])
	Geo.gen_ico(Sem.add(v_name, "_Finial"), [0, v_cy, Sem.mul(Sem.neg(0.31), v_s)], Sem.mul(0.025, v_s), v_gold, 1, v_root)
	v_anchor = Geo.gen_group(Sem.add(v_name, "_Light_anchor"), [0, v_cy, Sem.mul(Sem.neg(0.025), v_s)], 0, v_root)
	v_anchor["kind"] = "light_anchor"
	v_anchor["light_type"] = "point"
	v_anchor["energy_watts"] = float(v_light_energy)
	if Sem.truth(v_light):
		gen__light(Sem.add(v_name, "_Point"), v_root, v_anchor.location, "POINT", v_light_energy, [1.0, 0.72, 0.4], Sem.mul(0.075, v_s), null)
	return v_root

static func gen__banker_shade(v_name, v_mats, v_width, v_radius_y, v_radius_z, v_bottom, v_cy, v_parent):
	var v_angle = null
	var v_faces = null
	var v_i = null
	var v_il = null
	var v_index = null
	var v_inner = null
	var v_inner_faces = null
	var v_ir = null
	var v_j = null
	var v_obj = null
	var v_ol = null
	var v_or_ = null
	var v_outer = null
	var v_ring = null
	var v_rings = null
	var v_ry = null
	var v_rz = null
	var v_segments = null
	var v_settings = null
	var v_thick = null
	var v_vertices = null
	var v_x = null
	v_segments = 6
	v_thick = Sem.py_min(0.015, Sem.mul(v_radius_y, 0.12), Sem.mul(v_width, 0.04))
	v_vertices = []
	v_rings = []
	v_settings = [[Sem.div(Sem.neg(v_width), 2), v_radius_y, v_radius_z], [Sem.div(v_width, 2), v_radius_y, v_radius_z], [Sem.add(Sem.div(Sem.neg(v_width), 2), v_thick), Sem.sub(v_radius_y, v_thick), Sem.sub(v_radius_z, v_thick)], [Sem.sub(Sem.div(v_width, 2), v_thick), Sem.sub(v_radius_y, v_thick), Sem.sub(v_radius_z, v_thick)]]
	for tmp_11 in v_settings:
		var tmp_12 = tmp_11
		v_x = tmp_12[0]
		v_ry = tmp_12[1]
		v_rz = tmp_12[2]
		v_ring = []
		for tmp_13 in range(Sem.add(v_segments, 1)):
			v_j = tmp_13
			v_angle = Sem.div(Sem.mul(PI, v_j), v_segments)
			v_ring.append(Sem.py_len(v_vertices))
			v_vertices.append([v_x, Sem.add(v_cy, Sem.mul(v_ry, cos(v_angle))), Sem.add(v_bottom, Sem.mul(v_rz, sin(v_angle)))])
		v_rings.append(v_ring)
	var tmp_14 = v_rings
	v_ol = tmp_14[0]
	v_or_ = tmp_14[1]
	v_il = tmp_14[2]
	v_ir = tmp_14[3]
	var tmp_15 = [[], []]
	v_faces = tmp_15[0]
	v_inner_faces = tmp_15[1]
	for tmp_16 in range(v_segments):
		v_j = tmp_16
		v_faces.append([v_ol[v_j], v_ol[Sem.add(v_j, 1)], v_or_[Sem.add(v_j, 1)], v_or_[v_j]])
	v_faces.append(Sem.py_tuple(Sem.py_reversed(v_ol)))
	v_faces.append(Sem.py_tuple(v_or_))
	for tmp_17 in range(v_segments):
		v_j = tmp_17
		v_inner_faces.append(Sem.py_len(v_faces))
		v_faces.append([v_il[v_j], v_ir[v_j], v_ir[Sem.add(v_j, 1)], v_il[Sem.add(v_j, 1)]])
	v_inner_faces.append(Sem.py_len(v_faces))
	v_faces.append(Sem.py_tuple(v_il))
	v_inner_faces.append(Sem.py_len(v_faces))
	v_faces.append(Sem.py_tuple(Sem.py_reversed(v_ir)))
	v_outer = [v_ol[Sem.neg(1)], v_or_[Sem.neg(1)], v_or_[0], v_ol[0]]
	v_inner = [v_il[Sem.neg(1)], v_ir[Sem.neg(1)], v_ir[0], v_il[0]]
	for tmp_18 in range(4):
		v_i = tmp_18
		v_j = Sem.mod(Sem.add(v_i, 1), 4)
		v_faces.append([v_outer[v_i], v_inner[v_i], v_inner[v_j], v_outer[v_j]])
	v_obj = Geo.gen_mesh(v_name, v_vertices, v_faces, v_mats["green"], v_parent, 0)
	v_obj.data.materials.append(v_mats["cream"])
	for tmp_19 in v_inner_faces:
		v_index = tmp_19
		v_obj.data.polygons[v_index].material_index = 1
	return v_obj

static func gen_banker_lamp(v_name, v_mats, v_height = 0.55, v_width = 0.43, v_parent = null, v_light = true, v_light_energy = 8.0):
	var v_anchor = null
	var v_bottom = null
	var v_cy = null
	var v_gold = null
	var v_knob = null
	var v_root = null
	var v_s = null
	var v_side = null
	var v_switch = null
	var v_tube = null
	if Sem.truth(((Sem.py_min(v_height, v_width) <= 0))):
		push_error(str("Lamp dimensions must be positive"))
		return null
	v_root = Geo.gen_group(v_name, [0, 0, 0], 0, v_parent)
	v_root["kind"] = "banker_lamp"
	v_s = Sem.div(v_height, 0.55)
	v_gold = v_mats["gold"]
	Geo.gen_lathe(Sem.add(v_name, "_Base"), [[0, 0], [Sem.mul(0.11, v_s), 0], [Sem.mul(0.135, v_s), Sem.mul(0.018, v_s)], [Sem.mul(0.135, v_s), Sem.mul(0.035, v_s)], [Sem.mul(0.105, v_s), Sem.mul(0.055, v_s)], [Sem.mul(0.045, v_s), Sem.mul(0.072, v_s)], [0, Sem.mul(0.072, v_s)]], 12, v_gold, v_root, [0, 0, 0])
	Geo.gen_cylinder(Sem.add(v_name, "_Stem"), [0, Sem.mul(0.025, v_s), Sem.mul(0.215, v_s)], Sem.mul(0.024, v_s), Sem.mul(0.285, v_s), v_gold, 8, v_root)
	Geo.gen_lathe(Sem.add(v_name, "_Stem_collar"), [[0, Sem.mul(0.067, v_s)], [Sem.mul(0.038, v_s), Sem.mul(0.067, v_s)], [Sem.mul(0.038, v_s), Sem.mul(0.095, v_s)], [Sem.mul(0.029, v_s), Sem.mul(0.115, v_s)], [Sem.mul(0.025, v_s), Sem.mul(0.115, v_s)], [0, Sem.mul(0.115, v_s)]], 8, v_gold, v_root, [0, Sem.mul(0.025, v_s), 0])
	var tmp_20 = [Sem.mul(Sem.neg(0.025), v_s), Sem.mul(0.405, v_s)]
	v_cy = tmp_20[0]
	v_bottom = tmp_20[1]
	for tmp_21 in [Sem.neg(1), 1]:
		v_side = tmp_21
		Geo.gen_beam(Sem.add(Sem.add(v_name, "_Shade_support_"), str(v_side)), [0, Sem.mul(0.025, v_s), Sem.mul(0.335, v_s)], [Sem.mul(v_side, Sem.add(Sem.div(v_width, 2), Sem.mul(0.018, v_s))), Sem.mul(0.025, v_s), Sem.mul(0.435, v_s)], Sem.mul(0.017, v_s), Sem.mul(0.02, v_s), v_gold, v_root, Sem.mul(0.003, v_s))
		v_knob = Geo.gen_cylinder(Sem.add(Sem.add(v_name, "_Shade_pivot_"), str(v_side)), [Sem.mul(v_side, Sem.add(Sem.div(v_width, 2), Sem.mul(0.012, v_s))), v_cy, Sem.add(v_bottom, Sem.mul(0.045, v_s))], Sem.mul(0.022, v_s), Sem.mul(0.04, v_s), v_gold, 8, v_root)
		v_knob.rotation_euler[1] = Sem.div(PI, 2)
	gen__banker_shade(Sem.add(v_name, "_Green_shade"), v_mats, v_width, Sem.mul(0.128, v_s), Sem.mul(0.145, v_s), v_bottom, v_cy, v_root)
	Geo.gen_beam(Sem.add(v_name, "_Shade_front_rim"), [Sem.div(Sem.neg(v_width), 2), Sem.sub(v_cy, Sem.mul(0.128, v_s)), v_bottom], [Sem.div(v_width, 2), Sem.sub(v_cy, Sem.mul(0.128, v_s)), v_bottom], Sem.mul(0.011, v_s), Sem.mul(0.011, v_s), v_gold, v_root, Sem.mul(0.002, v_s))
	v_tube = Geo.gen_cylinder(Sem.add(v_name, "_Warm_tube"), [0, v_cy, Sem.add(v_bottom, Sem.mul(0.035, v_s))], Sem.mul(0.015, v_s), Sem.mul(v_width, 0.64), v_mats["emission"], 8, v_root)
	v_tube.rotation_euler[1] = Sem.div(PI, 2)
	gen__unshadowed_emitter(v_tube)
	v_switch = Geo.gen_cylinder(Sem.add(v_name, "_Switch"), [0, Sem.mul(Sem.neg(0.085), v_s), Sem.mul(0.064, v_s)], Sem.mul(0.013, v_s), Sem.mul(0.02, v_s), v_mats["wood_dark"], 8, v_root)
	v_switch.rotation_euler[0] = 0.35
	v_anchor = Geo.gen_group(Sem.add(v_name, "_Light_anchor"), [0, v_cy, Sem.sub(v_bottom, Sem.mul(0.008, v_s))], 0, v_root)
	v_anchor["kind"] = "light_anchor"
	v_anchor["light_type"] = "area"
	v_anchor["energy_watts"] = float(v_light_energy)
	if Sem.truth(v_light):
		gen__light(Sem.add(v_name, "_Downlight"), v_root, v_anchor.location, "AREA", v_light_energy, [1.0, 0.79, 0.5], Sem.mul(v_width, 0.64), Sem.mul(0.11, v_s))
	return v_root

static func gen__pendant_shade(v_name, v_mats, v_outer, v_thickness, v_sides, v_parent):
	var v_faces = null
	var v_index = null
	var v_inner = null
	var v_inner_faces = null
	var v_inside = null
	var v_j = null
	var v_k = null
	var v_l = null
	var v_obj = null
	var v_outside = null
	var v_profile = null
	var v_profile_rings = null
	var v_r = null
	var v_radius = null
	var v_ring = null
	var v_rings = null
	var v_theta = null
	var v_vertices = null
	var v_z = null
	var tmp_22 = [[], []]
	v_vertices = tmp_22[0]
	v_rings = tmp_22[1]
	v_inner = Sem.map_array(v_outer, func(tmp_23): var tmp_24 = tmp_23[0]; var tmp_25 = tmp_23[1]; return [Sem.py_max(0.005, Sem.sub(tmp_24, v_thickness)), tmp_25])
	for tmp_26 in [v_outer, v_inner]:
		v_profile = tmp_26
		v_profile_rings = []
		for tmp_27 in v_profile:
			var tmp_28 = tmp_27
			v_radius = tmp_28[0]
			v_z = tmp_28[1]
			v_ring = []
			for tmp_29 in range(v_sides):
				v_j = tmp_29
				v_theta = Sem.add(Sem.div(Sem.mul(Sem.mul(2, PI), v_j), v_sides), Sem.div(PI, 8))
				v_ring.append(Sem.py_len(v_vertices))
				v_vertices.append([Sem.mul(v_radius, cos(v_theta)), Sem.mul(v_radius, sin(v_theta)), v_z])
			v_profile_rings.append(v_ring)
		v_rings.append(v_profile_rings)
	var tmp_30 = v_rings
	v_outside = tmp_30[0]
	v_inside = tmp_30[1]
	var tmp_31 = [[], []]
	v_faces = tmp_31[0]
	v_inner_faces = tmp_31[1]
	for tmp_32 in range(Sem.sub(Sem.py_len(v_outer), 1)):
		v_k = tmp_32
		for tmp_33 in range(v_sides):
			v_j = tmp_33
			v_l = Sem.mod(Sem.add(v_j, 1), v_sides)
			v_faces.append([v_outside[v_k][v_j], v_outside[Sem.add(v_k, 1)][v_j], v_outside[Sem.add(v_k, 1)][v_l], v_outside[v_k][v_l]])
			v_inner_faces.append(Sem.py_len(v_faces))
			v_faces.append([v_inside[v_k][v_j], v_inside[v_k][v_l], v_inside[Sem.add(v_k, 1)][v_l], v_inside[Sem.add(v_k, 1)][v_j]])
	for tmp_34 in range(v_sides):
		v_j = tmp_34
		v_l = Sem.mod(Sem.add(v_j, 1), v_sides)
		v_faces.append([v_outside[0][v_j], v_outside[0][v_l], v_inside[0][v_l], v_inside[0][v_j]])
		v_faces.append([v_outside[Sem.neg(1)][v_j], v_inside[Sem.neg(1)][v_j], v_inside[Sem.neg(1)][v_l], v_outside[Sem.neg(1)][v_l]])
	v_obj = Geo.gen_mesh(v_name, v_vertices, v_faces, v_mats["green"], v_parent, 0)
	v_obj.data.materials.append(v_mats["cream"])
	for tmp_35 in v_inner_faces:
		v_index = tmp_35
		v_obj.data.polygons[v_index].material_index = 1
	return v_obj

static func gen_pendant_lamp(v_name, v_mats, v_drop = 0.8, v_radius = 0.27, v_parent = null, v_light = true, v_light_energy = 10.0):
	var v_anchor = null
	var v_bulb = null
	var v_profile = null
	var v_root = null
	if Sem.truth(Sem.either_lazy(((v_drop <= 0.15)), func(): return ((v_radius <= 0.06)))):
		push_error(str("Pendant needs drop>.15 and radius>.06"))
		return null
	v_root = Geo.gen_group(v_name, [0, 0, 0], 0, v_parent)
	v_root["kind"] = "pendant_lamp"
	Geo.gen_cylinder(Sem.add(v_name, "_Ceiling_cap"), [0, 0, Sem.neg(0.025)], 0.095, 0.05, v_mats["gold"], 8, v_root)
	Geo.gen_cylinder(Sem.add(v_name, "_Cord"), [0, 0, Sem.div(Sem.neg(v_drop), 2)], 0.008, v_drop, v_mats["wood_dark"], 6, v_root)
	v_profile = [[Sem.mul(v_radius, 0.19), Sem.add(Sem.neg(v_drop), 0.08)], [Sem.mul(v_radius, 0.34), Sem.add(Sem.neg(v_drop), 0.035)], [Sem.mul(v_radius, 0.82), Sem.sub(Sem.neg(v_drop), 0.115)], [v_radius, Sem.sub(Sem.neg(v_drop), 0.16)], [v_radius, Sem.sub(Sem.neg(v_drop), 0.18)]]
	gen__pendant_shade(Sem.add(v_name, "_Shade"), v_mats, v_profile, 0.012, 8, v_root)
	v_bulb = Geo.gen_ico(Sem.add(v_name, "_Bulb"), [0, 0, Sem.sub(Sem.neg(v_drop), 0.105)], 0.052, v_mats["emission"], 1, v_root)
	gen__unshadowed_emitter(v_bulb)
	v_anchor = Geo.gen_group(Sem.add(v_name, "_Light_anchor"), [0, 0, Sem.sub(Sem.neg(v_drop), 0.19)], 0, v_root)
	v_anchor["kind"] = "light_anchor"
	v_anchor["light_type"] = "point"
	v_anchor["energy_watts"] = float(v_light_energy)
	if Sem.truth(v_light):
		gen__light(Sem.add(v_name, "_Light"), v_root, v_anchor.location, "POINT", v_light_energy, [1.0, 0.78, 0.46], 0.065, null)
	return v_root

