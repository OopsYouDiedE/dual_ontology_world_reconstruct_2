extends SceneTree
## Structural checks: topology, mitred walls, opening bookkeeping, footprints, auto furnish.
## Run: godot --headless --path <project> --script res://tools/building_construction/tests/check_structure.gd
const State = preload("res://tools/building_construction/ArchitectState.gd")
const Topology = preload("res://tools/building_construction/RoomTopology.gd")
const Wall = preload("res://tools/building_construction/BuildingConstruction/Walls/WallPathGeometry.gd")
const Props = preload("res://tools/building_construction/BuildingConstruction/Props/ArchitectProps.gd")
const Footprint = preload("res://tools/building_construction/BuildingConstruction/Props/PropFootprint.gd")
const Furnish = preload("res://tools/building_construction/AutoFurnish.gd")
var failures = 0

func check(name: String, ok: bool, detail := "") -> void:
	print(("PASS " if ok else "FAIL ")+name+("" if ok else "  "+detail))
	if not ok: failures += 1

func wall(id: String, pts: Array, closed := false, thickness := 0.3, pillars := false) -> Dictionary:
	var points = []
	for p in pts: points.append([p[0],0.0,p[1]])
	if closed: points.append(points[0].duplicate())
	return {"id":id,"name":id,"closed":closed,"height":3.0,"thickness":thickness,"baseY":0.0,"style":"plain","hasPillars":pillars,"points":points,"openings":[]}

func scene(walls: Array) -> Dictionary:
	return {"activeLayerId":"L","layers":[{"id":"L","name":"L","y":0.0,"style":"plain_grout","polygons":[]}],"walls":walls,"stairs":[],"railings":[],"props":[]}

func load_state(data: Dictionary):
	var state = State.new()
	check("restore "+str(data.walls.size())+" walls",state.restore(JSON.stringify(data)))
	return state

func world_vertices(node: Node3D) -> Array:
	var result = []
	for seg in node.get_children():
		if not seg is Node3D or not str(seg.name).begins_with("Segment_"): continue
		for mi in seg.find_children("*","MeshInstance3D",true,false):
			if mi.mesh==null: continue
			for si in range(mi.mesh.get_surface_count()):
				for v in mi.mesh.surface_get_arrays(si)[Mesh.ARRAY_VERTEX]: result.append(seg.transform*mi.transform*v)
	return result

func _init() -> void:
	# 1. Hexagon: sloped corners must close (no vertex gaps) and the room must be found.
	var hex = []
	for i in range(6): hex.append([cos(i*PI/3)*4.0,sin(i*PI/3)*4.0])
	var state = load_state(scene([wall("hex",hex,true)]))
	check("hexagon room derived",state.data.layers[0].roomFaces.size()==1)
	var face = state.data.layers[0].roomFaces[0]
	check("hexagon area ~ inset",face.area>35.0 and face.area<42.0,str(face.area))
	check("room has centroid/perimeter",face.centroid.size()==2 and face.perimeter>20.0)
	var built = Wall.build(state.data.walls[0])
	var verts = world_vertices(built)
	# every outer-face top corner of the hexagon should coincide with the mitre point of its neighbour
	var tops = {}
	for v in verts:
		if absf(v.y-3.0)<0.001:
			var key = "%.2f,%.2f"%[v.x,v.z]
			tops[key] = tops.get(key,0)+1
	var shared = 0
	for key in tops: if tops[key]>=2: shared += 1
	check("hexagon mitres share top vertices",shared>=12,"shared="+str(shared))
	built.free()

	# 2. Rooms: shared wall splits a box into two rooms; exterior/neighbour data.
	var box = wall("box",[[-4,-3],[4,-3],[4,3],[-4,3]],true)
	var split = wall("split",[[0,-3],[0,3]])
	state = load_state(scene([box,split]))
	var rooms = state.data.layers[0].roomFaces
	check("split box = 2 rooms",rooms.size()==2)
	if rooms.size()==2:
		check("rooms are neighbours",rooms[0].neighbors.has(1) and rooms[1].neighbors.has(0))
		check("rooms have exterior edges",rooms[0].exteriorEdges>=3)
	# float noise: a crossing wall slightly off the node must still make one clean graph
	var noisy = wall("noisy",[[0.0000001,-3.0000002],[0.0000002,3.0000001]])
	state = load_state(scene([wall("box2",[[-4,-3],[4,-3],[4,3],[-4,3]],true),noisy]))
	check("noisy T junction = 2 rooms",state.data.layers[0].roomFaces.size()==2)
	# sharp wedge must still yield a room (miter limit + fallback)
	state = load_state(scene([wall("wedge",[[0,0],[10,0.8],[10,-0.8]],true,0.3)]))
	check("sharp wedge keeps a room",state.data.layers[0].roomFaces.size()==1)

	# 3. Openings follow node edits.
	var strip = wall("strip",[[0,0],[10,0]])
	strip.openings = [{"id":"o1","segment":0,"center":7.0,"width":1.0,"height":2.0,"bottom":0.0,"type":"closed_door"}]
	state = load_state(scene([strip]))
	state.selected = {}
	check("insert node",state.insert_wall_node(Vector2(4,0),0.2))
	var w = state.data.walls[0]
	check("opening moved to 2nd segment",w.openings[0].segment==1 and absf(w.openings[0].center-3.0)<0.02,str(w.openings[0]))
	state.selected = {"kind":"wallNode","wallIndex":0,"ptIndex":1}
	state.delete_selected()
	w = state.data.walls[0]
	check("delete node keeps opening at 7m",w.openings[0].segment==0 and absf(w.openings[0].center-7.0)<0.02,str(w.openings[0]))
	check("overlapping opening is shifted",state.add_opening(Vector2(7.2,0.0),{"type":"closed_door","width":1.0,"height":2.0,"bottom":0.0,"rise":0.4}))
	w = state.data.walls[0]
	check("shifted clear of the first",absf(w.openings[1].center-w.openings[0].center)>=1.04,str(w.openings))
	check("oversize opening rejected",not state.add_opening(Vector2(5,0),{"type":"portal_arch","width":12.0,"height":2.0,"bottom":0.0,"rise":0.4}) and state.message!="")

	# 4. Sanitising of incomplete data.
	state = State.new()
	check("restore tolerates sparse data",state.restore(JSON.stringify({"layers":[{"y":0}],"walls":[{"points":[[0,0,0],[3,0,0]],"height":3,"thickness":0.2,"openings":[{"type":"bogus","segment":9}]}],"props":[{"x":1,"z":2,"kind":"table"}]})))
	check("sparse prop has params",state.data.props[0].params is Dictionary and state.data.props[0].has("id"))
	check("bad opening repaired",state.data.walls[0].openings[0].segment==0 and state.data.walls[0].openings[0].width>0)

	# 5. Footprint maths and wall snapping.
	var table = {"kind":"table","x":2.0,"z":1.0,"yaw":90.0,"params":{}}
	var c = Footprint.corners(table)
	check("rotated footprint corners",c.size()==4 and absf(c[0].distance_to(c[1])-1.8)<0.01 or absf(c[0].distance_to(c[1])-0.95)<0.01)
	check("contains centre",Footprint.contains(table,Vector2(2,1)) and not Footprint.contains(table,Vector2(5,5)))
	var shelf = {"kind":"bookshelf","x":0,"z":0,"yaw":0,"params":{}}
	Footprint.against_wall(shelf,Vector2(0,-3),Vector2(0,1),0.0)
	check("against wall: back to wall, facing +z",absf(shelf.yaw)<0.01 and absf(shelf.z-(-3.0+0.05+0.21))<0.01,str(shelf))
	check("overlap detection",Footprint.overlaps({"kind":"chair","x":0,"z":0,"yaw":0,"params":{}},{"kind":"table","x":0.2,"z":0,"yaw":0,"params":{}}) and not Footprint.overlaps({"kind":"chair","x":0,"z":0,"yaw":0,"params":{}},{"kind":"table","x":4,"z":0,"yaw":0,"params":{}}))

	# 6. Auto furnish inside a 6x5 room with a door.
	var presets = JSON.parse_string(FileAccess.get_file_as_string("res://tools/building_construction/architect_prop_presets.json"))
	var room_wall = wall("room",[[-3,-2.5],[3,-2.5],[3,2.5],[-3,2.5]],true,0.3,false)
	room_wall.openings = [{"id":"d","segment":2,"center":3.0,"width":1.1,"height":2.2,"bottom":0.0,"type":"closed_door"}]
	state = load_state(scene([room_wall]))
	var room = state.data.layers[0].roomFaces[0]
	for template in Furnish.TEMPLATES:
		var added = Furnish.furnish(template,room,0.0,state.data.walls,[],presets)
		var inside = true
		var ring = PackedVector2Array()
		for p in room.polygon: ring.append(Vector2(p[0],p[1]))
		var collide = false
		for i in range(added.size()):
			if Footprint.blocks(added[i]):
				for p in Footprint.corners(added[i]): if not Geometry2D.is_point_in_polygon(p,ring): inside = false
			for j in range(i+1,added.size()): if Footprint.overlaps(added[i],added[j]): collide = true
		check("furnish %s places %d pieces inside, no overlap"%[template,added.size()],added.size()>=4 and inside and not collide)
		for item in added:
			var node = Props.build(item)
			if node==null or node.get_child_count()==0 and not Props.RECIPE_KINDS.has(item.kind): check("builds "+item.kind,false)
			node.free()
	# 7. Baking keeps geometry and lights.
	var table_node = Props.build({"kind":"table","x":0,"y":0,"z":0,"yaw":0,"params":{}})
	var baked = table_node.get_node_or_null("Baked")
	check("table baked into one mesh",baked!=null and table_node.find_children("*","MeshInstance3D",true,false).size()==1)
	if baked!=null:
		var bounds = baked.mesh.get_aabb()
		check("baked table keeps its size",absf(bounds.size.x-1.8)<0.05 and absf(bounds.size.y-0.75)<0.05 and absf(bounds.size.z-0.95)<0.05,str(bounds.size))
		check("baked table has 2+ material surfaces",baked.mesh.get_surface_count()>=2)
	table_node.free()
	var lamp = Props.build({"kind":"banker_lamp","x":0,"y":0,"z":0,"yaw":0,"params":{"lamp_energy":16}})
	var lights = lamp.find_children("*","OmniLight3D",true,false)
	check("lamp keeps its light, energy follows lamp_energy",lights.size()==1 and absf(lights[0].light_energy-2.0)<0.01,str(lights.size()))
	lamp.free()
	var crates = Props.build({"kind":"crates","x":0,"y":0,"z":0,"yaw":0,"params":{"crate_tier":4}})
	check("crate_tier raises the stack",crates.get_node("Baked").mesh.get_aabb().size.y>1.6)
	crates.free()
	var lectern = Props.build({"kind":"lectern","x":0,"y":0,"z":0,"yaw":0,"params":{"lec_h":1.3}})
	check("lectern uses the native recipe, not a placeholder cube",lectern.get("recipe_function")=="lectern" and absf(lectern.get("height")-1.3)<0.001)
	lectern.free()
	print("FAILURES ",failures)
	quit(1 if failures>0 else 0)
