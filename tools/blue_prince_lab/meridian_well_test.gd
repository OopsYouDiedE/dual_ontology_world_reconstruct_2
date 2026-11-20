extends SceneTree
## Verify the seeded-room renderer installs the escapement below walkable glass.
const NativeView = preload("res://scenes/rogue_view/RogueRoomView.tscn")
const Well = preload("res://scenes/rogue_view/render/MeridianWell.gd")
var errors := 0

func _initialize() -> void: call_deferred("run")

func check(value: bool, reason: String) -> void:
	if not value:
		errors += 1
		push_error(reason)

func run() -> void:
	var room := NativeView.instantiate()
	room.expedition_view = true
	root.add_child(room)
	for template: String in ["living_hall", "lecture", "valve_gallery"]:
		var path := "res://content/academy_lots/" + template + ".xml"
		var label := "Public Hall" if template == "living_hall" else "Observatory"
		check(room.set_blueprint_room(label, [], path) == OK, path)
		var area := Well.plan(room._lot)
		check(area.has_area(), template + ": no aperture")
		var mounted := room.get_node_or_null("RoomViewport/Geometry/FloorMeridian") as Node3D
		check(mounted != null, template + ": missing watch")
		if mounted:
			var watch = mounted.get_child(0)
			var before: float = watch.elapsed
			await process_frame
			await process_frame
			await physics_frame
			await physics_frame
			check(watch.running and watch.elapsed > before and watch.position.y < 0, "watch pose")
			# A known interval checks the three gear ratios, balance frequency and both hands.
			var angles: Vector3 = watch.angles
			var phase: float = watch.beat
			var hands := Vector2(watch.minute.rotation.z, watch.hour.rotation.z)
			var dt := 1./6. # one release, whatever the initial bank phase
			watch._process(dt)
			check((watch.angles-angles).is_equal_approx(Vector3(TAU/1800.,-TAU/360.,TAU/40.)*dt), "cage ratios")
			check(is_equal_approx(watch.oscillator.rotation.z, 2.7*sin(phase+TAU*3.*dt)), "balance rate")
			var change := Vector2(watch.minute.rotation.z, watch.hour.rotation.z)-hands
			check(change.is_equal_approx(Vector2(-TAU/3600.,-TAU/43200.)*dt), "dial ratios")
			var p := mounted.global_position + Vector3(.04, .0, .04)
			var hit := mounted.get_world_3d().direct_space_state.intersect_ray(PhysicsRayQueryParameters3D.create(p+Vector3.UP*.16,p+Vector3.DOWN*.25))
			check(not hit.is_empty() and absf(hit.position.y)<.01, "missing walkable cover")
		print(template, " -> ", area)
		room.set_blueprint_room("Side Room", [], path)
		check(not room.has_node("RoomViewport/Geometry/FloorMeridian"), "installation leaked into ordinary room")
	room.queue_free()
	await process_frame
	quit(1 if errors else 0)
