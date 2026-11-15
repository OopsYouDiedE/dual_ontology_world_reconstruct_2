extends SceneTree
const CaptureReceipt := preload("res://mcp/CaptureReceipt.gd")
## 集成回归：真实开场与走廊选择进入厨房，再自动搜证并处理第一天四区首题。
## 四题结论交回 DualEngine；随后检查原有门禁与场景节拍，不修改剧情数据。
const Main := preload("res://scenes/dual_world/DualWorldMain.tscn")
const ANSWERS := {
	"ded_drag": "in",
	"ded_cloth": "carried",
	"ded_cuffs": "reset",
	"ded_window": "ghost",
}
const CONFLICTS := ["c_door", "c_wetcloth", "c_handcuff", "c_window"]
const CONFLICT_ANSWERS := {
	"c_door": "echo",
	"c_wetcloth": "fifth",
	"c_handcuff": "split",
	"c_window": "imprint",
}
const REPLAY_ORDER := ["su_open", "detective_pull", "shen_cloth", "huo_lock"]

var fails := 0

func _check(ok: bool, message: String) -> void:
	print(("PASS  " if ok else "FAIL  ") + message)
	if not ok: fails += 1

func _idx(items: Array, id: String) -> int:
	for i in items.size():
		if str(items[i].id) == id: return i
	return -1

func _shot(out: String, tag: String) -> void:
	if DisplayServer.get_name() == "headless": return
	for i in 3: await process_frame
	var image := root.get_texture().get_image()
	if image == null: return
	if not CaptureReceipt.save(image, out.path_join(tag + ".png"), self): quit(1); return
	print("shot ", tag)

func _wait_modal(game, key: String, max_ms := 12000) -> bool:
	var start := Time.get_ticks_msec()
	while Time.get_ticks_msec() - start < max_ms:
		if game.modal.visible and str(game._modal_key) == key: return true
		await process_frame
	return game.modal.visible and str(game._modal_key) == key

func _initialize() -> void:
	Engine.time_scale = 10.0
	var game = Main.instantiate()
	root.add_child(game)
	game.skip_subtitles = true
	var start := Time.get_ticks_msec()
	var requested_kitchen := false
	var entered_kitchen := false
	var handled_deductions := {}
	var handled_conflicts := {}
	var handled_replay := false
	var out := "res://.runtime/screens/first_four"

	while Time.get_ticks_msec() - start < 240000:
		await process_frame
		if game.opening != null and game.opening.active and game.opening.phase == "free":
			var door := _idx(game.opening._items, "door")
			if door >= 0: game.opening.interact(door)
		var gathering = game.gathering
		if gathering != null and gathering.active and gathering.phase == "free" and not requested_kitchen:
			var kitchen_door := _idx(gathering._items, "kitchen")
			if kitchen_door >= 0:
				gathering.interact(kitchen_door)
				requested_kitchen = true
		if requested_kitchen and not entered_kitchen and game.kitchen != null and game.kitchen.active and str(game.eng.s.room) == "B-P":
			entered_kitchen = true
			game.auto_search = true
			game.eng.s.speed = 12.0
			print("PASS  开场与走廊后由玩家互动厨房门进入 B-P")

		var replay = game.kitchen._order_replay if game.kitchen != null else null
		if replay != null and is_instance_valid(replay) and replay.active and not replay._playing and not handled_replay:
			await _shot(out, "01_kitchen_replay")
			var order: Array[String] = []
			for action_id in REPLAY_ORDER: order.append(str(action_id))
			replay._order = order
			replay._render_order()
			replay._confirm_order()
			handled_replay = true
			handled_deductions["ded_drag"] = true
			print("PASS  首题厨房动作顺序确认并交回原引擎")

		var pending_ded: Dictionary = game.eng.s.pending_deduction
		if not pending_ded.is_empty():
			var did := str(pending_ded.id)
			if ANSWERS.has(did) and not handled_deductions.has(did) and (did != "ded_drag" or handled_replay):
				var ded_modal_ready := await _wait_modal(game, "ded:" + did)
				_check(ded_modal_ready, "%s 推演 UI 就绪" % did)
				if did in ["ded_cuffs", "ded_window"]:
					_check(game.kitchen == null or not game.kitchen.active, "离开 B-P 后厨房专属漫游已交还")
					_check(str(game._room_loaded) == str(game.eng.s.room), "离开 B-P 后场景状态同步当前剧情房间")
					_check(str(game.room_mesh.design.get("room_id", "")) == str(game.eng.s.room), "离开 B-P 后实际 3D 房间网格同步当前剧情房间")
				await _shot(out, did)
				game._dismiss_modal()
				game.eng.solve_deduction(did, str(ANSWERS[did]))
				handled_deductions[did] = true
				print("PASS  %s 正确推演结算" % did)

		var conflict_id := str(game.eng.s.pending_conflict)
		if conflict_id != "" and CONFLICT_ANSWERS.has(conflict_id) and not handled_conflicts.has(conflict_id):
			var conflict_modal_ready := await _wait_modal(game, "con:" + conflict_id)
			_check(conflict_modal_ready, "%s 争辩 UI 就绪" % conflict_id)
			await _shot(out, conflict_id)
			game._dismiss_modal()
			game.eng.resolve_conflict(conflict_id, str(CONFLICT_ANSWERS[conflict_id]))
			handled_conflicts[conflict_id] = true
			print("PASS  %s 争辩沿用主线选项结算" % conflict_id)

		var all_done := handled_deductions.size() == 4 and handled_conflicts.size() == 4
		if all_done and float(game.eng.s.t) >= 665.0:
			game.eng.set_door_flags()
			for i in 3:
				_check(bool(game.eng.s.doors.get("zone.%d" % i, false)), "第一至三区门禁开放 zone.%d" % i)
			_check(bool(game.eng.s.doors.get("zone.3", false)), "第四区门禁按既有时序开放")
			var meeting_reached := false
			for entry in game.eng.s.log:
				if str(entry.get("kind", "")) == "beat" and "四区对账" in str(entry.get("text", "")): meeting_reached = true
			_check(meeting_reached, "四区推演后接入原中翼对账节拍")
			break

	if not entered_kitchen: _check(false, "开场路径进入 B-P")
	_check(handled_replay, "首题动作复演已完成")
	_check(handled_deductions.size() == 4, "第一天四项推演均已正确结算 (%d/4)" % handled_deductions.size())
	_check(handled_conflicts.size() == 4, "四项推演均衔接到原争辩 (%d/4)" % handled_conflicts.size())
	_check(fails == 0, "全程无集成回归失败")
	print("RESULT fails=", fails, " beat=", game.eng.s.current_beat, " time=", game.eng.s.t, " room=", game.eng.s.room)
	quit(1 if fails > 0 else 0)
