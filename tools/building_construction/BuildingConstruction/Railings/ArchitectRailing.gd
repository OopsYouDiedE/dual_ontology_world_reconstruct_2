extends RefCounted
const Geo = preload("../Shared/ArchitectGeometry.gd")
static func build(data: Dictionary) -> Node3D:
	var root = Node3D.new()
	var height = data.get("height",0.9)
	var spacing = data.get("spacing",0.18)
	for i in range(data.points.size()-1):
		var p0 = data.points[i]
		var p1 = data.points[i+1]
		var dx = p1[0]-p0[0]
		var dz = p1[2]-p0[2]
		var length = Vector2(dx,dz).length()
		if length<0.05: continue
		var seg = Node3D.new()
		seg.add_child(Geo.box(Vector3(length,0.06,0.07),"wood_dark",Vector3(length*0.5,height-0.03,0)))
		seg.add_child(Geo.box(Vector3(length,0.04,0.06),"wood_dark",Vector3(length*0.5,0.05,0)))
		var count = max(1,floor(length/spacing))
		for k in range(1,int(count)): seg.add_child(Geo.box(Vector3(0.04,height-0.12,0.04),"wood",Vector3(k*length/count,height*0.5,0)))
		seg.add_child(Geo.box(Vector3(0.09,height+0.08,0.09),"wood_dark",Vector3(0,(height+0.08)*0.5,0)))
		if i==data.points.size()-2: seg.add_child(Geo.box(Vector3(0.09,height+0.08,0.09),"wood_dark",Vector3(length,(height+0.08)*0.5,0)))
		seg.position = Vector3(p0[0],p0[1],p0[2])
		seg.rotation.y = -atan2(dz,dx)
		root.add_child(seg)
	return root
