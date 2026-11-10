extends RefCounted
## Planar wall graph: split intersections, walk bounded faces, inset each wall face.
const EPS = 0.0001

static func point(p: Array) -> Vector2: return Vector2(p[0],p[2])
static func key(p: Vector2) -> String: return "%.4f,%.4f" % [p.x,p.y]
static func cross(a: Vector2,b: Vector2) -> float: return a.cross(b)

static func rooms(walls: Array, elevation: float) -> Array:
	var segments = []
	for wall in walls:
		for i in range(wall.points.size()-1):
			var a = wall.points[i]
			var b = wall.points[i+1]
			if abs(a[1]-elevation)>0.3 or abs(b[1]-elevation)>0.3: continue
			if point(a).distance_to(point(b))<EPS: continue
			segments.append({"a":point(a),"b":point(b),"cuts":[0.0,1.0],"half":float(wall.thickness)*0.5,"wall":wall.id})
	# Include crossings and collinear T junctions. A room node need not be an authored wall point.
	for i in range(segments.size()):
		for j in range(i+1,segments.size()):
			var a = segments[i]
			var b = segments[j]
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
	var edges = {}
	for segment in segments:
		segment.cuts.sort()
		for i in range(segment.cuts.size()-1):
			var a = segment.a.lerp(segment.b,segment.cuts[i])
			var b = segment.a.lerp(segment.b,segment.cuts[i+1])
			if a.distance_to(b)<EPS: continue
			var ka = key(a)
			var kb = key(b)
			for pair in [[ka,a],[kb,b]]:
				if not nodes.has(pair[0]): nodes[pair[0]] = {"p":pair[1],"next":[]}
			for pair in [[ka,kb],[kb,ka]]:
				if not nodes[pair[0]].next.has(pair[1]): nodes[pair[0]].next.append(pair[1])
				var ek = pair[0]+">"+pair[1]
				if not edges.has(ek) or segment.half>edges[ek].half: edges[ek] = {"half":segment.half,"wall":segment.wall}
	var pruning = true
	while pruning:
		pruning = false
		for nk in nodes:
			if nodes[nk].next.size()!=1: continue
			var other = nodes[nk].next[0]
			nodes[other].next.erase(nk)
			nodes[nk].next.clear()
			pruning = true
	for nk in nodes:
		var center = nodes[nk].p
		nodes[nk].next.sort_custom(func(a,b): return (nodes[a].p-center).angle()<(nodes[b].p-center).angle())
	var visited = {}
	var result = []
	for start in nodes:
		for neighbor in nodes[start].next:
			if visited.has(start+">"+neighbor): continue
			var ring = []
			var widths = []
			var wall_ids = []
			var a = start
			var b = neighbor
			var complete = false
			for _step in range(edges.size()+1):
				var ek = a+">"+b
				if visited.has(ek): break
				visited[ek] = true
				ring.append(nodes[a].p)
				widths.append(edges[ek].half)
				wall_ids.append(edges[ek].wall)
				var outgoing = nodes[b].next
				var next = outgoing[posmod(outgoing.find(a)-1,outgoing.size())]
				a = b; b = next
				if a==start and b==neighbor: complete = true; break
			if not complete or ring.size()<3 or signed_area(ring)<=EPS: continue
			# Reject repeated-node walks; leaf branches were pruned above.
			var clean = []
			for p in ring:
				if not clean.has(key(p)): clean.append(key(p))
			if clean.size()!=ring.size(): continue
			var floor = inset(ring,widths)
			if floor.size()<3: continue
			var boundary = []
			for p in ring: boundary.append([p.x,p.y])
			result.append({"nodes":boundary,"polygon":floor,"walls":wall_ids})
	return result

static func signed_area(poly: Array) -> float:
	var area = 0.0
	for i in range(poly.size()): area += cross(poly[i],poly[(i+1)%poly.size()])
	return area*0.5

static func inset(poly: Array, widths: Array) -> Array:
	var result = []
	for i in range(poly.size()):
		var prev = posmod(i-1,poly.size())
		var u = (poly[i]-poly[prev]).normalized()
		var v = (poly[(i+1)%poly.size()]-poly[i]).normalized()
		var a = poly[i]+Vector2(-u.y,u.x)*widths[prev]
		var b = poly[i]+Vector2(-v.y,v.x)*widths[i]
		var det = cross(u,v)
		var p = (a+b)*0.5 if abs(det)<EPS else a+u*cross(b-a,v)/det
		if not is_finite(p.x) or not is_finite(p.y): return []
		result.append([snappedf(p.x,0.00001),snappedf(p.y,0.00001)])
	var contour = PackedVector2Array()
	for p in result: contour.append(Vector2(p[0],p[1]))
	if Geometry2D.triangulate_polygon(contour).is_empty() or signed_area(Array(contour))<=EPS: return []
	return result
