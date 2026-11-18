extends RefCounted
## Plan-view footprints for the web furniture presets.
## Local convention (same as the 3D builders): origin at the piece centre, +Z is the front, -Z the back.
## Wall mounted pieces have their origin on the wall face and extend towards +Z.
## Everything is derived from the same parameters the 3D builder reads, so 2D and 3D always agree.
const FLOOR = "floor"
const WALL = "wall"
const TOP = "top"
const CEILING = "ceiling"
const FLAT = "flat"

const SIZES = {
	"table":["table_w","table_d",1.8,0.95,FLOOR,0.7],
	"round_table":["table_r","table_r",0.6,0.6,FLOOR,0.5],
	"chair":["seat_w","seat_d",0.48,0.5,FLOOR,0.0],
	"bench":["bench_len","bench_w",1.6,0.5,FLOOR,0.5],
	"bookshelf":["shelf_w","",1.5,0.42,FLOOR,0.7],
	"reception_desk":["desk_w","",2.4,0.93,FLOOR,0.8],
	"wash_table":["wash_w","",1.1,0.6,FLOOR,0.6],
	"bed":["bed_w","bed_l",1.8,2.1,FLOOR,0.6],
	"nightstand":["stand_w","",0.5,0.46,FLOOR,0.3],
	"sofa":["sofa_w","sofa_d",2.0,0.9,FLOOR,0.8],
	"cabinet":["cab_w","",1.2,0.62,FLOOR,0.7],
	"pedestal":["width","width",0.52,0.52,FLOOR,0.4],
	"chest":["chest_w","chest_d",0.95,0.55,FLOOR,0.5],
	"screen":["screen_w","",1.8,0.3,FLOOR,0.2],
	"lectern":["","",0.8,0.55,FLOOR,0.6],
	"planter":["plant_w","plant_w",0.65,0.65,FLOOR,0.3],
	"upright_piano":["piano_w","",1.7,0.7,FLOOR,0.8],
	"easel":["","",0.7,0.6,FLOOR,0.5],
	"crates":["","",0.8,0.8,FLOOR,0.3],
	"rug":["rug_w","rug_d",2.6,1.8,FLAT,0.0],
	"painting":["frame_w","",1.35,0.06,WALL,0.0],
	"chalkboard":["board_w","",3.3,0.15,WALL,0.0],
	"wall_lantern":["","",0.14,0.3,WALL,0.0],
	"banker_lamp":["","",0.26,0.2,TOP,0.0],
	"pendant_lamp":["","",0.5,0.5,CEILING,0.0],
}
## Parameter that holds the mounting height (absolute Y) of a piece, if any.
const MOUNT_FIELD = {"painting":"mount_y","wall_lantern":"lamp_height","banker_lamp":"mount_y"}
## Pieces that should be pushed against a wall when dropped near one.
const AGAINST_WALL = ["bookshelf","cabinet","bed","reception_desk","wash_table","sofa","chest","nightstand","upright_piano","screen","bench","lectern"]

static func info(item: Dictionary) -> Dictionary:
	var kind = str(item.get("kind",""))
	var params = item.get("params",{})
	if not SIZES.has(kind): return {"w":0.8,"d":0.8,"mount":FLOOR,"clear":0.3,"kind":kind}
	var spec = SIZES[kind]
	var w = float(params.get(spec[0],spec[2])) if spec[0]!="" else spec[2]
	var d = float(params.get(spec[1],spec[3])) if spec[1]!="" else spec[3]
	if kind=="round_table": w *= 2.0; d *= 2.0
	if kind=="pedestal": d = w
	if kind=="painting": d = 0.06
	return {"w":w,"d":d,"mount":spec[4],"clear":spec[5],"kind":kind}

## Rectangle of the piece in its own (x,z) plane.
static func local_rect(item: Dictionary) -> Rect2:
	var f = info(item)
	if f.mount==WALL: return Rect2(Vector2(-f.w*0.5,0.0),Vector2(f.w,f.d))
	return Rect2(Vector2(-f.w*0.5,-f.d*0.5),Vector2(f.w,f.d))

static func to_world(item: Dictionary, local: Vector2) -> Vector2:
	var a = deg_to_rad(float(item.get("yaw",0)))
	return Vector2(float(item.x)+local.x*cos(a)+local.y*sin(a),float(item.z)-local.x*sin(a)+local.y*cos(a))

static func to_local(item: Dictionary, world: Vector2) -> Vector2:
	var a = deg_to_rad(float(item.get("yaw",0)))
	var dx = world.x-float(item.x)
	var dz = world.y-float(item.z)
	return Vector2(dx*cos(a)-dz*sin(a),dx*sin(a)+dz*cos(a))

static func corners(item: Dictionary, grow := 0.0, extra_front := 0.0) -> PackedVector2Array:
	var r = local_rect(item).grow(grow)
	r.size.y += extra_front
	var result = PackedVector2Array()
	for p in [r.position,Vector2(r.end.x,r.position.y),r.end,Vector2(r.position.x,r.end.y)]: result.append(to_world(item,p))
	return result

static func contains(item: Dictionary, world: Vector2, margin := 0.0) -> bool:
	return local_rect(item).grow(margin).has_point(to_local(item,world))

## Floor pieces take up room; hanging, tabletop, ceiling and rug pieces do not.
static func blocks(item: Dictionary) -> bool:
	return info(item).mount==FLOOR

static func overlaps(a: Dictionary, b: Dictionary, grow := 0.0) -> bool:
	if not blocks(a) or not blocks(b): return false
	var ca = corners(a,grow)
	var cb = corners(b,grow)
	for p in ca:
		if p.x<-1e9: return false
	return not Geometry2D.intersect_polygons(ca,cb).is_empty() and Geometry2D.intersect_polygons(ca,cb).any(func(poly): return absf(polygon_area(poly))>0.002)

static func polygon_area(poly: PackedVector2Array) -> float:
	var area = 0.0
	for i in range(poly.size()): area += poly[i].cross(poly[(i+1)%poly.size()])
	return area*0.5

## Yaw (degrees) that makes the piece face along `direction` (plan vector pointing into the room).
static func yaw_facing(direction: Vector2) -> float:
	return rad_to_deg(atan2(direction.x,direction.y))

## Place a piece so its back touches a wall face. `normal` points from the wall into the room.
static func against_wall(item: Dictionary, wall_point: Vector2, normal: Vector2, wall_half: float) -> void:
	var f = info(item)
	item.yaw = snappedf(yaw_facing(normal),0.01)
	var reach = wall_half+0.05+(0.0 if f.mount==WALL else f.d*0.5)
	var at = wall_point+normal*reach
	item.x = snappedf(at.x,0.01)
	item.z = snappedf(at.y,0.01)
