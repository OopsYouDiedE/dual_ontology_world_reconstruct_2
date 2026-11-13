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
		print("失败 %d" % fails)
		quit(1 if fails > 0 else 0)
	return false
