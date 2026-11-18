extends RefCounted
## Planar wall graph: split intersections, walk bounded faces, inset each wall face.
## Optimised revision:
##  * graph nodes are merged with a spatial hash (tolerance) instead of a rounded string key,
##    so float noise at crossings can no longer split one node into two;
##  * segment intersection uses a bounding-box reject before the exact test;
##  * dangling branches are pruned with a work-list (linear) instead of repeated full scans;
##  * the wall-face inset limits its miters and falls back to a Clipper offset if the
##    per-edge inset self-intersects, so a sharp corner no longer deletes the whole room;
##  * every face now carries area / perimeter / centroid / neighbours / exterior-edge data.
const EPS = 0.0001
const MERGE_TOLERANCE = 0.002
const CELL = 0.01
const MITER_LIMIT = 3.0
const MIN_ROOM_AREA = 0.04

static func point(p: Array) -> Vector2: return Vector2(p[0],p[2])
static func key(p: Vector2) -> String: return "%.4f,%.4f" % [p.x,p.y]
static func cross(a: Vector2,b: Vector2) -> float: return a.cross(b)

## Return the id of an existing node within MERGE_TOLERANCE, or register a new one.
static func node_id(nodes: Dictionary, grid: Dictionary, p: Vector2) -> int:
	var cx = int(floor(p.x/CELL))
	var cy = int(floor(p.y/CELL))
	for dx in range(-1,2):
		for dy in range(-1,2):
			var bucket = grid.get(Vector2i(cx+dx,cy+dy),[])
			for id in bucket:
				if nodes[id].p.distance_to(p)<=MERGE_TOLERANCE: return id
	var fresh = nodes.size()
	nodes[fresh] = {"p":p,"next":[]}
	var cell = Vector2i(cx,cy)
	if not grid.has(cell): grid[cell] = []
	grid[cell].append(fresh)
	return fresh

static func rooms(walls: Array, elevation: float) -> Array:
	var segments = []
	for wall in walls:
		for i in range(wall.points.size()-1):
			var a = wall.points[i]
			var b = wall.points[i+1]
			if abs(a[1]-elevation)>0.3 or abs(b[1]-elevation)>0.3: continue
			if point(a).distance_to(point(b))<EPS: continue
			var pa = point(a)
			var pb = point(b)
			segments.append({"a":pa,"b":pb,"cuts":[0.0,1.0],"half":float(wall.thickness)*0.5,"wall":wall.id,
				"box":Rect2(Vector2(minf(pa.x,pb.x),minf(pa.y,pb.y)),Vector2(absf(pa.x-pb.x),absf(pa.y-pb.y))).grow(EPS*4)})
	if segments.size()<3: return []
	# Include crossings and collinear T junctions. A room node need not be an authored wall point.
	for i in range(segments.size()):
		for j in range(i+1,segments.size()):
			var a = segments[i]
			var b = segments[j]
			if not a.box.intersects(b.box,true): continue
			var u = a.b-a.a
			var v = b.b-b.a
			var det = cross(u,v)
			if abs(det)>EPS:
				var t = cross(b.a-a.a,v)/det
				var s = cross(b.a-a.a,u)/det
				if t>=-EPS and t<=1+EPS and s>=-EPS and s<=1+EPS:
					a.cuts.append(clampf(t,0,1)); b.cuts.append(clampf(s,0,1))
			else:
				for p in [b.a,b.b]:
					var t = (p-a.a).dot(u)/u.length_squared()
					if t>=0 and t<=1 and (a.a+u*t).distance_to(p)<EPS: a.cuts.append(t)
				for p in [a.a,a.b]:
					var t = (p-b.a).dot(v)/v.length_squared()
					if t>=0 and t<=1 and (b.a+v*t).distance_to(p)<EPS: b.cuts.append(t)
	var nodes = {}
	var grid = {}
	var edges = {}
	for segment in segments:
		segment.cuts.sort()
		for i in range(segment.cuts.size()-1):
			var a = segment.a.lerp(segment.b,segment.cuts[i])
			var b = segment.a.lerp(segment.b,segment.cuts[i+1])
			if a.distance_to(b)<EPS: continue
			var ia = node_id(nodes,grid,a)
			var ib = node_id(nodes,grid,b)
			if ia==ib: continue
			for pair in [[ia,ib],[ib,ia]]:
				if not nodes[pair[0]].next.has(pair[1]): nodes[pair[0]].next.append(pair[1])
				var ek = str(pair[0])+">"+str(pair[1])
				if not edges.has(ek) or segment.half>edges[ek].half: edges[ek] = {"half":segment.half,"wall":segment.wall}
	# Prune dangling branches with a work list.
	var work = []
	for nk in nodes:
		if nodes[nk].next.size()<=1: work.append(nk)
	while not work.is_empty():
		var nk = work.pop_back()
		if nodes[nk].next.is_empty(): continue
		var other = nodes[nk].next[0]
		nodes[other].next.erase(nk)
		nodes[nk].next.clear()
		if nodes[other].next.size()<=1: work.append(other)
	for nk in nodes:
		var center = nodes[nk].p
		nodes[nk].next.sort_custom(func(a,b): return (nodes[a].p-center).angle()<(nodes[b].p-center).angle())
	var visited = {}
	var faces = []
	var edge_face = {}
	for start in nodes:
		for neighbor in nodes[start].next:
			if visited.has(str(start)+">"+str(neighbor)): continue
			var ring = []
			var widths = []
			var wall_ids = []
			var ids = []
			var edge_keys = []
			var a = start
			var b = neighbor
			var complete = false
			for _step in range(edges.size()+1):
				var ek = str(a)+">"+str(b)
				if visited.has(ek): break
				visited[ek] = true
				ring.append(nodes[a].p)
				ids.append(a)
				edge_keys.append(ek)
				widths.append(edges[ek].half)
				wall_ids.append(edges[ek].wall)
				var outgoing = nodes[b].next
				var next = outgoing[posmod(outgoing.find(a)-1,outgoing.size())]
				a = b; b = next
				if a==start and b==neighbor: complete = true; break
			if not complete or ring.size()<3 or signed_area(ring)<=EPS: continue
			# Reject repeated-node walks; leaf branches were pruned above.
			var seen = {}
			var repeated = false
			for id in ids:
				if seen.has(id): repeated = true; break
				seen[id] = true
			if repeated: continue
			var floor = inset(ring,widths)
			if floor.size()<3: continue
			var floor_area = abs(signed_area(to_vectors(floor)))
			if floor_area<MIN_ROOM_AREA: continue
			var boundary = []
			for p in ring: boundary.append([p.x,p.y])
			var index = faces.size()
			for ek in edge_keys: edge_face[ek] = index
			faces.append({"nodes":boundary,"polygon":floor,"walls":wall_ids,"edges":edge_keys,"area":snappedf(floor_area,0.0001),"perimeter":snappedf(perimeter(floor),0.0001),"centroid":centroid(floor)})
	# Adjacency: a directed edge a>b is shared with the face owning b>a; otherwise it is an exterior edge.
	for index in range(faces.size()):
		var neighbors = []
		var exterior = 0
		for ek in faces[index].edges:
			var parts = ek.split(">")
			var reverse = parts[1]+">"+parts[0]
			if edge_face.has(reverse):
				if edge_face[reverse]!=index and not neighbors.has(edge_face[reverse]): neighbors.append(edge_face[reverse])
			else: exterior += 1
		faces[index].neighbors = neighbors
		faces[index].exteriorEdges = exterior
		faces[index].erase("edges")
	return faces

static func to_vectors(poly: Array) -> Array:
	var result = []
	for p in poly: result.append(p if p is Vector2 else Vector2(p[0],p[1]))
	return result

static func perimeter(poly: Array) -> float:
	var total = 0.0
	for i in range(poly.size()):
		var a = poly[i]
		var b = poly[(i+1)%poly.size()]
		total += Vector2(a[0],a[1]).distance_to(Vector2(b[0],b[1]))
	return total

static func centroid(poly: Array) -> Array:
	var area2 = 0.0
	var cx = 0.0
	var cy = 0.0
	for i in range(poly.size()):
		var a = poly[i]
		var b = poly[(i+1)%poly.size()]
		var c = a[0]*b[1]-b[0]*a[1]
		area2 += c
		cx += (a[0]+b[0])*c
		cy += (a[1]+b[1])*c
	if abs(area2)<EPS:
		var sum = Vector2.ZERO
		for p in poly: sum += Vector2(p[0],p[1])
		sum /= maxi(1,poly.size())
		return [snappedf(sum.x,0.0001),snappedf(sum.y,0.0001)]
	return [snappedf(cx/(3.0*area2),0.0001),snappedf(cy/(3.0*area2),0.0001)]

static func signed_area(poly: Array) -> float:
	var area = 0.0
	for i in range(poly.size()): area += cross(poly[i],poly[(i+1)%poly.size()])
	return area*0.5

static func valid_polygon(result: Array) -> bool:
	if result.size()<3: return false
	var contour = PackedVector2Array()
	for p in result: contour.append(Vector2(p[0],p[1]))
	return not Geometry2D.triangulate_polygon(contour).is_empty() and signed_area(Array(contour))>EPS

static func inset(poly: Array, widths: Array) -> Array:
	var result = []
	var count = poly.size()
	for i in range(count):
		var prev = posmod(i-1,count)
		var u = (poly[i]-poly[prev]).normalized()
		var v = (poly[(i+1)%count]-poly[i]).normalized()
		var a = poly[i]+Vector2(-u.y,u.x)*widths[prev]
		var b = poly[i]+Vector2(-v.y,v.x)*widths[i]
		var det = cross(u,v)
		var p = (a+b)*0.5 if abs(det)<EPS else a+u*cross(b-a,v)/det
		if not is_finite(p.x) or not is_finite(p.y): return fallback_inset(poly,widths)
		# Miter limit: very sharp corners would otherwise throw the vertex far outside the wall faces.
		var limit = MITER_LIMIT*maxf(widths[prev],widths[i])
		var offset = p-poly[i]
		if offset.length()>limit: p = poly[i]+offset.normalized()*limit
		result.append([snappedf(p.x,0.00001),snappedf(p.y,0.00001)])
	if valid_polygon(result): return result
	return fallback_inset(poly,widths)

## Uniform Clipper offset by the thinnest wall half-thickness; used when the per-edge inset collapses.
static func fallback_inset(poly: Array, widths: Array) -> Array:
	var smallest = INF
	for w in widths: smallest = minf(smallest,w)
	if not is_finite(smallest) or smallest<=0: return []
	var contour = PackedVector2Array()
	for p in poly: contour.append(p)
	var best = []
	var best_area = 0.0
	for shape in Geometry2D.offset_polygon(contour,-smallest,Geometry2D.JOIN_MITER):
		var candidate = []
		for p in shape: candidate.append([snappedf(p.x,0.00001),snappedf(p.y,0.00001)])
		if candidate.size()>=3 and signed_area(to_vectors(candidate))<0: candidate.reverse()
		var area = abs(signed_area(to_vectors(candidate)))
		if area>best_area and valid_polygon(candidate):
			best = candidate
			best_area = area
	return best
