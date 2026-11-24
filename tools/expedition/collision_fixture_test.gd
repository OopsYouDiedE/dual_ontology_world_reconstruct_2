extends SceneTree
const Fixture = preload("res://tools/expedition/collision_fixture.gd")
const Expedition = preload("res://scenes/expedition_01/Expedition.tscn")
const DT := 1.0 / 60.0
var failures := 0

func _initialize() -> void:
	run.call_deferred()

func check(ok: bool, label: String) -> void:
	print("PASS " if ok else "FAIL ", label)
	if not ok: failures += 1

func ticks(count: int) -> void:
	for i in count: await physics_frame

func named(geometry: Dictionary, role: String) -> Array:
	return geometry.shapes.filter(func(row): return row.role == role)

func ray_hits(level, from: Vector3, to: Vector3, target: CollisionObject3D) -> bool:
	var ray := PhysicsRayQueryParameters3D.create(from, to, 1, [level.walker.get_rid()])
	return level.get_world_3d().direct_space_state.intersect_ray(ray).get("collider") == target

func gaze(level, hale: bool) -> void:
	level.eye.look_at(level.archive.PLATE)
	level.archive.gaze = level.archive.PLATE - level.hale.position - Vector3.UP * 1.57 if hale else Vector3.ZERO
	level.rules(DT)

func scenario(light: bool) -> Dictionary:
	var level = Expedition.instantiate()
	root.add_child(level)
	# The driver stages identical inputs; production lift, tween, ray and rule code still run.
	level.set_physics_process(false)
	var env: WorldEnvironment = level.find_children("*", "WorldEnvironment", true, false)[0]
	var original := env.environment
	if light:
		var changes := Fixture.apply_lightweight(level)
		check(not changes.is_empty() and original.sdfgi_enabled and original.ssao_enabled and
			not env.environment.sdfgi_enabled and not env.environment.ssao_enabled and
			env.environment.glow_enabled == original.glow_enabled and env.environment.fog_enabled == original.fog_enabled and
			Fixture.apply_lightweight(level).is_empty(), "light disables expensive passes locally and is idempotent")
	await ticks(3)
	var boot := Fixture.capture(level)
	var by_shape := {}
	for shape in boot.shapes: by_shape[shape.shape] = by_shape.get(shape.shape, 0) + 1
	check(boot.errors.is_empty() and by_shape.has("ConcavePolygonShape3D") and by_shape.has("CapsuleShape3D") and
		boot.shapes.any(func(row): return row.body_type == "CSGPolygon3D"),
		"geometry coverage full=%s: %s; errors=%s" % [not light, by_shape, boot.errors])
	check(not named(boot, "player").is_empty() and not named(boot, "gaze_plate").is_empty(), "actor and plate roles exported")
	var lift: AnimatableBody3D = level.kit.maintenance.leaf
	var from := Vector3(23.6, 1.0, -7.4)
	var to := Vector3(24.4, 1.0, -7.4)
	check(ray_hits(level, from, to, lift), "closed lift blocks the actual physics ray")
	level.kit.maintenance.operate("maintenance_lift", level)
	await ticks(55)
	var mid := Fixture.capture(level)
	await ticks(55)
	var opened := Fixture.capture(level)
	var lift_y: Array = named(opened, "maintenance_lift")[0].y_range
	var mid_y: Array = named(mid, "maintenance_lift")[0].y_range
	check(level.kit.maintenance.opened and mid_y[0] > 0.1 and mid_y[0] < 2.3 and absf(lift_y[0] - 2.38) < 0.01 and
		not ray_hits(level, from, to, lift) and ray_hits(level, Vector3(23.86, 3.6, -7.4), Vector3(24.14, 3.6, -7.4), lift),
		"moving lift exports intermediate and open heights: %s %s low-hit=%s high-hit=%s" % [mid_y, lift_y, ray_hits(level, from, to, lift), ray_hits(level, Vector3(23.86, 3.6, -7.4), Vector3(24.14, 3.6, -7.4), lift)])
	level.walker.position = Vector3(26.89, .03, 8.53)
	level.hale.position = level.archive.WINDOW
	gaze(level, false)
	gaze(level, true)
	var active := Fixture.capture(level)
	var plate: StaticBody3D = level.kit.test_board.get_child(0)
	var above := Vector3(23.85, .4, 12.02)
	var below := Vector3(23.85, -.25, 12.02)
	check(level.contracts.a_state == "overlap" and ray_hits(level, above, below, plate), "live dual gaze preserves plate support")
	gaze(level, false)
	await ticks(2)
	var dark := Fixture.capture(level)
	check(level.contracts.a_state == "blackout" and not ray_hits(level, above, below, plate) and
		named(dark, "gaze_plate")[0].layer == 0, "gaze breach removes live collision and updates exported layer")
	for i in 184: gaze(level, false)
	await ticks(2)
	var recovered := Fixture.capture(level)
	check(level.contracts.a_state == "idle" and ray_hits(level, above, below, plate), "plate timer restores live collision")
	var gate: Node3D = level.kit.return_exit_gate
	var barrier: StaticBody3D = gate.find_children("*", "StaticBody3D", true, false)[0]
	var gate_ray_start := Vector3(level.kit.RETURN_WEST, 1, level.kit.RETURN_GATE_Z - .25)
	var gate_ray_end := gate_ray_start + Vector3(0, 0, .5)
	check(ray_hits(level, gate_ray_start, gate_ray_end, barrier), "return gate starts with live collision")
	level.return_started = true
	level.update_return_route(Vector3(level.kit.RETURN_WEST, 0, level.kit.RETURN_GATE_Z + .3))
	await ticks(55)
	var returned := Fixture.capture(level)
	check(level.return_gate_open and is_equal_approx(gate.position.y, 2.74) and
		not ray_hits(level, gate_ray_start, gate_ray_end, barrier) and
		ray_hits(level, gate_ray_start + Vector3.UP * 2.74, gate_ray_end + Vector3.UP * 2.74, barrier) and
		Fixture.fingerprint(named_geometry(recovered, "return_gate")) != Fixture.fingerprint(named_geometry(returned, "return_gate")),
		"return gate tween moves exported collision")
	level.queue_free()
	await process_frame
	await ticks(2)
	return {"boot": boot, "mid_lift": mid, "open_lift": opened, "active_plate": active, "blackout": dark,
		"recovered_plate": recovered, "open_return_gate": returned}

func named_geometry(geometry: Dictionary, role: String) -> Dictionary:
	return {"shapes": named(geometry, role)}

func run() -> void:
	var path := ""
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--geometry="): path = arg.trim_prefix("--geometry=")
		# ArchiveFacts consumes the same user argument in both scene instances.
		elif arg.begins_with("--run-seed=") and arg.trim_prefix("--run-seed=").is_valid_int(): pass
		else:
			printerr("Unknown option: ", arg)
			quit(2)
			return
	var start := Time.get_ticks_msec()
	var full := await scenario(false)
	var light := await scenario(true)
	for stage in full:
		var expected := Fixture.fingerprint(full[stage])
		var actual := Fixture.fingerprint(light[stage])
		check(expected == actual, "%s fingerprint %s%s" % [stage, actual, "" if expected == actual else " expected=" + expected])
		if expected != actual:
			for i in mini(full[stage].shapes.size(), light[stage].shapes.size()):
				var a: Dictionary = full[stage].shapes[i]
				var b: Dictionary = light[stage].shapes[i]
				if JSON.stringify(a, "", true, true) == JSON.stringify(b, "", true, true): continue
				for key in a:
					if a[key] != b.get(key): print("  ", a.id, " ", key, ": ", str(a[key]).left(160), " vs ", str(b.get(key)).left(160))
				break
	if not path.is_empty() and failures == 0:
		check(Fixture.write_json(path, full.boot) == OK, "wrote boot geometry: " + path)
	print("collision fixture: ", failures, " failures; ", Time.get_ticks_msec() - start, " ms")
	quit(0 if failures == 0 else 1)
