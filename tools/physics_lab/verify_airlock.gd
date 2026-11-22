extends SceneTree
## Physical counterfactuals plus the witnessed-rule contract. No player-side hooks.
const Scene := preload("res://scenes/physics_lab/airlock/Airlock.tscn")
const Room := preload("res://scenes/physics_lab/airlock/Room.gd")
const Rules := preload("res://scenes/physics_lab/airlock/Rules.gd")
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
	for i in range(20): isolated.record(true,true,false,false)
	check(not isolated.record(false,false,true,true), "Walking unseen cannot change Hale's belief.")
	for i in range(20): isolated.record(true,false,true,false)
	check(not isolated.record(false,false,true,true), "Merely crossing cannot prove that looking was safe.")
	for i in range(Rules.MIN_OBSERVED): isolated.record(true,true,true,false)
	check(not isolated.speak(true), "Hale needs to see the demonstrator return.")
	check(isolated.record(false,false,true,true), "Witnessed survival produces a counterexample.")
	check(not isolated.speak(false), "A counterexample alone grants no remote conversation.")
	check(isolated.forbidden("observe_lit_span",{"span_lit":true}), "Hale follows his original taboo until persuaded.")
	check(isolated.speak(true), "A nearby, witnessed exchange revises the taboo.")
	check(not isolated.forbidden("observe_lit_span",{"span_lit":true}), "Hale can finally sustain a witness relay.")
	# Lose the sole B witness while on the actual deck: check grace and recovery shore.
	game.yaw = 0.0
	game.pitch = 1.02
	game.lead.position = Vector3(4.95,.015,Room.B_LANE)
	game.refuge = Vector3(-.18,0,-3.55)
	game.deck[1] = true
	game.last_seen[1] = game.tick
	game.room.paint(1,true,0)
	for i in range(59): game._simulate(Vector2.ZERO,Vector2.ZERO,false,false)
	check(game.deck[1] and game.lead.position.y > -.05, "A lost witness preserves support for 59 tick advances.")
	game._simulate(Vector2.ZERO,Vector2.ZERO,false,false)
	check(not game.deck[1], "Tick 60 drops support.")
	for i in range(65): game._simulate(Vector2.ZERO,Vector2.ZERO,false,false)
	check(game._floor(game.lead) == "island" and not game.cleared, "The catch returns to the last reached bank, never across B.")
	for message in failures: printerr(message)
	print("Airlock optical, geometric, rule and physical recovery counterfactuals: %d failures" % failures.size())
	game.queue_free()
	await process_frame
	quit(0 if failures.is_empty() else 1)
