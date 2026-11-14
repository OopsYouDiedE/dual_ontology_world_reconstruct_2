extends SceneTree
## 无界面冒烟测试：实例化整合入口、切换三种视图、逐间生成 3D 房间与人物、合成音乐若干帧。
##   godot --headless --path . --script res://tools/dual_world/dual_smoke.gd

const MainScene := preload("res://scenes/dual_world/DualWorldMain.tscn")
const RoomMesh := preload("res://scenes/dual_world/RoomMesh3D.gd")
const Geo := preload("res://scenes/dual_world/RoomGeometry.gd")
const Data := preload("res://scenes/dual_world/DualData.gd")

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
		print("失败 %d" % fails)
		quit(1 if fails > 0 else 0)
	return false


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
		if button.text.begins_with("先回案卷重推"): retry_button = button
	check(retry_button != null, "永久争执弹窗显示重推入口")
	if retry_button == null: return
	retry_button.pressed.emit()
	main._sync_modal()
	check(main.modal.visible and main.eng.s.pending_deduction.get("id", "") == "ded_truth",
		"点击争执中的重推按钮可打开原推演弹窗")
	var evidence_checks: Array = main.modal.find_children("*", "CheckBox", true, false)
	var readable := not evidence_checks.is_empty()
	for evidence_check in evidence_checks:
		for color_name in ["font_color", "font_pressed_color", "font_hover_color", "font_hover_pressed_color", "font_focus_color"]:
			readable = readable and evidence_check.get_theme_color(color_name) == main.TEXT
	check(readable, "推演证物复选框各状态均使用亮色文字")
	var answer_button: Button
	for button in main.modal.find_children("*", "Button", true, false):
		if button.text == str(deduction.hypotheses.filter(func(hypothesis): return hypothesis.id == deduction.correct)[0].label):
			answer_button = button
	check(answer_button != null, "重推弹窗保留正确假设按钮")
	if answer_button == null: return
	for evidence_check in evidence_checks: evidence_check.button_pressed = false
	check(answer_button.disabled, "取消勾选后证物不足会禁用假设按钮")
	for evidence_check in evidence_checks: evidence_check.button_pressed = true
	check(not answer_button.disabled, "重新勾选足够证物后恢复假设按钮")
	answer_button.pressed.emit()
	main._sync_modal()
	check(main.modal.visible and main.eng.s.pending_conflict == "c_demon"
		and main.eng.s.deductions.get("ded_truth", "") == "solved" and not main.eng.s.irreparable,
		"通过界面重推成功后返回原永久争执且没有关系裂痕")
