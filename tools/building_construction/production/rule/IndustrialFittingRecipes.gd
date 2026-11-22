@tool
extends RefCounted

const Sem = preload("res://tools/building_construction/BuildingConstruction/Shared/RecipeSemantics.gd")
const Geo = preload("res://tools/building_construction/BuildingConstruction/Shared/RecipeGeometry.gd")

static func gen_ring(v_name, v_outer, v_inner, v_depth, v_mat, v_parent = null, v_sides = 12):
	var v_fs = null
	var v_i = null
	var v_j = null
	var v_radius = null
	var v_vs = null
	var v_z = null
	if Sem.truth(Sem.either_lazy(not Sem.truth(((0 < v_inner) and (v_inner < v_outer))), func(): return ((v_depth <= 0)))):
		push_error(str("Invalid annular dimensions"))
		return null
	v_vs = []
	for tmp_2 in [[v_outer, Sem.div(Sem.neg(v_depth), 2)], [v_outer, Sem.div(v_depth, 2)], [v_inner, Sem.div(Sem.neg(v_depth), 2)], [v_inner, Sem.div(v_depth, 2)]]:
		var tmp_3 = tmp_2
		v_radius = tmp_3[0]
		v_z = tmp_3[1]
		v_vs.append_array(Sem.map_array(range(v_sides), func(tmp_4): var tmp_5 = tmp_4; return [Sem.mul(v_radius, cos(Sem.div(Sem.mul(Sem.mul(2, PI), tmp_5), v_sides))), Sem.mul(v_radius, sin(Sem.div(Sem.mul(Sem.mul(2, PI), tmp_5), v_sides))), v_z]))
	v_fs = []
	for tmp_6 in range(v_sides):
		v_i = tmp_6
		v_j = Sem.mod(Sem.add(v_i, 1), v_sides)
		v_fs.append_array([[v_i, v_j, Sem.add(v_sides, v_j), Sem.add(v_sides, v_i)], [Sem.add(Sem.mul(2, v_sides), v_j), Sem.add(Sem.mul(2, v_sides), v_i), Sem.add(Sem.mul(3, v_sides), v_i), Sem.add(Sem.mul(3, v_sides), v_j)], [v_i, Sem.add(Sem.mul(2, v_sides), v_i), Sem.add(Sem.mul(2, v_sides), v_j), v_j], [Sem.add(v_sides, v_j), Sem.add(Sem.mul(3, v_sides), v_j), Sem.add(Sem.mul(3, v_sides), v_i), Sem.add(v_sides, v_i)]])
	return Geo.gen_mesh(v_name, v_vs, v_fs, v_mat, v_parent, 0)

static func gen_flange(v_name, v_mats, v_radius = 0.12, v_parent = null, v_bolts = 6):
	var v_a = null
	var v_i = null
	var v_m = null
	var v_root = null
	v_m = Geo.industrial_palette(v_mats)
	v_root = Geo.gen_group(v_name, [0, 0, 0], 0, v_parent)
	gen_ring(Sem.add(v_name, "_Flange"), Sem.mul(v_radius, 1.65), Sem.mul(v_radius, 0.93), Sem.mul(v_radius, 0.52), v_m["gold"], v_root, 12)
	for tmp_7 in range(v_bolts):
		v_i = tmp_7
		v_a = Sem.div(Sem.mul(Sem.mul(2, PI), v_i), v_bolts)
		Geo.gen_cylinder(Sem.add(v_name, Sem.mod("_Bolt_%02d", v_i)), [Sem.mul(Sem.mul(v_radius, 1.3), cos(v_a)), Sem.mul(Sem.mul(v_radius, 1.3), sin(v_a)), Sem.mul(v_radius, 0.32)], Sem.mul(v_radius, 0.12), Sem.mul(v_radius, 0.22), v_m["iron"], 6, v_root)
	return v_root
