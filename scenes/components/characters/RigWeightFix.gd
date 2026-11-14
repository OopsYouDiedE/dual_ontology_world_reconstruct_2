extends RefCounted
## 蒙皮权重修正（Mixamo 人物 GLB，Tripo 自动绑定后遗留的问题）。
##
## 诊断（tools/test/skin_report3.gd，骨架静止姿态空间）：
##   · model_16 苏泠：6 个腿部顶点绑在对侧腿；9 个低于颈部的顶点仍被 Head 抓着；
##     长袍大腿区 167 个顶点中线附近几乎全绑在右大腿，走路时左腿迈步，袍片被右腿单边拖裂。
##   · 其余人物左右对称，但围裙 / 长袍正中的顶点同样是「整片跟随一条腿」，坐下时穿进大腿。
## 修正：
##   1. 腿链（UpLeg / Leg / Foot / ToeBase）顶点落在对侧：换成对侧骨骼。
##   2. 大腿区中线附近的衣料：左右大腿权重按顶点横向位置平滑分配（smoothstep），不再偏向一条腿。
##   3. 低于颈部的 Head 权重改给 Spine2（动画里 Spine2 = chest）。
## 结果按模型路径缓存为新的 ArrayMesh；材质、顶点、法线、UV 不变，只替换 BONES / WEIGHTS。

static var _mesh_cache: Dictionary = {}
static var report: Dictionary = {}   # path -> {leg_swapped, thigh_blended, head_moved, verts}


static func apply(model: Node3D, skel: Skeleton3D, path: String) -> bool:
	if skel == null: return false
	var meshes := skel.find_children("*", "MeshInstance3D", true, false)
	if meshes.is_empty(): return false
	var mi := meshes[0] as MeshInstance3D
	if mi.mesh == null or not mi.mesh is ArrayMesh: return false
	if _mesh_cache.has(path):
		mi.mesh = _mesh_cache[path]
		return true
	var fixed := _rebuild(model, skel, mi, path)
	if fixed == null: return false
	_mesh_cache[path] = fixed
	mi.mesh = fixed
	return true


static func _rel(n: Node, top: Node) -> Transform3D:
	var t := Transform3D.IDENTITY
	while n != null and n != top:
		t = (n as Node3D).transform * t
		n = n.get_parent()
	return t


static func _bone(skel: Skeleton3D, short_name: String) -> int:
	for candidate in ["mixamorig_" + short_name, "mixamorig:" + short_name, short_name]:
		var i := skel.find_bone(candidate)
		if i != -1: return i
	return -1


static func _rebuild(model: Node3D, skel: Skeleton3D, mi: MeshInstance3D, path: String) -> ArrayMesh:
	var hips_i := _bone(skel, "Hips")
	var lu_i := _bone(skel, "LeftUpLeg")
	var ru_i := _bone(skel, "RightUpLeg")
	var lk_i := _bone(skel, "LeftLeg")
	var neck_i := _bone(skel, "Neck")
	var chest_i := _bone(skel, "Spine2")
	var head_i := _bone(skel, "Head")
	if -1 in [hips_i, lu_i, ru_i, lk_i, neck_i, chest_i, head_i]: return null
	var am := mi.mesh as ArrayMesh
	var arrays := am.surface_get_arrays(0)
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var bones: PackedInt32Array = arrays[Mesh.ARRAY_BONES]
	var weights: PackedFloat32Array = arrays[Mesh.ARRAY_WEIGHTS]
	if bones.is_empty() or bones.size() != verts.size() * 4: return null

	# 骨架空间：横轴取「右大腿 → 左大腿」，不假设模型朝向（这批模型的横轴是 z）。
	var to_skel := _rel(skel, model).affine_inverse() * _rel(mi, model)
	var lu := skel.get_bone_global_rest(lu_i).origin
	var ru := skel.get_bone_global_rest(ru_i).origin
	var lat := (lu - ru).normalized()
	var mid := ((lu + ru) * 0.5).dot(lat)
	var half := (lu - ru).length() * 0.5
	var hips_y := skel.get_bone_global_rest(hips_i).origin.y
	var knee_y := skel.get_bone_global_rest(lk_i).origin.y
	var neck_y := skel.get_bone_global_rest(neck_i).origin.y

	# 腿链骨骼的左右互换表
	var swap := {}
	var is_left := {}
	for part in ["UpLeg", "Leg", "Foot", "ToeBase"]:
		var l := _bone(skel, "Left" + part)
		var r := _bone(skel, "Right" + part)
		if l != -1 and r != -1:
			swap[l] = r
			swap[r] = l
			is_left[l] = true

	var n_swap := 0
	var n_thigh := 0
	var n_head := 0
	for i in verts.size():
		var p := to_skel * verts[i]
		var side := p.dot(lat) - mid       # >0 左侧
		var acc := {}
		for k in 4:
			var wv := weights[i * 4 + k]
			if wv > 0.0: acc[bones[i * 4 + k]] = float(acc.get(bones[i * 4 + k], 0.0)) + wv
		var changed := false

		# 1) 腿链顶点落在对侧：换骨
		var dom := -1
		var dom_w := -1.0
		for b in acc:
			if acc[b] > dom_w:
				dom_w = acc[b]
				dom = b
		if swap.has(dom) and absf(side) > half * 0.2:
			var on_left_bone: bool = is_left.has(dom)
			if (on_left_bone and side < 0.0) or ((not on_left_bone) and side > 0.0):
				var moved := {}
				for b in acc:
					var nb: int = int(swap.get(b, b))
					moved[nb] = float(moved.get(nb, 0.0)) + float(acc[b])
				acc = moved
				n_swap += 1
				changed = true

		# 2) 大腿区中线附近：左右大腿权重按位置平滑分配
		if p.y <= hips_y + 0.02 and p.y >= knee_y and absf(side) < half * 2.2:
			var total := float(acc.get(lu_i, 0.0)) + float(acc.get(ru_i, 0.0))
			acc.erase(lu_i)
			acc.erase(ru_i)
			if total > 0.0:
				var t := smoothstep(-half * 1.3, half * 1.3, side)
				acc[lu_i] = total * t
				acc[ru_i] = total * (1.0 - t)
				n_thigh += 1
				changed = true

		# 3) 低于颈部的 Head 权重 → Spine2
		if acc.has(head_i) and p.y < neck_y - 0.01:
			acc[chest_i] = float(acc.get(chest_i, 0.0)) + float(acc[head_i])
			acc.erase(head_i)
			n_head += 1
			changed = true

		if not changed: continue
		var keys := acc.keys()
		keys.sort_custom(func(a, b): return acc[a] > acc[b])
		var sum := 0.0
		for k in mini(4, keys.size()): sum += float(acc[keys[k]])
		for k in 4:
			if k < keys.size() and sum > 0.0:
				bones[i * 4 + k] = int(keys[k])
				weights[i * 4 + k] = float(acc[keys[k]]) / sum
			else:
				bones[i * 4 + k] = 0
				weights[i * 4 + k] = 0.0

	arrays[Mesh.ARRAY_BONES] = bones
	arrays[Mesh.ARRAY_WEIGHTS] = weights
	var out := ArrayMesh.new()
	out.add_surface_from_arrays(am.surface_get_primitive_type(0), arrays)
	out.surface_set_material(0, am.surface_get_material(0))
	out.resource_name = am.resource_name
	out.custom_aabb = am.get_aabb().grow(0.15)
	report[path] = {"leg_swapped": n_swap, "thigh_blended": n_thigh, "head_moved": n_head, "verts": verts.size()}
	return out
