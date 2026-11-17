extends Node
## 第四幕：B-P 乙区小厨房自由探索（与第一幕卧室、第三幕走廊同一套交互）。
##
## 修正前的问题（见 docs/厨房场景修正说明.md）：
##   · 厨房一进来就退回「完整界面」：顶栏 + 左卡 + 证物列表 + 7 根黄色光柱，没有 E 提示和操作提示，
##     与前面「点发光物件 / 靠近按 E / Esc 切换界面」的玩法断了层。
##   · 镜头在换场后被硬切成接近垂直俯视（pitch 1.25）、方位 az=0.65，WASD 却按世界坐标移动，
##     于是按 W 在屏幕上是斜着走；台词一出现 WASD 就完全失效；碰到家具直接「粘住」。
##
## 本脚本做的事：
##   · 证物仍由 DualEngine 负责（inspect_evidence、推演门槛、存档都不变）；这里只把 7 个证物换成
##     与卧室 / 走廊一致的发光宝石 + 名牌，点击先走过去再查看，靠近按 E 也行。
##   · 侦探从厨房门走进来（而不是凭空出现在房间中央），镜头沿用走廊的角度并平滑过渡到跟随镜头。
##   · 无顶栏 / 左卡 / 案卷抽屉；Esc 临时唤出完整界面。证物查完且首个推演结束后自动恢复完整界面。
##   · 移动按镜头方向（W = 屏幕向上），见 DualWorldMain._manual_move_step。

const ROOM := "B-P"
const FROM_ROOM := "R05"
const OrderReplay := preload("res://scenes/dual_world/KitchenOrderReplay.gd")
const ENTER_AZ := 0.12       # 与走廊镜头一致，换场时视角不跳
const ENTER_PITCH := 1.0
const ENTER_DIST := 7.4
const FOLLOW_PITCH := 0.95
const NEAR := 1.5            # E 键判定半径
const GEM_Y := 1.05
const SHORT_LABELS := {"e_b_sleeve":"袖口","e_b_drag":"鞋跟痕","e_b_water":"门缝","e_b_cloth":"湿布","e_b_ratchet":"棘轮","e_b_boots":"靴印","e_b_seal":"铅封"}

var host: Control
var active := false
var phase := "off"           # enter → free
var focus := Vector3.ZERO
var chrome_shown := false

var _clock := 0.0
var _free_t := 0.0
var _items: Array = []
var _markers_root: Node3D
var _hover := -1
var _busy_item := -1
var _prompt: Label
var _hint: Label
var _order_replay: Node = null


func begin(h: Control) -> bool:
	host = h
	if host.view != "room" or str(host.eng.s.room) != ROOM or host.room_mesh == null: return false
	active = true
	phase = "enter"
	host._cine = false
	_hide_chrome()
	_build_markers()
	_build_overlay()
	_hide_floor_pillars()
	_place_at_door()
	host.az = ENTER_AZ
	host.pitch = ENTER_PITCH
	host.dist = ENTER_DIST
	focus = _goal_focus()
	host._update_camera()
	return true


## 首个乙区推演证物齐全时，以房间内的动作复演替代抽象多选题。
func begin_order_replay(did: String) -> bool:
	if not active or did != "ded_drag": return false
	if _order_replay != null and is_instance_valid(_order_replay) and _order_replay.active: return true
	_order_replay = OrderReplay.new()
	add_child(_order_replay)
	_order_replay.observed.connect(func(event: Dictionary): host.reconstruction_observed.emit(event))
	if _order_replay.begin(host, did): return true
	_order_replay.queue_free()
	_order_replay = null
	return false


## 侦探从门外走进来：和房间之间换场（_transit_swap）用的是同一扇门、同一条路线。
func _place_at_door() -> void:
	var op: Dictionary = host._door_for(host.room_mesh.design, host._room_dir(ROOM, FROM_ROOM))
	if op.is_empty():
		_enter_free()
		return
	host.det_path.clear()
	host.det_pos = op.outer
	host.det.position = Vector3(host.det_pos.x, 0.0, host.det_pos.y)
	host.det.rotation.y = atan2(op.inward.x, op.inward.y)
	host.det.set_pose("stand")
	host._go_through_door(op, [op.pos, op.inner], _enter_free)


func _enter_free() -> void:
	if not active or phase == "free": return
	phase = "free"
	_free_t = 0.0
	if _hint != null: _hint.visible = true


# ───────────────────────── 每帧 ─────────────────────────
func process(delta: float) -> void:
	if not active: return
	if str(host.eng.s.room) != ROOM:
		end()
		return
	_clock += delta
	_hide_floor_pillars()
	if host._cine:
		_animate_markers()
		return
	if phase == "free":
		_free_t += delta
		_step_free(delta)
	if not active: return
	_drive_camera(delta)
	_animate_markers()


func _step_free(delta: float) -> void:
	for item in _items:
		var kind: String = host.interactions.kind_for(str(item.id))
		var detail: Node3D = host.evidence_presentations.get(kind)
		if is_instance_valid(detail): item.pos = Vector3(detail.global_position.x, 0.0, detail.global_position.z)
	var sub_up: bool = host.subtitle.visible or not host._sub_queue.is_empty()
	var near := _nearest_item(NEAR)
	var show_prompt: bool = near >= 0 and not sub_up and _busy_item < 0 and not host.modal.visible and not host._cine
	_prompt.visible = show_prompt
	if show_prompt:
		_prompt.text = "E %s" % str(_items[near].label)
	for i in _items.size():
		# 近距离时底部 E 提示已经给出名称；3D 名牌只跟随鼠标悬停，避免压住角色与动作。
		(_items[i].tag as Label3D).visible = i == _hover and i != near and not host._cine
	if _hint != null:
		var seen_count := 0
		for item in _items:
			if _seen(item): seen_count += 1
		_hint.text = "Clues %d/7" % seen_count
	_maybe_finish()


## 首个推演完成后交还导航；其余证物仍可在原房间复查。
func _maybe_finish() -> void:
	if host.modal.visible or not host.eng.s.pending_deduction.is_empty(): return
	if not host.eng.s.deductions.has("ded_drag"): return
	end()


## 引擎的原版证物光柱不再显示（改用宝石），但它们仍保留在 room_mesh 里供存档 / 重建使用。
func _hide_floor_pillars() -> void:
	for eid in host.room_mesh.evidence_nodes:
		var n: Node3D = host.room_mesh.evidence_nodes[eid]
		var mk: Node3D = n.get_node_or_null("Marker")
		if mk != null and mk.visible: mk.visible = false


# ───────────────────────── 镜头 ─────────────────────────
func _room_center() -> Vector3:
	if host._lowpoly_ok and host.lowpoly != null: return host.lowpoly.center()
	return host.room_mesh.center()


func _det_point() -> Vector3:
	return host.det.global_position + Vector3(0.0, 0.55, 0.0)


func _goal_focus() -> Vector3:
	return _room_center().lerp(_det_point(), 0.6)


func _goal_dist() -> float:
	return clampf(float(host._fit_dist) * 0.66, 4.6, 7.4)


## 跟随镜头：焦点平滑跟着侦探；刚进门 2.5 秒内把距离 / 俯角拉到位，之后滚轮与右键拖动归玩家。
func _drive_camera(delta: float) -> void:
	focus = focus.lerp(_goal_focus(), 1.0 - exp(-delta * 3.0))
	if phase != "free" or _free_t < 2.5:
		var rate := 1.0 - exp(-delta * 1.6)
		host.dist = lerpf(host.dist, _goal_dist(), rate)
		host.pitch = lerpf(host.pitch, FOLLOW_PITCH, rate)
	host._update_camera()


# ───────────────────────── 界面 ─────────────────────────
func _hide_chrome() -> void:
	chrome_shown = false
	host.ExplorationUiState.hide_chrome(host)


func toggle_chrome() -> void:
	_hide_chrome()
	host._open_exploration_book("journal")


func _build_overlay() -> void:
	_prompt = Label.new()
	_prompt.set_meta("text_category", "prompt")
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
	_hint.set_meta("text_category", "prompt")
	_hint.text = "WASD Move"
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
	_markers_root.name = "KitchenMarkers"
	host.det_root.get_parent().add_child(_markers_root)
	for e in host.data.evidence:
		if str(e.room) != ROOM: continue
		var eid := str(e.id)
		if not host.room_mesh.evidence_nodes.has(eid): continue
		var n: Node3D = host.room_mesh.evidence_nodes[eid]
		var pos := Vector3(n.global_position.x, 0.0, n.global_position.z)
		var marker := Node3D.new()
		_markers_root.add_child(marker)
		var label := tr(str(SHORT_LABELS.get(eid,e.label)))
		var parts: Dictionary = preload("res://scenes/components/interaction/ExplorationMarker.gd").create(marker, label, {"font": host.SANS_FONT})
		var gem: MeshInstance3D = parts["gem"]
		var mat: StandardMaterial3D = parts["mat"]
		var tag: Label3D = parts["tag"]
		marker.position = Vector3(pos.x, GEM_Y, pos.z)
		_items.append({"id": eid, "label": label, "pos": pos, "marker": marker, "gem": gem, "mat": mat, "tag": tag})


func _seen(it: Dictionary) -> bool:
	return host.eng.s.evidence.has(str(it.id))


func _animate_markers() -> void:
	var show_now: bool = phase == "free" and not host._cine
	for i in _items.size():
		var it: Dictionary = _items[i]
		var marker: Node3D = it.marker
		marker.visible = show_now
		if not show_now: continue
		var p: Vector3 = it.pos
		marker.position = Vector3(p.x, GEM_Y + sin(_clock * 2.0 + float(i)) * 0.04, p.z)
		var gem: MeshInstance3D = it.gem
		gem.rotation.y = _clock * 1.4
		var seen := _seen(it)
		gem.scale = gem.scale.lerp(Vector3.ONE * (0.62 if seen else (1.15 if i == _hover else 1.0)), 0.2)
		var mat: StandardMaterial3D = it.mat
		mat.emission_energy_multiplier = 0.5 if seen else 1.6
		mat.albedo_color = Color("#8a7a5a") if seen else Color("#ffa51f")


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


## 左键点击：命中证物则走过去查看，返回 true 表示事件已处理。
func handle_click(pos: Vector2) -> bool:
	if phase != "free": return false
	var i := _pick(pos)
	if i < 0: return false
	interact(i)
	return true


func interact_nearest() -> void:
	if phase != "free": return
	var i := _nearest_item(NEAR)
	if i >= 0: interact(i)


func interact(i: int) -> void:
	if phase != "free" or _busy_item >= 0 or host.modal.visible: return
	if host._cine: return
	if host.subtitle.visible or not host._sub_queue.is_empty(): return
	var p: Vector3 = _items[i].pos
	var target := Vector2(p.x, p.z)
	var from: Vector2 = host.det_pos
	var kind: String = host.interactions.kind_for(str(_items[i].id))
	var approach := preload("res://scenes/components/interaction/InteractionApproach.gd").plan(host, target, kind, from)
	if not approach.ok: return
	if approach.already_near:
		_arrive(i)
		return
	_busy_item = i
	host._go(approach.path, func(): _arrive(i))


func cancel_walk() -> void:
	_busy_item = -1


func _arrive(i: int) -> void:
	if _busy_item != i and _busy_item >= 0: return
	_busy_item = -1
	if not active or phase != "free": return
	var p: Vector3 = _items[i].pos
	var dv: Vector2 = Vector2(p.x, p.z) - host.det_pos
	if dv.length() > 0.05: host.det.rotation.y = atan2(dv.x, dv.y)
	host.det.set_pose("stand")
	var evidence_id := str(_items[i].id)
	var kind: String = host.interactions.kind_for(evidence_id)
	if kind.is_empty(): return
	_busy_item = i
	var started: bool = host.interactions.begin_gameplay(host,kind,func(success: bool):
		_busy_item = -1
		if success:
			host.eng.inspect_evidence(evidence_id,true)
			host._rebuild_markers()
			_hide_floor_pillars())
	if not started: _busy_item = -1


# ───────────────────────── 收尾 ─────────────────────────
func _cleanup() -> void:
	if _markers_root != null: _markers_root.queue_free()
	if _prompt != null: _prompt.queue_free()
	if _hint != null: _hint.queue_free()
	_markers_root = null
	_prompt = null
	_hint = null
	_items.clear()


## 结束本段控制器，正式探索继续使用共用的精简界面。
func end() -> void:
	if not active: return
	if _order_replay != null and is_instance_valid(_order_replay) and _order_replay.active: _order_replay.stop()
	active = false
	phase = "off"
	_cleanup()
	_hide_chrome()
	host.pitch = 1.25
	host._fit_camera()
