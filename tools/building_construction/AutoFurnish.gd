extends RefCounted
## Rule based furnishing of a derived room. Pieces are placed against the room's wall faces, kept inside the
## floor polygon, out of doorways and clear of each other. Pure data in / data out: returns prop dictionaries.
const Footprint = preload("BuildingConstruction/Props/PropFootprint.gd")
const Geo = preload("BuildingConstruction/Shared/ArchitectGeometry.gd")

const TEMPLATES = {
	"bedroom":{"label":"卧室","items":[
		{"kind":"bed","slot":"wall_long","params":{}},
		{"kind":"nightstand","slot":"beside_first","side":-1,"params":{}},
		{"kind":"nightstand","slot":"beside_first","side":1,"params":{}},
		{"kind":"cabinet","slot":"wall","params":{}},
		{"kind":"table","slot":"wall","params":{"table_w":1.4,"table_d":0.7}},
		{"kind":"chair","slot":"before_prev","params":{}},
		{"kind":"rug","slot":"center","params":{"rug_w":2.2,"rug_d":1.6}},
		{"kind":"painting","slot":"hang","params":{"mount_y":1.65}},
		{"kind":"wall_lantern","slot":"hang","params":{"lamp_height":2.3}},
	]},
	"study":{"label":"书房","items":[
		{"kind":"table","slot":"wall_long","params":{}},
		{"kind":"chair","slot":"before_prev","params":{}},
		{"kind":"banker_lamp","slot":"on_prev2","params":{}},
		{"kind":"bookshelf","slot":"wall","params":{}},
		{"kind":"bookshelf","slot":"wall","params":{}},
		{"kind":"chest","slot":"wall","params":{}},
		{"kind":"rug","slot":"center","params":{"rug_w":2.4,"rug_d":1.7}},
		{"kind":"painting","slot":"hang","params":{"mount_y":1.65}},
		{"kind":"wall_lantern","slot":"hang","params":{"lamp_height":2.3}},
	]},
	"living":{"label":"起居室","items":[
		{"kind":"sofa","slot":"wall_long","params":{}},
		{"kind":"round_table","slot":"before_prev","params":{"table_r":0.45,"table_h":0.45}},
		{"kind":"bench","slot":"wall","params":{}},
		{"kind":"cabinet","slot":"wall","params":{}},
		{"kind":"planter","slot":"corner","params":{}},
		{"kind":"rug","slot":"center","params":{"rug_w":2.6,"rug_d":1.8}},
		{"kind":"painting","slot":"hang","params":{"mount_y":1.65}},
		{"kind":"wall_lantern","slot":"hang","params":{"lamp_height":2.3}},
	]},
	"dining":{"label":"餐厅","items":[
		{"kind":"table","slot":"center","params":{"table_w":2.2,"table_d":1.0}},
		{"kind":"chair","slot":"around_prev","side":0,"params":{}},
		{"kind":"chair","slot":"around_prev","side":1,"params":{}},
		{"kind":"chair","slot":"around_prev","side":2,"params":{}},
		{"kind":"chair","slot":"around_prev","side":3,"params":{}},
		{"kind":"cabinet","slot":"wall","params":{}},
		{"kind":"planter","slot":"corner","params":{}},
		{"kind":"pendant_lamp","slot":"ceiling_center","params":{}},
		{"kind":"wall_lantern","slot":"hang","params":{"lamp_height":2.3}},
	]},
	"storage":{"label":"储藏室","items":[
		{"kind":"bookshelf","slot":"wall_long","params":{}},
		{"kind":"bookshelf","slot":"wall","params":{}},
		{"kind":"chest","slot":"wall","params":{}},
		{"kind":"crates","slot":"corner","params":{"crate_tier":3}},
		{"kind":"crates","slot":"corner","params":{"crate_tier":2}},
		{"kind":"wall_lantern","slot":"hang","params":{"lamp_height":2.3}},
	]},
}

static func template_names() -> Dictionary:
	var result = {}
	for key in TEMPLATES: result[key] = TEMPLATES[key].label
	return result

## One wall edge of the room floor: a→b along the wall, `normal` points into the room.
static func edges_of(polygon: Array) -> Array:
	var ring = []
	for p in polygon: ring.append(Vector2(p[0],p[1]))
	var area = 0.0
	for i in range(ring.size()): area += ring[i].cross(ring[(i+1)%ring.size()])
	var result = []
	for i in range(ring.size()):
		var a = ring[i]
		var b = ring[(i+1)%ring.size()]
		var along = (b-a)
		if along.length()<0.3: continue
		along = along.normalized()
		var normal = Vector2(-along.y,along.x) if area>0 else Vector2(along.y,-along.x)
		result.append({"a":a,"b":b,"along":along,"normal":normal,"length":a.distance_to(b)})
	result.sort_custom(func(x,y): return x.length>y.length)
	return result

## Points of every door-like opening on the walls of this layer, with the clearance rectangle they need.
static func door_zones(walls: Array, elevation: float) -> Array:
	var zones = []
	for wall in walls:
		for op in wall.get("openings",[]):
			if not str(op.type).contains("door") and op.type!="portal_arch": continue
			if op.segment<0 or op.segment>=wall.points.size()-1: continue
			var a = wall.points[op.segment]
			var b = wall.points[op.segment+1]
			if abs(a[1]-elevation)>0.3: continue
			var pa = Vector2(a[0],a[2])
			var pb = Vector2(b[0],b[2])
			var along = (pb-pa).normalized()
			var c = pa+along*op.center
			var normal = Vector2(-along.y,along.x)
			var reach = float(wall.thickness)*0.5+0.9
			var w = float(op.width)*0.5+0.15
			var rect = PackedVector2Array([c-along*w-normal*reach,c+along*w-normal*reach,c+along*w+normal*reach,c-along*w+normal*reach])
			zones.append(rect)
	return zones

static func fits(item: Dictionary, room: Array, others: Array, doors: Array, margin := 0.04) -> bool:
	var ring = PackedVector2Array()
	for p in room: ring.append(Vector2(p[0],p[1]))
	var body = Footprint.corners(item,margin)
	for p in body:
		if not Geometry2D.is_point_in_polygon(p,ring): return false
	# Keep edges inside too (concave rooms).
	for i in range(body.size()):
		var mid = (body[i]+body[(i+1)%body.size()])*0.5
		if not Geometry2D.is_point_in_polygon(mid,ring): return false
	if Footprint.blocks(item):
		var clearance = PackedVector2Array(Footprint.corners(item,0.0,float(Footprint.info(item).clear)*0.6))
		for zone in doors:
			if not Geometry2D.intersect_polygons(clearance,zone).is_empty(): return false
		for other in others:
			if Footprint.overlaps(item,other,0.04): return false
	return true

static func _make(spec: Dictionary, y: float, serial: int) -> Dictionary:
	var kind = spec.kind
	var item = {"id":"auto_%s_%d_%d"%[kind,Time.get_ticks_usec(),serial],"name":kind,"kind":kind,"x":0.0,"y":y,"z":0.0,"yaw":0.0,"params":spec.params.duplicate(true)}
	return item

const WALL_OFFSETS = [0.5,0.25,0.75,0.15,0.85,0.35,0.65]

static func _place_on_wall(item: Dictionary, edge: Dictionary, polygon: Array, placed: Array, doors: Array) -> bool:
	var f = Footprint.info(item)
	for t in WALL_OFFSETS:
		var along_pos = clampf(t*edge.length,f.w*0.5+0.1,edge.length-f.w*0.5-0.1)
		Footprint.against_wall(item,edge.a+edge.along*along_pos,edge.normal,0.0)
		if fits(item,polygon,placed,doors): return true
	return false

## Furnish one derived room (`room` = a layer roomFaces entry). `layer_y` is the floor elevation;
## `walls` supply the ceiling height and doors; `existing` are props already in the scene (kept clear).
static func furnish(template_id: String, room: Dictionary, layer_y: float, walls: Array, existing: Array, presets: Dictionary) -> Array:
	if not TEMPLATES.has(template_id): return []
	var polygon: Array = room.polygon
	var edges = edges_of(polygon)
	if edges.is_empty(): return []
	var doors = door_zones(walls,layer_y)
	var ceiling = layer_y+3.6
	for wall in walls:
		if abs(float(wall.get("baseY",0))-layer_y)<0.3: ceiling = layer_y+float(wall.height)
	var placed = existing.duplicate()
	var added = []
	var centroid = Vector2(room.centroid[0],room.centroid[1])
	var anchor = {}
	var first_anchor = {}
	var serial = 0
	var hung = 0
	for spec in TEMPLATES[template_id].items:
		serial += 1
		var item = _make(spec,layer_y,serial)
		for field in presets.get(item.kind,{"fields":[]}).fields:
			if not item.params.has(field.id): item.params[field.id] = field.val
		var f = Footprint.info(item)
		var ok = false
		var primary = true
		match str(spec.slot):
			"wall","wall_long":
				for ei in range(edges.size()):
					if edges[ei].length<f.w+0.3: continue
					if _place_on_wall(item,edges[ei],polygon,placed,doors): ok = true; break
					if spec.slot=="wall_long" and ei>=1: break
			"corner":
				for edge in edges:
					for end in [0,1]:
						var corner = edge.a if end==0 else edge.b
						var inward = edge.along*(1.0 if end==0 else -1.0)
						var at = corner+inward*(f.w*0.5+0.08)+edge.normal*(f.d*0.5+0.08)
						item.x = snappedf(at.x,0.01); item.z = snappedf(at.y,0.01)
						item.yaw = snappedf(Footprint.yaw_facing(edge.normal),0.01)
						if fits(item,polygon,placed,doors): ok = true; break
					if ok: break
			"center","ceiling_center":
				for offset in [Vector2.ZERO,Vector2(0.4,0),Vector2(-0.4,0),Vector2(0,0.4),Vector2(0,-0.4)]:
					item.x = snappedf(centroid.x+offset.x,0.01); item.z = snappedf(centroid.y+offset.y,0.01)
					item.yaw = snappedf(Footprint.yaw_facing(edges[0].normal),0.01)
					if str(spec.slot)=="ceiling_center":
						ok = Geometry2D.is_point_in_polygon(Vector2(item.x,item.z),Geo.points2(polygon))
					else: ok = fits(item,polygon,placed,doors)
					if ok: break
				if str(spec.slot)=="ceiling_center": item.y = snappedf(ceiling-float(item.params.get("drop_length",1.1))-0.03,0.01)
			"before_prev":
				primary = false
				if not anchor.is_empty():
					var forward = Vector2(sin(deg_to_rad(anchor.yaw)),cos(deg_to_rad(anchor.yaw)))
					var reach = Footprint.info(anchor).d*0.5+f.d*0.5+(0.12 if item.kind=="chair" else 0.55)
					item.x = snappedf(anchor.x+forward.x*reach,0.01); item.z = snappedf(anchor.z+forward.y*reach,0.01)
					item.yaw = snappedf(anchor.yaw+(180.0 if item.kind=="chair" else 0.0),0.01)
					ok = fits(item,polygon,placed,doors)
			"beside_first":
				primary = false
				if not first_anchor.is_empty():
					var base = first_anchor
					var bf = Footprint.info(base)
					var rot = deg_to_rad(base.yaw)
					var right = Vector2(cos(rot),-sin(rot))
					var back = Vector2(-sin(rot),-cos(rot))*(bf.d*0.5-f.d*0.5)
					var at = Vector2(base.x,base.z)+right*(bf.w*0.5+f.w*0.5+0.1)*float(spec.get("side",1))+back
					item.x = snappedf(at.x,0.01); item.z = snappedf(at.y,0.01)
					item.yaw = base.yaw
					ok = fits(item,polygon,placed,doors)
			"around_prev":
				primary = false
				if not anchor.is_empty():
					var side = int(spec.get("side",0))%4
					var tf = Footprint.info(anchor)
					var rot = deg_to_rad(anchor.yaw)
					var local = [Vector2(0,tf.d*0.5+0.34),Vector2(0,-tf.d*0.5-0.34),Vector2(tf.w*0.5+0.34,0),Vector2(-tf.w*0.5-0.34,0)][side]
					var at = Vector2(anchor.x,anchor.z)+Vector2(local.x*cos(rot)+local.y*sin(rot),-local.x*sin(rot)+local.y*cos(rot))
					item.x = snappedf(at.x,0.01); item.z = snappedf(at.y,0.01)
					item.yaw = snappedf(anchor.yaw+[180.0,0.0,-90.0,90.0][side],0.01)
					ok = fits(item,polygon,placed,doors)
			"on_prev2":
				primary = false
				if not anchor.is_empty():
					item.x = anchor.x; item.z = anchor.z
					item.y = snappedf(float(anchor.y)+0.76,0.01)
					ok = true
			"hang":
				primary = false
				var edge = edges[0] if item.kind=="painting" else edges[min(edges.size()-1,hung%edges.size())]
				hung += 1
				for t in [0.5,0.25,0.75,0.12,0.88]:
					var along_pos = edge.length*t
					if along_pos<f.w*0.5+0.1 or along_pos>edge.length-f.w*0.5-0.1: continue
					Footprint.against_wall(item,edge.a+edge.along*along_pos,edge.normal,0.0)
					item.y = snappedf(layer_y+float(item.params.get(Footprint.MOUNT_FIELD.get(item.kind,"mount_y"),1.65)),0.01)
					var blocked = false
					for zone in doors:
						if Geometry2D.is_point_in_polygon(Vector2(item.x,item.z),zone): blocked = true
					if not blocked: ok = true; break
		if not ok: continue
		var field_name = Footprint.MOUNT_FIELD.get(item.kind,"")
		if field_name!="" and item.kind!="banker_lamp": item.params[field_name] = item.y
		elif item.kind=="banker_lamp": item.params["mount_y"] = item.y
		added.append(item)
		placed.append(item)
		if primary and Footprint.blocks(item):
			anchor = item
			if first_anchor.is_empty(): first_anchor = item
	return added
