extends SceneTree
## Real-physics batch permutation prober for Expedition-01.
## Runs unmodified Sortie.tscn with exact player capsule, colliders, and triggers,
## recording every dialogue line, region transition, and interaction in exact tick order.
##
## Usage:
##   godot --headless --fixed-fps 60 --path . --script res://tools/expedition/batch_sequence_probe.gd -- --scenario=S1_Standard_North

var level
var ticks := 0
var scenario := "S1_Standard_North"
var dialogue_seq: Array = []
var region_seq: Array = []
var action_seq: Array = []
var last_region := ""
var peak_exposure := 0.0

func _initialize() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--scenario="):
			scenario = arg.trim_prefix("--scenario=")
	run.call_deferred()

func _on_caption(speaker: String, text: String) -> void:
	dialogue_seq.append({
		"tick": ticks,
		"speaker": "我" if speaker.is_empty() else speaker,
		"text": text,
		"region": level.region if level != null else "",
	})

func _on_audit(kind: String, detail: String) -> void:
	if kind in ["use", "order", "confirmed"]:
		action_seq.append({"tick": ticks, "kind": kind, "detail": detail})

func _sample_state() -> void:
	if level == null or not is_instance_valid(level):
		return
	peak_exposure = maxf(peak_exposure, level.hunter.exposure)
	if level.region != "" and level.region != last_region:
		last_region = level.region
		region_seq.append({"tick": ticks, "region": last_region})

func step_frames(n: int) -> void:
	for i in n:
		await physics_frame
		ticks += 1
		_sample_state()

func go(x: float, z: float, quiet := false, run_mode := false, look_pt := Vector3.ZERO, limit := 650, tol := 0.22) -> bool:
	level.running = run_mode
	if quiet:
		Input.action_press("expedition_quiet")
	else:
		Input.action_release("expedition_quiet")
	Input.action_press("move_up")
	var ok := false
	for i in limit:
		if level.retry > 0.0:
			break
		if level.finished:
			ok = true
			break
		var p: Vector3 = level.walker.position
		var d := Vector2(x - p.x, z - p.z)
		if d.length() < tol:
			ok = true
			break
		level.walker.rotation.y = atan2(-d.x, -d.y)
		if look_pt != Vector3.ZERO:
			level.eye.look_at(look_pt)
		else:
			level.eye.rotation.x = 0.0
		await physics_frame
		ticks += 1
		_sample_state()
	Input.action_release("move_up")
	Input.action_release("expedition_quiet")
	level.running = false
	return ok and level.retry <= 0.0

func use_at(target: Vector3) -> bool:
	level.eye.look_at(target)
	await step_frames(2)
	level.use()
	level.eye.rotation = Vector3.ZERO
	await step_frames(2)
	return true

func do_b2_b3_standard(witness_b2: bool, stare_b3: bool) -> bool:
	for pt in [[31.0, 0.0], [31.0, 4.9], [26.7, 4.9], [25.7, 5.5], [25.7, 7.75], [24.65, 7.75]]:
		if not await go(pt[0], pt[1]):
			return false
	if witness_b2:
		level.eye.look_at(Vector3(24.65, 1.57, 4.0))
		for i in 180:
			await step_frames(1)
			if level.archive.gaze != Vector3.ZERO and level.observers == 1:
				break
		level.eye.look_at(Vector3(23.85, 0.10, 12.02))
		var two := false
		for i in 220:
			await step_frames(1)
			if level.observers == 2:
				two = true
			if two and level.observers == 1 and level.archive.paired:
				break
		await step_frames(42)
		level.eye.rotation = Vector3.ZERO
	if not await go(20.95, 7.75) or not await go(20.95, 9.8) or not await go(23.85, 9.8):
		return false
	if stare_b3:
		level.eye.look_at(Vector3(23.85, 0.11, 12.02))
		await step_frames(155)
	return await go(23.85, 14.12, false, false, Vector3(23.85, 0.11, 13.0))

func run_spiral_and_exit(take_east: bool) -> bool:
	if take_east:
		if not await go(71.8, 8.95) or not await go(73.35, 9.12):
			return false
		var origin := Vector3(73.35, 0.0, 8.1)
		for i in range(42):
			var a := PI * 0.5 + TAU * i / 41.0
			var pt := origin + Vector3(1.02 * cos(a), 0.0, 1.02 * sin(a))
			if not await go(pt.x, pt.z, false, true, Vector3.ZERO, 160, 0.34):
				return false
		if not await go(74.54, 12.45, false, true):
			return false
		await use_at(level.kit.leaf.global_position)
		for pt in [[78.52, 12.45], [78.52, 26.65], [43.8, 26.65], [43.8, 10.1], [35.0, 0.0], [1.5, 0.0]]:
			if not await go(pt[0], pt[1], false, true):
				return false
		await use_at(Vector3(0.37, 1.5, 0.0))
		await go(-1.5, 0.0, false, false)
	return true

func run() -> void:
	level = preload("res://scenes/expedition_01/Sortie.tscn").instantiate()
	root.add_child(level)
	level.captions.posted.connect(_on_caption)
	level.audit_action.connect(_on_audit)
	await step_frames(4)

	var ok := true
	match scenario:
		"S1_Standard_North":
			if await go(35.0, 0.0, false, true):
				await use_at(Vector3(36.0, 1.57, 0.0))
			ok = await do_b2_b3_standard(true, true)
			if ok:
				for pt in [[25.5, 14.1], [38.9, 14.1], [38.9, 10.0], [36.6, 8.5]]:
					ok = await go(pt[0], pt[1])
					if not ok: break
			if ok:
				await use_at(Vector3(36.3, 1.35, 7.72))
				ok = await go(39.0, 10.1, true, false) and await go(48.8, 10.1, true, false)
			if ok:
				for i in 220:
					if level.hale.position.distance_to(level.walker.position) <= 6.0: break
					await step_frames(1)
				level.pick_order("north")
				for i in 900:
					if level.holding: break
					await step_frames(1)
				level.toggle_lamp() # Douse lamp (R) to obey Single-Lamp Rule
				ok = await go(71.5, 10.1, true, false)
			if ok:
				await use_at(level.kit.core.position)
				ok = await run_spiral_and_exit(true)

		"S2_A2Niche_B6Pump_North":
			ok = await go(9.0, 0.0, false, true) and await go(9.0, 4.8, true, false) and await go(13.2, 5.9, true, false)
			if ok:
				await step_frames(20)
				await use_at(Vector3(13.9, 0.62, 5.9))
				for pt in [[15.75, 6.6], [20.6, 6.6], [20.6, 7.8], [24.65, 7.75]]:
					ok = await go(pt[0], pt[1], true, false)
					if not ok: break
			if ok:
				await use_at(Vector3(23.6, 1.03, 4.0)) # note
				ok = await go(20.95, 7.75) and await go(20.95, 9.8) and await go(23.85, 9.8)
			if ok:
				level.eye.look_at(Vector3(23.85, 0.11, 12.02))
				await step_frames(155)
				ok = await go(23.85, 14.12, false, false, Vector3(23.85, 0.11, 13.0))
			if ok:
				for pt in [[25.5, 14.1], [38.9, 14.1], [38.9, 3.1]]:
					ok = await go(pt[0], pt[1])
					if not ok: break
				await use_at(Vector3(39.2, 1.10, 3.1)) # B6 flywheel
				ok = await go(38.9, 8.5) and await go(36.6, 8.5)
			if ok:
				await use_at(Vector3(36.3, 1.35, 7.72))
				ok = await go(39.0, 10.1, true, false) and await go(48.8, 10.1, true, false)
			if ok:
				for i in 220:
					if level.hale.position.distance_to(level.walker.position) <= 6.0: break
					await step_frames(1)
				level.pick_order("north")
				for i in 900:
					if level.holding: break
					await step_frames(1)
				level.toggle_lamp()
				ok = await go(71.5, 10.1, true, false)
			if ok:
				await use_at(level.kit.core.position)
				ok = await run_spiral_and_exit(true)

		"S3_Cheese_IgnoreHale_Solo":
			for pt in [[31.0, 0.0], [31.0, 4.9], [26.7, 4.9], [25.7, 5.5], [25.7, 7.75], [20.95, 7.75], [20.95, 9.8], [23.85, 9.8]]:
				ok = await go(pt[0], pt[1], false, true)
				if not ok: break
			if ok:
				ok = await go(23.85, 14.12, false, false, Vector3(23.85, 0.11, 13.0))
			if ok:
				for pt in [[25.5, 14.1], [38.9, 14.1], [38.9, 10.0], [36.6, 8.5]]:
					ok = await go(pt[0], pt[1], false, true)
					if not ok: break
			if ok:
				await use_at(Vector3(36.3, 1.35, 7.72))
				ok = await go(48.8, 10.1, true, false) and await go(52.2, 10.1, true, false, Vector3(61.0, 0.0, 10.1))
			if ok:
				ok = await go(70.5, 10.1, true, false, Vector3(61.0, 0.0, 10.1), 1100)
			if ok:
				await use_at(level.kit.core.position)
				ok = await run_spiral_and_exit(true)

		"S4_B4Dark_SouthCatwalk":
			ok = await do_b2_b3_standard(false, true)
			if ok:
				for pt in [[25.5, 14.1], [34.0, 14.1]]:
					ok = await go(pt[0], pt[1])
					if not ok: break
				await use_at(Vector3(34.14, 0.5, 14.67))
				ok = await go(38.9, 14.1) and await go(38.9, 10.0) and await go(36.6, 8.5)
			if ok:
				await use_at(Vector3(36.3, 1.35, 7.72))
				ok = await go(39.0, 10.1, true, false) and await go(48.8, 10.1, true, false)
			if ok:
				level.toggle_lamp()
				for i in 33:
					var pt: Vector3 = level.kit.polar(13.3, PI * (1.0 - i / 32.0), 0.0)
					ok = await go(pt.x, pt.z, true, false)
					if not ok: break
			if ok:
				ok = await go(71.5, 10.1, true, false)
			if ok:
				await use_at(level.kit.core.position)
				ok = await run_spiral_and_exit(true)

		"S5_B4Loft_Metronome_Bridge":
			ok = await do_b2_b3_standard(true, true)
			if ok:
				ok = await go(25.5, 14.1) and await go(29.9, 14.1) and await go(29.9, 16.45) and await go(level.Relay.PORTS[0].x, 16.73)
			if ok:
				await step_frames(15)
				await use_at(level.Relay.PORTS[0])
				await step_frames(52)
				ok = await go(level.Relay.PORTS[1].x, 16.73)
				if ok:
					await use_at(level.Relay.PORTS[1])
					ok = await go(level.Relay.HATCH.x, 16.60)
					if ok:
						await use_at(level.Relay.HATCH)
						ok = await go(39.05, 16.45) and await go(39.05, 14.1) and await go(38.9, 10.0) and await go(36.6, 8.5)
			if ok:
				await use_at(Vector3(36.3, 1.35, 7.72))
				ok = await go(39.0, 10.1, true, false) and await go(48.8, 10.1, true, false)
			if ok:
				await use_at(level.hunter.BAIT)
				ok = await go(71.5, 10.1, false, false, Vector3(61.0, 0.11, 10.1))
			if ok:
				await use_at(level.kit.core.position)
				ok = await run_spiral_and_exit(true)

		"S6_DoubleLamp_Breach":
			ok = await do_b2_b3_standard(false, true)
			if ok:
				for pt in [[25.5, 14.1], [38.9, 14.1], [38.9, 10.0], [36.6, 8.5]]:
					ok = await go(pt[0], pt[1])
					if not ok: break
			if ok:
				await use_at(Vector3(36.3, 1.35, 7.72))
				ok = await go(39.0, 10.1, true, false) and await go(48.8, 10.1, true, false)
			if ok:
				for i in 220:
					if level.hale.position.distance_to(level.walker.position) <= 6.0: break
					await step_frames(1)
				# Intentionally keep BOTH lamps lit and wait at shaft mouth to test Single-Lamp Rule
				for i in 300:
					if level.retry > 0.0: break
					await step_frames(1)

	var out := {
		"scenario": scenario,
		"success": ok and level.retry <= 0.0 and (level.collected or scenario == "S6_DoubleLamp_Breach"),
		"collected": level.collected,
		"finished": level.finished,
		"fail_reason": level.fail_reason,
		"ticks": ticks,
		"duration_s": snappedf(ticks / 60.0, 0.1),
		"oil_left": snappedf(level.oil, 0.1),
		"peak_exposure": snappedf(peak_exposure, 0.01),
		"both_lamp_triggered": level.cues.has("rule_light"),
		"region_seq": region_seq,
		"dialogue_seq": dialogue_seq,
		"action_seq": action_seq,
	}
	print("PROBE_RESULT " + JSON.stringify(out))
	level.queue_free()
	for i in 8:
		await process_frame
	quit(0)
