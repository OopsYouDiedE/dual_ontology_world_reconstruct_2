extends SceneTree

var failed := false

func _initialize() -> void:
	call_deferred("run")

func check(condition: bool, description: String) -> void:
	if not condition:
		failed = true
		push_error(description)

func hit(body: Node3D, x: float, y: float, z: float = 0.0) -> Dictionary:
	var from := body.to_global(Vector3(x, y, z + 2.0))
	var to := body.to_global(Vector3(x, y, z - 1.0))
	return body.get_world_3d().direct_space_state.intersect_ray(PhysicsRayQueryParameters3D.create(from, to))

func frames(count: int) -> void:
	for i in count:
		await physics_frame

func run() -> void:
	var door := preload("res://scenes/blue_prince_lab/doors/Door.tscn").instantiate()
	var cabinet := preload("res://scenes/blue_prince_lab/doors/Cabinet.tscn").instantiate()
	for item in [door, cabinet]:
		item.swing_seconds = 0.20
		root.add_child(item)
	cabinet.position.x = 4.0
	var leaf := door.get_node("RoomLeaf") as AnimatableBody3D
	var left := cabinet.get_node("LeftLeaf") as AnimatableBody3D
	var right := cabinet.get_node("RightLeaf") as AnimatableBody3D
	await frames(3)
	check(hit(door, 0.0, 1.2).get("collider") == leaf, "Closed doorway must hit moving leaf")
	check(hit(cabinet, -0.2, 0.85).get("collider") == left, "Closed cabinet must hit left leaf")
	check(hit(cabinet, 0.2, 0.85).get("collider") == right, "Closed cabinet must hit right leaf")
	door.interact()
	cabinet.interact()
	await frames(6)
	check(leaf.rotation.y < -0.05 and leaf.rotation.y > -1.5, "Hinge should animate through an intermediate angle")
	door.interact()
	await frames(16)
	check(is_zero_approx(leaf.rotation.y), "Second interaction should reverse the moving leaf")
	door.interact()
	await frames(16)
	check(is_equal_approx(leaf.rotation.y, -PI / 2), "Door should settle at 90 degrees")
	check(hit(door, 0.0, 1.2).is_empty(), "Opened doorway should clear the center ray")
	check(hit(door, -0.70, 1.2).get("collider") == leaf, "Door collider must follow the swing")
	check(left.rotation.y < -PI / 2 and right.rotation.y > PI / 2, "Cabinet leaves should swing outward symmetrically")
	check(hit(cabinet, 0.2, 0.85).get("collider") == cabinet.get_node("Carcass"), "Opened cabinet should expose its back board")
	cabinet.set_open(false, true)
	await frames(3)
	check(hit(cabinet, 0.2, 0.85).get("collider") == right, "Immediate close should restore leaf collision")
	if not failed:
		print("Door/cabinet hinge and collision tests passed")
	quit(int(failed))
