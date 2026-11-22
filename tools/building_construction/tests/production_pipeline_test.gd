extends SceneTree

const Factory = preload("../BuildingConstruction/Shared/ComponentFactory.gd")
const Assembly = preload("../production/assembly/ComponentAssembly.gd")
const LegacyAssembly = preload("../BuildingConstruction/Shared/ComponentAssembly.gd")
const Library = preload("../ComponentLibrary.tscn")
var failed := 0
var entries := {}

func _initialize() -> void:
	run.call_deferred()

func check(ok: bool, message: String) -> void:
	print(("PASS " if ok else "FAIL ") + message)
	if not ok: failed += 1

func mount(id: String, params := {}) -> Node3D:
	var node := Factory.create_entry(entries[id], params)
	Assembly.tag(node, entries[id])
	root.add_child(node)
	return node

func run() -> void:
	var data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://tools/building_construction/catalog.json"))
	var valid := true
	var kinds := {}
	for entry in data.items:
		var kind: String = entry.production.kind
		kinds[kind] = true
		valid = valid and not entries.has(entry.id) and not entry.has("production_route") and not entry.has("frame_route") and not entry.has("visual_source")
		entries[entry.id] = entry
		if entry.get("optional", false) and not ResourceLoader.exists(entry.path): continue
		var definition := load(entry.path) as Script
		var generator := load(entry.production.generator) as Script
		if definition == null or not definition.can_instantiate() or generator == null or not generator.can_instantiate():
			valid = false
			printerr("Invalid catalog entry: " + entry.id)
			continue
		# External scene scripts own their construction side effects.
		if str(entry.path).begins_with("res://tools/building_construction/"):
			var node := Factory.create_entry(entry)
			if "recipe_module" in node:
				if generator == null or not generator.has_method("gen_" + node.recipe_function):
					printerr("Wrong generator: " + entry.id + " → " + entry.production.generator)
					valid = false
			node.free()
	check(valid and kinds.size() == 3 and kinds.has("line") and kinds.has("rule") and kinds.has("assembly"), "catalog resolves all %d entries across line, rule and assembly" % data.items.size())

	var library := Library.instantiate()
	root.add_child(library)
	check(not library.entries.is_empty(), "Component Library displays the live catalog")
	library.free()

	var defaults := Factory.parameter_defaults(entries.RecipeChair)
	check(defaults.get("width") == 0.52 and defaults.has("arms"), "authoring inspector reads native recipe defaults")

	var chair := mount("RecipeChair", {"width": 0.84})
	var default_chair := Factory.create_entry(entries.RecipeChair)
	check(chair.width == 0.84 and default_chair.width == 0.52, "overrides are instance-local")
	default_chair.free()
	check(chair.get_node_or_null("Generated") != null and not chair.find_children("*", "CollisionShape3D", true, false).is_empty(), "assembly recipe generates visible and collision geometry")
	var wide := Assembly.bounds(chair).size.x
	chair.set("width", 0.65)
	await process_frame
	check(Assembly.bounds(chair).size.x < wide, "parameter edit rebuilds real geometry")
	chair.free()

	var legacy := Factory.create(entries.RecipeChair.path)
	root.add_child(legacy)
	check(legacy.get_node_or_null("Generated") != null, "legacy serialized recipe-module path still generates")
	legacy.free()

	var floor_part := mount("RecipeTiledFloor", {"width": 3.0, "depth": 2.0})
	check(absf(Assembly.bounds(floor_part).size.x - 3.0) < 0.1, "rule recipe uses floor dimensions")
	floor_part.free()

	var path_wall := mount("RecipeWallPath", {"points": [[0, 0, 0], [5, 0, 0]]})
	check(Assembly.bounds(path_wall).size.x >= 5.0, "line recipe builds from supplied path points")
	path_wall.free()

	var wall := mount("SmartWall3D", {"end_point": Vector3(5, 0, 0), "skirting_enabled": false})
	wall.register_opening(1.0, 2.0, 0.0, 2.1)
	wall.rebuild()
	check(LegacyAssembly.id(wall) == "SmartWall3D", "legacy assembly path retains its callable API")
	await physics_frame
	await physics_frame
	var space := root.world_3d.direct_space_state
	var hole := space.intersect_ray(PhysicsRayQueryParameters3D.create(Vector3(1.5, 1, -1), Vector3(1.5, 1, 1)))
	var solid := space.intersect_ray(PhysicsRayQueryParameters3D.create(Vector3(3, 1, -1), Vector3(3, 1, 1)))
	check(hole.is_empty() and not solid.is_empty(), "line wall collision leaves the aperture clear and retains the adjacent solid")
	wall.free()
	await check_review_cases()
	await process_frame
	quit(failed)


func dimension_changes(id: String, parameter: String, min_value: float, max_value: float, axis: int) -> void:
	var small := mount(id, {parameter: min_value})
	var large := mount(id, {parameter: max_value})
	check(Assembly.bounds(large).size[axis] > Assembly.bounds(small).size[axis] + 0.02, "%s: %s changes mesh bounds" % [id, parameter])
	small.free()
	large.free()

func check_review_cases() -> void:
	var pipe := mount("RecipePipeRun", {"nodes": [[0, 0, 0], [2, 0, 0]], "radius": 0.08, "collars": false})
	var thin := Assembly.bounds(pipe).size
	pipe.set("radius", 0.16)
	await process_frame
	var thick := Assembly.bounds(pipe).size
	check(absf(thin.y - 0.16) < 0.001 and absf(thick.y - 0.32) < 0.001, "pipe radius changes swept diameter")
	pipe.set("nodes", [[0, 0, 0], [2, 0, 0], [2, 0, 1]])
	await process_frame
	var ports := Assembly.pipe_ports(pipe)
	check(Assembly.bounds(pipe).size.y > thick.y + 0.5 and ports.size() == 4 and ports[2].is_equal_approx(Vector3(2, 1, 0)), "pipe polyline changes swept mesh and matching end port")
	pipe.free()

	dimension_changes("HingedDoor3D", "leaf_width", 0.7, 1.3, Vector3.AXIS_X)
	dimension_changes("HingedWindow3D", "sash_height", 0.7, 1.3, Vector3.AXIS_Y)
	dimension_changes("RecipeClosedDoor", "width", 0.8, 1.4, Vector3.AXIS_X)
	dimension_changes("RecipeArchedClosedDoor", "width", 0.9, 1.5, Vector3.AXIS_X)
	dimension_changes("RecipeCourtyardGate", "width", 1.9, 2.5, Vector3.AXIS_X)
	dimension_changes("RecipeWallLantern", "height", 0.50, 0.80, Vector3.AXIS_Y)
	dimension_changes("RecipeBankerLamp", "width", 0.35, 0.60, Vector3.AXIS_X)
	dimension_changes("RecipePendantLamp", "drop", 0.5, 1.2, Vector3.AXIS_Y)
	dimension_changes("RecipeCagedLamp", "height", 0.4, 0.7, Vector3.AXIS_Y)
	dimension_changes("RecipeLampPost", "height", 2.2, 3.2, Vector3.AXIS_Y)
	dimension_changes("HallLamp", "hang_length", 0.7, 1.4, Vector3.AXIS_Y)
	dimension_changes("RecipeBeam", "length", 1.8, 3.1, Vector3.AXIS_X)
	dimension_changes("RecipeColumn", "height", 2.1, 3.1, Vector3.AXIS_Y)
	dimension_changes("RecipeColumn", "radius", 0.15, 0.30, Vector3.AXIS_X)
	dimension_changes("RecipeArmillary", "radius", 0.75, 1.30, Vector3.AXIS_X)

	var gear := mount("HallGears")
	var rim: MeshInstance3D = gear.get_node("Mechanism/Driver/Beveled involute rim")
	var before := rim.mesh.get_aabb().size.x
	gear.set("driver_teeth", 34)
	await process_frame
	rim = gear.get_node("Mechanism/Driver/Beveled involute rim")
	var driver: Node3D = gear.get_node("Mechanism/Driver")
	var follower: Node3D = gear.get_node("Mechanism/Follower")
	check(rim.mesh.get_aabb().size.x > before + 0.10 and is_equal_approx(driver.position.distance_to(follower.position), 0.98), "gear teeth change involute mesh and pitch center distance")
	gear.set("driver_rad_per_second", 0.65)
	gear.interact()
	gear._physics_process(0.5)
	check(is_equal_approx(gear.follower_angle, gear._phase() - 0.325 * 34.0 / 22.0 + gear._lash()), "gear animation uses the reconfigured ratio")
	gear.free()

	var simple_door := mount("HallDoor", {"hall_finish": false})
	var carved_door := mount("HallDoor", {"hall_finish": true})
	check(simple_door.find_children("*", "MeshInstance3D", true, false).size() != carved_door.find_children("*", "MeshInstance3D", true, false).size(), "external hall door finish changes leaf geometry")
	simple_door.free()
	carved_door.free()
