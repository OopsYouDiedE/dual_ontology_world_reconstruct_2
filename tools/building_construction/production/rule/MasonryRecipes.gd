@tool
extends RefCounted

const Sem = preload("res://tools/building_construction/BuildingConstruction/Shared/RecipeSemantics.gd")
const Geo = preload("res://tools/building_construction/BuildingConstruction/Shared/RecipeGeometry.gd")

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

static func gen_material_set(v_mats):
	var v_args = null
	var v_colors = null
	var v_key = null
	var v_name = null
	var v_result = null
	return Geo.industrial_palette(v_mats)

static func gen_masonry_joints(v_name, v_mats, v_length, v_height, v_openings = [], v_brick_width = 1.08, v_row_height = 0.47, v_parent = null):
	var v_a = null
	var v_b = null
	var v_box_at = null
	var v_f = null
	var v_free_intervals = null
	var v_fs = null
	var v_hi = null
	var v_i = null
	var v_lo = null
	var v_m = null
	var v_new = null
	var v_o = null
	var v_root = null
	var v_row = null
	var v_rows = null
	var v_spans = null
	var v_start = null
	var v_vs = null
	var v_x = null
	var v_ys = null
	var v_z0 = null
	var v_z1 = null
	v_m = gen_material_set(v_mats)
	v_root = Geo.gen_group(v_name, [0, 0, 0], 0, v_parent)
	v_vs = []
	v_fs = []
	v_box_at = func(tmp_91, tmp_92, tmp_93, tmp_94):
		if Sem.truth(Sem.either_lazy(((Sem.sub(tmp_92, tmp_91) < 0.001)), func(): return ((Sem.sub(tmp_94, tmp_93) < 0.001)))):
			return null
		v_start = Sem.py_len(v_vs)
		v_ys = [Sem.neg(0.018), Sem.neg(0.006)]
		v_vs.append_array([[tmp_91, v_ys[0], tmp_93], [tmp_92, v_ys[0], tmp_93], [tmp_92, v_ys[1], tmp_93], [tmp_91, v_ys[1], tmp_93], [tmp_91, v_ys[0], tmp_94], [tmp_92, v_ys[0], tmp_94], [tmp_92, v_ys[1], tmp_94], [tmp_91, v_ys[1], tmp_94]])
		v_fs.append_array(Sem.map_array([[3, 2, 1, 0], [0, 1, 5, 4], [1, 2, 6, 5], [2, 3, 7, 6], [3, 0, 4, 7], [4, 5, 6, 7]], func(tmp_95): var tmp_96 = tmp_95; return Sem.py_tuple(Sem.map_array(tmp_96, func(tmp_97): var tmp_98 = tmp_97; return Sem.add(v_start, tmp_98)))))
	v_free_intervals = func(tmp_99):
		v_spans = [[0, v_length]]
		for tmp_100 in v_openings:
			v_o = tmp_100
			if Sem.truth(((Sem.sub(v_o.get("bottom", 0), 0.08) <= tmp_99) and (tmp_99 <= Sem.add(Sem.add(v_o.get("bottom", 0), v_o["height"]), 0.08)))):
				v_a = Sem.sub(Sem.sub(v_o["center"], Sem.div(v_o["width"], 2)), 0.12)
				v_b = Sem.add(Sem.add(v_o["center"], Sem.div(v_o["width"], 2)), 0.12)
				v_new = []
				for tmp_101 in v_spans:
					var tmp_102 = tmp_101
					v_lo = tmp_102[0]
					v_hi = tmp_102[1]
					if Sem.truth(Sem.either_lazy(((v_b <= v_lo)), func(): return ((v_a >= v_hi)))):
						v_new.append([v_lo, v_hi])
					else:
						if Sem.truth(((v_a > v_lo))):
							v_new.append([v_lo, Sem.py_min(v_a, v_hi)])
						if Sem.truth(((v_b < v_hi))):
							v_new.append([Sem.py_max(v_b, v_lo), v_hi])
				v_spans = v_new
		return v_spans
	v_rows = Sem.py_max(1, ceili(Sem.div(v_height, v_row_height)))
	for tmp_103 in range(v_rows):
		v_row = tmp_103
		v_z0 = Sem.mul(v_row, v_row_height)
		v_z1 = Sem.py_min(v_height, Sem.add(v_z0, v_row_height))
		if Sem.truth(((v_row > 0))):
			for tmp_104 in v_free_intervals.call(v_z0):
				var tmp_105 = tmp_104
				v_a = tmp_105[0]
				v_b = tmp_105[1]
				v_box_at.call(v_a, v_b, Sem.sub(v_z0, 0.006), Sem.add(v_z0, 0.006))
		v_x = Sem.mul(Sem.mul(Sem.mod(v_row, 2), v_brick_width), 0.5)
		while Sem.truth(((v_x < v_length))):
			if Sem.truth(Sem.both_lazy(((v_x > 0.08)), func(): return Sem.py_all(Sem.map_array(v_openings, func(tmp_106): var tmp_107 = tmp_106; return not Sem.truth(Sem.both_lazy(((Sem.sub(Sem.sub(tmp_107["center"], Sem.div(tmp_107["width"], 2)), 0.12) < v_x) and (v_x < Sem.add(Sem.add(tmp_107["center"], Sem.div(tmp_107["width"], 2)), 0.12))), func(): return Sem.both_lazy(((v_z0 < Sem.add(Sem.add(tmp_107.get("bottom", 0), tmp_107["height"]), 0.08))), func(): return ((v_z1 > Sem.sub(tmp_107.get("bottom", 0), 0.08)))))))))):
				v_box_at.call(Sem.sub(v_x, 0.006), Sem.add(v_x, 0.006), Sem.add(v_z0, 0.006), Sem.sub(v_z1, 0.006))
			v_x = Sem.add(v_x, v_brick_width)
	if Sem.truth(v_vs):
		Geo.gen_mesh(Sem.add(v_name, "_Real_joint_mesh"), v_vs, v_fs, v_m["masonry_dark"], v_root, 0)
	return v_root
