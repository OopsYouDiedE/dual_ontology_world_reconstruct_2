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
const ENTER_AZ := 0.12       # 与走廊镜头一致，换场时视角不跳
const ENTER_PITCH := 1.0
const ENTER_DIST := 7.4
const FOLLOW_PITCH := 0.95
const NEAR := 1.5            # E 键判定半径
const GEM_Y := 1.05

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
	host._go([op.pos, op.inner], _enter_free)


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
	if phase == "free":
		_free_t += delta
		_step_free(delta)
	if not active: return
	_drive_camera(delta)
	_animate_markers()


func _step_free(delta: float) -> void:
	var sub_up: bool = host.subtitle.visible or not host._sub_queue.is_empty()
	var near := _nearest_item(NEAR)
	var show_prompt: bool = near >= 0 and not sub_up and _busy_item < 0 and not host.modal.visible
	_prompt.visible = show_prompt
	if show_prompt:
		_prompt.text = "E  ·  %s「%s」" % ["复查" if _seen(_items[near]) else "查看", str(_items[near].label)]
	for i in _items.size():
		(_items[i].tag as Label3D).visible = i == _hover or i == near
	if _hint != null and _free_t > 14.0:
		_hint.modulate.a = move_toward(_hint.modulate.a, 0.0, delta * 0.3)
	_maybe_finish()


## 7 件证物都查过、首个推演已经有结论、也没有弹窗：交还完整界面（出口、地图、案卷）。
func _maybe_finish() -> void:
	if host.modal.visible or not host.eng.s.pending_deduction.is_empty(): return
	if host.eng.s.deductions.is_empty(): return
	for it in _items:
		if not _seen(it): return
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
	host.top_bar.visible = false
	host.left_card.visible = false
	host.room_hint.visible = false
	host.drawer.visible = false


func toggle_chrome() -> void:
	chrome_shown = not chrome_shown
	host.top_bar.visible = chrome_shown
	host.left_card.visible = chrome_shown
	host.room_hint.visible = chrome_shown
	if not chrome_shown:
		host.drawer.visible = false
		if host.drawer_btn != null: host.drawer_btn.button_pressed = false


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
	_hint.text = "WASD / 方向键 移动（W = 屏幕向上）　·　点击发光的证物，或靠近后按 E 查看　·　右键拖动转视角　·　Esc 显示 / 隐藏完整界面"
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
		mat.emission_energy_multiplier = 1.6
		gem.material_override = mat
		gem.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		marker.add_child(gem)
		var tag := Label3D.new()
		tag.text = str(e.label)
		tag.font = host.SANS_FONT
		tag.font_size = 40
		tag.pixel_size = 0.0055
		tag.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		tag.position = Vector3(0.0, 0.26, 0.0)
		tag.modulate = Color("#ffe3a3")
		tag.outline_size = 12
		tag.no_depth_test = true
		tag.visible = false
		marker.add_child(tag)
		marker.position = Vector3(pos.x, GEM_Y, pos.z)
		_items.append({"id": eid, "label": str(e.label), "pos": pos, "marker": marker, "gem": gem, "mat": mat, "tag": tag})


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
	if host.subtitle.visible or not host._sub_queue.is_empty(): return
	var p: Vector3 = _items[i].pos
	var target := Vector2(p.x, p.z)
	var from: Vector2 = host.det_pos
	if from.distance_to(target) <= 1.3:
		_arrive(i)
		return
	_busy_item = i
	var away := (from - target).normalized()
	var stand := target + away * 0.7
	var cell: Vector2i = host._nearest_free(host._cell_of(stand))
	stand = Vector2((cell.x + 0.5) * host.CELL, (cell.y + 0.5) * host.CELL)
	host._go(host._route(from, stand), func(): _arrive(i))


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
	host.eng.inspect_evidence(str(_items[i].id))
	host._rebuild_markers()
	_hide_floor_pillars()   # 重建会让原版光柱重新可见：同一帧内再收起，避免闪一下


# ───────────────────────── 收尾 ─────────────────────────
func _cleanup() -> void:
	if _markers_root != null: _markers_root.queue_free()
	if _prompt != null: _prompt.queue_free()
	if _hint != null: _hint.queue_free()
	_markers_root = null
	_prompt = null
	_hint = null
	_items.clear()


## 交还完整界面：与卧室的 _end 一致，恢复顶栏 / 左卡并重新取景。
func end() -> void:
	if not active: return
	active = false
	phase = "off"
	_cleanup()
	host.top_bar.visible = true
	host.left_card.visible = true
	host.room_hint.visible = true
	host.pitch = 1.25
	host._fit_camera()
