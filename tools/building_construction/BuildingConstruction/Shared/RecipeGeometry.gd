@tool
extends RefCounted

# Native replacement for kit/core.py's Blender boundary.
# Records retain source-local Z-up transforms until finish() creates Godot nodes.
static func gen_group(label, location = [0, 0, 0], rotation = 0, parent = null):
	var record = {"name": label, "location": location, "rotation_euler": [0, 0, rotation], "scale": [1, 1, 1], "children": [], "type": "EMPTY", "casts_shadow": true}
	if parent != null: parent.children.append(record)
	return record

static func gen_mesh(label, vertices, faces, mat, parent = null, bevel = 0):
	var record = gen_group(label, [0, 0, 0], 0, parent)
	var polygons = []
	for face in faces: polygons.append({"indices": Array(face), "material_index": 0, "normal": Vector3.ZERO})
	record.type = "MESH"
	record.data = {"vertices": vertices, "polygons": polygons, "materials": [mat]}
	record.bevel = bevel
	return record

static func gen_box(label, location, size, mat, bevel = 0.015, parent = null):
	var x = maxf(0.000001, float(size[0])) / 2
	var y = maxf(0.000001, float(size[1])) / 2
	var z = maxf(0.000001, float(size[2])) / 2
	var result = gen_mesh(label, [[-x,-y,-z],[x,-y,-z],[x,y,-z],[-x,y,-z],[-x,-y,z],[x,-y,z],[x,y,z],[-x,y,z]], [[3,2,1,0],[0,1,5,4],[1,2,6,5],[2,3,7,6],[3,0,4,7],[4,5,6,7]], mat, parent, minf(bevel, minf(x, minf(y, z)) * 0.45))
	result.location = location
	return result

static func gen_cylinder(label, location, radius, depth, mat, vertices = 8, parent = null):
	var points = []
	for i in range(maxi(3, int(vertices))): points.append([radius * cos(TAU * i / vertices), radius * sin(TAU * i / vertices)])
	var result = gen_polyprism(label, points, -depth/2.0, depth/2.0, mat, parent)
	result.location = location
	return result

static func gen_polyprism(label, points, bottom, top, mat, parent = null):
	var n = points.size()
	if n < 3 or top <= bottom:
		push_error("polyprism requires >=3 vertices and positive height")
		return null
	var vertices = []
	var faces = []
	for height in [bottom, top]:
		for p in points: vertices.append([p[0], p[1], height])
	var cap = Array(range(n))
	cap.reverse()
	faces.append(cap)
	faces.append(Array(range(n, 2*n)))
	for i in range(n): faces.append([i, (i+1)%n, (i+1)%n+n, i+n])
	return gen_mesh(label, vertices, faces, mat, parent)

static func gen_lathe(label, profile, sides, mat, parent = null, location = [0,0,0]):
	sides = maxi(3, int(sides))
	var vertices = []
	var rings = []
	for level in profile:
		if abs(level[0]) < 0.00000001:
			rings.append([vertices.size()])
			vertices.append([0, 0, level[1]])
		else:
			rings.append(Array(range(vertices.size(), vertices.size()+sides)))
			for i in range(sides):
				var angle = TAU*i/sides+PI/8
				vertices.append([level[0]*cos(angle), level[0]*sin(angle), level[1]])
	var faces = []
	for index in range(rings.size()-1):
		var a = rings[index]
		var b = rings[index+1]
		for j in range(sides):
			var k = (j+1)%sides
			if a.size()==1 and b.size()==1: continue
			elif a.size()==1: faces.append([a[0],b[k],b[j]])
			elif b.size()==1: faces.append([a[j],a[k],b[0]])
			else: faces.append([a[j],a[k],b[k],b[j]])
	if rings[0].size()>1:
		var cap = rings[0].duplicate()
		cap.reverse()
		faces.append(cap)
	if rings[-1].size()>1: faces.append(rings[-1])
	var result = gen_mesh(label, vertices, faces, mat, parent)
	result.location = location
	return result

static func gen_ico(label, location, radius, mat, subdivisions = 1, parent = null):
	var t = (1.0+sqrt(5.0))/2.0
	var vertices = [Vector3(-1,t,0),Vector3(1,t,0),Vector3(-1,-t,0),Vector3(1,-t,0),Vector3(0,-1,t),Vector3(0,1,t),Vector3(0,-1,-t),Vector3(0,1,-t),Vector3(t,0,-1),Vector3(t,0,1),Vector3(-t,0,-1),Vector3(-t,0,1)]
	var faces = [[0,11,5],[0,5,1],[0,1,7],[0,7,10],[0,10,11],[1,5,9],[5,11,4],[11,10,2],[10,7,6],[7,1,8],[3,9,4],[3,4,2],[3,2,6],[3,6,8],[3,8,9],[4,9,5],[2,4,11],[6,2,10],[8,6,7],[9,8,1]]
	for i in range(vertices.size()): vertices[i] = vertices[i].normalized()*radius
	for _level in range(maxi(0, subdivisions-1)):
		var cache = {}
		var refined = []
		for f in faces:
			var mid = []
			for edge in [[f[0],f[1]],[f[1],f[2]],[f[2],f[0]]]:
				var key = Vector2i(mini(edge[0],edge[1]),maxi(edge[0],edge[1]))
				if not cache.has(key):
					cache[key] = vertices.size()
					vertices.append((vertices[edge[0]]+vertices[edge[1]]).normalized()*radius)
				mid.append(cache[key])
			refined.append_array([[f[0],mid[0],mid[2]],[f[1],mid[1],mid[0]],[f[2],mid[2],mid[1]],[mid[0],mid[1],mid[2]]])
		faces = refined
	var result = gen_mesh(label, vertices, faces, mat, parent)
	result.location = location
	return result

static func gen_beam(label, a, b, width, depth, mat, parent = null, bevel = 0.008):
	var av = vec(a)
	var bv = vec(b)
	var delta = bv-av
	if delta.length()<0.0000001:
		push_error("beam endpoints must differ: "+str(label))
		return null
	var result = gen_box(label, (av+bv)*0.5, [width,depth,delta.length()], mat, bevel, parent)
	result.basis = track_basis(delta)
	return result

static func gen_place(record, location = [0,0,0], rotation = 0):
	record.location = location
	record.rotation_euler[2] = rotation
	return record

static func gen_solid_material(label, color, roughness = 0.62, metallic = 0, emission = 0, glass = false):
	var result = StandardMaterial3D.new()
	result.resource_name = label
	result.albedo_color = Color(color)
	result.roughness = roughness
	result.metallic = metallic
	if emission > 0:
		result.emission_enabled = true
		result.emission = Color(color)
		result.emission_energy_multiplier = emission
	if glass: result.albedo_color.a = 0.35; result.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	return result

static func gen_palette():
	var specs = {"wood":["#6D3C28",0.6,0,0],"wood_dark":["#402319",0.68,0,0],"wood_light":["#915A3D",0.56,0,0],"wall":["#AD8158",0.82,0,0],"stone":["#C9B698",0.82,0,0],"stone_dark":["#82756A",0.76,0,0],"grout":["#958775",0.85,0,0],"gold":["#CAA15A",0.3,0.68,0],"green":["#40563C",0.42,0.05,0],"leaf":["#52613A",0.78,0,0],"cream":["#E7D6AA",0.72,0,0],"emission":["#FFD58B",0.32,0,3],"book_red":["#7A4937",0.72,0,0],"book_blue":["#455961",0.72,0,0],"book_green":["#4C5740",0.72,0,0],"glass":["#8BAAB7",0.35,0,0.12]}
	var result = {}
	for key in specs:
		var s = specs[key]
		result[key] = gen_solid_material("LP_"+key,s[0],s[1],s[2],s[3],key=="glass")
	var tiles = ["#C6B191","#D2BFA1","#CDB79A","#BEAC92","#D3C1A5"]
	for i in range(tiles.size()): result["tile_"+str(i)] = gen_solid_material("LP_tile_"+str(i),tiles[i],0.83)
	return result

static func material_cache_get(_label): return null
static func industrial_palette(mats):
	var result = mats.duplicate()
	var colors = {"iron":["#51483B",0.65,0.25],"iron_dark":["#302A24",0.7,0.15],"copper":["#AA7643",0.4,0.55],"brick_red":["#8B4936",0.6,0.05],"masonry":["#B39A7D",0.86,0],"masonry_light":["#C7AF8D",0.83,0],"masonry_dark":["#8D765E",0.9,0],"sack":["#CEB98D",0.88,0]}
	for key in colors: result[key] = gen_solid_material("LP_Industrial_Warm_"+key,colors[key][0],colors[key][1],colors[key][2])
	return result

static func outdoor_palette(mats):
	var result = mats.duplicate()
	var colors = {"leaf_sun":"#718047","leaf_mid":"#52643B","leaf_dark":"#35472D","soil":"#53432D","water_0":"#315C5A","water_1":"#386B65","water_2":"#477B70","water_3":"#2B5657","rope":"#A88658"}
	for key in colors: result[key] = gen_solid_material("LP_Outdoor_"+key,colors[key],0.42 if key.begins_with("water") else 0.82)
	return result

static func fixture_light(label, parent, location, kind = "POINT", energy = 12.0, color = [1,0.72,0.4], size = 0.1, size_y = null):
	var record = gen_group(label,location,0,parent)
	record.type = "LIGHT"
	record.light = {"kind":kind,"energy":energy,"color":color,"size":size,"size_y":size_y}
	return record

static func descendants(record):
	var result = []
	for child in record.children:
		result.append(child)
		result.append_array(descendants(child))
	return result

static func add_bevel(record, _label = "", _kind = "BEVEL"):
	var modifier = {"width":0.0,"segments":1,"use_clamp_overlap":true}
	record.modifier = modifier
	return modifier

static func vec(a) -> Vector3:
	return Vector3(a[0],a[1],a[2]) if a is Array else a
static func converted(a) -> Vector3:
	var v = vec(a)
	return Vector3(v.x,v.z,-v.y)
static func track_basis(direction) -> Basis:
	var z = direction.normalized()
	var x = Vector3.UP.cross(z).normalized()
	if x.length_squared()<0.000001: x = Vector3.RIGHT
	return Basis(x,z.cross(x),z)

static func finish(record) -> Node3D:
	if record == null: return null
	var node = MeshInstance3D.new() if record.type=="MESH" else OmniLight3D.new() if record.type=="LIGHT" else Node3D.new()
	node.name = str(record.name).validate_node_name()
	if node is MeshInstance3D:
		node.mesh = make_mesh(record)
		if not record.get("casts_shadow",true): node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		if record.data.materials.any(func(m): return m is StandardMaterial3D and m.transparency != BaseMaterial3D.TRANSPARENCY_DISABLED): node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	elif node is OmniLight3D:
		var settings = record.light
		node.light_color = Color(settings.color[0],settings.color[1],settings.color[2])
		node.light_energy = maxf(0,settings.energy)/12.0
		node.omni_range = 6.0
		node.light_size = settings.size
	var r = vec(record.rotation_euler)
	var b = record.get("basis",Basis(Vector3.FORWARD,-r.z)*Basis(Vector3.UP,r.y)*Basis(Vector3.RIGHT,r.x))
	var conversion = Basis(Vector3.RIGHT,-PI/2)
	node.transform = Transform3D(conversion*b*conversion.inverse(),converted(record.location))
	node.scale = converted(record.scale).abs()
	for key in record:
		if key not in ["children","data","location","rotation_euler","scale","basis","modifier","light"]: node.set_meta(key,record[key])
	for child in record.children: node.add_child(finish(child),true)
	return node

static func make_mesh(record) -> ArrayMesh:
	var data = record.data
	var vertices = PackedVector3Array()
	for point in data.vertices: vertices.append(converted(point))
	var result = ArrayMesh.new()
	for mat_index in range(data.materials.size()):
		var surface = SurfaceTool.new()
		surface.begin(Mesh.PRIMITIVE_TRIANGLES)
		var count = 0
		for polygon in data.polygons:
			if polygon.material_index != mat_index: continue
			var face = polygon.indices
			if face.size()<3: continue
			var normal = Vector3.ZERO
			for i in range(face.size()): normal += vertices[face[i]].cross(vertices[face[(i+1)%face.size()]])
			if normal.length_squared()<0.000000000001: continue
			normal = normal.normalized()
			var axis = normal.abs().max_axis_index()
			var contour = PackedVector2Array()
			for index in face:
				var p = vertices[index]
				contour.append(Vector2(p[(axis+1)%3],p[(axis+2)%3]))
			var triangles = Geometry2D.triangulate_polygon(contour)
			for i in range(0,triangles.size(),3):
				var a = vertices[face[triangles[i]]]
				var b = vertices[face[triangles[i+1]]]
				var c = vertices[face[triangles[i+2]]]
				if (b-a).cross(c-a).dot(normal)>0:
					var swap = b; b = c; c = swap
				for p in [a,b,c]: surface.set_normal(normal); surface.add_vertex(p); count += 1
		if count>0:
			surface.set_material(data.materials[mat_index])
			surface.commit(result)
	return result

class Batch:
	var verts = []
	var faces = []
	func prism(poly,z0,z1):
		var n = poly.size()
		if n<3: return
		var k = verts.size()
		for z in [z0,z1]:
			for p in poly: verts.append([p[0],p[1],z])
		var cap = Array(range(k,k+n)); cap.reverse(); faces.append(cap)
		faces.append(Array(range(k+n,k+2*n)))
		for i in range(n): faces.append([k+i,k+(i+1)%n,k+(i+1)%n+n,k+i+n])
	func finish(label,mat,parent,bevel=0):
		return load("res://tools/building_construction/BuildingConstruction/Shared/RecipeGeometry.gd").gen_mesh(label,verts,faces,mat,parent,bevel) if not verts.is_empty() else null

