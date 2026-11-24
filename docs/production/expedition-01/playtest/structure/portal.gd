extends RefCounted
## Disposable geometry in the real A1 arcade. Coordinates are world meters.
const X := 4.5

static func install(level: Node3D, layout: String) -> void:
	if layout == "A": return
	var portal := Node3D.new()
	portal.name = "StructureTrialPortal"
	level.add_child(portal)
	box(portal, "SouthJamb", Vector3(X, 1.55, -.785), Vector3(.28, 3.10, 2.87))
	box(portal, "NorthJamb", Vector3(X, 1.55, 2.035), Vector3(.28, 3.10, .37))
	box(portal, "Lintel", Vector3(X, 2.65, 1.25), Vector3(.28, .90, 1.20))

static func box(parent: Node3D, label: String, center: Vector3, size: Vector3) -> void:
	var visual := MeshInstance3D.new()
	visual.name = label
	var mesh := BoxMesh.new()
	mesh.size = size
	visual.mesh = mesh
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(.34, .29, .23)
	visual.material_override = material
	parent.add_child(visual)
	visual.global_position = center
	# The existing vision proxy recognizes geometry-owned visible colliders.
	var body := StaticBody3D.new()
	visual.add_child(body)
	var collision := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = size
	collision.shape = shape
	body.add_child(collision)

static func probe(level, vision) -> Dictionary:
	var space: PhysicsDirectSpaceState3D = level.walker.get_world_3d().direct_space_state
	var result := {}
	for lane: Array in [["center", 0.0], ["opening", 1.25]]:
		var z: float = lane[1]
		var query := PhysicsRayQueryParameters3D.create(Vector3(3.8, 1.57, z), Vector3(5.2, 1.57, z), 7, [level.walker.get_rid()])
		var hit := space.intersect_ray(query)
		result[lane[0] + "_clear"] = hit.is_empty()
	var sight: Dictionary = vision.hit(level.eye, space, level.walker.get_rid(), Vector3(5.2, 1.57, 0))
	result["sensor_hits_portal_plane"] = sight.has("point") and absf(sight.point.x - (X - .14)) < .02
	return result
