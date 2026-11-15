extends SceneTree
const CaptureReceipt := preload("res://mcp/CaptureReceipt.gd")
## 开发回归截图（直接设置前置状态）：厨房首题收齐四件线索后进入角色动作复演，并可排列、确认时间顺序。
## 用法：godot --path . -s tools/test/kitchen_order_replay.gd -- out=.runtime/screens/order/replay.png
const Main := preload("res://scenes/dual_world/DualWorldMain.tscn")
const REQUIRED := ["e_b_sleeve", "e_b_drag", "e_b_water", "e_b_ratchet"]

var fails := 0

func _arg(k: String, d: String) -> String:
	for a in OS.get_cmdline_user_args():
		if str(a).begins_with(k + "="): return str(a).substr(k.length() + 1)
	return d

func _check(ok: bool, msg: String) -> void:
	print(("PASS  " if ok else "FAIL  ") + msg)
	if not ok: fails += 1

func _shot(path: String) -> void:
	if DisplayServer.get_name() == "headless":
		print("shot skipped (headless renderer)")
		return
	for i in 12: await process_frame
	var image := root.get_texture().get_image()
	if not CaptureReceipt.save(image, path, self): quit(1); return
	print("shot ", path)

func _initialize() -> void:
	Engine.time_scale = 2.0
	var m = Main.instantiate()
	m.show_intro = false
	root.add_child(m)
	for i in 10: await process_frame

	# 直接进入正式厨房房间，只跳过此前玩家已通过的走廊导航，不模拟引擎答案。
	m.eng.s.room = "B-P"
	m.eng.s.t = 470.0
	m._room_loaded = ""
	m._ensure_room()
	m._sync_figures(true)
	_check(m.room_mesh != null and str(m.eng.s.room) == "B-P", "真实 B-P 房间与角色模型已载入")
	_check(m.start_kitchen_exploration(), "厨房漫游接管")
	for i in 120:
		await process_frame
		if m.kitchen.phase == "free": break
	_check(m.kitchen.phase == "free", "门口进场动画完成，恢复自由探索")

	for evidence_id in REQUIRED:
		m.eng.inspect_evidence(evidence_id)
	m._sub_queue.clear()
	m.subtitle.visible = false
	m.eng.open_deduction("ded_drag")
	m._dirty = true
	for i in 30:
		await process_frame
		if m.kitchen._order_replay != null and m.kitchen._order_replay.active: break
	var replay = m.kitchen._order_replay
	_check(replay != null and replay.active, "四件相关证物齐后接管首个动作推演")
	_check(m.modal.visible and replay._echoes.size() == 4, "轻遮罩保留真实场景，四名动作记忆角色生成")
	var t0 := Time.get_ticks_msec()
	while replay._playing and Time.get_ticks_msec() - t0 < 20000:
		await process_frame
	_check(not replay._playing, "四段动作复演完成并可操作时间线")
	await replay._perform("su_open")
	_check(replay._echoes.su.visible, "苏泠的记忆动作可播放")
	await replay._perform("detective_pull")
	_check(replay._echoes.su.visible and replay._echoes.detective.visible, "双方以相反方向动作对峙")
	for i in 3: await process_frame
	var visible_echo := false
	for actor_id in replay._echoes:
		var echo: Node3D = replay._echoes[actor_id]
		if echo.visible: visible_echo = true
	_check(visible_echo, "动作复演的半透明角色在实景中可见")
	await _shot(_arg("out", ".runtime/screens/order/replay.png"))
	await replay._perform("huo_lock")
	var before := str(m.eng.s.deductions.get("ded_drag", ""))
	replay._confirm_order()
	_check(str(m.eng.s.deductions.get("ded_drag", "")) == before and not m.eng.s.pending_deduction.is_empty(), "错误先后不会误记结论，可继续调整")
	replay._move_card(1, -1)
	replay._move_card(2, -1)
	_check(replay._order == ["su_open", "detective_pull", "shen_cloth", "huo_lock"], "交换动作后得到现场顺序")
	replay._confirm_order()
	_check(str(m.eng.s.deductions.get("ded_drag", "")) == "solved", "正确顺序写回原推演引擎")
	_check(not m.modal.visible, "结论成立后关闭复演界面")
	m.eng.open_conflict("c_door")
	for i in 8: await process_frame
	_check(str(m.eng.s.pending_conflict) == "c_door", "正确推演自然进入原始乙区角色争辩")
	_check(m.modal.visible, "争辩仍使用主线原有对话与回应界面")
	print("RESULT fails=", fails)
	quit(1 if fails > 0 else 0)
