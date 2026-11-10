extends RefCounted
const Geo = preload("../Shared/ArchitectGeometry.gd")

static func build(layer: Dictionary) -> Node3D:
	var root = Node3D.new()
	root.name = str(layer.name)
	var y = float(layer.y)
	for raw in layer.polygons:
		var poly = Geo.ccw(raw)
		root.add_child(Geo.prism(poly,y-0.05,y,"grout"))
		var style = layer.get("style","octagonal_tile")
		var base_key = {"octagonal_tile":"grout","parquet_wood":"wood_dark","stone_slab":"stone_dark"}.get(style,"tile_light")
		root.add_child(Geo.prism(poly,y+0.006,y+0.006,base_key))
		var bounds = Rect2(Vector2(poly[0][0],poly[0][1]),Vector2.ZERO)
		for p in poly: bounds = bounds.expand(Vector2(p[0],p[1]))
		var vertices = []
		var dark = []
		var ring = Geo.points2(poly)
		if style == "octagonal_tile":
			var x = floor(bounds.position.x/0.8)*0.8
			while x<bounds.end.x:
				var z = floor(bounds.position.y/0.8)*0.8
				while z<bounds.end.y:
					var center = Vector2(x+0.4,z+0.4)
					if Geometry2D.is_point_in_polygon(center,ring):
						var oct = [Vector2(-0.24,-0.38),Vector2(0.24,-0.38),Vector2(0.38,-0.24),Vector2(0.38,0.24),Vector2(0.24,0.38),Vector2(-0.24,0.38),Vector2(-0.38,0.24),Vector2(-0.38,-0.24)]
						for k in range(8):
							var a = center+oct[k]
							var b = center+oct[(k+1)%8]
							vertices.append_array([Vector3(center.x,y+0.015,center.y),Vector3(a.x,y+0.015,a.y),Vector3(b.x,y+0.015,b.y)])
						var corner = Vector2(x+0.8,z+0.8)
						if Geometry2D.is_point_in_polygon(corner,ring): _tile(dark,corner.x-0.126,corner.y-0.126,corner.x+0.126,corner.y+0.126,y+0.02)
					z += 0.8
				x += 0.8
			root.add_child(Geo.surface(clip_tiles(vertices,ring),"tile_light"))
			root.add_child(Geo.surface(clip_tiles(dark,ring),"tile_dark"))
		elif style == "parquet_wood":
			var x = floor(bounds.position.x/0.8)*0.8
			while x<bounds.end.x:
				var z = floor(bounds.position.y/0.8)*0.8
				while z<bounds.end.y:
					for k in range(5):
						if Geometry2D.is_point_in_polygon(Vector2(x+0.4,z+k*0.16+0.08),ring): _tile(vertices,x+0.01,z+k*0.16+0.01,x+0.79,z+(k+1)*0.16-0.01,y+0.015)
					z += 0.8
				x += 0.8
			root.add_child(Geo.surface(clip_tiles(vertices,ring),"wood"))
		elif style == "stone_slab":
			var z = floor(bounds.position.y/0.8)*0.8
			var row = 0
			while z<bounds.end.y:
				var shift = 0.0 if row%2==0 else 0.6
				var x = floor(bounds.position.x/1.2)*1.2-shift
				while x<bounds.end.x:
					if Geometry2D.is_point_in_polygon(Vector2(x+0.6,z+0.4),ring): _tile(vertices,x+0.02,z+0.02,x+1.18,z+0.78,y+0.015)
					x += 1.2
				z += 0.8
				row += 1
			root.add_child(Geo.surface(clip_tiles(vertices,ring),"stone"))
	return root

static func _tile(vertices: Array, x0: float, z0: float, x1: float, z1: float, y: float) -> void:
	Geo.quad(vertices,Vector3(x0,y,z0),Vector3(x0,y,z1),Vector3(x1,y,z1),Vector3(x1,y,z0))

static func clip_tiles(vertices: Array, boundary: PackedVector2Array) -> Array:
	var result = []
	for i in range(0,vertices.size(),3):
		var triangle = PackedVector2Array()
		for j in range(3): triangle.append(Vector2(vertices[i+j].x,vertices[i+j].z))
		for polygon in Geometry2D.intersect_polygons(triangle,boundary):
			var indices = Geometry2D.triangulate_polygon(polygon)
			for k in range(0,indices.size(),3):
				var a = polygon[indices[k]]
				var b = polygon[indices[k+1]]
				var c = polygon[indices[k+2]]
				if (b-a).cross(c-a)<0:
					var swap = b; b = c; c = swap
				for p in [a,b,c]: result.append(Vector3(p.x,vertices[i].y,p.y))
	return result
