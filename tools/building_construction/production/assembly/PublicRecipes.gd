@tool
extends RefCounted

# Direct port of kit/public_props.py. Z-up recipe coordinates convert at the geometry boundary.
const Sem = preload("res://tools/building_construction/BuildingConstruction/Shared/RecipeSemantics.gd")
const Geo = preload("res://tools/building_construction/BuildingConstruction/Shared/RecipeGeometry.gd")
const PublicGeometry = preload("../rule/PublicGeometryRecipes.gd")
const EPS = 1e-9

static func gen_ring_band(v_name, v_mats, v_radius = 1.0, v_width = 0.07, v_depth = 0.045, v_segments = 24, v_parent = null):
	return PublicGeometry.gen_ring_band(v_name, v_mats, v_radius, v_width, v_depth, v_segments, v_parent)

static func gen_armillary(v_name, v_mats, v_radius = 1.12, v_height = 2.7, v_parent = null):
	return PublicGeometry.gen_armillary(v_name, v_mats, v_radius, v_height, v_parent)

static func gen_resonance_tubes(v_name, v_mats, v_width = 3.6, v_height = 2.9, v_count = 11, v_parent = null):
	return PublicGeometry.gen_resonance_tubes(v_name, v_mats, v_width, v_height, v_count, v_parent)

static func gen_balance(v_name, v_mats, v_width = 0.66, v_height = 0.68, v_parent = null):
	return PublicGeometry.gen_balance(v_name, v_mats, v_width, v_height, v_parent)

static func gen_magnifier(v_name, v_mats, v_height = 0.55, v_parent = null):
	return PublicGeometry.gen_magnifier(v_name, v_mats, v_height, v_parent)

static func gen_stamp_press(v_name, v_mats, v_width = 0.5, v_height = 0.65, v_parent = null):
	return PublicGeometry.gen_stamp_press(v_name, v_mats, v_width, v_height, v_parent)

static func gen_records_pillar(v_name, v_mats, v_radius = 0.66, v_height = 1.75, v_parent = null):
	return PublicGeometry.gen_records_pillar(v_name, v_mats, v_radius, v_height, v_parent)

static func gen_medicine_cabinet(v_name, v_mats, v_width = 1.5, v_height = 2.2, v_parent = null):
	var v_bs = null
	var v_i = null
	var v_root = null
	var v_x = null
	var v_z = null
	v_root = Geo.gen_group(v_name, [0, 0, 0], 0, v_parent)
	load("res://tools/building_construction/BuildingConstruction/Props/SpecialRecipes.gd").gen_cabinet(Sem.add(v_name, "_Base"), v_mats, v_width, 0.48, 0.66, 0, v_root)
	Geo.gen_box(Sem.add(v_name, "_Back"), [0, 0.2, Sem.mul(v_height, 0.63)], [v_width, 0.08, Sem.mul(v_height, 0.72)], v_mats["wood_dark"], 0.008, v_root)
	for tmp_14 in [Sem.add(Sem.div(Sem.neg(v_width), 2), 0.04), Sem.sub(Sem.div(v_width, 2), 0.04)]:
		v_x = tmp_14
		Geo.gen_box(Sem.add(v_name, "_Side"), [v_x, 0, Sem.mul(v_height, 0.64)], [0.08, 0.48, Sem.mul(v_height, 0.73)], v_mats["wood"], 0.008, v_root)
	for tmp_15 in range(4):
		v_i = tmp_15
		v_z = Sem.add(0.69, Sem.div(Sem.mul(v_i, Sem.sub(v_height, 0.73)), 3))
		Geo.gen_box(Sem.add(v_name, "_Shelf"), [0, 0, v_z], [v_width, 0.5, 0.05], v_mats["wood_light"], 0.008, v_root)
		if Sem.truth(((v_i < 3))):
			v_bs = load("res://tools/building_construction/BuildingConstruction/Props/SpecialRecipes.gd").gen_bottles(Sem.add(Sem.add(v_name, "_Bottles_"), str(v_i)), v_mats, 6, Sem.div(Sem.sub(v_width, 0.25), 6), v_root)
			v_bs.location = [0, Sem.neg(0.07), Sem.add(v_z, 0.03)]
	Geo.gen_box(Sem.add(v_name, "_Crown"), [0, 0, Sem.add(v_height, 0.05)], [Sem.add(v_width, 0.12), 0.55, 0.11], v_mats["wood_light"], 0.01, v_root)
	return v_root

static func gen_dish_rack(v_name, v_mats, v_width = 1.7, v_height = 1.7, v_parent = null):
	var v_i = null
	var v_root = null
	var v_v = null
	var v_x = null
	var v_z = null
	v_root = Geo.gen_group(v_name, [0, 0, 0], 0, v_parent)
	load("res://tools/building_construction/BuildingConstruction/Props/SpecialRecipes.gd").gen_work_counter(Sem.add(v_name, "_Base"), v_mats, v_width, 0.6, 0.86, v_root)
	for tmp_16 in [Sem.add(Sem.div(Sem.neg(v_width), 2), 0.05), Sem.sub(Sem.div(v_width, 2), 0.05)]:
		v_x = tmp_16
		Geo.gen_box(Sem.add(v_name, "_Post"), [v_x, 0.22, Sem.mul(v_height, 0.75)], [0.08, 0.08, Sem.mul(v_height, 0.5)], v_mats["wood"], 0.008, v_root)
	for tmp_17 in [1.18, 1.65]:
		v_z = tmp_17
		Geo.gen_box(Sem.add(v_name, "_Shelf"), [0, 0.1, v_z], [v_width, 0.4, 0.06], v_mats["wood"], 0.008, v_root)
		for tmp_18 in range(5):
			v_i = tmp_18
			v_v = load("res://tools/building_construction/BuildingConstruction/Props/SpecialRecipes.gd").gen_vessel(Sem.add(v_name, "_Cup"), v_mats, 0.075, 0.13, "cup", v_root)
			v_v.location = [Sem.add(Sem.mul(Sem.neg(v_width), 0.36), Sem.mul(Sem.mul(v_i, v_width), 0.18)), 0.07, Sem.add(v_z, 0.03)]
	for tmp_19 in range(6):
		v_i = tmp_19
		v_v = load("res://tools/building_construction/BuildingConstruction/Props/SpecialRecipes.gd").gen_vessel(Sem.add(v_name, "_Plate"), v_mats, 0.19, 0.035, "plate", v_root)
		v_v.location = [Sem.mul(Sem.neg(v_width), 0.25), Sem.neg(0.08), Sem.add(0.86, Sem.mul(v_i, 0.025))]
	return v_root

static func gen_planting_bed(v_name, v_mats, v_width = 1.8, v_depth = 3.2, v_height = 0.65, v_seed = 8, v_parent = null):
	var v_i = null
	var v_j = null
	var v_p = null
	var v_root = null
	var v_x = null
	var v_y = null
	v_root = Geo.gen_group(v_name, [0, 0, 0], 0, v_parent)
	Geo.gen_box(Sem.add(v_name, "_Box"), [0, 0, Sem.div(v_height, 2)], [v_width, v_depth, v_height], v_mats["wood"], 0.02, v_root)
	Geo.gen_box(Sem.add(v_name, "_Soil"), [0, 0, Sem.add(v_height, 0.008)], [Sem.sub(v_width, 0.12), Sem.sub(v_depth, 0.12), 0.03], v_mats["wood_dark"], 0.008, v_root)
	for tmp_20 in [Sem.div(Sem.neg(v_width), 2), Sem.div(v_width, 2)]:
		v_x = tmp_20
		Geo.gen_box(Sem.add(v_name, "_RimX"), [v_x, 0, Sem.add(v_height, 0.04)], [0.1, Sem.add(v_depth, 0.1), 0.1], v_mats["wood_light"], 0.01, v_root)
	for tmp_21 in [Sem.div(Sem.neg(v_depth), 2), Sem.div(v_depth, 2)]:
		v_y = tmp_21
		Geo.gen_box(Sem.add(v_name, "_RimY"), [0, v_y, Sem.add(v_height, 0.04)], [v_width, 0.1, 0.1], v_mats["wood_light"], 0.01, v_root)
	for tmp_22 in Sem.py_enumerate([Sem.mul(Sem.neg(v_depth), 0.32), 0, Sem.mul(v_depth, 0.32)]):
		var tmp_23 = tmp_22
		v_i = tmp_23[0]
		v_y = tmp_23[1]
		for tmp_24 in Sem.py_enumerate([Sem.mul(Sem.neg(v_width), 0.26), Sem.mul(v_width, 0.26)]):
			var tmp_25 = tmp_24
			v_j = tmp_25[0]
			v_x = tmp_25[1]
			v_p = load("res://tools/building_construction/BuildingConstruction/Tables/FurnitureRecipes.gd").gen_planter(Sem.add(v_name, Sem.mod("_Plant_%d_%d", [v_i, v_j])), v_mats, 0.59, 0.72, 3, Sem.add(Sem.add(v_seed, Sem.mul(v_i, 2)), v_j), v_root)
			v_p.location = [v_x, v_y, Sem.sub(v_height, 0.25)]
	return v_root

static func gen_greenhouse_frame(v_name, v_mats, v_width = 8, v_depth = 8, v_eave = 3.5, v_rise = 1.25, v_bays = 4, v_parent = null):
	return PublicGeometry.gen_greenhouse_frame(v_name, v_mats, v_width, v_depth, v_eave, v_rise, v_bays, v_parent)

static func gen_watering_can(v_name, v_mats, v_radius = 0.18, v_height = 0.35, v_parent = null):
	var v_root = null
	v_root = Geo.gen_group(v_name, [0, 0, 0], 0, v_parent)
	Geo.gen_lathe(Sem.add(v_name, "_Can"), [[0, 0], [v_radius, 0], [v_radius, Sem.mul(v_height, 0.8)], [Sem.mul(v_radius, 0.8), v_height]], 8, v_mats["gold"], v_root, [0, 0, 0])
	Geo.gen_beam(Sem.add(v_name, "_Spout"), [Sem.mul(v_radius, 0.8), 0, Sem.mul(v_height, 0.2)], [Sem.mul(v_radius, 2.8), 0, Sem.mul(v_height, 0.9)], 0.055, 0.055, v_mats["gold"], v_root, 0.008)
	Geo.gen_beam(Sem.add(v_name, "_HandleA"), [Sem.mul(Sem.neg(v_radius), 0.7), 0, Sem.mul(v_height, 0.7)], [Sem.mul(Sem.neg(v_radius), 1.5), 0, Sem.mul(v_height, 1.2)], 0.035, 0.035, v_mats["gold"], v_root, 0.008)
	Geo.gen_beam(Sem.add(v_name, "_HandleB"), [Sem.mul(Sem.neg(v_radius), 1.5), 0, Sem.mul(v_height, 1.2)], [0, 0, Sem.mul(v_height, 1.3)], 0.035, 0.035, v_mats["gold"], v_root, 0.008)
	return v_root

static func gen_grille(v_name, v_mats, v_width = 1.1, v_height = 1.8, v_parent = null):
	return PublicGeometry.gen_grille(v_name, v_mats, v_width, v_height, v_parent)
