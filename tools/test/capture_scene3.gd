extends SceneTree
## 第三幕验收：走廊对账结束后进入自由活动。
## 检查：① 没有顶栏 / 左卡 / 右侧案卷抽屉  ② 不会被自动送进厨房  ③ 他人的门锁着、只有 R05 是开的
##       ④ 走近物件按 E 出台词  ⑤ 玩家主动互动厨房拱门才进 B-P。
## 用法：xvfb-run -a godot --path . --rendering-driver opengl3 -s tools/test/capture_scene3.gd -- out=/tmp/shots/s3 scale=4.0
const Main := preload("res://scenes/dual_world/DualWorldMain.tscn")

var fails := 0

func _arg(k: String, d: String) -> String:
	for a in OS.get_cmdline_user_args():
		if str(a).begins_with(k + "="): return str(a).substr(k.length() + 1)
	return d

func _check(ok: bool, msg: String) -> void:
	print(("PASS  " if ok else "FAIL  ") + msg)
	if not ok: fails += 1

func _shot(out: String, tag: String) -> void:
	for i in 10: await process_frame
	root.get_texture().get_image().save_png("%s_%s.png" % [out, tag])
	print("shot ", tag)

func _idx(g, id: String) -> int:
	for i in g._items.size():
		if str(g._items[i].id) == id: return i
	return -1

func _wait_quiet(m, max_s := 40.0) -> void:
	var t0 := Time.get_ticks_msec()
	while (m.subtitle.visible or not m._sub_queue.is_empty()) and Time.get_ticks_msec() - t0 < max_s * 1000.0:
		m._sub_until = 0.0
		await process_frame
	for i in 6: await process_frame

func _initialize() -> void:
	var out := _arg("out", "/tmp/shots/s3")
	Engine.time_scale = float(_arg("scale", "4.0"))
	var m = Main.instantiate()
	m.show_intro = false
	root.add_child(m)
	for i in 12: await process_frame
	m.eng.s.t = 440.0
	m.det.set_pose("stand")
	m.start_gathering("B-P")
	var g = m.gathering
	var t0 := Time.get_ticks_msec()
	while g.phase != "free" and Time.get_ticks_msec() - t0 < 120000:
		m._sub_until = 0.0 if (m.subtitle.visible and g.phase == "talk") else m._sub_until
		await process_frame
	_check(g.phase == "free", "对账结束后进入第三幕自由活动 (phase=%s)" % g.phase)
	await _wait_quiet(m)
	await _shot(out, "01_free_start")
	_check(not m.top_bar.visible and not m.left_card.visible and not m.drawer.visible and not m.room_hint.visible, "无顶栏 / 左卡 / 右侧案卷抽屉")
	# 空等 8 秒（真实时间）：不会被自动送进厨房
	var w0 := Time.get_ticks_msec()
	while Time.get_ticks_msec() - w0 < 8000: await process_frame
	_check(m.gathering != null and m.gathering.active and str(m.eng.s.room) == "R05", "闲置 8 秒仍在走廊，没有被强制进厨房 (room=%s)" % str(m.eng.s.room))

	# 锁着的门：试 R06
	var i06 := _idx(g, "door_r06")
	g.interact(i06)
	for k in 400:
		await process_frame
		if m.subtitle.visible: break
	_check(m.subtitle.visible and "锁" in m.subtitle.text, "R06 门锁着：%s" % m.subtitle.text.left(26))
	await _shot(out, "02_locked_r06")
	await _wait_quiet(m)

	# 自己的门
	g.interact(_idx(g, "door_r05"))
	for k in 400:
		await process_frame
		if m.subtitle.visible: break
	_check(m.subtitle.visible and "钥匙" in m.subtitle.text, "R05 是自己的门，钥匙打得开：%s" % m.subtitle.text.left(26))
	await _shot(out, "03_own_door")
	await _wait_quiet(m)

	# 同伴
	g.interact(_idx(g, "npc_shen"))
	for k in 400:
		await process_frame
		if m.subtitle.visible: break
	_check(m.subtitle.visible, "与沈鼎互动：%s" % m.subtitle.text.left(20))
	await _shot(out, "04_npc")
	await _wait_quiet(m)

	# WASD 移动与边界
	var x0: float = m.det_pos.x
	Input.action_press("move_right")
	var tw := Time.get_ticks_msec()
	while Time.get_ticks_msec() - tw < 1500: await process_frame
	Input.action_release("move_right")
	_check(m.det_pos.x > x0 + 0.5, "WASD 可移动 (x %.2f → %.2f)" % [x0, m.det_pos.x])
	Input.action_press("move_up")
	tw = Time.get_ticks_msec()
	while Time.get_ticks_msec() - tw < 1500: await process_frame
	Input.action_release("move_up")
	_check(m.det_pos.y >= g.FREE_BOUNDS.position.y - 0.001, "走廊北墙挡得住 (z=%.2f)" % m.det_pos.y)
	await _shot(out, "05_walked")

	# 主动进厨房
	g.interact(_idx(g, "kitchen"))
	var tk := Time.get_ticks_msec()
	while m.gathering != null and Time.get_ticks_msec() - tk < 60000:
		m._sub_until = 0.0
		await process_frame
	for i in 40: await process_frame
	_check(m.gathering == null and str(m.eng.s.room) == "B-P", "玩家主动互动厨房拱门后才进入 B-P (room=%s)" % str(m.eng.s.room))
	await _shot(out, "06_kitchen_by_choice")
	print("RESULT fails=", fails)
	quit(1 if fails > 0 else 0)
