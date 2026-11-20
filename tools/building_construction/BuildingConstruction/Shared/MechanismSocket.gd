extends Node
## An existing placed object can host an existing activity. Keep the native
## camera, picking, timing and rule state together, in its own view. A socket
## never imports a room into the building physics world or takes the OS cursor.
signal completed
signal dismissed
const WEST := "res://scenes/mechanisms/Visit.gd"
const DIRECTORY := "res://scenes/mechanisms/Catalog.gd"
const FOLIO := "res://scenes/instrument_folio/Folio.gd"
const VESPER := "res://scenes/blue_prince_lab/vesper/VesperVisit.gd"
@export var activity := ""
@export var seed_value := 0
@export var target: NodePath
var state: Dictionary = {}
var achieved := false
var pressed_state := false
var panel: VBoxContainer
var view: Control

static func choices() -> Dictionary:
	var result := {"":"No activity", "vesper":"Vesper Index"}
	if ResourceLoader.exists(WEST) and ResourceLoader.exists(DIRECTORY):
		var catalog = load(DIRECTORY)
		for key in catalog.ROOMS: result["west:"+key] = "West wing / " + str(catalog.ROOMS[key][0])
	if ResourceLoader.exists(FOLIO):
		var folio = load(FOLIO)
		for i in folio.CASES.size(): result["folio:"+str(i)] = "Folio / " + str(folio.CASES[i].TITLE)
	return result

func _ready() -> void:
	set_process(false)
	for sig in [&"running_changed", &"open_changed"]:
		if get_parent().has_signal(sig): get_parent().connect(sig,drive)

func configure(key: String) -> void:
	close()
	activity = key
	state.clear()
	achieved = false

func drive(active: bool) -> void:
	var output := get_node_or_null(target) if not target.is_empty() else null
	if not output: return
	# Idempotent setters terminate reciprocal links and keep coupled latches in phase.
	if output.has_method("set_open"):
		if output.is_open != active: output.set_open(active)
	elif output.has_method("set_angle_checked"):
		var angle: float = open_angle(output)
		output.set_angle_checked(angle if active else 0.)
	elif "is_running" in output and output.has_method("interact") and output.is_running != active:
		output.interact()
	elif "running" in output and output.has_method("interact") and output.running != active:
		output.interact()

static func open_angle(node: Node3D) -> float:
	var low: float = node.minimum_angle if "minimum_angle" in node else node.min_angle
	var high: float = node.maximum_angle if "maximum_angle" in node else node.max_angle
	return low if absf(low)>absf(high) else high

func press() -> void:
	if not get_parent().has_method("pulse"): return
	get_parent().pulse()
	pressed_state = not pressed_state
	drive(pressed_state)

func activate(parent: Control) -> bool:
	if is_instance_valid(panel) or not choices().has(activity) or activity.is_empty(): return false
	# The native west-wing reader expects a visible pointer. Leave a captured
	# pointer under its game's ownership until that host opens its own menu.
	if activity.begins_with("west:") and Input.mouse_mode != Input.MOUSE_MODE_VISIBLE: return false
	panel = VBoxContainer.new()
	parent.add_child(panel)
	panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var back := Button.new(); back.text = "Return to assembly"; back.focus_mode = Control.FOCUS_NONE
	panel.add_child(back); back.pressed.connect(close)
	var frame := SubViewportContainer.new(); frame.stretch = true; frame.size_flags_vertical = Control.SIZE_EXPAND_FILL
	panel.add_child(frame)
	var vp := SubViewport.new(); vp.own_world_3d = true; frame.add_child(vp)
	if activity.begins_with("west:"):
		view = load(WEST).new(); view.seed_value = seed_value; view.rooms = state
		view.bells.volume_linear = 0.; vp.add_child(view); view.show_room(activity.trim_prefix("west:"))
	elif activity.begins_with("folio:"):
		view = load(FOLIO).new(); view.seed_value = seed_value; view.leaves = state
		view.audio.volume_linear = 0.; vp.add_child(view); view.choose(int(activity.trim_prefix("folio:")))
	else:
		view = load(VESPER).new()
		if state.has("rules"): view.puzzle.rules = state.rules
		state.rules = view.puzzle.rules
		view.puzzle.return_requested.connect(close, CONNECT_DEFERRED)
		view.puzzle.recovered.connect(_complete)
		vp.add_child(view)
	set_process(true)
	return true

func _process(_delta: float) -> void:
	if not is_instance_valid(view): return
	if activity.begins_with("west:"):
		if view.id != activity.trim_prefix("west:"): close(); return
		if view.unit.solved: _complete()
	elif activity.begins_with("folio:"):
		if view.index != int(activity.trim_prefix("folio:")): close(); return
		if view.leaves[view.index].solved: _complete()

func _complete() -> void:
	if achieved: return
	achieved = true
	drive(true)
	completed.emit()

func close() -> void:
	if not is_instance_valid(panel): return
	set_process(false)
	panel.hide()
	panel.queue_free()
	panel = null
	view = null
	dismissed.emit()

func _exit_tree() -> void:
	close()
