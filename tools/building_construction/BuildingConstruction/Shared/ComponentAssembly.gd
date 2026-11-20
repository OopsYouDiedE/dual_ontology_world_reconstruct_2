extends RefCounted
## All contact math is in the host frame; render/physics nodes stay inside their
## original component. Only the catalog root is parented to the supporting root.
const Wall = preload("../Walls/SmartWall3D.gd")
const Palette = preload("RecipeGeometry.gd")
const GRID := 0.25
const JOIN_RADIUS := 0.68
const MATERIALS := {"wall_material":"stone", "skirting_material":"wood_dark", "cutaway_cap_material":"stone_dark", "floor_material":"stone_dark", "ceiling_material":"cream", "railing_material":"wood", "stair_material":"stone", "frame_material":"wood_dark", "door_material":"wood", "glass_material":"glass"}
static var palette: Dictionary = {}

static func tag(part: Node3D, entry: Dictionary) -> void:
	part.set_meta(&"assembly_id", entry.id)
	part.set_meta(&"assembly_mount", entry.mount)
	part.set_meta(&"assembly_category", entry.category)
	if palette.is_empty(): palette = Palette.gen_palette()
	for prop in MATERIALS:
		if prop in part and part.get(prop) == null: part.set(prop, palette[MATERIALS[prop]])

static func id(part: Node) -> String:
	return str(part.get_meta(&"assembly_id", "")) if part else ""

static func members(root: Node) -> Array[Node3D]:
	var result: Array[Node3D] = []
	for child in root.get_children():
		if child is Node3D and not id(child).is_empty():
			result.append(child)
			result.append_array(members(child))
	return result

static func component(node: Node, root: Node) -> Node3D:
	while node and node != root:
		if not id(node).is_empty(): return node as Node3D
		node = node.get_parent()
	return null

static func _bounds(node: Node, t: Transform3D, boxes: Array[AABB]) -> void:
	if node is MeshInstance3D and node.mesh and node.is_visible_in_tree():
		var box: AABB = t * node.get_aabb()
		boxes.append(box)
	for child in node.get_children():
		if child is Node3D and not child.is_queued_for_deletion() and id(child).is_empty():
			_bounds(child, t * child.transform, boxes)

static func bounds(part: Node3D) -> AABB:
	var boxes: Array[AABB] = []
	_bounds(part, Transform3D.IDENTITY, boxes)
	if boxes.is_empty(): return AABB()
	var box := boxes[0]
	for i in range(1, boxes.size()): box = box.merge(boxes[i])
	return box

static func _recipe_point(v: Array) -> Vector3:
	return Vector3(v[0], v[2], -v[1])

static func ends(part: Node3D) -> PackedVector3Array:
	var p := PackedVector3Array()
	if "start_point" in part and "end_point" in part: p.append_array([part.start_point, part.end_point])
	elif part is Path3D and part.curve and part.curve.point_count >= 2:
		p.append_array([part.curve.get_point_position(0), part.curve.get_point_position(part.curve.point_count-1)])
	elif "points" in part and part.points is Array and part.points.size() >= 2:
		p.append_array([_recipe_point(part.points.front()), _recipe_point(part.points.back())])
	elif id(part) == "RecipeStraightFlight": p.append_array([_recipe_point(part.start), _recipe_point(part.end)])
	elif id(part) == "RecipeRampModule": p.append_array([Vector3.ZERO, Vector3(0,part.rise,-part.length)])
	elif id(part) == "HallStairs": p.append_array([Vector3.ZERO, Vector3(0, part.RISE, -part.RUN-part.LANDING)])
	elif part.get_meta(&"assembly_mount", "") == "run":
		var box := bounds(part)
		var mid := box.get_center()
		var width := float(part.length) if "length" in part else box.size.x
		p.append_array([Vector3(mid.x-width/2,box.position.y,mid.z),Vector3(mid.x+width/2,box.position.y,mid.z)])
	return p

static func rim(part: Node3D) -> PackedVector3Array:
	var p := PackedVector3Array()
	if "polygon" in part:
		for v: Vector2 in part.polygon: p.append(Vector3(v.x,0,v.y))
	else:
		var b := bounds(part)
		# Posts and coping project beyond the walking surface of a dock/platform.
		if id(part) == "RecipeDock": b = AABB(Vector3(-part.width/2,0,-part.length/2), Vector3(part.width,0,part.length))
		elif id(part) == "RecipeOathPlatform": b = AABB(Vector3(-part.width/2,part.height,-part.depth/2), Vector3(part.width,0,part.depth))
		for v in [Vector2(b.position.x,b.position.z),Vector2(b.end.x,b.position.z),Vector2(b.end.x,b.end.z),Vector2(b.position.x,b.end.z)]:
			p.append(Vector3(v.x,b.end.y,v.y))
	return p

static func _run_join(part: Node3D, root: Node3D, at: Vector3, reverse: bool) -> Node3D:
	var pegs := ends(part)
	var best := JOIN_RADIUS
	var anchor := Vector3.ZERO
	var heading := Vector3.ZERO
	var joint: Node3D
	if pegs.size()<2: return null
	var peg := pegs[-1] if reverse else pegs[0]
	var to_far := part.global_basis*((pegs[0] if reverse else pegs[-1])-peg)
	to_far.y=0
	for other in members(root):
		if other == part: continue
		var deck: bool = other.get_meta(&"assembly_mount", "") == "deck"
		if not deck and other.get_meta(&"assembly_mount", "") != "run": continue
		var points := rim(other) if deck else ends(other)
		for i in points.size():
			var socket := other.to_global(points[i]); var face := Vector3.ZERO
			if deck:
				var next := other.to_global(points[(i+1)%points.size()]); var tangent := socket.direction_to(next)
				if tangent.is_zero_approx(): continue
				var side := Vector3.UP.cross(tangent).normalized()
				var sample := other.to_local((socket+next)/2+side*.001)
				var outline := PackedVector2Array()
				for p in points: outline.append(Vector2(p.x,p.z))
				if Geometry2D.is_point_in_polygon(Vector2(sample.x,sample.z),outline): side=-side
				var edge_start := socket
				socket = Geometry3D.get_closest_point_to_segment(at, socket, next)
				if socket.distance_to(at)>=best: continue
				if absf(pegs[-1].y-pegs[0].y)>.035:
					face=side # Both a rising and a descending flight leave the landing.
				elif to_far.normalized().dot(side)>-.5:
					face=tangent if to_far.dot(tangent)>=0 else -tangent
					var distance_along := (socket-edge_start).dot(tangent)
					var length := edge_start.distance_to(next)
					if length>=to_far.length():
						distance_along = minf(distance_along,length-to_far.length()) if face.dot(tangent)>0 else maxf(distance_along,to_far.length())
						socket=edge_start+tangent*distance_along
				best = at.distance_to(Geometry3D.get_closest_point_to_segment(at,edge_start,next))
			else:
				var distance := socket.distance_to(at)
				if distance>=best: continue
				best=distance
			anchor=socket; heading=face; joint=other
	if joint:
		if not heading.is_zero_approx() and not to_far.is_zero_approx(): part.global_rotate(Vector3.UP,to_far.signed_angle_to(heading,Vector3.UP))
		part.global_position += anchor-part.to_global(peg)
	return joint

static func _deck_join(part: Node3D, host: Node3D, at: Vector3) -> bool:
	var a := rim(part)
	var b := rim(host)
	if a.size() < 3 or b.size() < 3: return false
	var ca := Vector3.ZERO
	var cb := Vector3.ZERO
	for v in a: ca += part.to_global(v) / a.size()
	for v in b: cb += host.to_global(v) / b.size()
	var best := JOIN_RADIUS
	var delta := Vector3.ZERO
	for i in b.size():
		var b0 := host.to_global(b[i]); var b1 := host.to_global(b[(i+1)%b.size()])
		if b0.is_equal_approx(b1): continue
		var distance := at.distance_to(Geometry3D.get_closest_point_to_segment(at,b0,b1))
		if distance >= best: continue
		for j in a.size():
			var a0 := part.to_global(a[j]); var a1 := part.to_global(a[(j+1)%a.size()])
			if absf((a1-a0).normalized().dot((b1-b0).normalized())) < 0.999: continue
			var ma := (a0+a1)/2; var mb := (b0+b1)/2
			var normal := (b1-b0).cross(Vector3.UP).normalized()
			if (ca-ma).dot(normal)*(cb-mb).dot(normal) >= 0: continue
			best = distance; delta = mb-ma; break
	if best >= JOIN_RADIUS: return false
	part.global_position += delta
	return true

# Pairs are the local mating face center and its outward normal. A collar
# exposes its opposite face so a pipe can continue through the fitting.
static func pipe_ports(p: Node3D) -> Array[Vector3]:
	match id(p):
		"RecipePipeRun":
			if p.nodes.size()<2: return []
			var first := _recipe_point(p.nodes[0]); var last := _recipe_point(p.nodes[-1])
			var a := first.direction_to(_recipe_point(p.nodes[1]))*-1
			var b := last.direction_to(_recipe_point(p.nodes[-2]))*-1
			var lip: float = p.radius*.26 if p.collars else 0.
			if a.is_zero_approx() or b.is_zero_approx(): return []
			return [first+a*lip,a,last+b*lip,b]
		"RecipeValveStation":
			var y: float = p.height*.6/1.35
			return [Vector3(-p.width*.44,y,0),Vector3.LEFT,Vector3(p.width*.44,y,0),Vector3.RIGHT]
		"RecipeFlange": return [Vector3.DOWN*p.radius*.26,Vector3.DOWN,Vector3.UP*p.radius*.26,Vector3.UP]
	return []

static func _pipe_join(part: Node3D, host: Node3D, at: Vector3, yaw: float, reverse: bool) -> String:
	var src := pipe_ports(part); var dst := pipe_ports(host)
	var i := 2 if reverse else 0
	var j := 0 if at.distance_squared_to(host.to_global(dst[0])) <= at.distance_squared_to(host.to_global(dst[2])) else 2
	if at.distance_to(host.to_global(dst[j])) > JOIN_RADIUS: return "Choose a pipe end or a valve outlet."
	if int(host.get_meta(&"assembly_inlet",-1))==j: return "This pipe end is already connected."
	for child in host.get_children():
		if int(child.get_meta(&"assembly_outlet",-1)) == j: return "This pipe end is already connected."
	var axis := -(host.global_basis*dst[j+1]).normalized()
	part.global_basis = Basis(axis,deg_to_rad(yaw))*Basis(Quaternion(src[i+1],axis))
	part.global_position = host.to_global(dst[j])-part.global_basis*src[i]
	part.set_meta(&"assembly_inlet",i); part.set_meta(&"assembly_outlet",j)
	return ""

static func _wall_mount(part: Node3D, host: Node3D, at: Vector3, normal: Vector3, opening: bool) -> String:
	if not host or host.get_meta(&"assembly_category", "") != "Walls" or absf(normal.y) > 0.1:
		return "Click a vertical wall face."
	if opening and not host is Wall: return "A working opening needs a Smart Wall."
	var z := Vector3(normal.x,0,normal.z).normalized()
	part.global_basis = Basis(Vector3.UP.cross(z), Vector3.UP, z)
	var box := bounds(part)
	if opening:
		var axis: Vector3 = (host.end_point-host.start_point).normalized()
		if absf(axis.y) > 0.001 or absf(z.dot(host.global_basis * axis)) > 0.01: return "Click the long side of a level wall."
		if id(part) in ["RecipeReferenceSpokeWindow","RecipeReferenceLeadedBay"]:
			var outline := PackedVector2Array()
			var center := Vector2(box.get_center().x,box.get_center().y)
			var radius := Vector2(box.size.x,box.size.y)*0.49
			if id(part) == "RecipeReferenceSpokeWindow":
				for i in 32: outline.append(center+Vector2.from_angle(TAU*i/32)*radius)
			else:
				for corner in [Vector2(-1,-1),Vector2(1,-1),Vector2(1,1),Vector2(-1,1)]: outline.append(center+corner*radius)
			part.set_meta(&"assembly_outline",outline)
		var rect := Wall.aperture(part)
		if not rect.has_area(): return "This insert has no opening profile."
		var along := snappedf((host.to_local(at)-host.start_point).dot(axis),GRID)
		var y := 0.0
		if id(part).contains("Window") or id(part) == "RecipeReferenceLeadedBay": y = snappedf(host.to_local(at).y-host.start_point.y-rect.size.y/2, GRID)
		if rect.size.y > host.wall_height or rect.size.x + 0.08 > host.end_point.distance_to(host.start_point): return "The opening is larger than this wall."
		y = clampf(y,0,host.wall_height-rect.size.y)
		along = clampf(along, rect.size.x/2+0.04, host.end_point.distance_to(host.start_point)-rect.size.x/2-0.04)
		part.global_position = host.to_global(host.start_point+axis*along+Vector3.UP*(y-rect.position.y)) - part.global_basis.x * rect.get_center().x
		var inserted := Rect2(along-rect.size.x/2,y,rect.size.x,rect.size.y).grow(0.035)
		var others: Array = host.openings.duplicate()
		others.append_array(host.detect_child_openings())
		for o in others:
			if inserted.intersects(Rect2(o.from,o.bottom,o.to-o.from,o.top-o.bottom)): return "This opening would cut an existing frame."
	else:
		var setback := float(part.wall_setback) if id(part) == "HallBanner" else -box.position.z
		part.global_position = at + z * setback - Vector3.UP * box.get_center().y - part.global_basis.x * box.get_center().x
		if host is Wall:
			var axis: Vector3 = (host.end_point - host.start_point).normalized()
			var local_at: Vector3 = host.to_local(at) - host.start_point
			var face := Rect2(local_at.dot(axis)-box.size.x/2,local_at.y-box.size.y/2,box.size.x,box.size.y)
			var wall_face := Rect2(0,0,host.start_point.distance_to(host.end_point),host.wall_height)
			if not wall_face.encloses(face): return "The mounting footprint extends beyond the wall."
			var openings: Array = host.openings.duplicate(); openings.append_array(host.detect_child_openings())
			for o in openings:
				if face.intersects(Rect2(o.from,o.bottom,o.to-o.from,o.top-o.bottom)): return "This face crosses an opening."
	return ""

## A reserved box is local to the CLOSED moving assembly, not to its mesh
## in the current pose. This keeps furnished layouts usable after a save/reopen.
static func _sweep(p: Node3D) -> AABB:
	match id(p):
		"HingedDoor3D", "HingedWindow3D":
			var door := id(p) == "HingedDoor3D"
			var w: float = p.leaf_width if door else p.sash_width
			var h: float = p.leaf_height if door else p.sash_height
			var a: float = p.minimum_angle if door else p.min_angle
			var b: float = p.maximum_angle if door else p.max_angle
			var sweep := AABB(Vector3.ZERO,Vector3(0,h,0))
			for degrees in [a, b, 0., -90., 90., -180., 180.]:
				if degrees >= a and degrees <= b:
					sweep = sweep.expand(Basis(Vector3.UP,deg_to_rad(degrees))*Vector3.RIGHT*w)
			return sweep.grow(.025)
		"HallDoor": return AABB(Vector3(-.735,.015,-.045),Vector3(1.48,2.57,1.52))
		"HallCabinet": return AABB(Vector3(-.52,.05,.20),Vector3(1.04,1.05,.53))
	return AABB()

static func _clearance(part: Node3D, host: Node3D, root: Node3D, box: AABB) -> String:
	var swing := _sweep(part)
	for other in members(root):
		if other == part or other == host or (host and other.is_ancestor_of(host)): continue
		var volume := _sweep(other)
		var other_mount := str(other.get_meta(&"assembly_mount", ""))
		var fitting: bool = host != null and other.get_parent() == host and other_mount not in ["deck","run"]
		if not fitting and not swing.has_volume() and not volume.has_volume(): continue
		var to_local := part.global_transform.affine_inverse() * other.global_transform
		if volume.has_volume() and not (part.get_meta(&"assembly_mount", "") == "deck" and box.end.y <= (to_local*volume).position.y+.03) and box.intersects(to_local * volume): return "Keep the moving space of %s clear." % other.name
		if other_mount == "deck": continue
		var solid := to_local * bounds(other)
		if swing.has_volume() and (swing.intersects(solid) or (volume.has_volume() and swing.intersects(to_local*volume))): return "The moving part would hit %s." % other.name
		if fitting and box.grow(-.002).intersects(solid): return "This mounting position is occupied by %s." % other.name
	return ""

static func _on_decks(part:Node3D, root:Node3D, box:AABB) -> bool:
	# Sample the meshes that actually touch the floor: feet, not tabletops or foliage.
	var pieces: Array[AABB] = []
	_bounds(part,Transform3D.IDENTITY,pieces)
	var decks: Array[Node3D] = []
	for peer in members(root):
		if peer.get_meta(&"assembly_mount", "") == "deck": decks.append(peer)
	for piece in pieces:
		if piece.position.y>box.position.y+.015: continue
		for x in [piece.position.x,piece.end.x]:
			for z in [piece.position.z,piece.end.z]:
				var foot := part.to_global(Vector3(x,box.position.y,z)); var supported := false
				for deck in decks:
					var v:=deck.to_local(foot);var poly:=PackedVector2Array();var edge:=rim(deck)
					if edge.is_empty() or absf(v.y-edge[0].y)>.07: continue
					for vertex in edge: poly.append(Vector2(vertex.x,vertex.z))
					if Geometry2D.is_point_in_polygon(Vector2(v.x,v.z),poly): supported=true;break
				if not supported: return false
	return true

static func _pick_shape(part:Node3D, root:Node3D, box:AABB) -> void:
	if not box.has_volume() or not part.find_children("*","CollisionShape3D",true,false).is_empty(): return
	var body:=StaticBody3D.new(); body.name="AssemblyPick"; body.collision_layer=1<<29;body.collision_mask=0
	part.add_child(body);body.owner=root
	var shape:=CollisionShape3D.new();var solid:=BoxShape3D.new();solid.size=box.size
	shape.shape=solid;shape.position=box.get_center();body.add_child(shape);shape.owner=root

static func _rids(node: Node, result: Array[RID]) -> void:
	if node is CollisionObject3D: result.append(node.get_rid())
	for child in node.get_children(): _rids(child,result)

## Returns a placement diagnostic (empty on success). The caller discards an
## unsuccessful preview. `hit` contains the real picked surface, not its AABB top.
static func place(part: Node3D, root: Node3D, host: Node3D, at: Vector3, normal: Vector3, yaw: float, reverse := false) -> String:
	var mount := str(part.get_meta(&"assembly_mount"))
	var host_mount := str(host.get_meta(&"assembly_mount", "")) if host else ""
	var group := str(host.get_meta(&"assembly_category", "")) if host else ""
	part.global_basis = Basis(Vector3.UP, deg_to_rad(yaw))
	part.global_position = Vector3(snappedf(at.x,GRID),at.y,snappedf(at.z,GRID))
	var box := bounds(part)
	var attached := false
	var joint: Node3D
	if id(part)=="SmartRailing3D" and id(host)=="SmartStair3D":
		var start: Vector3 = host.start_point; var finish: Vector3 = host.end_point
		var side := Vector3.UP.cross(finish-start).normalized()
		if side.is_zero_approx(): return "Choose a flight with a horizontal run."
		var flank := signf((host.to_local(at)-start).dot(side))
		if is_zero_approx(flank): flank=1.
		if reverse: flank = -flank
		var inset: Vector3 = side*flank*(host.stair_width*.5-part.post_radius)
		for rail in host.get_children():
			if rail.get_meta(&"assembly_flank",0.)==flank: return "This flight edge already has a handrail."
		part.global_transform = host.global_transform
		part.set_points(PackedVector3Array([start+inset,finish+inset]))
		part.set_meta(&"assembly_flank",flank)
		joint = host
	elif mount == "run": joint = _run_join(part,root,at,reverse)
	if host and not pipe_ports(host).is_empty() and not pipe_ports(part).is_empty():
		var error := _pipe_join(part,host,at,yaw,reverse)
		if not error.is_empty(): return error
		attached = true
	elif mount == "control" and host and (group == "Walls" or id(host) in ["RecipeControlConsole","RecipePressurePanel","RecipeIndicatorBoard","RecipeSchematic"]) and absf(normal.y)<.98:
		var n := normal.normalized()
		var x := Vector3.UP.cross(n).normalized()
		part.global_basis = Basis(x,n,x.cross(n))
		part.global_position = at
		attached = true
	elif mount in ["wall", "opening"] or (mount == "wall_or_ground" and group == "Walls"):
		var issue := _wall_mount(part, host, at, normal, mount == "opening")
		if not issue.is_empty(): return issue
		attached = true
	elif mount == "ceiling":
		if not host or not ("ceiling_enabled" in host and host.ceiling_enabled): return "Click a floor zone with its ceiling enabled."
		var local := host.to_local(at)
		if not Geometry2D.is_point_in_polygon(Vector2(local.x,local.z),host.polygon): return "Choose a point inside the ceiling."
		part.global_position = host.to_global(Vector3(local.x,host.ceiling_height,local.z)) - Vector3.UP*box.end.y
		attached = true
	elif mount == "deck" and host_mount == "deck":
		if not _deck_join(part,host,at): return "Click near an outside edge; R turns the new deck."
		attached = true
	elif mount == "deck" and host_mount == "run":
		var sockets := ends(host)
		if sockets.is_empty(): return "Choose an end of the flight."
		var socket := host.to_global(sockets[0])
		if host.to_global(sockets[-1]).distance_to(at) < socket.distance_to(at): socket = host.to_global(sockets[-1])
		if socket.distance_to(at) > JOIN_RADIUS: return "Click a flight end to fit a landing."
		var rim_points := rim(part)
		if rim_points.size() < 2: return "The platform needs an edge."
		var outward := (socket - host.to_global(sockets[-1] if socket.is_equal_approx(host.to_global(sockets[0])) else sockets[0]))
		outward.y = 0
		var center := Vector3.ZERO
		for v in rim_points: center += v / rim_points.size()
		var best := -INF
		var dock := Vector3.ZERO
		for i in rim_points.size():
			var mid := (rim_points[i]+rim_points[(i+1)%rim_points.size()])/2
			var score := (part.global_basis*(center-mid)).normalized().dot(outward.normalized())
			if score > best: best = score; dock = mid
		part.global_position += socket - part.to_global(dock)
		attached = true
	elif joint:
		host = joint
		attached = true
	elif id(host) == "RecipeWaterPatch" and (mount == "water_or_ground" or id(part) == "RecipeDock"):
		if normal.y < .9: return "Choose the water surface."
		# The rowboat's origin is its keel; the dock origin is its deck surface.
		part.global_position = at + Vector3.UP*(.28 if id(part) == "RecipeDock" else -float(part.height)*.38)
		if mount == "water_or_ground":
			for x in [box.position.x,box.end.x]:
				for z in [box.position.z,box.end.z]:
					var v: Vector3 = host.to_local(part.to_global(Vector3(x,0,z)))
					if absf(v.x)>host.width*.5 or absf(v.z)>host.depth*.5: return "The hull needs water underneath."
		attached = true
	else:
		if host and (normal.y < 0.96 or (host_mount != "deck" and not (mount in ["surface","control"] and (group in ["Tables", "Cabinets"] or id(host) in ["RecipePedestal","RecipePallet","RecipeCrockeryShelf","RecipeWashstand","HallCabinet","RecipeFoldingDesk","RecipeControlConsole","RecipeWorkCounter","RecipeStove"])))):
			return "Choose a level floor, or a supporting worktop for a small item."
		if host:
			part.global_position = at
			attached = true
		if mount not in ["deck", "run"]: part.global_position.y -= box.position.y
		if host_mount == "deck" and mount in ["surface","ground","control","water_or_ground"] and not _on_decks(part,root,box): return "Extend the floor under the contact points."
		if mount in ["surface","control"] and host and host_mount != "deck":
			# Sample the actual contact patch; a desk's raised back or a cabinet
			# cornice cannot silently support an object placed beside it.
			var excluded: Array[RID] = []
			_rids(part,excluded)
			for x in [box.position.x, box.end.x]:
				for z in [box.position.z, box.end.z]:
					var foot := part.to_global(Vector3(x,box.position.y,z))
					var ray := PhysicsRayQueryParameters3D.create(foot+Vector3.UP*.035,foot-Vector3.UP*.035)
					ray.exclude = excluded
					var result := root.get_world_3d().direct_space_state.intersect_ray(ray)
					if result.is_empty() or component(result.collider,root) != host or result.normal.y < .96: return "The object needs support under its whole footprint."
	var issue := _clearance(part,host,root,box)
	if not issue.is_empty(): return issue
	if attached: part.reparent(host,true)
	part.owner = root
	_pick_shape(part,root,box)
	if mount == "opening": host.rebuild()
	return ""
