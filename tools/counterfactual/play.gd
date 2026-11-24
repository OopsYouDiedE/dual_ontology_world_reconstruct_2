extends SceneTree
## Feed the canonical sparse receipt on Godot's actual physics signal, or run it headlessly at full speed.

const Model := preload("res://scenes/physics_lab/counterfactual/Model.gd")
const Replay := preload("res://tools/counterfactual/Replay.gd")

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var path := "res://tools/counterfactual/golden.json"
	var id := "staged_jack_rising_weight"
	var paced := false
	var trace := false
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--file="):
			path = arg.trim_prefix("--file=")
		elif arg.begins_with("--route="):
			id = arg.trim_prefix("--route=")
		elif arg == "--pace":
			paced = true
		elif arg == "--trace":
			trace = true
		else:
			printerr("Unknown replay option: ", arg)
			quit(2)
			return
	var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not data is Dictionary:
		printerr("Expected a JSON object: ", path)
		quit(2)
		return
	var route: Dictionary = data
	if data.has("routes"):
		route = {}
		for candidate in data.routes:
			if candidate.id == id:
				route = candidate
				break
	if not route.get("inputs") is Array:
		printerr("Replay has no inputs: ", id)
		quit(2)
		return
	var commands := Replay.compile(route.inputs)
	if commands.has("error"):
		printerr(commands.error)
		quit(2)
		return
	var until := maxi(commands.last_tick, int(route.get("win_tick", 0))) + Model.PROOF_TICKS + Model.NOTICE_TICKS
	Engine.physics_ticks_per_second = Model.HZ
	var m := Model.new()
	var begin := Time.get_ticks_usec()
	for t in range(1, until + 1):
		if paced:
			await physics_frame
		var input: Dictionary = commands.ticks.get(t, {})
		m.step(input)
		var frame := m.observe()
		if trace:
			print(JSON.stringify({"input": input, "frame": frame}))
		elif frame.event.tick == t and frame.event.id in ["marked", "spliced", "boarding", "crossed", "blocked"]:
			print("[", t, "] ", frame.event.text)
		if frame.won:
			var expected := int(route.get("win_tick", t))
			var match_expected: bool = t == expected and t >= commands.last_tick
			print("%s: crossing at tick %d, %.3f wall seconds, expected tick %d." %
				[route.get("id", "Replay"), t, (Time.get_ticks_usec() - begin) / 1_000_000.0, expected])
			quit(0 if match_expected else 1)
			return
	printerr("Far Landing was not reached by tick ", until, ".")
	quit(1)
