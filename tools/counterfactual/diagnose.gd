extends SceneTree
## A white-box reduction probe, derived from the ruler equations; no reads of golden.json.

const Model := preload("res://scenes/physics_lab/counterfactual/Model.gd")
const Replay := preload("res://tools/counterfactual/Replay.gd")

func _initialize() -> void:
	var started := Time.get_ticks_usec()
	var overformed := _recipe(0, 36, 0)  # Full cable on the unloaded hot seat, then maximum ballast.
	var over := _drive(overformed, 720)
	print("Saturation control: ", over.retained, ", ", over.local, ", won=", over.won)
	# At nominal force 99, with one historic ballast B used for forming and proof,
	# a centered shoe gives 99 ~= 2B + (64 - B/2 - 18) -> B ~= 35. Skip the brake.
	var tries := 0
	for b in [35, 36, 34, 33, 32, 31, 30, 29, 28]:
		for phase_delay in [0, 30, 60, 90]:
			tries += 1
			var recipe := _recipe(b, b, phase_delay)
			var end := _drive(recipe, 850)
			if end.won:
				var result := {"id": "coupled_centering_attack", "inputs": recipe, "win_tick": end.tick}
				print("Fast reduction: ballast=%d, extra phase delay=%d, brake=0, attempts=%d, won at tick %d (%.2f seconds at 60 Hz)." %
					[b, phase_delay, tries, end.tick, float(end.tick) / Model.HZ])
				print("Headless model sweep including control: %.1f ms." % ((Time.get_ticks_usec() - started) / 1000.0))
				print(JSON.stringify(result))
				if "--robustness" in OS.get_cmdline_user_args():
					var phase_started := Time.get_ticks_usec()
					var successes: Array[int] = []
					for delay in range(Model.DRUM_TICKS):
						if _drive(_recipe(b, b, delay), 850).won:
							successes.append(delay)
					print("Same one-setting attack: %d/%d exterior phases won in %.1f ms of sweep time." %
						[successes.size(), Model.DRUM_TICKS, (Time.get_ticks_usec() - phase_started) / 1000.0])
				quit()
				return
	printerr("Reduced probe did not win; no broader search was performed.")
	quit(1)

func _edge(rows: Array, at: int, press: String, target: String = "") -> void:
	rows.append({"tick": at, "press": press, "target": target})

func _hold(rows: Array, at: int, control: String, count: int) -> int:
	if count:
		rows.append({"tick": at, "hold": control, "for": count})
	return at + count

func _walk(rows: Array, at: int, target: String) -> int:
	_edge(rows, at, "move", target)
	return at + Model.WALK_TICKS

func _recipe(form_ballast: int, proof_ballast: int, phase_delay: int) -> Array:
	var rows := []
	var t := _walk(rows, 1, "jack")
	t = _walk(rows, _hold(rows, t, "haul", Model.MAX_PRELOAD), "yoke")
	if form_ballast:
		t = _walk(rows, _hold(rows, _walk(rows, t, "weight"), "raise", form_ballast), "yoke")
	t = _walk(rows, _walk(rows, t, "jack"), "start")
	_edge(rows, t, "mark")
	t = _walk(rows, t + 1, "kiln")
	_edge(rows, t, "cut_pin")
	# Full torch heat; the remaining warm ticks settle the target during the walk and rewind warning.
	t = _walk(rows, _hold(rows, t + Model.NOTICE_TICKS, "heat", int(Model.MAX_HEAT / 2.0)), "start")
	_edge(rows, t, "rewind_bench")
	t = _walk(rows, _walk(rows, t + Model.NOTICE_TICKS + 1, "kiln"), "yoke")
	if proof_ballast > form_ballast:
		t = _walk(rows, _hold(rows, _walk(rows, t, "weight"), "raise", proof_ballast - form_ballast), "yoke")
	t += phase_delay
	_edge(rows, t, "arm")
	t = _walk(rows, t + 1, "weight")
	_edge(rows, t + 1, "queue_cross")
	return rows

func _drive(rows: Array, until: int) -> Dictionary:
	var m := Model.new()
	var commands: Dictionary = Replay.compile(rows).ticks
	for t in range(1, until + 1):
		m.step(commands.get(t, {}))
	return m.observe()
