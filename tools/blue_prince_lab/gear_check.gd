extends SceneTree

const GearScript = preload("res://scenes/blue_prince_lab/gears/Gears.gd")
const GearScene = preload("res://scenes/blue_prince_lab/gears/Gears.tscn")

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var gear = GearScene.instantiate()
	root.add_child(gear)
	gear.set_physics_process(false)
	var a: Node3D = gear.get_node("Mechanism/Driver")
	var b: Node3D = gear.get_node("Mechanism/Follower")
	var pitch: float = TAU / GearScript.DRIVER_TEETH
	var angle_a: float = gear.driver_angle
	var angle_b: float = gear.follower_angle
	var ratio: float = float(GearScript.DRIVER_TEETH) / GearScript.FOLLOWER_TEETH
	var max_overlap := 0.0
	var outline_a := GearScript.tooth_outline(GearScript.DRIVER_TEETH)
	var outline_b := GearScript.tooth_outline(GearScript.FOLLOWER_TEETH)
	for i in range(121):
		var travel := pitch * i / 120.0
		var left := Transform2D(angle_a + travel, Vector2(a.position.x, a.position.y)) * outline_a
		var right := Transform2D(angle_b - travel * ratio, Vector2(b.position.x, b.position.y)) * outline_b
		for region in Geometry2D.intersect_polygons(left, right):
			var area := 0.0
			for j in range(region.size()):
				area += region[j].cross(region[(j + 1) % region.size()])
			max_overlap = maxf(max_overlap, absf(area) * 0.5)
	var mesh: MeshInstance3D = a.get_child(0)
	var bounds := mesh.get_aabb()
	var start_ok: bool = not gear.is_running and gear.interact()
	gear._physics_process(0.35)
	var movement_ok: bool = is_equal_approx(gear.driver_angle - angle_a, 0.35 * gear.driver_rad_per_second) and is_equal_approx(gear.follower_angle - angle_b, -(gear.driver_angle - angle_a) * ratio) and is_equal_approx(b.rotation.z, gear.follower_angle)
	var stop_ok: bool = not gear.interact()
	angle_a = gear.driver_angle
	gear._physics_process(0.5)
	var paused_ok: bool = gear.driver_angle == angle_a
	var geometry_ok: bool = mesh.mesh.get_surface_count() == 2 and is_equal_approx(bounds.size.z, 0.088) and a.position.distance_to(b.position) > 0.9099 and a.position.distance_to(b.position) < 0.9101
	print("Gear check: maximum sampled tooth overlap = %.9f m²; start=%s movement=%s stop=%s pause=%s geometry=%s" % [max_overlap, start_ok, movement_ok, stop_ok, paused_ok, geometry_ok])
	quit(0 if start_ok and movement_ok and stop_ok and paused_ok and geometry_ok and max_overlap < 0.000001 else 1)
