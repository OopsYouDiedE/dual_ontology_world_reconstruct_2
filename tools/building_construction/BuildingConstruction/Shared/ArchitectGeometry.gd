extends RefCounted
## Native geometry adapters for the original web editor. Coordinates remain X/Y/Z.
const COLORS = {"wood":0x6D3C28,"wood_dark":0x402319,"wood_light":0x915A3D,"wall":0xAD8158,"stone":0xC9B698,"stone_dark":0x82756A,"grout":0x483C32,"gold":0xCAA15A,"green":0x40563C,"leaf":0x52613A,"cream":0xE7D6AA,"emission":0xFFD58B,"glass":0x8BAAB7,"tile_light":0xE8DAC3,"tile_dark":0x262220,"blackboard":0x243328,"book_red":0x8A3324,"book_blue":0x2F4858,"book_green":0x335C43,"fabric_bed":0xDFD5C6}
static var materials: Dictionary = {}

static func material(key: String) -> StandardMaterial3D:
	if materials.has(key): return materials[key]
	var mat = StandardMaterial3D.new()
	mat.albedo_color = Color.hex((int(COLORS.get(key,0xAD8158)) << 8) | 255)
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.roughness = 0.75 if "dark" in key or "stone" in key else 0.58
	if key == "glass":
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mat.albedo_color.a = 0.42
		mat.roughness = 0.1
	elif key == "gold":
		mat.metallic = 0.65
		mat.roughness = 0.28
	elif key == "emission": mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	materials[key] = mat
	return mat

static func box(size: Vector3, key: String, position := Vector3.ZERO) -> MeshInstance3D:
	var node = MeshInstance3D.new()
	var mesh = BoxMesh.new()
	mesh.size = size
	node.mesh = mesh
	node.material_override = material(key)
	node.position = position
	return node

static func mesh(shape: Mesh, key: String) -> MeshInstance3D:
	var node = MeshInstance3D.new()
	node.mesh = shape
	node.material_override = material(key)
	return node

static func cylinder(top: float, bottom: float, height: float, sides: int = 12) -> CylinderMesh:
	var shape = CylinderMesh.new()
	shape.top_radius = top
	shape.bottom_radius = bottom
	shape.height = height
	shape.radial_segments = maxi(3,sides)
	shape.rings = 1
	return shape
static func cone(radius: float, height: float, sides: int) -> CylinderMesh: return cylinder(0,radius,height,sides)
static func torus(radius: float, tube: float, radial: int, tubular: int) -> ArrayMesh:
	var vertices = []
	for i in range(tubular):
		for j in range(radial):
			var points = []
			for pair in [[i,j],[i+1,j],[i+1,j+1],[i,j+1]]:
				var a = pair[0]*TAU/tubular
				var b = pair[1]*TAU/radial
				points.append(Vector3((radius+tube*cos(b))*cos(a),(radius+tube*cos(b))*sin(a),tube*sin(b)))
			quad(vertices,points[0],points[1],points[2],points[3])
	var node = surface(vertices,"gold")
	var result = node.mesh
	node.free()
	return result
static func ico(radius: float, detail: int = 0, scale := Vector3.ONE) -> ArrayMesh:
	var t = (1.0+sqrt(5.0))*0.5
	var points = [Vector3(-1,t,0),Vector3(1,t,0),Vector3(-1,-t,0),Vector3(1,-t,0),Vector3(0,-1,t),Vector3(0,1,t),Vector3(0,-1,-t),Vector3(0,1,-t),Vector3(t,0,-1),Vector3(t,0,1),Vector3(-t,0,-1),Vector3(-t,0,1)]
	var faces = [[0,11,5],[0,5,1],[0,1,7],[0,7,10],[0,10,11],[1,5,9],[5,11,4],[11,10,2],[10,7,6],[7,1,8],[3,9,4],[3,4,2],[3,2,6],[3,6,8],[3,8,9],[4,9,5],[2,4,11],[6,2,10],[8,6,7],[9,8,1]]
	var vertices = []
	var divisions = detail+1
	for face in faces:
		var a = points[face[0]]
		var b = points[face[1]]
		var c = points[face[2]]
		var rows = []
		for i in range(divisions+1):
			var row = []
			var aj = a.lerp(c,float(i)/divisions)
			var bj = b.lerp(c,float(i)/divisions)
			for j in range(divisions-i+1): row.append(aj if i==divisions else aj.lerp(bj,float(j)/(divisions-i)))
			rows.append(row)
		for i in range(divisions):
			for j in range(divisions-i):
				vertices.append_array([rows[i][j].normalized()*radius*scale,rows[i+1][j].normalized()*radius*scale,rows[i][j+1].normalized()*radius*scale])
				if j<divisions-i-1: vertices.append_array([rows[i][j+1].normalized()*radius*scale,rows[i+1][j].normalized()*radius*scale,rows[i+1][j+1].normalized()*radius*scale])
	var node = surface(vertices,"cream")
	var result = node.mesh
	node.free()
	return result
static func light(color: int, energy: float, distance: float, attenuation: float) -> OmniLight3D:
	var node = OmniLight3D.new()
	node.light_color = Color.hex((color<<8)|255)
	node.light_energy = energy
	node.omni_range = distance
	node.omni_attenuation = attenuation
	return node

static func lathe(profile: Array, sides: int = 8) -> MeshInstance3D:
	var points = []
	var rings = []
	for pair in profile:
		var ring = []
		if abs(pair[0])<0.00000001:
			ring.append(points.size())
			points.append(Vector3(0,pair[1],0))
		else:
			for j in range(sides):
				var theta = TAU*j/sides+PI/sides
				ring.append(points.size())
				points.append(Vector3(pair[0]*cos(theta),pair[1],pair[0]*sin(theta)))
		rings.append(ring)
	var vertices = []
	for r in range(rings.size()-1):
		var a = rings[r]
		var b = rings[r+1]
		for j in range(sides):
			var k = (j+1)%sides
			if a.size()==1 and b.size()==1: continue
			if a.size()==1: vertices.append_array([points[a[0]],points[b[j]],points[b[k]]])
			elif b.size()==1: vertices.append_array([points[a[j]],points[b[0]],points[a[k]]])
			else: vertices.append_array([points[a[j]],points[b[k]],points[a[k]],points[a[j]],points[b[j]],points[b[k]]])
	if not rings.is_empty() and rings[0].size()>1:
		for j in range(sides): vertices.append_array([Vector3(0,profile[0][1],0),points[rings[0][(j+1)%sides]],points[rings[0][j]]])
	return surface(vertices,"stone")

static func quad(vertices: Array, a: Vector3, b: Vector3, c: Vector3, d: Vector3) -> void:
	# Godot clockwise front winding; normals retain the original Three.js orientation.
	vertices.append_array([a,c,b,a,d,c])

static func surface(vertices: Array, key: String) -> MeshInstance3D:
	var node = MeshInstance3D.new()
	if vertices.is_empty(): return node
	var st = SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in range(0,vertices.size(),3):
		var normal = (vertices[i+2]-vertices[i]).cross(vertices[i+1]-vertices[i]).normalized()
		for j in range(3):
			st.set_normal(normal)
			st.add_vertex(vertices[i+j])
	node.mesh = st.commit()
	node.material_override = material(key)
	return node

static func points2(poly: Array) -> PackedVector2Array:
	var result = PackedVector2Array()
	for p in poly: result.append(Vector2(p[0],p[1]))
	return result

static func area(poly: Array) -> float:
	var value = 0.0
	for i in range(poly.size()):
		var j = (i+1)%poly.size()
		value += poly[i][0]*poly[j][1]-poly[j][0]*poly[i][1]
	return value*0.5

static func ccw(poly: Array) -> Array:
	var copy = poly.duplicate(true)
	if area(copy)>0: copy.reverse()
	return copy

static func js_round(value: float) -> float:
	return floor(value+0.5)

static func offset(poly: Array, distance: float) -> Array:
	var ring = ccw(poly)
	var result = []
	var count = ring.size()
	for i in range(count):
		var prev = ring[posmod(i-1,count)]
		var curr = ring[i]
		var next = ring[(i+1)%count]
		var v1x = curr[0]-prev[0]
		var v1z = curr[1]-prev[1]
		var len1 = sqrt(v1x*v1x+v1z*v1z)
		if len1==0: len1 = 1
		v1x /= len1; v1z /= len1
		var v2x = next[0]-curr[0]
		var v2z = next[1]-curr[1]
		var len2 = sqrt(v2x*v2x+v2z*v2z)
		if len2==0: len2 = 1
		v2x /= len2; v2z /= len2
		var n1x = -v1z
		var n1z = v1x
		var n2x = -v2z
		var n2z = v2x
		var bx = n1x+n2x
		var bz = n1z+n2z
		var length = sqrt(bx*bx+bz*bz)
		if length<0.0001: result.append([curr[0]+n1x*distance,curr[1]+n1z*distance])
		else:
			bx /= length; bz /= length
			var dot = bx*n1x+bz*n1z
			var d = distance/maxf(0.25,dot)
			result.append([js_round((curr[0]+bx*d)*100)/100,js_round((curr[1]+bz*d)*100)/100])
	return result

static func prism(poly: Array, bottom: float, top: float, key: String) -> MeshInstance3D:
	var ring = ccw(poly)
	var indices = Geometry2D.triangulate_polygon(points2(ring))
	var vertices = []
	for i in range(0,indices.size(),3):
		var a = ring[indices[i]]
		var b = ring[indices[i+1]]
		var c = ring[indices[i+2]]
		vertices.append_array([Vector3(a[0],top,a[1]),Vector3(b[0],top,b[1]),Vector3(c[0],top,c[1])])
		vertices.append_array([Vector3(a[0],bottom,a[1]),Vector3(c[0],bottom,c[1]),Vector3(b[0],bottom,b[1])])
	for i in range(ring.size()):
		var a = ring[i]
		var b = ring[(i+1)%ring.size()]
		quad(vertices,Vector3(a[0],bottom,a[1]),Vector3(b[0],bottom,b[1]),Vector3(b[0],top,b[1]),Vector3(a[0],top,a[1]))
	return surface(vertices,key)
