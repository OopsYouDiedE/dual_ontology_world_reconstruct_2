extends Control
## 2D 完整场景地图：所有房间一张图；房间之间的路径一律虚线（不要求空间关系在 3D 成立）；
## 单房间内部物体摆放则按真实尺寸（见 BlueprintEditor2D）。点击选中、双击进入、拖拽平移、滚轮缩放。
## 这也是可视化编辑器的总览层：从这里双击房间即可进入该房间的 2D 蓝图。

const Geo := preload("res://scenes/dual_world/RoomGeometry.gd")
const DayNight := preload("res://scenes/dual_world/DayNight.gd")

signal room_selected(room_id: String)
signal room_activated(room_id: String)

const ZONE := {"A": "#2c3650", "B": "#3d3027", "C": "#233b36", "D": "#3b2939", "M": "#2d2c35", "F": "#3c3426", "X": "#29351f", "U": "#20242b", "S": "#17131b"}
const BRASS := Color("#b89758")
const INK := Color("#221c15")

var engine: RefCounted
var data: RefCounted
var selected := ""
var hour := 8.0
var author_view := false
var pan := Vector2(20, 24)
var zoom := 9.0
var _drag := false
var _drag_moved := false
var _last_click_ms := 0
var _last_click_room := ""


func setup(eng: RefCounted) -> void:
	engine = eng
	data = eng.d
	mouse_filter = Control.MOUSE_FILTER_STOP
	clip_contents = true
	fit()


func fit() -> void:
	if data == null or size.x < 10: return
	var minp := Vector2(INF, INF)
	var maxp := Vector2(-INF, -INF)
	for g in data.map_groups:
		minp = minp.min(Vector2(g.x, g.y))
		maxp = maxp.max(Vector2(g.x + g.w, g.y + g.h))
	var span := maxp - minp
	zoom = minf(size.x / span.x, size.y / span.y) * 0.96
	pan = -minp * zoom + (size - span * zoom) * 0.5
	queue_redraw()


func _w2s(p: Vector2) -> Vector2:
	return p * zoom + pan


func _room_rect(r: Dictionary) -> Rect2:
	var m: Dictionary = r.map
	return Rect2(_w2s(Vector2(m.x, m.y)), Vector2(m.w, m.h) * zoom)


func _room_center(r: Dictionary) -> Vector2:
	return _room_rect(r).get_center()


func _room_at(p: Vector2) -> String:
	for r in data.rooms:
		if _room_rect(r).has_point(p): return r.id
	return ""


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb: InputEventMouseButton = event
		if mb.button_index == MOUSE_BUTTON_WHEEL_UP or mb.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			var f := 1.12 if mb.button_index == MOUSE_BUTTON_WHEEL_UP else 1.0 / 1.12
			var wpos := (mb.position - pan) / zoom
			zoom = clampf(zoom * f, 2.0, 40.0)
			pan = mb.position - wpos * zoom
			queue_redraw()
		elif mb.button_index == MOUSE_BUTTON_LEFT or mb.button_index == MOUSE_BUTTON_MIDDLE:
			if mb.pressed:
				_drag = true
				_drag_moved = false
			else:
				_drag = false
				if not _drag_moved and mb.button_index == MOUSE_BUTTON_LEFT:
					var id := _room_at(mb.position)
					if id != "":
						var now := Time.get_ticks_msec()
						selected = id
						room_selected.emit(id)
						if id == _last_click_room and now - _last_click_ms < 420:
							room_activated.emit(id)
						_last_click_room = id
						_last_click_ms = now
						queue_redraw()
	elif event is InputEventMouseMotion and _drag:
		var mm: InputEventMouseMotion = event
		if mm.relative.length() > 0.5: _drag_moved = true
		pan += mm.relative
		queue_redraw()


func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED and data != null: fit()


func _draw() -> void:
	if data == null: return
	var font := get_theme_default_font()
	draw_rect(Rect2(Vector2.ZERO, size), Color("#14110e"))
	# 区域底色
	for g in data.map_groups:
		var rc := Rect2(_w2s(Vector2(g.x, g.y)), Vector2(g.w, g.h) * zoom)
		var col := Color(str(g.color))
		draw_rect(rc, Color(col, 0.55))
		draw_rect(rc, Color(BRASS, 0.18), false, 1.0)
		draw_string(font, rc.position + Vector2(6, 14), str(g.label), HORIZONTAL_ALIGNMENT_LEFT, rc.size.x - 8, 11, Color("#c9b89a"))
	# 门之间的路径：一律虚线；上锁用暗红
	for dr in data.doors:
		var ra: Dictionary = data.room_by_id.get(dr.a, {})
		var rb: Dictionary = data.room_by_id.get(dr.b, {})
		if ra.is_empty() or rb.is_empty(): continue
		var open: bool = engine.unlocked(dr)
		var c := Color("#e9c98a", 0.75) if open else Color("#a5442f", 0.7)
		draw_dashed_line(_room_center(ra), _room_center(rb), c, 1.5 if open else 1.2, 6.0, true)
	var occ: Dictionary = engine.room_occupants()
	var here: String = engine.s.room
	for r in data.rooms:
		var rc2 := _room_rect(r)
		var base := Color(str(ZONE.get(r.zone, "#2d2c35"))).lightened(0.12)
		draw_rect(rc2, Color(base, 0.96))
		var is_here: bool = r.id == here
		var border := Color("#e9c98a") if is_here else (Color("#4f9dde") if r.id == selected else Color(BRASS, 0.5))
		draw_rect(rc2, border, false, 2.5 if (is_here or r.id == selected) else 1.0)
		var label := str(r.label)
		draw_string(font, rc2.position + Vector2(4, 13), label, HORIZONTAL_ALIGNMENT_LEFT, rc2.size.x - 6, 10, Color("#efe6d6"))
		# 证物进度
		var evs: Array = data.evidence_by_room.get(r.id, [])
		if not evs.is_empty():
			var got := 0
			for e in evs:
				if engine.s.evidence.has(e.id): got += 1
			draw_string(font, rc2.position + Vector2(4, rc2.size.y - 5), "证 %d/%d" % [got, evs.size()], HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color("#d9a13a") if got < evs.size() else Color("#a8c89a"))
		# 人物小圆点
		var list: Array = occ.get(r.id, [])
		for i in list.size():
			var a: Dictionary = data.actor_by_id[list[i]]
			var pos := rc2.position + Vector2(rc2.size.x - 8 - i * 10.0, 20.0)
			if pos.x < rc2.position.x + 4: break
			draw_circle(pos, 4.0, Color(str(a.color)).lightened(0.25))
			draw_arc(pos, 4.0, 0, TAU, 12, Color(0, 0, 0, 0.6), 1.0)
	# 夜色暗幕：与时间同步（2D 也体现光线变化）
	var dark := Geo.darkness(hour)
	if dark > 0.0:
		draw_rect(Rect2(Vector2.ZERO, size), Color(0.04, 0.05, 0.12, dark * 0.85))
	draw_string(font, Vector2(10, size.y - 10), "点击房间 · 双击进入 · 拖拽平移 · 滚轮缩放　%s" % DayNight.label(hour), HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color("#a8957b"))
