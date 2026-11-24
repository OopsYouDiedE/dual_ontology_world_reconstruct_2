extends SceneTree

const Layout = preload("res://layout.gd")
const SPEED := 3.0
const RADIUS := 0.32
const HEIGHT := 1.75
var world: Node3D
var walker: CharacterBody3D

func _initialize() -> void:
	call_deferred('_run')

func solid(id: String, center: Vector3, size: Vector3) -> void:
	var body := StaticBody3D.new()
	body.name = id
	body.position = center
	var collider := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = size
	collider.shape = shape
	body.add_child(collider)
	world.add_child(body)

func walk(layout: Dictionary, reverse: bool) -> Dictionary:
	world = Node3D.new()
	root.add_child(world)
	solid('floor', Vector3(0,-0.15,0), Vector3(14,0.3,8.4))
	solid('ceiling', Vector3(0,3.3,0), Vector3(10,0.2,8))
	for side in [-1, 1]:
		solid('side_' + str(side), Vector3(0,1.6,side*4.1), Vector3(10.4,3.2,0.2))
		for jamb in [-1, 1]:
			var width := 4.2 - Layout.DOOR/2
			solid('jamb_%s_%s' % [side,jamb], Vector3(side*5.1,1.6,jamb*(Layout.DOOR/2+width/2)), Vector3(0.2,3.2,width))
		solid('lintel_' + str(side), Vector3(side*5.1,2.65,0), Vector3(0.2,1.1,Layout.DOOR))
	for item in layout.items:
		solid(item.id, Layout.xyz(item.center), Layout.xyz(item.size))
	walker = CharacterBody3D.new()
	walker.floor_max_angle = deg_to_rad(60)
	walker.floor_constant_speed = true
	walker.floor_snap_length = 0.28
	var collider := CollisionShape3D.new()
	var capsule := CapsuleShape3D.new()
	capsule.radius = RADIUS
	capsule.height = HEIGHT
	collider.position.y = HEIGHT/2
	collider.shape = capsule
	walker.add_child(collider)
	var route: Array = layout.route.duplicate()
	if reverse:
		route.reverse()
	walker.position = Layout.xyz(route[0]) + Vector3.UP * 0.03
	world.add_child(walker)
	for i in range(8):
		await physics_frame
		walker.velocity = Vector3.DOWN
		walker.move_and_slide()
	var target := 1
	var frames := 0
	var stalled := 0
	var off_floor := 0
	var contacts := {}
	while target < route.size() and frames < 600 and stalled < 30:
		await physics_frame
		var before := walker.position
		var delta := Layout.xyz(route[target]) - before
		delta.y = 0
		if delta.length() <= 0.012:
			target += 1
			continue
		walker.velocity = delta.limit_length(SPEED/60.0)*60.0 + Vector3.DOWN
		walker.move_and_slide()
		frames += 1
		if not walker.is_on_floor():
			off_floor += 1
		var movement := walker.position - before
		stalled = stalled + 1 if Vector2(movement.x, movement.z).length() < 0.001 else 0
		for i in range(walker.get_slide_collision_count()):
			var hit := walker.get_slide_collision(i)
			var id := str(hit.get_collider().name)
			if id != 'floor':
				contacts[id] = contacts.get(id, 0) + 1
	var end := walker.position
	var status := 'pass' if target == route.size() and contacts.is_empty() and off_floor == 0 else ('blocked' if stalled >= 30 and not contacts.is_empty() else 'fail')
	world.queue_free()
	await process_frame
	return {'direction': 'east_to_west' if reverse else 'west_to_east', 'status': status,
		'frames': frames, 'waypoints_reached': target, 'off_floor_frames': off_floor,
		'contacts': contacts, 'end': [end.x, end.y, end.z]}

func _run() -> void:
	var input: Dictionary = JSON.parse_string(FileAccess.get_file_as_string('res://requests.json'))
	if input.get('sweep', false):
		await _sweep(input.physics)
		return
	var report := {'schema': 'clutter-report/v1', 'godot': Engine.get_version_info().string,
		'capsule': {'radius': RADIUS, 'height': HEIGHT}, 'rooms': [], 'controls': []}
	var ok := true
	for request in input.rooms:
		var seed := int(request.seed)
		var density := float(request.density)
		var max_layers := int(request.max_layers)
		var layout := Layout.generate(seed, request.room_id, density, max_layers)
		var errors := Layout.validate(layout)
		var passes := []
		var repeat := Layout.generate(seed, request.room_id, density, max_layers)
		var neighbor := Layout.generate(seed ^ 1, request.room_id, density, max_layers)
		var stable_seed: bool = layout == repeat and (layout.items != neighbor.items or layout.route != neighbor.route)
		var deepest := 0
		for item in layout.items:
			deepest = maxi(deepest, item.layer)
		var status := 'pass' if errors.is_empty() and stable_seed and (deepest == 0 if layout.items.is_empty() else deepest == max_layers) else 'fail'
		if input.physics and errors.is_empty():
			for reverse in [false, true]:
				var result := await walk(layout, reverse)
				passes.append(result)
				if result.status != 'pass':
					status = 'fail'
		ok = ok and status == 'pass'
		report.rooms.append({'room_id': request.room_id, 'seed': seed,
			'layout': layout, 'layout_errors': errors, 'seed_check': stable_seed, 'max_layer': deepest,
			'status': status if input.physics or status == 'fail' else 'layout_only', 'traversals': passes})
	if input.controls:
		var base := Layout.generate(31)
		for kind in ['floating', 'overhang', 'overlap', 'shifted_load', 'door_block', 'head_block']:
			var layout := base.duplicate(true)
			var prefix := ''
			var blocker := ''
			match kind:
				'floating':
					layout.items[2].center[1] += 0.12
					prefix = 'stack_contact:' + layout.items[2].id
				'overhang':
					layout.items[2].center[0] += 0.48
					prefix = 'unstable:' + layout.items[2].id
				'overlap':
					var clone: Dictionary = layout.items[0].duplicate(true)
					clone.id = 'overlap_probe'
					layout.items.append(clone)
					prefix = 'overlap:overlap_probe:'
				'shifted_load':
					layout.items = [Layout.box('base', Vector3(0,0.25,-3), Vector3(0.5,0.5,0.6), '', 1),
						Layout.box('middle', Vector3(0.15,0.75,-3), Vector3(0.7,0.5,0.6), 'base', 2),
						Layout.box('payload', Vector3(0.37,1.55,-3), Vector3(0.25,1.1,0.6), 'middle', 3)]
					prefix = 'unstable:middle'
				'door_block':
					blocker = kind
					layout.items.append(Layout.box(kind, Vector3(-4.72,0.55,0), Vector3(0.46,1.1,1.4), '', 1))
					prefix = 'route:' + kind
				'head_block':
					blocker = kind
					layout.items.append(Layout.box(kind, Vector3(-4,1.68,0), Vector3(0.5,0.32,1.4), '', 1))
					prefix = 'route:' + kind
			var errors := Layout.validate(layout)
			var caught := false
			for error in errors:
				caught = caught or error.begins_with(prefix)
			var traversal := {}
			if not blocker.is_empty():
				traversal = await walk(layout, false)
				caught = caught and traversal.status == 'blocked' and traversal.contacts.has(blocker)
			report.controls.append({'case': kind, 'caught': caught, 'layout_errors': errors, 'traversal': traversal})
			ok = ok and caught
	report['ok'] = ok
	print('clutter: rooms=%s controls=%s ok=%s' % [report.rooms.size(), report.controls.size(), ok])
	_finish(report)

func _sweep(physics: bool) -> void:
	var report := {'schema': 'clutter-sweep/v1', 'godot': Engine.get_version_info().string,
		'room_id': 'sweep/room', 'seed_range_inclusive': [0, 999], 'strata': [], 'failures': [],
		'geometry_cases': 0, 'capsule_rooms': 0, 'capsule_traversals': 0}
	for density in [0.0, 0.25, 0.5, 0.75, 1.0]:
		for cap in [1, 2, 3, 5]:
			var stratum := {'density': density, 'max_layers': cap, 'cases': 0, 'passed': 0,
				'empty': 0, 'total_boxes': 0, 'capsule_samples': []}
			for seed in range(1000):
				var layout := Layout.generate(seed, report.room_id, density, cap)
				var errors := Layout.validate(layout)
				var deepest := 0
				for item in layout.items:
					deepest = maxi(deepest, item.layer)
				if deepest != (0 if layout.items.is_empty() else cap):
					errors.append('unexpected_depth')
				if density == 1.0 and layout.items.is_empty():
					errors.append('unexpected_empty')
				stratum.cases += 1
				report.geometry_cases += 1
				stratum.total_boxes += layout.items.size()
				if layout.items.is_empty():
					stratum.empty += 1
				if errors.is_empty():
					stratum.passed += 1
				else:
					report.failures.append({'seed': seed, 'density': density, 'max_layers': cap, 'errors': errors})
				if physics and seed in [0, 499, 999]:
					report.capsule_rooms += 1
					var traversals := []
					for reverse in [false, true]:
						var result := await walk(layout, reverse)
						report.capsule_traversals += 1
						traversals.append(result)
						if result.status != 'pass':
							report.failures.append({'seed': seed, 'density': density, 'max_layers': cap, 'traversal': result})
					stratum.capsule_samples.append({'seed': seed, 'traversals': traversals})
			report.strata.append(stratum)
	report['ok'] = report.failures.is_empty()
	print('clutter sweep: geometry=%s walks=%s failures=%s' % [report.geometry_cases, report.capsule_traversals, report.failures.size()])
	_finish(report)

func _finish(report: Dictionary) -> void:
	var output := FileAccess.open('res://report.json', FileAccess.WRITE)
	output.store_string(JSON.stringify(report, '  '))
	output.close()
	quit(0 if report.ok else 1)
