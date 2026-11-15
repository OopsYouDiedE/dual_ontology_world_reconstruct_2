extends Node
## Gameplay and test fixtures call the same presentation entry point.
const Closeup := preload("res://scenes/components/interaction/EvidenceCloseup.gd")
const EVIDENCE_KINDS := {"e_b_sleeve": "sleeve", "e_b_drag": "drag", "e_b_water": "water", "e_b_ratchet": "ratchet", "e_b_cloth": "cloth", "e_b_boots": "boots", "e_b_seal": "seal", "e_c_copper": "copper", "e_a_grate":"grille"}
var active: Control
signal event_recorded(event: Dictionary)

func begin(parent: Control, kind: String, callback := Callable(), context: Dictionary = {}) -> bool:
	if is_instance_valid(active): return false
	active = Closeup.new()
	active.kind = kind
	active.wrist_anchor = context.get("wrist_anchor")
	active.anchor_camera = context.get("camera")
	active.anchor_container = context.get("container")
	active.observed.connect(func(event: Dictionary): event_recorded.emit(event))
	active.finished.connect(func(success: bool):
		active = null
		if callback.is_valid(): callback.call(success))
	parent.add_child(active)
	return true

func kind_for(evidence_id: String) -> String:
	return str(EVIDENCE_KINDS.get(evidence_id, ""))

func begin_gameplay(host: Control, kind: String, callback := Callable()) -> bool:
	if is_instance_valid(active): return false
	var was_playing: bool = host.eng.s.playing
	var was_cinematic: bool = host._cine
	host.eng.s.playing = false
	host._cine = true
	var context: Dictionary = {}
	if kind == "sleeve":
		var figure: Node3D = host.figures.get("su")
		var body: Node3D = figure.get("_body") if figure != null else null
		var wrist: Node3D = body.get_meta("slot_right_hand",null) if body != null else null
		context = {"wrist_anchor":wrist,"camera":host.cam,"container":host.room_container}
		event_recorded.emit({"phase":"wrist_anchor","available":wrist != null,"actor":"su"})
	var started := begin(host.center,kind,func(success: bool):
		host.eng.s.playing = was_playing
		host._cine = was_cinematic
		if callback.is_valid(): callback.call(success),context)
	if not started:
		host.eng.s.playing = was_playing
		host._cine = was_cinematic
	return started

func cancel() -> void:
	if is_instance_valid(active): active.queue_free()
	active = null
