@tool
extends RefCounted

# Direct port of kit/openings.py. Z-up recipe coordinates convert at the geometry boundary.
const Sem = preload("res://tools/building_construction/BuildingConstruction/Shared/RecipeSemantics.gd")
const Geo = preload("res://tools/building_construction/BuildingConstruction/Shared/RecipeGeometry.gd")
const EPS = 1e-9

static func gen_arch_points(v_width, v_height, v_rise = null, v_segments = 10):
	var v_angle = null
	var v_half = null
	var v_j = null
	var v_points = null
	var v_spring = null
	var tmp_1 = [float(v_width), float(v_height)]
	v_width = tmp_1[0]
	v_height = tmp_1[1]
	v_rise = (Sem.div(v_width, 2) if Sem.truth(((v_rise == null))) else float(v_rise))
	v_segments = Sem.py_max(4, int(v_segments))
	if Sem.truth(Sem.either_lazy(((v_width <= 0)), func(): return Sem.either_lazy(((v_height <= 0)), func(): return not Sem.truth(((0 < v_rise) and (v_rise < v_height)))))):
		push_error(str("An arch needs width>0 and 0<rise<height"))
		return null
	v_half = Sem.div(v_width, 2)
	v_spring = Sem.sub(v_height, v_rise)
	v_points = [[Sem.neg(v_half), 0.0], [v_half, 0.0]]
	for tmp_2 in range(Sem.add(v_segments, 1)):
		v_j = tmp_2
		v_angle = Sem.div(Sem.mul(PI, v_j), v_segments)
		v_points.append([Sem.mul(v_half, cos(v_angle)), Sem.add(v_spring, Sem.mul(v_rise, sin(v_angle)))])
	return v_points

static func gen__outset(v_points, v_distance):
	var v_denominator = null
	var v_e0 = null
	var v_e1 = null
	var v_i = null
	var v_k = null
	var v_l0 = null
	var v_l1 = null
	var v_n0 = null
	var v_n1 = null
	var v_nx = null
	var v_nz = null
	var v_px = null
	var v_pz = null
	var v_result = null
	var v_x = null
	var v_z = null
	v_result = []
	for tmp_3 in Sem.py_enumerate(v_points):
		var tmp_4 = tmp_3
		v_i = tmp_4[0]
		var tmp_5 = tmp_4[1]
		v_x = tmp_5[0]
		v_z = tmp_5[1]
		var tmp_6 = v_points[Sem.mod(Sem.sub(v_i, 1), Sem.py_len(v_points))]
		v_px = tmp_6[0]
		v_pz = tmp_6[1]
		var tmp_7 = v_points[Sem.mod(Sem.add(v_i, 1), Sem.py_len(v_points))]
		v_nx = tmp_7[0]
		v_nz = tmp_7[1]
		v_e0 = [Sem.sub(v_x, v_px), Sem.sub(v_z, v_pz)]
		v_e1 = [Sem.sub(v_nx, v_x), Sem.sub(v_nz, v_z)]
		var tmp_8 = [Sem.hypot.callv(v_e0), Sem.hypot.callv(v_e1)]
		v_l0 = tmp_8[0]
		v_l1 = tmp_8[1]
		if Sem.truth(((Sem.py_min(v_l0, v_l1) < 1e-09))):
			push_error(str("Repeated contour vertex"))
			return null
		v_n0 = [Sem.div(v_e0[1], v_l0), Sem.div(Sem.neg(v_e0[0]), v_l0)]
		v_n1 = [Sem.div(v_e1[1], v_l1), Sem.div(Sem.neg(v_e1[0]), v_l1)]
		v_denominator = Sem.add(Sem.add(1, Sem.mul(v_n0[0], v_n1[0])), Sem.mul(v_n0[1], v_n1[1]))
		if Sem.truth(((v_denominator < 1e-05))):
			push_error(str("Contour has an excessively sharp corner"))
			return null
		v_k = Sem.div(v_distance, v_denominator)
		v_result.append([Sem.add(v_x, Sem.mul(v_k, Sem.add(v_n0[0], v_n1[0]))), Sem.add(v_z, Sem.mul(v_k, Sem.add(v_n0[1], v_n1[1])))])
	return v_result

static func gen__frame_band(v_name, v_inner, v_outer, v_front, v_back, v_mat, v_parent, v_bevel = 0.006):
	var v_faces = null
	var v_i = null
	var v_j = null
	var v_n = null
	var v_vertices = null
	var v_x = null
	var v_z = null
	v_n = Sem.py_len(v_inner)
	if Sem.truth(((v_n != Sem.py_len(v_outer)))):
		push_error(str("Frame contours require matching samples"))
		return null
	v_vertices = Sem.add(Sem.add(Sem.add(Sem.map_array(v_outer, func(tmp_9): var tmp_10 = tmp_9[0]; var tmp_11 = tmp_9[1]; return [tmp_10, v_front, tmp_11]), Sem.map_array(v_outer, func(tmp_12): var tmp_13 = tmp_12[0]; var tmp_14 = tmp_12[1]; return [tmp_13, v_back, tmp_14])), Sem.map_array(v_inner, func(tmp_15): var tmp_16 = tmp_15[0]; var tmp_17 = tmp_15[1]; return [tmp_16, v_front, tmp_17])), Sem.map_array(v_inner, func(tmp_18): var tmp_19 = tmp_18[0]; var tmp_20 = tmp_18[1]; return [tmp_19, v_back, tmp_20]))
	v_faces = []
	for tmp_21 in range(v_n):
		v_i = tmp_21
		v_j = Sem.mod(Sem.add(v_i, 1), v_n)
		v_faces = Sem.add(v_faces, [[v_i, v_j, Sem.add(Sem.mul(2, v_n), v_j), Sem.add(Sem.mul(2, v_n), v_i)], [Sem.add(v_n, v_j), Sem.add(v_n, v_i), Sem.add(Sem.mul(3, v_n), v_i), Sem.add(Sem.mul(3, v_n), v_j)], [v_i, Sem.add(v_n, v_i), Sem.add(v_n, v_j), v_j], [Sem.add(Sem.mul(2, v_n), v_i), Sem.add(Sem.mul(2, v_n), v_j), Sem.add(Sem.mul(3, v_n), v_j), Sem.add(Sem.mul(3, v_n), v_i)]])
	return Geo.gen_mesh(v_name, v_vertices, v_faces, v_mat, v_parent, v_bevel)

static func gen_arched_window(v_name, v_mats, v_width = 1.4, v_height = 3.0, v_rise = null, v_cols = 4, v_rows = 5, v_parent = null, v_segments = 10, v_frame_width = 0.12, v_glass = true):
	var v_angle = null
	var v_bar = null
	var v_depth = null
	var v_i = null
	var v_j = null
	var v_outside = null
	var v_pane = null
	var v_points = null
	var v_polygon = null
	var v_root = null
	var v_spring = null
	var v_x = null
	var v_y = null
	var v_z = null
	v_points = gen_arch_points(v_width, v_height, v_rise, v_segments)
	v_rise = (Sem.div(v_width, 2) if Sem.truth(((v_rise == null))) else float(v_rise))
	v_spring = Sem.sub(v_height, v_rise)
	var tmp_22 = [Sem.py_max(1, int(v_cols)), Sem.py_max(1, int(v_rows))]
	v_cols = tmp_22[0]
	v_rows = tmp_22[1]
	v_root = Geo.gen_group(v_name, [0, 0, 0], 0, v_parent)
	v_root["kind"] = "arched_window"
	v_root["clear_width"] = v_width
	v_root["clear_height"] = v_height
	v_root["arch_rise"] = v_rise
	v_root["arc_segments"] = int(v_segments)
	v_frame_width = Sem.py_min(float(v_frame_width), Sem.mul(v_width, 0.22))
	v_outside = gen__outset(v_points, v_frame_width)
	gen__frame_band(Sem.add(v_name, "_Deep_frame"), v_points, v_outside, Sem.neg(0.11), 0.095, v_mats["wood_dark"], v_root, 0.008)
	gen__frame_band(Sem.add(v_name, "_Raised_moulding"), gen__outset(v_points, Sem.mul(v_frame_width, 0.68)), gen__outset(v_points, Sem.add(v_frame_width, 0.025)), Sem.neg(0.155), Sem.neg(0.095), v_mats["wood"], v_root, 0.006)
	gen__frame_band(Sem.add(v_name, "_Inner_bead"), v_points, gen__outset(v_points, 0.024), Sem.neg(0.145), Sem.neg(0.1), v_mats["wood_light"], v_root, 0.004)
	if Sem.truth(v_glass):
		v_pane = Geo.gen_mesh(Sem.add(v_name, "_Glass"), Sem.map_array(v_points, func(tmp_23): var tmp_24 = tmp_23[0]; var tmp_25 = tmp_23[1]; return [tmp_24, 0.035, tmp_25]), [Sem.py_tuple(range(Sem.py_len(v_points)))], v_mats.get("glass", v_mats["cream"]), v_root, 0)
		if Sem.truth(((v_pane.data.polygons[0].normal.y > 0))):
			for tmp_26 in v_pane.data.polygons:
				v_polygon = tmp_26
				v_polygon.flip()
			v_pane.data.merge()
	v_bar = Sem.py_min(0.035, Sem.div(v_width, Sem.mul(v_cols, 11)))
	v_depth = 0.068
	v_y = Sem.neg(0.065)
	for tmp_27 in range(1, v_cols):
		v_i = tmp_27
		v_x = Sem.add(Sem.div(Sem.neg(v_width), 2), Sem.div(Sem.mul(v_width, v_i), v_cols))
		Geo.gen_box(Sem.add(Sem.add(v_name, "_Mullion_"), str(v_i)), [v_x, v_y, Sem.div(v_spring, 2)], [v_bar, v_depth, v_spring], v_mats["wood"], 0.004, v_root)
	for tmp_28 in range(1, Sem.add(v_rows, 1)):
		v_j = tmp_28
		v_z = Sem.div(Sem.mul(v_spring, v_j), v_rows)
		Geo.gen_box(Sem.add(Sem.add(v_name, "_Transom_"), str(v_j)), [0, Sem.sub(v_y, 0.002), v_z], [v_width, Sem.add(v_depth, 0.008), v_bar], v_mats["wood"], 0.004, v_root)
	for tmp_29 in range(1, Sem.py_max(3, Sem.add(v_cols, 1))):
		v_j = tmp_29
		v_angle = Sem.div(Sem.mul(PI, v_j), Sem.py_max(3, Sem.add(v_cols, 1)))
		Geo.gen_beam(Sem.add(Sem.add(v_name, "_Fan_ray_"), str(v_j)), [0, v_y, v_spring], [Sem.mul(Sem.div(v_width, 2), cos(v_angle)), v_y, Sem.add(v_spring, Sem.mul(v_rise, sin(v_angle)))], Sem.mul(v_bar, 0.84), v_depth, v_mats["wood_light"], v_root, 0.003)
	Geo.gen_box(Sem.add(v_name, "_Sill"), [0, Sem.neg(0.115), Sem.neg(0.075)], [Sem.add(Sem.add(v_width, Sem.mul(2, v_frame_width)), 0.18), 0.39, 0.12], v_mats["wood_light"], 0.016, v_root)
	Geo.gen_box(Sem.add(v_name, "_Sill_apron"), [0, Sem.neg(0.055), Sem.neg(0.17)], [Sem.sub(Sem.add(v_width, Sem.mul(2, v_frame_width)), 0.02), 0.18, 0.1], v_mats["wood"], 0.01, v_root)
	return v_root

static func gen__raised_panel(v_name, v_mats, v_x, v_z, v_width, v_height, v_parent):
	var v_moulding = null
	var v_sign = null
	v_moulding = Sem.py_min(0.034, Sem.mul(v_width, 0.11), Sem.mul(v_height, 0.11))
	Geo.gen_box(Sem.add(v_name, "_Field"), [v_x, Sem.neg(0.058), v_z], [v_width, 0.026, v_height], v_mats["wood"], 0.007, v_parent)
	for tmp_30 in [Sem.neg(1), 1]:
		v_sign = tmp_30
		Geo.gen_box(Sem.add(Sem.add(v_name, "_Upright_"), str(v_sign)), [Sem.add(v_x, Sem.div(Sem.mul(v_sign, Sem.sub(v_width, v_moulding)), 2)), Sem.neg(0.084), v_z], [v_moulding, 0.035, v_height], v_mats["wood_light"], 0.004, v_parent)
		Geo.gen_box(Sem.add(Sem.add(v_name, "_Rail_"), str(v_sign)), [v_x, Sem.neg(0.084), Sem.add(v_z, Sem.div(Sem.mul(v_sign, Sem.sub(v_height, v_moulding)), 2))], [Sem.py_max(0.005, Sem.sub(v_width, Sem.mul(2, v_moulding))), 0.035, v_moulding], v_mats["wood_light"], 0.004, v_parent)

static func gen_closed_door(v_name, v_mats, v_width = 1.25, v_height = 2.65, v_double = false, v_transom = false, v_parent = null):
	var v_a = null
	var v_b = null
	var v_cell_w = null
	var v_count = null
	var v_cx = null
	var v_direction = null
	var v_edge = null
	var v_fw = null
	var v_gap = null
	var v_handle_x = null
	var v_handle_z = null
	var v_hinge_x = null
	var v_i = null
	var v_index = null
	var v_inner_w = null
	var v_knob = null
	var v_leaf = null
	var v_leaf_h = null
	var v_leaf_w = null
	var v_left_hinged = null
	var v_level = null
	var v_lower_bottom = null
	var v_lower_top = null
	var v_n = null
	var v_number = null
	var v_rail = null
	var v_root = null
	var v_side = null
	var v_transom_h = null
	var v_upper_bottom = null
	var v_upper_top = null
	var v_z = null
	var v_z0 = null
	if Sem.truth(Sem.either_lazy(((v_width <= 0.35)), func(): return ((v_height <= 0.8)))):
		push_error(str("Door opening is too small"))
		return null
	v_root = Geo.gen_group(v_name, [0, 0, 0], 0, v_parent)
	v_root["kind"] = ("closed_double_door" if Sem.truth(v_double) else "closed_door")
	var tmp_31 = [v_width, v_height]
	v_root["clear_width"] = tmp_31[0]
	v_root["clear_height"] = tmp_31[1]
	v_root["closed_angle"] = 0.0
	v_fw = Sem.py_min(0.14, Sem.mul(v_width, 0.11))
	for tmp_32 in [Sem.neg(1), 1]:
		v_side = tmp_32
		Geo.gen_box(Sem.add(Sem.add(v_name, "_Jamb_"), str(v_side)), [Sem.div(Sem.mul(v_side, Sem.add(v_width, v_fw)), 2), Sem.neg(0.04), Sem.div(v_height, 2)], [v_fw, 0.25, v_height], v_mats["wood_dark"], 0.012, v_root)
		Geo.gen_box(Sem.add(Sem.add(v_name, "_Jamb_moulding_"), str(v_side)), [Sem.div(Sem.mul(v_side, Sem.add(v_width, v_fw)), 2), Sem.neg(0.18), Sem.div(v_height, 2)], [Sem.mul(v_fw, 0.76), 0.055, Sem.add(v_height, 0.025)], v_mats["wood_light"], 0.008, v_root)
	Geo.gen_box(Sem.add(v_name, "_Lintel"), [0, Sem.neg(0.04), Sem.add(v_height, Sem.div(v_fw, 2))], [Sem.add(v_width, Sem.mul(2, v_fw)), 0.27, v_fw], v_mats["wood_dark"], 0.012, v_root)
	Geo.gen_box(Sem.add(v_name, "_Cornice"), [0, Sem.neg(0.095), Sem.add(Sem.add(v_height, v_fw), 0.05)], [Sem.add(Sem.add(v_width, Sem.mul(2, v_fw)), 0.15), 0.36, 0.1], v_mats["wood_light"], 0.012, v_root)
	v_transom_h = (Sem.py_min(0.5, Sem.mul(v_height, 0.18)) if Sem.truth(v_transom) else 0.0)
	v_leaf_h = Sem.sub(Sem.sub(Sem.sub(v_height, v_transom_h), (0.075 if Sem.truth(v_transom) else 0)), 0.012)
	if Sem.truth(v_transom):
		v_z0 = Sem.add(v_leaf_h, 0.075)
		Geo.gen_box(Sem.add(v_name, "_Fixed_transom_back"), [0, 0.035, Sem.div(Sem.add(v_z0, v_height), 2)], [v_width, 0.055, Sem.sub(v_height, v_z0)], v_mats["wood_dark"], 0.002, v_root)
		v_n = Sem.py_max(3, Sem.py_round(Sem.div(v_width, 0.23)))
		v_gap = 0.032
		v_cell_w = Sem.div(Sem.sub(v_width, Sem.mul(Sem.add(v_n, 1), v_gap)), v_n)
		for tmp_33 in range(v_n):
			v_i = tmp_33
			v_cx = Sem.add(Sem.add(Sem.add(Sem.div(Sem.neg(v_width), 2), v_gap), Sem.div(v_cell_w, 2)), Sem.mul(v_i, Sem.add(v_cell_w, v_gap)))
			Geo.gen_box(Sem.add(Sem.add(v_name, "_Transom_inset_"), str(v_i)), [v_cx, Sem.neg(0.007), Sem.div(Sem.add(v_z0, v_height), 2)], [v_cell_w, 0.018, Sem.py_max(0.02, Sem.sub(Sem.sub(v_height, v_z0), 0.07))], v_mats["cream"], 0.003, v_root)
		Geo.gen_box(Sem.add(v_name, "_Transom_crossrail"), [0, Sem.neg(0.075), Sem.add(v_leaf_h, 0.038)], [Sem.add(v_width, 0.02), 0.16, 0.075], v_mats["wood_light"], 0.008, v_root)
	v_count = (2 if Sem.truth(v_double) else 1)
	v_gap = 0.009
	v_leaf_w = Sem.div(Sem.sub(v_width, Sem.mul(Sem.add(v_count, 1), v_gap)), v_count)
	for tmp_34 in range(v_count):
		v_number = tmp_34
		v_left_hinged = ((v_number == 0))
		v_direction = (1 if Sem.truth(v_left_hinged) else Sem.neg(1))
		v_hinge_x = (Sem.add(Sem.div(Sem.neg(v_width), 2), v_gap) if Sem.truth(v_left_hinged) else Sem.sub(Sem.div(v_width, 2), v_gap))
		v_leaf = Geo.gen_group(Sem.add(v_name, ("_Left_hinge" if Sem.truth(v_left_hinged) else "_Right_hinge")), [v_hinge_x, 0, 0.006], 0, v_root)
		v_leaf["kind"] = "door_hinge"
		v_leaf["open_angle_degrees"] = Sem.mul(Sem.neg(95), v_direction)
		v_cx = Sem.div(Sem.mul(v_direction, v_leaf_w), 2)
		Geo.gen_box(Sem.add(Sem.add(v_name, "_Leaf_"), str(v_number)), [v_cx, 0.005, Sem.div(v_leaf_h, 2)], [v_leaf_w, 0.11, v_leaf_h], v_mats["wood_dark"], 0.008, v_leaf)
		v_rail = Sem.py_min(0.095, Sem.mul(v_leaf_w, 0.13))
		for tmp_35 in [Sem.neg(1), 1]:
			v_edge = tmp_35
			Geo.gen_box(Sem.add(Sem.add(Sem.add(Sem.add(v_name, "_Leaf_stile_"), str(v_number)), "_"), str(v_edge)), [Sem.add(v_cx, Sem.div(Sem.mul(v_edge, Sem.sub(v_leaf_w, v_rail)), 2)), Sem.neg(0.073), Sem.div(v_leaf_h, 2)], [v_rail, 0.06, v_leaf_h], v_mats["wood"], 0.007, v_leaf)
		for tmp_36 in [Sem.div(v_rail, 2), Sem.mul(v_leaf_h, 0.34), Sem.sub(v_leaf_h, Sem.div(v_rail, 2))]:
			v_z = tmp_36
			Geo.gen_box(Sem.add(Sem.add(Sem.add(Sem.add(v_name, "_Leaf_crossrail_"), str(v_number)), "_"), str(Sem.py_round(v_z, 3))), [v_cx, Sem.neg(0.073), v_z], [Sem.sub(v_leaf_w, Sem.mul(2, v_rail)), 0.06, v_rail], v_mats["wood"], 0.007, v_leaf)
		v_inner_w = Sem.sub(Sem.sub(v_leaf_w, Sem.mul(2, v_rail)), 0.025)
		var tmp_37 = [Sem.add(v_rail, 0.02), Sem.sub(Sem.sub(Sem.mul(v_leaf_h, 0.34), Sem.div(v_rail, 2)), 0.02)]
		v_lower_bottom = tmp_37[0]
		v_lower_top = tmp_37[1]
		var tmp_38 = [Sem.add(Sem.add(Sem.mul(v_leaf_h, 0.34), Sem.div(v_rail, 2)), 0.02), Sem.sub(Sem.sub(v_leaf_h, v_rail), 0.02)]
		v_upper_bottom = tmp_38[0]
		v_upper_top = tmp_38[1]
		for tmp_39 in Sem.py_enumerate([[v_lower_bottom, v_lower_top], [v_upper_bottom, v_upper_top]]):
			var tmp_40 = tmp_39
			v_index = tmp_40[0]
			var tmp_41 = tmp_40[1]
			v_a = tmp_41[0]
			v_b = tmp_41[1]
			gen__raised_panel(Sem.add(Sem.add(Sem.add(Sem.add(v_name, "_Panel_"), str(v_number)), "_"), str(v_index)), v_mats, v_cx, Sem.div(Sem.add(v_a, v_b), 2), v_inner_w, Sem.sub(v_b, v_a), v_leaf)
		v_handle_x = Sem.mul(v_direction, Sem.sub(v_leaf_w, Sem.mul(v_rail, 0.7)))
		v_handle_z = Sem.py_min(1.03, Sem.mul(v_leaf_h, 0.47))
		Geo.gen_box(Sem.add(Sem.add(v_name, "_Handle_plate_"), str(v_number)), [v_handle_x, Sem.neg(0.119), v_handle_z], [0.048, 0.025, 0.19], v_mats["gold"], 0.008, v_leaf)
		v_knob = Geo.gen_cylinder(Sem.add(Sem.add(v_name, "_Handle_neck_"), str(v_number)), [v_handle_x, Sem.neg(0.153), Sem.add(v_handle_z, 0.025)], 0.022, 0.055, v_mats["gold"], 8, v_leaf)
		v_knob.rotation_euler[0] = Sem.div(PI, 2)
		Geo.gen_beam(Sem.add(Sem.add(v_name, "_Handle_lever_"), str(v_number)), [v_handle_x, Sem.neg(0.19), Sem.add(v_handle_z, 0.025)], [Sem.sub(v_handle_x, Sem.mul(v_direction, 0.105)), Sem.neg(0.19), Sem.add(v_handle_z, 0.025)], 0.022, 0.025, v_mats["gold"], v_leaf, 0.005)
		for tmp_42 in [0.22, 0.78]:
			v_level = tmp_42
			Geo.gen_cylinder(Sem.add(Sem.add(Sem.add(Sem.add(v_name, "_Hinge_barrel_"), str(v_number)), "_"), str(v_level)), [0, Sem.neg(0.075), Sem.mul(v_leaf_h, v_level)], 0.018, 0.13, v_mats["gold"], 8, v_leaf)
		Geo.gen_group(Sem.add(Sem.add(v_name, "_Handle_anchor_"), str(v_number)), [v_handle_x, Sem.neg(0.2), v_handle_z], 0, v_leaf)
	Geo.gen_group(Sem.add(v_name, "_Stand_front"), [0, Sem.neg(0.65), 0], 0, v_root)
	Geo.gen_group(Sem.add(v_name, "_Passage_center"), [0, 0, 0], 0, v_root)
	return v_root

