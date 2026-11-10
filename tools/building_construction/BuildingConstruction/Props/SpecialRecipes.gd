@tool
extends RefCounted

# Direct port of kit/special_props.py. Z-up recipe coordinates convert at the geometry boundary.
const Sem = preload("res://tools/building_construction/BuildingConstruction/Shared/RecipeSemantics.gd")
const Geo = preload("res://tools/building_construction/BuildingConstruction/Shared/RecipeGeometry.gd")
const EPS = 1e-9

static func gen_bed(v_name, v_mats, v_width = 1.15, v_length = 2.15, v_height = 0.52, v_medical = false, v_parent = null):
	var v_h = null
	var v_mat = null
	var v_root = null
	var v_x = null
	var v_y = null
	v_root = Geo.gen_group(v_name, [0, 0, 0], 0, v_parent)
	v_mat = (v_mats["stone_dark"] if Sem.truth(v_medical) else v_mats["wood"])
	for tmp_1 in [Sem.mul(Sem.neg(v_width), 0.43), Sem.mul(v_width, 0.43)]:
		v_x = tmp_1
		for tmp_2 in [Sem.mul(Sem.neg(v_length), 0.43), Sem.mul(v_length, 0.43)]:
			v_y = tmp_2
			Geo.gen_box(Sem.add(v_name, "_Leg"), [v_x, v_y, 0.25], [0.09, 0.09, 0.5], v_mat, 0.012, v_root)
	Geo.gen_box(Sem.add(v_name, "_Frame"), [0, 0, Sem.sub(v_height, 0.13)], [v_width, v_length, 0.16], v_mat, 0.02, v_root)
	Geo.gen_box(Sem.add(v_name, "_Mattress"), [0, 0, Sem.sub(v_height, 0.015)], [Sem.mul(v_width, 0.94), Sem.mul(v_length, 0.97), 0.15], v_mats["cream"], 0.035, v_root)
	Geo.gen_box(Sem.add(v_name, "_Blanket"), [0, Sem.mul(Sem.neg(v_length), 0.11), Sem.add(v_height, 0.075)], [Sem.mul(v_width, 0.96), Sem.mul(v_length, 0.63), 0.045], (v_mats["book_blue"] if Sem.truth(v_medical) else v_mats["green"]), 0.02, v_root)
	Geo.gen_box(Sem.add(v_name, "_Fold"), [0, Sem.mul(v_length, 0.19), Sem.add(v_height, 0.103)], [Sem.mul(v_width, 0.97), 0.16, 0.03], (v_mats["stone"] if Sem.truth(v_medical) else v_mats["book_green"]), 0.006, v_root)
	Geo.gen_box(Sem.add(v_name, "_Pillow"), [0, Sem.mul(v_length, 0.34), Sem.add(v_height, 0.105)], [Sem.mul(v_width, 0.69), 0.42, 0.12], v_mats["cream"], 0.05, v_root)
	for tmp_3 in [[Sem.mul(v_length, 0.47), 1.02], [Sem.mul(Sem.neg(v_length), 0.47), 0.67]]:
		var tmp_4 = tmp_3
		v_y = tmp_4[0]
		v_h = tmp_4[1]
		Geo.gen_box(Sem.add(v_name, "_HeadFoot"), [0, v_y, Sem.mul(v_h, 0.5)], [Sem.add(v_width, 0.07), 0.09, v_h], v_mat, 0.018, v_root)
		Geo.gen_box(Sem.add(v_name, "_Inset"), [0, Sem.sub(v_y, 0.055), Sem.mul(v_h, 0.65)], [Sem.mul(v_width, 0.8), 0.035, Sem.mul(v_h, 0.37)], (v_mats["wood_light"] if Sem.truth(not Sem.truth(v_medical)) else v_mats["cream"]), 0.008, v_root)
	v_root["kind"] = "bed"
	v_root["surface_height"] = Sem.add(v_height, 0.06)
	return v_root

static func gen_cabinet(v_name, v_mats, v_width = 1.2, v_depth = 0.5, v_height = 1.9, v_drawers = 0, v_parent = null):
	var v_count = null
	var v_hx = null
	var v_i = null
	var v_pos = null
	var v_root = null
	var v_size = null
	var v_wh = null
	var v_x = null
	var v_y = null
	var v_z = null
	v_root = Geo.gen_group(v_name, [0, 0, 0], 0, v_parent)
	Geo.gen_box(Sem.add(v_name, "_Body"), [0, 0, Sem.div(v_height, 2)], [v_width, v_depth, v_height], v_mats["wood_dark"], 0.012, v_root)
	Geo.gen_box(Sem.add(v_name, "_Top"), [0, 0, Sem.sub(v_height, 0.025)], [Sem.add(v_width, 0.08), Sem.add(v_depth, 0.05), 0.07], v_mats["wood_light"], 0.012, v_root)
	Geo.gen_box(Sem.add(v_name, "_Plinth"), [0, 0, 0.07], [Sem.add(v_width, 0.05), Sem.add(v_depth, 0.04), 0.14], v_mats["wood"], 0.012, v_root)
	v_count = (v_drawers if Sem.truth(v_drawers) else 2)
	for tmp_5 in range(v_count):
		v_i = tmp_5
		if Sem.truth(v_drawers):
			v_wh = Sem.div(Sem.sub(v_height, 0.23), v_count)
			v_pos = [0, Sem.sub(Sem.div(Sem.neg(v_depth), 2), 0.018), Sem.add(0.15, Sem.mul(v_wh, Sem.add(v_i, 0.5)))]
			v_size = [Sem.sub(v_width, 0.1), 0.045, Sem.sub(v_wh, 0.035)]
		else:
			v_pos = [Sem.add(Sem.div(Sem.neg(v_width), 4), Sem.div(Sem.mul(v_i, v_width), 2)), Sem.sub(Sem.div(Sem.neg(v_depth), 2), 0.018), Sem.mul(v_height, 0.53)]
			v_size = [Sem.mul(v_width, 0.47), 0.045, Sem.sub(v_height, 0.24)]
		Geo.gen_box(Sem.add(v_name, Sem.mod("_Front_%02d", v_i)), v_pos, v_size, v_mats["wood"], 0.012, v_root)
		var tmp_6 = v_pos
		v_x = tmp_6[0]
		v_y = tmp_6[1]
		v_z = tmp_6[2]
		Geo.gen_box(Sem.add(v_name, Sem.mod("_Inset_%02d", v_i)), [v_x, Sem.sub(v_y, 0.027), v_z], [Sem.sub(v_size[0], 0.1), 0.018, Sem.sub(v_size[2], 0.12)], v_mats["wood_light"], 0.006, v_root)
		v_hx = (v_x if Sem.truth(v_drawers) else Sem.add(v_x, (Sem.mul(0.18, v_width) if Sem.truth(((v_i == 0))) else Sem.mul(Sem.neg(0.18), v_width))))
		Geo.gen_ico(Sem.add(v_name, "_Handle"), [v_hx, Sem.sub(v_y, 0.07), v_z], 0.028, v_mats["gold"], 1, v_root)
	v_root["kind"] = "cabinet"
	return v_root

static func gen_chest(v_name, v_mats, v_width = 0.9, v_depth = 0.52, v_height = 0.48, v_parent = null):
	var v_root = null
	var v_x = null
	v_root = Geo.gen_group(v_name, [0, 0, 0], 0, v_parent)
	Geo.gen_box(Sem.add(v_name, "_Case"), [0, 0, Sem.mul(v_height, 0.45)], [v_width, v_depth, Sem.mul(v_height, 0.9)], v_mats["wood"], 0.02, v_root)
	Geo.gen_box(Sem.add(v_name, "_Lid"), [0, 0, Sem.sub(v_height, 0.03)], [Sem.add(v_width, 0.035), Sem.add(v_depth, 0.035), 0.075], v_mats["wood_light"], 0.015, v_root)
	for tmp_7 in [Sem.mul(Sem.neg(v_width), 0.32), Sem.mul(v_width, 0.32)]:
		v_x = tmp_7
		Geo.gen_box(Sem.add(v_name, "_Band"), [v_x, Sem.sub(Sem.div(Sem.neg(v_depth), 2), 0.008), Sem.mul(v_height, 0.47)], [0.055, 0.024, Sem.mul(v_height, 0.92)], v_mats["stone_dark"], 0.004, v_root)
		Geo.gen_box(Sem.add(v_name, "_TopBand"), [v_x, 0, Sem.add(v_height, 0.014)], [0.055, Sem.add(v_depth, 0.035), 0.018], v_mats["stone_dark"], 0.002, v_root)
	Geo.gen_box(Sem.add(v_name, "_Lock"), [0, Sem.sub(Sem.div(Sem.neg(v_depth), 2), 0.028), Sem.mul(v_height, 0.67)], [0.09, 0.035, 0.12], v_mats["gold"], 0.008, v_root)
	return v_root

static func gen_vessel(v_name, v_mats, v_radius = 0.12, v_height = 0.3, v_kind = "bottle", v_parent = null):
	var v_p = null
	var v_profile = null
	var v_q = null
	var v_root = null
	var v_x = null
	v_root = Geo.gen_group(v_name, [0, 0, 0], 0, v_parent)
	if Sem.truth(((v_kind == "bottle"))):
		v_profile = [[0, 0], [Sem.mul(v_radius, 0.8), 0], [v_radius, 0.04], [v_radius, Sem.mul(v_height, 0.66)], [Sem.mul(v_radius, 0.42), Sem.mul(v_height, 0.8)], [Sem.mul(v_radius, 0.42), Sem.mul(v_height, 0.95)]]
		Geo.gen_lathe(Sem.add(v_name, "_Bottle"), v_profile, 8, v_mats["book_green"], v_root, [0, 0, 0])
		Geo.gen_cylinder(Sem.add(v_name, "_Cork"), [0, 0, Sem.mul(v_height, 0.97)], Sem.mul(v_radius, 0.47), Sem.mul(v_height, 0.08), v_mats["wood_light"], 8, v_root)
		Geo.gen_box(Sem.add(v_name, "_Label"), [0, Sem.sub(Sem.neg(v_radius), 0.001), Sem.mul(v_height, 0.42)], [Sem.mul(v_radius, 1.1), 0.008, Sem.mul(v_height, 0.24)], v_mats["cream"], 0, v_root)
	else:
		if Sem.truth(((v_kind == "plate"))):
			Geo.gen_lathe(Sem.add(v_name, "_Dish"), [[0, 0], [Sem.mul(v_radius, 0.7), 0], [v_radius, Sem.mul(v_height, 0.3)], [v_radius, v_height], [Sem.mul(v_radius, 0.77), Sem.mul(v_height, 0.9)], [Sem.mul(v_radius, 0.58), Sem.mul(v_height, 0.35)], [0, Sem.mul(v_height, 0.35)]], 12, v_mats["cream"], v_root, [0, 0, 0])
		else:
			if Sem.truth(((v_kind == "cup"))):
				Geo.gen_lathe(Sem.add(v_name, "_Cup"), [[Sem.mul(v_radius, 0.7), 0], [v_radius, v_height], [Sem.mul(v_radius, 0.83), v_height], [Sem.mul(v_radius, 0.6), Sem.mul(v_height, 0.12)], [0, Sem.mul(v_height, 0.12)]], 10, v_mats["cream"], v_root, [0, 0, 0])
				for tmp_8 in [[[Sem.mul(v_radius, 0.85), 0, Sem.mul(v_height, 0.8)], [Sem.mul(v_radius, 1.5), 0, Sem.mul(v_height, 0.8)]], [[Sem.mul(v_radius, 1.5), 0, Sem.mul(v_height, 0.8)], [Sem.mul(v_radius, 1.5), 0, Sem.mul(v_height, 0.25)]], [[Sem.mul(v_radius, 1.5), 0, Sem.mul(v_height, 0.25)], [Sem.mul(v_radius, 0.75), 0, Sem.mul(v_height, 0.25)]]]:
					var tmp_9 = tmp_8
					v_p = tmp_9[0]
					v_q = tmp_9[1]
					Geo.gen_beam(Sem.add(v_name, "_Handle"), v_p, v_q, 0.025, 0.025, v_mats["cream"], v_root, 0.008)
			else:
				Geo.gen_lathe(Sem.add(v_name, "_Pot"), [[0, 0], [Sem.mul(v_radius, 0.65), 0], [v_radius, Sem.mul(v_height, 0.7)], [Sem.mul(v_radius, 0.92), v_height], [Sem.mul(v_radius, 0.78), v_height], [Sem.mul(v_radius, 0.72), Sem.mul(v_height, 0.25)], [0, Sem.mul(v_height, 0.25)]], 10, v_mats["stone_dark"], v_root, [0, 0, 0])
				for tmp_10 in [Sem.mul(Sem.neg(v_radius), 1.12), Sem.mul(v_radius, 1.12)]:
					v_x = tmp_10
					Geo.gen_box(Sem.add(v_name, "_Grip"), [v_x, 0, Sem.mul(v_height, 0.7)], [Sem.mul(v_radius, 0.48), 0.06, 0.08], v_mats["gold"], 0.012, v_root)
	return v_root

static func gen_sink(v_name, v_mats, v_width = 1.3, v_depth = 0.65, v_height = 0.88, v_parent = null):
	var v_base = null
	var v_root = null
	var v_x = null
	var v_y = null
	v_root = Geo.gen_group(v_name, [0, 0, 0], 0, v_parent)
	v_base = gen_cabinet(Sem.add(v_name, "_Base"), v_mats, v_width, v_depth, Sem.sub(v_height, 0.08), 0, v_root)
	Geo.gen_box(Sem.add(v_name, "_Bottom"), [0, 0, Sem.sub(v_height, 0.12)], [Sem.sub(v_width, 0.12), Sem.sub(v_depth, 0.12), 0.04], v_mats["stone"], 0.012, v_root)
	for tmp_11 in [Sem.add(Sem.div(Sem.neg(v_width), 2), 0.045), Sem.sub(Sem.div(v_width, 2), 0.045)]:
		v_x = tmp_11
		Geo.gen_box(Sem.add(v_name, "_RimX"), [v_x, 0, Sem.sub(v_height, 0.04)], [0.09, v_depth, 0.12], v_mats["cream"], 0.016, v_root)
	for tmp_12 in [Sem.add(Sem.div(Sem.neg(v_depth), 2), 0.045), Sem.sub(Sem.div(v_depth, 2), 0.045)]:
		v_y = tmp_12
		Geo.gen_box(Sem.add(v_name, "_RimY"), [0, v_y, Sem.sub(v_height, 0.04)], [Sem.sub(v_width, 0.15), 0.09, 0.12], v_mats["cream"], 0.016, v_root)
	Geo.gen_beam(Sem.add(v_name, "_TapStem"), [0, Sem.mul(v_depth, 0.34), v_height], [0, Sem.mul(v_depth, 0.34), Sem.add(v_height, 0.28)], 0.036, 0.036, v_mats["gold"], v_root, 0.008)
	Geo.gen_beam(Sem.add(v_name, "_TapNeck"), [0, Sem.mul(v_depth, 0.34), Sem.add(v_height, 0.28)], [0, 0, Sem.add(v_height, 0.28)], 0.036, 0.036, v_mats["gold"], v_root, 0.008)
	Geo.gen_cylinder(Sem.add(v_name, "_Drain"), [0, 0, Sem.sub(v_height, 0.094)], 0.04, 0.012, v_mats["stone_dark"], 10, v_root)
	return v_root

static func gen_stove(v_name, v_mats, v_width = 1.4, v_depth = 0.72, v_height = 0.9, v_parent = null):
	var v_knob = null
	var v_root = null
	var v_x = null
	var v_y = null
	v_root = Geo.gen_group(v_name, [0, 0, 0], 0, v_parent)
	Geo.gen_box(Sem.add(v_name, "_Iron"), [0, 0, Sem.mul(v_height, 0.49)], [v_width, v_depth, Sem.mul(v_height, 0.98)], v_mats["stone_dark"], 0.02, v_root)
	Geo.gen_box(Sem.add(v_name, "_Top"), [0, 0, v_height], [Sem.add(v_width, 0.05), Sem.add(v_depth, 0.05), 0.055], v_mats["stone"], 0.012, v_root)
	for tmp_13 in [Sem.mul(Sem.neg(v_width), 0.27), Sem.mul(v_width, 0.27)]:
		v_x = tmp_13
		for tmp_14 in [Sem.mul(Sem.neg(v_depth), 0.23), Sem.mul(v_depth, 0.23)]:
			v_y = tmp_14
			Geo.gen_cylinder(Sem.add(v_name, "_Burner"), [v_x, v_y, Sem.add(v_height, 0.04)], Sem.py_min(Sem.mul(v_width, 0.14), Sem.mul(v_depth, 0.19)), 0.024, v_mats["wood_dark"], 10, v_root)
	for tmp_15 in [Sem.mul(Sem.neg(v_width), 0.28), Sem.mul(v_width, 0.28)]:
		v_x = tmp_15
		Geo.gen_box(Sem.add(v_name, "_Oven"), [v_x, Sem.sub(Sem.div(Sem.neg(v_depth), 2), 0.016), Sem.mul(v_height, 0.43)], [Sem.mul(v_width, 0.43), 0.04, Sem.mul(v_height, 0.48)], v_mats["wood_dark"], 0.008, v_root)
		Geo.gen_beam(Sem.add(v_name, "_Bar"), [Sem.sub(v_x, Sem.mul(v_width, 0.12)), Sem.sub(Sem.div(Sem.neg(v_depth), 2), 0.07), Sem.mul(v_height, 0.57)], [Sem.add(v_x, Sem.mul(v_width, 0.12)), Sem.sub(Sem.div(Sem.neg(v_depth), 2), 0.07), Sem.mul(v_height, 0.57)], 0.025, 0.025, v_mats["gold"], v_root, 0.008)
		v_knob = Geo.gen_cylinder(Sem.add(v_name, "_Knob"), [v_x, Sem.sub(Sem.div(Sem.neg(v_depth), 2), 0.04), Sem.mul(v_height, 0.82)], 0.035, 0.035, v_mats["gold"], 8, v_root)
		v_knob.rotation_euler[0] = Sem.div(PI, 2)
	return v_root

static func gen_work_counter(v_name, v_mats, v_width = 2, v_depth = 0.7, v_height = 0.9, v_parent = null):
	var v_root = null
	v_root = gen_cabinet(v_name, v_mats, v_width, v_depth, Sem.sub(v_height, 0.05), 0, v_parent)
	Geo.gen_box(Sem.add(v_name, "_Worktop"), [0, 0, Sem.sub(v_height, 0.025)], [Sem.add(v_width, 0.08), Sem.add(v_depth, 0.06), 0.07], v_mats["stone"], 0.012, v_root)
	return v_root

static func gen_tub(v_name, v_mats, v_width = 1.6, v_depth = 0.8, v_height = 0.6, v_parent = null):
	var v_root = null
	var v_x = null
	var v_y = null
	v_root = Geo.gen_group(v_name, [0, 0, 0], 0, v_parent)
	Geo.gen_box(Sem.add(v_name, "_Bottom"), [0, 0, 0.2], [Sem.sub(v_width, 0.12), Sem.sub(v_depth, 0.12), 0.1], v_mats["cream"], 0.04, v_root)
	for tmp_16 in [Sem.add(Sem.div(Sem.neg(v_width), 2), 0.07), Sem.sub(Sem.div(v_width, 2), 0.07)]:
		v_x = tmp_16
		Geo.gen_box(Sem.add(v_name, "_End"), [v_x, 0, Sem.mul(v_height, 0.6)], [0.14, v_depth, Sem.mul(v_height, 0.8)], v_mats["cream"], 0.035, v_root)
	for tmp_17 in [Sem.add(Sem.div(Sem.neg(v_depth), 2), 0.07), Sem.sub(Sem.div(v_depth, 2), 0.07)]:
		v_y = tmp_17
		Geo.gen_box(Sem.add(v_name, "_Side"), [0, v_y, Sem.mul(v_height, 0.6)], [Sem.sub(v_width, 0.14), 0.14, Sem.mul(v_height, 0.8)], v_mats["cream"], 0.035, v_root)
	Geo.gen_box(Sem.add(v_name, "_Water"), [0, 0, Sem.mul(v_height, 0.55)], [Sem.sub(v_width, 0.3), Sem.sub(v_depth, 0.3), 0.015], v_mats["glass"], 0.006, v_root)
	for tmp_18 in [Sem.mul(Sem.neg(v_width), 0.32), Sem.mul(v_width, 0.32)]:
		v_x = tmp_18
		for tmp_19 in [Sem.mul(Sem.neg(v_depth), 0.28), Sem.mul(v_depth, 0.28)]:
			v_y = tmp_19
			Geo.gen_box(Sem.add(v_name, "_Foot"), [v_x, v_y, 0.09], [0.1, 0.1, 0.18], v_mats["gold"], 0.015, v_root)
	return v_root

static func gen_washstand(v_name, v_mats, v_width = 0.8, v_depth = 0.54, v_height = 0.84, v_parent = null):
	return gen_sink(v_name, v_mats, v_width, v_depth, v_height, v_parent)

static func gen_screen(v_name, v_mats, v_width = 1.8, v_height = 1.8, v_parent = null):
	var v_i = null
	var v_panel = null
	var v_root = null
	var v_x = null
	var v_z = null
	v_root = Geo.gen_group(v_name, [0, 0, 0], 0, v_parent)
	for tmp_20 in range(3):
		v_i = tmp_20
		v_panel = Geo.gen_group(Sem.add(Sem.add(v_name, "_Panel_"), str(v_i)), [Sem.div(Sem.mul(Sem.sub(v_i, 1), v_width), 3), 0, 0], Sem.mul((Sem.neg(1) if Sem.truth(Sem.mod(v_i, 2)) else 1), 0.14), v_root)
		Geo.gen_box(Sem.add(v_name, "_Fabric"), [0, 0, Sem.mul(v_height, 0.55)], [Sem.sub(Sem.div(v_width, 3), 0.05), 0.035, Sem.mul(v_height, 0.84)], v_mats["cream"], 0.008, v_panel)
		for tmp_21 in [Sem.div(Sem.neg(v_width), 6), Sem.div(v_width, 6)]:
			v_x = tmp_21
			Geo.gen_box(Sem.add(v_name, "_Post"), [v_x, 0, Sem.div(v_height, 2)], [0.045, 0.055, v_height], v_mats["wood"], 0.006, v_panel)
		for tmp_22 in [0.18, v_height]:
			v_z = tmp_22
			Geo.gen_box(Sem.add(v_name, "_Rail"), [0, 0, v_z], [Sem.div(v_width, 3), 0.055, 0.05], v_mats["wood"], 0.006, v_panel)
	return v_root

static func gen_rack(v_name, v_mats, v_width = 1.5, v_height = 1.65, v_parent = null):
	var v_i = null
	var v_root = null
	var v_x = null
	v_root = Geo.gen_group(v_name, [0, 0, 0], 0, v_parent)
	for tmp_23 in [Sem.div(Sem.neg(v_width), 2), Sem.div(v_width, 2)]:
		v_x = tmp_23
		Geo.gen_beam(Sem.add(v_name, "_Upright"), [v_x, 0, 0], [v_x, 0, v_height], 0.06, 0.06, v_mats["wood"], v_root, 0.008)
		Geo.gen_box(Sem.add(v_name, "_Foot"), [v_x, 0, 0.045], [0.24, 0.6, 0.09], v_mats["wood_dark"], 0.01, v_root)
	Geo.gen_beam(Sem.add(v_name, "_Rail"), [Sem.div(Sem.neg(v_width), 2), 0, v_height], [Sem.div(v_width, 2), 0, v_height], 0.055, 0.055, v_mats["wood"], v_root, 0.008)
	for tmp_24 in range(4):
		v_i = tmp_24
		v_x = Sem.add(Sem.mul(Sem.neg(v_width), 0.35), Sem.mul(Sem.mul(v_i, v_width), 0.23))
		Geo.gen_box(Sem.add(v_name, "_Towel"), [v_x, 0, Sem.sub(v_height, 0.45)], [Sem.mul(v_width, 0.17), 0.04, 0.83], (v_mats["cream"] if Sem.truth(Sem.mod(v_i, 2)) else v_mats["book_blue"]), 0.008, v_root)
	return v_root

static func gen_chalkboard(v_name, v_mats, v_width = 3.3, v_height = 1.7, v_parent = null):
	var v_col = null
	var v_root = null
	var v_row = null
	var v_x = null
	var v_z = null
	v_root = Geo.gen_group(v_name, [0, 0, 0], 0, v_parent)
	Geo.gen_box(Sem.add(v_name, "_Slate"), [0, 0, Sem.div(v_height, 2)], [v_width, 0.08, v_height], v_mats["green"], 0.012, v_root)
	for tmp_25 in [Sem.div(Sem.neg(v_width), 2), Sem.div(v_width, 2)]:
		v_x = tmp_25
		Geo.gen_box(Sem.add(v_name, "_Stile"), [v_x, Sem.neg(0.025), Sem.div(v_height, 2)], [0.1, 0.13, Sem.add(v_height, 0.12)], v_mats["wood_light"], 0.01, v_root)
	for tmp_26 in [0, v_height]:
		v_z = tmp_26
		Geo.gen_box(Sem.add(v_name, "_Rail"), [0, Sem.neg(0.025), v_z], [Sem.add(v_width, 0.1), 0.13, 0.1], v_mats["wood_light"], 0.01, v_root)
	Geo.gen_box(Sem.add(v_name, "_Tray"), [0, Sem.neg(0.15), Sem.neg(0.04)], [v_width, 0.28, 0.065], v_mats["wood"], 0.008, v_root)
	for tmp_27 in range(5):
		v_row = tmp_27
		for tmp_28 in range(Sem.sub(5, Sem.mod(v_row, 2))):
			v_col = tmp_28
			v_x = Sem.add(Sem.mul(Sem.neg(v_width), 0.37), Sem.mul(Sem.mul(v_col, v_width), 0.15))
			Geo.gen_box(Sem.add(v_name, "_ChalkMark"), [v_x, Sem.neg(0.046), Sem.sub(Sem.mul(v_height, 0.77), Sem.mul(Sem.mul(v_row, v_height), 0.13))], [Sem.mul(v_width, 0.09), 0.005, 0.014], v_mats["cream"], 0, v_root)
	v_root["text_binding"] = "host_owned_no_story_text_embedded"
	return v_root

static func gen_lectern(v_name, v_mats, v_width = 0.8, v_depth = 0.55, v_height = 1.12, v_parent = null):
	var v_root = null
	var v_top = null
	v_root = Geo.gen_group(v_name, [0, 0, 0], 0, v_parent)
	Geo.gen_box(Sem.add(v_name, "_Foot"), [0, 0, 0.07], [Sem.mul(v_width, 0.9), Sem.mul(v_depth, 0.95), 0.14], v_mats["wood_dark"], 0.015, v_root)
	Geo.gen_box(Sem.add(v_name, "_Pedestal"), [0, 0, Sem.mul(v_height, 0.43)], [Sem.mul(v_width, 0.68), Sem.mul(v_depth, 0.68), Sem.mul(v_height, 0.78)], v_mats["wood"], 0.015, v_root)
	v_top = Geo.gen_box(Sem.add(v_name, "_Slope"), [0, 0, Sem.sub(v_height, 0.06)], [v_width, v_depth, 0.08], v_mats["wood_light"], 0.015, v_root)
	v_top.rotation_euler[0] = deg_to_rad(14)
	Geo.gen_box(Sem.add(v_name, "_BookStop"), [0, Sem.mul(Sem.neg(v_depth), 0.43), Sem.sub(v_height, 0.105)], [Sem.mul(v_width, 0.9), 0.045, 0.045], v_mats["gold"], 0.006, v_root)
	return v_root

static func gen_chessboard(v_name, v_mats, v_size = 0.62, v_parent = null):
	var v_col = null
	var v_color = null
	var v_h = null
	var v_pos = null
	var v_root = null
	var v_row = null
	var v_rows = null
	v_root = Geo.gen_group(v_name, [0, 0, 0], 0, v_parent)
	Geo.gen_box(Sem.add(v_name, "_Base"), [0, 0, 0.018], [Sem.add(v_size, 0.06), Sem.add(v_size, 0.06), 0.036], v_mats["wood_dark"], 0.008, v_root)
	for tmp_29 in range(8):
		v_row = tmp_29
		for tmp_30 in range(8):
			v_col = tmp_30
			Geo.gen_box(Sem.add(v_name, Sem.mod("_Square_%d_%d", [v_row, v_col])), [Sem.add(Sem.div(Sem.neg(v_size), 2), Sem.div(Sem.mul(Sem.add(v_col, 0.5), v_size), 8)), Sem.add(Sem.div(Sem.neg(v_size), 2), Sem.div(Sem.mul(Sem.add(v_row, 0.5), v_size), 8)), 0.04], [Sem.sub(Sem.div(v_size, 8), 0.001), Sem.sub(Sem.div(v_size, 8), 0.001), 0.012], (v_mats["cream"] if Sem.truth(Sem.mod(Sem.add(v_row, v_col), 2)) else v_mats["wood"]), 0, v_root)
	for tmp_31 in [[v_mats["cream"], [0, 1]], [v_mats["wood_dark"], [6, 7]]]:
		var tmp_32 = tmp_31
		v_color = tmp_32[0]
		v_rows = tmp_32[1]
		for tmp_33 in v_rows:
			v_row = tmp_33
			for tmp_34 in range(8):
				v_col = tmp_34
				v_h = Sem.mul(v_size, (0.11 if Sem.truth(((v_row in [0, 7]))) else 0.08))
				v_pos = [Sem.add(Sem.div(Sem.neg(v_size), 2), Sem.div(Sem.mul(Sem.add(v_col, 0.5), v_size), 8)), Sem.add(Sem.div(Sem.neg(v_size), 2), Sem.div(Sem.mul(Sem.add(v_row, 0.5), v_size), 8)), 0.048]
				Geo.gen_lathe(Sem.add(v_name, "_Piece"), [[Sem.mul(v_size, 0.026), 0], [Sem.mul(v_size, 0.028), Sem.mul(v_h, 0.13)], [Sem.mul(v_size, 0.016), Sem.mul(v_h, 0.32)], [Sem.mul(v_size, 0.012), Sem.mul(v_h, 0.6)], [Sem.mul(v_size, 0.022), Sem.mul(v_h, 0.78)], [0, v_h]], 6, v_color, v_root, v_pos)
	return v_root

static func gen_record_station(v_name, v_mats, v_width = 0.9, v_height = 1.45, v_kind = "record", v_parent = null):
	var v_a = null
	var v_base = null
	var v_i = null
	var v_reel = null
	var v_root = null
	var v_volume = null
	var v_x = null
	v_root = Geo.gen_group(v_name, [0, 0, 0], 0, v_parent)
	gen_cabinet(Sem.add(v_name, "_Case"), v_mats, v_width, 0.38, Sem.mul(v_height, 0.74), 3, v_root)
	Geo.gen_box(Sem.add(v_name, "_Top"), [0, 0, Sem.mul(v_height, 0.76)], [Sem.add(v_width, 0.06), 0.45, 0.06], v_mats["wood_light"], 0.012, v_root)
	if Sem.truth(((v_kind == "audio"))):
		v_base = [0, 0, Sem.mul(v_height, 0.85)]
		Geo.gen_box(Sem.add(v_name, "_Recorder"), v_base, [Sem.mul(v_width, 0.72), 0.3, 0.18], v_mats["stone_dark"], 0.016, v_root)
		for tmp_35 in [Sem.mul(Sem.neg(v_width), 0.2), Sem.mul(v_width, 0.2)]:
			v_x = tmp_35
			v_reel = Geo.gen_cylinder(Sem.add(v_name, "_Reel"), [v_x, Sem.neg(0.17), Sem.mul(v_height, 0.88)], Sem.mul(v_width, 0.13), 0.026, v_mats["gold"], 10, v_root)
			v_reel.rotation_euler[0] = Sem.div(PI, 2)
			for tmp_36 in [0, 2.09, 4.19]:
				v_a = tmp_36
				Geo.gen_ico(Sem.add(v_name, "_ReelHole"), [Sem.add(v_x, Sem.mul(Sem.mul(cos(v_a), v_width), 0.075)), Sem.neg(0.19), Sem.add(Sem.mul(v_height, 0.88), Sem.mul(Sem.mul(sin(v_a), v_width), 0.075))], Sem.mul(v_width, 0.025), v_mats["wood_dark"], 1, v_root)
	else:
		if Sem.truth(((v_kind == "monitor"))):
			Geo.gen_box(Sem.add(v_name, "_Panel"), [0, 0.07, Sem.mul(v_height, 0.91)], [Sem.mul(v_width, 0.75), 0.11, Sem.mul(v_height, 0.29)], v_mats["stone_dark"], 0.012, v_root)
			for tmp_37 in range(3):
				v_i = tmp_37
				Geo.gen_ico(Sem.add(v_name, "_Signal"), [Sem.add(Sem.mul(Sem.neg(v_width), 0.22), Sem.mul(Sem.mul(v_i, v_width), 0.22)), Sem.neg(0.002), Sem.mul(v_height, 0.96)], 0.04, (v_mats["green"] if Sem.truth(((v_i < 2))) else v_mats["gold"]), 1, v_root)
		else:
			v_volume = load("res://tools/building_construction/BuildingConstruction/Tables/FurnitureRecipes.gd").gen_open_book(Sem.add(v_name, "_Ledger"), v_mats, Sem.mul(v_width, 0.65), 0.3, 0.055, v_root)
			v_volume.location = [0, Sem.neg(0.03), Sem.mul(v_height, 0.8)]
			Geo.gen_beam(Sem.add(v_name, "_Pen"), [0.23, Sem.neg(0.1), Sem.mul(v_height, 0.82)], [0.29, 0.12, Sem.mul(v_height, 0.84)], 0.012, 0.012, v_mats["gold"], v_root, 0.008)
	return v_root

static func gen_bottles(v_name, v_mats, v_count = 6, v_spacing = 0.17, v_parent = null):
	var v_i = null
	var v_obj = null
	var v_root = null
	v_root = Geo.gen_group(v_name, [0, 0, 0], 0, v_parent)
	for tmp_38 in range(v_count):
		v_i = tmp_38
		v_obj = gen_vessel(Sem.add(v_name, Sem.mod("_%02d", v_i)), v_mats, 0.055, Sem.add(0.17, Sem.mul(Sem.mod(v_i, 3), 0.035)), "bottle", v_root)
		v_obj.location = [Sem.mul(Sem.sub(v_i, Sem.div(Sem.sub(v_count, 1), 2)), v_spacing), 0, 0]
	return v_root

static func gen_crates(v_name, v_mats, v_width = 0.9, v_depth = 0.7, v_height = 0.75, v_stack = 2, v_parent = null):
	var v_h = null
	var v_root = null
	var v_row = null
	var v_x = null
	var v_z = null
	v_root = Geo.gen_group(v_name, [0, 0, 0], 0, v_parent)
	for tmp_39 in range(v_stack):
		v_row = tmp_39
		v_z = Sem.mul(v_row, Sem.add(v_height, 0.02))
		Geo.gen_box(Sem.add(v_name, "_Box"), [0, 0, Sem.add(v_z, Sem.div(v_height, 2))], [v_width, v_depth, v_height], v_mats["wood_light"], 0.008, v_root)
		for tmp_40 in [Sem.mul(Sem.neg(v_width), 0.35), Sem.mul(v_width, 0.35)]:
			v_x = tmp_40
			Geo.gen_box(Sem.add(v_name, "_Strap"), [v_x, Sem.sub(Sem.div(Sem.neg(v_depth), 2), 0.012), Sem.add(v_z, Sem.div(v_height, 2))], [0.06, 0.03, v_height], v_mats["wood"], 0.004, v_root)
		for tmp_41 in [0.1, Sem.sub(v_height, 0.1)]:
			v_h = tmp_41
			Geo.gen_box(Sem.add(v_name, "_Cross"), [0, Sem.sub(Sem.div(Sem.neg(v_depth), 2), 0.03), Sem.add(v_z, v_h)], [v_width, 0.04, 0.075], v_mats["wood"], 0.004, v_root)
		Geo.gen_beam(Sem.add(v_name, "_Diagonal"), [Sem.mul(Sem.neg(v_width), 0.4), Sem.sub(Sem.div(Sem.neg(v_depth), 2), 0.06), Sem.add(v_z, 0.12)], [Sem.mul(v_width, 0.4), Sem.sub(Sem.div(Sem.neg(v_depth), 2), 0.06), Sem.sub(Sem.add(v_z, v_height), 0.12)], 0.06, 0.03, v_mats["wood"], v_root, 0.003)
	return v_root

static func gen_sacks(v_name, v_mats, v_count = 3, v_parent = null):
	var v_i = null
	var v_obj = null
	var v_root = null
	var v_x = null
	var v_y = null
	v_root = Geo.gen_group(v_name, [0, 0, 0], 0, v_parent)
	for tmp_42 in range(v_count):
		v_i = tmp_42
		v_x = Sem.sub(Sem.mul(Sem.mod(v_i, 2), 0.48), 0.24)
		v_y = Sem.mul(Sem.floor_div(v_i, 2), 0.42)
		v_obj = Geo.gen_ico(Sem.add(v_name, "_Sack"), [v_x, v_y, 0.32], 0.38, v_mats["stone"], 2, v_root)
		v_obj.scale = [0.72, 0.65, 1]
		Geo.gen_cylinder(Sem.add(v_name, "_Tie"), [v_x, v_y, 0.66], 0.07, 0.08, v_mats["wood"], 8, v_root)
	return v_root

