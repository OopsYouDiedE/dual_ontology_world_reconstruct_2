extends SceneTree
## Physical counterfactuals plus the witnessed-rule contract. No player-side hooks.
const Scene := preload("res://scenes/physics_lab/airlock/Airlock.tscn")
const Room := preload("res://scenes/physics_lab/airlock/Room.gd")
const Rules := preload("res://scenes/physics_lab/airlock/Rules.gd")
const Span := preload("res://scenes/physics_lab/airlock/Span.gd")
var failures: Array[String] = []

func _initialize() -> void:
	_run.call_deferred()

func check(ok: bool, message: String) -> void:
	if not ok: failures.append(message)

func _run() -> void:
	var game := Scene.instantiate()
	root.add_child(game)
	game.set_physics_process(false)
	await physics_frame
	await process_frame
	var a_eye := Vector3(-.18,1.60,2.8)
	var bank_obs: Array = game._observe(a_eye,(Room.A_AIM-a_eye).normalized(),game.lead)
	check(bank_obs == [true,false], "The lit A deck is directly visible at the entrance.")
	game.room.spans[0].lamp.hide()
	check(not game._observe(a_eye,(Room.A_AIM-a_eye).normalized(),game.lead)[0], "An unlit A opening produces no witness even with the same aim.")
	game.room.spans[0].lamp.show()
	for x in [-1.45,-.9,0.0,.9,1.45]:
		for z in [.35,1.7,3.55]:
			var eye := Vector3(x,1.60,z)
			check(not game._observe(eye,(Room.B_AIM-eye).normalized(),game.lead)[1], "B must stay occluded from the near bank (%s)." % eye)
	var blinders: Array[StaticBody3D] = []
	for part in game.room.root.get_children():
		if part is StaticBody3D and part.get_meta("surface", "") in ["blind_wall","blind_pier"]:
			blinders.append(part)
			part.collision_layer = 0
	var opened_eye := Vector3(.72,1.60,.7)
	check(game._observe(opened_eye,(Room.B_AIM-opened_eye).normalized(),game.lead)[1], "Removing only the baffle reveals B from near; there is no scripted bank exclusion.")
	for b in blinders: b.collision_layer = Room.WORLD
	for point in [Room.ISLAND_WATCH,Room.FAR_WATCH]:
		var eye: Vector3 = point + Vector3.UP*1.60
		check(game._observe(eye,(Room.B_AIM-eye).normalized(),game.lead)[1], "Each overlook sees the same B rib directly.")
	for x in [1.65,2.10,3.30,4.50,5.55]:
		for z in [-4.26,-3.88,-3.12]:
			var eye := Vector3(x,1.60,z)
			check(not game._observe(eye,(Room.B_AIM-eye).normalized(),game.lead)[1], "Walking the B deck cannot replace its lateral observer.")
	var start := Transform3D(Basis.IDENTITY,Vector3(.58,.007,Room.B_LANE))
	var contact := KinematicCollision3D.new()
	check(game.lead.test_move(start,Vector3(.76,0,0),contact) and contact.get_collider().get_meta("surface") == "low_lintel", "Standing capsule hits the lintel.")
	game._stance(game.lead,true,false)
	check(not game.lead.test_move(start,Vector3(.76,0,0)), "Crouching capsule passes the same lintel.")
	game._stance(game.lead,false,true)
	for i in range(2):
		game.room.paint(i,true,0)
		var span: Dictionary = game.room.spans[i]
		check(span.surface.visible and span.solid.collision_layer == Room.DECK, "Live deck mesh and collision agree.")
		check(span.surface.mesh.size == span.solid.get_child(0).shape.size, "Live deck dimensions agree.")
		game.room.paint(i,false,0)
		check(not span.surface.visible and span.solid.collision_layer == 0, "Collapsed deck has only optical echoes.")
	var isolated := Rules.new()
	check(isolated.forbidden("observe_lit_span",{"lead_already_watching":false}), "Hale holds the initial taboo even while the lead looks away.")
	for i in range(120): isolated.sample_trial(false,true)
	check(not isolated.speak(true), "The lead's solo evidence cannot describe what Hale perceived.")
	for i in range(15): isolated.sample_trial(true,true)
	check(not isolated.speak(true), "A red flare alone confirms danger but cannot narrow the taboo.")
	for i in range(Rules.MIN_SOLO-1): isolated.sample_trial(true,false)
	check(not isolated.counterexample, "A transient white flash does not suffice.")
	check(isolated.sample_trial(true,false) == "EVIDENCE", "Hale sees the sustained one-eye boundary after red.")
	check(not isolated.speak(false), "Evidence grants no remote conversation.")
	check(isolated.speak(true), "Face-to-face conversation narrows the taboo.")
	check(not isolated.forbidden("observe_lit_span",{"lead_already_watching":false}), "Solo ownership is allowed.")
	check(isolated.forbidden("observe_lit_span",{"lead_already_watching":true}), "Overlapping ownership stays forbidden.")
	check(isolated.forbidden("observe_lit_span") and isolated.forbidden("step_into_void"), "The exception fails closed and the void taboo survives.")
	var cautious := Rules.new()
	for i in range(Rules.MIN_UNINTERRUPTED_SOLO-1): cautious.sample_trial(true,false)
	check(not cautious.counterexample, "Without a contrast Hale takes longer to trust the stationary result.")
	check(cautious.sample_trial(true,false) == "EVIDENCE", "A careful player can also establish the exception without provoking red.")
	var panic := Rules.new()
	for i in range(23): panic.sample_trial(true,true)
	panic.sample_trial(true,false)
	for i in range(23): panic.sample_trial(true,true)
	check(panic.distorted and panic.urges_overlap() and not panic.speak(true), "Separate survivable flares can corrupt advice without granting valid evidence.")
	panic.ground()
	check(not panic.distorted and panic.panic == 0 and panic.forbidden("observe_lit_span"), "Grounding restores the known safety rule.")
	var span := Span.new()
	span.step(1)
	for i in range(59): span.step(0)
	check(span.solid and span.dark == 59, "A one-eye span survives the first 59 zero-eye samples.")
	span.step(0)
	check(not span.solid and span.dark == 60, "The 60th zero-eye sample collapses support.")
	span.step(1)
	check(span.solid and span.dark == 0, "One lit eye reforms the span.")
	for i in range(40): span.step(2)
	check(span.red == 40 and span.solid, "A double look supplies forty full warning ticks.")
	span.step(1)
	check(span.red == 0 and span.solid, "A withdrawn eye prevents death on the next sample.")
	game.witness = [[true,false],[false,true]]
	check(game._tick_spans() and game.deck == [true,true] and game.spans[0].red == 0 and game.spans[1].red == 0,
		"One eye on each different span is not a double look at either bridge.")
	# One-hit collision and mesh release, followed by physical falling; no catch teleport.
	game.yaw = 0.0
	game.pitch = 1.02
	game.lead.position = Vector3(4.95,.015,Room.B_LANE)
	for i in range(59): game._simulate(Vector2.ZERO,Vector2.ZERO,false,false)
	check(game.deck[1] and game.lead.position.y > -.05, "Lost B witness preserves physical support for 59 samples.")
	game._simulate(Vector2.ZERO,Vector2.ZERO,false,false)
	check(not game.deck[1] and not game.room.spans[1].surface.visible and game.room.spans[1].solid.collision_layer == 0,
		"On sample 60 the B mesh and collision release together.")
	for i in range(66): game._simulate(Vector2.ZERO,Vector2.ZERO,false,false)
	check(game.failed == "FALL" and game.lead.position.y < -2.46 and not game.cleared, "Loss of support has a terminal fall after gravity does its work.")
	game._reset()
	check(game.failed.is_empty() and game.role == "NEAR" and game.deck == [false,false], "Restart restores a live initial room.")
	game.witness = [[true,false],[true,false]]
	for i in range(40):
		check(game._tick_spans(), "Red must remain survivable throughout all 40 warning steps.")
	check(not game._tick_spans() and game.failed == "DOUBLE_GAZE", "The next overlapping sample kills, even on the near bank.")
	for message in failures: printerr(message)
	print("Airlock optical, geometric, AST, panic, and lethal timing counterfactuals: %d failures" % failures.size())
	game.queue_free()
	await process_frame
	quit(0 if failures.is_empty() else 1)
