extends Label
## Read-only display of the native FreeSO camp feed. Never controls the VM.

const SNAPSHOT_SCHEMA := "freeso.lot-snapshot.v1"
const POLL_SECONDS := 1.0
const STALE_SECONDS := 6.0 # The native hook publishes at most once per second.
const MAX_BYTES := 16 * 1024 * 1024
const RESIDENT_ROLES := {"owner": "owner", "build_roommate": "build roommate", "roommate": "roommate"}

var _active := false
var _path := ""
var _remaining := 0.0
var _pid := -1
var _tick := -1
var _last_progress := 0.0
var _advancing := false


func _ready() -> void:
	autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	visible = _active
	set_process(_active)


func set_camp(active: bool, json_path: String) -> void:
	if _active == active and _path == json_path:
		return
	_active = active
	_path = json_path
	_reset_tracking()
	visible = active
	set_process(active)
	text = ""
	if active:
		_poll_feed()
	_remaining = POLL_SECONDS


func _process(delta: float) -> void:
	_remaining -= delta
	if _remaining <= 0.0:
		_remaining = POLL_SECONDS
		_poll_feed()


func _poll_feed() -> void:
	if _path.is_empty() or not FileAccess.file_exists(_path):
		_reset_tracking()
		text = "Camp watch | Missing live FreeSO feed."
		return
	var modified := FileAccess.get_modified_time(_path)
	var file := FileAccess.open(_path, FileAccess.READ)
	if file == null or file.get_length() > MAX_BYTES:
		text = "Camp watch | Live feed unreadable."
		return
	var parser := JSON.new()
	if parser.parse(file.get_as_text()) != OK:
		text = "Camp watch | Live feed unreadable."
		return
	var age := Time.get_unix_time_from_system() - float(modified)
	var now := Time.get_ticks_msec() / 1000.0
	text = _observe_snapshot(parser.data, age, now)


func _observe_snapshot(snapshot: Variant, file_age: float, now: float) -> String:
	if not snapshot is Dictionary or snapshot.get("schema") != SNAPSHOT_SCHEMA:
		_reset_tracking()
		return "Camp watch | Unrecognized snapshot."
	var source: Variant = snapshot.get("source")
	if not source is Dictionary or source.get("kind") != "live-vm" or source.get("room_id") != "camp":
		_reset_tracking()
		return "Camp watch | Waiting for the live FreeSO camp feed."
	if not _whole(source.get("pid"), 1) or not _whole(snapshot.get("tick"), 0) or not snapshot.get("avatars") is Array:
		_reset_tracking()
		return "Camp watch | Incomplete live camp feed."
	if file_age < -STALE_SECONDS or file_age > STALE_SECONDS:
		_reset_tracking()
		return "Camp watch | Stale live feed (old snapshot timestamp)."
	var pid := int(source.pid)
	var tick := int(snapshot.tick)
	if pid != _pid or tick < _tick:
		_pid = pid
		_tick = tick
		_last_progress = now
		_advancing = false
	elif tick > _tick:
		_tick = tick
		_last_progress = now
		_advancing = true
	if now - _last_progress > STALE_SECONDS:
		return "Camp watch | Stale live feed (VM tick stopped)."
	if not _advancing:
		return "Camp watch | Waiting for the FreeSO VM tick to advance."
	return _render_residents(snapshot.avatars, tick)


func _render_residents(avatars: Array, tick: int) -> String:
	var residents := PackedStringArray()
	var other := PackedStringArray()
	for avatar: Variant in avatars:
		if not avatar is Dictionary or not avatar.get("placed", false) is bool or not avatar.get("placed", false) or not _whole(avatar.get("object_id"), 0):
			continue
		var membership := _clean(avatar.get("lot_membership"))
		var name := _clean(avatar.get("name"))
		if name.is_empty():
			name = "Sim #%d" % int(avatar.object_id)
		var action := _activity_text(avatar.get("activity"))
		if RESIDENT_ROLES.has(membership):
			residents.append("%s (%s): %s" % [name, RESIDENT_ROLES[membership], action])
		else:
			var role := "not listed as a resident" if membership == "not_listed" else "membership unavailable"
			other.append("%s (%s): %s" % [name, role, action])
	var lines := PackedStringArray(["Camp watch | Live FreeSO tick %d" % tick])
	lines.append("Residents: " + ("; ".join(residents) if not residents.is_empty() else "none identified on the lot."))
	if not other.is_empty():
		lines.append("Other present Sims: " + "; ".join(other))
	return "\n".join(lines)


func _activity_text(activity: Variant) -> String:
	if not activity is Dictionary:
		return "activity unavailable"
	match activity.get("status"):
		"no_active_action":
			return "no active interaction"
		"active":
			var action: Variant = activity.get("action")
			if not action is Dictionary:
				return "action details unavailable"
			var title := _clean(action.get("name"))
			if title.is_empty():
				title = "active action (name unavailable)"
			if action.get("freewill_evidence") == "vm_find_best_action":
				title += " [VM free-will selection]"
			return title
	return "activity unavailable"


func _reset_tracking() -> void:
	_pid = -1
	_tick = -1
	_last_progress = 0.0
	_advancing = false


static func _whole(value: Variant, minimum: int) -> bool:
	return (value is int or value is float) and value >= minimum and value <= 9007199254740991 and floorf(value) == value


static func _clean(value: Variant) -> String:
	if not value is String:
		return ""
	return value.replace("\r", " ").replace("\n", " ").strip_edges().left(90)
