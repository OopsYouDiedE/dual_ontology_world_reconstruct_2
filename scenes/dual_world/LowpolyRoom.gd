extends Node3D
## Lowpoly 房间适配器：把 room_art.zip 里的 Lowpoly 房间 tscn（RoomContainer3D）
## 挂进 DualWorldMain 的单房间 3D 视图，并与 RoomGeometry 的设计坐标系对齐。
##
## 坐标对齐：Lowpoly 房间以房间中心为原点（FloorZone polygon 居中），
## 而 RoomGeometry 设计以左上角 (0,0) 为原点、x 向右、z 向下。
## 本适配器把 Lowpoly 房间平移到设计坐标系，使两套坐标一致：
##   - 侦探走路网格、证物标记、人物站位全部使用设计坐标；
##   - Lowpoly 房间只负责视觉（墙/家具/门窗），其内部坐标经平移与设计坐标重合。
## 若 Lowpoly 房间缺失（zip 未解压 / 房间无对应 tscn），返回 false，调用方回退到程序化房间。

const RoomLibrary := preload("res://scenes/components/world/RoomLibrary.gd")

## Lowpoly 房间 id → dual_world 房间 id 的映射（zip 里的命名与数据层基本一致，
## 仅个别房间命名不同；缺失的房间回退到程序化生成）。
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
var _attached := false


## 尝试把 Lowpoly 房间挂到 parent 下。design 为 RoomGeometry 设计（提供 w/d）。
## 成功返回 true；失败返回 false（调用方应回退到 RoomMesh3D 程序化房间）。
func attach(parent: Node3D, rid: String, design: Dictionary) -> bool:
	room_id = rid
	detach()
	if not ID_MAP.has(rid):
		_floor_size = Vector2.ZERO
		return false
	var identity: String = str(ID_MAP[rid])
	if not RoomLibrary.available(identity):
		_floor_size = Vector2.ZERO
		return false
	var inst := RoomLibrary.instantiate(identity)
	if inst == null:
		_floor_size = Vector2.ZERO
		return false
	_root = inst
	_attached = true
	inst.set_meta("lowpoly_room", true)
	parent.add_child(inst)
	# 对齐：Lowpoly 房间中心在原点 → 平移到设计坐标系中心 (w/2, d/2)
	var w: float = float(design.get("w", 5.4))
	var d: float = float(design.get("d", 4.6))
	inst.position = Vector3(w * 0.5, 0.0, d * 0.5)
	# 尺寸：用 FloorZone polygon 估算 Lowpoly 房间实际尺寸（仅记录，不缩放——
	# Lowpoly 房间按真实米制建模，与设计尺寸接近；缩放会让家具变形）。
	_floor_size = _floor_size_of(inst)
	return true


func _floor_size_of(inst: Node3D) -> Vector2:
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
	# 兼容旧版 room_art.zip：部分 FloorZone 在 tscn 中只有导出字段，没有脚本，
	# 因而 polygon 读回 null。回退到可见网格的局部 AABB 尺寸。
	var bounds := AABB()
	var found := false
	for mesh: MeshInstance3D in inst.find_children("*", "MeshInstance3D", true, false):
		if mesh.mesh == null: continue
		var rel := inst.global_transform.affine_inverse() * mesh.global_transform
		var item := rel * mesh.get_aabb()
		if not found: bounds = item; found = true
		else: bounds = bounds.merge(item)
	return Vector2(bounds.size.x, bounds.size.z) if found else Vector2.ZERO

## Lowpoly 房间的出生点（设计坐标系）
func spawn_pos() -> Vector2:
	if _root == null:
		return Vector2.ZERO
	var sp := _root.get_node_or_null("SpawnPoint") as Marker3D
	if sp != null:
		var gp: Vector3 = sp.global_position
		return Vector2(gp.x, gp.z)
	return Vector2.ZERO


## 房间中心（设计坐标系）
func center() -> Vector3:
	if _root == null:
		return Vector3.ZERO
	return _root.global_position + Vector3(0, 1.0, 0)


## Lowpoly 房间的地板尺寸（设计坐标系下的实际米制）
func floor_size() -> Vector2:
	return _floor_size


func detach() -> void:
	if _root != null and is_instance_valid(_root):
		if _root.get_parent() != null:
			_root.get_parent().remove_child(_root)
		_root.queue_free()
	_root = null
	_attached = false
