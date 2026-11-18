extends RefCounted
const Geo = preload("../Shared/ArchitectGeometry.gd")
var rng_state = 7.0
func uniform(low: float, high: float) -> float:
	rng_state = fmod(rng_state*9301+49297,233280)
	return low+(high-low)*rng_state/233280
static func build(params: Dictionary) -> Node3D:
	var rng = new()
	rng.rng_state = params.get("seed",7)
	var pw = params.get("plant_w",params.get("width",0.65))
	var ph = params.get("plant_h",params.get("height",0.85))
	var count = max(0,floor(params.get("flower_count",7)))
	var pot_h = ph*0.44
	var radius = pw*0.31
	var root = Node3D.new()
	root.add_child(Geo.lathe([[radius*0.60,0],[radius*0.67,pot_h*0.07],[radius*0.91,pot_h*0.78],[radius*0.94,pot_h*0.84],[radius,pot_h*0.86],[radius,pot_h],[radius*0.82,pot_h],[radius*0.78,pot_h*0.81],[radius*0.56,pot_h*0.17],[0,pot_h*0.17]],8))
	var soil = Geo.mesh(Geo.cylinder(radius*0.78,radius*0.78,ph*0.018,8),"wood_dark")
	soil.position.y = pot_h*0.86+ph*0.018*0.5
	root.add_child(soil)
	for i in range(10):
		var theta = TAU*i/10+rng.uniform(-0.15,0.15)
		var outer = pw*rng.uniform(0.38,0.48)
		var start = Vector3(cos(theta)*pw*0.05,pot_h*0.92,sin(theta)*pw*0.05)
		var end = Vector3(cos(theta)*outer,ph*rng.uniform(0.48,0.68),sin(theta)*outer)
		var width = pw*rng.uniform(0.15,0.23)
		var delta = Vector2(end.x-start.x,end.z-start.z)
		var length = delta.length() if delta.length()>0 else 0.000001
		var cross = Vector3(-delta.y/length,0,delta.x/length)
		var center = (start+end)*0.5
		var points = [start,end,center+cross*width*0.5,center-cross*width*0.5,center+Vector3.UP*width*0.14,center-Vector3.UP*width*0.04]
		var indices = [0,2,4,2,1,4,1,3,4,3,0,4,2,0,5,1,2,5,3,1,5,0,3,5]
		var vertices = []
		for j in range(0,indices.size(),3): vertices.append_array([points[indices[j]],points[indices[j+2]],points[indices[j+1]]])
		root.add_child(Geo.surface(vertices,"green" if i%3==0 else "leaf"))
	for i in range(int(count)):
		var fx = 0.0
		var fz = 0.0
		var fy = ph*0.89
		if i>0:
			var angle = TAU*(i-1)/max(1,count-1)+0.20
			var rr = pw*(0.23 if count<=8 else 0.29)
			fx = cos(angle)*rr
			fz = sin(angle)*rr
			fy = ph*(0.72+0.06*sin(angle*2+0.4))
		var flower_radius = min(pw*0.115,ph*0.09)
		var start = Vector3(fx*0.35,pot_h*0.85,fz*0.35)
		var end = Vector3(fx,fy,fz)
		var delta = end-start
		var stem = Geo.mesh(Geo.cylinder(pw*0.006,pw*0.006,delta.length(),6),"leaf")
		stem.position = (start+end)*0.5
		stem.quaternion = Quaternion(Vector3.UP,delta.normalized())
		root.add_child(stem)
		var heart = Geo.mesh(Geo.ico(flower_radius*0.65,1,Vector3(1,0.75,1)),"cream")
		heart.position = Vector3(fx,fy+flower_radius*0.15,fz)
		root.add_child(heart)
		for petal in range(6):
			var theta = petal*PI/3+i*0.37
			var pr = flower_radius*0.65
			var mesh = Geo.mesh(Geo.ico(flower_radius*0.62,1,Vector3(1,0.70,1)),"cream")
			mesh.position = Vector3(fx+cos(theta)*pr,fy+rng.uniform(-0.05,0.08)*flower_radius,fz+sin(theta)*pr)
			root.add_child(mesh)
		var pollen = Geo.mesh(Geo.ico(flower_radius*0.25,1),"wall")
		pollen.position = Vector3(fx,fy+flower_radius*0.60,fz)
		root.add_child(pollen)
	return root
