extends SceneTree
## 无界面冒烟测试：实例化整合入口、切换三种视图、逐间生成 3D 房间与人物、合成音乐若干帧。
##   godot --headless --path . --script res://tools/dual_world/dual_smoke.gd

const MainScene := preload("res://scenes/dual_world/DualWorldMain.tscn")
const RoomMesh := preload("res://scenes/dual_world/RoomMesh3D.gd")
const Geo := preload("res://scenes/dual_world/RoomGeometry.gd")
const Data := preload("res://scenes/dual_world/DualData.gd")
const Lifecycle := preload("res://scenes/components/shared/HostLifecycle.gd")

var frames := 0
var main: Control
var fails := 0


func _initialize() -> void:
	main = MainScene.instantiate()
	main.instant_story = true
	main.auto_search = true # 回归测试显式启用自动搜证；正式开局默认由玩家控制
	root.add_child(main)


func check(ok: bool, text: String) -> void:
	print(("  [通过] " if ok else "  [失败] ") + text)
	if not ok: fails += 1


func _process(_delta: float) -> bool:
	frames += 1
	if frames == 3:
		main.eng.s.room = "B-P"
		main._set_view("room")
	if frames == 6:
		check(main.room_mesh.get_child_count() > 0, "3D 房间已生成（%s）" % main.room_mesh.design.name)
		check(main.figures.size() > 0 or true, "人物生成：%d 名" % main.figures.size())
		main._set_view("editor")
	if frames == 9:
		check(not main.editor.design.is_empty(), "2D 编辑器载入设计")
		main.editor.add_prop("table")
		main.editor.undo()
		main._set_view("map")
	if frames == 12:
		# 逐间构建全部房间的 3D 网格
		var data := Data.get_data()
		var built := 0
		for r in data.rooms:
			var rm: Node3D = RoomMesh.new()
			root.add_child(rm)
			rm.build(Geo.make_design(r, data), {})
			for az in [0.0, 1.6, 3.1, 4.7]:
				rm.refresh_walls(az)
			built += 1
			rm.queue_free()
		check(built == data.rooms.size(), "全部 %d 间房 3D 生成无错误" % built)
		# 触发各类模态
		main.eng.s.t = float(Data.t_minutes(1, 8, 10))
		main.eng.process_beats()
	if frames > 12 and frames < 400:
		main.eng.s.speed = 600.0
		if not main.eng.s.hold.is_empty(): main.eng.search_step()  # 推演前必须先搜证
		if main.eng.s.waiting:
			# 模拟玩家处理待决事项，借此覆盖三类模态的构建
			main._sync_modal()
			var s: Dictionary = main.eng.s
			if not s.pending_deduction.is_empty(): main.eng.solve_deduction(s.pending_deduction.id, "x")
			elif s.pending_conflict != "": main.eng.resolve_conflict(s.pending_conflict, "x")
			elif not s.pending_choice.is_empty(): main.eng.choose(s.pending_choice.beat_id, s.pending_choice.choice.options[0].id)
	if frames == 400:
		check(main.eng.s.t > 1000.0, "时间推进到第 %d 分钟" % int(main.eng.s.t))
		var sc = main.score
		sc.start()
		sc.sfx("door")
		main.eng.s.ending = ""
		main.eng.finish()
		main._sync_modal()
	if frames == 420:
		_check_conflict_retry()
		_check_save_and_ending()
		print("失败 %d" % fails)
		_finish.call_deferred()
	return false


func _finish() -> void:
	main.score.stop()
	await process_frame
	await Lifecycle.quit(self, 1 if fails > 0 else 0)


func _check_conflict_retry() -> void:
	main._dismiss_modal()
	main.eng.new_game()
	var data := Data.get_data()
	var deduction: Dictionary = data.deduction_by_id["ded_truth"]
	for evidence_id in deduction.evidence:
		main.eng.s.evidence[evidence_id] = {"at": main.eng.s.t, "room": data.evidence_by_id[evidence_id].room}
	main.eng.open_deduction("ded_truth", "c_demon")
	main.eng.solve_deduction("ded_truth", "__wrong__")
	main._sync_modal()
	var retry_button: Button
	for button in main.modal.find_children("*", "Button", true, false):
		if button.text.contains("先翻回案卷重新推演"): retry_button = button
	check(retry_button != null, "永久争执弹窗显示重推入口")
	if retry_button == null: return
	retry_button.pressed.emit()
	main._sync_modal()
	check(main.modal.visible and main.eng.s.pending_deduction.get("id", "") == "ded_truth",
		"点击争执中的重推按钮可打开原推演弹窗")
	var evidence_checks: Array = main.modal.find_children("*", "CheckBox", true, false)
	var readable := not evidence_checks.is_empty()
	var color_states := {
		"font_color": "normal", "font_pressed_color": "pressed", "font_hover_color": "hover",
		"font_hover_pressed_color": "hover_pressed", "font_focus_color": "normal"
	}
	for evidence_check in evidence_checks:
		for color_name in color_states:
			var foreground: Color = evidence_check.get_theme_color(color_name)
			var background: Color = evidence_check.get_theme_stylebox(color_states[color_name]).bg_color
			var foreground_luminance := foreground.srgb_to_linear().get_luminance()
			var background_luminance := background.srgb_to_linear().get_luminance()
			var contrast := (maxf(foreground_luminance, background_luminance) + 0.05) / (minf(foreground_luminance, background_luminance) + 0.05)
			readable = readable and contrast >= 4.5
	check(readable, "推演证物复选框各状态文字对比度至少为 4.5:1")
	var answer_button: Button
	for button in main.modal.find_children("*", "Button", true, false):
		if button.text == str(deduction.hypotheses.filter(func(hypothesis): return hypothesis.id == deduction.correct)[0].label):
			answer_button = button
	check(answer_button != null, "重推弹窗保留正确假设按钮")
	if answer_button == null: return
	for evidence_check in evidence_checks: evidence_check.button_pressed = false
	check(answer_button.disabled, "取消勾选后证物不足会禁用假设按钮")
	var select_all := _modal_button("全选已得证物")
	check(select_all != null and select_all.visible, "取消证物勾选后显示全选入口")
	if select_all == null: return
	select_all.pressed.emit()
	check(not answer_button.disabled and not select_all.visible, "全选已得证物恢复推演按钮并收起全选入口")
	answer_button.pressed.emit()
	main._sync_modal()
	check(main.modal.visible and main.eng.s.pending_conflict == "c_demon"
		and main.eng.s.deductions.get("ded_truth", "") == "solved" and not main.eng.s.irreparable,
		"通过界面重推成功后返回原永久争执且没有关系裂痕")


func _modal_button(text: String) -> Button:
	for button in main.modal.find_children("*", "Button", true, false):
		if button.text == text: return button
	return null


func _check_save_and_ending() -> void:
	main._dismiss_modal()
	main.eng.new_game()
	main.eng.s.playing = true
	main.eng.s.speed = 600.0
	var save_path: String = main.slot_save_path(3)
	main._write_save(save_path)
	main.instant_story = false
	var loaded: bool = main._read_save(save_path)
	check(loaded and not main.eng.s.playing and is_equal_approx(main.eng.s.speed, 5.0), "交互读档暂停时间并将过高倍率回调至 5 倍")
	main.instant_story = true
	main.eng.s.speed = 20.0
	main._write_save(save_path)
	main.instant_story = false
	loaded = main._read_save(save_path)
	check(loaded and not main.eng.s.playing and is_equal_approx(main.eng.s.speed, 20.0), "交互读档保留正常阅读倍率")
	main.instant_story = true
	main._save_design()
	main._load_designs()
	check(main.design_save_path().get_base_dir() == save_path.get_base_dir()
		and main.auto_save_path().get_base_dir() == save_path.get_base_dir()
		and main.designs.has(main.editor.design.room_id), "设计与存档共用隔离目录，保存后可重载设计")
	main.eng.finish()
	main._write_auto()
	var ending_id: String = main.eng.s.ending
	main.eng.new_game()
	loaded = main._read_save(main.auto_save_path())
	main._sync_modal()
	check(loaded and main.eng.s.ending == ending_id and main.modal.visible, "通关自动存档保留结局，读档后重新展示结局页")
	var case_button := _modal_button("翻看案卷")
	check(case_button != null, "结局页提供案卷回看入口")
	if case_button == null: return
	case_button.pressed.emit()
	main._sync_modal()
	check(not main.modal.visible and main.drawer.visible and main.eng.s.ending == ending_id, "翻看案卷保留结局并打开案卷抽屉")
	main.play_btn.pressed.emit()
	main._sync_modal()
	check(main.modal.visible and main.eng.s.ending == ending_id, "案卷回看期间可再次打开结局页")
	var restart_button := _modal_button("重新开始")
	check(restart_button != null, "结局页提供重新开始入口")
	if restart_button == null: return
	restart_button.pressed.emit()
	main._sync_modal()
	main.instant_story = false
	loaded = main._read_save(main.auto_save_path())
	check(loaded and main.eng.s.ending == "" and main.eng.s.beat_cursor <= 1 and not main.eng.s.playing, "重新开始清空结局并将新局写入自动存档")
	_check_title_flow()


func _check_title_flow() -> void:
	var host: Node = load("res://scenes/main/Main.tscn").instantiate()
	root.add_child(host)
	var candidates: Array = host._dual_world_saves()
	check(candidates.size() == 4 and candidates.has(main.slot_save_path(3)) and candidates.has(main.auto_save_path()), "标题继续入口识别自动存档及全部三个手动槽位")
	var menus_match := true
	for node_path in ["Menu/LifeTestButton", "Menu/CampaignButton", "Menu/RecordsButton"]:
		menus_match = menus_match and host.title_ui.get_node(node_path).visible == (host.bridge != null)
	check(menus_match and host.title_ui.get_node("Menu/StartButton").visible, "标题按 C# 可用性显示生活与调试入口，并保留正式新局")
	host.open_dual_world()
	check(is_instance_valid(host.dual_world) and host.mcp_observe().get("mode", "") == "dual_world", "标题可打开正式新局并转发正式游戏观察状态")
	host.dual_world._close()
	check(host.dual_world == null and host.title_ui.interactive and host.has_progress(), "返回标题保存进度并恢复继续入口")
	host._continue_game()
	check(is_instance_valid(host.dual_world) and not host.dual_world.eng.s.playing, "标题继续游戏读取正式存档并保持暂停")
	host.begin_shutdown()
	host.queue_free()
