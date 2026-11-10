@tool
extends RefCounted

# Direct port of kit/decor.py. Z-up recipe coordinates convert at the geometry boundary.
const Sem = preload("res://tools/building_construction/BuildingConstruction/Shared/RecipeSemantics.gd")
const Geo = preload("res://tools/building_construction/BuildingConstruction/Shared/RecipeGeometry.gd")
const EPS = 1e-9

static func gen_pedestal(v_name, v_mats, v_height = 0.8, v_width = 0.48, v_parent = null):
	var v_h = null
	var v_mat = null
	var v_root = null
	var v_suffix = null
	var v_w = null
	var v_z = null
	v_root = Geo.gen_group(v_name, [0, 0, 0], 0, v_parent)
	for tmp_1 in [["Foot", 0.06, Sem.mul(v_width, 1.13), 0.12, "wood_light"], ["Plinth", 0.17, v_width, 0.16, "wood"], ["Shaft", Sem.mul(v_height, 0.53), Sem.mul(v_width, 0.78), Sem.sub(v_height, 0.29), "wood"], ["Neck", Sem.sub(v_height, 0.13), Sem.mul(v_width, 0.9), 0.1, "wood_dark"], ["Capital", Sem.sub(v_height, 0.055), Sem.mul(v_width, 1.15), 0.11, "wood_light"]]:
		var tmp_2 = tmp_1
		v_suffix = tmp_2[0]
		v_z = tmp_2[1]
		v_w = tmp_2[2]
		v_h = tmp_2[3]
		v_mat = tmp_2[4]
		Geo.gen_box(Sem.add(Sem.add(v_name, "_"), v_suffix), [0, 0, v_z], [v_w, v_w, v_h], v_mats[v_mat], 0.015, v_root)
	Geo.gen_box(Sem.add(v_name, "_Recess"), [0, Sem.mul(Sem.neg(v_width), 0.397), Sem.mul(v_height, 0.52)], [Sem.mul(v_width, 0.48), 0.02, Sem.mul(v_height, 0.48)], v_mats["wood_dark"], 0.008, v_root)
	Geo.gen_box(Sem.add(v_name, "_Panel"), [0, Sem.mul(Sem.neg(v_width), 0.412), Sem.mul(v_height, 0.52)], [Sem.mul(v_width, 0.39), 0.025, Sem.mul(v_height, 0.41)], v_mats["wood"], 0.008, v_root)
	return v_root

static func gen_coat_stand(v_name, v_mats, v_height = 1.95, v_parent = null):
	var v_a = null
	var v_coat = null
	var v_i = null
	var v_level = null
	var v_root = null
	var v_x = null
	var v_y = null
	var v_z = null
	v_root = Geo.gen_group(v_name, [0, 0, 0], 0, v_parent)
	Geo.gen_cylinder(Sem.add(v_name, "_Base"), [0, 0, 0.07], 0.32, 0.14, v_mats["wood_dark"], 8, v_root)
	Geo.gen_cylinder(Sem.add(v_name, "_Base_cap"), [0, 0, 0.16], 0.24, 0.08, v_mats["wood"], 8, v_root)
	Geo.gen_cylinder(Sem.add(v_name, "_Column"), [0, 0, Sem.mul(v_height, 0.5)], 0.047, Sem.sub(v_height, 0.24), v_mats["wood_light"], 8, v_root)
	Geo.gen_ico(Sem.add(v_name, "_Finial"), [0, 0, v_height], 0.085, v_mats["wood_light"], 1, v_root)
	for tmp_3 in [0.68, 0.85]:
		v_level = tmp_3
		v_z = Sem.mul(v_height, v_level)
		for tmp_4 in range(4):
			v_i = tmp_4
			v_a = Sem.add(Sem.div(Sem.mul(v_i, PI), 2), 0.3)
			var tmp_5 = [Sem.mul(0.29, cos(v_a)), Sem.mul(0.29, sin(v_a))]
			v_x = tmp_5[0]
			v_y = tmp_5[1]
			Geo.gen_beam(Sem.add(v_name, "_Arm"), [0, 0, v_z], [v_x, v_y, Sem.add(v_z, 0.1)], 0.038, 0.038, v_mats["wood_light"], v_root, 0.008)
			Geo.gen_ico(Sem.add(v_name, "_Hook"), [v_x, v_y, Sem.add(v_z, 0.13)], 0.055, v_mats["gold"], 1, v_root)
	v_coat = Geo.gen_polyprism(Sem.add(v_name, "_Hanging_coat"), [[Sem.neg(0.17), Sem.neg(0.12)], [0.05, Sem.neg(0.16)], [0.17, Sem.neg(0.08)], [0.11, Sem.neg(0.02)], [Sem.neg(0.1), Sem.neg(0.01)]], 0.45, 1.46, v_mats["book_red"], v_root)
	v_coat.location = [0.1, 0.08, 0]
	return v_root

static func gen_platform(v_name, v_mats, v_width = 2, v_depth = 1.5, v_height = 1.8, v_thickness = 0.18, v_parent = null):
	var v_root = null
	v_root = Geo.gen_group(v_name, [0, 0, 0], 0, v_parent)
	Geo.gen_box(Sem.add(v_name, "_Timber_fascia"), [0, 0, Sem.sub(v_height, Sem.div(v_thickness, 2))], [v_width, v_depth, v_thickness], v_mats["wood"], 0.018, v_root)
	Geo.gen_box(Sem.add(v_name, "_Stone_top"), [0, 0, Sem.add(v_height, 0.025)], [Sem.sub(v_width, 0.035), Sem.sub(v_depth, 0.035), 0.05], v_mats["stone"], 0.012, v_root)
	return v_root

static func gen_library_rail(v_name, v_mats, v_length = 4, v_height = 3.2, v_parent = null):
	var v_root = null
	var v_x = null
	v_root = Geo.gen_group(v_name, [0, 0, 0], 0, v_parent)
	Geo.gen_beam(Sem.add(v_name, "_Rail"), [Sem.div(Sem.neg(v_length), 2), Sem.neg(0.36), v_height], [Sem.div(v_length, 2), Sem.neg(0.36), v_height], 0.05, 0.05, v_mats["gold"], v_root, 0.008)
	for tmp_6 in [Sem.div(Sem.neg(v_length), 2), 0, Sem.div(v_length, 2)]:
		v_x = tmp_6
		Geo.gen_beam(Sem.add(v_name, "_Mount"), [v_x, 0, v_height], [v_x, Sem.neg(0.36), v_height], 0.06, 0.06, v_mats["gold"], v_root, 0.008)
		Geo.gen_cylinder(Sem.add(v_name, "_End_cap"), [v_x, Sem.neg(0.36), v_height], 0.075, 0.08, v_mats["gold"], 8, v_root)
	return v_root

