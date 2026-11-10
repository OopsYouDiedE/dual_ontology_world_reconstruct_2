@tool
extends RefCounted

# Direct port of kit/outdoor_props.py. Z-up recipe coordinates convert at the geometry boundary.
const Sem = preload("res://tools/building_construction/BuildingConstruction/Shared/RecipeSemantics.gd")
const Geo = preload("res://tools/building_construction/BuildingConstruction/Shared/RecipeGeometry.gd")
const EPS = 1e-9

static func gen_outdoor_materials(v_base):
	var v_color = null
	var v_colors = null
	var v_key = null
	var v_mats = null
	var v_name = null
	return Geo.outdoor_palette(v_base)

static func gen_stone_wall(v_name, v_mats, v_length = 4, v_height = 1.05, v_thickness = 0.32, v_pier_spacing = 3.0, v_parent = null):
	var v_a = null
	var v_b = null
	var v_col = null
	var v_i = null
	var v_rh = null
	var v_root = null
	var v_row = null
	var v_rows = null
	var v_spans = null
	var v_start = null
	var v_x = null
	v_root = Geo.gen_group(v_name, [0, 0, 0], 0, v_parent)
	Geo.gen_box(Sem.add(v_name, "_Core"), [0, 0, Sem.div(v_height, 2)], [v_length, Sem.mul(v_thickness, 0.9), v_height], v_mats["stone_dark"], 0, v_root)
	v_rows = Sem.py_max(1, Sem.py_round(Sem.div(v_height, 0.32)))
	v_rh = Sem.div(v_height, v_rows)
	for tmp_1 in range(v_rows):
		v_row = tmp_1
		v_start = Sem.sub(Sem.div(Sem.neg(v_length), 2), (0.5 if Sem.truth(Sem.mod(v_row, 2)) else 0))
		for tmp_2 in range(Sem.add(ceili(v_length), 2)):
			v_col = tmp_2
			v_a = Sem.py_max(Sem.div(Sem.neg(v_length), 2), Sem.add(v_start, v_col))
			v_b = Sem.py_min(Sem.div(v_length, 2), Sem.add(Sem.add(v_start, v_col), 1))
			if Sem.truth(((Sem.sub(v_b, v_a) < 0.03))):
				continue
			Geo.gen_box(Sem.add(v_name, Sem.mod("_Block_%d_%d", [v_row, v_col])), [Sem.div(Sem.add(v_a, v_b), 2), 0, Sem.mul(Sem.add(v_row, 0.5), v_rh)], [Sem.sub(Sem.sub(v_b, v_a), 0.012), v_thickness, Sem.sub(v_rh, 0.012)], (v_mats["stone"] if Sem.truth(Sem.mod(Sem.add(v_row, v_col), 4)) else v_mats["cream"]), 0.012, v_root)
	Geo.gen_box(Sem.add(v_name, "_Coping"), [0, 0, Sem.add(v_height, 0.045)], [Sem.add(v_length, 0.04), Sem.add(v_thickness, 0.12), 0.09], v_mats["cream"], 0.012, v_root)
	v_spans = Sem.py_max(1, ceili(Sem.div(v_length, v_pier_spacing)))
	for tmp_3 in range(Sem.add(v_spans, 1)):
		v_i = tmp_3
		v_x = Sem.add(Sem.div(Sem.neg(v_length), 2), Sem.div(Sem.mul(v_length, v_i), v_spans))
		Geo.gen_box(Sem.add(v_name, Sem.mod("_Pier_%d", v_i)), [v_x, 0, Sem.div(Sem.add(v_height, 0.12), 2)], [0.43, 0.43, Sem.add(v_height, 0.12)], v_mats["stone"], 0.012, v_root)
		Geo.gen_box(Sem.add(v_name, Sem.mod("_Pier_cap_%d", v_i)), [v_x, 0, Sem.add(v_height, 0.14)], [0.55, 0.55, 0.16], v_mats["cream"], 0.018, v_root)
	return v_root

static func gen_courtyard_gate(v_name, v_mats, v_width = 2.2, v_height = 2.7, v_rise = 0.65, v_parent = null):
	var v_obj = null
	var v_root = null
	var v_sign = null
	v_root = load("res://tools/building_construction/BuildingConstruction/Doors/VariantRecipes.gd").gen_arched_closed_door(v_name, v_mats, v_width, v_height, v_rise, true, 12, 0.14, v_parent)
	for tmp_4 in Geo.descendants(v_root):
		v_obj = tmp_4
		if Sem.truth(((v_obj.type != "MESH"))):
			continue
		if Sem.truth(Sem.either_lazy((("_Arch_jamb" in v_obj.name)), func(): return Sem.either_lazy((("_Arch_moulding" in v_obj.name)), func(): return (("_Arch_inner_bead" in v_obj.name))))):
			v_obj.data.materials.clear()
			v_obj.data.materials.append((v_mats["stone"] if Sem.truth((("_jamb" in v_obj.name))) else v_mats["cream"]))
	for tmp_5 in [Sem.neg(1), 1]:
		v_sign = tmp_5
		Geo.gen_box(Sem.add(Sem.add(v_name, "_Stone_Pier_"), str(v_sign)), [Sem.mul(v_sign, Sem.add(Sem.div(v_width, 2), 0.3)), 0.04, Sem.div(v_height, 2)], [0.44, 0.48, v_height], v_mats["stone"], 0.015, v_root)
		Geo.gen_box(Sem.add(Sem.add(v_name, "_Stone_Cap_"), str(v_sign)), [Sem.mul(v_sign, Sem.add(Sem.div(v_width, 2), 0.3)), 0.04, Sem.add(v_height, 0.08)], [0.6, 0.62, 0.18], v_mats["cream"], 0.015, v_root)
	v_root["transition_mode"] = "teleport"
	return v_root

static func gen_tree(v_name, v_mats, v_height = 3.8, v_crown_radius = 1.15, v_seed = 7, v_parent = null):
	var v_angle = null
	var v_end = null
	var v_i = null
	var v_leaf = null
	var v_location = null
	var v_radius = null
	var v_rng = null
	var v_root = null
	var v_z = null
	v_root = Geo.gen_group(v_name, [0, 0, 0], 0, v_parent)
	v_rng = Sem.RandomSequence.new(v_seed)
	Geo.gen_lathe(Sem.add(v_name, "_Trunk"), [[0.18, 0], [0.13, Sem.mul(v_height, 0.18)], [0.1, Sem.mul(v_height, 0.48)], [0.055, Sem.mul(v_height, 0.76)]], 7, v_mats["wood"], v_root, [0, 0, 0])
	for tmp_6 in range(5):
		v_i = tmp_6
		v_angle = Sem.add(Sem.div(Sem.mul(Sem.mul(2, PI), v_i), 5), 0.4)
		v_end = [Sem.mul(Sem.mul(v_crown_radius, 0.78), cos(v_angle)), Sem.mul(Sem.mul(v_crown_radius, 0.78), sin(v_angle)), Sem.mul(v_height, Sem.add(0.58, Sem.mul(0.06, Sem.mod(v_i, 3))))]
		Geo.gen_beam(Sem.add(Sem.add(v_name, "_Branch_"), str(v_i)), [0, 0, Sem.mul(v_height, 0.35)], v_end, 0.09, 0.11, v_mats["wood"], v_root, 0.004)
	for tmp_7 in range(10):
		v_i = tmp_7
		v_angle = Sem.div(Sem.mul(Sem.mul(2, PI), v_i), 7)
		v_radius = Sem.mul(v_crown_radius, (0.62 if Sem.truth(((v_i < 7))) else 0.28))
		v_z = Sem.add(Sem.mul(v_height, (0.62 if Sem.truth(((v_i < 7))) else 0.81)), v_rng.uniform(Sem.neg(0.08), 0.1))
		v_location = [Sem.mul(v_radius, cos(v_angle)), Sem.mul(v_radius, sin(v_angle)), v_z]
		v_leaf = Geo.gen_ico(Sem.add(v_name, Sem.mod("_Crown_%02d", v_i)), v_location, Sem.mul(v_crown_radius, (0.6 if Sem.truth(((v_i < 7))) else 0.67)), v_mats[["leaf_mid", "leaf_sun", "leaf_dark"][Sem.mod(v_i, 3)]], 1, v_root)
		v_leaf.scale = [1.0, v_rng.uniform(0.82, 1.1), v_rng.uniform(0.75, 1.0)]
		v_leaf.rotation_euler = [v_rng.uniform(0, 0.4), v_rng.uniform(0, 0.4), v_angle]
	v_root["kind"] = "faceted_tree"
	v_root["seed"] = v_seed
	return v_root

static func gen_planter_bed(v_name, v_mats, v_width = 2.0, v_depth = 0.85, v_height = 0.42, v_shrubs = true, v_parent = null):
	var v_count = null
	var v_i = null
	var v_leaf = null
	var v_root = null
	var v_x = null
	var v_y = null
	v_root = Geo.gen_group(v_name, [0, 0, 0], 0, v_parent)
	Geo.gen_box(Sem.add(v_name, "_Soil"), [0, 0, Sem.sub(v_height, 0.075)], [Sem.sub(v_width, 0.14), Sem.sub(v_depth, 0.14), 0.08], v_mats["soil"], 0, v_root)
	for tmp_8 in [Sem.add(Sem.div(Sem.neg(v_width), 2), 0.055), Sem.sub(Sem.div(v_width, 2), 0.055)]:
		v_x = tmp_8
		Geo.gen_box(Sem.add(v_name, "_End"), [v_x, 0, Sem.div(v_height, 2)], [0.11, v_depth, v_height], v_mats["stone"], 0.012, v_root)
	for tmp_9 in [Sem.add(Sem.div(Sem.neg(v_depth), 2), 0.055), Sem.sub(Sem.div(v_depth, 2), 0.055)]:
		v_y = tmp_9
		Geo.gen_box(Sem.add(v_name, "_Side"), [0, v_y, Sem.div(v_height, 2)], [Sem.sub(v_width, 0.12), 0.11, v_height], v_mats["stone"], 0.012, v_root)
	if Sem.truth(v_shrubs):
		v_count = Sem.py_max(3, Sem.py_round(Sem.div(v_width, 0.3)))
		for tmp_10 in range(v_count):
			v_i = tmp_10
			v_leaf = Geo.gen_ico(Sem.add(v_name, Sem.mod("_Shrub_%02d", v_i)), [Sem.add(Sem.mul(Sem.neg(v_width), 0.35), Sem.div(Sem.mul(Sem.mul(v_width, 0.7), v_i), Sem.sub(v_count, 1))), 0, Sem.add(v_height, 0.12)], Sem.py_min(0.3, Sem.mul(v_depth, 0.4)), (v_mats["leaf_mid"] if Sem.truth(Sem.mod(v_i, 2)) else v_mats["leaf_sun"]), 1, v_root)
			v_leaf.scale = [1, 0.85, Sem.add(1.0, Sem.mul(Sem.mod(v_i, 3), 0.15))]
	return v_root

static func gen_fountain(v_name, v_mats, v_radius = 1.05, v_height = 1.4, v_parent = null):
	var v_angle = null
	var v_i = null
	var v_j = null
	var v_points = null
	var v_r = null
	var v_root = null
	var v_t = null
	v_root = Geo.gen_group(v_name, [0, 0, 0], 0, v_parent)
	Geo.gen_cylinder(Sem.add(v_name, "_Octagonal_Foot"), [0, 0, 0.06], Sem.add(v_radius, 0.16), 0.12, v_mats["stone_dark"], 8, v_root)
	Geo.gen_lathe(Sem.add(v_name, "_Basin"), [[0, 0.12], [v_radius, 0.12], [v_radius, 0.56], [Sem.sub(v_radius, 0.11), 0.62], [Sem.sub(v_radius, 0.2), 0.62], [Sem.sub(v_radius, 0.22), 0.24], [0, 0.24]], 8, v_mats["stone"], v_root, [0, 0, 0])
	Geo.gen_cylinder(Sem.add(v_name, "_Water"), [0, 0, 0.34], Sem.sub(v_radius, 0.22), 0.028, v_mats["water_2"], 8, v_root)
	Geo.gen_lathe(Sem.add(v_name, "_Column"), [[0.24, 0.26], [0.29, 0.32], [0.19, 0.42], [0.12, Sem.mul(v_height, 0.7)], [0.26, Sem.mul(v_height, 0.81)], [0.31, Sem.mul(v_height, 0.93)], [0.17, v_height], [0, v_height]], 8, v_mats["cream"], v_root, [0, 0, 0])
	for tmp_11 in range(4):
		v_i = tmp_11
		v_angle = Sem.add(Sem.div(Sem.mul(v_i, PI), 2), Sem.div(PI, 4))
		v_points = []
		for tmp_12 in range(7):
			v_j = tmp_12
			v_t = Sem.div(v_j, 6)
			v_r = Sem.mul(Sem.sub(v_radius, 0.3), v_t)
			v_points.append([Sem.mul(v_r, cos(v_angle)), Sem.mul(v_r, sin(v_angle)), Sem.sub(Sem.add(Sem.sub(v_height, 0.04), Sem.mul(0.2, v_t)), Sem.mul(Sem.mul(Sem.sub(v_height, 0.34), v_t), v_t))])
		for tmp_13 in range(Sem.sub(Sem.py_len(v_points), 1)):
			v_j = tmp_13
			Geo.gen_beam(Sem.add(v_name, Sem.mod("_Water_Arc_%d_%d", [v_i, v_j])), v_points[v_j], v_points[Sem.add(v_j, 1)], 0.035, 0.035, v_mats["water_2"], v_root, 0)
	v_root["water"] = "Stylized opaque solid streams; no fluid simulation or texture."
	return v_root

static func gen_scholarly_statue(v_name, v_mats, v_height = 2.8, v_parent = null):
	var v_base = null
	var v_beard = null
	var v_body = null
	var v_book = null
	var v_h = null
	var v_head = null
	var v_root = null
	var v_w = null
	var v_z = null
	v_root = Geo.gen_group(v_name, [0, 0, 0], 0, v_parent)
	v_base = Sem.mul(v_height, 0.3)
	v_body = Sem.sub(v_height, v_base)
	for tmp_14 in [[0.08, 0.92, 0.16], [0.2, 0.76, 0.14], [Sem.add(Sem.div(v_base, 2), 0.12), 0.64, Sem.sub(v_base, 0.3)], [Sem.sub(v_base, 0.04), 0.83, 0.12]]:
		var tmp_15 = tmp_14
		v_z = tmp_15[0]
		v_w = tmp_15[1]
		v_h = tmp_15[2]
		Geo.gen_box(Sem.add(v_name, "_Plinth"), [0, 0, v_z], [v_w, v_w, v_h], v_mats["stone"], 0.014, v_root)
	Geo.gen_lathe(Sem.add(v_name, "_Robe"), [[0.32, v_base], [0.34, Sem.add(v_base, 0.1)], [0.27, Sem.add(v_base, Sem.mul(v_body, 0.42))], [0.2, Sem.add(v_base, Sem.mul(v_body, 0.7))], [0.27, Sem.add(v_base, Sem.mul(v_body, 0.76))], [0.14, Sem.add(v_base, Sem.mul(v_body, 0.84))]], 7, v_mats["cream"], v_root, [0, 0, 0])
	v_head = Geo.gen_ico(Sem.add(v_name, "_Head"), [0, Sem.neg(0.025), Sem.add(v_base, Sem.mul(v_body, 0.91))], Sem.mul(v_body, 0.12), v_mats["cream"], 1, v_root)
	v_head.scale = [0.86, 0.9, 1.05]
	Geo.gen_beam(Sem.add(v_name, "_Left_Arm"), [Sem.neg(0.22), 0, Sem.add(v_base, Sem.mul(v_body, 0.73))], [Sem.neg(0.23), Sem.neg(0.22), Sem.add(v_base, Sem.mul(v_body, 0.48))], 0.14, 0.15, v_mats["cream"], v_root, 0.01)
	Geo.gen_beam(Sem.add(v_name, "_Right_Arm"), [0.22, 0, Sem.add(v_base, Sem.mul(v_body, 0.72))], [0.1, Sem.neg(0.25), Sem.add(v_base, Sem.mul(v_body, 0.56))], 0.14, 0.15, v_mats["cream"], v_root, 0.01)
	v_book = Geo.gen_box(Sem.add(v_name, "_Stone_Book"), [Sem.neg(0.04), Sem.neg(0.28), Sem.add(v_base, Sem.mul(v_body, 0.57))], [0.35, 0.09, 0.3], v_mats["stone"], 0.008, v_root)
	v_book.rotation_euler[1] = Sem.neg(0.18)
	Geo.gen_ico(Sem.add(v_name, "_Nose"), [0, Sem.neg(0.2), Sem.add(v_base, Sem.mul(v_body, 0.92))], Sem.mul(v_body, 0.035), v_mats["cream"], 1, v_root)
	v_beard = Geo.gen_ico(Sem.add(v_name, "_Beard"), [0, Sem.neg(0.13), Sem.add(v_base, Sem.mul(v_body, 0.84))], Sem.mul(v_body, 0.085), v_mats["cream"], 1, v_root)
	v_beard.scale = [0.65, 0.55, 1.05]
	v_root["identity"] = "generic_scholarly_statue_no_story_identity"
	return v_root

static func gen__ring(v_name, v_center, v_radius, v_normal, v_mats, v_parent, v_segments = 16):
	var v_i = null
	var v_k = null
	var v_p = null
	var v_pts = null
	var v_u = null
	var v_v = null
	if Sem.truth(((v_normal == "X"))):
		var tmp_16 = [[0, 1, 0], [0, 0, 1]]
		v_u = tmp_16[0]
		v_v = tmp_16[1]
	else:
		if Sem.truth(((v_normal == "Y"))):
			var tmp_17 = [[1, 0, 0], [0, 0, 1]]
			v_u = tmp_17[0]
			v_v = tmp_17[1]
		else:
			var tmp_18 = [[1, 0, 0], [0, 0.70710678, 0.70710678]]
			v_u = tmp_18[0]
			v_v = tmp_18[1]
	v_pts = Sem.map_array(range(v_segments), func(tmp_19): var tmp_20 = tmp_19; return Sem.py_tuple(Sem.map_array(range(3), func(tmp_21): var tmp_22 = tmp_21; return Sem.add(v_center[tmp_22], Sem.mul(v_radius, Sem.add(Sem.mul(v_u[tmp_22], cos(Sem.div(Sem.mul(Sem.mul(tmp_20, 2), PI), v_segments))), Sem.mul(v_v[tmp_22], sin(Sem.div(Sem.mul(Sem.mul(tmp_20, 2), PI), v_segments)))))))))
	for tmp_23 in Sem.py_enumerate(v_pts):
		var tmp_24 = tmp_23
		v_i = tmp_24[0]
		v_p = tmp_24[1]
		Geo.gen_beam(Sem.add(v_name, Sem.mod("_%02d", v_i)), v_p, v_pts[Sem.mod(Sem.add(v_i, 1), v_segments)], 0.018, 0.026, v_mats["gold"], v_parent, 0.002)

static func gen_instrument_table(v_name, v_mats, v_width = 1.4, v_depth = 0.72, v_height = 0.88, v_instrument = "armillary", v_parent = null):
	var v_bottom = null
	var v_center = null
	var v_cx = null
	var v_dial = null
	var v_i = null
	var v_normal = null
	var v_p = null
	var v_pts = null
	var v_root = null
	v_root = Geo.gen_group(v_name, [0, 0, 0], 0, v_parent)
	load("res://tools/building_construction/BuildingConstruction/Tables/FurnitureRecipes.gd").gen_table(Sem.add(v_name, "_Table"), v_mats, v_width, v_depth, v_height, "rect", v_root)
	v_cx = Sem.mul(Sem.neg(v_width), 0.16)
	Geo.gen_lathe(Sem.add(v_name, "_Instrument_Base"), [[0, 0], [0.17, 0], [0.19, 0.035], [0.11, 0.07], [0.045, 0.11], [0.045, 0.2], [0, 0.2]], 8, v_mats["gold"], v_root, [v_cx, 0, v_height])
	if Sem.truth(((v_instrument == "armillary"))):
		v_center = [v_cx, 0, Sem.add(v_height, 0.48)]
		for tmp_25 in ["X", "Y", "T"]:
			v_normal = tmp_25
			gen__ring(Sem.add(Sem.add(v_name, "_Armillary_"), v_normal), v_center, 0.29, v_normal, v_mats, v_root, 16)
		Geo.gen_beam(Sem.add(v_name, "_Axis"), [Sem.sub(v_cx, 0.11), 0, Sem.add(v_height, 0.12)], [Sem.add(v_cx, 0.11), 0, Sem.add(v_height, 0.84)], 0.025, 0.025, v_mats["gold"], v_root, 0.008)
		Geo.gen_ico(Sem.add(v_name, "_Globe"), v_center, 0.085, v_mats["stone"], 1, v_root)
	else:
		if Sem.truth(((v_instrument == "sextant"))):
			v_bottom = [Sem.sub(v_cx, 0.25), Sem.neg(0.03), Sem.add(v_height, 0.16)]
			v_pts = Sem.map_array(range(13), func(tmp_26): var tmp_27 = tmp_26; return [Sem.add(Sem.sub(v_cx, 0.25), Sem.mul(0.55, cos(Sem.add(Sem.div(PI, 6), Sem.div(Sem.div(Sem.mul(tmp_27, PI), 3), 12))))), Sem.neg(0.03), Sem.add(Sem.add(v_height, 0.16), Sem.mul(0.55, sin(Sem.add(Sem.div(PI, 6), Sem.div(Sem.div(Sem.mul(tmp_27, PI), 3), 12)))))])
			for tmp_28 in range(Sem.sub(Sem.py_len(v_pts), 1)):
				v_i = tmp_28
				Geo.gen_beam(Sem.add(v_name, "_Sextant_Arc"), v_pts[v_i], v_pts[Sem.add(v_i, 1)], 0.03, 0.04, v_mats["gold"], v_root, 0.008)
			for tmp_29 in [v_pts[0], v_pts[Sem.neg(1)], v_pts[6]]:
				v_p = tmp_29
				Geo.gen_beam(Sem.add(v_name, "_Sextant_Arm"), v_bottom, v_p, 0.035, 0.035, v_mats["gold"], v_root, 0.008)
		else:
			push_error(str("instrument must be armillary or sextant"))
			return null
	v_dial = Geo.gen_cylinder(Sem.add(v_name, "_Compass"), [Sem.mul(v_width, 0.3), Sem.neg(0.03), Sem.add(v_height, 0.035)], 0.12, 0.04, v_mats["gold"], 12, v_root)
	Geo.gen_cylinder(Sem.add(v_name, "_Compass_Face"), [Sem.mul(v_width, 0.3), Sem.neg(0.03), Sem.add(v_height, 0.058)], 0.092, 0.008, v_mats["cream"], 12, v_root)
	Geo.gen_beam(Sem.add(v_name, "_Compass_Needle"), [Sem.sub(Sem.mul(v_width, 0.3), 0.065), Sem.neg(0.03), Sem.add(v_height, 0.065)], [Sem.add(Sem.mul(v_width, 0.3), 0.065), Sem.neg(0.03), Sem.add(v_height, 0.065)], 0.009, 0.009, v_mats["wood_dark"], v_root, 0.008)
	Geo.gen_group(Sem.add(v_name, "_Measurement_anchor"), [v_cx, Sem.neg(0.1), Sem.add(v_height, 0.4)], 0, v_root)
	v_root["kind"] = "outdoor_instrument"
	v_root["instrument"] = v_instrument
	return v_root

static func gen_lamp_post(v_name, v_mats, v_height = 2.8, v_energy = 22, v_parent = null):
	var v_lantern = null
	var v_r = null
	var v_root = null
	var v_z = null
	v_root = Geo.gen_group(v_name, [0, 0, 0], 0, v_parent)
	Geo.gen_lathe(Sem.add(v_name, "_Pole"), [[0.2, 0], [0.21, 0.12], [0.12, 0.22], [0.07, 0.65], [0.055, Sem.sub(v_height, 0.35)]], 8, v_mats["wood_dark"], v_root, [0, 0, 0])
	for tmp_30 in [[0.12, 0.21], [0.65, 0.1], [Sem.sub(v_height, 0.39), 0.1]]:
		var tmp_31 = tmp_30
		v_z = tmp_31[0]
		v_r = tmp_31[1]
		Geo.gen_cylinder(Sem.add(v_name, "_Gold_Collar"), [0, 0, v_z], v_r, 0.065, v_mats["gold"], 8, v_root)
	v_lantern = load("res://tools/building_construction/BuildingConstruction/Lighting/LightingRecipes.gd").gen_wall_lantern(Sem.add(v_name, "_Lantern"), v_mats, 0.76, v_root, true, v_energy)
	v_lantern.location = [0, 0.18, Sem.sub(v_height, 0.37)]
	return v_root

static func gen_oath_platform(v_name, v_mats, v_width = 4.2, v_depth = 2.4, v_height = 0.6, v_parent = null):
	var v_extra = null
	var v_h = null
	var v_i = null
	var v_root = null
	v_root = Geo.gen_group(v_name, [0, 0, 0], 0, v_parent)
	for tmp_32 in range(3):
		v_i = tmp_32
		v_extra = Sem.mul(Sem.sub(2, v_i), 0.3)
		v_h = Sem.div(v_height, 3)
		Geo.gen_box(Sem.add(v_name, Sem.mod("_Stone_Step_%d", v_i)), [0, Sem.div(Sem.neg(v_extra), 2), Sem.mul(Sem.add(v_i, 0.5), v_h)], [Sem.add(v_width, v_extra), Sem.add(v_depth, v_extra), v_h], v_mats["stone"], 0.012, v_root)
	Geo.gen_box(Sem.add(v_name, "_Top_Trim"), [0, 0, Sem.sub(v_height, 0.022)], [Sem.add(v_width, 0.035), Sem.add(v_depth, 0.035), 0.044], v_mats["cream"], 0.008, v_root)
	v_root["surface_height"] = v_height
	return v_root

static func gen_barrel(v_name, v_mats, v_radius = 0.38, v_height = 0.85, v_parent = null):
	var v_level = null
	var v_profile = null
	var v_r = null
	var v_root = null
	var v_z = null
	v_root = Geo.gen_group(v_name, [0, 0, 0], 0, v_parent)
	v_profile = [[0, 0], [Sem.mul(v_radius, 0.82), 0], [Sem.mul(v_radius, 0.92), Sem.mul(v_height, 0.13)], [v_radius, Sem.mul(v_height, 0.48)], [Sem.mul(v_radius, 0.92), Sem.mul(v_height, 0.87)], [Sem.mul(v_radius, 0.82), v_height], [0, v_height]]
	Geo.gen_lathe(Sem.add(v_name, "_Staves"), v_profile, 12, v_mats["wood"], v_root, [0, 0, 0])
	for tmp_33 in [0.15, 0.5, 0.85]:
		v_level = tmp_33
		v_z = Sem.mul(v_height, v_level)
		v_r = Sem.mul(v_radius, (0.94 if Sem.truth(((v_level != 0.5))) else 1.015))
		Geo.gen_lathe(Sem.add(Sem.add(v_name, "_Band_"), str(v_level)), [[Sem.sub(v_r, 0.015), Sem.sub(v_z, 0.025)], [Sem.add(v_r, 0.012), Sem.sub(v_z, 0.025)], [Sem.add(v_r, 0.012), Sem.add(v_z, 0.025)], [Sem.sub(v_r, 0.015), Sem.add(v_z, 0.025)]], 12, v_mats["gold"], v_root, [0, 0, 0])
	Geo.gen_cylinder(Sem.add(v_name, "_Lid"), [0, 0, Sem.add(v_height, 0.008)], Sem.mul(v_radius, 0.8), 0.025, v_mats["wood_light"], 12, v_root)
	return v_root

static func gen_bollard(v_name, v_mats, v_height = 0.55, v_parent = null):
	var v_root = null
	v_root = Geo.gen_group(v_name, [0, 0, 0], 0, v_parent)
	Geo.gen_cylinder(Sem.add(v_name, "_Foot"), [0, 0, 0.035], 0.25, 0.07, v_mats["gold"], 8, v_root)
	Geo.gen_lathe(Sem.add(v_name, "_Post"), [[0.15, 0.07], [0.12, Sem.sub(v_height, 0.1)], [0.2, Sem.sub(v_height, 0.08)], [0.2, v_height], [0, v_height]], 8, v_mats["gold"], v_root, [0, 0, 0])
	return v_root

static func gen_rope_coil(v_name, v_mats, v_radius = 0.38, v_parent = null):
	var v_angle = null
	var v_i = null
	var v_points = null
	var v_r = null
	var v_root = null
	var v_t = null
	v_root = Geo.gen_group(v_name, [0, 0, 0], 0, v_parent)
	v_points = []
	for tmp_34 in range(97):
		v_i = tmp_34
		v_t = Sem.div(v_i, 96)
		v_angle = Sem.mul(Sem.mul(v_t, PI), 6)
		v_r = Sem.mul(v_radius, Sem.add(0.36, Sem.mul(0.64, v_t)))
		v_points.append([Sem.mul(v_r, cos(v_angle)), Sem.mul(v_r, sin(v_angle)), 0.035])
	for tmp_35 in range(Sem.sub(Sem.py_len(v_points), 1)):
		v_i = tmp_35
		Geo.gen_beam(Sem.add(v_name, Sem.mod("_Segment_%02d", v_i)), v_points[v_i], v_points[Sem.add(v_i, 1)], 0.035, 0.035, v_mats["rope"], v_root, 0)
	return v_root

static func gen_dock(v_name, v_mats, v_width = 2.3, v_length = 3.2, v_parent = null):
	var v_count = null
	var v_i = null
	var v_root = null
	var v_x = null
	var v_y = null
	v_root = Geo.gen_group(v_name, [0, 0, 0], 0, v_parent)
	v_count = Sem.py_max(4, Sem.py_round(Sem.div(v_length, 0.28)))
	for tmp_36 in range(v_count):
		v_i = tmp_36
		v_y = Sem.add(Sem.div(Sem.neg(v_length), 2), Sem.div(Sem.mul(Sem.add(v_i, 0.5), v_length), v_count))
		Geo.gen_box(Sem.add(v_name, Sem.mod("_Deck_Plank_%02d", v_i)), [0, v_y, Sem.neg(0.055)], [v_width, Sem.sub(Sem.div(v_length, v_count), 0.012), 0.11], (v_mats["wood_light"] if Sem.truth(Sem.mod(v_i, 3)) else v_mats["wood"]), 0.008, v_root)
	for tmp_37 in [Sem.mul(Sem.neg(v_width), 0.38), Sem.mul(v_width, 0.38)]:
		v_x = tmp_37
		Geo.gen_box(Sem.add(v_name, "_Stringer"), [v_x, 0, Sem.neg(0.2)], [0.13, Sem.add(v_length, 0.1), 0.22], v_mats["wood_dark"], 0.008, v_root)
	for tmp_38 in [Sem.mul(Sem.neg(v_width), 0.44), Sem.mul(v_width, 0.44)]:
		v_x = tmp_38
		for tmp_39 in [Sem.mul(Sem.neg(v_length), 0.43), Sem.mul(v_length, 0.43)]:
			v_y = tmp_39
			Geo.gen_cylinder(Sem.add(v_name, "_Pile"), [v_x, v_y, Sem.neg(0.13)], 0.105, 1.18, v_mats["wood"], 8, v_root)
			Geo.gen_cylinder(Sem.add(v_name, "_Post_Cap"), [v_x, v_y, 0.47], 0.135, 0.09, v_mats["wood_light"], 8, v_root)
	for tmp_40 in [Sem.mul(Sem.neg(v_width), 0.38), Sem.mul(v_width, 0.38)]:
		v_x = tmp_40
		Geo.gen_beam(Sem.add(v_name, "_Brace"), [v_x, Sem.mul(Sem.neg(v_length), 0.4), Sem.neg(0.61)], [v_x, 0, Sem.neg(0.16)], 0.1, 0.12, v_mats["wood"], v_root, 0.008)
		Geo.gen_beam(Sem.add(v_name, "_Brace"), [v_x, Sem.mul(v_length, 0.4), Sem.neg(0.61)], [v_x, 0, Sem.neg(0.16)], 0.1, 0.12, v_mats["wood"], v_root, 0.008)
	v_root["finished_deck_z"] = 0.0
	return v_root

static func gen_water_patch(v_name, v_mats, v_width = 10, v_depth = 4.2, v_seed = 3, v_parent = null):
	var v_a = null
	var v_b = null
	var v_bottom = null
	var v_c = null
	var v_d = null
	var v_face = null
	var v_faces = null
	var v_i = null
	var v_index = null
	var v_j = null
	var v_nx = null
	var v_ny = null
	var v_obj = null
	var v_perimeter = null
	var v_rng = null
	var v_root = null
	var v_top_count = null
	var v_vertices = null
	var v_x = null
	var v_y = null
	var v_z = null
	v_root = Geo.gen_group(v_name, [0, 0, 0], 0, v_parent)
	v_rng = Sem.RandomSequence.new(v_seed)
	var tmp_41 = [8, 5]
	v_nx = tmp_41[0]
	v_ny = tmp_41[1]
	v_vertices = []
	for tmp_42 in range(Sem.add(v_ny, 1)):
		v_j = tmp_42
		for tmp_43 in range(Sem.add(v_nx, 1)):
			v_i = tmp_43
			v_x = Sem.add(Sem.div(Sem.neg(v_width), 2), Sem.div(Sem.mul(v_width, v_i), v_nx))
			v_y = Sem.add(Sem.div(Sem.neg(v_depth), 2), Sem.div(Sem.mul(v_depth, v_j), v_ny))
			if Sem.truth(((0 < v_i) and (v_i < v_nx))):
				v_x = Sem.add(v_x, v_rng.uniform(Sem.neg(0.18), 0.18))
			if Sem.truth(((0 < v_j) and (v_j < v_ny))):
				v_y = Sem.add(v_y, v_rng.uniform(Sem.neg(0.16), 0.16))
			v_vertices.append([v_x, v_y, v_rng.uniform(Sem.neg(0.012), 0.012)])
	v_faces = []
	for tmp_44 in range(v_ny):
		v_j = tmp_44
		for tmp_45 in range(v_nx):
			v_i = tmp_45
			v_a = Sem.add(Sem.mul(v_j, Sem.add(v_nx, 1)), v_i)
			v_b = Sem.add(v_a, 1)
			v_c = Sem.add(Sem.add(v_a, v_nx), 2)
			v_d = Sem.add(Sem.add(v_a, v_nx), 1)
			v_faces.append_array(([[v_a, v_b, v_c], [v_a, v_c, v_d]] if Sem.truth(Sem.mod(Sem.add(v_i, v_j), 2)) else [[v_a, v_b, v_d], [v_b, v_c, v_d]]))
	v_top_count = Sem.py_len(v_faces)
	v_perimeter = Sem.add(Sem.py_list(range(Sem.add(v_nx, 1))), Sem.map_array(range(1, Sem.add(v_ny, 1)), func(tmp_46): var tmp_47 = tmp_46; return Sem.add(Sem.mul(tmp_47, Sem.add(v_nx, 1)), v_nx)))
	v_perimeter = Sem.add(v_perimeter, Sem.add(Sem.py_list(range(Sem.sub(Sem.add(Sem.mul(v_ny, Sem.add(v_nx, 1)), v_nx), 1), Sem.sub(Sem.mul(v_ny, Sem.add(v_nx, 1)), 1), Sem.neg(1))), Sem.map_array(range(Sem.sub(v_ny, 1), 0, Sem.neg(1)), func(tmp_48): var tmp_49 = tmp_48; return Sem.mul(tmp_49, Sem.add(v_nx, 1)))))
	v_bottom = []
	for tmp_50 in v_perimeter:
		v_index = tmp_50
		var tmp_51 = v_vertices[v_index]
		v_x = tmp_51[0]
		v_y = tmp_51[1]
		v_z = tmp_51[2]
		v_bottom.append(Sem.py_len(v_vertices))
		v_vertices.append([v_x, v_y, Sem.neg(0.17)])
	for tmp_52 in Sem.py_enumerate(v_perimeter):
		var tmp_53 = tmp_52
		v_i = tmp_53[0]
		v_index = tmp_53[1]
		v_j = Sem.mod(Sem.add(v_i, 1), Sem.py_len(v_perimeter))
		v_faces.append([v_index, v_bottom[v_i], v_bottom[v_j], v_perimeter[v_j]])
	v_faces.append(Sem.py_tuple(Sem.py_reversed(v_bottom)))
	v_obj = Geo.gen_mesh(Sem.add(v_name, "_Faceted_Water"), v_vertices, v_faces, v_mats["water_0"], v_root, 0)
	for tmp_54 in range(1, 4):
		v_i = tmp_54
		v_obj.data.materials.append(v_mats[Sem.add("water_", str(v_i))])
	for tmp_55 in Sem.py_enumerate(v_obj.data.polygons):
		var tmp_56 = tmp_55
		v_i = tmp_56[0]
		v_face = tmp_56[1]
		v_face.material_index = (v_rng.randrange(4) if Sem.truth(((v_i < v_top_count))) else 0)
	v_root["kind"] = "faceted_water"
	v_root["water_rendering"] = "Opaque mesh facets, four constant colours."
	return v_root

static func gen_rowboat(v_name, v_mats, v_length = 2.6, v_width = 1.05, v_height = 0.55, v_parent = null):
	var v_face = null
	var v_faces = null
	var v_i = null
	var v_j = null
	var v_n = null
	var v_obj = null
	var v_ring = null
	var v_root = null
	var v_scale = null
	var v_shape = null
	var v_verts = null
	var v_x = null
	var v_xx = null
	var v_y = null
	var v_yy = null
	var v_z = null
	v_root = Geo.gen_group(v_name, [0, 0, 0], 0, v_parent)
	v_shape = [[Sem.div(Sem.neg(v_width), 2), Sem.mul(v_length, 0.34)], [Sem.mul(Sem.neg(v_width), 0.43), Sem.mul(Sem.neg(v_length), 0.25)], [0, Sem.div(Sem.neg(v_length), 2)], [Sem.mul(v_width, 0.43), Sem.mul(Sem.neg(v_length), 0.25)], [Sem.div(v_width, 2), Sem.mul(v_length, 0.34)], [Sem.mul(v_width, 0.3), Sem.div(v_length, 2)], [Sem.mul(Sem.neg(v_width), 0.3), Sem.div(v_length, 2)]]
	v_n = Sem.py_len(v_shape)
	v_verts = []
	for tmp_57 in [[0.45, 0], [1, v_height], [0.86, v_height], [0.4, 0.1]]:
		var tmp_58 = tmp_57
		v_scale = tmp_58[0]
		v_z = tmp_58[1]
		v_verts.append_array(Sem.map_array(v_shape, func(tmp_59): var tmp_60 = tmp_59[0]; var tmp_61 = tmp_59[1]; return [Sem.mul(tmp_60, v_scale), Sem.mul(tmp_61, v_scale), v_z]))
	v_faces = [Sem.py_tuple(Sem.py_reversed(range(v_n))), Sem.py_tuple(range(Sem.mul(3, v_n), Sem.mul(4, v_n)))]
	for tmp_62 in range(3):
		v_ring = tmp_62
		for tmp_63 in range(v_n):
			v_i = tmp_63
			v_j = Sem.mod(Sem.add(v_i, 1), v_n)
			v_faces.append([Sem.add(Sem.mul(v_ring, v_n), v_i), Sem.add(Sem.mul(v_ring, v_n), v_j), Sem.add(Sem.mul(Sem.add(v_ring, 1), v_n), v_j), Sem.add(Sem.mul(Sem.add(v_ring, 1), v_n), v_i)])
	v_obj = Geo.gen_mesh(Sem.add(v_name, "_Hollow_Hull"), v_verts, v_faces, v_mats["wood"], v_root, 0.006)
	v_obj.data.materials.append(v_mats["wood_light"])
	for tmp_64 in Sem.py_enumerate(v_obj.data.polygons):
		var tmp_65 = tmp_64
		v_i = tmp_65[0]
		v_face = tmp_65[1]
		if Sem.truth(Sem.either_lazy(((v_i == 1)), func(): return ((v_i >= Sem.add(2, v_n))))):
			v_face.material_index = 1
	for tmp_66 in Sem.py_enumerate(v_shape):
		var tmp_67 = tmp_66
		v_i = tmp_67[0]
		var tmp_68 = tmp_67[1]
		v_x = tmp_68[0]
		v_y = tmp_68[1]
		var tmp_69 = v_shape[Sem.mod(Sem.add(v_i, 1), v_n)]
		v_xx = tmp_69[0]
		v_yy = tmp_69[1]
		Geo.gen_beam(Sem.add(v_name, Sem.mod("_Gunwale_%02d", v_i)), [v_x, v_y, v_height], [v_xx, v_yy, v_height], 0.045, 0.055, v_mats["wood_light"], v_root, 0.004)
	for tmp_70 in [Sem.mul(Sem.neg(v_length), 0.13), Sem.mul(v_length, 0.22)]:
		v_y = tmp_70
		Geo.gen_box(Sem.add(v_name, "_Seat"), [0, v_y, Sem.mul(v_height, 0.64)], [Sem.mul(v_width, 0.78), 0.18, 0.055], v_mats["wood_light"], 0.008, v_root)
	return v_root

