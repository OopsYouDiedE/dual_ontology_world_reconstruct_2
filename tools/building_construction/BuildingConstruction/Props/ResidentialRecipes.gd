@tool
extends RefCounted

# Direct port of kit/residential_props.py. Z-up recipe coordinates convert at the geometry boundary.
const Sem = preload("res://tools/building_construction/BuildingConstruction/Shared/RecipeSemantics.gd")
const Geo = preload("res://tools/building_construction/BuildingConstruction/Shared/RecipeGeometry.gd")
const EPS = 1e-9

static func gen_paneled_bed(v_name, v_mats, v_width = 1.35, v_length = 2.25, v_height = 0.56, v_parent = null):
	var v_root = null
	var v_top = null
	var v_x = null
	var v_y = null
	v_root = load("res://tools/building_construction/BuildingConstruction/Props/SpecialRecipes.gd").gen_bed(v_name, v_mats, v_width, v_length, v_height, false, v_parent)
	for tmp_1 in [[Sem.mul(v_length, 0.47), 1.28], [Sem.mul(Sem.neg(v_length), 0.47), 0.82]]:
		var tmp_2 = tmp_1
		v_y = tmp_2[0]
		v_top = tmp_2[1]
		for tmp_3 in [Sem.mul(Sem.neg(v_width), 0.5), Sem.mul(v_width, 0.5)]:
			v_x = tmp_3
			Geo.gen_box(Sem.add(v_name, "_Post"), [v_x, v_y, Sem.mul(v_top, 0.5)], [0.12, 0.13, v_top], v_mats["wood"], 0.012, v_root)
			Geo.gen_box(Sem.add(v_name, "_Cap"), [v_x, v_y, Sem.add(v_top, 0.025)], [0.18, 0.18, 0.06], v_mats["wood_light"], 0.01, v_root)
		Geo.gen_box(Sem.add(v_name, "_Crown"), [0, v_y, Sem.sub(v_top, 0.06)], [v_width, 0.13, 0.09], v_mats["wood_light"], 0.01, v_root)
	Geo.gen_box(Sem.add(v_name, "_FootDrape"), [0, Sem.mul(Sem.neg(v_length), 0.39), Sem.sub(v_height, 0.04)], [Sem.mul(v_width, 0.92), 0.045, 0.24], v_mats["green"], 0.01, v_root)
	return v_root

static func gen_framed_mirror(v_name, v_mats, v_width = 0.65, v_height = 0.95, v_parent = null):
	var v_cut = null
	var v_glass = null
	var v_inset = null
	var v_panel = null
	var v_pts = null
	var v_root = null
	var v_x = null
	var v_z = null
	v_root = Geo.gen_group(v_name, [0, 0, 0], 0, v_parent)
	v_cut = Sem.mul(Sem.py_min(v_width, v_height), 0.15)
	v_pts = [[Sem.div(Sem.neg(v_width), 2), 0], [Sem.div(v_width, 2), 0], [Sem.div(v_width, 2), Sem.sub(v_height, v_cut)], [Sem.sub(Sem.div(v_width, 2), v_cut), v_height], [Sem.add(Sem.div(Sem.neg(v_width), 2), v_cut), v_height], [Sem.div(Sem.neg(v_width), 2), Sem.sub(v_height, v_cut)]]
	v_panel = Geo.gen_polyprism(Sem.add(v_name, "_Frame"), v_pts, Sem.neg(0.022), 0.022, v_mats["gold"], v_root)
	v_panel.rotation_euler[0] = Sem.div(PI, 2)
	v_inset = Sem.map_array(v_pts, func(tmp_4): var tmp_5 = tmp_4[0]; var tmp_6 = tmp_4[1]; return [Sem.mul(tmp_5, 0.86), Sem.add(Sem.mul(Sem.sub(tmp_6, Sem.mul(v_height, 0.5)), 0.88), Sem.mul(v_height, 0.5))])
	v_glass = Geo.gen_polyprism(Sem.add(v_name, "_Glass"), v_inset, 0.026, 0.03, v_mats["grout"], v_root)
	v_glass.rotation_euler[0] = Sem.div(PI, 2)
	Geo.gen_beam(Sem.add(v_name, "_Highlight"), [Sem.mul(Sem.neg(v_width), 0.22), Sem.neg(0.034), Sem.mul(v_height, 0.25)], [Sem.mul(v_width, 0.2), Sem.neg(0.034), Sem.mul(v_height, 0.68)], 0.012, 0.007, v_mats["stone"], v_root, 0)
	return v_root

static func gen_pitcher(v_name, v_mats, v_radius = 0.11, v_height = 0.3, v_parent = null):
	var v_a = null
	var v_b = null
	var v_root = null
	v_root = Geo.gen_group(v_name, [0, 0, 0], 0, v_parent)
	Geo.gen_lathe(Sem.add(v_name, "_Body"), [[0, 0], [Sem.mul(v_radius, 0.55), 0], [Sem.mul(v_radius, 0.85), Sem.mul(v_height, 0.12)], [v_radius, Sem.mul(v_height, 0.46)], [Sem.mul(v_radius, 0.55), Sem.mul(v_height, 0.76)], [Sem.mul(v_radius, 0.55), v_height], [Sem.mul(v_radius, 0.43), v_height], [Sem.mul(v_radius, 0.42), Sem.mul(v_height, 0.79)], [Sem.mul(v_radius, 0.76), Sem.mul(v_height, 0.46)], [Sem.mul(v_radius, 0.53), Sem.mul(v_height, 0.15)], [0, Sem.mul(v_height, 0.15)]], 10, v_mats["cream"], v_root, [0, 0, 0])
	for tmp_7 in [[[Sem.mul(v_radius, 0.55), 0, Sem.mul(v_height, 0.83)], [Sem.mul(v_radius, 1.55), 0, Sem.mul(v_height, 0.78)]], [[Sem.mul(v_radius, 1.55), 0, Sem.mul(v_height, 0.78)], [Sem.mul(v_radius, 1.5), 0, Sem.mul(v_height, 0.25)]], [[Sem.mul(v_radius, 1.5), 0, Sem.mul(v_height, 0.25)], [Sem.mul(v_radius, 0.85), 0, Sem.mul(v_height, 0.28)]]]:
		var tmp_8 = tmp_7
		v_a = tmp_8[0]
		v_b = tmp_8[1]
		Geo.gen_beam(Sem.add(v_name, "_Handle"), v_a, v_b, 0.025, 0.028, v_mats["cream"], v_root, 0.008)
	return v_root

static func gen_wash_table(v_name, v_mats, v_width = 0.98, v_depth = 0.6, v_height = 0.86, v_mirror = true, v_parent = null):
	var v_bowl = null
	var v_jug = null
	var v_m = null
	var v_root = null
	var v_x = null
	v_root = Geo.gen_group(v_name, [0, 0, 0], 0, v_parent)
	load("res://tools/building_construction/BuildingConstruction/Props/SpecialRecipes.gd").gen_cabinet(Sem.add(v_name, "_Case"), v_mats, v_width, v_depth, Sem.sub(v_height, 0.05), 0, v_root)
	Geo.gen_box(Sem.add(v_name, "_Top"), [0, 0, Sem.sub(v_height, 0.025)], [Sem.add(v_width, 0.09), Sem.add(v_depth, 0.06), 0.07], v_mats["wood_light"], 0.012, v_root)
	v_bowl = load("res://tools/building_construction/BuildingConstruction/Props/SpecialRecipes.gd").gen_vessel(Sem.add(v_name, "_Bowl"), v_mats, Sem.mul(v_width, 0.24), 0.12, "plate", v_root)
	v_bowl.location = [Sem.mul(Sem.neg(v_width), 0.14), Sem.neg(0.04), Sem.add(v_height, 0.014)]
	v_jug = gen_pitcher(Sem.add(v_name, "_Jug"), v_mats, 0.11, 0.3, v_root)
	v_jug.location = [Sem.mul(v_width, 0.29), 0.08, Sem.add(v_height, 0.014)]
	for tmp_9 in [Sem.mul(Sem.neg(v_width), 0.46), Sem.mul(v_width, 0.46)]:
		v_x = tmp_9
		Geo.gen_box(Sem.add(v_name, "_SplashSide"), [v_x, Sem.mul(v_depth, 0.29), Sem.add(v_height, 0.08)], [0.035, Sem.mul(v_depth, 0.34), 0.17], v_mats["wood"], 0.008, v_root)
	if Sem.truth(v_mirror):
		for tmp_10 in [Sem.mul(Sem.neg(v_width), 0.25), Sem.mul(v_width, 0.25)]:
			v_x = tmp_10
			Geo.gen_box(Sem.add(v_name, "_MirrorSupport"), [v_x, Sem.mul(v_depth, 0.5), Sem.add(v_height, 0.25)], [0.035, 0.05, 0.54], v_mats["wood"], 0.005, v_root)
		v_m = gen_framed_mirror(Sem.add(v_name, "_Mirror"), v_mats, Sem.mul(v_width, 0.65), 0.88, v_root)
		v_m.location = [0, Sem.mul(v_depth, 0.5), Sem.add(v_height, 0.3)]
	return v_root

static func gen_rug(v_name, v_mats, v_width = 2.1, v_depth = 1.4, v_parent = null):
	var v_root = null
	v_root = Geo.gen_group(v_name, [0, 0, 0], 0, v_parent)
	Geo.gen_box(Sem.add(v_name, "_Border"), [0, 0, 0.009], [v_width, v_depth, 0.018], v_mats["stone"], 0.004, v_root)
	Geo.gen_box(Sem.add(v_name, "_Field"), [0, 0, 0.02], [Sem.sub(v_width, 0.1), Sem.sub(v_depth, 0.1), 0.015], v_mats["book_green"], 0.002, v_root)
	return v_root

static func gen_slate_table(v_name, v_mats, v_width = 2.3, v_depth = 1.3, v_height = 0.8, v_parent = null):
	var v_root = null
	var v_y = null
	v_root = load("res://tools/building_construction/BuildingConstruction/Tables/FurnitureRecipes.gd").gen_table(v_name, v_mats, v_width, v_depth, v_height, "rect", v_parent)
	Geo.gen_box(Sem.add(v_name, "_Inset"), [0, 0, Sem.add(v_height, 0.006)], [Sem.sub(v_width, 0.17), Sem.sub(v_depth, 0.17), 0.014], v_mats["stone_dark"], 0.006, v_root)
	for tmp_11 in [Sem.mul(Sem.neg(v_depth), 0.44), Sem.mul(v_depth, 0.44)]:
		v_y = tmp_11
		Geo.gen_box(Sem.add(v_name, "_FineBorder"), [0, v_y, Sem.add(v_height, 0.015)], [Sem.mul(v_width, 0.9), 0.018, 0.012], v_mats["gold"], 0.002, v_root)
	return v_root

static func gen_folding_desk(v_name, v_mats, v_width = 1.2, v_depth = 0.65, v_height = 0.78, v_parent = null):
	var v_root = null
	var v_x = null
	v_root = Geo.gen_group(v_name, [0, 0, 0], 0, v_parent)
	Geo.gen_box(Sem.add(v_name, "_Top"), [0, 0, Sem.sub(v_height, 0.035)], [v_width, v_depth, 0.07], v_mats["wood_light"], 0.012, v_root)
	Geo.gen_box(Sem.add(v_name, "_WallRail"), [0, Sem.mul(v_depth, 0.44), Sem.sub(v_height, 0.13)], [v_width, 0.065, 0.15], v_mats["wood"], 0.01, v_root)
	for tmp_12 in [Sem.mul(Sem.neg(v_width), 0.32), Sem.mul(v_width, 0.32)]:
		v_x = tmp_12
		Geo.gen_beam(Sem.add(v_name, "_FoldingBracket"), [v_x, Sem.mul(v_depth, 0.43), Sem.sub(v_height, 0.46)], [v_x, Sem.mul(Sem.neg(v_depth), 0.35), Sem.sub(v_height, 0.075)], 0.05, 0.05, v_mats["gold"], v_root, 0.008)
		Geo.gen_cylinder(Sem.add(v_name, "_Hinge"), [v_x, Sem.mul(v_depth, 0.43), Sem.sub(v_height, 0.1)], 0.055, 0.1, v_mats["gold"], 8, v_root)
	return v_root

static func gen_go_board(v_name, v_mats, v_size = 0.72, v_lines = 19, v_parent = null):
	var v_batch = null
	var v_border = null
	var v_c = null
	var v_i = null
	var v_j = null
	var v_mat = null
	var v_r = null
	var v_root = null
	var v_span = null
	var v_step = null
	var v_t = null
	var v_thick = null
	var v_x = null
	if Sem.truth(((int(v_lines) != 19))):
		push_error(str("The approved Go board uses 19 lines."))
		return null
	v_root = Geo.gen_group(v_name, [0, 0, 0], 0, v_parent)
	Geo.gen_box(Sem.add(v_name, "_Board"), [0, 0, 0.025], [v_size, v_size, 0.05], v_mats["wood_light"], 0.008, v_root)
	v_border = Sem.mul(v_size, 0.065)
	v_span = Sem.sub(v_size, Sem.mul(2, v_border))
	v_step = Sem.div(v_span, Sem.sub(v_lines, 1))
	v_batch = Geo.Batch.new()
	for tmp_13 in range(v_lines):
		v_i = tmp_13
		v_t = Sem.add(Sem.div(Sem.neg(v_span), 2), Sem.mul(v_i, v_step))
		v_thick = Sem.mul(v_size, 0.0023)
		v_batch.prism([[Sem.div(Sem.neg(v_span), 2), Sem.sub(v_t, v_thick)], [Sem.div(v_span, 2), Sem.sub(v_t, v_thick)], [Sem.div(v_span, 2), Sem.add(v_t, v_thick)], [Sem.div(Sem.neg(v_span), 2), Sem.add(v_t, v_thick)]], 0.05, 0.052)
		v_batch.prism([[Sem.sub(v_t, v_thick), Sem.div(Sem.neg(v_span), 2)], [Sem.add(v_t, v_thick), Sem.div(Sem.neg(v_span), 2)], [Sem.add(v_t, v_thick), Sem.div(v_span, 2)], [Sem.sub(v_t, v_thick), Sem.div(v_span, 2)]], 0.05, 0.052)
	v_batch.finish(Sem.add(v_name, "_19x19Grid"), v_mats["wood_dark"], v_root)
	for tmp_14 in [3, 9, 15]:
		v_r = tmp_14
		for tmp_15 in [3, 9, 15]:
			v_c = tmp_15
			Geo.gen_cylinder(Sem.add(v_name, "_Star"), [Sem.add(Sem.div(Sem.neg(v_span), 2), Sem.mul(v_c, v_step)), Sem.add(Sem.div(Sem.neg(v_span), 2), Sem.mul(v_r, v_step)), 0.053], Sem.mul(v_size, 0.005), 0.003, v_mats["wood_dark"], 8, v_root)
	for tmp_16 in Sem.py_enumerate([[3, 3], [15, 15], [3, 15], [15, 3], [9, 9], [8, 9], [9, 8], [10, 10], [5, 6], [5, 7], [6, 6], [7, 7]]):
		var tmp_17 = tmp_16
		v_j = tmp_17[0]
		var tmp_18 = tmp_17[1]
		v_r = tmp_18[0]
		v_c = tmp_18[1]
		Geo.gen_lathe(Sem.add(v_name, "_Stone"), [[0, 0], [Sem.mul(v_step, 0.38), 0], [Sem.mul(v_step, 0.46), 0.007], [Sem.mul(v_step, 0.39), 0.016], [0, 0.023]], 10, (v_mats["wood_dark"] if Sem.truth(((Sem.mod(v_j, 2) == 0))) else v_mats["cream"]), v_root, [Sem.add(Sem.div(Sem.neg(v_span), 2), Sem.mul(v_c, v_step)), Sem.add(Sem.div(Sem.neg(v_span), 2), Sem.mul(v_r, v_step)), 0.054])
	for tmp_19 in [[Sem.mul(Sem.neg(v_size), 0.72), v_mats["wood_dark"]], [Sem.mul(v_size, 0.72), v_mats["cream"]]]:
		var tmp_20 = tmp_19
		v_x = tmp_20[0]
		v_mat = tmp_20[1]
		Geo.gen_lathe(Sem.add(v_name, "_Bowl"), [[0, 0], [0.1, 0], [0.13, 0.09], [0.12, 0.12], [0.1, 0.12], [0.08, 0.04], [0, 0.04]], 10, v_mats["wood"], v_root, [v_x, 0, 0])
		Geo.gen_ico(Sem.add(v_name, "_Reserve"), [v_x, 0, 0.09], 0.068, v_mat, 1, v_root)
	v_root["grid_lines"] = 19
	v_root["story_position"] = "visual_placeholder_not_authored_evidence"
	return v_root

static func gen_music_stand(v_name, v_mats, v_width = 0.52, v_height = 1.25, v_parent = null):
	var v_a = null
	var v_root = null
	var v_row = null
	var v_tray = null
	v_root = Geo.gen_group(v_name, [0, 0, 0], 0, v_parent)
	for tmp_21 in [0, 2.094, 4.189]:
		v_a = tmp_21
		Geo.gen_beam(Sem.add(v_name, "_Foot"), [0, 0, 0.08], [Sem.mul(0.24, cos(v_a)), Sem.mul(0.24, sin(v_a)), 0.04], 0.045, 0.045, v_mats["wood"], v_root, 0.008)
	Geo.gen_beam(Sem.add(v_name, "_Stem"), [0, 0, 0.06], [0, 0, Sem.sub(v_height, 0.2)], 0.045, 0.045, v_mats["gold"], v_root, 0.008)
	v_tray = Geo.gen_group(Sem.add(v_name, "_Tray"), [0, 0, Sem.sub(v_height, 0.18)], 0, v_root)
	v_tray.rotation_euler[0] = deg_to_rad(20)
	Geo.gen_box(Sem.add(v_name, "_Back"), [0, 0, 0.18], [v_width, 0.045, 0.38], v_mats["wood"], 0.008, v_tray)
	Geo.gen_box(Sem.add(v_name, "_Score"), [0, Sem.neg(0.027), 0.19], [Sem.mul(v_width, 0.84), 0.009, 0.3], v_mats["cream"], 0.002, v_tray)
	Geo.gen_box(Sem.add(v_name, "_Rest"), [0, Sem.neg(0.05), 0.015], [Sem.add(v_width, 0.03), 0.13, 0.035], v_mats["wood_light"], 0.006, v_tray)
	for tmp_22 in range(5):
		v_row = tmp_22
		Geo.gen_box(Sem.add(v_name, "_Staff"), [0, Sem.neg(0.034), Sem.add(0.09, Sem.mul(v_row, 0.045))], [Sem.mul(v_width, 0.65), 0.005, 0.007], v_mats["stone_dark"], 0, v_tray)
	return v_root

static func gen_keyboard(v_name, v_mats, v_width = 1.7, v_depth = 0.7, v_height = 1.45, v_parent = null):
	var v_i = null
	var v_kw = null
	var v_n = null
	var v_root = null
	var v_score = null
	var v_x = null
	v_root = Geo.gen_group(v_name, [0, 0, 0], 0, v_parent)
	load("res://tools/building_construction/BuildingConstruction/Props/SpecialRecipes.gd").gen_cabinet(Sem.add(v_name, "_Case"), v_mats, v_width, Sem.mul(v_depth, 0.65), v_height, 0, v_root)
	Geo.gen_box(Sem.add(v_name, "_KeyboardBed"), [0, Sem.mul(Sem.neg(v_depth), 0.36), 0.82], [Sem.add(v_width, 0.08), Sem.mul(v_depth, 0.45), 0.11], v_mats["wood_light"], 0.012, v_root)
	v_n = 28
	v_kw = Sem.div(Sem.sub(v_width, 0.18), v_n)
	for tmp_23 in range(v_n):
		v_i = tmp_23
		v_x = Sem.add(Sem.add(Sem.div(Sem.neg(v_width), 2), 0.09), Sem.mul(Sem.add(v_i, 0.5), v_kw))
		Geo.gen_box(Sem.add(v_name, "_IvoryKey"), [v_x, Sem.mul(Sem.neg(v_depth), 0.4), 0.89], [Sem.sub(v_kw, 0.002), Sem.mul(v_depth, 0.33), 0.025], v_mats["cream"], 0.001, v_root)
		if Sem.truth(Sem.both_lazy(((Sem.mod(v_i, 7) not in [2, 6])), func(): return ((v_i < Sem.sub(v_n, 1))))):
			Geo.gen_box(Sem.add(v_name, "_BlackKey"), [Sem.add(v_x, Sem.mul(v_kw, 0.5)), Sem.mul(Sem.neg(v_depth), 0.32), 0.916], [Sem.mul(v_kw, 0.55), Sem.mul(v_depth, 0.17), 0.035], v_mats["wood_dark"], 0.001, v_root)
	for tmp_24 in [Sem.mul(Sem.neg(v_width), 0.44), Sem.mul(v_width, 0.44)]:
		v_x = tmp_24
		Geo.gen_box(Sem.add(v_name, "_FrontLeg"), [v_x, Sem.mul(Sem.neg(v_depth), 0.42), 0.39], [0.09, 0.09, 0.78], v_mats["wood"], 0.008, v_root)
	v_score = gen_music_stand(Sem.add(v_name, "_ScoreDesk"), v_mats, 0.58, 0.43, v_root)
	v_score.location = [0, Sem.mul(Sem.neg(v_depth), 0.15), 0.95]
	for tmp_25 in [Sem.neg(0.14), 0, 0.14]:
		v_x = tmp_25
		Geo.gen_box(Sem.add(v_name, "_Pedal"), [v_x, Sem.mul(Sem.neg(v_depth), 0.39), 0.075], [0.055, 0.2, 0.028], v_mats["gold"], 0.005, v_root)
	return v_root

static func gen_cooker_hood(v_name, v_mats, v_width = 1.6, v_depth = 0.78, v_height = 1.65, v_parent = null):
	var v_root = null
	var v_verts = null
	var v_x = null
	v_root = Geo.gen_group(v_name, [0, 0, 0], 0, v_parent)
	v_verts = [[Sem.div(Sem.neg(v_width), 2), Sem.div(Sem.neg(v_depth), 2), 0], [Sem.div(v_width, 2), Sem.div(Sem.neg(v_depth), 2), 0], [Sem.div(v_width, 2), Sem.div(v_depth, 2), 0], [Sem.div(Sem.neg(v_width), 2), Sem.div(v_depth, 2), 0], [Sem.mul(Sem.neg(v_width), 0.19), Sem.mul(Sem.neg(v_depth), 0.18), 0.57], [Sem.mul(v_width, 0.19), Sem.mul(Sem.neg(v_depth), 0.18), 0.57], [Sem.mul(v_width, 0.19), Sem.mul(v_depth, 0.18), 0.57], [Sem.mul(Sem.neg(v_width), 0.19), Sem.mul(v_depth, 0.18), 0.57]]
	Geo.gen_mesh(Sem.add(v_name, "_Canopy"), v_verts, [[0, 1, 5, 4], [1, 2, 6, 5], [2, 3, 7, 6], [3, 0, 4, 7], [4, 5, 6, 7], [3, 2, 1, 0]], v_mats["stone_dark"], v_root, 0.008)
	Geo.gen_box(Sem.add(v_name, "_Rim"), [0, 0, 0.035], [Sem.add(v_width, 0.06), Sem.add(v_depth, 0.05), 0.09], v_mats["stone_dark"], 0.01, v_root)
	Geo.gen_box(Sem.add(v_name, "_Flue"), [0, Sem.mul(v_depth, 0.04), Sem.div(Sem.add(0.57, v_height), 2)], [Sem.mul(v_width, 0.36), Sem.mul(v_depth, 0.36), Sem.sub(v_height, 0.57)], v_mats["stone_dark"], 0.01, v_root)
	for tmp_26 in [Sem.mul(Sem.neg(v_width), 0.4), Sem.mul(v_width, 0.4)]:
		v_x = tmp_26
		Geo.gen_beam(Sem.add(v_name, "_Bracket"), [v_x, Sem.mul(v_depth, 0.43), Sem.neg(0.48)], [v_x, Sem.mul(Sem.neg(v_depth), 0.3), 0], 0.065, 0.065, v_mats["wood_dark"], v_root, 0.008)
	return v_root

static func gen_crockery_shelf(v_name, v_mats, v_width = 1.65, v_parent = null):
	var v_i = null
	var v_j = null
	var v_p = null
	var v_root = null
	var v_x = null
	var v_z = null
	v_root = Geo.gen_group(v_name, [0, 0, 0], 0, v_parent)
	for tmp_27 in [0, 0.48]:
		v_z = tmp_27
		Geo.gen_box(Sem.add(v_name, "_Shelf"), [0, 0, v_z], [v_width, 0.34, 0.07], v_mats["wood_light"], 0.009, v_root)
		for tmp_28 in [Sem.mul(Sem.neg(v_width), 0.36), Sem.mul(v_width, 0.36)]:
			v_x = tmp_28
			Geo.gen_beam(Sem.add(v_name, "_Bracket"), [v_x, 0.13, Sem.sub(v_z, 0.23)], [v_x, Sem.neg(0.12), Sem.sub(v_z, 0.045)], 0.05, 0.05, v_mats["wood"], v_root, 0.008)
	for tmp_29 in range(4):
		v_i = tmp_29
		if Sem.truth(((v_i < 2))):
			v_p = gen_pitcher(Sem.add(v_name, "_Jug"), v_mats, 0.105, 0.3, v_root)
			v_p.location = [Sem.add(Sem.mul(Sem.neg(v_width), 0.32), Sem.mul(Sem.mul(v_i, v_width), 0.21)), 0, 0.52]
		for tmp_30 in range((2 if Sem.truth(Sem.mod(v_i, 2)) else 3)):
			v_j = tmp_30
			v_p = load("res://tools/building_construction/BuildingConstruction/Props/SpecialRecipes.gd").gen_vessel(Sem.add(v_name, "_Bowl"), v_mats, 0.12, 0.065, "plate", v_root)
			v_p.location = [Sem.add(Sem.mul(Sem.neg(v_width), 0.33), Sem.mul(Sem.mul(v_i, v_width), 0.22)), Sem.neg(0.02), Sem.add(0.04, Sem.mul(v_j, 0.035))]
	return v_root

static func gen_linen_cabinet(v_name, v_mats, v_width = 0.85, v_height = 1.9, v_parent = null):
	var v_depth = null
	var v_j = null
	var v_root = null
	var v_row = null
	var v_x = null
	var v_z = null
	v_root = Geo.gen_group(v_name, [0, 0, 0], 0, v_parent)
	v_depth = 0.45
	load("res://tools/building_construction/BuildingConstruction/Props/SpecialRecipes.gd").gen_cabinet(Sem.add(v_name, "_Lower"), v_mats, v_width, v_depth, Sem.mul(v_height, 0.43), 0, v_root)
	Geo.gen_box(Sem.add(v_name, "_Back"), [0, Sem.mul(v_depth, 0.45), Sem.mul(v_height, 0.7)], [v_width, 0.06, Sem.mul(v_height, 0.6)], v_mats["wood_dark"], 0.005, v_root)
	for tmp_31 in [Sem.mul(Sem.neg(v_width), 0.47), Sem.mul(v_width, 0.47)]:
		v_x = tmp_31
		Geo.gen_box(Sem.add(v_name, "_Side"), [v_x, 0, Sem.mul(v_height, 0.7)], [0.06, v_depth, Sem.mul(v_height, 0.6)], v_mats["wood"], 0.007, v_root)
	for tmp_32 in [Sem.mul(v_height, 0.48), Sem.mul(v_height, 0.72), v_height]:
		v_z = tmp_32
		Geo.gen_box(Sem.add(v_name, "_Shelf"), [0, 0, v_z], [Sem.add(v_width, 0.04), Sem.add(v_depth, 0.03), 0.055], v_mats["wood_light"], 0.007, v_root)
	for tmp_33 in [0, 1]:
		v_row = tmp_33
		for tmp_34 in range(3):
			v_j = tmp_34
			Geo.gen_box(Sem.add(v_name, "_FoldedLinen"), [0, Sem.neg(0.015), Sem.add(Sem.add(Sem.mul(v_height, Sem.add(0.48, Sem.mul(v_row, 0.24))), 0.07), Sem.mul(v_j, 0.063))], [Sem.mul(v_width, 0.76), Sem.mul(v_depth, 0.73), 0.057], v_mats["cream"], 0.013, v_root)
	return v_root

static func gen_speaking_tube(v_name, v_mats, v_height = 1.8, v_parent = null):
	var v_bell = null
	var v_root = null
	var v_z = null
	v_root = Geo.gen_group(v_name, [0, 0, 0], 0, v_parent)
	Geo.gen_beam(Sem.add(v_name, "_Pipe"), [0, 0.07, 0], [0, 0.07, v_height], 0.065, 0.065, v_mats["gold"], v_root, 0.008)
	for tmp_35 in [0.18, Sem.sub(v_height, 0.16)]:
		v_z = tmp_35
		Geo.gen_box(Sem.add(v_name, "_WallClamp"), [0, 0.12, v_z], [0.15, 0.1, 0.08], v_mats["wood_dark"], 0.006, v_root)
	v_bell = Geo.gen_lathe(Sem.add(v_name, "_Mouth"), [[0.035, 0], [0.04, 0.1], [0.13, 0.22], [0.12, 0.25], [0.09, 0.23], [0.025, 0.1]], 8, v_mats["gold"], v_root, [0, 0, 0])
	v_bell.rotation_euler[0] = Sem.div(PI, 2)
	v_bell.location = [0, 0.06, 0.45]
	return v_root

static func gen_pressure_panel(v_name, v_mats, v_width = 0.65, v_height = 0.75, v_parent = null):
	var v_c = null
	var v_mat = null
	var v_rad = null
	var v_root = null
	var v_z = null
	v_root = Geo.gen_group(v_name, [0, 0, 0], 0, v_parent)
	Geo.gen_box(Sem.add(v_name, "_Mount"), [0, 0, Sem.div(v_height, 2)], [v_width, 0.11, v_height], v_mats["wood_dark"], 0.012, v_root)
	for tmp_36 in [[Sem.mul(v_height, 0.65), 0.18, v_mats["gold"]], [Sem.mul(v_height, 0.65), 0.145, v_mats["cream"]]]:
		var tmp_37 = tmp_36
		v_z = tmp_37[0]
		v_rad = tmp_37[1]
		v_mat = tmp_37[2]
		v_c = Geo.gen_cylinder(Sem.add(v_name, "_Gauge"), [0, Sem.neg(0.078), v_z], v_rad, 0.035, v_mat, 12, v_root)
		v_c.rotation_euler[0] = Sem.div(PI, 2)
	Geo.gen_beam(Sem.add(v_name, "_Needle"), [0, Sem.neg(0.106), Sem.mul(v_height, 0.65)], [0.08, Sem.neg(0.106), Sem.mul(v_height, 0.71)], 0.012, 0.01, v_mats["wood_dark"], v_root, 0)
	Geo.gen_beam(Sem.add(v_name, "_Lever"), [Sem.neg(0.13), Sem.neg(0.11), 0.16], [0.13, Sem.neg(0.11), 0.16], 0.05, 0.05, v_mats["gold"], v_root, 0.008)
	v_root["state_binding"] = "host_owned_no_pressure_reading_embedded"
	return v_root

static func gen_vent_grille(v_name, v_mats, v_width = 0.75, v_height = 0.42, v_parent = null):
	var v_i = null
	var v_root = null
	var v_x = null
	v_root = Geo.gen_group(v_name, [0, 0, 0], 0, v_parent)
	Geo.gen_box(Sem.add(v_name, "_Recess"), [0, 0, Sem.div(v_height, 2)], [v_width, 0.035, v_height], v_mats["wood_dark"], 0.008, v_root)
	for tmp_38 in range(7):
		v_i = tmp_38
		Geo.gen_box(Sem.add(v_name, "_Louvre"), [0, Sem.neg(0.03), Sem.div(Sem.mul(Sem.add(v_i, 0.5), v_height), 7)], [Sem.mul(v_width, 0.91), 0.045, 0.023], v_mats["stone_dark"], 0.003, v_root)
	for tmp_39 in [Sem.mul(Sem.neg(v_width), 0.48), Sem.mul(v_width, 0.48)]:
		v_x = tmp_39
		Geo.gen_box(Sem.add(v_name, "_Stile"), [v_x, Sem.neg(0.03), Sem.div(v_height, 2)], [0.04, 0.06, v_height], v_mats["wood_light"], 0.005, v_root)
	return v_root

static func gen_desk_bundle(v_name, v_mats, v_mode = "manuscripts", v_seed = 7, v_parent = null):
	var v_a = null
	var v_b = null
	var v_i = null
	var v_n = null
	var v_p = null
	var v_root = null
	var v_x = null
	v_root = Geo.gen_group(v_name, [0, 0, 0], 0, v_parent)
	if Sem.truth(((v_mode in ["manuscripts", "legal_records", "notebook", "rubbings", "sketchbook", "score_sheets", "botany_notebook"]))):
		v_n = (4 if Sem.truth(((v_mode in ["manuscripts", "legal_records", "rubbings"]))) else 1)
		for tmp_40 in range(v_n):
			v_i = tmp_40
			v_p = Geo.gen_box(Sem.add(v_name, "_Paper"), [Sem.mul(0.013, Sem.mod(v_i, 2)), Sem.mul(0.011, v_i), Sem.add(0.006, Sem.mul(v_i, 0.009))], [0.38, 0.27, 0.012], v_mats["cream"], 0.002, v_root)
			v_p.rotation_euler[2] = Sem.add(Sem.neg(0.06), Sem.mul(v_i, 0.04))
		Geo.gen_beam(Sem.add(v_name, "_Pen"), [0.24, Sem.neg(0.1), 0.025], [0.27, 0.14, 0.025], 0.012, 0.012, (v_mats["gold"] if Sem.truth(((v_mode == "legal_records"))) else v_mats["wood_dark"]), v_root, 0)
		if Sem.truth(((v_mode == "manuscripts"))):
			Geo.gen_box(Sem.add(v_name, "_BlueChalk"), [Sem.neg(0.25), 0.02, 0.014], [0.08, 0.022, 0.022], v_mats["book_blue"], 0.003, v_root)
		if Sem.truth(((v_mode == "rubbings"))):
			Geo.gen_lathe(Sem.add(v_name, "_Magnifier"), [[0.066, 0], [0.08, 0], [0.08, 0.018], [0.066, 0.018], [0.066, 0]], 12, v_mats["gold"], v_root, [0.24, 0.02, 0.023])
			Geo.gen_cylinder(Sem.add(v_name, "_Lens"), [0.24, 0.02, 0.032], 0.065, 0.008, v_mats["glass"], 12, v_root)
			Geo.gen_beam(Sem.add(v_name, "_MagnifierHandle"), [0.24, Sem.neg(0.055), 0.031], [0.24, Sem.neg(0.21), 0.031], 0.028, 0.028, v_mats["wood_dark"], v_root, 0.008)
	else:
		if Sem.truth(((v_mode in ["drawing_rolls", "ruler"]))):
			for tmp_41 in range(3):
				v_i = tmp_41
				v_p = Geo.gen_cylinder(Sem.add(v_name, "_PaperRoll"), [Sem.add(Sem.neg(0.14), Sem.mul(v_i, 0.14)), 0, 0.04], 0.039, 0.41, v_mats["cream"], 10, v_root)
				v_p.rotation_euler[0] = Sem.div(PI, 2)
			Geo.gen_box(Sem.add(v_name, "_Ruler"), [0.1, Sem.neg(0.27), 0.012], [0.52, 0.04, 0.022], v_mats["wood_light"], 0.002, v_root)
			Geo.gen_lathe(Sem.add(v_name, "_PlumbBob"), [[0, 0], [0.04, 0.06], [0.04, 0.1], [0, 0.13]], 8, v_mats["gold"], v_root, [Sem.neg(0.24), Sem.neg(0.2), 0])
		else:
			if Sem.truth(((v_mode in ["cloth_bag", "cloth_kit", "medical_bag"]))):
				Geo.gen_box(Sem.add(v_name, "_Bag"), [0, 0, 0.13], [0.4, 0.22, 0.26], (v_mats["wood_dark"] if Sem.truth(((v_mode == "medical_bag"))) else v_mats["stone"]), 0.045, v_root)
				Geo.gen_box(Sem.add(v_name, "_Flap"), [0, Sem.neg(0.12), 0.18], [0.39, 0.03, 0.17], (v_mats["wood"] if Sem.truth(((v_mode == "medical_bag"))) else v_mats["cream"]), 0.025, v_root)
				for tmp_42 in [Sem.neg(0.14), 0.14]:
					v_x = tmp_42
					Geo.gen_box(Sem.add(v_name, "_Buckle"), [v_x, Sem.neg(0.145), 0.12], [0.045, 0.025, 0.065], v_mats["gold"], 0.004, v_root)
				for tmp_43 in [[[Sem.neg(0.1), 0, 0.26], [Sem.neg(0.1), 0, 0.36]], [[Sem.neg(0.1), 0, 0.36], [0.1, 0, 0.36]], [[0.1, 0, 0.36], [0.1, 0, 0.26]]]:
					var tmp_44 = tmp_43
					v_a = tmp_44[0]
					v_b = tmp_44[1]
					Geo.gen_beam(Sem.add(v_name, "_Handle"), v_a, v_b, 0.025, 0.025, v_mats["wood_dark"], v_root, 0.008)
			else:
				if Sem.truth(((v_mode in ["bandage_rolls", "bedside_bandages", "oil_cloth", "shawl"]))):
					Geo.gen_box(Sem.add(v_name, "_Cloth"), [0, 0, 0.025], [0.45, 0.31, 0.05], (v_mats["cream"] if Sem.truth(((v_mode != "oil_cloth"))) else v_mats["stone_dark"]), 0.02, v_root)
					for tmp_45 in range(3):
						v_i = tmp_45
						Geo.gen_cylinder(Sem.add(v_name, "_Roll"), [Sem.add(Sem.neg(0.14), Sem.mul(v_i, 0.14)), 0, 0.09], 0.05, 0.1, v_mats["cream"], 10, v_root)
				else:
					if Sem.truth(((v_mode in ["mechanical_tools", "tool_roll", "gear_board"]))):
						Geo.gen_box(Sem.add(v_name, "_ToolMat"), [0, 0, 0.008], [0.52, 0.36, 0.015], v_mats["wood_light"], 0.008, v_root)
						for tmp_46 in range(3):
							v_i = tmp_46
							v_x = Sem.add(Sem.neg(0.18), Sem.mul(v_i, 0.17))
							Geo.gen_beam(Sem.add(v_name, "_Tool"), [v_x, Sem.neg(0.11), 0.027], [v_x, 0.1, 0.027], 0.022, 0.026, v_mats["stone_dark"], v_root, 0.008)
							Geo.gen_box(Sem.add(v_name, "_ToolHead"), [v_x, 0.12, 0.033], [0.1, 0.05, 0.035], v_mats["gold"], 0.003, v_root)
						if Sem.truth(((v_mode == "gear_board"))):
							for tmp_47 in range(3):
								v_i = tmp_47
								Geo.gen_cylinder(Sem.add(v_name, "_Gear"), [Sem.add(Sem.neg(0.15), Sem.mul(v_i, 0.15)), 0.0, 0.045], 0.055, 0.025, v_mats["gold"], 8, v_root)
					else:
						if Sem.truth(((v_mode in ["bowls", "cooking_tools"]))):
							for tmp_48 in range(2):
								v_i = tmp_48
								v_p = load("res://tools/building_construction/BuildingConstruction/Props/SpecialRecipes.gd").gen_vessel(Sem.add(v_name, "_Bowl"), v_mats, 0.12, 0.09, "plate", v_root)
								v_p.location = [Sem.add(Sem.neg(0.15), Sem.mul(v_i, 0.3)), 0, 0]
							Geo.gen_beam(Sem.add(v_name, "_Spoon"), [Sem.neg(0.25), Sem.neg(0.2), 0.035], [0.1, Sem.neg(0.2), 0.035], 0.02, 0.02, v_mats["wood_light"], v_root, 0.008)
						else:
							push_error(str(Sem.add("Unknown residential accessory bundle: ", v_mode)))
							return null
	v_root["authored_text"] = "none_visual_only"
	return v_root

static func gen_easel(v_name, v_mats, v_width = 0.7, v_height = 1.65, v_parent = null):
	var v_art = null
	var v_root = null
	var v_x = null
	v_root = Geo.gen_group(v_name, [0, 0, 0], 0, v_parent)
	for tmp_49 in [Sem.mul(Sem.neg(v_width), 0.38), Sem.mul(v_width, 0.38)]:
		v_x = tmp_49
		Geo.gen_beam(Sem.add(v_name, "_Leg"), [v_x, Sem.neg(0.17), 0], [Sem.mul(v_x, 0.45), 0.06, v_height], 0.055, 0.055, v_mats["wood_light"], v_root, 0.008)
	Geo.gen_beam(Sem.add(v_name, "_BackLeg"), [0, 0.53, 0], [0, 0.06, Sem.mul(v_height, 0.86)], 0.055, 0.055, v_mats["wood"], v_root, 0.008)
	Geo.gen_box(Sem.add(v_name, "_Rest"), [0, Sem.neg(0.07), Sem.mul(v_height, 0.43)], [Sem.add(v_width, 0.12), 0.18, 0.06], v_mats["wood"], 0.008, v_root)
	v_art = load("res://tools/building_construction/BuildingConstruction/Tables/FurnitureRecipes.gd").gen_painting(Sem.add(v_name, "_Canvas"), v_mats, v_width, Sem.mul(v_height, 0.48), 0.065, "landscape", 7, v_root)
	v_art.location = [0, Sem.neg(0.06), Sem.mul(v_height, 0.46)]
	return v_root

static func gen_stool(v_name, v_mats, v_width = 0.62, v_depth = 0.4, v_height = 0.45, v_parent = null):
	var v_root = null
	var v_x = null
	var v_y = null
	v_root = Geo.gen_group(v_name, [0, 0, 0], 0, v_parent)
	for tmp_50 in [Sem.mul(Sem.neg(v_width), 0.4), Sem.mul(v_width, 0.4)]:
		v_x = tmp_50
		for tmp_51 in [Sem.mul(Sem.neg(v_depth), 0.36), Sem.mul(v_depth, 0.36)]:
			v_y = tmp_51
			Geo.gen_box(Sem.add(v_name, "_Leg"), [v_x, v_y, Sem.mul(v_height, 0.46)], [0.065, 0.065, Sem.mul(v_height, 0.92)], v_mats["wood"], 0.008, v_root)
	Geo.gen_box(Sem.add(v_name, "_Seat"), [0, 0, Sem.sub(v_height, 0.035)], [v_width, v_depth, 0.07], v_mats["wood_light"], 0.009, v_root)
	Geo.gen_box(Sem.add(v_name, "_Cushion"), [0, 0, Sem.add(v_height, 0.018)], [Sem.mul(v_width, 0.94), Sem.mul(v_depth, 0.91), 0.045], v_mats["green"], 0.014, v_root)
	return v_root

static func gen_seal_door_trim(v_name, v_mats, v_width = 1.3, v_height = 2.45, v_parent = null):
	var v_root = null
	var v_x = null
	var v_z = null
	v_root = Geo.gen_group(v_name, [0, 0, 0], 0, v_parent)
	for tmp_52 in [Sem.mul(Sem.neg(v_width), 0.46), Sem.mul(v_width, 0.46)]:
		v_x = tmp_52
		Geo.gen_box(Sem.add(v_name, "_SealRail"), [v_x, Sem.neg(0.06), Sem.mul(v_height, 0.5)], [0.055, 0.045, Sem.sub(v_height, 0.1)], v_mats["stone_dark"], 0.005, v_root)
	for tmp_53 in [0.07, Sem.sub(v_height, 0.07)]:
		v_z = tmp_53
		Geo.gen_box(Sem.add(v_name, "_Seal"), [0, Sem.neg(0.06), v_z], [Sem.sub(v_width, 0.1), 0.045, 0.055], v_mats["stone_dark"], 0.005, v_root)
	for tmp_54 in [Sem.mul(v_height, 0.24), Sem.mul(v_height, 0.5), Sem.mul(v_height, 0.76)]:
		v_z = tmp_54
		Geo.gen_box(Sem.add(v_name, "_Lock"), [Sem.mul(v_width, 0.32), Sem.neg(0.115), v_z], [0.12, 0.08, 0.16], v_mats["gold"], 0.008, v_root)
	return v_root

static func gen_kitchen_hood(v_name, v_mats, v_width = 2.25, v_parent = null, v_depth = 0.8, v_height = 1.65):
	return gen_cooker_hood(v_name, v_mats, v_width, v_depth, v_height, v_parent)

static func gen_upright_piano(v_name, v_mats, v_width = 1.7, v_parent = null, v_depth = 0.7, v_height = 1.45):
	return gen_keyboard(v_name, v_mats, v_width, v_depth, v_height, v_parent)

