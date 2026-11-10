extends RefCounted
## buildSingleWall3D: same segment splitting, trims, mouldings and joints as the web editor.
const Geo = preload("../Shared/ArchitectGeometry.gd")
const Openings = preload("../Windows/ArchitectOpenings.gd")

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
	var openings = wall.get("openings",[])
	var wall_mat = "stone" if style == "stone" else "wall"
	var half_t = thickness*0.5
	var total = points.size()-1
	for i in range(total):
		var p0 = points[i]
		var p1 = points[i+1]
		var dx = p1[0]-p0[0]
		var dz = p1[2]-p0[2]
		var length = Vector2(dx,dz).length()
		if length<0.01: continue
		var segment_y = p0[1] if p0.size()>1 else base_y
		var start_join = wall.closed or i>0 or pillars
		var end_join = wall.closed or i<total-1 or pillars
		var start_trim = min(length*0.25,thickness*(0.52 if pillars else 0.48)) if start_join else 0.0
		var end_trim = min(length*0.25,thickness*(0.52 if pillars else 0.48)) if end_join else 0.0
		var x_min = start_trim
		var x_max = max(x_min+0.01,length-end_trim)
		var holes = openings.filter(func(o): return o.segment == i)
		var seg = Node3D.new()
		seg.name = "Segment_%d" % i
		var x_set = [x_min,x_max]
		for o in holes:
			x_set.append(max(x_min,o.center-o.width*0.5))
			x_set.append(min(x_max,o.center+o.width*0.5))
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
				Geo.quad(vertices,Vector3(x0,y0,half_t),Vector3(x1,y0,half_t),Vector3(x1,y1,half_t),Vector3(x0,y1,half_t))
				Geo.quad(vertices,Vector3(x1,y0,-half_t),Vector3(x0,y0,-half_t),Vector3(x0,y1,-half_t),Vector3(x1,y1,-half_t))
				if not cornice: Geo.quad(vertices,Vector3(x0,y1,half_t),Vector3(x1,y1,half_t),Vector3(x1,y1,-half_t),Vector3(x0,y1,-half_t))
				Geo.quad(vertices,Vector3(x0,y0,-half_t),Vector3(x1,y0,-half_t),Vector3(x1,y0,half_t),Vector3(x0,y0,half_t))
				if style in ["classical","dado"]:
					if y0<=0.01 and gap[1]>=0.17: seg.add_child(Geo.box(Vector3(width,0.17,thickness+0.04),"wood_dark",Vector3(xm,0.085,0)))
					if y0<=1.01 and gap[1]>=1.09: seg.add_child(Geo.box(Vector3(width,0.08,thickness+0.05),"wood_dark",Vector3(xm,1.05,0)))
					if cornice: seg.add_child(Geo.box(Vector3(width,0.12,thickness+0.06),"wood_dark",Vector3(xm,height-0.06,0)))
		var cap_top = height-0.12 if style == "classical" else height
		Geo.quad(vertices,Vector3(x_min,0,-half_t),Vector3(x_min,0,half_t),Vector3(x_min,cap_top,half_t),Vector3(x_min,cap_top,-half_t))
		Geo.quad(vertices,Vector3(x_max,0,half_t),Vector3(x_max,0,-half_t),Vector3(x_max,cap_top,-half_t),Vector3(x_max,cap_top,half_t))
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
	var limit = points.size()-1 if wall.closed else points.size()
	for i in range(limit):
		var first_child = root.get_child_count()
		var pt = points[i]
		var y = pt[1] if pt.size()>1 else base_y
		if pillars:
			var width = thickness*1.35
			root.add_child(Geo.box(Vector3(width,height+0.06,width),"wood_dark",Vector3(pt[0],y+(height+0.06)*0.5,pt[2])))
		elif wall.closed or (i>0 and i<limit-1):
			var corner_h = height-0.12 if style == "classical" else height
			root.add_child(Geo.box(Vector3(thickness,corner_h,thickness),wall_mat,Vector3(pt[0],y+corner_h*0.5,pt[2])))
			if style == "classical": root.add_child(Geo.box(Vector3(thickness+0.06,0.12,thickness+0.06),"wood_dark",Vector3(pt[0],y+height-0.06,pt[2])))
		for child_index in range(first_child,root.get_child_count()):
			root.get_child(child_index).set_meta("wall_joint",i)
	return root
