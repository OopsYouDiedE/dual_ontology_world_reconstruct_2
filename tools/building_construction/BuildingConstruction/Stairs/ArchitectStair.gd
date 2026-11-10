extends RefCounted
const Geo = preload("../Shared/ArchitectGeometry.gd")
static func build(s: Dictionary) -> Node3D:
	var root = Node3D.new()
	root.position = Vector3(s.x,s.get("y",0),s.z)
	root.rotation.y = deg_to_rad(s.get("yaw",0))
	var rh = s.rise/float(s.risers)
	var td = s.run/float(s.risers)
	var nosing = s.get("nosing",0.03)
	var sides = []
	if s.get("railingPos","both") in ["both","left"]: sides.append(-s.width*0.5+0.05)
	if s.get("railingPos","both") in ["both","right"]: sides.append(s.width*0.5-0.05)
	for i in range(int(s.risers)):
		root.add_child(Geo.box(Vector3(td+nosing,0.045,s.width),"wood",Vector3(i*td+(td+nosing)*0.5-nosing,(i+1)*rh-0.022,0)))
		root.add_child(Geo.box(Vector3(0.03,rh,s.width),"wood_dark",Vector3(i*td,(i+1)*rh-rh*0.5,0)))
		for side in sides: root.add_child(Geo.box(Vector3(0.04,0.75,0.04),"wood_dark",Vector3(i*td+td*0.5,(i+1)*rh+0.375,side)))
	for side in sides:
		root.add_child(Geo.box(Vector3(0.09,0.95,0.09),"wood_dark",Vector3(0,0.475,side)))
		root.add_child(Geo.box(Vector3(0.09,0.95,0.09),"wood_dark",Vector3(s.run,s.rise+0.475,side)))
		var rail = Geo.box(Vector3(Vector2(s.run,s.rise).length(),0.06,0.08),"wood_dark",Vector3(s.run*0.5,s.rise*0.5+0.85,side))
		rail.rotation.z = atan2(s.rise,s.run)
		root.add_child(rail)
	return root
