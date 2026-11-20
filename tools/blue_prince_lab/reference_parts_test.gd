extends SceneTree
## Exercise actual catalog paths and physics geometry, not a display-only duplicate.
const FACTORY := preload("res://tools/building_construction/BuildingConstruction/Shared/ComponentFactory.gd")
var parts := {}
var failed := false

func _initialize() -> void: call_deferred("run")

func check(ok: bool, message: String) -> void:
	if not ok:
		failed = true
		push_error(message)

func blocked(part: Node3D, p: Vector2) -> bool:
	var a := part.to_global(Vector3(p.x,p.y,2))
	var b := part.to_global(Vector3(p.x,p.y,-2))
	return not part.get_world_3d().direct_space_state.intersect_ray(PhysicsRayQueryParameters3D.create(a,b)).is_empty()

func run() -> void:
	var catalog: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://tools/building_construction/catalog.json"))
	for item in catalog.items:
		if not str(item.id).begins_with("RecipeReference"): continue
		var part := FACTORY.create(item.path)
		check(part != null, "Cannot place " + str(item.id))
		if not part: continue
		part.position.x = parts.size()*12.0
		root.add_child(part)
		parts[item.id] = part
		check(not part.find_children("*", "MeshInstance3D", true, false).is_empty(), "Missing geometry: " + str(item.id))
		check(not part.find_children("*", "CollisionShape3D", true, false).is_empty(), "Missing collision: " + str(item.id))
	for i in 3: await physics_frame
	check(parts.size() == 7, "Expected seven reusable modules")
	if parts.has("RecipeReferenceMoonGate"):
		var gate: Node3D = parts.RecipeReferenceMoonGate
		check(not blocked(gate,Vector2(0,2.23)) and blocked(gate,Vector2(1.23,2.23)),"Moon gate: ring must be open between solid posts")
	if parts.has("RecipeReferenceSpokeWindow"):
		var window: Node3D = parts.RecipeReferenceSpokeWindow
		check(not blocked(window,Vector2(.40,.13)) and blocked(window,Vector2(.4,0)), "Window: daylight must pass between solid spokes")
	if not failed: print("Seven catalog modules instantiated; gate and window aperture rays passed.")
	quit(1 if failed else 0)
