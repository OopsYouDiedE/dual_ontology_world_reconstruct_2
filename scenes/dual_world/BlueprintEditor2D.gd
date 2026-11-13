extends Control
## 2D 可视化场景编辑器（单个房间的真实尺寸蓝图）。
## 墙体、地板、门窗、家具都在 2D 俯视图里设计；3D 实机用的是同一份设计字典（RoomGeometry）。
## 操作：左键选中/拖动家具或门窗（吸附网格）· R 旋转 90° · Delete 删除 · Ctrl+Z / Ctrl+Y 撤销重做 ·
##       [ ] 调整选中门窗宽度 · 滚轮缩放 · 中键拖动平移。
## 实时校验：落地家具是否越出地板、占地是否重叠、门窗是否超出墙段；不阻止摆放，但标红提示。

const Geo := preload("res://scenes/dual_world/RoomGeometry.gd")
const SANS_FONT := preload("res://assets/external/NotoSansSC/NotoSansSC[wght].ttf")

signal design_changed
signal selection_changed(text: String)

var design: Dictionary = {}
var data: RefCounted
var grid := 0.25
var snap_on := true
var hour := 12.0
var found: Dictionary = {}
var sel_kind := ""  # "prop" | "opening" | ""
var sel_id := ""
var scale_px := 60.0
var origin := Vector2(40, 40)
var _undo: Array = []
var _redo: Array = []
var _drag := false
var _drag_off := Vector2.ZERO
var _drag_changed := false
var _pan := false
var _issues: Array = []


func _ready() -> void:
	focus_mode = Control.FOCUS_ALL
	clip_contents = true


func set_design(ds: Dictionary, d: RefCounted = null) -> void:
	design = ds
	if d != null: data = d
	sel_kind = ""
	sel_id = ""
	_undo.clear()
	_redo.clear()
	fit()
	_revalidate()
	queue_redraw()


func fit() -> void:
	if design.is_empty() or size.x < 10: return
	scale_px = minf((size.x - 80.0) / design.w, (size.y - 80.0) / design.d)
	origin = Vector2((size.x - design.w * scale_px) * 0.5, (size.y - design.d * scale_px) * 0.5)


func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED:
		fit()
		queue_redraw()


func issues() -> Array:
	return _issues


func _revalidate() -> void:
	_issues = Geo.validate(design).issues if not design.is_empty() else []


func _w2s(x: float, z: float) -> Vector2:
	return origin + Vector2(x, z) * scale_px


func _s2w(p: Vector2) -> Vector2:
	return (p - origin) / scale_px


func _snap(v: float) -> float:
	return snappedf(v, grid) if snap_on else snappedf(v, 0.01)


# ───────────────────────── 撤销 / 重做 ─────────────────────────
func _push_undo() -> void:
	_undo.append(design.duplicate(true))
	if _undo.size() > 80: _undo.pop_front()
	_redo.clear()


func undo() -> void:
	if _undo.is_empty(): return
	_redo.append(design.duplicate(true))
	design = _undo.pop_back()
	_after_edit()


func redo() -> void:
	if _redo.is_empty(): return
	_undo.append(design.duplicate(true))
	design = _redo.pop_back()
	_after_edit()


func _after_edit() -> void:
	_revalidate()
	queue_redraw()
	design_changed.emit()
	_emit_selection()


# ───────────────────────── 编辑操作 ─────────────────────────
func _find_prop(id: String) -> Dictionary:
	for p in design.props:
		if p.id == id: return p
	return {}


func _find_opening(id: String) -> Dictionary:
	for o in design.walls[0].openings:
		if o.id == id: return o
	return {}


func add_prop(kind: String) -> void:
	if design.is_empty(): return
	_push_undo()
	var n := 1
	while not _find_prop("u_%s_%d" % [kind, n]).is_empty(): n += 1
	var p := {"id": "u_%s_%d" % [kind, n], "kind": kind, "x": snappedf(design.w * 0.5, 0.05), "z": snappedf(design.d * 0.5, 0.05), "yaw": 0.0, "params": {}}
	# 就近找一个不重叠的落点
	var dm := Geo.prop_dims(p)
	if dm.blocking:
		var best := Vector2(p.x, p.z)
		var found_free := false
		var step := 0.3
		var r := 0.0
		while r < maxf(design.w, design.d) and not found_free:
			for a in 16:
				var c := Vector2(design.w * 0.5, design.d * 0.5) + Vector2(cos(a * TAU / 16.0), sin(a * TAU / 16.0)) * r
				p.x = c.x
				p.z = c.y
				var ok := Geo.inside_floor(p, design)
				if ok:
					for q in design.props:
						if Geo.prop_dims(q).blocking and Geo.rects_overlap(p, q, 0.03): ok = false
				if ok:
					best = c
					found_free = true
					break
			r += step
		p.x = _snap(best.x)
		p.z = _snap(best.y)
	design.props.append(p)
	sel_kind = "prop"
	sel_id = p.id
	_after_edit()


func delete_selected() -> void:
	if sel_kind == "prop":
		_push_undo()
		design.props = design.props.filter(func(p): return p.id != sel_id)
		sel_kind = ""
		sel_id = ""
		_after_edit()
	elif sel_kind == "opening":
		_push_undo()
		design.walls[0].openings = design.walls[0].openings.filter(func(o): return o.id != sel_id)
		sel_kind = ""
		sel_id = ""
		_after_edit()


func rotate_selected(deg: float) -> void:
	if sel_kind != "prop": return
	var p := _find_prop(sel_id)
	if p.is_empty(): return
	_push_undo()
	p.yaw = fposmod(float(p.yaw) + deg + 180.0, 360.0) - 180.0
	_after_edit()


func resize_opening(delta: float) -> void:
	if sel_kind != "opening": return
	var o := _find_opening(sel_id)
	if o.is_empty(): return
	_push_undo()
	o.width = clampf(float(o.width) + delta, 0.6, 3.2)
	_after_edit()


func add_opening(type: String) -> void:
	_push_undo()
	var id := "op_u_%d" % (design.walls[0].openings.size() + Time.get_ticks_msec() % 1000)
	var seg_len: float = design.w
	design.walls[0].openings.append({"id": id, "segment": 0, "center": seg_len * 0.5, "width": 1.2, "type": type})
	sel_kind = "opening"
	sel_id = id
	_after_edit()


func reset_auto() -> void:
	if data == null or not data.room_by_id.has(design.room_id): return
	_push_undo()
	design = Geo.make_design(data.room_by_id[design.room_id], data)
	sel_kind = ""
	sel_id = ""
	_after_edit()


func _emit_selection() -> void:
	var text := ""
	if sel_kind == "prop":
		var p := _find_prop(sel_id)
		if not p.is_empty():
			var dm := Geo.prop_dims(p)
			text = "%s · (%.2f, %.2f) m · 朝向 %d° · 占地 %.2f×%.2f m" % [Geo.prop_label(str(p.kind)), p.x, p.z, int(p.yaw), dm.w, dm.d]
			if p.has("eid") and data != null: text += "\n证物：" + str(data.evidence_by_id[p.eid].label)
	elif sel_kind == "opening":
		var o := _find_opening(sel_id)
		if not o.is_empty():
			text = "%s · 墙段 %d · 中心 %.2f m · 宽 %.2f m" % [str(o.type), int(o.segment), o.center, o.width]
	selection_changed.emit(text)


# ───────────────────────── 输入 ─────────────────────────
func _opening_at(pw: Vector2) -> Dictionary:
	var wall: Dictionary = design.walls[0]
	for pc in Geo.wall_pieces(wall):
		if pc.kind != "opening": continue
		var seg: Dictionary = pc.seg
		var u: Vector2 = (seg.b - seg.a) / seg.len
		var rel: Vector2 = pw - seg.a
		var t: float = rel.dot(u)
		var dist := absf(rel.dot(Vector2(-u.y, u.x)))
		if dist < wall.thickness / 2.0 + 0.2 and t >= pc.t0 - 0.1 and t <= pc.t1 + 0.1:
			return pc.op
	return {}


func _gui_input(event: InputEvent) -> void:
	if design.is_empty(): return
	if event is InputEventMouseButton:
		var mb: InputEventMouseButton = event
		if mb.button_index == MOUSE_BUTTON_WHEEL_UP or mb.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			var f := 1.1 if mb.button_index == MOUSE_BUTTON_WHEEL_UP else 1.0 / 1.1
			var w := _s2w(mb.position)
			scale_px = clampf(scale_px * f, 12.0, 240.0)
			origin = mb.position - w * scale_px
			queue_redraw()
		elif mb.button_index == MOUSE_BUTTON_MIDDLE or mb.button_index == MOUSE_BUTTON_RIGHT:
			_pan = mb.pressed
		elif mb.button_index == MOUSE_BUTTON_LEFT:
			if mb.pressed:
				grab_focus()
				var pw := _s2w(mb.position)
				var hit := Geo.hit_prop(design, pw.x, pw.y)
				if not hit.is_empty():
					sel_kind = "prop"
					sel_id = hit.id
					_drag = true
					_drag_off = Vector2(hit.x, hit.z) - pw
					_drag_changed = false
				else:
					var op := _opening_at(pw)
					if not op.is_empty():
						sel_kind = "opening"
						sel_id = op.id
						_drag = true
						_drag_changed = false
					else:
						sel_kind = ""
						sel_id = ""
				_emit_selection()
				queue_redraw()
			else:
				_drag = false
	elif event is InputEventMouseMotion:
		var mm: InputEventMouseMotion = event
		if _pan:
			origin += mm.relative
			queue_redraw()
		elif _drag:
			var pw2 := _s2w(mm.position)
			if not _drag_changed:
				_push_undo()
				_drag_changed = true
			if sel_kind == "prop":
				var p := _find_prop(sel_id)
				if not p.is_empty():
					var t := pw2 + _drag_off
					p.x = clampf(_snap(t.x), 0.1, design.w - 0.1)
					p.z = clampf(_snap(t.y), 0.1, design.d - 0.1)
			elif sel_kind == "opening":
				var o := _find_opening(sel_id)
				if not o.is_empty():
					var segs := Geo.wall_segments(design.walls[0])
					var seg: Dictionary = segs[clampi(int(o.segment), 0, segs.size() - 1)]
					var u: Vector2 = (seg.b - seg.a) / seg.len
					var t2: float = (pw2 - seg.a).dot(u)
					o.center = clampf(_snap(t2), o.width / 2.0 + 0.15, seg.len - o.width / 2.0 - 0.15)
			_revalidate()
			_emit_selection()
			design_changed.emit()
			queue_redraw()
	elif event is InputEventKey and event.pressed:
		var k: InputEventKey = event
		match k.keycode:
			KEY_R: rotate_selected(90.0)
			KEY_DELETE, KEY_BACKSPACE: delete_selected()
			KEY_Z:
				if k.ctrl_pressed or k.meta_pressed: undo()
			KEY_Y:
				if k.ctrl_pressed or k.meta_pressed: redo()
			KEY_BRACKETLEFT: resize_opening(-0.1)
			KEY_BRACKETRIGHT: resize_opening(0.1)
		accept_event()


# ───────────────────────── 绘制 ─────────────────────────
func _draw() -> void:
	var font: Font = SANS_FONT
	draw_rect(Rect2(Vector2.ZERO, size), Color("#1a1612"))
	if design.is_empty():
		draw_string(font, size * 0.5 + Vector2(-120, 0), "未载入设计", HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color("#a8957b"))
		return
	# 顶部操作提示（编辑器易用性：不用记快捷键）
	draw_string(font, Vector2(10, 18), "点家具选中 → 拖动移动 · R 旋转 · Delete 删除 · 滚轮缩放 · 中键/右键平移 · [ ] 调门窗宽", HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color("#d8c9a8", 0.9))
	var w: float = design.w
	var d: float = design.d
	# 网格
	var x := 0.0
	while x <= w + 0.001:
		var major := is_equal_approx(fposmod(x, 1.0), 0.0)
		draw_line(_w2s(x, 0), _w2s(x, d), Color(1, 1, 1, 0.07 if major else 0.025), 1.0)
		x += grid if grid >= 0.25 else 0.25
	var z := 0.0
	while z <= d + 0.001:
		var major2 := is_equal_approx(fposmod(z, 1.0), 0.0)
		draw_line(_w2s(0, z), _w2s(w, z), Color(1, 1, 1, 0.07 if major2 else 0.025), 1.0)
		z += grid if grid >= 0.25 else 0.25
	# 地板（由墙中线内偏移派生）
	var fp := Geo.floor_polygon(design)
	var pts := PackedVector2Array()
	for p in fp: pts.append(_w2s(p.x, p.y))
	if pts.size() >= 3: draw_colored_polygon(pts, Color("#5a4630", 0.55))
	# 墙：按开洞切片，实心片画粗线，洞口画门/窗符号
	var wall: Dictionary = design.walls[0]
	var thick: float = wall.thickness * scale_px
	for pc in Geo.wall_pieces(wall):
		var seg: Dictionary = pc.seg
		var u: Vector2 = (seg.b - seg.a) / seg.len
		var a: Vector2 = seg.a + u * pc.t0
		var b: Vector2 = seg.a + u * pc.t1
		if pc.kind == "solid":
			draw_line(_w2s(a.x, a.y), _w2s(b.x, b.y), Color("#a0876b"), thick)
		else:
			var op: Dictionary = pc.op
			var selo: bool = sel_kind == "opening" and sel_id == op.id
			var col := Color("#4f9dde") if selo else (Color("#d9a13a") if op.type != "rectangular_window" else Color("#9fc6d6"))
			var n := Vector2(-u.y, u.x)
			draw_line(_w2s(a.x, a.y), _w2s(b.x, b.y), Color(col, 0.35), thick * 0.9)
			if op.type == "rectangular_window":
				for off in [-0.05, 0.05]:
					draw_line(_w2s(a.x + n.x * off, a.y + n.y * off), _w2s(b.x + n.x * off, b.y + n.y * off), col, 2.0)
			elif op.type == "closed_door":
				var hinge := _w2s(a.x, a.y)
				var tip := _w2s(a.x + n.x * op.width, a.y + n.y * op.width)
				draw_line(hinge, tip, col, 2.5)
				var ang0 := (_w2s(b.x, b.y) - hinge).angle()
				# 只画开门扫过的 90° 小弧：draw_arc 的起止顺序会绕 270° 画出大弧
				# （截图里那条冲出房间的黄线），故用 lerp_angle 逐点画最短弧。
				var arc_pts := PackedVector2Array()
				var a_tip := (tip - hinge).angle()
				for i in 17:
					var aa := lerp_angle(a_tip, ang0, float(i) / 16.0)
					arc_pts.append(hinge + Vector2(cos(aa), sin(aa)) * op.width * scale_px)
				draw_polyline(arc_pts, Color(col, 0.6), 1.0)
			else:
				draw_line(_w2s(a.x, a.y), _w2s(b.x, b.y), col, 3.0)
	# 家具：有向占地
	var bad := _bad_props()
	for p in design.props:
		var dm := Geo.prop_dims(p)
		var cs := Geo.prop_corners(p)
		var poly := PackedVector2Array()
		for c in cs: poly.append(_w2s(c.x, c.y))
		var col2 := Geo.prop_color(str(p.kind))
		var is_sel: bool = sel_kind == "prop" and sel_id == p.id
		if str(p.kind) == "evidence_marker":
			var got := found.has(str(p.get("eid", "")))
			col2 = Color("#7fbf6a") if got else Color("#d9a13a")
			draw_circle(_w2s(p.x, p.z), 0.17 * scale_px, Color(col2, 0.85))
			draw_arc(_w2s(p.x, p.z), 0.24 * scale_px, 0, TAU, 20, col2, 1.5)
		elif dm.has("circle"):
			draw_circle(_w2s(p.x, p.z), dm.circle * scale_px, Color(col2, 0.9))
		else:
			var alpha := 0.45 if dm.has("flat") else (0.8 if dm.has("mounted") else 0.95)
			draw_colored_polygon(poly, Color(col2, alpha))
			var outline := poly.duplicate()
			outline.append(poly[0])
			draw_polyline(outline, Color("#ff5a4a") if bad.has(p.id) else Color(0, 0, 0, 0.55), 2.0 if bad.has(p.id) else 1.0)
			# 正面朝向短线
			var fv := Geo.front_vec(p.yaw)
			draw_line(_w2s(p.x, p.z), _w2s(p.x + fv.x * dm.d * 0.5, p.z + fv.y * dm.d * 0.5), Color(1, 1, 1, 0.55), 1.5)
		if is_sel:
			var o2 := poly.duplicate()
			o2.append(poly[0])
			draw_polyline(o2, Color("#4f9dde"), 2.5)
		if scale_px > 28.0 and str(p.kind) != "evidence_marker":
			draw_string(font, _w2s(p.x, p.z) + Vector2(-30, 4), Geo.prop_label(str(p.kind)), HORIZONTAL_ALIGNMENT_CENTER, 60, 12, Color("#fff4dc", 0.95))
	# 尺寸标注（移到顶部提示下方，避免与提示重叠）
	draw_string(font, Vector2(10, 36), "%s　%.1f × %.1f m　网格 %.2f m%s" % [design.name, w, d, grid, "（吸附）" if snap_on else ""], HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color("#e6d7b8"))
	# 昼夜暗幕
	var dark := Geo.darkness(hour)
	if dark > 0.0: draw_rect(Rect2(Vector2.ZERO, size), Color(0.04, 0.05, 0.12, dark * 0.5))


func _bad_props() -> Dictionary:
	var bad := {}
	var blocking: Array = design.props.filter(func(p): return Geo.prop_dims(p).blocking)
	for p in blocking:
		if not Geo.inside_floor(p, design): bad[p.id] = true
	for i in blocking.size():
		for j in range(i + 1, blocking.size()):
			if Geo.rects_overlap(blocking[i], blocking[j], 0.0):
				bad[blocking[i].id] = true
				bad[blocking[j].id] = true
	return bad
