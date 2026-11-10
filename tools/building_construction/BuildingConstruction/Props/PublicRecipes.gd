@tool
extends RefCounted

# Direct port of kit/public_props.py. Z-up recipe coordinates convert at the geometry boundary.
const Sem = preload("res://tools/building_construction/BuildingConstruction/Shared/RecipeSemantics.gd")
const Geo = preload("res://tools/building_construction/BuildingConstruction/Shared/RecipeGeometry.gd")
const EPS = 1e-9

static func gen_ring_band(v_name, v_mats, v_radius = 1.0, v_width = 0.07, v_depth = 0.045, v_segments = 24, v_parent = null):
	var v_faces = null
	var v_i = null
	var v_j = null
	var v_r = null
	var v_root = null
	var v_vertices = null
	var v_z = null
	v_root = Geo.gen_group(v_name, [0, 0, 0], 0, v_parent)
	v_vertices = []
	for tmp_1 in [[Sem.sub(v_radius, Sem.div(v_width, 2)), Sem.div(Sem.neg(v_depth), 2)], [Sem.add(v_radius, Sem.div(v_width, 2)), Sem.div(Sem.neg(v_depth), 2)], [Sem.sub(v_radius, Sem.div(v_width, 2)), Sem.div(v_depth, 2)], [Sem.add(v_radius, Sem.div(v_width, 2)), Sem.div(v_depth, 2)]]:
		var tmp_2 = tmp_1
		v_r = tmp_2[0]
		v_z = tmp_2[1]
		v_vertices.append_array(Sem.map_array(range(v_segments), func(tmp_3): var tmp_4 = tmp_3; return [Sem.mul(v_r, cos(Sem.div(Sem.mul(Sem.mul(2, PI), tmp_4), v_segments))), Sem.mul(v_r, sin(Sem.div(Sem.mul(Sem.mul(2, PI), tmp_4), v_segments))), v_z]))
	v_faces = []
	for tmp_5 in range(v_segments):
		v_i = tmp_5
		v_j = Sem.mod(Sem.add(v_i, 1), v_segments)
		v_faces.append_array([[v_i, v_j, Sem.add(v_segments, v_j), Sem.add(v_segments, v_i)], [Sem.add(Sem.mul(2, v_segments), v_i), Sem.add(Sem.mul(3, v_segments), v_i), Sem.add(Sem.mul(3, v_segments), v_j), Sem.add(Sem.mul(2, v_segments), v_j)], [v_i, Sem.add(Sem.mul(2, v_segments), v_i), Sem.add(Sem.mul(2, v_segments), v_j), v_j], [Sem.add(v_segments, v_i), Sem.add(v_segments, v_j), Sem.add(Sem.mul(3, v_segments), v_j), Sem.add(Sem.mul(3, v_segments), v_i)]])
	Geo.gen_mesh(Sem.add(v_name, "_Band"), v_vertices, v_faces, v_mats["gold"], v_root, 0.003)
	return v_root

static func gen_armillary(v_name, v_mats, v_radius = 1.12, v_height = 2.7, v_parent = null):
	var v_angle = null
	var v_center = null
	var v_i = null
	var v_ring = null
	var v_root = null
	var v_x = null
	v_root = Geo.gen_group(v_name, [0, 0, 0], 0, v_parent)
	Geo.gen_lathe(Sem.add(v_name, "_Pedestal"), [[0.65, 0], [0.68, 0.08], [0.55, 0.22], [0.35, 0.65], [0.45, 0.78]], 8, v_mats["wood"], v_root, [0, 0, 0])
	v_center = Sem.sub(v_height, v_radius)
	for tmp_6 in Sem.py_enumerate([0, Sem.div(PI, 2), 0.65]):
		var tmp_7 = tmp_6
		v_i = tmp_7[0]
		v_angle = tmp_7[1]
		v_ring = gen_ring_band(Sem.add(Sem.add(v_name, "_Ring_"), str(v_i)), v_mats, Sem.mul(v_radius, Sem.sub(1, Sem.mul(v_i, 0.09))), 0.085, 0.055, 24, v_root)
		v_ring.location = [0, 0, v_center]
		v_ring.rotation_euler = [v_angle, (0.45 if Sem.truth(((v_i == 2))) else 0), (0.3 if Sem.truth(((v_i == 2))) else 0)]
	Geo.gen_beam(Sem.add(v_name, "_Axis"), [Sem.neg(v_radius), 0, v_center], [v_radius, 0, v_center], 0.065, 0.065, v_mats["gold"], v_root, 0.008)
	Geo.gen_ico(Sem.add(v_name, "_Core"), [0, 0, v_center], Sem.mul(v_radius, 0.22), v_mats["gold"], 1, v_root)
	for tmp_8 in [Sem.mul(Sem.neg(v_radius), 0.9), Sem.mul(v_radius, 0.9)]:
		v_x = tmp_8
		Geo.gen_beam(Sem.add(v_name, "_Stanchion"), [Sem.mul(v_x, 1.15), 0, 0], [v_x, 0, v_center], 0.09, 0.09, v_mats["gold"], v_root, 0.008)
		Geo.gen_box(Sem.add(v_name, "_Foot"), [Sem.mul(v_x, 1.15), 0, 0.06], [0.3, 0.35, 0.12], v_mats["wood_dark"], 0.02, v_root)
	return v_root

static func gen_resonance_tubes(v_name, v_mats, v_width = 3.6, v_height = 2.9, v_count = 11, v_parent = null):
	var v_h = null
	var v_i = null
	var v_root = null
	var v_x = null
	v_root = Geo.gen_group(v_name, [0, 0, 0], 0, v_parent)
	load("res://tools/building_construction/BuildingConstruction/Props/SpecialRecipes.gd").gen_cabinet(Sem.add(v_name, "_Base"), v_mats, v_width, 0.55, 0.68, 0, v_root)
	for tmp_9 in range(v_count):
		v_i = tmp_9
		v_x = Sem.add(Sem.mul(Sem.neg(v_width), 0.43), Sem.div(Sem.mul(Sem.mul(v_i, v_width), 0.86), Sem.sub(v_count, 1)))
		v_h = Sem.mul(v_height, Sem.add(0.37, Sem.div(Sem.mul(0.56, v_i), Sem.sub(v_count, 1))))
		Geo.gen_lathe(Sem.add(v_name, Sem.mod("_Pipe_%02d", v_i)), [[0.09, 0], [0.09, v_h], [0.073, v_h], [0.073, 0.12], [0, 0.12]], 10, v_mats["gold"], v_root, [v_x, 0, 0.66])
		Geo.gen_box(Sem.add(v_name, Sem.mod("_Mouth_%02d", v_i)), [v_x, Sem.neg(0.092), 0.84], [0.1, 0.015, 0.1], v_mats["wood_dark"], 0, v_root)
	Geo.gen_box(Sem.add(v_name, "_Support"), [0, 0.02, 1.2], [v_width, 0.12, 0.08], v_mats["wood_light"], 0.012, v_root)
	return v_root

static func gen_balance(v_name, v_mats, v_width = 0.66, v_height = 0.68, v_parent = null):
	var v_pan = null
	var v_root = null
	var v_x = null
	var v_y = null
	v_root = Geo.gen_group(v_name, [0, 0, 0], 0, v_parent)
	Geo.gen_box(Sem.add(v_name, "_Base"), [0, 0, 0.035], [0.24, 0.22, 0.07], v_mats["wood"], 0.012, v_root)
	Geo.gen_beam(Sem.add(v_name, "_Stem"), [0, 0, 0.07], [0, 0, v_height], 0.025, 0.025, v_mats["gold"], v_root, 0.008)
	Geo.gen_beam(Sem.add(v_name, "_Cross"), [Sem.div(Sem.neg(v_width), 2), 0, Sem.sub(v_height, 0.08)], [Sem.div(v_width, 2), 0, Sem.sub(v_height, 0.08)], 0.025, 0.025, v_mats["gold"], v_root, 0.008)
	for tmp_10 in [Sem.mul(Sem.neg(v_width), 0.43), Sem.mul(v_width, 0.43)]:
		v_x = tmp_10
		for tmp_11 in [Sem.neg(0.09), 0.09]:
			v_y = tmp_11
			Geo.gen_beam(Sem.add(v_name, "_Wire"), [v_x, 0, Sem.sub(v_height, 0.08)], [v_x, v_y, Sem.mul(v_height, 0.4)], 0.008, 0.008, v_mats["gold"], v_root, 0)
		v_pan = load("res://tools/building_construction/BuildingConstruction/Props/SpecialRecipes.gd").gen_vessel(Sem.add(v_name, "_Pan"), v_mats, 0.13, 0.04, "plate", v_root)
		v_pan.location = [v_x, 0, Sem.mul(v_height, 0.4)]
	return v_root

static func gen_magnifier(v_name, v_mats, v_height = 0.55, v_parent = null):
	var v_ring = null
	var v_root = null
	v_root = Geo.gen_group(v_name, [0, 0, 0], 0, v_parent)
	Geo.gen_box(Sem.add(v_name, "_Base"), [0, 0, 0.025], [0.2, 0.2, 0.05], v_mats["gold"], 0.01, v_root)
	Geo.gen_beam(Sem.add(v_name, "_Stand"), [0, 0, 0.05], [0, 0, Sem.sub(v_height, 0.1)], 0.018, 0.018, v_mats["gold"], v_root, 0.008)
	v_ring = gen_ring_band(Sem.add(v_name, "_Lens"), v_mats, 0.12, 0.025, 0.02, 16, v_root)
	v_ring.location = [0, Sem.neg(0.07), Sem.sub(v_height, 0.08)]
	v_ring.rotation_euler[0] = 1.0
	return v_root

static func gen_stamp_press(v_name, v_mats, v_width = 0.5, v_height = 0.65, v_parent = null):
	var v_root = null
	var v_x = null
	v_root = Geo.gen_group(v_name, [0, 0, 0], 0, v_parent)
	Geo.gen_box(Sem.add(v_name, "_Base"), [0, 0, 0.05], [v_width, 0.45, 0.1], v_mats["wood"], 0.012, v_root)
	for tmp_12 in [Sem.mul(Sem.neg(v_width), 0.36), Sem.mul(v_width, 0.36)]:
		v_x = tmp_12
		Geo.gen_box(Sem.add(v_name, "_Upright"), [v_x, 0.06, Sem.mul(v_height, 0.5)], [0.07, 0.08, Sem.mul(v_height, 0.8)], v_mats["gold"], 0.008, v_root)
	Geo.gen_box(Sem.add(v_name, "_Cross"), [0, 0.06, Sem.mul(v_height, 0.9)], [Sem.mul(v_width, 0.85), 0.1, 0.09], v_mats["gold"], 0.01, v_root)
	Geo.gen_beam(Sem.add(v_name, "_Screw"), [0, 0.06, 0.17], [0, 0.06, v_height], 0.045, 0.045, v_mats["stone_dark"], v_root, 0.008)
	Geo.gen_box(Sem.add(v_name, "_PressurePlate"), [0, 0.02, 0.19], [Sem.mul(v_width, 0.62), 0.28, 0.05], v_mats["gold"], 0.008, v_root)
	Geo.gen_beam(Sem.add(v_name, "_Lever"), [Sem.mul(Sem.neg(v_width), 0.6), 0.06, v_height], [Sem.mul(v_width, 0.45), 0.06, v_height], 0.028, 0.028, v_mats["gold"], v_root, 0.008)
	return v_root

static func gen_records_pillar(v_name, v_mats, v_radius = 0.66, v_height = 1.75, v_parent = null):
	var v_a = null
	var v_g = null
	var v_root = null
	var v_side = null
	v_root = Geo.gen_group(v_name, [0, 0, 0], 0, v_parent)
	Geo.gen_lathe(Sem.add(v_name, "_Stone"), [[Sem.add(v_radius, 0.12), 0], [Sem.add(v_radius, 0.12), 0.1], [v_radius, 0.17], [v_radius, Sem.sub(v_height, 0.13)], [Sem.add(v_radius, 0.1), Sem.sub(v_height, 0.1)], [Sem.add(v_radius, 0.1), v_height], [Sem.mul(v_radius, 0.86), Sem.add(v_height, 0.1)]], 8, v_mats["stone"], v_root, [0, 0, 0])
	for tmp_13 in range(8):
		v_side = tmp_13
		v_a = Sem.add(Sem.div(Sem.mul(Sem.mul(2, PI), v_side), 8), Sem.div(PI, 8))
		v_g = Geo.gen_group(Sem.add(Sem.add(v_name, "_Face_"), str(v_side)), [Sem.mul(Sem.mul(sin(v_a), v_radius), 0.94), Sem.mul(Sem.mul(Sem.neg(cos(v_a)), v_radius), 0.94), 0.3], v_a, v_root)
		load("res://tools/building_construction/BuildingConstruction/Props/SpecialRecipes.gd").gen_cabinet(Sem.add(Sem.add(v_name, "_Drawers_"), str(v_side)), v_mats, Sem.mul(v_radius, 0.55), 0.05, Sem.sub(v_height, 0.5), 4, v_g)
	return v_root

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
	var v_a = null
	var v_b = null
	var v_i = null
	var v_p = null
	var v_root = null
	var v_x = null
	var v_y = null
	var v_z = null
	v_root = Geo.gen_group(v_name, [0, 0, 0], 0, v_parent)
	for tmp_26 in range(Sem.add(v_bays, 1)):
		v_i = tmp_26
		v_y = Sem.div(Sem.mul(v_depth, v_i), v_bays)
		v_p = [[Sem.div(Sem.neg(v_width), 2), v_y, 0], [Sem.div(Sem.neg(v_width), 2), v_y, v_eave], [0, v_y, Sem.add(v_eave, v_rise)], [Sem.div(v_width, 2), v_y, v_eave], [Sem.div(v_width, 2), v_y, 0]]
		for tmp_27 in Sem.py_zip(v_p, Sem.slice_array(v_p, 1, null, null)):
			var tmp_28 = tmp_27
			v_a = tmp_28[0]
			v_b = tmp_28[1]
			Geo.gen_beam(Sem.add(v_name, Sem.mod("_Rib_%02d", v_i)), v_a, v_b, 0.1, 0.1, v_mats["wood_dark"], v_root, 0.008)
	for tmp_29 in [[Sem.div(Sem.neg(v_width), 2), v_eave], [Sem.div(v_width, 2), v_eave], [0, Sem.add(v_eave, v_rise)]]:
		var tmp_30 = tmp_29
		v_x = tmp_30[0]
		v_z = tmp_30[1]
		Geo.gen_beam(Sem.add(v_name, "_Longitudinal"), [v_x, 0, v_z], [v_x, v_depth, v_z], 0.09, 0.09, v_mats["gold"], v_root, 0.008)
	return v_root

static func gen_watering_can(v_name, v_mats, v_radius = 0.18, v_height = 0.35, v_parent = null):
	var v_root = null
	v_root = Geo.gen_group(v_name, [0, 0, 0], 0, v_parent)
	Geo.gen_lathe(Sem.add(v_name, "_Can"), [[0, 0], [v_radius, 0], [v_radius, Sem.mul(v_height, 0.8)], [Sem.mul(v_radius, 0.8), v_height]], 8, v_mats["gold"], v_root, [0, 0, 0])
	Geo.gen_beam(Sem.add(v_name, "_Spout"), [Sem.mul(v_radius, 0.8), 0, Sem.mul(v_height, 0.2)], [Sem.mul(v_radius, 2.8), 0, Sem.mul(v_height, 0.9)], 0.055, 0.055, v_mats["gold"], v_root, 0.008)
	Geo.gen_beam(Sem.add(v_name, "_HandleA"), [Sem.mul(Sem.neg(v_radius), 0.7), 0, Sem.mul(v_height, 0.7)], [Sem.mul(Sem.neg(v_radius), 1.5), 0, Sem.mul(v_height, 1.2)], 0.035, 0.035, v_mats["gold"], v_root, 0.008)
	Geo.gen_beam(Sem.add(v_name, "_HandleB"), [Sem.mul(Sem.neg(v_radius), 1.5), 0, Sem.mul(v_height, 1.2)], [0, 0, Sem.mul(v_height, 1.3)], 0.035, 0.035, v_mats["gold"], v_root, 0.008)
	return v_root

static func gen_grille(v_name, v_mats, v_width = 1.1, v_height = 1.8, v_parent = null):
	var v_i = null
	var v_root = null
	var v_x = null
	var v_z = null
	v_root = Geo.gen_group(v_name, [0, 0, 0], 0, v_parent)
	for tmp_31 in [Sem.div(Sem.neg(v_width), 2), Sem.div(v_width, 2)]:
		v_x = tmp_31
		Geo.gen_box(Sem.add(v_name, "_FrameX"), [v_x, 0, Sem.div(v_height, 2)], [0.08, 0.1, v_height], v_mats["wood"], 0.01, v_root)
	for tmp_32 in [0, v_height]:
		v_z = tmp_32
		Geo.gen_box(Sem.add(v_name, "_FrameZ"), [0, 0, v_z], [v_width, 0.1, 0.08], v_mats["wood"], 0.01, v_root)
	for tmp_33 in range(7):
		v_i = tmp_33
		v_x = Sem.add(Sem.mul(Sem.neg(v_width), 0.42), Sem.div(Sem.mul(Sem.mul(v_i, v_width), 0.84), 6))
		Geo.gen_beam(Sem.add(v_name, "_Bar"), [v_x, 0, 0.05], [v_x, 0, Sem.sub(v_height, 0.05)], 0.024, 0.024, v_mats["gold"], v_root, 0.008)
	Geo.gen_box(Sem.add(v_name, "_OpaqueBacking"), [0, 0.08, Sem.div(v_height, 2)], [v_width, 0.08, v_height], v_mats["wood_dark"], 0, v_root)
	return v_root

