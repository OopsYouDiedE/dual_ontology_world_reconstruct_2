extends SceneTree

const REVIEW = preload("res://scenes/rubber_whitebox/room_review/RoomReview.tscn")
const PLANS = preload("res://scenes/rubber_whitebox/room_review/RoomPlans.gd")
const MAIN_STAGES = preload("res://scenes/rogue_crossing/Rooms.gd")
var failures := 0

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var review := REVIEW.instantiate()
	root.add_child(review)
	_check(PLANS.ORDER.size() == MAIN_STAGES.TITLES.size(), "Catalog matches main stage count")
	_check(PLANS.ORDER.size() == 11, "Eleven ordered blockouts")
	var seen := {}
	var primary := 0
	var alternate := 0
	for i in PLANS.ORDER.size():
		var id := PLANS.ORDER[i]
		_check(MAIN_STAGES.TITLES.has(id) and not seen.has(id), "Unique main stage: " + id)
		seen[id] = true
		review.open_room(i)
		for frame in 10:
			await physics_frame
		var observation: Dictionary = review.mcp_observe()
		_check(observation.stage == id and observation.grounded, "%s: valid grounded entry" % id)
		_check(observation.fixtures >= 3, "%s: fixture envelopes" % id)
		var plan: Dictionary = review.plan
		var space: PhysicsDirectSpaceState3D = review.get_world_3d().direct_space_state
		_route(space, id + " primary", plan.route)
		primary += 1
		if not plan.alternative.is_empty():
			_route(space, id + " alternate", plan.alternative)
			alternate += 1
		# Prove the documented threshold has a real ArchBuilder hole with a solid cheek.
		if not plan.terminal:
			var edge_z: float = -plan.size.y * 0.5
			var cheek_x: float = plan.exit_x - 1.75 if plan.exit_x > 0.0 else plan.exit_x + 1.75
			_check(not _segment(space, Vector2(cheek_x, edge_z + 0.4), Vector2(cheek_x, edge_z - 0.4)), "%s: solid jamb outside portal" % id)
		print("ROOM %02d %s: %d fixture envelopes, %d marked route(s)" % [i + 1, id, observation.fixtures, 2 if observation.alternate else 1])
	_check(alternate == 3, "Three additional marked lanes")
	if failures == 0:
		print("PASS: %d grounded entries, %d primary routes, %d alternatives and 10 doorway cheeks" % [seen.size(), primary, alternate])
	quit(1 if failures else 0)

func _route(space: PhysicsDirectSpaceState3D, label: String, points: Array) -> void:
	for i in range(1, points.size()):
		_check(_segment(space, points[i-1], points[i]), "%s: capsule clearance %s → %s" % [label, points[i-1], points[i]])

func _segment(space: PhysicsDirectSpaceState3D, a: Vector2, b: Vector2) -> bool:
	var capsule := CapsuleShape3D.new()
	capsule.radius = 0.31
	capsule.height = 1.72
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = capsule
	query.collision_mask = 1
	query.transform.origin = Vector3(a.x, capsule.height * 0.5 + 0.067, a.y)
	if not space.intersect_shape(query, 1).is_empty():
		return false
	query.motion = Vector3(b.x - a.x, 0, b.y - a.y)
	return space.cast_motion(query)[0] >= 0.999

func _check(ok: bool, description: String) -> void:
	if not ok:
		failures += 1
		push_error(description)
