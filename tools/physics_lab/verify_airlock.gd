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
	for point in [Room.ISLAND_WATCH,Room.FAR_WATCH,Room.FAR_SECOND]:
		var eye: Vector3 = point + Vector3.UP*1.60
		check(game._observe(eye,(Room.B_AIM-eye).normalized(),game.lead)[1], "Each overlook sees the same B rib directly.")
	var hits := 0
	var samples := 0
	var min_contiguous := 100
	for point in [Room.ISLAND_WATCH,Room.FAR_WATCH,Room.FAR_SECOND]:
		for dy in [.92,1.60]:
			for dx in [-.11,0.0,.11]:
				var eye: Vector3 = point + Vector3(dx,dy,0)
				var axis := (Room.B_AIM-eye).normalized()
				var row := 0
				for az in range(-8,9):
					var look := axis.rotated(Vector3.UP,deg_to_rad(az))
					var hit: bool = game._observe(eye,look,game.lead)[1]
					samples += 1
					hits += int(hit)
					row += int(hit and abs(az) <= 4)
					if not hit and abs(az) <= 4: print("Overlap miss ",eye," ",az)
					if abs(az) <= 1: check(hit,"The photographed rib must survive the prior ±1° audit counterexample: %s° at %s" % [az,eye])
				if row < 9: print("Sweep edge ",eye," -> ",row,"/9")
				min_contiguous = mini(min_contiguous,row)
				for pitch in [-3.0,3.0]:
					var slope := axis.rotated(axis.cross(Vector3.UP).normalized(),deg_to_rad(pitch))
					check(game._observe(eye,slope,game.lead)[1], "Three-degree vertical adjustment must not lose B at %s." % eye)
	print("B optical sweep: %s/%s angular samples; worst central +/-4 deg row has %s/9 hits" % [hits,samples,min_contiguous])
	check(min_contiguous == 9, "B central yaw coverage must stay continuous across stations, head heights and offsets.")
	var old_eye := Vector3(6.297585,1.600834,-2.628127)
	var old_axis := (Vector3(3.55,-.245,-2.977)-old_eye).normalized()
	for az in [-1.0,0.0,1.0]:
		check(game._observe(old_eye,old_axis.rotated(Vector3.UP,deg_to_rad(az)),game.lead)[1], "Astra's exact historical ±1° pose must still see B in the replacement geometry.")
	for x in [1.65,2.10,3.30,4.50,5.55]:
		for z in [-4.26,-3.88,-3.40]:
			var eye := Vector3(x,1.60,z)
			check(not game._observe(eye,(Room.B_AIM-eye).normalized(),game.lead)[1], "An eye above actual B walking surface cannot replace the lateral observer.")
	var aperture := Room.FAR_HIDDEN+Vector3.UP*1.60
	check(game._observe(aperture,(Room.B_AIM-aperture).normalized(),game.lead)[1], "Standing behind the high shutter sees down to the rib.")
	var lane_eye := Room.ISLAND_WATCH+Vector3.UP*1.60
	var no_exclusions: Array[RID] = []
	var hidden_head: Dictionary = game._ray(lane_eye,aperture,Room.WORLD,no_exclusions)
	check(not hidden_head.is_empty() and hidden_head.collider.get_meta("surface") == "head_shutter", "The same shutter blocks Hale's head-level line; this is not a 2D test.")
	await _verify_tread(game)
	await _verify_marks(game)
	for zone in [Room.FAR_WATCH,Room.FAR_SECOND]:
		check(game._ray(lane_eye,zone+Vector3.UP*1.60,Room.WORLD,no_exclusions).is_empty(), "Both alternate dry-bank positions expose a visible signal.")
	var lamp: SpotLight3D = game.room.spans[1].lamp
	var sample := Room.B_AIM
	check(game._lit(lamp,sample), "The dedicated B light illuminates the rib with no blocker.")
	game.lead.position = sample.lerp(lamp.position,.36)-Vector3.UP*.85
	await physics_frame
	await process_frame
	check(not game._lit(lamp,sample), "A real actor standing in the light ray blocks the licensed facet.")
	game.lead.position = Room.LEAD_HOME
	await physics_frame
	await process_frame
	check(game._lit(lamp,sample), "Removing the physical shadow restores the illuminated facet.")
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
	var untouched := Rules.new()
	var careful := Rules.new()
	var isolated := Rules.new()
	var far_away := {"head":"AWAY","bank":"far","color":"WHITE"}
	var far_toward := {"head":"TOWARD","bank":"far","color":"RED"}
	var alone := {"head":"AWAY","bank":"near","color":"WHITE"}
	var conflict := {"head":"TOWARD","bank":"near","color":"RED"}
	var hidden := {"head":Rules.NONE,"bank":Rules.NONE,"color":"WHITE"}
	for i in range(120): isolated.sample_trial(hidden)
	check(not isolated.speak(true), "Unseen head direction is not counterexample evidence.")
	for i in range(15): isolated.sample_trial(conflict)
	check(not isolated.speak(true), "A red flare alone confirms danger but cannot narrow the taboo.")
	for i in range(Rules.MIN_SOLO-1): isolated.sample_trial(alone)
	check(not isolated.counterexample, "A transient white flash does not suffice.")
	check(isolated.sample_trial(alone) == "EVIDENCE", "Hale sees the sustained one-eye boundary after red.")
	check(not isolated.speak(false), "Evidence grants no remote conversation.")
	check(isolated.speak(true) and isolated.hypotheses == [Rules.JOIN_IS_HAZARD], "Contrasting observations refute both rival explanations.")
	check(isolated.ast.allowed_heads == ["AWAY"] and not isolated.permits_step(false), "The generated exception fails closed and retains the void taboo.")
	for i in range(Rules.MIN_UNINTERRUPTED_SOLO-1): careful.sample_trial(alone)
	check(not careful.counterexample, "Without a contrast Hale takes longer to trust the stationary result.")
	check(careful.sample_trial(alone) == "EVIDENCE" and careful.speak(true), "A cautious player proves the solo boundary without provoking red.")
	check(careful.hypotheses == [Rules.JOIN_IS_HAZARD,Rules.NO_GAZE_HAZARD] and careful.ast.allowed_heads == ["AWAY"], "Solo evidence leaves genuine uncertainty; an untested overlap is not approved.")
	var panic := Rules.new()
	for i in range(23): panic.sample_trial(conflict)
	panic.sample_trial(alone)
	for i in range(23): panic.sample_trial(conflict)
	check(panic.distorted and not panic.speak(true), "Separate survivable flares can corrupt behaviour without granting valid evidence.")
	# One identical percept trace fed to each controller, no internal bridge state supplied.
	var trial_actions := []
	for mind in [untouched,isolated,panic]:
		var choice: String
		for i in range(Rules.HAND_SIGNAL): choice = mind.decide(far_away,"GIVE")
		var away_choice := choice
		for i in range(9): choice = mind.decide(far_toward,"GIVE")
		trial_actions.append([away_choice,choice])
	check(trial_actions == [["REFUSE","REFUSE"],["GIVE","RECOIL"],["SEARCH","JOIN"]], "Identical public observations must cause three distinct decisions and only the distorted policy joins red.")
	print("Same percept stream / initial, revised, distorted: ",trial_actions)
	for i in range(Rules.HAND_SIGNAL+6):
		check(isolated.decide(hidden,"GIVE") == "HOLD", "Lost line of sight stalls the transfer on the same bridge.")
	panic.ground()
	check(not panic.distorted and panic.panic == 0 and panic.decide(far_toward,"TAKE") == "REFUSE", "Grounding restores the known safety rule.")
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
	for i in range(100): game._simulate(Vector2.ZERO,Vector2.ZERO,false,false)
	check(game.failed == "FALL" and game.lead.position.y < -2.46 and not game.cleared, "Loss of support has a terminal fall after gravity does its work.")
	game._reset()
	check(game.failed.is_empty() and game.role == "NEAR" and game.deck == [false,false], "Restart restores a live initial room.")
	game.witness = [[true,false],[true,false]]
	for i in range(40):
		check(game._tick_spans(), "Red must remain survivable throughout all 40 warning steps.")
	check(not game._tick_spans() and game.failed == "DOUBLE_GAZE", "The next overlapping sample kills, even on the near bank.")
	game.queue_free()
	await process_frame
	await _same_inputs([Rules.new(), isolated, _distorted_mind()])
	for message in failures: printerr(message)
	print("Airlock optical, geometric, AST, panic, and lethal timing counterfactuals: %d failures" % failures.size())
	quit(0 if failures.is_empty() else 1)


func _verify_tread(game: Node3D) -> void:
	var throat := Vector3(.82,0,Room.B_LANE)
	check(game.room.tread.global_position.is_equal_approx(game.room.tread_reference.global_position),
		"The real pale tread and the missing-tread referent must occupy the same world point.")
	game.role = "WAIT_B"
	game.lead.position = throat
	game.yaw = -PI/2.0
	game.pitch = deg_to_rad(-5)
	game._camera_rotation()
	await physics_frame
	await process_frame
	var shallow: bool = game._tread_in_view()
	game._trial(false)
	game.lead.position = Room.ISLAND_TRIAL
	await physics_frame
	await process_frame
	game._trial(false)
	check(not shallow and not game.attempted_tread and not game.stalemate, "Off-screen tread plus retreat must not award observation.")
	game.lead.position = throat
	var aim := (Room.TREAD_AT-(throat+Vector3.UP*1.60)).normalized()
	game.pitch = asin(aim.y)
	game._camera_rotation()
	await physics_frame
	await process_frame
	var downward: bool = game._tread_in_view()
	var cover = game.room._solid(Vector3(1.32,.82,Room.B_LANE),Vector3(.09,.50,1.52),Color("464646"),"test_occluder")
	await physics_frame
	await process_frame
	check(not game._tread_in_view(), "An in-frustum tread hidden behind a wall does not enter evidence.")
	game._trial(false)
	check(not game.attempted_tread, "The occluded witness cannot unlock the trial.")
	cover.queue_free()
	await physics_frame
	await process_frame
	game.book_open = true
	game._trial(false)
	check(not game.attempted_tread, "The open field copies cannot obscure the mark while granting evidence.")
	game.book_open = false
	game._trial(false)
	game.lead.position = Room.ISLAND_TRIAL
	await physics_frame
	await process_frame
	game._trial(false)
	check(downward and game.attempted_tread and game.stalemate, "Same position + framed true glance + retreat unlocks the trial.")
	print("Tread same-position counterexample: shallow=",shallow,", clear downward=",downward,", retreat receipt=",game.stalemate)
	game._reset()
	await physics_frame
	await process_frame


func _verify_marks(game: Node3D) -> void:
	game.hale.position = Room.ISLAND_WATCH
	game.cue_head.position.y = 1.51
	game.cue_head.rotation.y = PI
	for point: Vector3 in [Room.FAR_WATCH,Room.FAR_SECOND,Room.FAR_HIDDEN,Vector3(4.9,0,Room.B_LANE)]:
		game.lead.position = point
		await physics_frame
		await process_frame
		var eye := game._hale_eye() as Vector3
		var dir: Vector3 = (game._watch_b()-eye).normalized()
		var visual: Dictionary = game._sample(eye,dir,game.hale,true)
		check(visual.spans[1], "A visual contact test must not falsify the live B witness: %s" % point)
		if point in [Room.FAR_WATCH,Room.FAR_SECOND]:
			check(not visual.head.is_empty() and visual.boot.get("bank") == "far", "Both dry poses must give same-lattice head and boot cues.")
			for item in [visual.head,visual.boot,visual.optic[1]]:
				check(item.get("ray",-1) in range(27) and not item.get("light","").is_empty(),"Percept must cite its ray and actual light.")
		else:
			check(visual.boot.get("bank",Rules.NONE) != "far", "Concealed or on-deck identity cannot be treated as safe on stone.")
		if point == Room.FAR_HIDDEN: check(visual.head.is_empty(), "The high shutter really hides the head signal.")
	game.lead.position = Room.FAR_WATCH
	await physics_frame
	await process_frame
	var far_lamp: SpotLight3D = game.room.cue_lights[1]
	var old_lamp: Transform3D = far_lamp.global_transform
	var old_eye := game._hale_eye() as Vector3
	var look: Vector3 = (game._watch_b()-old_eye).normalized()
	var illuminated: Dictionary = game._sample(old_eye,look,game.hale,true)
	far_lamp.position = Vector3(6.69,3.47,-2.94)
	far_lamp.look_at(Vector3(6.63,.27,-2.70))
	var from_behind: Dictionary = game._sample(old_eye,look,game.hale,true)
	check(illuminated.head.get("incidence",-1) > .02 and illuminated.boot.get("incidence",-1) > .02,
		"Astra's exact far-bank signals must now have light on the ray-hit exterior, not merely a spot cone.")
	check(from_behind.spans[1] and from_behind.head.is_empty() and from_behind.boot.is_empty(),
		"Returning the active lamp to its former backlit position cannot claim the same head / boot observations.")
	print("Far-side incidence counterexample: head=",illuminated.head.get("incidence"),", boot=",illuminated.boot.get("incidence"),
		", rear rejected=",from_behind.head.is_empty() and from_behind.boot.is_empty())
	far_lamp.global_transform = old_lamp
	for lamp: SpotLight3D in game.room.cue_lights: lamp.hide()
	var eye := game._hale_eye() as Vector3
	var unlit: Dictionary = game._sample(eye,(game._watch_b()-eye).normalized(),game.hale,true)
	check(unlit.spans[1] and unlit.head.is_empty() and unlit.boot.is_empty(),"Dark actor signals must become unobservable without turning off the bridge.")
	for lamp: SpotLight3D in game.room.cue_lights: lamp.show()
	game.hale.position = Room.HALE_HOME
	game.lead.position = Room.LEAD_HOME
	game.cue_head.rotation.y = 0.0
	await physics_frame
	await process_frame


func _distorted_mind() -> Rules:
	var mind := Rules.new()
	var flare := {"color":"RED","head":"TOWARD","bank":"near"}
	for i in range(23): mind.sample_trial(flare)
	mind.sample_trial({"color":"WHITE","head":"AWAY","bank":"near"})
	for i in range(23): mind.sample_trial(flare)
	return mind


func _same_inputs(minds: Array) -> void:
	var rows := []
	for mind: Rules in minds:
		var world := Scene.instantiate()
		root.add_child(world)
		world.set_physics_process(false)
		world.role = "WAIT_B"
		world.rule = mind
		world.hale.position = Room.ISLAND_WATCH
		world.lead.position = Room.ISLAND_TRIAL
		world._turn_hale(Room.ISLAND_TRIAL+Vector3.UP*1.84)
		world.yaw = PI/2.0
		world.pitch = .0
		await physics_frame
		await process_frame
		for i in range(55): world._simulate(Vector2.ZERO,Vector2.ZERO,false,false)
		var gaze_away: bool = world.witness[1][1]
		for i in range(25): world._simulate(Vector2.ZERO,Vector2(-PI/15.0,0) if i < 15 else Vector2.ZERO,false,false)
		rows.append([gaze_away,world.witness[1][1],world.role])
		world.queue_free()
		await process_frame
	print("Same real scene + player turn / initial, revised, distorted: ",rows)
	check(rows == [[false,false,"WAIT_B"],[true,true,"WATCH_B"],[false,true,"WATCH_B"]],
		"Policy revisions must yield three actual gaze patterns under identical inputs in Godot.")
