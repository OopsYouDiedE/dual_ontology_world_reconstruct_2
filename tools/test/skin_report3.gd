extends SceneTree
## 蒙皮诊断（骨架静止姿态空间）：左右腿错边、头骨抓住颈部以下顶点、衣摆被单腿拖拽。
func _rel(n: Node, top: Node) -> Transform3D:
	var t := Transform3D.IDENTITY
	while n != null and n != top:
		t = (n as Node3D).transform * t
		n = n.get_parent()
	return t
func _initialize() -> void:
	for id in OS.get_cmdline_user_args():
		var path := "res://assets/characters/UserModels/%s.glb" % id
		var model: Node3D = (load(path) as PackedScene).instantiate()
		var sk: Skeleton3D
		for c in model.find_children("*", "Skeleton3D", true, false): sk = c
		var mi: MeshInstance3D = sk.find_children("*", "MeshInstance3D", true, false)[0]
		var to_sk := _rel(sk, model).affine_inverse() * _rel(mi, model)
		var g := func(n): return sk.get_bone_global_rest(sk.find_bone("mixamorig_" + n)).origin
		var lu: Vector3 = g.call("LeftUpLeg"); var ru: Vector3 = g.call("RightUpLeg")
		var neck: Vector3 = g.call("Neck"); var head: Vector3 = g.call("Head"); var hips: Vector3 = g.call("Hips")
		var knee: Vector3 = g.call("LeftLeg")
		var lat := (lu - ru).normalized()
		var mid := ((lu + ru) * 0.5).dot(lat)
		var half := (lu - ru).length() * 0.5
		var arr := (mi.mesh as ArrayMesh).surface_get_arrays(0)
		var v: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
		var b: PackedInt32Array = arr[Mesh.ARRAY_BONES]
		var w: PackedFloat32Array = arr[Mesh.ARRAY_WEIGHTS]
		var wrong := 0; var legverts := 0; var headlow := 0; var cloth_mono := 0; var cloth := 0
		var skin_bones := mi.skin.get_bind_count() if mi.skin else -1
		for i in v.size():
			var p := to_sk * v[i]
			var best := ""; var bw := -1.0
			for k in 4:
				if w[i*4+k] > bw: bw = w[i*4+k]; best = sk.get_bone_name(b[i*4+k])
			var is_l := "Left" in best; var is_r := "Right" in best
			if ("UpLeg" in best or best.ends_with("Leg") or "Foot" in best or "Toe" in best):
				legverts += 1
				var side := p.dot(lat) - mid   # >0 左侧
				if (is_l and side < -0.01) or (is_r and side > 0.01): wrong += 1
			if best.ends_with("Head") and p.y < neck.y - 0.01: headlow += 1
			if p.y < hips.y + 0.02 and p.y > knee.y and absf(p.dot(lat) - mid) < half * 2.2:
				cloth += 1
				if ("UpLeg" in best) and bw > 0.9: cloth_mono += 1
		print("== %s skin_binds=%s v=%d bone_y: hips %.2f neck %.2f head %.2f knee %.2f  lat=%s half=%.3f" % [id, skin_bones, v.size(), hips.y, neck.y, head.y, knee.y, lat, half])
		print("   leg-dominated verts=%d  on wrong side=%d | Head-dominated below neck=%d | thigh-zone verts=%d, 100%% single-UpLeg=%d" % [legverts, wrong, headlow, cloth, cloth_mono])
		model.free()
	quit()
