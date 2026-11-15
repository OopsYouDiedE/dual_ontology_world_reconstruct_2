extends Node
## 第二幕：走出寝室门 → 乙区走廊 → 听见人声 → 加入对话圈 → 快速对账 → 商定下一步。
## 第三幕：对账结束后留在走廊里自由活动（无顶栏 / 左卡 / 右侧案卷抽屉），只有侦探和几件可互动的物件。
##   · 没有任何剧情理由逼侦探去厨房：厨房拱门只是其中一个可选物件，玩家主动按 E 才会过去。
##   · 每个房间的门都带锁，侦探只能开自己的 R05；其余三扇门只能试一下把手。
##
## 设计取舍（走廊 vs. 直接闯进厨房）：
##   · B-P 的 Lowpoly 房间是 11×5.2 米的带灶小厨房，只有一扇门，不是走廊；R05 的门原先直接开进厨房，
##     侦探一出门就「瞬移」到所有人面前。这里补上走廊：侦探先在走廊里听到东端传来的低声对账，
##     再走过去加入，比「推门看见所有人」更自然。四人都失忆，只汇总各自房间里搜到的东西。
##   · 站位参照《模拟人生》的对话圈：参与者朝向圈心，圈子永远留一个开口给后来者；后来者靠近时，
##     圈内的人先转头看他，入列后全体重新均分角度（0.9 秒平滑），说话者做手势，其余人站定。
##   · 走廊是程序化生成的舞台（不动 36 个 Lowpoly 房间资源）；时间冻结，台词由 DualEngine.say 推进，
##     空格 / 回车可跳过字幕。结束后把引擎房间切到 B-P，接上原有「乙区小厨房 · 摊开笔记」推演节拍。

const Figure := preload("res://scenes/dual_world/ProceduralFigure.gd")

const LEN := 20.0            # 走廊长度（x）
const DEPTH := 3.4           # 走廊进深（z，+z 朝向镜头）
const WALK := 2.6
const DOORS := [["R05", "侦探", 3.0], ["R06", "霍铎", 7.0], ["R07", "沈鼎", 11.0], ["R08", "苏泠", 15.0]]
const OWN_DOOR := "R05"      # 侦探只有自己房间的钥匙
const FREE_BOUNDS := Rect2(0.6, 0.75, 18.6, 2.3)   # 第三幕可走区域（x, z, 宽, 深）
const NPC_BODY := 0.5        # 第三幕：与三位同伴保持的最小距离
const CIRCLE := Vector2(16.9, 1.95)
const R3 := 0.95             # 三人弧半径（给侦探留开口）
const R4 := 1.1              # 四人圈半径
# 角度：atan2(z, x)，+z 朝镜头。开口朝西（侦探从西边来）。
const ANG3 := {"huo": 255.0, "shen": 330.0, "su": 28.0}
const ANG4 := {"huo": 238.0, "shen": 312.0, "su": 12.0, "detective": 150.0}

const LINES := [
	["huo", "来了。先说一件事：我们三个醒来都一样——名字记得，可从入学那天起的事，全是空的。你呢？"],
	["detective", "一样。名字还在，入学以来的记忆没了。连这条走廊我是什么时候走过的，都说不上来。", "think"],
	["shen", "那就别凭印象说话，只说自己屋里亲眼看到的东西。我先来：袖口是湿的，还没干透。是水还是别的什么，我不知道。"],
	["su", "我的琴盒里，高音弦断了，断口很新，袖子也破了一道。可我想不起是怎么弄的——也请别急着替我解释。"],
	["huo", "我的工具箱里少了一个曲柄销，别的都在。它去了哪儿，我一点印象都没有。"],
	["detective", "我这边：门没被撬，笔记本最后一页只写了半行字，抖得厉害。手背上有三道抓痕。", "think"],
	["huo", "也就是说，昨晚发生过什么，我们谁也确定不了。能确定的只有一件事：四个人都丢了同样的东西，而且各自房里都留下了点什么。"],
	["su", "甲区那边的人……会不会也一样？没人能保证。"],
	["detective", "先别下结论。三步：一，各自把自己屋里看到的东西记下来；二，只记录，不推断；三，别人的门都锁着，谁也别硬闯，对得上再说。"],
	["shen", "那我先回自己那边，把袖口和那块湿布再看一遍。你们也各看各的，别漏。"],
	["huo", "同意。谁的话和痕迹对不上，就当场指出来，不记仇。"],
	["detective", "好。我先在走廊里转转，看看这一层到底是什么样子。", "think"],
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
# 第三幕（自由活动）
var _items: Array = []
var _hover := -1
var _busy_item := -1
var _free_t := 0.0
var _prompt: Label
var _hint: Label
var _enter_pending := false


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
		tag.outline_size = 14
		tag.outline_modulate = Color(0.04, 0.03, 0.02, 0.95)
		if id == "shen": tag.position.y += 0.24   # 三人站得近：错开名牌高度，避免互相压住
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


## 盆栽：陶盆（上宽下窄）+ 土面 + 一圈斜插的叶片，替代原先的「绿方块 + 棕方柱」。
func _plant(at: Vector3) -> void:
	var holder := Node3D.new()
	holder.position = at
	_root.add_child(holder)
	var pot := MeshInstance3D.new()
	var pm := CylinderMesh.new()
	pm.top_radius = 0.25
	pm.bottom_radius = 0.17
	pm.height = 0.5
	pm.radial_segments = 14
	pot.mesh = pm
	pot.material_override = _mat(Color("#9a5b3a"))
	pot.position = Vector3(0, 0.25, 0)
	holder.add_child(pot)
	var rim := MeshInstance3D.new()
	var rm := CylinderMesh.new()
	rm.top_radius = 0.28
	rm.bottom_radius = 0.26
	rm.height = 0.07
	rm.radial_segments = 14
	rim.mesh = rm
	rim.material_override = _mat(Color("#7d4529"))
	rim.position = Vector3(0, 0.5, 0)
	holder.add_child(rim)
	var soil := MeshInstance3D.new()
	var sm := CylinderMesh.new()
	sm.top_radius = 0.23
	sm.bottom_radius = 0.23
	sm.height = 0.03
	sm.radial_segments = 14
	soil.mesh = sm
	soil.material_override = _mat(Color("#3a2a1c"))
	soil.position = Vector3(0, 0.5, 0)
	holder.add_child(soil)
	var greens := [Color("#3f7a45"), Color("#4f8f52"), Color("#2f6a3c")]
	for i in 9:
		var ang := float(i) / 9.0 * TAU
		var leaf := MeshInstance3D.new()
		var cm := CapsuleMesh.new()
		cm.radius = 0.055
		cm.height = 0.62 + 0.1 * float(i % 3)
		cm.radial_segments = 6
		cm.rings = 2
		leaf.mesh = cm
		leaf.material_override = _mat(greens[i % 3])
		var lean := 0.42 + 0.12 * float(i % 3)
		leaf.position = Vector3(cos(ang) * 0.1, 0.84 + 0.06 * float(i % 3), sin(ang) * 0.1)
		leaf.rotation = Vector3(sin(ang) * lean, 0.0, -cos(ang) * lean)
		holder.add_child(leaf)


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
	# 区域路标不再用 3D 悬浮大字（贴在画面边缘会被斜着截断），改写进左下角 HUD 提示
	# 寝室门：深色门框 + 门扇。每个房间的门都带锁：只有侦探自己的 R05 能打开（刚被他推开），
	# 其余三扇门关紧，门扇平贴门框，装黄铜把手和红色锁牌。
	for d in DOORS:
		var x: float = d[2]
		var own: bool = str(d[0]) == OWN_DOOR
		_box(Vector3(x, 1.1, 0.03), Vector3(1.15, 2.2, 0.1), Color("#2a1d14"))
		_box(Vector3(x, 2.28, 0.0), Vector3(1.35, 0.14, 0.2), Color("#5a4129"))
		if own:
			var leaf := _box(Vector3(x - 0.45, 1.05, 0.5), Vector3(0.08, 2.05, 0.85), Color("#6b4a2e"))
			leaf.rotation.y = deg_to_rad(-62.0)
			_label("%s · %s（我的门）" % [d[0], d[1]], Vector3(x, 2.6, 0.2), 0.0042)
		else:
			_box(Vector3(x, 1.05, 0.1), Vector3(0.96, 2.05, 0.07), Color("#5f4229"))               # 关紧的门扇
			_box(Vector3(x, 1.05, 0.145), Vector3(0.62, 1.5, 0.02), Color("#6d4c30"))              # 门板嵌线
			_box(Vector3(x + 0.34, 1.0, 0.19), Vector3(0.07, 0.07, 0.12), Color("#c2a35b"), 0.3)   # 铜把手
			_box(Vector3(x + 0.34, 1.2, 0.16), Vector3(0.13, 0.22, 0.04), Color("#b83a2e"), 0.9)   # 锁牌
			_label("%s · %s（锁）" % [d[0], d[1]], Vector3(x, 2.6, 0.2), 0.0042, Color("#e0b7a8"))
	# 门间：窗（晨光）、长凳、盆栽，让走廊不空
	for wx in [5.0, 9.0, 13.0]:
		_box(Vector3(wx, 1.7, 0.03), Vector3(0.9, 0.9, 0.06), Color("#b9d0e0"), 0.45)
	_box(Vector3(9.0, 0.28, 0.45), Vector3(1.5, 0.12, 0.42), Color("#5a3d26"))
	_box(Vector3(8.4, 0.12, 0.45), Vector3(0.1, 0.24, 0.36), Color("#3b2819"))
	_box(Vector3(9.6, 0.12, 0.45), Vector3(0.1, 0.24, 0.36), Color("#3b2819"))
	_plant(Vector3(13.0, 0.0, 0.4))
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
## 读档、返回标题共用的终止路径，恢复房间原节点。
func stop() -> void:
	active = false
	phase = "off"
	for item in [_card, _prompt, _hint, _root]:
		if is_instance_valid(item):
			if item.get_parent() != null: item.get_parent().remove_child(item)
			item.queue_free()
	for id in _npc: host.figures.erase(id)
	_npc.clear()
	host.room_mesh.visible = true
	host.figures_root.visible = true
	host.sun.visible = _sun_was_on
	host._cine = false
	host._occ_key = ""


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
					host.eng.say("detective", "走廊那头有人声，压得很低。不是争吵——像是在互相确认什么。", "think")
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
			if _pt > 5.5: _enter_free()
		"free":
			_step_free(delta)
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
	if phase == "free" and not host.subtitle.visible:
		return host.det_pos if host.det_pos.distance_to(CIRCLE) < 5.0 else CIRCLE
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
		"free":
			g_focus = Vector3(clampf(host.det_pos.x + 0.8, 5.0, LEN - 4.6), 0.8, 1.7)
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
	l.text = "对账小结\n\n已对上　门被反扣（霍铎）· 拖痕朝内 · 湿布挂在钩上（沈鼎）\n对不上　「开门」是谁喊的（苏泠）· 你手背上的抓痕\n下一步　① 各自复查自己的屋子　② 只记录不推断　③ 别人的门上着锁，不硬闯"
	l.add_theme_font_size_override("font_size", 17)
	l.add_theme_color_override("font_color", Color("#f2e6c8"))
	_card.add_child(l)
	_card.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	_card.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_card.offset_top = 40
	_card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	host.center.add_child(_card)


# ───────────────────────── 收尾：玩家主动走进厨房时才接回原节拍 ─────────────────────────
func _finish() -> void:
	if phase == "out": return
	phase = "out"
	host._fade(1.0, 0.35, _swap_to_room)


func _swap_to_room() -> void:
	if _card != null: _card.queue_free()
	if _prompt != null: _prompt.queue_free()
	if _hint != null: _hint.queue_free()
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
	host._cine = false
	host.eng.s.playing = true
	host.gathering = null
	# 第四幕：厨房沿用卧室 / 走廊的探索交互（无顶栏、宝石证物、E 键、跟随镜头、按镜头方向移动）。
	# 测试模式（instant_story）或房间不是 B-P 时回退到原来的完整界面。
	var explore := false
	if _to_room == "B-P" and host.has_method("start_kitchen_exploration") and not host.instant_story:
		explore = host.start_kitchen_exploration()
	if not explore:
		host.pitch = 1.25
		host._fit_camera()
	active = false
	host._fade(0.0, 0.4)
	queue_free()


# ───────────────────────── 第三幕：走廊自由活动 ─────────────────────────
## 厨房、走廊门、窗、长凳、盆栽、大门，以及三位同伴，都是「看一眼、说一句」的物件。
## 定义：stand 为侦探站位，pos 为判定中心，npc 非空时位置跟随该人物。
func _item_defs() -> Array:
	var defs: Array = []
	defs.append({"id": "door_r05", "label": "我的房门", "pos": Vector2(3.0, 0.0), "stand": Vector2(3.0, 1.0), "y": 1.55,
		"lines": [["detective", "这是我的门，钥匙在我口袋里，只有它打得开。门没被撬过。", "think"],
			["detective", "屋里能查的，刚才都查过了。"]]})
	var others := [["R06", "霍铎", 7.0, "霍铎"], ["R07", "沈鼎", 11.0, "沈师傅"], ["R08", "苏泠", 15.0, "苏泠"]]
	for o in others:
		defs.append({"id": "door_%s" % str(o[0]).to_lower(), "label": "%s 的房门（锁）" % o[1], "pos": Vector2(float(o[2]), 0.0),
			"stand": Vector2(float(o[2]), 1.0), "y": 1.55,
			"lines": [["detective", "试着拧了一下把手——纹丝不动。这是%s的屋子，门锁着，我的钥匙开不了它。" % o[3]],
				["detective", "没有他开门，我进不去，也不该硬闯。", "think"]]})
	defs.append({"id": "window", "label": "窗", "pos": Vector2(9.0, 0.0), "stand": Vector2(9.0, 1.1), "y": 1.95,
		"lines": [["detective", "晨光是从这几扇窗透进来的，窗外是一片灰白，看不出是什么庭院。"],
			["detective", "窗框是固定死的，推不开。四个人醒在这样一层楼里……", "think"]]})
	defs.append({"id": "bench", "label": "长凳", "pos": Vector2(9.0, 0.45), "stand": Vector2(9.0, 1.15), "y": 0.85,
		"lines": [["detective", "一条靠墙的长凳，坐面是凉的，没人坐过。"],
			["detective", "凳脚下有一小片拖过的灰痕，不到一尺长，朝着东边。", "think"]]})
	defs.append({"id": "plant", "label": "盆栽", "pos": Vector2(13.0, 0.4), "stand": Vector2(12.9, 1.1), "y": 1.5,
		"lines": [["detective", "叶子还是湿的，有人今早浇过水——或者昨晚。"],
			["detective", "土面上有一枚半个鞋印，比我的脚小。", "think"]]})
	defs.append({"id": "gate", "label": "乙区大门（锁）", "pos": Vector2(0.3, 1.7), "stand": Vector2(1.3, 1.7), "y": 1.7,
		"lines": [["detective", "走廊西头的大门，厚实的橡木，门上有锁孔，没有把手。"],
			["detective", "我们四个都没有这把钥匙。是谁把乙区锁起来的？", "think"]]})
	defs.append({"id": "kitchen", "label": "去小厨房复查", "pos": Vector2(LEN - 0.3, 1.7), "stand": Vector2(LEN - 1.4, 1.7), "y": 1.7,
		"lines": [["detective", "厨房还留着昨夜的痕迹。先一起把现场复查一遍。", "think"]]})
	for id in ["huo", "shen", "su"]:
		var a: Dictionary = host.data.actor_by_id[id]
		defs.append({"id": "npc_" + id, "label": str(a.name), "pos": Vector2.ZERO, "stand": Vector2.ZERO, "npc": id,
			"y": float(a.look.height) + 0.55, "lines": _npc_lines(id)})
	return defs


func _npc_lines(id: String) -> Array:
	match id:
		"huo": return [["huo", "曲柄销的事我还没想通。要是你在哪儿见到它，别自己收着，告诉我。"]]
		"shen": return [["shen", "别盯着我的袖子看。湿归湿，我也想知道是怎么回事。"]]
		_: return [["su", "琴弦断了，我反而很平静。真奇怪……我是不是平时也这样？"]]


func _enter_free() -> void:
	if phase == "free": return
	if _card != null:
		_card.queue_free()
		_card = null
	_build_items()
	_build_overlay()
	_joined = true
	_free_t = 0.0
	host.det_path.clear()
	host.det.set_pose("stand")
	phase = "free"
	_pt = 0.0


func _build_overlay() -> void:
	_prompt = Label.new()
	_prompt.add_theme_font_size_override("font_size", 18)
	_prompt.add_theme_color_override("font_color", Color("#ffe3a3"))
	_prompt.add_theme_stylebox_override("normal", host._style(Color(0.06, 0.05, 0.04, 0.82), host.BRASS, 18, 8))
	_prompt.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	_prompt.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_prompt.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_prompt.offset_top = -150
	_prompt.offset_bottom = -112
	_prompt.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_prompt.visible = false
	host.center.add_child(_prompt)
	_hint = Label.new()
	_hint.text = "WASD / 方向键 移动　·　点击发光的物件，或靠近后按 E 查看　·　◀ 西：乙区大门（锁）　▶ 东：乙区小厨房"
	_hint.add_theme_font_size_override("font_size", 14)
	_hint.add_theme_color_override("font_color", Color("#f2e6c8"))
	_hint.add_theme_color_override("font_outline_color", Color(0.04, 0.03, 0.02, 0.95))
	_hint.add_theme_constant_override("outline_size", 6)
	_hint.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT)
	_hint.offset_left = 18
	_hint.offset_top = -30
	_hint.offset_bottom = -8
	_hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	host.center.add_child(_hint)


func _build_items() -> void:
	for def in _item_defs():
		var marker := Node3D.new()
		_root.add_child(marker)
		var locked: bool = "（锁）" in str(def.label)
		var parts: Dictionary = preload("res://scenes/components/interaction/ExplorationMarker.gd").create(marker, str(def.label), {
			"albedo_color": Color("#d9604f") if locked else Color("#ffa51f"),
			"emission_color": Color("#c02a1a") if locked else Color("#ff8a00"),
			"emission_energy_multiplier": 1.6,
			"font": host.SANS_FONT,
		})
		var gem: MeshInstance3D = parts["gem"]
		var mat: StandardMaterial3D = parts["mat"]
		var tag: Label3D = parts["tag"]
		var it: Dictionary = def
		it["marker"] = marker
		it["gem"] = gem
		it["mat"] = mat
		it["tag"] = tag
		it["seen"] = false
		it["locked"] = locked
		_items.append(it)
	_update_markers()


func _item_pos(i: int) -> Vector2:
	var it: Dictionary = _items[i]
	if str(it.get("npc", "")) != "":
		var n: Node3D = _npc[str(it.npc)]
		return Vector2(n.position.x, n.position.z)
	return it.pos


func _item_stand(i: int) -> Vector2:
	var it: Dictionary = _items[i]
	if str(it.get("npc", "")) != "":
		var p := _item_pos(i)
		var away: Vector2 = host.det_pos - p
		if away.length() < 0.05: away = Vector2(-1.0, 0.0)
		return p + away.normalized() * 0.9
	return it.stand


func _update_markers() -> void:
	for i in _items.size():
		var it: Dictionary = _items[i]
		var marker: Node3D = it.marker
		var p := _item_pos(i)
		var wob: float = sin(_clock * 2.0 + float(i)) * 0.04
		# 门上的光标稍微离墙，免得被门框吞掉
		marker.position = Vector3(p.x, float(it.y) + wob, maxf(p.y, 0.35))
		var gem: MeshInstance3D = it.gem
		gem.rotation.y = _clock * 1.4
		var s := 0.62 if bool(it.seen) else (1.15 if i == _hover else 1.0)
		gem.scale = gem.scale.lerp(Vector3.ONE * s, 0.2)
		var mat: StandardMaterial3D = it.mat
		mat.emission_energy_multiplier = 0.6 if bool(it.seen) else 1.6


func _nearest_item(radius: float) -> int:
	var best := -1
	var best_d := radius
	for i in _items.size():
		var d := _item_pos(i).distance_to(host.det_pos)
		if d < best_d:
			best_d = d
			best = i
	return best


func _pick(pos: Vector2) -> int:
	var best := -1
	var best_d := 48.0
	for i in _items.size():
		var w: Vector3 = (_items[i].marker as Node3D).global_position
		if (host.cam as Camera3D).is_position_behind(w): continue
		var d: float = (host.cam as Camera3D).unproject_position(w).distance_to(pos)
		if d < best_d:
			best_d = d
			best = i
	return best


func handle_motion(pos: Vector2) -> void:
	if phase == "free": _hover = _pick(pos)


## 左键点击：命中物件则走过去查看，返回 true 表示事件已处理。
func handle_click(pos: Vector2) -> bool:
	if phase != "free": return false
	var i := _pick(pos)
	if i < 0: return false
	interact(i)
	return true


func interact_nearest() -> void:
	if phase != "free": return
	var i := _nearest_item(1.6)
	if i >= 0: interact(i)


func interact(i: int) -> void:
	if phase != "free" or _busy_item >= 0 or _enter_pending: return
	if host.subtitle.visible or not host._sub_queue.is_empty(): return
	if _item_pos(i).distance_to(host.det_pos) <= 1.6:
		_arrive(i)
	else:
		_busy_item = i


func _arrive(i: int) -> void:
	_busy_item = -1
	var it: Dictionary = _items[i]
	it["seen"] = true
	var p := _item_pos(i)
	var dv: Vector2 = p - host.det_pos
	if dv.length() > 0.05: host.det.rotation.y = atan2(dv.x, dv.y)
	host.det.set_pose("stand")
	for ln in it.lines:
		var l: Array = ln
		host.eng.say(str(l[0]), str(l[1]), str(l[2]) if l.size() > 2 else "")
	if str(it.id) == "kitchen": _enter_pending = true


func _step_free(delta: float) -> void:
	_free_t += delta
	var det: Node3D = host.det
	var sub_up: bool = host.subtitle.visible or not host._sub_queue.is_empty()
	# 玩家主动选择走进厨房：台词说完后才切场
	if _enter_pending and not sub_up:
		_finish()
		return
	var vec := Input.get_vector("move_left", "move_right", "move_up", "move_down")
	if vec.length() >= 0.05 and not _enter_pending:
		_busy_item = -1
		_move_det(vec.normalized() * float(host.WALK_SPEED) * delta, vec)
	elif _busy_item >= 0:
		var stand := _item_stand(_busy_item)
		if host.det_pos.distance_to(stand) > 0.12:
			_walk_to(stand, delta)
			host.det_pos = _push_out(host.det_pos)
			det.position = Vector3(host.det_pos.x, 0.0, host.det_pos.y)
		else:
			_arrive(_busy_item)
	else:
		det.set_pose("stand")
	var near := _nearest_item(1.6)
	var show_prompt := near >= 0 and not sub_up and _busy_item < 0 and not _enter_pending
	_prompt.visible = show_prompt
	if show_prompt:
		var it: Dictionary = _items[near]
		_prompt.text = "E %s" % ("去小厨房复查" if str(it.id) == "kitchen" else str(it.label).replace("（锁）", ""))
	for i in _items.size():
		# 同伴头顶已有名牌，不再重复显示标记标签
		(_items[i].tag as Label3D).visible = (i == _hover or i == near) and str(_items[i].get("npc", "")) == ""
	if _free_t > 14.0: _hint.modulate.a = move_toward(_hint.modulate.a, 0.0, delta * 0.3)
	_update_markers()


## 手动移动：限制在走廊范围内，并与三位同伴保持距离（不穿人）。
func _move_det(step: Vector2, vec: Vector2) -> void:
	var cand: Vector2 = host.det_pos + step
	cand.x = clampf(cand.x, FREE_BOUNDS.position.x, FREE_BOUNDS.end.x)
	cand.y = clampf(cand.y, FREE_BOUNDS.position.y, FREE_BOUNDS.end.y)
	cand = _push_out(cand)
	host.det_pos = cand
	host.det.position = Vector3(cand.x, 0.0, cand.y)
	host.det.rotation.y = lerp_angle(host.det.rotation.y, atan2(vec.x, vec.y), 0.35)
	host.det.set_pose("walk")


func _push_out(p: Vector2) -> Vector2:
	for id in _npc:
		var n: Node3D = _npc[id]
		var np := Vector2(n.position.x, n.position.z)
		var d := p - np
		if d.length() < NPC_BODY:
			p = np + (d.normalized() if d.length() > 0.001 else Vector2(-1.0, 0.0)) * NPC_BODY
	return p
