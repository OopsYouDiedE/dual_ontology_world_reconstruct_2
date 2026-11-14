extends Node
## 第二幕：走出寝室门 → 乙区走廊 → 听见人声 → 加入对话圈 → 快速对账 → 商定下一步 → 进小厨房。
##
## 设计取舍（走廊 vs. 直接闯进厨房）：
##   · B-P 的 Lowpoly 房间是 11×5.2 米的带灶小厨房，只有一扇门，不是走廊；R05 的门原先直接开进厨房，
##     侦探一出门就「瞬移」到所有人面前。这里补上走廊：侦探先在走廊里听到东端传来的低声对账，
##     再走过去加入，比「推门看见所有人」更符合他是「最后醒的人」。
##   · 站位参照《模拟人生》的对话圈：参与者朝向圈心，圈子永远留一个开口给后来者；后来者靠近时，
##     圈内的人先转头看他，入列后全体重新均分角度（0.9 秒平滑），说话者做手势，其余人站定。
##   · 走廊是程序化生成的舞台（不动 36 个 Lowpoly 房间资源）；时间冻结，台词由 DualEngine.say 推进，
##     空格 / 回车可跳过字幕。结束后把引擎房间切到 B-P，接上原有「乙区小厨房 · 摊开笔记」推演节拍。

const Figure := preload("res://scenes/dual_world/ProceduralFigure.gd")

const LEN := 20.0            # 走廊长度（x）
const DEPTH := 3.4           # 走廊进深（z，+z 朝向镜头）
const WALK := 2.6
const DOORS := [["R05", "侦探", 3.0], ["R06", "霍铎", 7.0], ["R07", "沈鼎", 11.0], ["R08", "苏泠", 15.0]]
const CIRCLE := Vector2(16.9, 1.95)
const R3 := 0.95             # 三人弧半径（给侦探留开口）
const R4 := 1.1              # 四人圈半径
# 角度：atan2(z, x)，+z 朝镜头。开口朝西（侦探从西边来）。
const ANG3 := {"huo": 255.0, "shen": 330.0, "su": 28.0}
const ANG4 := {"huo": 238.0, "shen": 312.0, "su": 12.0, "detective": 150.0}

const LINES := [
	["huo", "来了。你是我们当中最后一个醒的——我们先快速对一遍，你听着，有出入就打断。"],
	["su", "我先说。天亮前我被「开门」两个字惊醒，可我分不清是门外有人喊，还是屋里有人喊。琴上的高音弦断了，断口很新。"],
	["huo", "乙区的门我看过：棘轮是反扣的，门轴上有新咬痕。从里面扣上，外面的人就拉不开。机械不会撒谎，人会。"],
	["shen", "我只记得往门缝塞了一块湿布。可它现在挂在灶边的钩子上，还在滴水。要么我记错了，要么有人动过。"],
	["detective", "我这边：醒在 R05，门没被撬，笔记本最后一页只写了半行，字抖得厉害。手背上三道抓痕——我不知道是谁留下的。", "think"],
	["huo", "也就是说，到现在四个人手里的东西互相对不上：拖痕朝内、布挂在钩上、门被反扣、你手上有伤。"],
	["su", "还有，听说四区的外闩昨晚都被人拨过。甲区那边的沃德、雀儿、卢西安，想必也在对账。"],
	["detective", "先别下结论。三步：一，进小厨房，把门槛、拖痕、湿布按原位摆一遍，先排顺序；二，霍铎留在门上，拿棘轮咬痕去比拖痕；三，乙区对完，再去甲区找他们换口供。"],
	["shen", "热水我来烧，伤员和忙人总得有口热的。但你们谁都别碰灶边那块布。"],
	["huo", "同意。谁的话跟痕迹对不上，就当场指出来，不记仇。"],
	["su", "我只有一个条件：我听到的那句「开门」，别急着替我定性。"],
	["detective", "好。先进厨房。", "think"],
]

var host: Control
var active := false
var phase := "off"
var _pt := 0.0
var _clock := 0.0
var _root: Node3D
var _npc: Dictionary = {}          # id -> Figure
var _ang: Dictionary = {}          # id -> 当前角度（度）
var _ang_goal: Dictionary = {}
var _radius := R3
var _line := 0
var _card: PanelContainer
var _focus := Vector3(4.0, 0.7, 1.6)
var _az := 0.15
var _pitch := 0.9
var _dist := 6.2
var _target := ""
var _lights: Array = []
var _to_room := "B-P"
var _joined := false
var _saved_visible := true
var _sun_was_on := true


func begin(h: Control, to_room: String) -> void:
	host = h
	_to_room = to_room
	active = true
	phase = "fadeout"
	host._cine = true
	host.eng.s.playing = false
	host.top_bar.visible = false
	host.left_card.visible = false
	host.room_hint.visible = false
	host.drawer.visible = false
	host._fade(1.0, 0.3, _setup_stage)


# ───────────────────────── 舞台 ─────────────────────────
func _setup_stage() -> void:
	_saved_visible = host.room_mesh.visible
	_sun_was_on = host.sun.visible
	host.sun.visible = false            # 走廊是室内：关掉昼夜系统的直射阳光，只用自己的灯
	host.room_mesh.visible = false
	host.figures_root.visible = false
	_root = Node3D.new()
	_root.name = "CorridorStage"
	host.det_root.get_parent().add_child(_root)
	_build_corridor()
	for id in ["huo", "shen", "su"]:
		var f: Node3D = Figure.new()
		f.setup(host.data.actor_by_id[id], host.data.rig_spec.get("poses", {}))
		_root.add_child(f)
		host.figures[id] = f
		_npc[id] = f
		_ang[id] = float(ANG3[id])
		_ang_goal[id] = float(ANG3[id])
		var tag := Label3D.new()
		tag.text = str(host.data.actor_by_id[id].name)
		tag.font = host.SANS_FONT
		tag.font_size = 40
		tag.pixel_size = 0.005
		tag.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		tag.position = Vector3(0, float(host.data.actor_by_id[id].look.height) + 0.28, 0)
		tag.modulate = Color(str(host.data.actor_by_id[id].color)).lightened(0.55)
		tag.outline_size = 8
		tag.no_depth_test = true
		f.add_child(tag)
	_place_npcs(true)
	# 侦探从 R05 的门里走出来
	host.det_pos = Vector2(DOORS[0][2], -0.35)
	host.det.position = Vector3(host.det_pos.x, 0.0, host.det_pos.y)
	host.det.rotation.y = 0.0
	host.det.set_pose("stand")
	host.det_path.clear()
	host.det_done = Callable()
	host._wake_timer = 0.0
	_focus = Vector3(5.0, 0.8, 1.7)
	_az = 0.12
	_pitch = 1.0
	_dist = 7.6
	_apply_camera()
	phase = "exit"
	_pt = 0.0
	host._fade(0.0, 0.5)


func _mat(c: Color, emit := 0.0) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = 0.9
	if emit > 0.0:
		m.emission_enabled = true
		m.emission = c
		m.emission_energy_multiplier = emit
	return m


func _box(pos: Vector3, size: Vector3, c: Color, emit := 0.0) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.material_override = _mat(c, emit)
	mi.position = pos
	_root.add_child(mi)
	return mi


func _label(text: String, pos: Vector3, size := 0.0045, c := Color("#ffe3a3")) -> void:
	var t := Label3D.new()
	t.text = text
	t.font = host.SANS_FONT
	t.font_size = 44
	t.pixel_size = size
	t.position = pos
	t.modulate = c
	t.outline_size = 10
	_root.add_child(t)


func _build_corridor() -> void:
	# 地板：木拼 + 长条地毯
	_box(Vector3(LEN * 0.5, -0.06, DEPTH * 0.5), Vector3(LEN + 1.2, 0.12, DEPTH + 0.4), Color("#5d4430"))
	_box(Vector3(LEN * 0.5, 0.005, DEPTH * 0.5), Vector3(LEN - 0.6, 0.02, 1.25), Color("#6b2f2a"))
	_box(Vector3(LEN * 0.5, 0.012, DEPTH * 0.5), Vector3(LEN - 0.6, 0.01, 0.12), Color("#c2a35b"))
	# 北墙（带门）、西端墙、东端拱门、南侧矮墙（剖面，镜头一侧）
	_box(Vector3(LEN * 0.5, 1.5, -0.12), Vector3(LEN + 0.4, 3.0, 0.24), Color("#8f785a"))
	_box(Vector3(LEN * 0.5, 0.14, 0.02), Vector3(LEN, 0.28, 0.06), Color("#4a3426"))        # 踢脚线
	_box(Vector3(-0.12, 1.5, DEPTH * 0.5), Vector3(0.24, 3.0, DEPTH + 0.4), Color("#85704f"))
	_box(Vector3(LEN + 0.12, 1.5, 0.45), Vector3(0.24, 3.0, 0.9), Color("#85704f"))
	_box(Vector3(LEN + 0.12, 1.5, DEPTH - 0.45), Vector3(0.24, 3.0, 0.9), Color("#85704f"))
	_box(Vector3(LEN + 0.12, 2.65, DEPTH * 0.5), Vector3(0.24, 0.7, DEPTH), Color("#85704f"))
	_box(Vector3(LEN + 0.55, 1.1, DEPTH * 0.5), Vector3(0.1, 2.2, DEPTH - 0.9), Color("#ffb347"), 1.5)  # 厨房暖光
	_box(Vector3(LEN * 0.5, 0.22, DEPTH + 0.14), Vector3(LEN + 0.4, 0.44, 0.2), Color("#6b5238"))
	_label("乙区小厨房  →", Vector3(LEN - 0.4, 2.35, DEPTH * 0.5), 0.005, Color("#ffd98a"))
	_label("乙区大门（上锁）", Vector3(0.7, 2.35, 0.2), 0.0038, Color("#c9b99a"))
	# 寝室门：深色门框 + 门扇，R05 刚被推开
	for d in DOORS:
		var x: float = d[2]
		_box(Vector3(x, 1.1, 0.03), Vector3(1.15, 2.2, 0.1), Color("#2a1d14"))
		_box(Vector3(x, 2.28, 0.0), Vector3(1.35, 0.14, 0.2), Color("#5a4129"))
		var leaf := _box(Vector3(x - 0.45, 1.05, 0.5), Vector3(0.08, 2.05, 0.85), Color("#6b4a2e"))
		leaf.rotation.y = deg_to_rad(-62.0 if str(d[0]) in ["R05", "R06", "R07"] else -8.0)
		_label("%s · %s" % [d[0], d[1]], Vector3(x, 2.6, 0.2), 0.0042)
	# 门间：窗（晨光）、长凳、盆栽，让走廊不空
	for wx in [5.0, 9.0, 13.0]:
		_box(Vector3(wx, 1.7, 0.03), Vector3(0.9, 0.9, 0.06), Color("#b9d0e0"), 0.45)
	_box(Vector3(9.0, 0.28, 0.45), Vector3(1.5, 0.12, 0.42), Color("#5a3d26"))
	_box(Vector3(8.4, 0.12, 0.45), Vector3(0.1, 0.24, 0.36), Color("#3b2819"))
	_box(Vector3(9.6, 0.12, 0.45), Vector3(0.1, 0.24, 0.36), Color("#3b2819"))
	_box(Vector3(13.0, 0.3, 0.4), Vector3(0.42, 0.6, 0.42), Color("#7b5a3a"))
	_box(Vector3(13.0, 0.78, 0.4), Vector3(0.5, 0.36, 0.5), Color("#4f7a45"))
	# 灯：三盏暖色顶灯 + 厨房方向的暖光 + 窗口晨光
	for lx in [4.0, 10.0, 16.0]:
		var l := OmniLight3D.new()
		l.position = Vector3(lx, 2.6, DEPTH * 0.5)
		l.light_color = Color("#ffd9a0")
		l.light_energy = 1.6
		l.omni_range = 9.0
		l.shadow_enabled = false
		_root.add_child(l)
		_lights.append(l)
		_box(Vector3(lx, 2.92, DEPTH * 0.5), Vector3(0.5, 0.08, 0.5), Color("#ffe6b0"), 2.0)
	var kl := OmniLight3D.new()
	kl.position = Vector3(LEN - 0.6, 1.4, DEPTH * 0.5)
	kl.light_color = Color("#ff9d3c")
	kl.light_energy = 2.2
	kl.omni_range = 6.0
	_root.add_child(kl)
	_lights.append(kl)


# ───────────────────────── 站位 ─────────────────────────
func _slot(ang_deg: float, r: float) -> Vector2:
	return CIRCLE + Vector2(cos(deg_to_rad(ang_deg)), sin(deg_to_rad(ang_deg))) * r


func _face(node: Node3D, at: Vector2, delta: float, rate := 8.0) -> void:
	var p := Vector2(node.position.x, node.position.z)
	var to := at - p
	if to.length() < 0.01: return
	node.rotation.y = lerp_angle(node.rotation.y, atan2(to.x, to.y), 1.0 - exp(-delta * rate))


func _place_npcs(snap: bool, delta := 0.0) -> void:
	for id in _npc:
		_ang[id] = float(_ang[id]) if snap else lerpf(float(_ang[id]), float(_ang_goal[id]), 1.0 - exp(-delta * 4.0))
		var sp := _slot(float(_ang[id]), _radius)
		var f: Node3D = _npc[id]
		f.position = Vector3(sp.x, 0.0, sp.y)
		if snap:
			_face(f, CIRCLE, 1.0, 100.0)


# ───────────────────────── 每帧 ─────────────────────────
func process(delta: float) -> void:
	if not active or _root == null: return
	_clock += delta
	_pt += delta
	var det: Node3D = host.det
	var talking: bool = host.subtitle.visible or not host._sub_queue.is_empty()
	match phase:
		"exit":
			# 出门、转向东边：停一拍，先听见人声
			var goal := Vector2(DOORS[0][2], 1.95)
			if host.det_pos.distance_to(goal) > 0.05:
				_walk_to(goal, delta)
			else:
				det.rotation.y = lerp_angle(det.rotation.y, PI * 0.5, 1.0 - exp(-delta * 6.0))
				if _pt > 1.2 and not talking:
					host.eng.say("detective", "走廊那头有人声。不是争吵——是有人压着嗓子在对账。", "think")
					phase = "hear"
					_pt = 0.0
		"hear":
			det.set_pose("stand")
			det.rotation.y = lerp_angle(det.rotation.y, PI * 0.5, 1.0 - exp(-delta * 6.0))
			if not talking and _pt > 0.6: phase = "approach"
		"approach":
			var goal2 := _slot(150.0, R4)
			var d2: float = host.det_pos.distance_to(goal2)
			if d2 > 0.06:
				_walk_to(goal2, delta)
				# 对话圈里的人先注意到来人：转头看他
				if host.det_pos.distance_to(CIRCLE) < 6.5: _target = "det"
			else:
				_join()
		"join":
			det.set_pose("stand")
			_face(det, CIRCLE, delta)
			if _pt > 1.0: _next_line()
		"talk":
			_face(det, CIRCLE, delta, 6.0)
			if not talking:
				if _line < LINES.size(): _next_line()
				else:
					phase = "card"
					_pt = 0.0
					_show_card()
		"card":
			if _pt > 5.5: _finish()
		"out":
			pass
	for id in _npc:
		var f: Node3D = _npc[id]
		if _target == "det" and not _joined: _face(f, host.det_pos, delta, 5.0)
		else: _face(f, _look_target(id), delta, 5.0)
	if phase in ["join", "talk", "card"]:
		_place_npcs(false, delta)
	_camera_drive(delta)


func _look_target(id: String) -> Vector2:
	# 说话者所在的人 → 其余人看他；其余时间看圈心
	var who: String = host._speaker
	if host.subtitle.visible and who != id:
		if who == "detective": return host.det_pos
		if _npc.has(who):
			var n: Node3D = _npc[who]
			return Vector2(n.position.x, n.position.z)
	return CIRCLE


func _walk_to(goal: Vector2, delta: float) -> void:
	var det: Node3D = host.det
	var dv: Vector2 = goal - host.det_pos
	var l := dv.length()
	var step := WALK * delta
	det.rotation.y = lerp_angle(det.rotation.y, atan2(dv.x, dv.y), 1.0 - exp(-delta * 10.0))
	if l <= step: host.det_pos = goal
	else: host.det_pos += dv / l * step
	det.position = Vector3(host.det_pos.x, 0.0, host.det_pos.y)
	det.set_pose("walk" if host.det_pos.distance_to(goal) > 0.05 else "stand")


func _join() -> void:
	_joined = true
	_target = ""
	host.det.set_pose("stand")
	_radius = R4
	for id in ANG4:
		if id != "detective": _ang_goal[id] = float(ANG4[id])
	phase = "join"
	_pt = 0.0


func _next_line() -> void:
	if _line >= LINES.size(): return
	var ln: Array = LINES[_line]
	_line += 1
	host.eng.say(str(ln[0]), str(ln[1]), str(ln[2]) if ln.size() > 2 else "")
	phase = "talk"


# ───────────────────────── 镜头 ─────────────────────────
func _camera_drive(delta: float) -> void:
	var g_focus := _focus
	var g_az := _az
	var g_pitch := _pitch
	var g_dist := _dist
	match phase:
		"exit", "hear":
			g_focus = Vector3(host.det_pos.x + 1.8, 0.8, 1.7)
			g_az = 0.12
			g_pitch = 1.0
			g_dist = 7.4
		"approach":
			g_focus = Vector3(lerpf(host.det_pos.x, CIRCLE.x, 0.55), 0.8, 1.8)
			g_az = 0.22
			g_pitch = 0.92
			g_dist = 6.4
		_:
			g_focus = Vector3(CIRCLE.x - 0.35, 0.75, CIRCLE.y)
			g_az = 0.5
			g_pitch = 0.88
			g_dist = 5.0
	var k := 1.0 - exp(-delta * 2.2)
	_focus = _focus.lerp(g_focus, k)
	_az = lerpf(_az, g_az, k)
	_pitch = lerpf(_pitch, g_pitch, k)
	_dist = lerpf(_dist, g_dist, k)
	_apply_camera()


func _apply_camera() -> void:
	var dir := Vector3(sin(_az) * cos(_pitch), sin(_pitch), cos(_az) * cos(_pitch))
	host.cam.position = _focus + dir * _dist
	host.cam.look_at(_focus, Vector3.UP)


# ───────────────────────── 对账小结卡 ─────────────────────────
func _show_card() -> void:
	_card = PanelContainer.new()
	_card.add_theme_stylebox_override("panel", host._style(Color(0.07, 0.055, 0.04, 0.9), host.BRASS, 10, 14))
	var l := Label.new()
	l.text = "对账小结\n\n已对上　门被反扣（霍铎）· 拖痕朝内 · 湿布挂在钩上（沈鼎）\n对不上　「开门」是谁喊的（苏泠）· 你手背上的抓痕\n下一步　① 小厨房按原位摆顺序　② 棘轮咬痕比拖痕　③ 乙区对完去甲区"
	l.add_theme_font_size_override("font_size", 17)
	l.add_theme_color_override("font_color", Color("#f2e6c8"))
	_card.add_child(l)
	_card.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	_card.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_card.offset_top = 40
	_card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	host.center.add_child(_card)


# ───────────────────────── 收尾：进厨房，接回原节拍 ─────────────────────────
func _finish() -> void:
	if phase == "out": return
	phase = "out"
	host._fade(1.0, 0.35, _swap_to_room)


func _swap_to_room() -> void:
	if _card != null: _card.queue_free()
	for id in _npc: host.figures.erase(id)
	if _root != null: _root.queue_free()
	host.room_mesh.visible = true
	host.sun.visible = _sun_was_on
	host.figures_root.visible = true
	host.top_bar.visible = true
	host.left_card.visible = true
	host.room_hint.visible = true
	host.eng.enter_room(_to_room)
	host._build_room(_to_room)   # 同步建好 B-P，避免 _watch_room_change 再演一遍 R05 的走出动画
	host._det_to_home()
	host.pitch = 1.25
	host._fit_camera()
	host._cine = false
	host.eng.s.playing = true
	host.gathering = null
	active = false
	host._fade(0.0, 0.4)
	queue_free()
