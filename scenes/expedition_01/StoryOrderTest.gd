extends SceneTree
## --headless --path . --script res://scenes/expedition_01/StoryOrderTest.gd
var level
var failures := 0

func _initialize() -> void:
	run.call_deferred()

func check(ok: bool, label: String) -> void:
	print("PASS " if ok else "FAIL ", label)
	if not ok:failures += 1

func move_to(player: Vector3, hale: Vector3) -> void:
	level.walker.position = player
	level.hale.position = hale
	level.rules(0.016)

func caption(speaker: String) -> String:
	return level.captions.entries.get(speaker, {}).get("id", "")

func run() -> void:
	level = preload("Sortie.tscn").instantiate()
	root.add_child(level)
	if not level.is_node_ready() or level.captions.typeface == null:
		push_error("Expedition fixture failed to initialize")
		quit(1)
		return
	level.set_physics_process(false)
	await physics_frame
	level.phase = 30.
	move_to(Vector3(13, .03, 0), Vector3(12, 0, 0))
	check(not level.cues.has("start") and not level.cues.has("sealed_well"), "elapsed phase schedules no old exposition")
	level.phase = 0.
	move_to(Vector3(1, .03, 0), Vector3(2, 0, 0))
	check(caption("Hale") == "start", "arrival with Hale triggers local opening at phase zero")
	var remaining:float=level.captions.entries["Hale"].remaining
	level.toggle_book()
	check(not level.captions.visible,"manual hides world dialogue")
	level.toggle_book()
	check(caption("Hale")=="start" and level.captions.entries["Hale"].remaining==remaining,"closing manual restores the interrupted line and reading time")
	level.oil=10.;level.lamp_on=false;level.rules(1.)
	check(is_equal_approx(level.oil,10.),"an extinguished wick consumes no fuel in the arcade")
	level.oil=0.;level.toggle_lamp();check(not level.lamp_on,"empty lamp cannot relight")
	level.oil=65.;level.toggle_lamp()
	move_to(Vector3(13, .03, 0), Vector3(12, 0, 0))
	check(caption("Hale") != "start", "leaving the entrance clears the opening even with Hale nearby")
	move_to(Vector3(34, .03, 0), Vector3(33, 0, 0))
	check(not level.cues.has("sealed_well"), "gate line waits for a failed gate attempt")
	level.confirm_gate_locked()
	move_to(Vector3(34, .03, 0), Vector3(12, 0, 0))
	check(not level.cues.has("sealed_well"), "distant Hale does not speak about the gate")
	move_to(Vector3(34, .03, 0), Vector3(33, 0, 0))
	check(caption("Hale") == "sealed_well", "confirmed gate plus nearby Hale delivers local advice")
	move_to(Vector3(31, .03, 5), Vector3(30, 0, 5))
	check(caption("Hale") == "collapse", "detour replaces stale gate advice")
	level.released = true
	level.hunter.wake()
	level.walker.position = Vector3(49, .03, 10.1)
	level.eye.look_at(Vector3(43, 1.5, 10.1))
	move_to(level.walker.position, Vector3(39, 0, 0))
	check(not level.cues.has("shaft_doubt"), "shaft X coordinate alone gives no bridge thought")
	level.eye.look_at(Vector3(53.5, .08, 10.1))
	move_to(level.walker.position, Vector3(39, 0, 0))
	check(caption("") == "shaft_doubt" and caption("Hale") != "shaft_doubt", "looking at bridge yields player observation without Hale")
	level.posting = true
	var core: Vector3 = level.kit.core.global_position
	level.walker.position = core + Vector3(-1.3, -core.y + .03, 0)
	level.eye.look_at(core)
	check(level.focus() == "core", "core interaction fixture is reachable")
	level.use()
	check(level.collected and not level.left_north_window and caption("") == "core" and caption("Hale") != "core", "core alarm gives player thought; Hale still en route was never at north window")
	level.collected = false
	level.kit.core.show()
	level.holding = true
	level.use()
	check(level.collected and level.left_north_window and caption("Hale") != "core", "posted Hale returns without remote dialogue")
	# Sample the built collision surface halfway down a continuous west stair wedge.
	var stair_index := -22.5
	var angle := PI * .5 + TAU * stair_index / 41.
	var stair_y := 4.8 * stair_index / 41.
	var stair := Vector3(level.kit.WEST_STAIR_X + cos(angle), stair_y, level.kit.CZ - 2. + sin(angle))
	var ray := PhysicsRayQueryParameters3D.create(stair + Vector3.UP * .35, stair - Vector3.UP * .35, 1)
	var ground: Dictionary = level.get_world_3d().direct_space_state.intersect_ray(ray)
	var valid_tread: bool = not ground.is_empty() and ground.collider.is_in_group("expedition_iron_tread") and ground.position.y < -1.8
	check(valid_tread, "west spiral has walkable iron collision below -1.8")
	if valid_tread:
		level.retry = 0.
		move_to(ground.position + Vector3.UP * .03, Vector3(39, 0, 0))
		check(level.retry == 0., "supported west spiral tread remains safe below -1.8")
	# A stale hunt flag, an absent item, or a sealed gallery must not give Hale knowledge.
	level.walker.position=Vector3(51,0,10);level.hale.position=Vector3(51,0,11)
	level.hunter.state="hunt";level.hunter.voice.stop();level.captions.clear();level.trust_line_cd=0.
	level.hale_report()
	check(caption("Hale")=="", "silent hunt state produces no witness line")
	level.hunter.voice.stream=level.sounds.scream;level.hunter.voice.play()
	level.hale_report()
	check(caption("Hale")=="hale_read", "Hale and player hear the same shaft cry")
	level.walker.position=Vector3(76,4.8,12.45);level.hale.position=Vector3(76,4.8,12.)
	level.return_started=true;level.captions.clear();level.trust_line_cd=0.;level.hale_report()
	check(caption("Hale")=="", "shaft cry does not carry into the closed escape gallery")
	level.contracts.b_remembered=true;level.equipped=false
	check("节拍器" not in level.contracts.b_line(level), "Hale does not propose throwing a metronome the party lacks")
	level.free()
	# Let the audio mixer release playbacks before terminating the test host.
	for frame in 26:
		OS.delay_msec(8)
		await process_frame
	quit(0 if failures == 0 else 1)
