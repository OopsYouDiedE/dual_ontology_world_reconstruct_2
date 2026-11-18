extends RefCounted
## Resolve player and development launches before loading any scene or save.
const BOOT := "res://scenes/main/Boot.tscn"
const TITLE := "res://scenes/main/Main.tscn"
const STORY := "res://scenes/dual_world/DualWorldMain.tscn"
const SEGMENT := "res://mcp/game/SegmentEntry.tscn"
const WORKBENCH := "res://tools/testing/StoryTest.tscn"

static func argument(args: PackedStringArray, key: String, fallback := "") -> String:
	for raw in args:
		if raw.begins_with(key + "="): return raw.trim_prefix(key + "=")
	return fallback

static func resolve(args: PackedStringArray) -> Dictionary:
	var modes: Array[String] = []
	var parameters := {}
	for raw in args:
		var parts := raw.split("=", true, 1)
		var key := parts[0]
		match key:
			"--dv-snapshot", "--dv-scenario", "--scenario":
				if parameters.has(key): return {"error": "Repeated launch option: " + key}
				if parts.size() != 2 or parts[1].strip_edges().is_empty():
					return {"error": "Enter a file path for " + key + "."}
				parameters[key] = parts[1]
			"--dv-focused-workbench", "--dv-workbench", "--dv-story-direct", "--dv-campaign-lab":
				if parts.size() != 1: return {"error": key + " takes no value."}
				modes.append(key)
	if parameters.has("--dv-snapshot"): modes.append("--dv-snapshot")
	if parameters.has("--dv-scenario"): modes.append("--dv-scenario")
	# The existing --scenario flag selects the workbench too, so old commands
	# and explicit workbench launches agree about which host owns the fixture.
	if parameters.has("--scenario") and "--dv-workbench" not in modes and "--dv-focused-workbench" not in modes:
		modes.append("--dv-workbench")
	if modes.size() > 1: return {"error": "Choose one launch mode: " + ", ".join(modes) + "."}
	var mode := modes[0] if not modes.is_empty() else "title"
	var scene := TITLE
	match mode:
		"--dv-snapshot", "--dv-story-direct": scene = STORY
		"--dv-scenario": scene = SEGMENT
		"--dv-workbench", "--dv-focused-workbench": scene = WORKBENCH
	return {"mode": mode, "scene": scene}
