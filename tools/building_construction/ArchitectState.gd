extends RefCounted
## Original serializeSceneState schema and wall editing transitions.
const Geo = preload("BuildingConstruction/Shared/ArchitectGeometry.gd")
const Topology = preload("RoomTopology.gd")
var data = {"activeLayerId":null,"layers":[],"walls":[],"stairs":[],"railings":[],"props":[]}
var selected: Dictionary = {}
var history: Array[String] = []
var history_index = -1
var grid_snap = 0.2

func uid(prefix: String) -> String: return prefix+"_"+str(Time.get_ticks_usec())+"_"+str(randi()%10000)
func snap(value: float) -> float:
	return Geo.js_round((Geo.js_round(value/grid_snap)*grid_snap if grid_snap>0 else value)*100)/100
func layer() -> Dictionary:
	for item in data.layers:
		if item.id == data.activeLayerId: return item
	return data.layers[0] if not data.layers.is_empty() else {}
func new_layer() -> void:
	var y = data.layers.size()*3.6
	var item = {"id":uid("fl"),"name":"标高 %.1fm" % y,"y":y,"style":"octagonal_tile","polygons":[]}
	data.layers.append(item)
	data.activeLayerId = item.id
func remember() -> void:
	sync_rooms()
	var text = JSON.stringify(data)
	if history_index>=0 and history[history_index]==text: return
	history.resize(history_index+1)
	history.append(text)
	if history.size()>40: history.pop_front()
	history_index = history.size()-1
func restore(text: String) -> bool:
	var parsed = preload("ArchitectYaml.gd").new().parse(text)
	if not parsed is Dictionary: return false
	for key in ["layers","walls","stairs","railings","props"]:
		if not parsed.get(key,[]) is Array: return false
		parsed[key] = parsed.get(key,[])
	for wall in parsed.walls:
		if not wall is Dictionary or not wall.get("points") is Array or wall.points.size()<2: return false
		for pt in wall.points:
			if not pt is Array or pt.size()!=3: return false
		for key in ["height","thickness"]:
			if not (wall.get(key) is float or wall.get(key) is int): return false
		wall["openings"] = wall.get("openings",[])
	data = {"activeLayerId":parsed.get("activeLayerId"),"layers":parsed.layers,"walls":parsed.walls,"stairs":parsed.stairs,"railings":parsed.railings,"props":parsed.props}
	if not data.get("activeLayerId") and not data.layers.is_empty(): data.activeLayerId = data.layers[0].id
	selected = {}
	sync_rooms()
	return true

func sync_rooms() -> void:
	for item in data.layers:
		var faces = Topology.rooms(data.walls,item.y)
		if not faces.is_empty():
			item.roomFaces = faces
			item.polygons = []
			for face in faces: item.polygons.append(face.polygon)
		elif item.has("roomFaces"):
			item.polygons = []
			item.roomFaces = []
		item.erase("manualPolygons")
	if selected.get("kind","") in ["floorNode","floorPoly"]:
		if selected.layerIndex>=data.layers.size() or selected.polyIndex>=data.layers[selected.layerIndex].polygons.size(): selected = {}
		elif selected.kind=="floorNode" and selected.ptIndex>=data.layers[selected.layerIndex].polygons[selected.polyIndex].size(): selected = {}

func move_junction(origin: Array, destination: Array) -> void:
	apply_junction_moves([{"from":origin,"to":destination}])

func apply_junction_moves(moves: Array) -> void:
	# Read all original segments before applying any move, so a translated node
	# cannot accidentally match a second node's former position.
	for wall in data.walls:
		var original = wall.points.duplicate(true)
		var points = []
		var remap = []
		for i in range(original.size()-1):
			var a = original[i]
			var b = original[i+1]
			var cuts = [{"t":0.0,"p":a}]
			for move in moves:
				var p = move["from"]
				if abs(a[1]-p[1])>0.001 or abs(b[1]-p[1])>0.001: continue
				var hit = project(Vector2(p[0],p[2]),Vector2(a[0],a[2]),Vector2(b[0],b[2]))
				if hit.dist<0.001 and hit.t>0.001 and hit.t<0.999:
					cuts.append({"t":hit.t,"p":p})
			cuts.sort_custom(func(x,y): return x.t<y.t)
			var offsets = []
			for cut in cuts:
				var mapped = cut.p
				for move in moves:
					if Vector3(cut.p[0],cut.p[1],cut.p[2]).distance_to(Vector3(move["from"][0],move["from"][1],move["from"][2]))<0.001:
						mapped = move.to; break
				offsets.append({"index":points.size(),"distance":cut.t*Vector2(b[0]-a[0],b[2]-a[2]).length()})
				points.append(mapped.duplicate())
			remap.append(offsets)
		var last = original[-1]
		for move in moves:
			if Vector3(last[0],last[1],last[2]).distance_to(Vector3(move["from"][0],move["from"][1],move["from"][2]))<0.001:
				last = move.to; break
		points.append(last.duplicate())
		wall.points = points
		for opening in wall.openings:
			if opening.segment<0 or opening.segment>=remap.size(): continue
			var offsets = remap[opening.segment]
			var chosen = offsets[0]
			for offset in offsets:
				if opening.center>=offset.distance: chosen = offset
			opening.segment = chosen.index
			opening.center -= chosen.distance

func move_room_node(layer_index: int, poly_index: int, node_index: int, x: float, z: float) -> void:
	var item = data.layers[layer_index]
	if not item.has("roomFaces"):
		item.polygons[poly_index][node_index] = [x,z]
		return
	var p = item.roomFaces[poly_index].nodes[node_index]
	move_junction([p[0],item.y,p[1]],[x,item.y,z])

func translate_room(layer_index: int, poly_index: int, snapshot: Dictionary, dx: float, dz: float) -> void:
	var item = snapshot.layers[layer_index]
	if not item.has("roomFaces"):
		var poly = data.layers[layer_index].polygons[poly_index]
		for i in range(poly.size()):
			var p = item.polygons[poly_index][i]
			poly[i] = [Geo.js_round((p[0]+dx)*100)/100,Geo.js_round((p[1]+dz)*100)/100]
		return
	data.walls = snapshot.walls.duplicate(true)
	var moves = []
	for p in item.roomFaces[poly_index].nodes:
		moves.append({"from":[p[0],item.y,p[1]],"to":[Geo.js_round((p[0]+dx)*100)/100,item.y,Geo.js_round((p[1]+dz)*100)/100]})
	apply_junction_moves(moves)

func translate_wall(index: int, snapshot: Dictionary, dx: float, dz: float) -> void:
	data.walls = snapshot.walls.duplicate(true)
	var wall = data.walls[index]
	var count = wall.points.size()-(1 if wall.closed else 0)
	var origins = wall.points.duplicate(true)
	var moves = []
	for i in range(count):
		var p = origins[i]
		moves.append({"from":p,"to":[Geo.js_round((p[0]+dx)*100)/100,p[1],Geo.js_round((p[2]+dz)*100)/100]})
	apply_junction_moves(moves)
func undo(delta: int) -> bool:
	var index = history_index+delta
	if index<0 or index>=history.size(): return false
	history_index = index
	return restore(history[index])

func project(point: Vector2, a: Vector2, b: Vector2) -> Dictionary:
	var delta = b-a
	var length = delta.length()
	var t = clampf((point-a).dot(delta)/delta.length_squared(),0,1) if length>0 else 0.0
	var p = a+delta*t
	return {"point":p,"t":t,"len":length,"dist":point.distance_to(p)}
func nearest_wall(point: Vector2, max_distance := 0.8) -> Dictionary:
	var best = {}
	for wi in range(data.walls.size()):
		var wall = data.walls[wi]
		for si in range(wall.points.size()-1):
			var a = wall.points[si]
			var b = wall.points[si+1]
			var hit = project(point,Vector2(a[0],a[2]),Vector2(b[0],b[2]))
			if hit.dist<=max_distance and (best.is_empty() or hit.dist<best.dist):
				best = hit
				best.wallIndex = wi
				best.segIndex = si
				best.centerDist = snap(hit.t*hit.len)
	return best

func add_opening(point: Vector2, params: Dictionary) -> bool:
	var hit = nearest_wall(point,0.9)
	if hit.is_empty(): return false
	var opening = params.duplicate(true)
	opening.id = uid("op")
	opening.segment = hit.segIndex
	opening.center = max(opening.width*0.5+0.1,min(hit.len-opening.width*0.5-0.1,hit.centerDist))
	opening.center = Geo.js_round(opening.center*100)/100
	data.walls[hit.wallIndex].openings.append(opening)
	selected = {"kind":"opening","wallIndex":hit.wallIndex,"opIndex":data.walls[hit.wallIndex].openings.size()-1}
	remember()
	return true

func auto_walls(params: Dictionary) -> bool:
	var active = layer()
	if active.is_empty() or active.polygons.is_empty(): return false
	if params.height<0.5 or params.height>10 or params.thickness<0.05 or params.thickness>1: return false
	if active.has("roomFaces"):
		var updated = false
		for wall in data.walls:
			if wall.get("generatedLayerId")==active.id:
				wall.merge(params,true)
				updated = true
		if updated: remember()
		return updated
	var generated = []
	for polygon in active.polygons:
		var floor_poly = polygon.duplicate(true)
		if floor_poly.size()>3 and Vector2(floor_poly[0][0],floor_poly[0][1]).distance_to(Vector2(floor_poly[-1][0],floor_poly[-1][1]))<0.001: floor_poly.pop_back()
		if floor_poly.size()<3 or abs(Geo.area(floor_poly))<0.01: continue
		# Centerline sits half a wall thickness outside the floor boundary.
		var ring = Geo.offset(floor_poly,params.thickness*0.5)
		if ring.size()<3: return false
		var points = []
		for pt in ring:
			if not is_finite(pt[0]) or not is_finite(pt[1]): return false
			points.append([pt[0],active.y,pt[1]])
		points.append(points[0].duplicate())
		var wall = params.duplicate(true)
		wall.merge({"id":uid("wall"),"name":"自动外墙 · "+active.name+" · "+str(generated.size()+1),"generatedLayerId":active.id,"points":points,"closed":true,"baseY":active.y,"openings":[]},true)
		generated.append(wall)
	if generated.is_empty(): return false
	data.walls = data.walls.filter(func(w): return w.get("generatedLayerId")!=active.id)
	data.walls.append_array(generated)
	selected = {}
	remember()
	return true

func add_floor(poly: Array) -> void:
	var active = layer()
	var new_poly = Geo.ccw(poly)
	for item in data.layers:
		if abs(item.y-active.y)>0.3: continue
		var clipped = []
		for existing in item.polygons:
			for ring in Geometry2D.clip_polygons(Geo.points2(existing),Geo.points2(new_poly)):
				# Martinez original retains outer rings only.
				if Geometry2D.is_polygon_clockwise(ring): continue
				var values = []
				for p in ring: values.append([p.x,p.y])
				if values.size()>=3: clipped.append(Geo.ccw(values))
		item.polygons = clipped
	active.polygons.append(new_poly)

func insert_wall_node(point: Vector2, tolerance: float) -> bool:
	for wi in range(data.walls.size()):
		var wall = data.walls[wi]
		for si in range(wall.points.size()-1):
			var a = wall.points[si]
			var b = wall.points[si+1]
			var hit = project(point,Vector2(a[0],a[2]),Vector2(b[0],b[2]))
			if hit.dist<=max(wall.thickness*0.6,tolerance):
				var y = Geo.js_round((a[1]*(1-hit.t)+b[1]*hit.t)*100)/100
				wall.points.insert(si+1,[snap(hit.point.x),y,snap(hit.point.y)])
				for op in wall.openings:
					if op.segment>si: op.segment += 1
				selected = {"kind":"wallNode","wallIndex":wi,"ptIndex":si+1}
				remember()
				return true
	return false

func set_wall_y(wall: Dictionary, value: float) -> void:
	wall.baseY = value
	var moves = []
	for pt in wall.points: moves.append({"from":pt.duplicate(),"to":[pt[0],value,pt[2]]})
	apply_junction_moves(moves)
func set_node(wall: Dictionary, index: int, axis: int, value: float) -> void:
	var origin = wall.points[index].duplicate()
	var destination = origin.duplicate()
	destination[axis] = value
	move_junction(origin,destination)

func delete_selected() -> void:
	if selected.is_empty(): return
	var s = selected
	match s.kind:
		"wall": data.walls.remove_at(s.wallIndex)
		"wallNode":
			var wall = data.walls[s.wallIndex]
			var count = wall.points.size()-(1 if wall.closed else 0)
			if count<=2: data.walls.remove_at(s.wallIndex)
			else:
				wall.points.remove_at(s.ptIndex)
				if wall.closed and s.ptIndex==0: wall.points[-1] = wall.points[0].duplicate()
				wall.openings = wall.openings.filter(func(op): return op.segment<wall.points.size()-1)
		"opening": data.walls[s.wallIndex].openings.remove_at(s.opIndex)
		"floorPoly": data.layers[s.layerIndex].polygons.remove_at(s.polyIndex)
		"floorNode":
			if data.layers[s.layerIndex].has("roomFaces"):
				selected = {}
				return
			var poly = data.layers[s.layerIndex].polygons[s.polyIndex]
			if poly.size()>3: poly.remove_at(s.ptIndex)
			else: data.layers[s.layerIndex].polygons.remove_at(s.polyIndex)
		"railing": data.railings.remove_at(s.railIndex)
		"railingNode":
			var rail = data.railings[s.railIndex]
			if rail.points.size()<=2: data.railings.remove_at(s.railIndex)
			else: rail.points.remove_at(s.ptIndex)
		"stair": data.stairs.remove_at(s.index)
		"prop": data.props.remove_at(s.index)
	selected = {}
	remember()
