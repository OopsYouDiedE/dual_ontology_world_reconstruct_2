extends SceneTree
## 第四幕验收：从走廊主动走进 B-P 小厨房后的探索交互。
## 检查：① 无顶栏 / 左卡 / 抽屉，7 个宝石证物，原版光柱被隐藏  ② 侦探从门口走进来
##       ③ WASD 按镜头方向（含 az 被右键拖动改变之后）  ④ 台词在播时仍可移动
##       ⑤ 顶着家具 / 墙会滑行而不是粘住  ⑥ 靠近按 E / 点击走近后取得证物  ⑦ Esc 切换完整界面
## 用法：xvfb-run -a godot --path . --rendering-driver opengl3 -s tools/test/kitchen_flow.gd -- out=/tmp/shots/kf scale=4.0
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
	if DisplayServer.get_name() == "headless":
		print("shot skipped (headless renderer): ", tag)
		return
	var texture := root.get_texture()
	var image: Image = texture.get_image() if texture != null else null
	if image == null:
		print("shot skipped (headless renderer): ", tag)
		return
	image.save_png("%s_%s.png" % [out, tag])
	print("shot ", tag)

func _hold(action: String, ms: int) -> void:
	Input.action_press(action)
	var t := Time.get_ticks_msec()
	while Time.get_ticks_msec() - t < ms: await process_frame
	Input.action_release(action)
	await process_frame

func _put(m, c: Vector2i) -> void:
	m.det_pos = Vector2((c.x + 0.5) * m.CELL, (c.y + 0.5) * m.CELL)
	m.det.position = Vector3(m.det_pos.x, 0.0, m.det_pos.y)
	m.det_path.clear()

func _free_cell(m, c: Vector2i) -> bool:
	return m._grid.is_in_boundsv(c) and not m._grid.is_point_solid(c)

## 周围 r 格内全是通畅地面、且 r 最大的一格（取最靠中间的）
func _open_cell(m, r: int) -> Vector2i:
	var best := Vector2i(-1, -1)
	var best_d := 1e9
	var reg: Rect2i = m._grid.region
	var mid := Vector2(reg.size.x * 0.5, reg.size.y * 0.5)
	for x in reg.size.x:
		for y in reg.size.y:
			var ok := true
			for dx in range(-r, r + 1):
				for dy in range(-r, r + 1):
					if not _free_cell(m, Vector2i(x + dx, y + dy)): ok = false
			if ok and Vector2(x, y).distance_to(mid) < best_d:
				best_d = Vector2(x, y).distance_to(mid)
				best = Vector2i(x, y)
	return best

## 北（z-）面紧贴障碍，东面连续 4 格通畅，西面也通畅
func _wall_cell(m) -> Vector2i:
	var reg: Rect2i = m._grid.region
	for y in range(1, reg.size.y):
		for x in range(2, reg.size.x - 6):
			var c := Vector2i(x, y)
			if not _free_cell(m, c) or _free_cell(m, c + Vector2i(0, -1)): continue
			var ok := true
			for k in range(0, 6):
				if not _free_cell(m, c + Vector2i(k, 0)) or _free_cell(m, c + Vector2i(k, -1)): ok = false
			if ok: return c
	return Vector2i(-1, -1)

## 按住 action，以固定步长 0.1 秒调用 n 次移动逻辑（与帧率、time_scale 无关）
func _step(m, action: String, n: int) -> void:
	Input.action_press(action)
	for i in n: m._manual_move_step(0.1)
	Input.action_release(action)

func _wait_quiet(m, max_s := 30.0) -> void:
	var t0 := Time.get_ticks_msec()
	while (m.subtitle.visible or not m._sub_queue.is_empty()) and Time.get_ticks_msec() - t0 < max_s * 1000.0:
		m._sub_until = 0.0
		await process_frame
	for i in 6: await process_frame

func _initialize() -> void:
	var out := _arg("out", "/tmp/shots/kf")
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
	await _wait_quiet(m)
	for i in g._items.size():
		if str(g._items[i].id) == "kitchen":
			g.interact(i)
			break
	var tk := Time.get_ticks_msec()
	while m.gathering != null and Time.get_ticks_msec() - tk < 60000:
		m._sub_until = 0.0
		await process_frame
	var k = m.kitchen
	_check(k != null and k.active and str(m.eng.s.room) == "B-P", "进入 B-P 后厨房探索接管")
	_check(not m.top_bar.visible and not m.left_card.visible and not m.drawer.visible and not m.room_hint.visible, "无顶栏 / 左卡 / 案卷抽屉")
	_check(k._items.size() == 7, "7 个宝石证物 (%d)" % k._items.size())
	var pillars_hidden := true
	for eid in m.room_mesh.evidence_nodes:
		var mk = m.room_mesh.evidence_nodes[eid].get_node_or_null("Marker")
		if mk != null and mk.visible: pillars_hidden = false
	_check(pillars_hidden, "原版黄色光柱已隐藏")
	_check(k.phase == "enter", "侦探先从门口走进来 (phase=%s)" % k.phase)
	var tw := Time.get_ticks_msec()
	while k.phase != "free" and Time.get_ticks_msec() - tw < 20000:
		m._sub_until = 0.0
		await process_frame
	_check(k.phase == "free", "走进门后进入自由阶段")
	await _wait_quiet(m)
	await _shot(out, "01_enter_free")

	# ③ 按镜头方向移动：在房间里最空旷的地方，W 应沿屏幕「上」走，D 沿屏幕「右」走；换 az 之后依旧成立
	var open_cell := Vector2i(-1, -1)
	for r in [4, 3, 2]:
		open_cell = _open_cell(m, r)
		if open_cell.x >= 0:
			print("  空旷半径 %d 格" % r)
			break
	_check(open_cell.x >= 0, "找到空旷地面 (cell %s)" % str(open_cell))
	for az_test in [0.12, 0.9, -0.7, 2.2]:
		m.az = az_test
		m._update_camera()
		for pair in [["move_up", Vector2(-sin(az_test), -cos(az_test)), "W"], ["move_right", Vector2(cos(az_test), -sin(az_test)), "D"],
				["move_down", Vector2(sin(az_test), cos(az_test)), "S"], ["move_left", Vector2(-cos(az_test), sin(az_test)), "A"]]:
			_put(m, open_cell)
			var p0: Vector2 = m.det_pos
			_step(m, pair[0], 2)
			var d: Vector2 = m.det_pos - p0
			_check(d.length() > 0.4 and d.normalized().dot(pair[1]) > 0.98, "az=%.2f：%s 沿屏幕方向 (dot=%.2f, 位移 %.2f)" % [az_test, pair[2], d.normalized().dot(pair[1]) if d.length() > 0.001 else 0.0, d.length()])
	m.az = 0.12
	m._update_camera()

	# ④ 台词在播时也能走
	_put(m, open_cell)
	m.eng.say("detective", "测试台词：边说边走。", "think")
	for i in 3: await process_frame
	var talking: bool = m.subtitle.visible
	var q0: Vector2 = m.det_pos
	_step(m, "move_right", 2)
	_check(talking and m.det_pos.distance_to(q0) > 0.4, "台词在播时 WASD 仍可移动 (talking=%s, 位移 %.2f)" % [talking, m.det_pos.distance_to(q0)])
	await _wait_quiet(m)

	# ⑤ 顶着墙 / 家具斜着走：找一格「北面是障碍、东面通畅」的地面，az=0 时按 W+D 应沿障碍向东滑
	var wc := _wall_cell(m)
	_check(wc.x >= 0, "找到贴障碍的地面 (cell %s)" % str(wc))
	m.az = 0.0
	m._update_camera()
	_put(m, wc)
	var s0: Vector2 = m.det_pos
	Input.action_press("move_up")
	Input.action_press("move_right")
	for i in 5: m._manual_move_step(0.1)
	Input.action_release("move_up")
	Input.action_release("move_right")
	_check(m.det_pos.x > s0.x + 0.4 and absf(m.det_pos.y - s0.y) < 0.05, "斜向顶障碍时沿边滑行 (x %.2f → %.2f, z %.2f → %.2f)" % [s0.x, m.det_pos.x, s0.y, m.det_pos.y])

	# ⑥ 互动：传到某证物旁按 E → 取得证物
	var it0: Dictionary = k._items[0]
	var tp: Vector3 = it0.pos
	var cell: Vector2i = m._nearest_free(m._cell_of(Vector2(tp.x + 0.5, tp.z + 0.5)))
	m.det_pos = Vector2((cell.x + 0.5) * m.CELL, (cell.y + 0.5) * m.CELL)
	m.det.position = Vector3(m.det_pos.x, 0.0, m.det_pos.y)
	for i in 6: await process_frame
	await _shot(out, "02_near_item")
	var n0: int = m.eng.s.evidence.size()
	k.interact_nearest()
	for i in 20: await process_frame
	_check(m.eng.s.evidence.has(str(it0.id)) and m.eng.s.evidence.size() == n0 + 1, "靠近按 E 取得证物「%s」" % str(it0.label))
	await _wait_quiet(m)

	# 点击走近：把鼠标位置投影到第二个宝石上
	var it1: Dictionary = k._items[3]
	var sp: Vector2 = (m.cam as Camera3D).unproject_position((it1.marker as Node3D).global_position)
	var handled: bool = k.handle_click(sp)
	_check(handled and k._busy_item >= 0, "点击宝石 → 侦探走过去")
	var tc := Time.get_ticks_msec()
	while not m.eng.s.evidence.has(str(it1.id)) and Time.get_ticks_msec() - tc < 30000:
		m._sub_until = 0.0
		await process_frame
	_check(m.eng.s.evidence.has(str(it1.id)), "走到跟前后取得证物「%s」" % str(it1.label))
	await _wait_quiet(m)
	await _shot(out, "03_after_click")

	# ⑦ Esc 切换完整界面
	k.toggle_chrome()
	_check(m.top_bar.visible and m.left_card.visible, "Esc 唤出完整界面")
	await _shot(out, "04_chrome")
	k.toggle_chrome()
	_check(not m.top_bar.visible and not m.left_card.visible, "Esc 再次收起")

	print("RESULT fails=", fails)
	quit(1 if fails > 0 else 0)
