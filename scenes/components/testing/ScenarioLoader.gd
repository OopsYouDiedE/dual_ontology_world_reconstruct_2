extends RefCounted
## Author fixtures are isolated from campaign saves and are always marked as mocks.
const Yaml := preload("res://tools/building_construction/ArchitectYaml.gd")
const ALLOWED_MODES := ["story", "interaction", "lighting", "building", "deduction", "expression", "mocap"]
var error := ""
var source_path := ""
var configuration: Dictionary = {}

func read(path: String) -> bool:
	error = ""
	source_path = path
	if not FileAccess.file_exists(path): return _fail("Configuration file does not exist")
	var parser := Yaml.new()
	var parsed: Variant = parser.parse(FileAccess.get_file_as_string(path))
	if not parsed is Dictionary: return _fail("Configuration must be a YAML/JSON mapping: " + parser.error)
	return validate(parsed)

func validate(value: Dictionary) -> bool:
	error = ""
	configuration = {}
	if int(value.get("schema_version", 0)) != 1: return _fail("schema_version must be 1")
	if str(value.get("mode", "story")) not in ALLOWED_MODES: return _fail("Unknown test mode")
	if not value.get("mock", {}) is Dictionary: return _fail("mock must be a mapping")
	if not value.get("time", {}) is Dictionary: return _fail("time must be a mapping")
	if typeof(value.get("playing", false)) != TYPE_BOOL: return _fail("playing must be a boolean")
	if value.has("before_beat"):
		if not value.before_beat is String or value.before_beat.strip_edges().is_empty(): return _fail("before_beat must be a beat ID")
		if value.get("mock", {}).has("beat_cursor"): return _fail("Choose before_beat or mock.beat_cursor")
	var clock: Dictionary = value.get("time", {})
	for key in ["day", "hour", "minute"]:
		if clock.has(key) and (typeof(clock[key]) not in [TYPE_INT, TYPE_FLOAT] or float(clock[key]) != floorf(float(clock[key]))): return _fail("time." + key + " must be an integer")
	if int(clock.get("day", 1)) < 1 or int(clock.get("day", 1)) > 5: return _fail("day must be 1..5")
	if int(clock.get("hour", 8)) not in range(24): return _fail("hour must be 0..23")
	if int(clock.get("minute", 0)) not in range(60): return _fail("minute must be 0..59")
	var entry := str(value.get("entry", "exploration"))
	if entry not in ["wake", "exploration", "corridor"]: return _fail("Unknown story entry")
	if entry in ["wake", "corridor"] and (int(clock.get("day", 1)) != 1 or str(value.get("room", "R05")) != "R05"):
		return _fail("Wake and corridor entries start from R05 on Day 1")
	if str(value.get("mode", "story")) == "interaction" and str(value.get("kind", "wardrobe")) not in ["wardrobe", "ratchet", "grille", "hand", "sleeve", "copper", "water", "cloth", "chalk"]: return _fail("Unknown interaction kind")
	for reserved in ["t", "day"]:
		if value.get("mock", {}).has(reserved): return _fail("Set time through the time mapping, not mock." + reserved)
	if value.has("scene"):
		var scene_path := str(value.scene)
		if not scene_path.begins_with("res://") or not scene_path.ends_with(".tscn") or not ResourceLoader.exists(scene_path): return _fail("scene must be an existing project .tscn")
	configuration = value.duplicate(true)
	return true

func _fail(message: String) -> bool:
	error = message
	return false

func state_for(engine: RefCounted) -> Dictionary:
	var state: Dictionary = engine.save_dict()
	var clock: Dictionary = configuration.get("time", {})
	state.t = (int(clock.get("day", 1)) - 1) * 1440 + int(clock.get("hour", 8)) * 60 + int(clock.get("minute", 0))
	state.day = int(clock.get("day", 1))
	state.chapter = 1 if state.day == 1 else 2
	state.room = str(configuration.get("room", "R05"))
	if not engine.d.room_by_id.has(state.room): _fail("Unknown room: " + str(state.room)); return {}
	state.playing = bool(configuration.get("playing", false))
	if configuration.has("before_beat"):
		var id := str(configuration.before_beat)
		if not engine.d.beat_index_by_id.has(id): _fail("Unknown before_beat: " + id); return {}
		state.beat_cursor = engine.d.beat_index_by_id[id]
	var mock: Dictionary = configuration.get("mock", {})
	for key in mock:
		if not state.has(key): _fail("Unknown mock state field: " + str(key)); return {}
		if typeof(state[key]) != typeof(mock[key]) and not (typeof(state[key]) in [TYPE_INT, TYPE_FLOAT] and typeof(mock[key]) in [TYPE_INT, TYPE_FLOAT]):
			_fail("Mock state type mismatch: " + str(key)); return {}
		state[key] = mock[key].duplicate(true) if mock[key] is Dictionary or mock[key] is Array else mock[key]
	if not engine.d.room_by_id.has(str(state.room)): _fail("Unknown mock room"); return {}
	for field in ["evidence", "knowledge", "deductions", "choices", "conflicts", "inspected", "flags", "doors", "beliefs", "relations", "pending_choice", "pending_deduction", "hold", "postponed", "story_gate", "unlocked_terms"]:
		if not state[field] is Dictionary: _fail("Invalid state mapping: " + field); return {}
	for evidence in state.evidence:
		if not engine.d.evidence_by_id.has(str(evidence)): _fail("Unknown evidence mock: " + str(evidence)); return {}
	for knowledge in state.knowledge:
		if not engine.d.know_by_id.has(str(knowledge)): _fail("Unknown knowledge mock: " + str(knowledge)); return {}
	if float(state.beat_cursor) != floorf(float(state.beat_cursor)) or int(state.beat_cursor) < 0 or int(state.beat_cursor) > engine.d.beats.size(): _fail("beat_cursor out of bounds"); return {}
	return state
