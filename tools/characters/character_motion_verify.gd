extends SceneTree

const WorldScene := preload("res://scenes/dual_world/DualWorldMain.tscn")
const CharacterScene := preload("res://scenes/components/characters/CharacterModel.tscn")
const Lifecycle := preload("res://scenes/components/shared/HostLifecycle.gd")

var failures := 0

func _initialize() -> void:
	_run.call_deferred()

func check(condition: bool, description: String) -> void:
	print(("[PASS] " if condition else "[FAIL] ") + description)
	if not condition: failures += 1

func _run() -> void:
	var world := WorldScene.instantiate()
	world.show_intro = false
	root.add_child(world)
	world.set_process(false)
	var player: AnimationPlayer = world.det.get("_glb_player")
	check(player != null, "Opening detective has a skeletal animation player")
	if player == null:
		world.free()
		quit(1)
		return
	world._process(0.016)
	check(world.det.pose == "lie" and player.current_animation == "lie_idle", "Opening frame keeps the lying animation")
	var skeleton: Skeleton3D = world.det.get("_body").get_meta("skeleton")
	var leg := skeleton.find_bone("mixamorig_LeftUpLeg")
	player.play("walk", 0.0)
	player.seek(0.1, true)
	var first_rotation := skeleton.get_bone_pose_rotation(leg)
	player.seek(0.6, true)
	check(first_rotation.angle_to(skeleton.get_bone_pose_rotation(leg)) > 0.1, "Walking changes the rendered skeleton between strides")
	world.det.set_pose("lie")
	world._sub_queue.clear()
	world.subtitle.visible = false
	world.modal.visible = false
	Input.action_press("move_right")
	world._process(0.016)
	check(world.det.pose == "lie_stand_up" and player.current_animation == "lie_stand_up", "Movement starts waking up before walking")
	var wake_length := player.get_animation("lie_stand_up").length
	check(world._wake_timer >= wake_length, "Wake duration covers the complete imported clip")
	world._step_wake_up(1.2)
	world._walk_step(0.016)
	check(world._wake_timer > 0.0 and player.current_animation == "lie_stand_up", "Wake clip survives beyond the old cutoff")
	world._step_wake_up(wake_length)
	check(world.det.position.y == 0.0 and not world._grid.is_point_solid(world._cell_of(world.det_pos)), "Waking finishes on a navigable floor point")
	world._sub_queue.clear()
	world.subtitle.visible = false
	var before: Vector2 = world.det_pos
	world._process(0.016)
	check(world.det_pos.distance_to(before) > 0.001 and player.current_animation == "walk", "Manual movement retains walk after the entire main loop")
	player.advance(0.15)
	var playback_position := player.current_animation_position
	world._process(0.016)
	check(player.current_animation == "walk" and player.current_animation_position >= playback_position, "Held movement advances instead of restarting idle each frame")
	Input.action_release("move_right")
	world._process(0.016)
	check(player.current_animation == "idle", "Releasing movement returns to idle")
	world._go([world.det_pos + Vector2(0.5, 0.0)])
	world._walk_step(0.016)
	check(player.current_animation == "walk", "Navigation paths animate walking")
	world.det_path.clear()
	for gesture in ["talk", "argue", "point", "think", "wave", "work", "tend"]:
		world.det.set_pose(gesture)
		var expected: String = "gestures/" + gesture if gesture in ["talk", "argue", "point", "think"] else "talk" if gesture == "tend" else "work_loop" if gesture == "work" else gesture
		check(player.current_animation == expected, "Story gesture: " + gesture)
	world.det.set_pose("stand")
	world._on_said("detective", "motion regression", "confront")
	world._process(0.0)
	check(player.current_animation == "gestures/argue", "Dialogue selects and retains its gesture")
	world._sub_until = 0.0
	world._process(0.0)
	check(player.current_animation == "idle", "Finishing dialogue clears its gesture")
	world.free()
	var character := CharacterScene.instantiate()
	root.add_child(character)
	character.configure({"character_id": "detective", "path": "res://assets/characters/UserModels/model_06.glb", "height": 1.32, "yaw_degrees": -90.0})
	var cases := [["sit", "eat_meal", "eat"], ["work", "prepare_meal", "work"], ["stand", "drink", "eat"], ["sit", "read_seated", "read_scroll"], ["stand", "read", "pickup"], ["stand", "request", "interact"], ["lie", "sleep", "lie_idle"], ["sit", "rest", "sit_idle"]]
	for sample in cases:
		character.play_life_action(sample[0], sample[1])
		character.set_motion(false)
		check(character.animation_player.current_animation == sample[2], "Life action keeps its clip: " + sample[1])
	character.play_life_action("stand", "request")
	character.animation_player.advance(0.0)
	character.animation_player.advance(character.animation_player.current_animation_length + 0.05)
	check(character.animation_player.is_playing(), "Ongoing life actions repeat one-shot clips")
	character.clear_life_action()
	character.set_motion(true)
	check(character.animation_player.current_animation == "walk", "Life action releases to walking")
	character.free()
	await _check_life_scene()
	print("FAILURES: ", failures)
	await Lifecycle.quit(self, 1 if failures > 0 else 0)

func _check_life_scene() -> void:
	var main := load("res://scenes/main/Main.tscn").instantiate() as Control
	root.add_child(main)
	main.set_process(false)
	main.open_life()
	check(main.active, "Five-person life scene opens")
	if not main.active:
		main.free()
		return
	var seen: Dictionary = {}
	var motor_present := true
	for frame_index in range(400):
		main._process(0.2)
		for profile in main.snapshot.get("actors", []):
			if profile.activity == null: continue
			motor_present = motor_present and profile.get("motor") is Dictionary
			var animation_player: AnimationPlayer = main.figures[profile.id].animation_player
			seen[animation_player.current_animation] = true
		if frame_index % 20 == 0: await process_frame
	check(motor_present, "Runtime snapshots publish the current authored motor declaration")
	check(seen.has("walk"), "Life scene animates actual navigation")
	check(seen.has("interact") or seen.has("work") or seen.has("eat") or seen.has("pickup") or seen.has("sit_idle"), "Life scene animates work after arrival")
	print("LIFE CLIPS: ", seen.keys())
	main.bridge.Close()
	main.active = false
	root.remove_child(main)
	main.queue_free()
	await process_frame
