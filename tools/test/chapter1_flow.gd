extends SceneTree
## 第一章现版流程探针。
## 前半段实例化正式 DualWorldMain，并用开发自动输入走过醒来／走廊／厨房入口。
## 后半段为明确标记的诊断推进：直接补齐证物、提交已有 UI 的推演／争执／抉择，目的是定位节拍链，
## 不代表玩家视觉、碰撞或操作验收，也不启用生产自动搜证。

const Main := preload("res://scenes/dual_world/DualWorldMain.tscn")
const Data := preload("res://scenes/dual_world/DualData.gd")
const Engine_ := preload("res://scenes/dual_world/DualEngine.gd")

const ANSWERS := {
	"ded_drag": "in", "ded_cloth": "carried", "ded_cuffs": "reset",
	"ded_window": "ghost", "ded_truth": "literal",
}
const CONFLICT_ANSWERS := {
	"c_door": "echo", "c_wetcloth": "fifth", "c_handcuff": "split",
	"c_window": "imprint", "c_demon": "lexeme", "c_borrow": "both",
}
const REPLAY_ORDER := ["su_open", "detective_pull", "shen_cloth", "huo_lock"]

var fails := 0


func _check(ok: bool, text: String) -> void:
	print(("PASS  " if ok else "FAIL  ") + text)
	if not ok: fails += 1


func _idx(items: Array, id: String) -> int:
	for i in items.size():
		if str(items[i].id) == id: return i
	return -1


func _seed_evidence(game, did: String) -> void:
	var dd: Dictionary = game.data.deduction_by_id[did]
	print("[DEV DIAGNOSTIC] 直接补齐推演证物：", did)
	for eid in dd.evidence:
		var room := str(game.data.evidence_by_id[eid].room)
		game.eng.s.room = room
		game.eng.inspect_evidence(str(eid), true)


func _poem_branch(branch: String) -> bool:
	var e = Engine_.new(Data.get_data())
	var hint := -1
	for i in e.d.beats.size():
		if str(e.d.beats[i].id) == "d1_poem_hint": hint = i
	if hint < 0: return false
	e.s.t = float(e.T(1, 13, 15))
	e.s.room = "2F-cross-M"
	e.s.beat_cursor = hint
	e.process_beats()
	if str(e.s.pending_choice.get("beat_id", "")) != "d1_poem_hint": return false
	e.choose("d1_poem_hint", branch)
	e.s.t = float(e.T(1, 13, 35))
	e.process_beats()
	if str(e.s.current_beat) != "d1_poem": return false
	e.s.t = float(e.T(1, 15, 30))
	e.process_beats()
	return str(e.s.current_beat) == "d1_institutes"


func _teardown_game(game) -> void:
	if game == null or not is_instance_valid(game): return
	# 测试中途若有同场 closeup，先让导演走正常的 restore/callback 收束路径。
	print("[DEV DIAGNOSTIC] CLEANUP interactions")
	if game.interactions != null and is_instance_valid(game.interactions):
		game.interactions.cancel()
		await process_frame
	print("[DEV DIAGNOSTIC] CLEANUP kitchen")
	if game.kitchen != null and is_instance_valid(game.kitchen) and game.kitchen.active:
		game.kitchen.end()
	print("[DEV DIAGNOSTIC] CLEANUP game queued")
	game.queue_free()
	# 把 queue_free 和可能的 tween/closeup tree_exiting 信号消化完，再退出进程。
	for i in 60: await process_frame
	print("[DEV DIAGNOSTIC] CLEANUP frames drained")


func _initialize() -> void:
	# This optional development-only cap avoids giant per-frame walking steps
	# during the script's 120x time acceleration. It never changes game code.
	var motion_scale := 120.0
	var stall_snapshot := ""
	var pretransit_snapshot := ""
	var pretransit_from := ""
	var pretransit_to := ""
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--dv-motion-scale="):
			var value := argument.trim_prefix("--dv-motion-scale=")
			if not value.is_valid_float() or float(value) <= 0.0 or float(value) > 120.0:
				printerr("Invalid --dv-motion-scale; expected a number in (0, 120]")
				call_deferred("quit", 2)
				return
			motion_scale = float(value)
		elif argument.begins_with("--dv-stall-snapshot="):
			stall_snapshot = preload("res://mcp/CaptureSource.gd").project_output(argument.trim_prefix("--dv-stall-snapshot="))
			if stall_snapshot.is_empty():
				printerr("Stall checkpoint must be an output inside the authorized project")
				call_deferred("quit", 2)
				return
		elif argument.begins_with("--dv-pretransit-snapshot="):
			pretransit_snapshot = preload("res://mcp/CaptureSource.gd").project_output(argument.trim_prefix("--dv-pretransit-snapshot="))
			if pretransit_snapshot.is_empty():
				printerr("Transit checkpoint must be an output inside the authorized project")
				call_deferred("quit", 2)
				return
		elif argument.begins_with("--dv-pretransit-from="):
			pretransit_from = argument.trim_prefix("--dv-pretransit-from=")
		elif argument.begins_with("--dv-pretransit-to="):
			pretransit_to = argument.trim_prefix("--dv-pretransit-to=")
	if (not pretransit_snapshot.is_empty() or not pretransit_from.is_empty() or not pretransit_to.is_empty()) and (pretransit_snapshot.is_empty() or pretransit_from.is_empty() or pretransit_to.is_empty()):
		printerr("Transit checkpoint requires snapshot, from and to together")
		call_deferred("quit", 2)
		return
	if not pretransit_snapshot.is_empty():
		var rooms: Dictionary = Data.get_data().room_by_id
		if not rooms.has(pretransit_from) or not rooms.has(pretransit_to) or pretransit_from == pretransit_to:
			printerr("Transit checkpoint room IDs must name two different project rooms")
			call_deferred("quit", 2)
			return
	# 测试专用：加速镜头与复演，同时停住自然时钟；后文仍只通过 next_beat 推进剧情。
	Engine.time_scale = 120.0
	print("[DEV DIAGNOSTIC] walking/transit time-scale cap=", motion_scale, "; no acceptance claim")
	var game = Main.instantiate()
	root.add_child(game)
	game.skip_subtitles = true
	game.auto_search = false
	await process_frame
	game.eng.s.speed = 0.0
	print("[DEV UI INPUT] 开场、走廊、厨房入口通过脚本调用现有互动方法；生产自动搜证保持关闭。")
	print("[DEV DIAGNOSTIC] 后段通过引擎 API 推进，检查第一天节拍与弹窗连接。")
	var started := Time.get_ticks_msec()
	var asked_kitchen := false
	var seeded_kitchen := false
	var replay_done := false
	var handled_ded := {}
	var handled_conflict := {}
	var prepared_ded := {}
	var prepared_hold := {}
	var handled_choice := false
	var reached_plan := false
	var pretransit_captured := false
	var last_state := ""
	var last_progress := Time.get_ticks_msec()

	while Time.get_ticks_msec() - started < 180000:
		await process_frame
		if motion_scale < 120.0:
			var pending_room_change: bool = game.view == "room" and game._room_loaded != "" and str(game.eng.s.room) != str(game._room_loaded)
			var desired_scale := motion_scale if game._transit_active() or not game.det_path.is_empty() or pending_room_change else 120.0
			if not is_equal_approx(Engine.time_scale, desired_scale):
				Engine.time_scale = desired_scale
				print("[DEV DIAGNOSTIC] walking/transit test time_scale=", desired_scale)
		# A stuck development driver is not a game verdict. Preserve the actual
		# gates and UI state instead of burning the whole slow-loop timeout.
		var diagnostic := {"beat":str(game.eng.s.current_beat), "room":str(game.eng.s.room),
			"time":game.eng.s.t, "cursor":game.eng.s.beat_cursor, "hold":game.eng.s.hold,
			"postponed":game.eng.s.postponed, "story_gate":game.eng.s.story_gate,
			"waiting":game.eng.s.waiting, "pending_deduction":game.eng.s.pending_deduction,
			"pending_conflict":game.eng.s.pending_conflict, "pending_choice":game.eng.s.pending_choice,
			"story_busy":game._story_busy(), "cinematic":game._cine,
			"modal_visible":game.modal.visible, "modal_key":game._modal_key,
			"subtitle_visible":game.subtitle.visible, "subtitle_queue":game._sub_queue.size(),
			"path_points":game.det_path.size(), "detective_x":snappedf(game.det_pos.x,0.01),
			"detective_z":snappedf(game.det_pos.y,0.01),
			"opening":str(game.opening.phase) if is_instance_valid(game.opening) and game.opening.active else "",
			"corridor":str(game.gathering.phase) if is_instance_valid(game.gathering) and game.gathering.active else "",
			"kitchen":str(game.kitchen.phase) if is_instance_valid(game.kitchen) and game.kitchen.active else ""}
		var state_text := JSON.stringify(diagnostic)
		if state_text != last_state:
			last_state = state_text
			last_progress = Time.get_ticks_msec()
		elif Time.get_ticks_msec() - last_progress > 30000:
			# Observe the live production path without moving the actor or changing
			# its occupancy: this diagnoses the accelerated test driver only.
			var observation: Dictionary = game.mcp_observe()
			diagnostic["navigation"] = observation.get("navigation", {})
			diagnostic["loaded_room"] = str(game._room_loaded)
			diagnostic["transit_active"] = bool(game._transit_active())
			diagnostic["transit_phase"] = str(game._transit.get("phase", ""))
			diagnostic["wake_timer"] = float(game._wake_timer)
			diagnostic["current_position_occupiable"] = bool(game._det_can_occupy(game.det_pos))
			diagnostic["engine_time_scale"] = Engine.time_scale
			diagnostic["target_cells"] = []
			if game._grid != null:
				for point: Vector2 in game.det_path:
					var cell: Vector2i = game._cell_of(point)
					diagnostic.target_cells.append({"position": [point.x, point.y], "cell": [cell.x, cell.y],
						"static_solid": bool(game._grid.is_point_solid(cell)),
						"occupiable": bool(game._det_can_occupy(point))})
			if not stall_snapshot.is_empty():
				diagnostic["stall_snapshot_saved"] = game.checkpoints.save_now(stall_snapshot)
				diagnostic["stall_snapshot"] = stall_snapshot if diagnostic.stall_snapshot_saved else ""
				diagnostic["stall_snapshot_error"] = str(game.checkpoints.error)
			print("[DEV DIAGNOSTIC] STALLED_NO_PROGRESS " + JSON.stringify(diagnostic))
			break
		# 开发加速字幕，不修改剧情数据或自动搜证开关。
		if game.subtitle.visible: game._sub_until = 0.0

		if game.opening != null and game.opening.active and game.opening.phase == "free":
			var door := _idx(game.opening._items, "door")
			if door >= 0: game.opening.interact(door)

		if game.gathering != null and game.gathering.active and game.gathering.phase == "free" and not asked_kitchen:
			var kitchen_door := _idx(game.gathering._items, "kitchen")
			if kitchen_door >= 0:
				game.gathering.interact(kitchen_door)
				asked_kitchen = true

		if game.kitchen != null and game.kitchen.active and game.kitchen.phase == "free" and not seeded_kitchen:
			print("[DEV DIAGNOSTIC] 厨房 UI 已接管；直接登记 7 件物件以检查首题与退出条件。")
			for item in game.kitchen._items:
				game.eng.s.room = "B-P"
				game.eng.inspect_evidence(str(item.id), true)
			seeded_kitchen = true

		var replay = game.kitchen._order_replay if game.kitchen != null else null
		if replay != null and is_instance_valid(replay) and replay.active and not replay._playing and not replay_done:
			print("[DEV DIAGNOSTIC] 写入正确的厨房复演顺序。")
			var order: Array[String] = []
			for action_id in REPLAY_ORDER: order.append(str(action_id))
			replay._order = order
			replay._render()
			replay._confirm_order()
			replay_done = true
			handled_ded["ded_drag"] = true

		var pending_ded: Dictionary = game.eng.s.pending_deduction
		if not pending_ded.is_empty():
			var did := str(pending_ded.id)
			if ANSWERS.has(did) and did != "ded_drag" and not handled_ded.has(did):
				if not prepared_ded.has(did):
					_seed_evidence(game, did)
					prepared_ded[did] = true
				if game.modal.visible and str(game._modal_key) == "ded:" + did:
					game._dismiss_modal()
					game.eng.solve_deduction(did, str(ANSWERS[did]))
					handled_ded[did] = true

		var hold: Dictionary = game.eng.s.hold
		if not hold.is_empty():
			var hold_did := str(hold.get("deduction", ""))
			if ANSWERS.has(hold_did) and not prepared_hold.has(hold_did):
				_seed_evidence(game, hold_did)
				prepared_hold[hold_did] = true
				game.eng.process_beats()

		var cid := str(game.eng.s.pending_conflict)
		if cid != "" and CONFLICT_ANSWERS.has(cid) and not handled_conflict.has(cid):
			if game.modal.visible and str(game._modal_key) == "con:" + cid:
				print("[DEV DIAGNOSTIC] 提交争执正解：", cid)
				game._dismiss_modal()
				game.eng.resolve_conflict(cid, str(CONFLICT_ANSWERS[cid]))
				handled_conflict[cid] = true

		if not game.eng.s.pending_choice.is_empty() and str(game.eng.s.pending_choice.get("beat_id", "")) == "d1_poem_hint" and not handled_choice:
			if game.modal.visible and str(game._modal_key) == "cho:d1_poem_hint":
				print("[DEV DIAGNOSTIC] 选择黑板诗 expose 分支。")
				game._dismiss_modal()
				game.eng.choose("d1_poem_hint", "expose")
				handled_choice = true

		if str(game.eng.s.current_beat) == "d1_plan":
			reached_plan = true
			break

		var can_advance: bool = seeded_kitchen and game.eng.s.pending_deduction.is_empty() and game.eng.s.pending_conflict == "" and game.eng.s.pending_choice.is_empty() and game.eng.s.hold.is_empty() and game.eng.s.postponed.is_empty() and game.eng.s.story_gate.is_empty() and not game.eng.s.waiting and not game._story_busy() and (game.kitchen == null or not game.kitchen.active or replay_done)
		if can_advance:
			print("[DEV DIAGNOSTIC] 下一节拍：", game.eng.s.current_beat, " ->")
			# next_beat may change rooms synchronously. Lower the clock before
			# the next host frame, rather than after its first oversized walk step.
			if motion_scale < 120.0: Engine.time_scale = motion_scale
			game.eng.next_beat()
			if not pretransit_captured and not pretransit_snapshot.is_empty() and str(game._room_loaded) == pretransit_from and str(game.eng.s.room) == pretransit_to and not game._transit_active():
				var detective_before: Vector2 = game.det_pos
				var camera_before: Transform3D = game.cam.global_transform
				var rules_before: Dictionary = game.eng.save_dict()
				# Explicitly invoke the same production watcher before the next
				# frame, so the checkpoint records the planned route before any
				# movement. This is a development intervention, not natural play.
				game._watch_room_change()
				var planned: bool = game._transit_active() and str(game._transit.get("phase", "")) == "exit"
				var untouched: bool = game.det_pos.is_equal_approx(detective_before) and game.cam.global_transform.is_equal_approx(camera_before) and game.eng.save_dict() == rules_before
				var saved: bool = planned and untouched and game.checkpoints.save_now(pretransit_snapshot)
				pretransit_captured = true
				print("[DEV DIAGNOSTIC] PRETRANSIT_SNAPSHOT " + JSON.stringify({"saved":saved, "planned":planned, "detective_camera_rules_unchanged":untouched,
					"from":pretransit_from, "to":pretransit_to, "detective":[game.det_pos.x,game.det_pos.y],
					"path_points":game.det_path.size(), "explicit_watcher_before_next_frame":true,
					"path":pretransit_snapshot if saved else "", "error":str(game.checkpoints.error), "acceptance_eligible":false}))
				_check(saved, "开发过门首次移动前快照已保存")

	_check(asked_kitchen, "开发输入已从走廊请求进入 B-P")
	_check(seeded_kitchen, "厨房专属探索已实际启动")
	_check(replay_done, "首题复演接入原厨房组件")
	_check(handled_ded.size() == 5, "第一天五项推演均完成 (%d/5)" % handled_ded.size())
	_check(handled_conflict.size() == 6, "第一天六项争执均完成 (%d/6)" % handled_conflict.size())
	_check(handled_choice, "黑板诗主流程抉择已处理")
	_check(reached_plan and bool(game.eng.s.flags.get("day2_plan", false)), "主流程抵达 d1_plan 并写入翌日分工")
	for branch in ["stakeout", "expose", "indulge"]:
		_check(_poem_branch(branch), "黑板诗 %s 路线汇回 d1_institutes" % branch)

	print("RESULT fails=", fails, " beat=", game.eng.s.current_beat, " time=", game.eng.s.t, " room=", game.eng.s.room)
	await _teardown_game(game)
	call_deferred("quit", 1 if fails > 0 else 0)
