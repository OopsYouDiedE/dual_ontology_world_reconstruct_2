extends RefCounted
## Geometry/lighting fingerprint of a built Public Hall, used to prove that the editable
## component scene reproduces the original procedural hall (tools/test/hall_parity_test.gd).
## Every MeshInstance3D, CollisionShape3D and Light3D under the given roots becomes one
## entry: kind, world AABB / position, material colour, light range/energy/colour/direction.

static func material_tag(mat: Material) -> String:
	if mat is ShaderMaterial:
		var sm := mat as ShaderMaterial
		var shader := sm.shader.resource_path.get_file() if sm.shader else "-"
		var pigment = sm.get_shader_parameter("pigment")
		return "%s:%s" % [shader, (pigment as Color).to_html(false) if pigment is Color else "-"]
	if mat is StandardMaterial3D:
		return "std:" + (mat as StandardMaterial3D).albedo_color.to_html(false)
	return "-" if mat == null else mat.get_class()

static func collect(roots: Array) -> Array:
	var out: Array = []
	for root: Node in roots:
		var nodes: Array = [root]
		nodes.append_array(root.find_children("*", "", true, false))
		for n in nodes:
			if not (n is Node3D) or not (n as Node3D).is_visible_in_tree() and not (n is CollisionShape3D):
				continue
			if n is MeshInstance3D and (n as MeshInstance3D).mesh != null:
				var mi := n as MeshInstance3D
				var box: AABB = mi.global_transform * mi.get_aabb()
				var mat := mi.material_override if mi.material_override else mi.get_active_material(0)
				out.append({"kind": "mesh", "v": [box.position.x, box.position.y, box.position.z, box.end.x, box.end.y, box.end.z], "tag": material_tag(mat)})
			elif n is CollisionShape3D and (n as CollisionShape3D).shape != null:
				var cs := n as CollisionShape3D
				var p := cs.global_position
				var size := Vector3.ZERO
				if cs.shape is BoxShape3D:
					size = (cs.shape as BoxShape3D).size
				out.append({"kind": "shape", "v": [p.x, p.y, p.z, size.x, size.y, size.z], "tag": cs.shape.get_class()})
			elif n is Light3D:
				var l := n as Light3D
				var p := l.global_position
				var dir := -l.global_transform.basis.z
				var reach := 0.0
				if l is OmniLight3D: reach = (l as OmniLight3D).omni_range
				elif l is SpotLight3D: reach = (l as SpotLight3D).spot_range
				out.append({"kind": l.get_class(), "v": [p.x, p.y, p.z, dir.x, dir.y, dir.z, reach, l.light_energy if l.visible else 0.0], "tag": l.light_color.to_html(false)})
	return out

static func to_json(entries: Array, extra: Dictionary) -> String:
	var rounded: Array = []
	for e: Dictionary in entries:
		rounded.append({"kind": e.kind, "tag": e.tag, "v": e.v.map(func(x): return snappedf(float(x), 0.0001))})
	return JSON.stringify({"entries": rounded, "extra": extra}, "", false)

## Greedy tolerance match. Returns {missing: [...], extra: [...]} (entries only in a / only in b).
static func diff(a: Array, b: Array, tol := 0.003) -> Dictionary:
	var buckets := {}
	for i in b.size():
		var key := _key(b[i])
		if not buckets.has(key):
			buckets[key] = []
		buckets[key].append(i)
	var used := {}
	var missing: Array = []
	for e: Dictionary in a:
		var found := -1
		for key in _near_keys(e):
			for i in buckets.get(key, []):
				if used.has(i):
					continue
				if _same(e, b[i], tol):
					found = i
					break
			if found >= 0:
				break
		if found >= 0:
			used[found] = true
		else:
			missing.append(e)
	var extra: Array = []
	for i in b.size():
		if not used.has(i):
			extra.append(b[i])
	return {"missing": missing, "extra": extra}

static func _key(e: Dictionary) -> String:
	return "%s|%d|%d|%d" % [e.kind, roundi(float(e.v[0]) * 4.0), roundi(float(e.v[1]) * 4.0), roundi(float(e.v[2]) * 4.0)]

static func _near_keys(e: Dictionary) -> Array:
	var keys: Array = []
	var bx := float(e.v[0]) * 4.0
	var by := float(e.v[1]) * 4.0
	var bz := float(e.v[2]) * 4.0
	for x in [floori(bx), ceili(bx)]:
		for y in [floori(by), ceili(by)]:
			for z in [floori(bz), ceili(bz)]:
				var k := "%s|%d|%d|%d" % [e.kind, x, y, z]
				if not k in keys:
					keys.append(k)
	return keys

static func _same(a: Dictionary, b: Dictionary, tol: float) -> bool:
	if a.kind != b.kind or a.tag != b.tag or a.v.size() != b.v.size():
		return false
	for i in a.v.size():
		var t := tol if i < 6 else maxf(tol, absf(float(a.v[i])) * 0.001)
		if absf(float(a.v[i]) - float(b.v[i])) > t:
			return false
	return true
