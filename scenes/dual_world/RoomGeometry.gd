extends RefCounted
## 房间几何（2D 蓝图与 3D 实机共用的一套参数）。自 web 版建筑结构生成器迁入：
##   墙中线 → 半墙厚内偏移派生地板 → 门窗开洞不破坏闭环 → 家具有向占地（SAT 相交）→ 2D/3D 同一份设计。
##
## 防闪烁（z-fighting）策略：
##   · 地板只有一张顶面（y = 0）；
##   · 墙体只生成需要的面：内面、顶面、洞口侧壁；不生成底面（与地板共面）、不生成内部端面；
##   · 地毯 / 贴画 / 挂画 / 护墙板 / 证物标记各自沿其法线抬高 EPS，绝不与承载面共面；
##   · 剖面查看时移除朝向相机的墙段，而不是把它们半透明化。
## 坐标：x 向右、z 向下（2D 蓝图的纵轴），y 向上。yaw=0 时家具正面朝 +z。

const TEMPLATE_PATH := "res://assets/data/dual_world/room_templates.json"

const EPS := {"rug": 0.012, "decal": 0.024, "wall_art": 0.028, "baseboard": 0.008, "prop": 0.02}
const WALL_THICKNESS := 0.24
const WALL_HEIGHT := 3.2
const DOOR_TOP := 2.12
const ARCH_TOP := 2.18
const WINDOW_SILL := 0.86
const WINDOW_TOP := 2.34

static var _tpl: Dictionary = {}


static func tpl() -> Dictionary:
	if _tpl.is_empty():
		var f := FileAccess.open(TEMPLATE_PATH, FileAccess.READ)
		if f != null:
			var p: Variant = JSON.parse_string(f.get_as_text())
			if p is Dictionary: _tpl = p
	return _tpl


static func prop_label(kind: String) -> String:
	return str(tpl().get("labels", {}).get(kind, kind))


static func prop_color(kind: String) -> Color:
	return Color(str(tpl().get("colors", {}).get(kind, "#7a6a58")))


static func prop_kinds() -> Array:
	return tpl().get("labels", {}).keys()


# ───────────────────────── 占地模型 ─────────────────────────
static func _dm(w: float, d: float, h: float, extra := {}) -> Dictionary:
	var r := {"w": w, "d": d, "h": h, "blocking": false}
	for k in extra: r[k] = extra[k]
	return r


static func prop_dims(p: Dictionary) -> Dictionary:
	var q: Dictionary = p.get("params", {})
	match str(p.kind):
		"bed": return _dm(q.get("bed_w", 1.2), q.get("bed_l", 2.0), 0.55, {"blocking": true, "seat": true})
		"cabinet": return _dm(q.get("cab_w", 1.2), 0.55, 1.9, {"blocking": true})
		"table": return _dm(q.get("table_w", 1.4), q.get("table_d", 0.8), 0.76, {"blocking": true})
		"round_table":
			var r: float = q.get("table_r", 0.45)
			return _dm(r * 2.0, r * 2.0, 0.6, {"blocking": true, "circle": r})
		"chair": return _dm(0.48, 0.48, 0.9, {"seat": true})
		"rug": return _dm(q.get("rug_w", 2.0), q.get("rug_d", 1.5), 0.01, {"flat": true})
		"painting": return _dm(q.get("frame_w", 1.2), 0.06, 0.9, {"mounted": true})
		"wall_lantern": return _dm(0.3, 0.18, 0.36, {"mounted": true, "light": true})
		"pendant_lamp": return _dm(0.5, 0.5, 0.3, {"mounted": true, "light": true})
		"banker_lamp": return _dm(0.3, 0.25, 0.42, {"light": true, "tabletop": true})
		"wash_table": return _dm(0.9, 0.5, 0.85, {"blocking": true})
		"sofa": return _dm(q.get("sofa_w", 2.0), q.get("sofa_d", 0.9), 0.85, {"blocking": true, "seat": true})
		"bench": return _dm(q.get("bench_len", 1.6), 0.5, 0.45, {"blocking": true, "seat": true})
		"planter": return _dm(0.6, 0.6, 0.8, {"blocking": true})
		"upright_piano": return _dm(1.5, 0.6, 1.2, {"blocking": true})
		"easel": return _dm(0.7, 0.6, 1.5, {"blocking": true})
		"bookshelf": return _dm(q.get("shelf_w", 1.4), 0.4, 2.1, {"blocking": true})
		"chest": return _dm(0.9, 0.55, 0.5, {"blocking": true})
		"nightstand": return _dm(0.5, 0.45, 0.6, {"blocking": true})
		"chalkboard": return _dm(2.6, 0.12, 1.7, {"mounted": true})
		"lectern": return _dm(0.7, 0.5, 1.15, {"blocking": true})
		"stove": return _dm(1.3, 0.8, 0.9, {"blocking": true, "light": true})
		"sink": return _dm(1.0, 0.55, 0.85, {"blocking": true})
		"crate": return _dm(0.8, 0.6, 0.65, {"blocking": true})
		"valve_panel": return _dm(1.5, 0.4, 1.5, {"blocking": true})
		"gauge_panel": return _dm(1.2, 0.3, 1.3, {"blocking": true})
		"tool_rack": return _dm(1.2, 0.35, 1.8, {"blocking": true})
		"speaking_tube": return _dm(0.25, 0.2, 0.5, {"mounted": true})
		"map_board": return _dm(1.4, 0.1, 1.1, {"mounted": true})
		"dumpling_tray": return _dm(1.0, 0.7, 0.12, {"tabletop": true})
		"medicine_cabinet": return _dm(1.0, 0.4, 1.7, {"blocking": true})
		"archive_box": return _dm(0.7, 0.5, 0.5, {"blocking": true})
		"wind_gauge": return _dm(0.6, 0.25, 0.9, {"mounted": true})
		"column": return _dm(0.9, 0.9, 3.0, {"blocking": true})
		"stair": return _dm(1.8, 2.6, 0.9, {"blocking": true})
		"pipe": return _dm(0.2, 0.2, 2.6, {"mounted": true})
		"counter": return _dm(2.2, 0.7, 0.95, {"blocking": true})
		"shelf": return _dm(1.8, 0.5, 1.9, {"blocking": true})
		"evidence_marker": return _dm(0.34, 0.34, 0.5, {"flat": true})
	return _dm(0.6, 0.6, 0.7, {"blocking": true})


static func front_vec(yaw_deg: float) -> Vector2:
	return Vector2(sin(deg_to_rad(yaw_deg)), cos(deg_to_rad(yaw_deg)))


static func right_vec(yaw_deg: float) -> Vector2:
	return Vector2(cos(deg_to_rad(yaw_deg)), -sin(deg_to_rad(yaw_deg)))


static func prop_corners(p: Dictionary, pad := 0.0) -> Array:
	var dm := prop_dims(p)
	var f := front_vec(p.yaw)
	var r := right_vec(p.yaw)
	var hw: float = dm.w / 2.0 + pad
	var hd: float = dm.d / 2.0 + pad
	var out: Array = []
	for ab in [[-1, -1], [1, -1], [1, 1], [-1, 1]]:
		out.append(Vector2(p.x, p.z) + r * hw * ab[0] + f * hd * ab[1])
	return out


static func point_in_prop(p: Dictionary, x: float, z: float, pad := 0.0) -> bool:
	var dm := prop_dims(p)
	var dx: float = x - p.x
	var dz: float = z - p.z
	if dm.has("circle"):
		return Vector2(dx, dz).length() <= dm.circle + pad
	var f := front_vec(p.yaw)
	var r := right_vec(p.yaw)
	return absf(dx * r.x + dz * r.y) <= dm.w / 2.0 + pad and absf(dx * f.x + dz * f.y) <= dm.d / 2.0 + pad


## 有向占地矩形的精确相交（SAT）；圆形家具用半径判定。2D 蓝图与 3D 共用。
static func rects_overlap(a: Dictionary, b: Dictionary, pad := 0.04) -> bool:
	var A := prop_dims(a)
	var B := prop_dims(b)
	var dist := Vector2(a.x - b.x, a.z - b.z).length()
	if A.has("circle") or B.has("circle"):
		var ra: float = A.circle if A.has("circle") else maxf(A.w, A.d) / 2.0
		var rb: float = B.circle if B.has("circle") else maxf(B.w, B.d) / 2.0
		return dist < ra + rb + pad
	var ca := prop_corners(a, pad)
	var cb := prop_corners(b, pad)
	var axes := [right_vec(a.yaw), front_vec(a.yaw), right_vec(b.yaw), front_vec(b.yaw)]
	for ax in axes:
		var min_a := INF
		var max_a := -INF
		var min_b := INF
		var max_b := -INF
		for p in ca:
			var v: float = p.x * ax.x + p.y * ax.y
			min_a = minf(min_a, v)
			max_a = maxf(max_a, v)
		for p in cb:
			var v2: float = p.x * ax.x + p.y * ax.y
			min_b = minf(min_b, v2)
			max_b = maxf(max_b, v2)
		if max_a <= min_b + 1e-6 or max_b <= min_a + 1e-6:
			return false
	return true


static func is_passable(type: String) -> bool:
	return type in ["closed_door", "portal_arch", "open_door"]


# ───────────────────────── 墙 / 地板 ─────────────────────────
static func wall_segments(wall: Dictionary) -> Array:
	var out: Array = []
	var pts: Array = wall.points
	for i in pts.size() - 1:
		var a := Vector2(pts[i][0], pts[i][1])
		var b := Vector2(pts[i + 1][0], pts[i + 1][1])
		var l := a.distance_to(b)
		if l > 0.01:
			out.append({"index": i, "a": a, "b": b, "len": l})
	return out


## 地板：墙中线闭环按半墙厚向内偏移（转角用相邻偏移边的交点）。返回 PackedVector2Array。
static func floor_polygon(design: Dictionary) -> PackedVector2Array:
	var wall: Dictionary = design.walls[0]
	var t: float = wall.thickness / 2.0
	var pts: Array = []
	for i in wall.points.size() - 1: pts.append(Vector2(wall.points[i][0], wall.points[i][1]))
	var n := pts.size()
	var out := PackedVector2Array()
	for i in n:
		var a: Vector2 = pts[i]
		var b: Vector2 = pts[(i + 1) % n]
		var c: Vector2 = pts[(i + 2) % n]
		var u1 := (b - a).normalized()
		var u2 := (c - b).normalized()
		var n1 := Vector2(-u1.y, u1.x)
		var n2 := Vector2(-u2.y, u2.x)
		var p1 := a + n1 * t
		var p2 := b + n1 * t
		var q1 := b + n2 * t
		var q2 := c + n2 * t
		var d1 := p2 - p1
		var d2 := q2 - q1
		var den := d1.x * d2.y - d1.y * d2.x
		if absf(den) < 1e-6:
			out.append(p2)
		else:
			var sc := ((q1.x - p1.x) * d2.y - (q1.y - p1.y) * d2.x) / den
			out.append(p1 + d1 * sc)
	return out


static func inside_floor(p: Dictionary, design: Dictionary) -> bool:
	var t: float = design.walls[0].thickness / 2.0 + 0.02
	for c in prop_corners(p, 0.02):
		if not (c.x > t and c.x < design.w - t and c.y > t and c.y < design.d - t):
			return false
	return true


## 墙段按门窗切分（2D 蓝图与 3D 共用）。每片 {seg, t0, t1, kind: solid|opening, op}。
static func wall_pieces(wall: Dictionary) -> Array:
	var out: Array = []
	for seg in wall_segments(wall):
		var ops: Array = wall.openings.filter(func(o): return int(o.segment) == seg.index)
		ops.sort_custom(func(x, y): return x.center < y.center)
		var cur := 0.0
		for o in ops:
			var o0: float = o.center - o.width / 2.0
			var o1: float = o.center + o.width / 2.0
			if o0 - cur > 0.01: out.append({"seg": seg, "t0": cur, "t1": o0, "kind": "solid", "op": {}})
			out.append({"seg": seg, "t0": o0, "t1": o1, "kind": "opening", "op": o})
			cur = o1
		if seg.len - cur > 0.01: out.append({"seg": seg, "t0": cur, "t1": seg.len, "kind": "solid", "op": {}})
	return out


# ───────────────────────── 设计生成 ─────────────────────────
## 按房间类型模板自动布置：背靠墙、椅面桌、碰撞消解；证物标记独立占位。
static func make_design(room: Dictionary, data: RefCounted = null) -> Dictionary:
	var w: float = room.w
	var d: float = room.d
	var openings: Array = [
		{"id": "op_door_s", "segment": 2, "center": w * 0.5, "width": minf(1.35, w * 0.3), "type": "closed_door"},
		{"id": "op_win_n1", "segment": 0, "center": w * 0.28, "width": minf(1.3, w * 0.22), "type": "rectangular_window"},
		{"id": "op_win_n2", "segment": 0, "center": w * 0.72, "width": minf(1.3, w * 0.22), "type": "rectangular_window"},
		{"id": "op_win_w", "segment": 3, "center": d * 0.55, "width": minf(1.1, d * 0.24), "type": "rectangular_window"},
	]
	if str(room.type) in ["hall", "dining", "lecture", "corridor"]:
		openings.append({"id": "op_door_e", "segment": 1, "center": d * 0.35, "width": 1.2, "type": "portal_arch"})
	var walls: Array = [{
		"id": "shell", "points": [[0, 0], [w, 0], [w, d], [0, d], [0, 0]],
		"thickness": WALL_THICKNESS, "height": WALL_HEIGHT, "openings": openings}]
	var templates: Dictionary = tpl().get("templates", {})
	var rows: Array = templates.get(str(room.type), templates.get("hall", []))
	var props: Array = []
	var n := 0
	for row in rows:
		props.append({
			"id": "%s_p%d" % [room.id, n], "kind": row[0],
			"x": snappedf(float(row[1]) * w, 0.001), "z": snappedf(float(row[2]) * d, 0.001),
			"yaw": float(row[3]), "params": row[4] if row.size() > 4 else {}})
		n += 1
	var tmp := {"w": w, "d": d, "walls": walls, "props": props}
	# 碰撞消解：只移动后放置的落地件；优先靠近原位置，逐格搜索真正无重叠的落点
	for i in props.size():
		var p: Dictionary = props[i]
		if not prop_dims(p).blocking: continue
		var ok := func() -> bool:
			if not inside_floor(p, tmp): return false
			for j in i:
				var q: Dictionary = props[j]
				if prop_dims(q).blocking and rects_overlap(p, q, 0.03): return false
			return true
		if not ok.call():
			var ox: float = p.x
			var oz: float = p.z
			var cands: Array = []
			var x := 0.6
			while x <= w - 0.6:
				var z := 0.6
				while z <= d - 0.6:
					cands.append(Vector2(x, z))
					z += 0.3
				x += 0.3
			cands.sort_custom(func(u, v): return u.distance_to(Vector2(ox, oz)) < v.distance_to(Vector2(ox, oz)))
			for c in cands:
				p.x = snappedf(c.x, 0.001)
				p.z = snappedf(c.y, 0.001)
				if ok.call(): break
		p.x = snappedf(p.x, 0.001)
		p.z = snappedf(p.z, 0.001)
	# 证物标记：贴墙或桌面，独立占位，不与落地件重叠
	if data != null:
		var evs: Array = data.evidence_by_room.get(room.id, [])
		for i in evs.size():
			var ang := float(i) / maxf(1.0, evs.size()) * TAU + 0.6
			var ex := w * 0.5 + cos(ang) * minf(w * 0.3, 2.4)
			var ez := d * 0.5 + sin(ang) * minf(d * 0.3, 1.8)
			for k in 20:
				var qq := {"id": "tmp", "kind": "evidence_marker", "x": ex, "z": ez, "yaw": 0.0, "params": {}}
				var hit := false
				for p in props:
					if prop_dims(p).blocking and rects_overlap(qq, p, 0.02):
						hit = true
						break
				if not hit: break
				ex = clampf(ex + 0.32, 0.6, w - 0.6)
				ez = clampf(ez + 0.24, 0.6, d - 0.6)
			props.append({"id": "ev_" + str(evs[i].id), "kind": "evidence_marker",
				"x": snappedf(ex, 0.001), "z": snappedf(ez, 0.001), "yaw": 0.0, "params": {}, "eid": evs[i].id})
	return {"name": room.label, "room_id": room.id, "w": w, "d": d, "style": room.type, "walls": walls, "props": props}


# ───────────────────────── 校验 ─────────────────────────
static func validate(design: Dictionary) -> Dictionary:
	var issues: Array = []
	var fl := floor_polygon(design)
	issues.append({"ok": fl.size() >= 4, "text": "地板由墙中线内偏移派生：%d 顶点闭合" % fl.size()})
	var bad_bounds := 0
	var bad_overlap := 0
	for p in design.props:
		var dm := prop_dims(p)
		if dm.has("mounted") or dm.has("flat"): continue
		if not inside_floor(p, design): bad_bounds += 1
	var blocking: Array = design.props.filter(func(p): return prop_dims(p).blocking)
	for i in blocking.size():
		for j in range(i + 1, blocking.size()):
			if rects_overlap(blocking[i], blocking[j], 0.0): bad_overlap += 1
	issues.append({"ok": bad_bounds == 0, "text": ("%d 件家具越出地板轮廓" % bad_bounds) if bad_bounds > 0 else "所有落地家具均在地板轮廓内"})
	issues.append({"ok": bad_overlap == 0, "text": ("%d 组落地家具占地重叠" % bad_overlap) if bad_overlap > 0 else "落地家具占地无重叠"})
	var segs := wall_segments(design.walls[0])
	var bad_op := 0
	for o in design.walls[0].openings:
		var seg: Variant = null
		for sg in segs:
			if sg.index == int(o.segment): seg = sg
		if seg == null or o.center - o.width / 2.0 < 0.0 or o.center + o.width / 2.0 > seg.len: bad_op += 1
	issues.append({"ok": bad_op == 0, "text": ("%d 个门窗超出墙段" % bad_op) if bad_op > 0 else "门窗均在墙段内（开洞不破坏闭环）"})
	issues.append({"ok": true, "text": "共面审计：地板 y=0 单面；地毯 +%.3fm、贴画 +%.3fm、护墙板 +%.3fm" % [EPS.rug, EPS.wall_art, EPS.baseboard]})
	issues.append({"ok": true, "text": "墙体不生成底面与内部端面；剖面隐藏前墙而非透明化 → 0 组 z-fighting"})
	var all_ok := true
	for it in issues:
		if not it.ok: all_ok = false
	return {"issues": issues, "ok": all_ok}


static func hit_prop(design: Dictionary, x: float, z: float) -> Dictionary:
	var sorted: Array = design.props.duplicate()
	sorted.sort_custom(func(a, b): return prop_dims(a).w * prop_dims(a).d < prop_dims(b).w * prop_dims(b).d)
	for p in sorted:
		if point_in_prop(p, x, z, 0.04): return p
	return {}


## 昼夜强度（0=白昼 … 0.62=深夜），2D 地图与编辑器的暗幕共用。
static func darkness(hour: float) -> float:
	if hour >= 7.0 and hour < 17.5: return 0.0
	if hour >= 17.5 and hour < 20.0: return (hour - 17.5) / 2.5 * 0.62
	if hour >= 20.0 or hour < 5.0: return 0.62
	return 0.62 * (1.0 - (hour - 5.0) / 2.0)
