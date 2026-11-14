extends Node
## 第一幕：R05 床上醒来。
##
## 流程：黑场淡入 → 躺着迷糊 → 撑起上身 → 一脸困惑地东张西望 → 弹出台词 → 下床 → 自由操作。
## 自由操作阶段没有案卷抽屉、左侧位置卡和顶栏，只剩侦探和房间里几个可以查看的物件（点击或按 E）。
## 剧情时间线、台词、存档都仍由 DualEngine 负责；本脚本只负责「演」和「摸」。按 Esc 可临时唤出完整界面。

const PROPS := [
	{"id": "bed", "node": "R05_bed_01", "label": "床", "y": 1.0, "lines": [
		"被子被踢到了床脚，枕头也歪着。",
		"我睡得很不踏实——不对，我根本不记得自己是什么时候睡着的。"]},
	{"id": "lamp", "node": "R05_banker_lamp_01", "label": "床头灯", "y": 1.1, "lines": [
		"台灯还亮着。我有开着灯睡觉的习惯吗？",
		"灯罩上落了一点灰……至少它比我清醒。"]},
	{"id": "desk", "node": "R05_table_01", "label": "书桌", "y": 1.35, "lines": [
		"笔记本合着，上面压着一支笔。",
		"最后一页只写了半行，字迹发抖，我认得那是我的字。可它想说什么，我一点也想不起来。"]},
	{"id": "window", "node": "R05_window_01", "label": "窗", "y": 1.75, "lines": [
		"天刚亮，窗外一片灰白。",
		"乙区的方向很安静。太安静了。"]},
	{"id": "wardrobe", "node": "R05_wardrobe_01", "label": "衣柜", "y": 2.25, "lines": [
		"大衣整整齐齐地挂着。",
		"整齐得不像一个半夜出过门的人——可我手背上这几道抓痕，又是谁留下的？"]},
	{"id": "wash", "node": "R05_wash_table_01", "label": "洗手台", "y": 1.45, "lines": [
		"冷水泼在脸上，镜子里的人眼下发青。",
		"手背上的抓痕被水一激，又红了。我得弄清楚，它是怎么来的。"]},
	{"id": "door", "node": "R05_Door_00", "label": "寝室门", "y": 2.3, "lines": [
		"门没有被撬过的痕迹。",
		"……走吧。乙区小厨房，八点，他们在等我。"]},
]

const SIT_KEYS := [[0.0, 0.0, 0.10, 0.0], [1.0, 0.45, 0.25, 0.05], [1.7, 0.45, 0.30, -0.05], [3.0, 1.0, 0.28, 0.04]]
const LOOK_KEYS := [
	[0.0, 0.0, 0.28, 0.04], [0.8, -0.95, 0.02, -0.10], [1.5, -0.95, 0.02, -0.10],
	[2.7, 0.95, -0.05, 0.12], [3.4, 0.95, -0.05, 0.12], [4.2, -0.30, 0.25, -0.18],
	[5.0, 0.0, 0.35, 0.0],
]
const T_BLACK := 0.7
const T_FADE := 2.3
const T_LIE := 1.7
const T_SIT := 3.2
const T_LOOK := 5.0

var host: Control
var active := false
var phase := "off"
var focus := Vector3.ZERO
var chrome_shown := false

var _rig: SkeletonModifier3D
var _pt := 0.0
var _clock := 0.0
var _items: Array = []
var _markers_root: Node3D
var _hover := -1
var _prompt: Label
var _hint: Label
var _talk_seen := false
var _talk_idle := 0.0
var _busy_item := -1
var _pending_exit := ""
var _all_seen_said := false
var _free_t := 0.0
var _name_tag: Label3D = null
var _head := Vector3.ZERO  # yaw, pitch, roll（平滑后的实际值）


func begin(h: Control) -> bool:
	host = h
	if host.det == null or host.det.pose != "lie" or host.view != "room": return false
	_rig = host.det.wake_rig()
	if _rig == null: return false
	_name_tag = _find_tag()
	if _name_tag != null: _name_tag.visible = false  # 近景里「侦探」名牌太大，表演时先收起
	active = true
	host._cine = true
	host.eng.s.playing = false
	host.fade_rect.modulate.a = 1.0
	_hide_chrome()
	_build_markers()
	_build_overlay()
	_enter("black")
	_snap_camera()
	return true


func _enter(p: String) -> void:
	phase = p
	_pt = 0.0
	match p:
		"fade": host._fade(0.0, 1.8)
		"talk":
			_talk_seen = false
			_talk_idle = 0.0
			host.eng.s.playing = true
		"getup":
			host.eng.s.playing = false
			host._begin_wake_up()
		"free":
			host._cine = false
			host.eng.s.playing = true
			_free_t = 0.0
			if _hint != null: _hint.visible = true
			if _name_tag != null:
				_name_tag.pixel_size = 0.0036
				_name_tag.visible = true


# ───────────────────────── 每帧 ─────────────────────────
func process(delta: float) -> void:
	if not active: return
	if str(host.eng.s.room) != "R05":
		_end()
		return
	_clock += delta
	_pt += delta
	match phase:
		"black": if _pt >= T_BLACK: _enter("fade")
		"fade": if _pt >= T_FADE: _enter("lie")
		"lie":
			_set_head(Vector3(0.0, 0.08, sin(_clock * 1.3) * 0.07), 0.0, delta)
			if _pt >= T_LIE: _enter("sit")
		"sit":
			var k := _keys(_pt, SIT_KEYS)
			_set_head(Vector3(0.0, k[1], k[2]), k[0], delta)
			if _pt >= T_SIT: _enter("look")
		"look":
			var k2 := _keys(_pt, LOOK_KEYS)
			_set_head(Vector3(k2[0], k2[1], k2[2]), 1.0, delta)
			if _pt >= T_LOOK: _enter("talk")
		"talk": _step_talk(delta)
		"getup":
			var k3 := clampf(_pt / 0.7, 0.0, 1.0)
			_set_head(Vector3.ZERO, 1.0 - smoothstep(0.0, 1.0, k3), delta)
			if _pt > 0.3 and host._wake_timer <= 0.0: _enter("free")
		"free": _step_free(delta)
	_drive_camera(delta)
	_animate_markers()
	if active and str(host.eng.s.room) != "R05": _end()


func _find_tag() -> Label3D:
	for c in host.det.get_children():
		if c is Label3D: return c as Label3D
	return null


func _step_talk(delta: float) -> void:
	var shown: bool = host.subtitle.visible or not host._sub_queue.is_empty()
	if shown: _talk_seen = true
	# 说到手背抓痕时低头看手
	var look_down: bool = host.subtitle.visible and "抓痕" in host.subtitle.text
	_set_head(Vector3(0.0, 0.5 if look_down else 0.15, 0.0), 1.0, delta)
	if _talk_seen:
		_talk_idle = 0.0 if shown else _talk_idle + delta
		if _talk_idle >= 0.5: _enter("getup")
	elif _pt > 8.0:
		_enter("getup")  # 保险：节拍没有触发台词时也不要卡在床上


func _step_free(delta: float) -> void:
	_free_t += delta
	var sub_up: bool = host.subtitle.visible or not host._sub_queue.is_empty()
	if _pending_exit != "" and not sub_up:
		var to := _pending_exit
		_pending_exit = ""
		# 第二幕：出门先走到乙区走廊，听见人声再加入对话圈（见 CorridorGathering.gd）
		if to == "B-P" and host.has_method("start_gathering") and not host.instant_story:
			host.start_gathering(to)
		else:
			host.eng.enter_room(to)
		return
	# 互动提示：离得近的物件
	var near := _nearest_item(1.5)
	var show_prompt := near >= 0 and not sub_up and _busy_item < 0 and _pending_exit == ""
	_prompt.visible = show_prompt
	if show_prompt: _prompt.text = "E  ·  查看「%s」" % str(_items[near].label)
	for i in _items.size():
		var tag: Label3D = _items[i].tag
		tag.visible = i == _hover or i == near
	if _hint != null and _free_t > 14.0:
		_hint.modulate.a = move_toward(_hint.modulate.a, 0.0, delta * 0.3)
	# 全部看过：提醒去门口
	if not _all_seen_said and not sub_up and _busy_item < 0:
		var left := 0
		for it in _items:
			if str(it.id) != "door" and not bool(it.seen): left += 1
		if left == 0:
			_all_seen_said = true
			host.eng.say("detective", "能看的都看了。该去乙区了。", "think")


func _set_head(v: Vector3, sit: float, delta: float) -> void:
	_head = _head.lerp(v, 1.0 - exp(-delta * 9.0))
	if _rig == null: return
	_rig.set("sit", clampf(sit, 0.0, 1.0))
	_rig.set("head_yaw", _head.x)
	_rig.set("head_pitch", _head.y)
	_rig.set("head_roll", _head.z)


func _keys(tt: float, keys: Array) -> Array:
	if tt <= float(keys[0][0]): return (keys[0] as Array).slice(1)
	for i in range(1, keys.size()):
		var a: Array = keys[i - 1]
		var b: Array = keys[i]
		if tt <= float(b[0]):
			var k := smoothstep(0.0, 1.0, (tt - float(a[0])) / (float(b[0]) - float(a[0])))
			var out: Array = []
			for c in range(1, a.size()): out.append(lerpf(float(a[c]), float(b[c]), k))
			return out
	return (keys[keys.size() - 1] as Array).slice(1)


# ───────────────────────── 镜头 ─────────────────────────
func _room_center() -> Vector3:
	if host._lowpoly_ok and host.lowpoly != null: return host.lowpoly.center()
	return host.room_mesh.center()


func _det_point() -> Vector3:
	return host.det.global_position + Vector3(0.0, 0.55, 0.0)


func _cam_goal() -> Dictionary:
	match phase:
		"black", "fade", "lie", "sit": return {"dist": 3.9, "pitch": 0.60, "focus": _det_point()}
		"look": return {"dist": 3.4, "pitch": 0.55, "focus": _det_point()}
		"talk": return {"dist": 3.7, "pitch": 0.62, "focus": _det_point()}
	return {"dist": clampf(float(host._fit_dist) * 0.66, 4.6, 7.4), "pitch": 0.95,
		"focus": _room_center().lerp(_det_point(), 0.6)}


func _snap_camera() -> void:
	var g := _cam_goal()
	host.dist = g.dist
	host.pitch = g.pitch
	focus = g.focus
	host._update_camera()


func _drive_camera(delta: float) -> void:
	var g := _cam_goal()
	var follow := 1.0 - exp(-delta * 3.0)
	focus = focus.lerp(g.focus, follow)
	# 自由阶段只在刚起床的 2.5 秒内把镜头拉到位，之后滚轮 / 右键拖动归玩家
	if phase != "free" or _free_t < 2.5:
		var rate := 1.0 - exp(-delta * (6.0 if phase in ["black", "fade", "lie", "sit", "look", "talk"] else 1.6))
		host.dist = lerpf(host.dist, g.dist, rate)
		host.pitch = lerpf(host.pitch, g.pitch, rate)
	host._update_camera()


# ───────────────────────── 界面 ─────────────────────────
func _hide_chrome() -> void:
	chrome_shown = false
	host.top_bar.visible = false
	host.left_card.visible = false
	host.room_hint.visible = false
	host.drawer.visible = false


func toggle_chrome() -> void:
	chrome_shown = not chrome_shown
	host.top_bar.visible = chrome_shown
	host.left_card.visible = chrome_shown
	host.room_hint.visible = chrome_shown
	if not chrome_shown: host.drawer.visible = false
	if host.drawer_btn != null and not chrome_shown: host.drawer_btn.button_pressed = false


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
	_hint.text = "WASD / 方向键 移动　·　点击发光的物件，或靠近后按 E 查看　·　Esc 显示 / 隐藏完整界面"
	_hint.add_theme_font_size_override("font_size", 14)
	_hint.add_theme_color_override("font_color", Color("#f2e6c8"))
	_hint.add_theme_color_override("font_outline_color", Color(0.04, 0.03, 0.02, 0.95))
	_hint.add_theme_constant_override("outline_size", 6)
	_hint.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT)
	_hint.offset_left = 18
	_hint.offset_top = -30
	_hint.offset_bottom = -8
	_hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hint.visible = false
	host.center.add_child(_hint)


func _build_markers() -> void:
	_markers_root = Node3D.new()
	_markers_root.name = "WakeOpeningMarkers"
	host.det_root.get_parent().add_child(_markers_root)
	var root3: Node3D = host.lowpoly.get("_root") if host.lowpoly != null else null
	if root3 == null: return
	for def in PROPS:
		var n := root3.find_child(str(def.node), true, false) as Node3D
		if n == null: continue
		var pos := n.global_position
		var marker := Node3D.new()
		marker.position = Vector3(pos.x, float(def.y), pos.z)
		_markers_root.add_child(marker)
		var gem := MeshInstance3D.new()
		var sm := SphereMesh.new()
		sm.radius = 0.15
		sm.height = 0.34
		sm.radial_segments = 4
		sm.rings = 2
		gem.mesh = sm
		var mat := StandardMaterial3D.new()
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mat.albedo_color = Color("#ffa51f")
		mat.emission_enabled = true
		mat.emission = Color("#ff8a00")
		mat.emission_energy_multiplier = 1.8
		gem.material_override = mat
		gem.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		marker.add_child(gem)
		var tag := Label3D.new()
		tag.text = str(def.label)
		tag.font_size = 40
		tag.pixel_size = 0.0055
		tag.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		tag.position = Vector3(0.0, 0.26, 0.0)
		tag.modulate = Color("#ffe3a3")
		tag.outline_size = 12
		tag.no_depth_test = true
		tag.visible = false
		marker.add_child(tag)
		_items.append({"id": str(def.id), "label": str(def.label), "lines": def.lines, "pos": pos,
			"marker": marker, "gem": gem, "mat": mat, "tag": tag, "seen": false, "base_y": float(def.y)})


func _animate_markers() -> void:
	var visible_now := phase == "free"
	var door_ready := _all_seen_said
	for i in _items.size():
		var it: Dictionary = _items[i]
		var marker: Node3D = it.marker
		marker.visible = visible_now
		if not visible_now: continue
		marker.position.y = float(it.base_y) + sin(_clock * 2.0 + float(i)) * 0.04
		var gem: MeshInstance3D = it.gem
		gem.rotation.y = _clock * 1.4
		var s := 0.62 if bool(it.seen) else (1.15 if i == _hover else 1.0)
		if str(it.id) == "door" and door_ready: s = 1.0 + 0.2 * sin(_clock * 4.0)
		gem.scale = gem.scale.lerp(Vector3.ONE * s, 0.2)
		var mat: StandardMaterial3D = it.mat
		mat.emission_energy_multiplier = 0.5 if bool(it.seen) and not (str(it.id) == "door" and door_ready) else 1.6
		mat.albedo_color = Color("#8a7a5a") if bool(it.seen) and not (str(it.id) == "door" and door_ready) else Color("#ffa51f")


# ───────────────────────── 互动 ─────────────────────────
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


func _nearest_item(radius: float) -> int:
	var best := -1
	var best_d := radius
	for i in _items.size():
		var p: Vector3 = _items[i].pos
		var d: float = Vector2(p.x, p.z).distance_to(host.det_pos)
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
	var i := _nearest_item(1.5)
	if i >= 0: interact(i)


func interact(i: int) -> void:
	if phase != "free" or _busy_item >= 0 or _pending_exit != "": return
	var it: Dictionary = _items[i]
	var p: Vector3 = it.pos
	var target := Vector2(p.x, p.z)
	var from: Vector2 = host.det_pos
	if from.distance_to(target) <= 1.3:
		_arrive(i)
		return
	_busy_item = i
	var away := (from - target).normalized()
	var stand := target + away * 0.8
	var cell: Vector2i = host._nearest_free(host._cell_of(stand))
	stand = Vector2((cell.x + 0.5) * host.CELL, (cell.y + 0.5) * host.CELL)
	host._go(host._route(from, stand), func(): _arrive(i))


func cancel_walk() -> void:
	_busy_item = -1


func _arrive(i: int) -> void:
	if _busy_item != i and _busy_item >= 0: return
	_busy_item = -1
	if not active or phase != "free": return
	var it: Dictionary = _items[i]
	var p: Vector3 = it.pos
	var dv: Vector2 = Vector2(p.x, p.z) - host.det_pos
	if dv.length() > 0.05: host.det.rotation.y = atan2(dv.x, dv.y)
	host.det.set_pose("stand")
	it.seen = true
	for ln in it.lines: host.eng.say("detective", str(ln), "think")
	if str(it.id) == "door":
		for dr in host.data.doors:
			var other := ""
			if dr.a == "R05": other = str(dr.b)
			elif dr.b == "R05": other = str(dr.a)
			if other != "" and host.eng.unlocked(dr):
				_pending_exit = other
				break


## 交棒给第二幕：停止第一幕的演出与光标，但不恢复完整界面、不动镜头（走廊场景接管）。
func handoff() -> void:
	active = false
	phase = "off"
	if _rig != null:
		_rig.set("sit", 0.0)
		_rig.set("head_yaw", 0.0)
		_rig.set("head_pitch", 0.0)
		_rig.set("head_roll", 0.0)
	if _name_tag != null:
		_name_tag.pixel_size = 0.006
		_name_tag.visible = true
	if _markers_root != null: _markers_root.queue_free()
	if _prompt != null: _prompt.queue_free()
	if _hint != null: _hint.queue_free()
	_items.clear()
	host.top_bar.visible = false
	host.left_card.visible = false
	host.room_hint.visible = false
	host.drawer.visible = false


func _end() -> void:
	active = false
	phase = "off"
	host._cine = false
	if _rig != null:
		_rig.set("sit", 0.0)
		_rig.set("head_yaw", 0.0)
		_rig.set("head_pitch", 0.0)
		_rig.set("head_roll", 0.0)
	if _name_tag != null:
		_name_tag.pixel_size = 0.006
		_name_tag.visible = true
	if _markers_root != null: _markers_root.queue_free()
	if _prompt != null: _prompt.queue_free()
	if _hint != null: _hint.queue_free()
	_items.clear()
	host.top_bar.visible = true
	host.left_card.visible = true
	host.room_hint.visible = true
	host.pitch = 1.25
	host._fit_camera()
