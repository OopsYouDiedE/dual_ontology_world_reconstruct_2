@tool
extends RefCounted

# Direct port of kit/variants.py. Z-up recipe coordinates convert at the geometry boundary.
const Sem = preload("res://tools/building_construction/BuildingConstruction/Shared/RecipeSemantics.gd")
const Geo = preload("res://tools/building_construction/BuildingConstruction/Shared/RecipeGeometry.gd")
const EPS = 1e-9

static func gen__root(v_name, v_kind, v_points, v_parent = null):
	var v_p = null
	var v_root = null
	v_root = Geo.gen_group(v_name, [0, 0, 0], 0, v_parent)
	v_root["kind"] = v_kind
	v_root["front_axis"] = "-Y"
	v_root["opening_profile_json"] = JSON.stringify(v_points)
	v_root["clear_width"] = Sem.sub(Sem.py_max(Sem.map_array(v_points, func(tmp_1): var tmp_2 = tmp_1; return tmp_2[0])), Sem.py_min(Sem.map_array(v_points, func(tmp_3): var tmp_4 = tmp_3; return tmp_4[0])))
	v_root["clear_height"] = Sem.sub(Sem.py_max(Sem.map_array(v_points, func(tmp_5): var tmp_6 = tmp_5; return tmp_6[1])), Sem.py_min(Sem.map_array(v_points, func(tmp_7): var tmp_8 = tmp_7; return tmp_8[1])))
	return v_root

static func gen__pane(v_name, v_points, v_mats, v_root):
	var v_pane = null
	var v_polygon = null
	var v_x = null
	var v_z = null
	v_pane = Geo.gen_mesh(Sem.add(v_name, "_Glass"), Sem.map_array(v_points, func(tmp_9): var tmp_10 = tmp_9[0]; var tmp_11 = tmp_9[1]; return [tmp_10, 0.035, tmp_11]), [Sem.py_tuple(range(Sem.py_len(v_points)))], v_mats["glass"], v_root, 0)
	if Sem.truth(((v_pane.data.polygons[0].normal.y > 0))):
		for tmp_12 in v_pane.data.polygons:
			v_polygon = tmp_12
			v_polygon.flip()
		v_pane.data.merge()
	return v_pane

static func gen__window_frame(v_name, v_points, v_mats, v_root, v_frame_width):
	load("res://tools/building_construction/BuildingConstruction/Windows/OpeningRecipes.gd").gen__frame_band(Sem.add(v_name, "_Deep_frame"), v_points, load("res://tools/building_construction/BuildingConstruction/Windows/OpeningRecipes.gd").gen__outset(v_points, v_frame_width), Sem.neg(0.11), 0.1, v_mats["wood_dark"], v_root, 0.007)
	load("res://tools/building_construction/BuildingConstruction/Windows/OpeningRecipes.gd").gen__frame_band(Sem.add(v_name, "_Raised_moulding"), load("res://tools/building_construction/BuildingConstruction/Windows/OpeningRecipes.gd").gen__outset(v_points, Sem.mul(v_frame_width, 0.64)), load("res://tools/building_construction/BuildingConstruction/Windows/OpeningRecipes.gd").gen__outset(v_points, Sem.add(v_frame_width, 0.024)), Sem.neg(0.16), Sem.neg(0.098), v_mats["wood"], v_root, 0.005)
	load("res://tools/building_construction/BuildingConstruction/Windows/OpeningRecipes.gd").gen__frame_band(Sem.add(v_name, "_Inner_bead"), v_points, load("res://tools/building_construction/BuildingConstruction/Windows/OpeningRecipes.gd").gen__outset(v_points, 0.026), Sem.neg(0.145), Sem.neg(0.102), v_mats["wood_light"], v_root, 0.003)

static func gen_rectangular_window(v_name, v_mats, v_width = 1.8, v_height = 2.35, v_cols = 4, v_rows = 5, v_frame_width = 0.13, v_sill = true, v_glass = true, v_parent = null):
	var v_bar = null
	var v_i = null
	var v_j = null
	var v_points = null
	var v_root = null
	if Sem.truth(Sem.either_lazy(((Sem.py_min(v_width, v_height) <= 0.2)), func(): return ((v_frame_width <= 0)))):
		push_error(str("Window width/height must exceed .2m and frame_width > 0"))
		return null
	var tmp_13 = [Sem.py_max(1, int(v_cols)), Sem.py_max(1, int(v_rows))]
	v_cols = tmp_13[0]
	v_rows = tmp_13[1]
	v_frame_width = Sem.py_min(v_frame_width, Sem.mul(v_width, 0.22))
	v_points = [[Sem.div(Sem.neg(v_width), 2), 0], [Sem.div(v_width, 2), 0], [Sem.div(v_width, 2), v_height], [Sem.div(Sem.neg(v_width), 2), v_height]]
	v_root = gen__root(v_name, "rectangular_window", v_points, v_parent)
	var tmp_14 = [v_cols, v_rows]
	v_root["cols"] = tmp_14[0]
	v_root["rows"] = tmp_14[1]
	gen__window_frame(v_name, v_points, v_mats, v_root, v_frame_width)
	if Sem.truth(v_glass):
		gen__pane(v_name, v_points, v_mats, v_root)
	v_bar = Sem.py_min(0.038, Sem.div(v_width, Sem.mul(v_cols, 10)), Sem.div(v_height, Sem.mul(v_rows, 10)))
	for tmp_15 in range(1, v_cols):
		v_i = tmp_15
		Geo.gen_box(Sem.add(v_name, Sem.mod("_Mullion_%02d", v_i)), [Sem.add(Sem.div(Sem.neg(v_width), 2), Sem.div(Sem.mul(v_width, v_i), v_cols)), Sem.neg(0.065), Sem.div(v_height, 2)], [v_bar, 0.075, v_height], v_mats["wood"], 0.003, v_root)
	for tmp_16 in range(1, v_rows):
		v_j = tmp_16
		Geo.gen_box(Sem.add(v_name, Sem.mod("_Transom_%02d", v_j)), [0, Sem.neg(0.067), Sem.div(Sem.mul(v_height, v_j), v_rows)], [v_width, 0.082, v_bar], v_mats["wood"], 0.003, v_root)
	if Sem.truth(v_sill):
		Geo.gen_box(Sem.add(v_name, "_Sill"), [0, Sem.neg(0.115), Sem.neg(0.075)], [Sem.add(Sem.add(v_width, Sem.mul(2, v_frame_width)), 0.18), 0.39, 0.12], v_mats["wood_light"], 0.014, v_root)
		Geo.gen_box(Sem.add(v_name, "_Sill_apron"), [0, Sem.neg(0.055), Sem.neg(0.17)], [Sem.sub(Sem.add(v_width, Sem.mul(2, v_frame_width)), 0.02), 0.18, 0.1], v_mats["wood"], 0.009, v_root)
	return v_root

static func gen_round_window(v_name, v_mats, v_radius = 0.95, v_segments = 12, v_frame_width = 0.13, v_grid = "cross", v_glass = true, v_parent = null):
	var v_angle = null
	var v_boss = null
	var v_count = null
	var v_i = null
	var v_points = null
	var v_root = null
	v_segments = int(v_segments)
	if Sem.truth(Sem.either_lazy(((v_radius <= 0.12)), func(): return Sem.either_lazy(((v_frame_width <= 0)), func(): return ((v_segments not in [8, 12]))))):
		push_error(str("Round window needs radius>.12, frame_width>0, segments=8 or 12"))
		return null
	if Sem.truth(((v_grid not in ["cross", "radial"]))):
		push_error(str("grid must be 'cross' or 'radial'"))
		return null
	v_points = Sem.map_array(range(v_segments), func(tmp_17): var tmp_18 = tmp_17; return [Sem.mul(v_radius, cos(Sem.div(Sem.mul(Sem.mul(2, PI), tmp_18), v_segments))), Sem.add(v_radius, Sem.mul(v_radius, sin(Sem.div(Sem.mul(Sem.mul(2, PI), tmp_18), v_segments))))])
	v_root = gen__root(v_name, "round_window", v_points, v_parent)
	var tmp_19 = [v_radius, v_segments, v_grid]
	v_root["radius"] = tmp_19[0]
	v_root["segments"] = tmp_19[1]
	v_root["grid"] = tmp_19[2]
	gen__window_frame(v_name, v_points, v_mats, v_root, Sem.py_min(v_frame_width, Sem.mul(v_radius, 0.28)))
	if Sem.truth(v_glass):
		gen__pane(v_name, v_points, v_mats, v_root)
	v_count = (4 if Sem.truth(((v_grid == "cross"))) else v_segments)
	for tmp_20 in range(v_count):
		v_i = tmp_20
		v_angle = Sem.div(Sem.mul(Sem.mul(2, PI), v_i), v_count)
		Geo.gen_beam(Sem.add(v_name, Sem.mod("_Ray_%02d", v_i)), [0, Sem.neg(0.067), v_radius], [Sem.mul(v_radius, cos(v_angle)), Sem.neg(0.067), Sem.add(v_radius, Sem.mul(v_radius, sin(v_angle)))], 0.04, 0.076, v_mats["wood_light"], v_root, 0.003)
	v_boss = Geo.gen_cylinder(Sem.add(v_name, "_Centre_boss"), [0, Sem.neg(0.08), v_radius], 0.055, 0.1, v_mats["wood"], 8, v_root)
	v_boss.rotation_euler[0] = Sem.div(PI, 2)
	return v_root

static func gen__clip_x(v_points, v_boundary, v_keep_left):
	var v_clean = null
	var v_current = null
	var v_current_inside = null
	var v_inside = null
	var v_point = null
	var v_previous = null
	var v_previous_inside = null
	var v_result = null
	var v_t = null
	v_result = []
	v_inside = func(v_p): return (((v_p[0] <= Sem.add(v_boundary, 1e-09))) if Sem.truth(v_keep_left) else ((v_p[0] >= Sem.sub(v_boundary, 1e-09))))
	v_previous = v_points[Sem.neg(1)]
	v_previous_inside = v_inside.call(v_previous)
	for tmp_21 in v_points:
		v_current = tmp_21
		v_current_inside = v_inside.call(v_current)
		if Sem.truth(((v_current_inside != v_previous_inside))):
			v_t = Sem.div(Sem.sub(v_boundary, v_previous[0]), Sem.sub(v_current[0], v_previous[0]))
			v_result.append([v_boundary, Sem.add(v_previous[1], Sem.mul(v_t, Sem.sub(v_current[1], v_previous[1])))])
		if Sem.truth(v_current_inside):
			v_result.append(v_current)
		var tmp_22 = [v_current, v_current_inside]
		v_previous = tmp_22[0]
		v_previous_inside = tmp_22[1]
	v_clean = []
	for tmp_23 in v_result:
		v_point = tmp_23
		if Sem.truth(Sem.either_lazy(not Sem.truth(v_clean), func(): return ((Sem.dist(v_point, v_clean[Sem.neg(1)]) > 1e-07)))):
			v_clean.append(v_point)
	if Sem.truth(Sem.both_lazy(((Sem.py_len(v_clean) > 1)), func(): return ((Sem.dist(v_clean[0], v_clean[Sem.neg(1)]) < 1e-07)))):
		v_clean.pop_back()
	return v_clean

static func gen__xz_solid(v_name, v_points, v_front, v_back, v_mat, v_parent):
	var v_faces = null
	var v_i = null
	var v_n = null
	var v_vertices = null
	var v_x = null
	var v_z = null
	v_n = Sem.py_len(v_points)
	v_vertices = Sem.add(Sem.map_array(v_points, func(tmp_24): var tmp_25 = tmp_24[0]; var tmp_26 = tmp_24[1]; return [tmp_25, v_front, tmp_26]), Sem.map_array(v_points, func(tmp_27): var tmp_28 = tmp_27[0]; var tmp_29 = tmp_27[1]; return [tmp_28, v_back, tmp_29]))
	v_faces = [Sem.py_tuple(range(v_n)), Sem.py_tuple(Sem.py_reversed(range(v_n, Sem.mul(2, v_n))))]
	v_faces = Sem.add(v_faces, Sem.map_array(range(v_n), func(tmp_30): var tmp_31 = tmp_30; return [tmp_31, Sem.mod(Sem.add(tmp_31, 1), v_n), Sem.add(Sem.mod(Sem.add(tmp_31, 1), v_n), v_n), Sem.add(tmp_31, v_n)]))
	return Geo.gen_mesh(v_name, v_vertices, v_faces, v_mat, v_parent, 0.005)

static func gen_arched_closed_door(v_name, v_mats, v_width = 2.15, v_height = 2.95, v_rise = 0.78, v_double = true, v_segments = 12, v_frame_width = 0.14, v_parent = null):
	var v_bottom = null
	var v_count = null
	var v_cx = null
	var v_direction = null
	var v_gap = null
	var v_handle_x = null
	var v_handle_z = null
	var v_hinge = null
	var v_hinge_x = null
	var v_hinge_z = null
	var v_inset_inner = null
	var v_inset_outer = null
	var v_j = null
	var v_leaf_width = null
	var v_left_hinged = null
	var v_level = null
	var v_local = null
	var v_max_x = null
	var v_min_x = null
	var v_neck = null
	var v_number = null
	var v_outline = null
	var v_p = null
	var v_panel_width = null
	var v_perimeter = null
	var v_points = null
	var v_root = null
	var v_spring = null
	var v_top = null
	var v_x = null
	var v_z = null
	if Sem.truth(Sem.either_lazy(((v_width <= 0.55)), func(): return Sem.either_lazy(((v_height <= 1.2)), func(): return not Sem.truth(((0.12 < v_rise) and (v_rise < Sem.mul(v_height, 0.7))))))):
		push_error(str("Invalid arched door dimensions"))
		return null
	v_points = load("res://tools/building_construction/BuildingConstruction/Windows/OpeningRecipes.gd").gen_arch_points(v_width, v_height, v_rise, v_segments)
	v_root = gen__root(v_name, ("arched_closed_double_door" if Sem.truth(v_double) else "arched_closed_door"), v_points, v_parent)
	var tmp_32 = [0.0, float(v_rise)]
	v_root["closed_angle"] = tmp_32[0]
	v_root["arch_rise"] = tmp_32[1]
	var tmp_33 = [(2 if Sem.truth(v_double) else 1), int(v_segments)]
	v_root["leaf_count"] = tmp_33[0]
	v_root["arc_segments"] = tmp_33[1]
	v_frame_width = Sem.py_min(float(v_frame_width), Sem.mul(v_width, 0.16))
	load("res://tools/building_construction/BuildingConstruction/Windows/OpeningRecipes.gd").gen__frame_band(Sem.add(v_name, "_Arch_jamb"), v_points, load("res://tools/building_construction/BuildingConstruction/Windows/OpeningRecipes.gd").gen__outset(v_points, v_frame_width), Sem.neg(0.13), 0.14, v_mats["wood_dark"], v_root, 0.008)
	load("res://tools/building_construction/BuildingConstruction/Windows/OpeningRecipes.gd").gen__frame_band(Sem.add(v_name, "_Arch_moulding"), load("res://tools/building_construction/BuildingConstruction/Windows/OpeningRecipes.gd").gen__outset(v_points, Sem.mul(v_frame_width, 0.7)), load("res://tools/building_construction/BuildingConstruction/Windows/OpeningRecipes.gd").gen__outset(v_points, Sem.add(v_frame_width, 0.035)), Sem.neg(0.19), Sem.neg(0.115), v_mats["wood"], v_root, 0.006)
	load("res://tools/building_construction/BuildingConstruction/Windows/OpeningRecipes.gd").gen__frame_band(Sem.add(v_name, "_Arch_inner_bead"), v_points, load("res://tools/building_construction/BuildingConstruction/Windows/OpeningRecipes.gd").gen__outset(v_points, 0.028), Sem.neg(0.165), Sem.neg(0.118), v_mats["wood_light"], v_root, 0.004)
	v_gap = 0.009
	v_perimeter = load("res://tools/building_construction/BuildingConstruction/Windows/OpeningRecipes.gd").gen__outset(v_points, Sem.neg(v_gap))
	v_spring = Sem.sub(v_height, v_rise)
	v_count = (2 if Sem.truth(v_double) else 1)
	for tmp_34 in range(v_count):
		v_number = tmp_34
		v_left_hinged = ((v_number == 0))
		v_direction = (1 if Sem.truth(v_left_hinged) else Sem.neg(1))
		v_hinge_x = (Sem.add(Sem.div(Sem.neg(v_width), 2), v_gap) if Sem.truth(v_left_hinged) else Sem.sub(Sem.div(v_width, 2), v_gap))
		v_hinge_z = 0.006
		v_hinge = Geo.gen_group(Sem.add(v_name, ("_Left_hinge" if Sem.truth(v_left_hinged) else "_Right_hinge")), [v_hinge_x, 0, v_hinge_z], 0, v_root)
		v_hinge["kind"] = "door_hinge"
		v_hinge["open_angle_degrees"] = Sem.mul(Sem.neg(95.0), v_direction)
		v_outline = v_perimeter
		if Sem.truth(v_double):
			v_outline = gen__clip_x(v_perimeter, (Sem.div(Sem.neg(v_gap), 2) if Sem.truth(v_left_hinged) else Sem.div(v_gap, 2)), v_left_hinged)
		v_local = Sem.map_array(v_outline, func(tmp_35): var tmp_36 = tmp_35[0]; var tmp_37 = tmp_35[1]; return [Sem.sub(tmp_36, v_hinge_x), Sem.sub(tmp_37, v_hinge_z)])
		gen__xz_solid(Sem.add(v_name, Sem.mod("_Leaf_%d", v_number)), v_local, Sem.neg(0.04), 0.07, v_mats["wood_dark"], v_hinge)
		v_inset_outer = load("res://tools/building_construction/BuildingConstruction/Windows/OpeningRecipes.gd").gen__outset(v_local, Sem.neg(0.035))
		v_inset_inner = load("res://tools/building_construction/BuildingConstruction/Windows/OpeningRecipes.gd").gen__outset(v_local, Sem.neg(0.065))
		load("res://tools/building_construction/BuildingConstruction/Windows/OpeningRecipes.gd").gen__frame_band(Sem.add(v_name, Sem.mod("_Leaf_outline_%d", v_number)), v_inset_inner, v_inset_outer, Sem.neg(0.091), Sem.neg(0.037), v_mats["wood_light"], v_hinge, 0.003)
		var tmp_42 = [Sem.py_min(Sem.map_array(v_local, func(tmp_38): var tmp_39 = tmp_38; return tmp_39[0])), Sem.py_max(Sem.map_array(v_local, func(tmp_40): var tmp_41 = tmp_40; return tmp_41[0]))]
		v_min_x = tmp_42[0]
		v_max_x = tmp_42[1]
		v_leaf_width = Sem.sub(v_max_x, v_min_x)
		v_cx = Sem.div(Sem.add(v_min_x, v_max_x), 2)
		v_panel_width = Sem.sub(v_leaf_width, 0.2)
		for tmp_43 in Sem.py_enumerate([[0.17, Sem.mul(v_spring, 0.42)], [Sem.add(Sem.mul(v_spring, 0.42), 0.1), Sem.sub(v_spring, 0.15)]]):
			var tmp_44 = tmp_43
			v_level = tmp_44[0]
			var tmp_45 = tmp_44[1]
			v_bottom = tmp_45[0]
			v_top = tmp_45[1]
			if Sem.truth(Sem.both_lazy(((v_panel_width > 0.12)), func(): return ((Sem.sub(v_top, v_bottom) > 0.12)))):
				load("res://tools/building_construction/BuildingConstruction/Windows/OpeningRecipes.gd").gen__raised_panel(Sem.add(v_name, Sem.mod("_Panel_%d_%d", [v_number, v_level])), v_mats, v_cx, Sem.sub(Sem.div(Sem.add(v_bottom, v_top), 2), v_hinge_z), v_panel_width, Sem.sub(v_top, v_bottom), v_hinge)
		v_handle_x = (Sem.sub(v_max_x, 0.085) if Sem.truth(v_left_hinged) else Sem.add(v_min_x, 0.085))
		v_handle_z = Sem.py_min(1.05, Sem.mul(v_spring, 0.53))
		Geo.gen_box(Sem.add(v_name, Sem.mod("_Handle_plate_%d", v_number)), [v_handle_x, Sem.neg(0.13), v_handle_z], [0.05, 0.025, 0.2], v_mats["gold"], 0.006, v_hinge)
		v_neck = Geo.gen_cylinder(Sem.add(v_name, Sem.mod("_Handle_neck_%d", v_number)), [v_handle_x, Sem.neg(0.16), Sem.add(v_handle_z, 0.02)], 0.022, 0.06, v_mats["gold"], 8, v_hinge)
		v_neck.rotation_euler[0] = Sem.div(PI, 2)
		Geo.gen_beam(Sem.add(v_name, Sem.mod("_Handle_lever_%d", v_number)), [v_handle_x, Sem.neg(0.2), Sem.add(v_handle_z, 0.02)], [Sem.sub(v_handle_x, Sem.mul(v_direction, 0.1)), Sem.neg(0.2), Sem.add(v_handle_z, 0.02)], 0.023, 0.026, v_mats["gold"], v_hinge, 0.004)
		for tmp_46 in Sem.py_enumerate([0.23, Sem.mul(v_spring, 0.8)]):
			var tmp_47 = tmp_46
			v_j = tmp_47[0]
			v_z = tmp_47[1]
			Geo.gen_cylinder(Sem.add(v_name, Sem.mod("_Hinge_barrel_%d_%d", [v_number, v_j])), [0, Sem.neg(0.075), v_z], 0.02, 0.14, v_mats["gold"], 8, v_hinge)
		Geo.gen_group(Sem.add(v_name, Sem.mod("_Handle_anchor_%d", v_number)), [v_handle_x, Sem.neg(0.21), v_handle_z], 0, v_hinge)
	Geo.gen_box(Sem.add(v_name, "_Keystone"), [0, Sem.neg(0.21), Sem.add(v_height, Sem.mul(v_frame_width, 0.48))], [0.18, 0.12, Sem.mul(v_frame_width, 1.15)], v_mats["wood_light"], 0.008, v_root)
	Geo.gen_group(Sem.add(v_name, "_Stand_front"), [0, Sem.neg(0.68), 0], 0, v_root)
	Geo.gen_group(Sem.add(v_name, "_Passage_center"), [0, 0, 0], 0, v_root)
	return v_root

