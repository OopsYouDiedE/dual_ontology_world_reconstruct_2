extends SceneTree
## 开发回归：检查原房间相机/世界/证物身份和退出恢复；画面验收交给独立 Terra。
const Main := preload("res://scenes/dual_world/DualWorldMain.tscn")
var failures := 0
var checks := 0

func check(value: bool, message: String) -> void:
	checks += 1
	print(("PASS " if value else "FAIL ") + message)
	if not value: failures += 1

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	Engine.time_scale = 20.0
	var game = Main.instantiate()
	game.show_intro = false
	game.instant_story = true
	root.add_child(game)
	game.set_process(false)
	game.score.set_enabled(false)
	game.eng.s.room = "B-P"
	game.eng.s.t = 480.0
	game.eng.s.current_beat = "d1_deduce_drag"
	game.eng.s.beat_cursor = 2
	game._build_room("B-P")
	game._det_to_home()
	await process_frame
	await process_frame
	check(game.evidence_presentations.size() == 7, "七件现场证物入场即创建")
	var camera_id: int = game.cam.get_instance_id()
	var world_id: int = game.cam.get_world_3d().get_instance_id()
	var viewport_count: int = game.find_children("*", "SubViewport", true, false).size()
	var room_id: int = game.lowpoly._root.get_instance_id()
	for kind in ["sleeve", "drag", "water", "cloth", "ratchet", "boots", "seal"]:
		var detail: Node3D = game.evidence_presentations[kind]
		var detail_id := detail.get_instance_id()
		var saved: Transform3D = game.cam.global_transform
		game.eng.s.playing = true
		var result := {"calls": 0, "success": false}
		check(game.interactions.begin_gameplay(game, kind, func(success: bool):
			result.calls += 1
			result.success = success), kind + " 原场景调查启动")
		var active = game.interactions.active
		var deadline := Time.get_ticks_msec() + 3000
		while is_instance_valid(active) and not active._ready_for_input and Time.get_ticks_msec() < deadline:
			await process_frame
		check(is_instance_valid(active) and active._ready_for_input, kind + " 镜头推近到位")
		check(game.cam.get_instance_id() == camera_id and game.cam.get_world_3d().get_instance_id() == world_id, kind + " 相机与世界身份保持")
		check(game.find_children("*", "SubViewport", true, false).size() == viewport_count, kind + " 未创建额外视口")
		check(game.lowpoly._root.get_instance_id() == room_id and active.prop.get_instance_id() == detail_id, kind + " 房间与证物实例保持")
		if kind == "sleeve": detail.align_hand(Vector2(0.25, 0))
		elif kind in ["drag", "water", "cloth", "boots"]: detail.sweep(200.0, Vector2.ZERO)
		await create_timer(0.65).timeout
		active.close()
		await create_timer(0.85).timeout
		check(int(result.calls) == 1 and bool(result.success), kind + " 完成回调仅一次")
		check(game.cam.global_transform.is_equal_approx(saved) and bool(game.eng.s.playing) and not game._cine, kind + " 相机与游玩状态恢复")
		check(is_instance_valid(game.evidence_presentations[kind]) and game.evidence_presentations[kind].get_instance_id() == detail_id, kind + " 调查后证物仍留在现场")
	# Session input has priority over the journal and never records an unfinished sample.
	for kind in ["drag", "water"]:
		game.evidence_presentations[kind].progress = 0.0
		game.evidence_presentations[kind].completed = false
	var returns: Array[bool] = []
	check(game.interactions.begin_gameplay(game, "drag", func(success: bool): returns.append(success)), "再次查看可在推近期间退出")
	var escape := InputEventAction.new()
	escape.action = "cancel"
	escape.pressed = true
	game._input(escape)
	game._input(escape)
	await create_timer(0.85).timeout
	check(returns == [false] and game.interactions.active == null and not game.modal.visible, "Esc 只关闭特写、不记入未完成证物、不打开案卷")
	check(game.interactions.begin_gameplay(game, "water", func(success: bool): returns.append(success)), "右键退出路径可用")
	var right_click := InputEventMouseButton.new()
	right_click.button_index = MOUSE_BUTTON_RIGHT
	right_click.pressed = true
	game._input(right_click)
	await create_timer(0.85).timeout
	check(returns == [false, false] and game.interactions.active == null and not game._cine, "右键退出后恢复探索，每次只结算一次")
	# 推近中取消后马上换房，不允许旧相机下一帧覆盖新房镜头。
	game.interactions.begin_gameplay(game, "water")
	await create_timer(0.2).timeout
	game.interactions.cancel()
	game.eng.s.room = "A-P"
	game._build_room("A-P")
	var next_camera: Transform3D = game.cam.global_transform
	await create_timer(1.0).timeout
	check(game.cam.global_transform.is_equal_approx(next_camera), "取消后旧镜头不会覆盖新房间")
	check(game.evidence_presentations.is_empty(), "离开厨房释放厨房证物映射")
	game.eng.s.chapter = 1
	game.eng.s.chapter_complete = true
	game.eng.s.playing = false
	game.eng.s.t = 1320.0
	game._sub_queue.clear()
	game.subtitle.visible = false
	game.det_path.clear()
	game._sync_modal()
	check(game.modal.visible and game._modal_key == "chapter:1", "第一章完成后出现独立章节卡")
	check(FileAccess.file_exists(game.chapter_save_path(1)), "章节完成检查点已写入")
	var next_button: Button
	for button in game.modal.find_children("*", "Button", true, false):
		if button.text == "Chapter 2": next_button = button
	check(next_button != null, "章节卡提供明确继续入口")
	if next_button != null:
		next_button.pressed.emit()
		await create_timer(1.0).timeout
		check(int(game.eng.s.chapter) == 2 and not bool(game.eng.s.chapter_complete), "章节卡实际按钮继续第二章")
	print("IN_ROOM_EVIDENCE checks=%d failures=%d" % [checks, failures])
	game.queue_free()
	await process_frame
	quit(0 if failures == 0 else 1)
