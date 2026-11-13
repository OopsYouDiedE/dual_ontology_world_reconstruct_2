extends Node3D
## 单房间 3D 生成器：读取 RoomGeometry 的设计字典，生成地板、墙、门窗、家具与证物标记。
## 3D 实机只显示一间房（参考同类游戏的做法）；设计与 2D 蓝图编辑器共用同一份数据。
##
## 防闪烁：见 RoomGeometry 文件头。所有「贴面」件（护墙板、挂画、地毯、证物标记）都沿法线抬高 EPS，
## 墙体不生成底面与内部端面，剖面隐藏朝向相机的墙段（而不是半透明化）。

const Geo := preload("res://scenes/dual_world/RoomGeometry.gd")

signal marker_picked(eid: String)

var design: Dictionary = {}
var lamps: Array = []
var glow_materials: Array = []
var evidence_nodes: Dictionary = {}
var _walls_root: Node3D
var _static_root: Node3D
var _hidden_key := ""
var _wood_tex: ImageTexture
var found: Dictionary = {}


func build(ds: Dictionary, found_evidence: Dictionary = {}) -> void:
	design = ds
	found = found_evidence
	for c in get_children(): c.queue_free()
	lamps.clear()
	glow_materials.clear()
	evidence_nodes.clear()
	_static_root = Node3D.new()
	_static_root.name = "Static"
	add_child(_static_root)
	_static_root.add_child(_build_floor())
	for p in design.props:
		var n := _build_prop(p)
		if n != null: _static_root.add_child(n)
	_walls_root = Node3D.new()
	_walls_root.name = "Walls"
	add_child(_walls_root)
	_hidden_key = "?"
	refresh_walls(0.0)


func center() -> Vector3:
	return Vector3(design.w * 0.5, 1.0, design.d * 0.5)


# ───────────────────────── 基础网格工具 ─────────────────────────
## 追加一个三角形并强制其朝向 normal（Godot 以顺时针为正面，故叉积与法线反向时才是正面）。
func _tri(arr: Dictionary, a: Vector3, b: Vector3, c: Vector3, normal: Vector3, uv_scale := 0.4) -> void:
	var cr := (b - a).cross(c - a)
	var pts := [a, b, c]
	if cr.dot(normal) > 0.0:
		pts = [a, c, b]
	for p in pts:
		arr.pos.append(p)
		arr.nrm.append(normal)
		arr.uv.append(Vector2(p.x + p.y * 0.0, p.z) * uv_scale if absf(normal.y) > 0.5 else Vector2(p.x + p.z, p.y) * uv_scale)


func _quad(arr: Dictionary, a: Vector3, b: Vector3, c: Vector3, d: Vector3, normal: Vector3, uv_scale := 0.4) -> void:
	_tri(arr, a, b, c, normal, uv_scale)
	_tri(arr, a, c, d, normal, uv_scale)


func _new_arr() -> Dictionary:
	return {"pos": PackedVector3Array(), "nrm": PackedVector3Array(), "uv": PackedVector2Array()}


func _mesh_from(arr: Dictionary) -> ArrayMesh:
	var m := ArrayMesh.new()
	if arr.pos.is_empty(): return m
	var a := []
	a.resize(Mesh.ARRAY_MAX)
	a[Mesh.ARRAY_VERTEX] = arr.pos
	a[Mesh.ARRAY_NORMAL] = arr.nrm
	a[Mesh.ARRAY_TEX_UV] = arr.uv
	m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, a)
	return m


func _mat(color: Variant, rough := 0.85, metal := 0.0) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(color)
	m.roughness = rough
	m.metallic = metal
	return m


func _glow_mat(color: Variant) -> StandardMaterial3D:
	var m := _mat(color, 0.4)
	m.emission_enabled = true
	m.emission = Color(color)
	m.emission_energy_multiplier = 0.5
	glow_materials.append(m)
	return m


func _box(size: Vector3, color: Variant, pos: Vector3, rough := 0.85, metal := 0.0) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.material_override = _mat(color, rough, metal)
	mi.position = pos
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	return mi


func _cyl(r_top: float, r_bot: float, h: float, color: Variant, pos: Vector3, seg := 14, mat: Material = null) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = r_top
	cm.bottom_radius = r_bot
	cm.height = h
	cm.radial_segments = seg
	cm.rings = 1
	mi.mesh = cm
	mi.material_override = mat if mat != null else _mat(color)
	mi.position = pos
	return mi


# ───────────────────────── 地板 ─────────────────────────
func _wood_texture() -> ImageTexture:
	if _wood_tex != null: return _wood_tex
	var img := Image.create(256, 256, true, Image.FORMAT_RGB8)
	img.fill(Color("#6b5038"))
	for y in 16:
		for x in 4:
			var off := (y % 2) * 32
			var hue := 28.0 / 360.0
			var sat := (30 + ((x * 7 + y * 13) % 12)) / 100.0
			var val := (26 + ((x * 11 + y * 5) % 11)) / 100.0 + 0.1
			var col := Color.from_hsv(hue, sat + 0.2, val + 0.12)
			for px in range(x * 64 + off - 32, x * 64 + off + 30):
				for py in range(y * 16, y * 16 + 15):
					img.set_pixel(posmod(px, 256), py, col)
	img.generate_mipmaps()
	_wood_tex = ImageTexture.create_from_image(img)
	return _wood_tex


func _build_floor() -> MeshInstance3D:
	var fp := Geo.floor_polygon(design)
	var idx := Geometry2D.triangulate_polygon(fp)
	var arr := _new_arr()
	for i in range(0, idx.size(), 3):
		var a := fp[idx[i]]
		var b := fp[idx[i + 1]]
		var c := fp[idx[i + 2]]
		_tri(arr, Vector3(a.x, 0, a.y), Vector3(b.x, 0, b.y), Vector3(c.x, 0, c.y), Vector3.UP, 0.5)
	var mi := MeshInstance3D.new()
	mi.name = "Floor"
	mi.mesh = _mesh_from(arr)  # 只有一张顶面：没有底面、没有与墙共面的端面
	var m := _mat("#ffffff", 0.88)
	m.albedo_texture = _wood_texture()
	m.uv1_scale = Vector3(1, 1, 1)
	mi.material_override = m
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return mi


# ───────────────────────── 墙（随相机方位重建） ─────────────────────────
## 剖面：移除朝向相机一侧的墙段，而不是把它们透明化。
func hidden_segments(cam_azimuth: float) -> Array:
	var cx: float = design.w / 2.0
	var cz: float = design.d / 2.0
	var vx := sin(cam_azimuth)
	var vz := cos(cam_azimuth)
	var hidden: Array = []
	for seg in Geo.wall_segments(design.walls[0]):
		var u: Vector2 = (seg.b - seg.a) / seg.len
		var out := Vector2(u.y, -u.x)  # 朝室外
		var mid: Vector2 = (seg.a + seg.b) / 2.0
		if out.x * vx + out.y * vz > 0.25 or ((mid.x - cx) * vx + (mid.y - cz) * vz) > 0.1:
			hidden.append(seg.index)
	return hidden


func refresh_walls(cam_azimuth: float) -> void:
	var hidden := hidden_segments(cam_azimuth)
	var key := ",".join(hidden.map(func(i): return str(i)))
	if key == _hidden_key: return
	_hidden_key = key
	for c in _walls_root.get_children(): c.queue_free()
	var wall: Dictionary = design.walls[0]
	var pieces: Array = Geo.wall_pieces(wall).filter(func(p): return not hidden.has(p.seg.index))
	var h: float = wall.thickness / 2.0
	var top: float = wall.height
	var arr := _new_arr()
	for pc in pieces:
		var seg: Dictionary = pc.seg
		var u: Vector2 = (seg.b - seg.a) / seg.len
		var n := Vector2(-u.y, u.x)  # 朝室内
		var P := func(t: float, off: float, y: float) -> Vector3:
			return Vector3(seg.a.x + u.x * t + n.x * off, y, seg.a.y + u.y * t + n.y * off)
		var spans: Array = [[0.0, top]]
		if pc.kind == "opening":
			match str(pc.op.type):
				"rectangular_window": spans = [[0.0, Geo.WINDOW_SILL], [Geo.WINDOW_TOP, top]]
				"portal_arch": spans = [[Geo.ARCH_TOP, top]]
				_: spans = [[Geo.DOOR_TOP, top]]
		var n3 := Vector3(n.x, 0, n.y)
		var u3 := Vector3(u.x, 0, u.y)
		for sp in spans:
			var y0: float = sp[0]
			var y1: float = sp[1]
			_quad(arr, P.call(pc.t0, h, y0), P.call(pc.t1, h, y0), P.call(pc.t1, h, y1), P.call(pc.t0, h, y1), n3, 0.35)  # 内面
			_quad(arr, P.call(pc.t0, h, y1), P.call(pc.t1, h, y1), P.call(pc.t1, -h, y1), P.call(pc.t0, -h, y1), Vector3.UP, 0.35)  # 顶面
			# 底面跳过：与地板共面；只在洞口处补侧壁，墙体内部端面不生成
			if pc.t0 > 0.02:
				_quad(arr, P.call(pc.t0, -h, y0), P.call(pc.t0, h, y0), P.call(pc.t0, h, y1), P.call(pc.t0, -h, y1), -u3, 0.35)
			if pc.t1 < seg.len - 0.02:
				_quad(arr, P.call(pc.t1, h, y0), P.call(pc.t1, -h, y0), P.call(pc.t1, -h, y1), P.call(pc.t1, h, y1), u3, 0.35)
			if pc.kind == "opening" and y0 > 0.0 and y0 < top and sp == spans[0]:
				pass
		# 洞口上沿/窗台的横向侧壁（窗洞下沿朝上、上沿朝下），同样只在洞内可见
		if pc.kind == "opening":
			var lo: float = Geo.WINDOW_SILL if pc.op.type == "rectangular_window" else 0.0
			var hi: float = Geo.WINDOW_TOP if pc.op.type == "rectangular_window" else (Geo.ARCH_TOP if pc.op.type == "portal_arch" else Geo.DOOR_TOP)
			if lo > 0.0:
				_quad(arr, P.call(pc.t0, h, lo), P.call(pc.t1, h, lo), P.call(pc.t1, -h, lo), P.call(pc.t0, -h, lo), Vector3.UP, 0.35)
			_quad(arr, P.call(pc.t0, -h, hi), P.call(pc.t1, -h, hi), P.call(pc.t1, h, hi), P.call(pc.t0, h, hi), Vector3.DOWN, 0.35)
	var mi := MeshInstance3D.new()
	mi.name = "WallShell"
	mi.mesh = _mesh_from(arr)
	var wm := _mat("#8c735b", 0.92)
	mi.material_override = wm
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	_walls_root.add_child(mi)
	_build_baseboards(pieces, wall)
	_build_openings(pieces, wall)


func _build_baseboards(pieces: Array, wall: Dictionary) -> void:
	var arr := _new_arr()
	var hh: float = wall.thickness / 2.0 + Geo.EPS.baseboard  # 贴内面但不共面：内移 EPS
	for pc in pieces:
		if pc.kind == "opening" and pc.op.type != "rectangular_window": continue
		var seg: Dictionary = pc.seg
		var u: Vector2 = (seg.b - seg.a) / seg.len
		var n := Vector2(-u.y, u.x)
		var P := func(t: float, y: float) -> Vector3:
			return Vector3(seg.a.x + u.x * t + n.x * hh, y, seg.a.y + u.y * t + n.y * hh)
		_quad(arr, P.call(pc.t0, 0.02), P.call(pc.t1, 0.02), P.call(pc.t1, 0.19), P.call(pc.t0, 0.19), Vector3(n.x, 0, n.y), 0.6)
	var mi := MeshInstance3D.new()
	mi.name = "Baseboard"
	mi.mesh = _mesh_from(arr)
	mi.material_override = _mat("#4a3527", 0.8)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_walls_root.add_child(mi)


func _build_openings(pieces: Array, wall: Dictionary) -> void:
	for pc in pieces:
		if pc.kind != "opening": continue
		var seg: Dictionary = pc.seg
		var op: Dictionary = pc.op
		var u: Vector2 = (seg.b - seg.a) / seg.len
		var n := Vector2(-u.y, u.x)
		var c: Vector2 = seg.a + u * op.center
		var yaw := atan2(-u.y, u.x)
		if op.type == "closed_door":
			var leaf := _box(Vector3(op.width * 0.94, 2.05, 0.06), "#4a3324", Vector3(c.x - n.x * 0.02, 1.03, c.y - n.y * 0.02))
			leaf.rotation.y = yaw
			_walls_root.add_child(leaf)
			var knob := MeshInstance3D.new()
			var sm := SphereMesh.new()
			sm.radius = 0.045
			sm.height = 0.09
			sm.radial_segments = 8
			sm.rings = 6
			knob.mesh = sm
			knob.material_override = _mat("#d9a13a", 0.3, 0.7)
			knob.position = Vector3(c.x + u.x * op.width * 0.3 + n.x * 0.05, 1.0, c.y + u.y * op.width * 0.3 + n.y * 0.05)
			_walls_root.add_child(knob)
		elif op.type == "rectangular_window":
			var glass := MeshInstance3D.new()
			var pm := QuadMesh.new()
			pm.size = Vector2(op.width * 0.92, 1.38)
			glass.mesh = pm
			var gm := _mat(Color(0.62, 0.78, 0.84, 0.32), 0.2, 0.1)
			gm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			gm.cull_mode = BaseMaterial3D.CULL_DISABLED
			glass.material_override = gm
			glass.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			glass.position = Vector3(c.x + n.x * wall.thickness * 0.03, 1.6, c.y + n.y * wall.thickness * 0.03)
			glass.rotation.y = atan2(n.x, n.y)  # QuadMesh 面朝 +Z
			_walls_root.add_child(glass)
			var fr := _box(Vector3(op.width * 0.96, 0.05, 0.07), "#3d2d22", Vector3(c.x, 1.6, c.y))  # 窗框：与玻璃不同平面
			fr.rotation.y = yaw
			_walls_root.add_child(fr)


# ───────────────────────── 家具 ─────────────────────────
## 贴墙件：把背面吸附到最近内墙面外加 EPS，并朝向房间内部。
func _wall_snap(p: Dictionary, depth: float) -> Dictionary:
	var th: float = design.walls[0].thickness / 2.0
	var gap: float = th + Geo.EPS.wall_art + depth / 2.0
	var x: float = p.x
	var z: float = p.z
	var dists := {"n": z, "s": design.d - z, "w": x, "e": design.w - x}
	var best := "n"
	for k in dists:
		if dists[k] < dists[best]: best = k
	match best:
		"n": return {"x": x, "z": gap, "yaw": 0.0, "y_off": 0.0}
		"s": return {"x": x, "z": design.d - gap, "yaw": 180.0, "y_off": 0.0}
		"w": return {"x": gap, "z": z, "yaw": 90.0, "y_off": 0.0}
	return {"x": design.w - gap, "z": z, "yaw": -90.0, "y_off": 0.0}


func _build_prop(p: Dictionary) -> Node3D:
	var kind := str(p.kind)
	var dm := Geo.prop_dims(p)
	var root := Node3D.new()
	root.name = str(p.id)
	var yaw: float = p.yaw
	var px: float = p.x
	var pz: float = p.z
	var col := Geo.prop_color(kind)
	var wallish := kind in ["painting", "chalkboard", "map_board", "wall_lantern", "speaking_tube", "wind_gauge", "pipe"]
	if wallish:
		var sn := _wall_snap(p, dm.d)
		px = sn.x
		pz = sn.z
		yaw = sn.yaw
	root.position = Vector3(px, 0, pz)
	root.rotation.y = deg_to_rad(yaw)
	var w: float = dm.w
	var d: float = dm.d
	var h: float = dm.h
	match kind:
		"bed":
			root.add_child(_box(Vector3(w, 0.28, d), "#4a3324", Vector3(0, 0.14, 0)))
			root.add_child(_box(Vector3(w * 0.94, 0.16, d * 0.94), "#cfc4ad", Vector3(0, 0.36, 0)))
			root.add_child(_box(Vector3(w * 0.8, 0.1, 0.32), "#efe6d6", Vector3(0, 0.49, -d * 0.36)))
			root.add_child(_box(Vector3(w, 0.9, 0.08), "#4a3324", Vector3(0, 0.45, -d / 2.0 + 0.04)))
		"table", "counter":
			root.add_child(_box(Vector3(w, 0.06, d), col, Vector3(0, h - 0.03, 0)))
			for sx in [-1, 1]:
				for sz in [-1, 1]:
					root.add_child(_box(Vector3(0.07, h - 0.06, 0.07), "#483222", Vector3(sx * (w / 2.0 - 0.07), (h - 0.06) / 2.0, sz * (d / 2.0 - 0.07))))
		"round_table":
			root.add_child(_cyl(w / 2.0, w / 2.0, 0.05, col, Vector3(0, h - 0.025, 0), 20))
			root.add_child(_cyl(0.05, 0.08, h - 0.05, "#483222", Vector3(0, (h - 0.05) / 2.0, 0), 10))
		"chair", "bench":
			root.add_child(_box(Vector3(w, 0.05, d), col, Vector3(0, 0.44, 0)))
			for sx in [-1, 1]:
				for sz in [-1, 1]:
					root.add_child(_box(Vector3(0.04, 0.42, 0.04), "#483222", Vector3(sx * (w / 2.0 - 0.05), 0.21, sz * (d / 2.0 - 0.05))))
			if kind == "chair":
				root.add_child(_box(Vector3(w, 0.46, 0.04), col, Vector3(0, 0.69, -d / 2.0 + 0.03)))
		"rug":
			# 地毯抬高 EPS.rug，且比地板略小：绝不与地板共面
			root.add_child(_box(Vector3(w, 0.01, d), "#6a4b3c", Vector3(0, Geo.EPS.rug + 0.005, 0), 0.95))
			root.add_child(_box(Vector3(w * 0.9, 0.01, d * 0.9), "#7d5a46", Vector3(0, Geo.EPS.rug + 0.014, 0), 0.95))
		"painting":
			root.add_child(_box(Vector3(w, h, 0.05), "#4a3527", Vector3(0, 1.75, 0)))
			root.add_child(_box(Vector3(w * 0.86, h * 0.8, 0.02), col, Vector3(0, 1.75, 0.02 + 0.005)))  # 画心前移，不与画框前面共面
		"chalkboard":
			root.add_child(_box(Vector3(w, h, 0.05), "#3d2d22", Vector3(0, 1.6, 0)))
			root.add_child(_box(Vector3(w * 0.94, h * 0.9, 0.02), "#2f4a42", Vector3(0, 1.6, 0.02 + 0.006)))
		"map_board":
			root.add_child(_box(Vector3(w, h, 0.05), "#3d2d22", Vector3(0, 1.5, 0)))
			root.add_child(_box(Vector3(w * 0.92, h * 0.88, 0.02), "#cdbb92", Vector3(0, 1.5, 0.02 + 0.006)))
		"wall_lantern", "pendant_lamp", "banker_lamp":
			var y := 1.9 if kind == "wall_lantern" else (2.85 if kind == "pendant_lamp" else 0.9)
			root.add_child(_box(Vector3(w * 0.6, h, d * 0.6), "#3d2d22", Vector3(0, y, 0)))
			var bulb := MeshInstance3D.new()
			var sm := SphereMesh.new()
			sm.radius = 0.1
			sm.height = 0.2
			bulb.mesh = sm
			bulb.material_override = _glow_mat("#ffd27a")
			bulb.position = Vector3(0, y - (0.0 if kind == "wall_lantern" else 0.18), 0.08 if kind == "wall_lantern" else 0.0)
			root.add_child(bulb)
			if kind == "pendant_lamp":
				root.add_child(_cyl(0.01, 0.01, 3.2 - 2.85, "#2a2420", Vector3(0, 3.05, 0), 5))
			var lt := OmniLight3D.new()
			lt.light_color = Color("#ffcf86")
			lt.omni_range = 7.0 if kind == "pendant_lamp" else 4.0
			lt.light_energy = 0.4
			lt.shadow_enabled = kind == "pendant_lamp"
			lt.position = bulb.position + Vector3(0, -0.15 if kind == "pendant_lamp" else 0.0, 0.2 if kind == "wall_lantern" else 0.0)
			root.add_child(lt)
			lamps.append(lt)
		"column", "pipe":
			var r: float = w / 2.0
			root.add_child(_cyl(r * 0.9, r, 3.2 if kind == "column" else 3.1, col if kind == "column" else "#b87333", Vector3(0, 1.6, 0), 16))
		"stair":
			for i in 5:
				root.add_child(_box(Vector3(w, 0.18, d - i * (d / 5.0)), col.darkened(0.1 * i), Vector3(0, 0.09 + i * 0.18, -(i * d / 10.0))))
		"evidence_marker":
			var mk := Node3D.new()
			mk.name = "Marker"
			var found_it: bool = found.has(str(p.get("eid", "")))
			var color := Color("#7fbf6a") if found_it else Color("#d9a13a")
			# 圆盘抬高 EPS.decal；光柱是独立的竖向几何，不贴任何已有表面
			var disc := _cyl(0.17, 0.17, 0.012, color, Vector3(0, Geo.EPS.decal + 0.006, 0), 20, _glow_mat(color))
			mk.add_child(disc)
			var beam := _cyl(0.02, 0.02, 0.5, color, Vector3(0, 0.3, 0), 6, _glow_mat(color))
			mk.add_child(beam)
			root.add_child(mk)
			evidence_nodes[str(p.get("eid", ""))] = root
		_:
			root.add_child(_box(Vector3(w, h, d), col, Vector3(0, h / 2.0 + (0.0 if dm.get("mounted", false) == false else 0.0), 0)))
			if kind in ["cabinet", "bookshelf", "shelf", "medicine_cabinet"]:
				# 柜面分格线：前移 EPS，不与柜体前面共面
				for i in 3:
					root.add_child(_box(Vector3(w * 0.96, 0.02, 0.01), "#2a1c12", Vector3(0, h * (0.25 + i * 0.25), d / 2.0 + Geo.EPS.prop * 0.5)))
	return root


# ───────────────────────── 点选证物 ─────────────────────────
## 射线与证物标记的最近距离判定（不依赖物理引擎）。
func pick_marker(origin: Vector3, direction: Vector3) -> String:
	var best := ""
	var best_t := INF
	for eid in evidence_nodes:
		var n: Node3D = evidence_nodes[eid]
		var c := to_global(n.position + Vector3(0, 0.3, 0)) if false else n.global_position + Vector3(0, 0.3, 0)
		var oc := c - origin
		var t := oc.dot(direction)
		if t < 0.0: continue
		var dist := (origin + direction * t).distance_to(c)
		if dist < 0.42 and t < best_t:
			best_t = t
			best = str(eid)
	return best
