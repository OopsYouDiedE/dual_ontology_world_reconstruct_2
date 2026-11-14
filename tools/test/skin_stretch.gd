extends SceneTree
## 蒙皮拉伸检测：对每个动画片段取若干帧，CPU 蒙皮后统计相对静止姿态被拉长 / 压扁的三角边。
## 用法：godot --headless --path . -s tools/test/skin_stretch.gd -- ids=detective,su nofix=0
const Data := preload("res://scenes/dual_world/DualData.gd")
const Figure := preload("res://scenes/dual_world/ProceduralFigure.gd")
const Imp := preload("res://scenes/components/characters/ImportedCharacter.gd")
const RigFix := preload("res://scenes/components/characters/RigWeightFix.gd")

func _arg(k: String, d: String) -> String:
	for a in OS.get_cmdline_user_args():
		if str(a).begins_with(k + "="): return str(a).substr(k.length() + 1)
	return d

func _skin_points(skel: Skeleton3D, mi: MeshInstance3D, arrays: Array, rest: bool) -> PackedVector3Array:
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var bones: PackedInt32Array = arrays[Mesh.ARRAY_BONES]
	var weights: PackedFloat32Array = arrays[Mesh.ARRAY_WEIGHTS]
	var skin := mi.skin
	var mats: Array = []
	for b in skel.get_bone_count():
		var g := skel.get_bone_global_rest(b) if rest else skel.get_bone_global_pose(b)
		var bind := skel.get_bone_global_rest(b).affine_inverse()
		if skin != null and b < skin.get_bind_count(): bind = skin.get_bind_pose(b)
		mats.append(g * bind)
	var out := PackedVector3Array()
	out.resize(verts.size())
	for i in verts.size():
		var p := Vector3.ZERO
		for k in 4:
			var w := weights[i * 4 + k]
			if w <= 0.0: continue
			var bi := bones[i * 4 + k]
			if bi < mats.size(): p += (mats[bi] as Transform3D) * verts[i] * w
		out[i] = p
	return out

func _dom(arrays: Array, vi: int, skel: Skeleton3D) -> String:
	var bones: PackedInt32Array = arrays[Mesh.ARRAY_BONES]
	var weights: PackedFloat32Array = arrays[Mesh.ARRAY_WEIGHTS]
	var parts: Array = []
	for k in 4:
		if weights[vi * 4 + k] > 0.01: parts.append("%s:%.2f" % [skel.get_bone_name(bones[vi * 4 + k]).replace("mixamorig_", ""), weights[vi * 4 + k]])
	return ",".join(parts)

func _initialize() -> void:
	var data = Data.get_data()
	var ids := _arg("ids", "detective").split(",")
	var dbg := _arg("dbg", "0") == "1"
	var clips_want := _arg("clips", "").split(",", false)
	root.size = Vector2i(640, 360)
	for id in ids:
		var f: Node3D = Figure.new()
		f.setup(data.actor_by_id[id], data.rig_spec.get("poses", {}))
		root.add_child(f)
		f.wake_rig()
		for i in 5: await process_frame
		var skel := f._body.get_meta("skeleton") as Skeleton3D
		var player := f._glb_player as AnimationPlayer
		var mi := skel.find_children("*", "MeshInstance3D", true, false)[0] as MeshInstance3D
		var arrays := mi.mesh.surface_get_arrays(0)
		var idx: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
		var rest_pts := _skin_points(skel, mi, arrays, true)
		print("skin=", mi.skin != null, " binds=", (mi.skin.get_bind_count() if mi.skin else 0), " bones=", skel.get_bone_count())
		var edges := {}
		for t in idx.size() / 3:
			for e in [[0, 1], [1, 2], [2, 0]]:
				var a := idx[t * 3 + e[0]]
				var b := idx[t * 3 + e[1]]
				edges[Vector2i(mini(a, b), maxi(a, b))] = true
		var groups := {}
		var verts_rest: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		for vi in verts_rest.size():
			var key := Vector3i(roundi(verts_rest[vi].x * 5000.0), roundi(verts_rest[vi].y * 5000.0), roundi(verts_rest[vi].z * 5000.0))
			if not groups.has(key): groups[key] = []
			(groups[key] as Array).append(vi)
		var multi: Array = []
		for key in groups:
			if (groups[key] as Array).size() > 1: multi.append(groups[key])
		print("  coincident groups=", multi.size())
		var names := player.get_animation_list()
		var picks: Array = []
		for n in names:
			if clips_want.is_empty():
				for key in ["Idle", "Walk", "Sit", "Lie", "wake", "Interact", "Run", "Standing"]:
					if key.to_lower() in str(n).to_lower(): picks.append(n); break
			elif str(n) in clips_want: picks.append(n)
		print("== ", id, " verts=", rest_pts.size(), " edges=", edges.size(), " clips=", picks.size())
		var worst_all := 0.0
		for n in picks:
			var anim := player.get_animation(n)
			var worst := 0.0
			var bad := 0
			var crack_max := 0.0
			var crack_n := 0
			for fr in [0.2, 0.4, 0.6, 0.8, 1.0]:
				player.play(n)
				player.seek(anim.length * min(fr, 0.999), true)
				for i in 3: await process_frame
				var pts := _skin_points(skel, mi, arrays, false)
				var hp := skel.get_bone_global_pose(Imp._find_mixamo_bone(skel, "Hips")).origin
				if fr == 0.2 or fr == 0.8: print("    ", n, " hips@", fr, " ", hp, " cur=", player.current_animation, " playing=", player.is_playing())
				var nb := 0
				for grp in multi:
					var g0: Vector3 = pts[(grp as Array)[0]]
					for gi in (grp as Array):
						var dsep := g0.distance_to(pts[gi])
						if dsep > crack_max: crack_max = dsep
						if dsep > 0.004: crack_n += 1
				for e in edges:
					var r0 := rest_pts[e.x].distance_to(rest_pts[e.y])
					if r0 < 0.004: continue
					var r1 := pts[e.x].distance_to(pts[e.y])
					var ratio := r1 / r0
					if ratio > worst: worst = ratio
					if dbg and ratio > 3.0 and fr == 0.8:
						var d0 := _dom(arrays, e.x, skel)
						var d1 := _dom(arrays, e.y, skel)
						print("      WORST %.1fx rest=%s / %s  %s  |  %s" % [ratio, str(verts_rest[e.x]), str(verts_rest[e.y]), d0, d1])
					if ratio > 1.8: nb += 1
				bad = maxi(bad, nb)
			worst_all = maxf(worst_all, worst)
			print("  %-22s worst_stretch=%.2f  edges>1.8x=%d  seam_crack_max=%.4f  cracked_verts=%d" % [n, worst, bad, crack_max, crack_n])
		print("  -> ", id, " worst overall ", snappedf(worst_all, 0.01))
		f.queue_free()
		await process_frame
	quit()
