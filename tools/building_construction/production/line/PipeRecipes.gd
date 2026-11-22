@tool
extends RefCounted

const Sem = preload("res://tools/building_construction/BuildingConstruction/Shared/RecipeSemantics.gd")
const Geo = preload("res://tools/building_construction/BuildingConstruction/Shared/RecipeGeometry.gd")
const Paths = preload("PathRecipes.gd")
const Fittings = preload("../rule/IndustrialFittingRecipes.gd")

static func gen__rounded_nodes(v_nodes, v_radius):
	var v_a = null
	var v_b = null
	var v_c = null
	var v_d = null
	var v_incoming = null
	var v_out = null
	var v_outgoing = null
	var v_p = null
	var v_pts = null
	var v_q0 = null
	var v_q3 = null
	if Sem.truth(Sem.py_any(Sem.map_array(v_nodes, func(tmp_8): var tmp_9 = tmp_8; return (tmp_9 is Dictionary)))):
		return Paths.gen_sample_path(v_nodes, 5, false)
	v_pts = Sem.map_array(Paths.gen_clean_polyline(v_nodes, false), func(tmp_10): var tmp_11 = tmp_10; return Sem.vector(tmp_11))
	if v_pts.size() < 2: return []
	v_out = [Sem.py_tuple(v_pts[0])]
	for tmp_12 in Sem.py_zip(v_pts, Sem.slice_array(v_pts, 1, null, null), Sem.slice_array(v_pts, 2, null, null)):
		var tmp_13 = tmp_12
		v_a = tmp_13[0]
		v_b = tmp_13[1]
		v_c = tmp_13[2]
		var tmp_14 = [Sem.sub(v_b, v_a).normalized(), Sem.sub(v_c, v_b).normalized()]
		v_incoming = tmp_14[0]
		v_outgoing = tmp_14[1]
		if Sem.truth(((v_incoming.dot(v_outgoing) > 0.995))):
			v_out.append(Sem.py_tuple(v_b))
			continue
		v_d = Sem.py_min(v_radius, Sem.mul(Sem.sub(v_b, v_a).length(), 0.35), Sem.mul(Sem.sub(v_c, v_b).length(), 0.35))
		var tmp_15 = [Sem.sub(v_b, Sem.mul(v_incoming, v_d)), Sem.add(v_b, Sem.mul(v_outgoing, v_d))]
		v_q0 = tmp_15[0]
		v_q3 = tmp_15[1]
		v_out.append_array(Paths.gen_sample_cubic_bezier(v_q0, Sem.add(v_q0, Sem.mul(Sem.mul(v_incoming, v_d), 0.552)), Sem.sub(v_q3, Sem.mul(Sem.mul(v_outgoing, v_d), 0.552)), v_q3, 5))
	v_out.append(Sem.py_tuple(v_pts[Sem.neg(1)]))
	return Paths.gen_clean_polyline(v_out, false)

## Sample in recipe coordinates (Z up). Mesh and mating ports share this path.
static func centerline(nodes: Array, radius: float) -> Array:
	if radius <= 0.0 or nodes.size() < 2: return []
	return gen__rounded_nodes(nodes, radius * 2.8)

static func gen_pipe_run(v_name, v_mats, v_nodes, v_radius = 0.09, v_sides = 8, v_collars = true, v_parent = null):
	var v_a = null
	var v_axis = null
	var v_bitangent = null
	var v_f = null
	var v_fs = null
	var v_i = null
	var v_j = null
	var v_k = null
	var v_m = null
	var v_normal = null
	var v_p = null
	var v_pos = null
	var v_projected = null
	var v_pts = null
	var v_ref = null
	var v_root = null
	var v_tangent = null
	var v_vs = null
	v_m = Geo.industrial_palette(v_mats)
	v_root = Geo.gen_group(v_name, [0, 0, 0], 0, v_parent)
	v_pts = Sem.map_array(centerline(v_nodes, v_radius), func(tmp_16): var tmp_17 = tmp_16; return Sem.vector(tmp_17))
	if v_pts.size() < 2 or v_radius <= 0.0 or v_sides < 3: return v_root
	v_vs = []
	v_normal = null
	for tmp_18 in Sem.py_enumerate(v_pts):
		var tmp_19 = tmp_18
		v_i = tmp_19[0]
		v_p = tmp_19[1]
		v_tangent = Sem.sub(v_pts[Sem.py_min(Sem.add(v_i, 1), Sem.sub(Sem.py_len(v_pts), 1))], v_pts[Sem.py_max(Sem.sub(v_i, 1), 0)]).normalized()
		if Sem.truth(((v_normal == null))):
			v_ref = (Sem.vector([0, 0, 1]) if Sem.truth(((abs(v_tangent.z) < 0.9))) else Sem.vector([1, 0, 0]))
			v_normal = v_tangent.cross(v_ref).normalized()
		else:
			v_projected = Sem.sub(v_normal, Sem.mul(v_tangent, v_normal.dot(v_tangent)))
			if Sem.truth(((v_projected.length() < 1e-06))):
				v_projected = v_tangent.cross(Sem.vector([0, 1, 0]))
			v_normal = v_projected.normalized()
		v_bitangent = v_tangent.cross(v_normal).normalized()
		for tmp_20 in range(v_sides):
			v_j = tmp_20
			v_a = Sem.div(Sem.mul(Sem.mul(2, PI), v_j), v_sides)
			v_vs.append(Sem.py_tuple(Sem.add(v_p, Sem.mul(v_radius, Sem.add(Sem.mul(v_normal, cos(v_a)), Sem.mul(v_bitangent, sin(v_a)))))))
	v_fs = [Sem.py_tuple(Sem.py_reversed(range(v_sides)))]
	for tmp_21 in range(Sem.sub(Sem.py_len(v_pts), 1)):
		v_i = tmp_21
		for tmp_22 in range(v_sides):
			v_j = tmp_22
			v_k = Sem.mod(Sem.add(v_j, 1), v_sides)
			v_fs.append([Sem.add(Sem.mul(v_i, v_sides), v_j), Sem.add(Sem.mul(v_i, v_sides), v_k), Sem.add(Sem.mul(Sem.add(v_i, 1), v_sides), v_k), Sem.add(Sem.mul(Sem.add(v_i, 1), v_sides), v_j)])
	v_fs.append(Sem.py_tuple(range(Sem.mul(Sem.sub(Sem.py_len(v_pts), 1), v_sides), Sem.mul(Sem.py_len(v_pts), v_sides))))
	Geo.gen_mesh(Sem.add(v_name, "_Swept_pipe"), v_vs, v_fs, v_m["copper"], v_root, 0)
	if Sem.truth(v_collars):
		for tmp_23 in Sem.py_enumerate([[v_pts[0], Sem.sub(v_pts[1], v_pts[0])], [v_pts[Sem.neg(1)], Sem.sub(v_pts[Sem.neg(1)], v_pts[Sem.neg(2)])]]):
			var tmp_24 = tmp_23
			v_i = tmp_24[0]
			var tmp_25 = tmp_24[1]
			v_pos = tmp_25[0]
			v_axis = tmp_25[1]
			v_f = Fittings.gen_flange(Sem.add(v_name, Sem.mod("_End_%d", v_i)), v_m, v_radius, v_root, 6)
			v_f.location = v_pos
			v_f.rotation_euler = Sem.track_euler(v_axis)
	v_root["generator"] = "sampled_octagonal_pipe_v1"
	v_root["pipe_radius"] = v_radius
	return v_root
