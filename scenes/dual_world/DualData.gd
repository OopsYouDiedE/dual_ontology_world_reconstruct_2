extends RefCounted
## 《安眠者有福 · 门的这一侧》静态数据（由 web 整合版的数据层导出为 JSON）。
## 世界事实只有一份；主观词义、知识门槛、证物的「当前读法／客观读法」都在这里声明，
## 引擎（DualEngine.gd）只读取，不在代码里硬编码剧情。

const PATH := "res://assets/data/dual_world/dual_world.json"

static var _cache: RefCounted = null

var raw: Dictionary = {}
var rooms: Array = []
var room_by_id: Dictionary = {}
var doors: Array = []
var actors: Array = []
var actor_by_id: Dictionary = {}
var humans: Array = []
var terms: Dictionary = {}
var lex_defaults: Dictionary = {}
var lex_overrides: Dictionary = {}
var knowledge: Array = []
var know_by_id: Dictionary = {}
var evidence: Array = []
var evidence_by_id: Dictionary = {}
var evidence_by_room: Dictionary = {}
var conflicts: Array = []
var conflict_by_id: Dictionary = {}
var deductions: Array = []
var deduction_by_id: Dictionary = {}
var phases: Array = []
var beats: Array = []
var relation_pairs: Array = []
var endings: Dictionary = {}
var timeline: Array = []
var contract: Array = []
var map_groups: Array = []
var rig_spec: Dictionary = {}


static func get_data() -> RefCounted:
	if _cache == null:
		_cache = load("res://scenes/dual_world/DualData.gd").new()
		_cache.load_file(PATH)
	return _cache


func load_file(path: String) -> bool:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		push_error("DualData: 无法打开 " + path)
		return false
	var parsed: Variant = JSON.parse_string(f.get_as_text())
	if not parsed is Dictionary:
		push_error("DualData: JSON 解析失败 " + path)
		return false
	raw = parsed
	rooms = raw.get("ROOMS", [])
	doors = raw.get("DOORS", [])
	actors = raw.get("ACTORS", [])
	humans = raw.get("HUMANS", [])
	terms = raw.get("TERMS", {})
	lex_defaults = raw.get("LEX_DEFAULTS", {})
	lex_overrides = raw.get("LEX_OVERRIDES", {})
	knowledge = raw.get("KNOWLEDGE", [])
	evidence = raw.get("EVIDENCE", [])
	conflicts = raw.get("CONFLICTS", [])
	deductions = raw.get("DEDUCTIONS", [])
	phases = raw.get("PHASES", [])
	beats = raw.get("BEATS", [])
	relation_pairs = raw.get("RELATION_PAIRS", [])
	endings = raw.get("ENDINGS", {})
	timeline = raw.get("TIMELINE", [])
	contract = raw.get("CONTRACT", [])
	map_groups = raw.get("MAP_GROUPS", [])
	rig_spec = raw.get("RIG_SPEC", {})
	for r in rooms: room_by_id[r.id] = r
	for a in actors: actor_by_id[a.id] = a
	for k in knowledge: know_by_id[k.id] = k
	for e in evidence:
		evidence_by_id[e.id] = e
		if not evidence_by_room.has(e.room): evidence_by_room[e.room] = []
		evidence_by_room[e.room].append(e)
	for c in conflicts: conflict_by_id[c.id] = c
	for d in deductions: deduction_by_id[d.id] = d
	return true


## 某人对某词取的义项 id（未写明者取默认义项）。
func sense_of(actor_id: String, term: String) -> String:
	var o: Dictionary = lex_overrides.get(actor_id, {})
	return str(o.get(term, lex_defaults.get(term, "")))


func sense_label(actor_id: String, term: String) -> String:
	var sid := sense_of(actor_id, term)
	var senses: Dictionary = terms.get(term, {}).get("senses", {})
	return str(senses.get(sid, {}).get("label", sid))


func actor_name(id: String) -> String:
	return str(actor_by_id.get(id, {}).get("name", id))


static func t_minutes(day: int, hour: int, minute: int = 0) -> int:
	return (day - 1) * 1440 + hour * 60 + minute


static func pair_key(a: String, b: String) -> String:
	return a + "|" + b if a < b else b + "|" + a
