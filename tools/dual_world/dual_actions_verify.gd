extends SceneTree

const MainScene := preload("res://scenes/dual_world/DualWorldMain.tscn")
const Figure := preload("res://scenes/dual_world/ProceduralFigure.gd")
const Data := preload("res://scenes/dual_world/DualData.gd")

const SUSTAINED := ["stand", "walk", "run", "sit", "lie", "talk", "argue", "point", "think", "work", "tend", "wave"]
const IDLE_BY_DESIGN := ["stand", "think"]

var fails := 0
var frames := 0
var main: Control
var phase_two_done := false


func check(ok: bool, text: String) -> void:
	print(("  [通过] " if ok else "  [失败] ") + text)
	if not ok: fails += 1


func _initialize() -> void:
	_start.call_deferred()


func _start() -> void:
	_figure_checks()
	main = MainScene.instantiate()
	root.add_child(main)


func _figure_checks() -> void:
	var data := Data.get_data()
	var poses: Dictionary = data.rig_spec.get("poses", {})
	var fig: Node3D = Figure.new()
	fig.setup(data.actor_by_id["detective"], poses)
	root.add_child(fig)
	var player: AnimationPlayer = fig._glb_player
	check(player != null, "侦探使用 GLB 骨骼动画（AnimationPlayer 存在）")
	if player == null: return
	var skeleton: Skeleton3D = fig._body.get_meta("skeleton")
	for pose_name in SUSTAINED:
		fig.set_pose(pose_name)
		var clip := str(player.current_animation)
		var ok_clip := clip != ""
		if pose_name not in IDLE_BY_DESIGN: ok_clip = ok_clip and clip != "idle"
		check(ok_clip, "姿态 %s → 片段 %s（不应回退成待机）" % [pose_name, clip])
		if clip != "" and player.has_animation(clip):
			var mode: int = player.get_animation(clip).loop_mode
			check(mode != Animation.LOOP_NONE, "姿态 %s 的片段 %s 为循环片段" % [pose_name, clip])
			if pose_name in ["talk", "argue", "point", "tend", "work", "wave"]:
				var length := player.get_animation(clip).length
				player.play(clip, 0.0)
				player.seek(length * 0.2, true)
				var rotations: Array[Quaternion] = []
				for bone_index in skeleton.get_bone_count():
					rotations.append(skeleton.get_bone_pose_rotation(bone_index))
				player.seek(length * 0.7, true)
				var motion := 0.0
				for bone_index in skeleton.get_bone_count():
					motion = maxf(motion, rotations[bone_index].angle_to(skeleton.get_bone_pose_rotation(bone_index)))
				check(motion > 0.01, "姿态 %s 实际驱动骨骼运动（最大转角 %.3f）" % [pose_name, motion])
	for pose_name in ["talk", "argue", "work"]:
		fig.set_pose(pose_name)
		var restarts := 0
		var last := -1.0
		for frame_index in 80:
			player.advance(0.05)
			fig.set_pose(pose_name)
			var pos := player.current_animation_position
			if last >= 0.0 and pos < last - 0.0001: restarts += 1
			last = pos
		var length := player.get_animation(player.current_animation).length if player.current_animation != "" else 1.0
		var expected := int(ceil(4.0 / maxf(length, 0.1))) + 1
		check(player.is_playing() and restarts <= expected, "姿态 %s 持续 4 秒仍在播放且无异常重启（回绕 %d 次，≤ %d）" % [pose_name, restarts, expected])
	check(fig.has_method("pose_length"), "ProceduralFigure 提供 pose_length() 以便场景按真实片段时长等待")
	if fig.has_method("pose_length"):
		var wake_len: float = fig.pose_length("lie_stand_up")
		check(wake_len > 2.0, "起床片段真实时长 %.2f 秒" % wake_len)
	fig.set_pose("work")
	player.advance(0.2)
	var previous_time := player.current_animation_position
	var measurement: Dictionary = fig.measure_pose("lie", 0.0)
	check(not measurement.is_empty() and player.current_animation == "work_loop" and is_equal_approx(previous_time, player.current_animation_position), "骨骼测量恢复原片段与播放进度")
	fig.set_pose("lie")
	fig.set_pose("lie_stand_up")
	player.advance(0.0)
	player.advance(player.current_animation_length + 0.1)
	for frame_index in 5:
		fig.set_pose("lie_stand_up")
	check(not player.is_playing(), "起床一次性片段结束后保持末帧，逐帧设姿态不会重播")
	fig.queue_free()


func _process(_delta: float) -> bool:
	frames += 1
	if frames == 3:
		main.eng.s.room = "R05"
		main._set_view("room")
	if frames == 30 and not phase_two_done:
		phase_two_done = true
		_scene_checks()
		print("失败 %d" % fails)
		quit(1 if fails > 0 else 0)
	return false


func _scene_checks() -> void:
	var det: Node3D = main.det
	check(det != null, "新局进入 R05 后侦探已生成")
	if det == null: return
	var bed_y: float = det.position.y
	check(bed_y > 0.05, "开局侦探在床面高度（y=%.2f）" % bed_y)
	check(str(det.pose) == "lie", "开局侦探保持躺姿，而不是被行走逻辑改成坐姿（当前 %s）" % det.pose)
	_bed_contact_checks(det)
	check(det.has_method("pose_length"), "ProceduralFigure 提供 pose_length()")
	if not det.has_method("pose_length"): return
	var need: float = det.pose_length("lie_stand_up")
	main._begin_wake_up()
	check(main._wake_timer >= need - 0.01, "起床等待 %.2f 秒 ≥ 起床片段 %.2f 秒（否则动作被截断）" % [main._wake_timer, need])
	var last_y := bed_y
	var monotonic := true
	var steps := 0
	while main._wake_timer > 0.0 and steps < 200:
		main._step_wake_up(0.05)
		det._glb_player.advance(0.05)
		if det.position.y > last_y + 0.0001: monotonic = false
		last_y = det.position.y
		steps += 1
	check(monotonic, "起床过程身体高度单调回落，无向上跳变")
	check(absf(steps * 0.05 - need) < 0.15, "起床总耗时 %.2f 秒与片段时长 %.2f 秒一致" % [steps * 0.05, need])
	check(det.position.y < 0.01, "起床结束后侦探站在地面（y=%.2f）" % det.position.y)
	check(str(det.pose) == "stand", "起床结束后恢复站立姿态（当前 %s）" % det.pose)
	var info: Dictionary = main._bed_info()
	var bed_rect := Rect2(info.pos - info.half, info.half * 2.0)
	check(not bed_rect.has_point(main.det_pos), "起床后站在床外 (%.2f, %.2f)，不在床垫范围 %s 内" % [main.det_pos.x, main.det_pos.y, str(bed_rect)])
	check(not main._grid.is_point_solid(main._cell_of(main.det_pos)), "起床落点位于现有可行走网格")
	main._begin_wake_up()
	check(main._wake_timer == 0.0, "已离床后再次触发起床不会重复播放")


func _bed_contact_checks(det: Node3D) -> void:
	var mattress := AABB()
	var found := false
	var lp: Node3D = main.lowpoly.get("_root") if main.lowpoly != null else null
	if lp != null:
		for mi in lp.find_children("Mattress*", "MeshInstance3D", true, false):
			var b: AABB = (mi as MeshInstance3D).global_transform * (mi as MeshInstance3D).get_aabb()
			mattress = b if not found else mattress.merge(b)
			found = true
	check(found, "R05 的 Lowpoly 床含 Mattress 网格，可作为接触面基准")
	if not found or not det.has_method("measure_pose"): return
	var measurement: Dictionary = det.measure_pose("lie", 0.0)
	det.set_pose("lie")
	var back_y: float = det.position.y + float(measurement.hips_y) - main.LIE_BACK_HALF_THICKNESS
	check(absf(back_y - mattress.end.y) < 0.03, "躺姿背部高度 %.2f 贴合床垫顶面 %.2f（误差 < 3cm，不悬空）" % [back_y, mattress.end.y])
	var lo := Vector2(det.position.x + float(measurement.center.x) - 0.0, det.position.z + float(measurement.center.y))
	var rect := Rect2(Vector2(mattress.position.x, mattress.position.z), Vector2(mattress.size.x, mattress.size.z)).grow(0.1)
	check(rect.has_point(lo), "躺姿身体中心 (%.2f, %.2f) 在床垫范围内" % [lo.x, lo.y])
	var head := Vector2(det.position.x + float(measurement.head.x), det.position.z + float(measurement.head.y))
	check(rect.has_point(head), "躺姿头部 (%.2f, %.2f) 在床垫范围内" % [head.x, head.y])
