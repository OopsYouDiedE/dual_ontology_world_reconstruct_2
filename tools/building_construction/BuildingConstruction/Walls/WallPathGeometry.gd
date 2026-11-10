extends RefCounted
## buildSingleWall3D: segment splitting, mouldings and openings as in the web editor,
## with mitred joints. Each segment now has separate start/end extents for its front (+z)
## and back (-z) faces, so two walls meeting at ANY angle close cleanly. The old build trimmed
## every segment by a fixed amount and plugged the joint with an axis-aligned square post,
## which left gaps and overlaps on diagonal corners.
const Geo = preload("../Shared/ArchitectGeometry.gd")
const Openings = preload("../Windows/ArchitectOpenings.gd")
const MITER_LIMIT_THICKNESSES = 2.5

static func _direction(points: Array, i: int) -> Vector2:
	var d = Vector2(points[i+1][0]-points[i][0],points[i+1][2]-points[i][2])
	return d.normalized() if d.length()>=0.01 else Vector2.ZERO

## Face extensions for the joint where a segment heading `u` meets one heading `v`.
## t: how far the end of the first segment's FRONT face runs past the node (back face: -t).
## s: how far the start of the second segment's FRONT face is shifted along its axis (back face: -s).
## Returns {} when there is no clean mitre (U-turn or a spike longer than the limit).
static func miter(u: Vector2, v: Vector2, half: float, limit: float) -> Dictionary:
	var det = u.cross(v)
	if u.dot(v)<=0.0 and abs(det)<0.02: return {}
	if abs(det)<0.0005: return {"t":0.0,"s":0.0}
	var d = Vector2(-v.y,v.x)-Vector2(-u.y,u.x)
	var t = half*d.cross(v)/det
	var s = half*d.cross(u)/det
	if abs(t)>limit or abs(s)>limit: return {}
	return {"t":t,"s":s}

static func build(wall: Dictionary) -> Node3D:
	var root = Node3D.new()
	root.name = str(wall.get("name","墙体"))
	root.set_meta("wall_path",wall.duplicate(true))
	var points = wall.points
	var height = float(wall.height)
	var thickness = float(wall.thickness)
	var base_y = float(wall.get("baseY",0))
	var style = str(wall.get("style","classical"))
	var pillars = bool(wall.get("hasPillars",true))
	var closed = bool(wall.get("closed",false))
	var openings = wall.get("openings",[])
	var wall_mat = "stone" if style == "stone" else "wall"
	var half_t = thickness*0.5
	var total = points.size()-1
	var dirs = []
	for i in range(total): dirs.append(_direction(points,i))
	var bevel_joints = {}
	for i in range(total):
		var p0 = points[i]
		var p1 = points[i+1]
		var dx = p1[0]-p0[0]
		var dz = p1[2]-p0[2]
		var length = Vector2(dx,dz).length()
		if length<0.01: continue
		var u = dirs[i]
		var segment_y = p0[1] if p0.size()>1 else base_y
		var flat_trim = min(length*0.25,thickness*(0.52 if pillars else 0.48))
		# Front/back extents of the two long faces.
		var f0 = 0.0
		var b0 = 0.0
		var f1 = length
		var b1 = length
		var start_mitred = false
		var end_mitred = false
		var previous = i-1 if i>0 else (total-1 if closed else -1)
		var following = i+1 if i<total-1 else (0 if closed else -1)
		if previous>=0 and previous!=i and dirs[previous]!=Vector2.ZERO:
			var m = miter(dirs[previous],u,half_t,thickness*MITER_LIMIT_THICKNESSES)
			if m.is_empty():
				f0 = flat_trim; b0 = flat_trim; bevel_joints[i] = true
			else:
				f0 = m.s; b0 = -m.s; start_mitred = true
		elif pillars:
			f0 = flat_trim; b0 = flat_trim
		if following>=0 and following!=i and dirs[following]!=Vector2.ZERO:
			var m = miter(u,dirs[following],half_t,thickness*MITER_LIMIT_THICKNESSES)
			if m.is_empty():
				f1 = length-flat_trim; b1 = length-flat_trim; bevel_joints[following] = true
			else:
				f1 = length+m.t; b1 = length-m.t; end_mitred = true
		elif pillars:
			f1 = length-flat_trim; b1 = length-flat_trim
		if f1-f0<0.02 or b1-b0<0.02:
			# Segment too short for the mitre: fall back to flat trimmed ends.
			f0 = flat_trim if (previous>=0 or pillars) else 0.0; b0 = f0
			f1 = length-(flat_trim if (following>=0 or pillars) else 0.0); b1 = f1
			start_mitred = false; end_mitred = false
			if f1-f0<0.02: f0 = 0.0; b0 = 0.0; f1 = length; b1 = length
		# Inner extent: where openings and mouldings may live.
		var x_min = max(f0,b0)
		var x_max = max(x_min+0.01,min(f1,b1))
		var lo = min(f0,b0)
		var hi = max(f1,b1)
		var holes = openings.filter(func(o): return o.segment == i)
		var seg = Node3D.new()
		seg.name = "Segment_%d" % i
		var x_set = [lo,hi,f0,b0,f1,b1,x_min,x_max]
		for o in holes:
			x_set.append(clampf(o.center-o.width*0.5,x_min,x_max))
			x_set.append(clampf(o.center+o.width*0.5,x_min,x_max))
		x_set.sort()
		var xs = []
		for value in x_set:
			if xs.is_empty() or abs(value-xs[-1])>0.001: xs.append(value)
		var vertices = []
		for j in range(xs.size()-1):
			var x0 = xs[j]
			var x1 = xs[j+1]
			var width = x1-x0
			if width<0.002: continue
			var xm = (x0+x1)*0.5
			var fa = clampf(x0,f0,f1)
			var fb = clampf(x1,f0,f1)
			var ba = clampf(x0,b0,b1)
			var bb = clampf(x1,b0,b1)
			var has_front = fb-fa>=0.002
			var has_back = bb-ba>=0.002
			if not has_front and not has_back: continue
			var active = holes.filter(func(o): return o.center-o.width*0.5<=xm and xm<=o.center+o.width*0.5)
			active.sort_custom(func(a,b): return a.bottom<b.bottom)
			var cursor = 0.0
			var gaps = []
			for o in active:
				if o.bottom>cursor+0.001: gaps.append([cursor,o.bottom])
				cursor = max(cursor,o.bottom+o.height)
			if height>cursor+0.001: gaps.append([cursor,height])
			for gap in gaps:
				var y0 = gap[0]
				var cornice = style == "classical" and gap[1]>=height-0.01 and gap[1]-y0>=0.16
				var y1 = height-0.12 if cornice else gap[1]
				if has_front: Geo.quad(vertices,Vector3(fa,y0,half_t),Vector3(fb,y0,half_t),Vector3(fb,y1,half_t),Vector3(fa,y1,half_t))
				if has_back: Geo.quad(vertices,Vector3(bb,y0,-half_t),Vector3(ba,y0,-half_t),Vector3(ba,y1,-half_t),Vector3(bb,y1,-half_t))
				if not cornice: Geo.quad(vertices,Vector3(fa,y1,half_t),Vector3(fb,y1,half_t),Vector3(bb,y1,-half_t),Vector3(ba,y1,-half_t))
				Geo.quad(vertices,Vector3(ba,y0,-half_t),Vector3(bb,y0,-half_t),Vector3(fb,y0,half_t),Vector3(fa,y0,half_t))
				if style in ["classical","dado"] and x0>=x_min-0.001 and x1<=x_max+0.001:
					if y0<=0.01 and gap[1]>=0.17: seg.add_child(Geo.box(Vector3(width,0.17,thickness+0.04),"wood_dark",Vector3(xm,0.085,0)))
					if y0<=1.01 and gap[1]>=1.09: seg.add_child(Geo.box(Vector3(width,0.08,thickness+0.05),"wood_dark",Vector3(xm,1.05,0)))
					if cornice: seg.add_child(Geo.box(Vector3(width,0.12,thickness+0.06),"wood_dark",Vector3(xm,height-0.06,0)))
		var cap_top = height-0.12 if style == "classical" else height
		# Flat end caps only where the end is not closed by a neighbouring mitre.
		if not start_mitred:
			Geo.quad(vertices,Vector3(f0,0,-half_t),Vector3(f0,0,half_t),Vector3(f0,cap_top,half_t),Vector3(f0,cap_top,-half_t))
		if not end_mitred:
			Geo.quad(vertices,Vector3(f1,0,half_t),Vector3(f1,0,-half_t),Vector3(f1,cap_top,-half_t),Vector3(f1,cap_top,half_t))
		for o in holes:
			var lx = max(x_min,o.center-o.width*0.5)
			var rx = min(x_max,o.center+o.width*0.5)
			var by = o.bottom
			var ty = min(cap_top,o.bottom+o.height)
			Geo.quad(vertices,Vector3(lx,by,half_t),Vector3(lx,by,-half_t),Vector3(lx,ty,-half_t),Vector3(lx,ty,half_t))
			Geo.quad(vertices,Vector3(rx,by,-half_t),Vector3(rx,by,half_t),Vector3(rx,ty,half_t),Vector3(rx,ty,-half_t))
			if o.type=="arched_window":
				# Fill the rectangular cutout's upper corners to match the arched frame.
				var rise = clampf(float(o.get("rise",0.4)),0.01,float(o.height))
				var spring = by+o.height-rise
				for ai in range(14):
					var a = PI*float(ai)/14.0
					var b = PI*float(ai+1)/14.0
					var ax = o.center-cos(a)*o.width*0.5
					var bx = o.center-cos(b)*o.width*0.5
					var ay = spring+sin(a)*rise
					var by_arc = spring+sin(b)*rise
					Geo.quad(vertices,Vector3(ax,ay,half_t),Vector3(bx,by_arc,half_t),Vector3(bx,ty,half_t),Vector3(ax,ty,half_t))
					Geo.quad(vertices,Vector3(bx,by_arc,-half_t),Vector3(ax,ay,-half_t),Vector3(ax,ty,-half_t),Vector3(bx,ty,-half_t))
					Geo.quad(vertices,Vector3(ax,ay,-half_t),Vector3(bx,by_arc,-half_t),Vector3(bx,by_arc,half_t),Vector3(ax,ay,half_t))
		seg.add_child(Geo.surface(vertices,wall_mat))
		for o in holes:
			var component = Openings.build(o.type,o.width,o.height,o.bottom,(o.get("rise",0.4) if o.get("rise",0.4) else 0.4),thickness)
			component.position = Vector3(o.center,o.bottom,0)
			seg.add_child(component)
		seg.position = Vector3(p0[0],segment_y,p0[2])
		seg.rotation.y = -atan2(dz,dx)
		root.add_child(seg)
	var limit = points.size()-1 if closed else points.size()
	for i in range(limit):
		var first_child = root.get_child_count()
		var pt = points[i]
		var y = pt[1] if pt.size()>1 else base_y
		# Post orientation follows the adjoining segment, so it is square to the wall at any angle.
		var heading = Vector2.RIGHT
		if i<total and dirs[i]!=Vector2.ZERO: heading = dirs[i]
		elif i>0 and dirs[i-1]!=Vector2.ZERO: heading = dirs[i-1]
		var yaw = -atan2(heading.y,heading.x)
		if pillars:
			var width = thickness*1.35
			var post = Geo.box(Vector3(width,height+0.06,width),"wood_dark",Vector3(pt[0],y+(height+0.06)*0.5,pt[2]))
			post.rotation.y = yaw
			root.add_child(post)
		elif closed or (i>0 and i<limit-1):
			# Mitred walls need no filler post; only joints that fell back to a flat butt joint, and the classical cornice cap.
			var corner_h = height-0.12 if style == "classical" else height
			if bevel_joints.has(i):
				var filler = Geo.box(Vector3(thickness,corner_h,thickness),wall_mat,Vector3(pt[0],y+corner_h*0.5,pt[2]))
				filler.rotation.y = yaw
				root.add_child(filler)
			if style == "classical":
				var cap = Geo.box(Vector3(thickness+0.06,0.12,thickness+0.06),"wood_dark",Vector3(pt[0],y+height-0.06,pt[2]))
				cap.rotation.y = yaw
				root.add_child(cap)
		for child_index in range(first_child,root.get_child_count()):
			root.get_child(child_index).set_meta("wall_joint",i)
	return root
