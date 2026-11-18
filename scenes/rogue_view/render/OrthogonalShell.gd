extends RefCounted
## Exact (millimetre grid) solid union for the orthogonal kitchen shell.
## Rectangular prisms are [minimum tick, maximum tick, surface material index].
const SCALE := 1000.0
const DIRECTIONS := [Vector3i.RIGHT, Vector3i.LEFT, Vector3i.UP, Vector3i.DOWN, Vector3i.BACK, Vector3i.FORWARD]

static func prism(low: Vector3, high: Vector3, material: int) -> Array:
	return [Vector3i((low * SCALE).round()), Vector3i((high * SCALE).round()), material]

static func compile(prisms: Array) -> Dictionary:
	var axes := [{}, {}, {}]
	for solid in prisms:
		for axis in 3:
			axes[axis][solid[0][axis]] = true
			axes[axis][solid[1][axis]] = true
	var ticks := []
	var indices := [{}, {}, {}]
	for axis in 3:
		var values: Array = axes[axis].keys()
		values.sort()
		ticks.append(values)
		for i in values.size(): indices[axis][values[i]] = i
	var occupied := {}
	for solid in prisms:
		var lo: Vector3i = solid[0]
		var hi: Vector3i = solid[1]
		for x in range(indices[0][lo.x], indices[0][hi.x]):
			for y in range(indices[1][lo.y], indices[1][hi.y]):
				for z in range(indices[2][lo.z], indices[2][hi.z]):
					occupied[Vector3i(x,y,z)] = solid[2]
	var faces := []
	for cell: Vector3i in occupied:
		for direction: Vector3i in DIRECTIONS:
			if occupied.has(cell + direction): continue
			var axis := 0 if direction.x else (1 if direction.y else 2)
			var u := (axis+1)%3
			var v := (axis+2)%3
			var p := Vector3i(ticks[0][cell.x],ticks[1][cell.y],ticks[2][cell.z])
			if direction[axis] > 0: p[axis] = ticks[axis][cell[axis]+1]
			var q := p
			var r := p
			q[u] = ticks[u][cell[u]+1]
			r[v] = ticks[v][cell[v]+1]
			var s := q
			s[v] = r[v]
			# Godot front faces are clockwise when seen from outside the solid.
			var corners := [p,r,s,q] if direction[axis] > 0 else [p,q,s,r]
			faces.append({"corners":corners,"normal":direction,"material":occupied[cell]})
	return {"faces":faces,"ticks":ticks,"occupied":occupied}

static func mesh_of(faces: Array, materials: Array[Material]) -> ArrayMesh:
	var mesh := ArrayMesh.new()
	for id in materials.size():
		var surface := SurfaceTool.new()
		surface.begin(Mesh.PRIMITIVE_TRIANGLES)
		surface.set_material(materials[id])
		var count := 0
		for face in faces:
			if face.material != id: continue
			for i in [0,1,2,0,2,3]:
				surface.set_normal(Vector3(face.normal))
				surface.add_vertex(Vector3(face.corners[i])/SCALE)
			count += 1
		if count: surface.commit(mesh)
	return mesh
