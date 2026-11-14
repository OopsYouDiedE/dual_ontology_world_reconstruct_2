extends Node3D
## Lowpoly 房间适配器：把 room_art.zip 里的 Lowpoly 房间 tscn（RoomContainer3D）
## 挂进 DualWorldMain 的单房间 3D 视图，并与 RoomGeometry 的设计坐标系对齐。
##
## 坐标对齐：Lowpoly 房间网格在局部坐标系中 Z 轴跨度约为 [-D .. +0.28]（并非以原点为中心），
## 本适配器通过与 SceneTree 无关的局部矩阵遍历求得真实 AABB 中心，将其精确平移到设计中心
## (w/2, d/2)，并导出可行走地板矩形、家具碰撞矩形、床位中心与室内暖色顶灯。

const RoomLibrary := preload("res://scenes/components/world/RoomLibrary.gd")

const ID_MAP := {
	"R01": "R01", "R02": "R02", "R03": "R03", "R04": "R04",
	"R05": "R05", "R06": "R06", "R07": "R07", "R08": "R08",
	"R09": "R09", "R10": "R10", "R11": "R11", "R12": "R12",
	"R13": "R13", "R14": "R14", "R15": "R15", "R16": "R16",
	"A-P": "A-P", "B-P": "B-P", "C-P": "C-P", "D-P": "D-P",
	"clinic": "clinic", "T01": "lecture", "living_hall": "living_hall",
	"F03": "main_dining", "F04": "main1f_f04", "F05": "main1f_f05", "F06": "main1f_f06",
	"U01-granary": "mainb1_u01", "B1-hazard": "mainb1_service",
	"B2-control": "b2_control", "B2-valve": "b2_valve_gallery",
	"S-102": "S-102", "W-102": "W-102", "B-102": "B-102", "F-104": "F-104",
	"service_stair_M": "service_stair_M",
}

var room_id := ""
var _root: Node3D = null
var _floor_size := Vector2.ZERO
var _local_bounds := AABB()
var _target_center := Vector2.ZERO
var _obstacles: Array = []
var _bed_pos := Vector2.ZERO
var lamps: Array = []
var _attached := false


func attach(parent: Node3D, rid: String, design: Dictionary) -> bool:
	room_id = rid
	detach()
	if not ID_MAP.has(rid):
		return false
	var identity: String = str(ID_MAP[rid])
	if not RoomLibrary.available(identity):
		return false
	var inst := RoomLibrary.instantiate(identity)
	if inst == null:
		return false
	_root = inst
	_attached = true
	inst.set_meta("lowpoly_room", true)
	var mesh_items: Array = []
	_collect_meshes(inst, Transform3D.IDENTITY, "", mesh_items)
	var found := false
	var bounds := AABB()
	for it in mesh_items:
		var ab: AABB = it.aabb
		if not found:
			bounds = ab
			found = true
		else:
			bounds = bounds.merge(ab)
	_local_bounds = bounds if found else AABB(Vector3(-2.5, 0.0, -2.5), Vector3(5.0, 3.0, 5.0))
	_floor_size = _floor_size_of(inst, _local_bounds)
	var w: float = float(design.get("w", 5.4))
	var d: float = float(design.get("d", 4.6))
	var span_w := maxf(w, _floor_size.x)
	var span_d := maxf(d, _floor_size.y)
	_target_center = Vector2(span_w * 0.5, span_d * 0.5)
	var bc := _local_bounds.get_center()
	inst.position = Vector3(_target_center.x - bc.x, 0.0, _target_center.y - bc.z)
	_extract_features(mesh_items, inst.position)
	_spawn_indoor_lamps(inst, bc)
	parent.add_child(inst)
	return true


func _collect_meshes(node: Node, acc_xf: Transform3D, tag_chain: String, out: Array) -> void:
	var xf := acc_xf
	if node is Node3D and node != _root:
		xf = acc_xf * (node as Node3D).transform
	var nm := tag_chain + "/" + node.name.to_lower()
	if node is MeshInstance3D:
		var mi := node as MeshInstance3D
		if mi.mesh != null and mi.visible:
			out.append({"aabb": xf * mi.get_aabb(), "path": nm})
	for ch in node.get_children():
		_collect_meshes(ch, xf, nm, out)


func _floor_size_of(inst: Node3D, fallback_bounds: AABB) -> Vector2:
	var fz := inst.get_node_or_null("FloorZone")
	if fz != null:
		var value: Variant = fz.get("polygon")
		if value is PackedVector2Array and value.size() >= 4:
			var poly: PackedVector2Array = value
			var minx := INF
			var maxx := -INF
			var miny := INF
			var maxy := -INF
			for p in poly:
				minx = minf(minx, p.x)
				maxx = maxf(maxx, p.x)
				miny = minf(miny, p.y)
				maxy = maxf(maxy, p.y)
			return Vector2(maxx - minx, maxy - miny)
	var sx := maxf(2.0, fallback_bounds.size.x - 0.56)
	var sz := maxf(2.0, fallback_bounds.size.z - 0.56)
	return Vector2(sx, sz)


func _extract_features(mesh_items: Array, offset: Vector3) -> void:
	_obstacles.clear()
	_bed_pos = Vector2.ZERO
	var bed_bounds := AABB()
	var has_bed := false
	var wr := walk_rect()
	for it in mesh_items:
		var ab: AABB = it.aabb
		var path: String = it.path
		if "bed" in path:
			if not has_bed:
				bed_bounds = ab
				has_bed = true
			else:
				bed_bounds = bed_bounds.merge(ab)
		# 过滤地板、天花板、外墙与高处灯饰，只保留落地的室内家具碰撞盒
		if "floor" in path or "wall" in path or "ceil" in path or "roof" in path or "rug" in path or "carpet" in path or "mat" in path:
			continue
		if ab.position.y > 0.95 or ab.end.y < 0.28 or ab.size.y > 2.85:
			continue
		if ab.size.x > _floor_size.x * 0.82 or ab.size.z > _floor_size.y * 0.82:
			continue
		if ab.size.x < 0.18 or ab.size.z < 0.18:
			continue
		var rx := ab.position.x + offset.x
		var rz := ab.position.z + offset.z
		var rect := Rect2(rx, rz, ab.size.x, ab.size.z).intersection(wr)
		if rect.size.x > 0.15 and rect.size.y > 0.15:
			_obstacles.append(rect)
	if has_bed:
		var bc := bed_bounds.get_center() + offset
		_bed_pos = Vector2(bc.x, bc.z)


func _spawn_indoor_lamps(inst: Node3D, local_center: Vector3) -> void:
	lamps.clear()
	var lamp_y := clampf(_local_bounds.end.y - 0.55, 2.35, 3.35)
	var cols := 2 if _floor_size.x >= 9.0 else 1
	var rows := 2 if _floor_size.y >= 9.0 else 1
	var span_x := maxf(2.0, _floor_size.x * 0.52)
	var span_z := maxf(2.0, _floor_size.y * 0.52)
	var radius := maxf(9.0, maxf(_floor_size.x, _floor_size.y) * 0.95)
	for ix in cols:
		for iz in rows:
			var tx := 0.0 if cols == 1 else lerpf(-span_x * 0.5, span_x * 0.5, float(ix) / float(cols - 1))
			var tz := 0.0 if rows == 1 else lerpf(-span_z * 0.5, span_z * 0.5, float(iz) / float(rows - 1))
			var light := OmniLight3D.new()
			light.name = "IndoorLamp_%d_%d" % [ix, iz]
			light.position = Vector3(local_center.x + tx, lamp_y, local_center.z + tz)
			light.light_color = Color("#ffdfb2")
			light.light_energy = 1.15
			light.omni_range = radius
			light.omni_attenuation = 1.1
			light.shadow_enabled = false
			inst.add_child(light)
			lamps.append(light)


## Lowpoly 房间的室内可行走矩形（设计坐标系）
func walk_rect(margin := 0.42) -> Rect2:
	var iw := maxf(1.2, _floor_size.x - margin * 2.0)
	var id_ := maxf(1.2, _floor_size.y - margin * 2.0)
	return Rect2(_target_center.x - iw * 0.5, _target_center.y - id_ * 0.5, iw, id_)


func obstacle_rects() -> Array:
	return _obstacles


func bed_spot() -> Vector2:
	return _bed_pos


## Lowpoly 房间的出生点（设计坐标系）
func spawn_pos() -> Vector2:
	if _root == null:
		return Vector2.ZERO
	var sp := _root.get_node_or_null("SpawnPoint") as Marker3D
	if sp != null:
		var p := _root.position + sp.position
		return Vector2(p.x, p.z)
	return Vector2.ZERO


## 房间中心（设计坐标系，与 SceneTree 挂载状态无关）
func center() -> Vector3:
	if _root == null:
		return Vector3.ZERO
	return Vector3(_target_center.x, 1.0, _target_center.y)


## Lowpoly 房间的地板尺寸（实际米制）
func floor_size() -> Vector2:
	return _floor_size


func detach() -> void:
	lamps.clear()
	_obstacles.clear()
	_bed_pos = Vector2.ZERO
	_floor_size = Vector2.ZERO
	if _root != null and is_instance_valid(_root):
		if _root.get_parent() != null:
			_root.get_parent().remove_child(_root)
		_root.queue_free()
	_root = null
	_attached = false
