extends Node
## Runtime checkpoints retain presentation state as well as the rule-engine save.
## Only immutable Variant data crosses the background writer boundary.
const Source := preload("res://mcp/CaptureSource.gd")
const PROJECT := "dual_ontology_world_reconstruct_2"
const FORMAT := "story-checkpoint-v1"
const DEFAULT_PATH := "res://.runtime/checkpoints/latest.json"
const HOST_FIELDS := ["az", "pitch", "dist", "det_pos", "det_path", "_door_passage", "_transit", "_wake_timer", "_wake_total", "_wake_y0", "_wake_from", "_wake_to", "_wake_bed", "_wake_custom", "_wake_edge", "_sub_clock", "_sub_until", "_sub_queue", "_speaker", "_det_talk", "_cine", "skip_subtitles", "_chapter_dismissed", "_ending_dismissed"]
const OPENING_FIELDS := ["phase", "focus", "chrome_shown", "_pt", "_clock", "_talk_seen", "_talk_idle", "_busy_item", "_pending_exit", "_all_seen_said", "_free_t", "_head"]
const CORRIDOR_FIELDS := ["phase", "_pt", "_clock", "_line", "_focus", "_az", "_pitch", "_dist", "_target", "_joined", "_busy_item", "_free_t", "_enter_pending"]
const KITCHEN_FIELDS := ["phase", "focus", "chrome_shown", "_clock", "_free_t", "_busy_item"]
const EXTRA_HOST_FIELDS := ["_inspect_intent", "_intro_pending"]
var host: Control
var output_path := ""
var error := ""
var restored := false
var restoring := false
var _elapsed := 0.0
var _task := -1
var _sequence := 0
var _write_result := OK
var _stop_file := ""
var automatic := true
var finalized := false
var recovery_path := ""
signal saved(path: String)
signal loaded(path: String)

static func argument(key: String, fallback := "") -> String:
	for raw in OS.get_cmdline_user_args():
		if raw.begins_with(key + "="): return raw.trim_prefix(key + "=")
	return fallback

func bind(content: Control) -> void:
	host = content
	var project_root := ProjectSettings.globalize_path("res://").simplify_path().trim_suffix("/")
	if project_root.get_file() != PROJECT or OS.get_process_id() <= 0:
		error = "Checkpoint host identity rejected"
		get_tree().quit(2)
		return
	output_path = Source.project_output(argument("--dv-checkpoint-output", DEFAULT_PATH))
	automatic = argument("--dv-checkpoint-auto", "true") == "true"
	_stop_file = Source.project_output(argument("--dv-checkpoint-stop", "res://.runtime/checkpoints/interrupt.request"))
	get_tree().auto_accept_quit = false
	process_mode = Node.PROCESS_MODE_ALWAYS
	add_to_group("lifecycle_hosts")
	if not get_tree().root.close_requested.is_connected(_close_requested): get_tree().root.close_requested.connect(_close_requested)
	# This also runs for a directly instantiated production scene (MCP / editor).
	var resume := argument("--dv-snapshot")
	if not resume.is_empty(): restored = restore_file(resume)

func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_F6:
		save_now(output_path.get_base_dir() + "/manual-" + str(Time.get_unix_time_from_system()).replace(".", "-") + ".json")
		get_viewport().set_input_as_handled()

func _process(delta: float) -> void:
	if restoring or not is_instance_valid(host) or host.eng == null: return
	_poll_writer()
	_elapsed += delta
	if not _stop_file.is_empty() and FileAccess.file_exists(_stop_file) and FileAccess.get_file_as_string(_stop_file).strip_edges() == str(OS.get_process_id()):
		DirAccess.remove_absolute(_stop_file)
		preload("res://scenes/components/shared/HostLifecycle.gd").quit(get_tree())
	elif automatic and _elapsed >= 1.0 and _task < 0:
		_elapsed = 0.0
		queue_save()

func _close_requested() -> void:
	preload("res://scenes/components/shared/HostLifecycle.gd").quit(get_tree())

func begin_shutdown() -> void:
	if finalized: return
	save_now()
	finalized = true
	set_process(false)

func wait_for_shutdown() -> void:
	_wait_writer()

func _exit_tree() -> void:
	_wait_writer()

func _poll_writer() -> void:
	if _task >= 0 and WorkerThreadPool.is_task_completed(_task):
		WorkerThreadPool.wait_for_task_completion(_task)
		_task = -1
		if _write_result != OK: error = "Checkpoint write failed: " + error_string(_write_result)
		else: saved.emit(output_path)

func _wait_writer() -> void:
	if _task >= 0:
		WorkerThreadPool.wait_for_task_completion(_task)
		_task = -1

func queue_save() -> bool:
	if output_path.is_empty() or restoring or _task >= 0: return false
	var snapshot := capture()
	if snapshot.is_empty(): return false
	_sequence += 1
	var sequence := _sequence
	var path := output_path
	_task = WorkerThreadPool.add_task(func(): _write_result = write_snapshot(path, snapshot, sequence))
	return true

func save_now(path := "") -> bool:
	_wait_writer()
	var target := output_path if path.is_empty() else Source.project_output(path)
	if target.is_empty(): return false
	_sequence += 1
	_write_result = write_snapshot(target, capture(), _sequence)
	if _write_result != OK:
		error = "Checkpoint write failed: " + error_string(_write_result)
		return false
	saved.emit(target)
	return true

static func write_snapshot(path: String, snapshot: Dictionary, sequence: int) -> Error:
	if snapshot.is_empty(): return ERR_INVALID_DATA
	var directory_error := DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	if directory_error != OK: return directory_error
	var bytes := var_to_bytes(snapshot)
	var checksum := HashingContext.new()
	checksum.start(HashingContext.HASH_SHA256)
	checksum.update(bytes)
	var envelope := {"format": FORMAT, "project": PROJECT, "sequence": sequence,
		"created_at": Time.get_datetime_string_from_system(false, true), "room": snapshot.engine.room,
		"stage": snapshot.presentation.get("controller", "room"), "host_pid": snapshot.source.process_id,
		"acceptance_eligible": false, "sha256": checksum.finish().hex_encode(), "payload": Marshalls.raw_to_base64(bytes)}
	var temporary := path + ".pending"
	var file := FileAccess.open(temporary, FileAccess.WRITE)
	if file == null: return FileAccess.get_open_error()
	file.store_string(JSON.stringify(envelope))
	file.flush()
	var write_error := file.get_error()
	file.close()
	if write_error != OK: return write_error
	# A full previous generation survives interruption during replacement.
	if FileAccess.file_exists(path):
		var backup_error := DirAccess.copy_absolute(path, path + ".previous")
		if backup_error != OK: return backup_error
	return DirAccess.rename_absolute(temporary, path)

func read_snapshot(path: String) -> Dictionary:
	recovery_path = ""
	var value := _read_exact(path)
	if value.is_empty() and FileAccess.file_exists(path + ".previous"):
		value = _read_exact(path + ".previous")
		if not value.is_empty(): recovery_path = path + ".previous"
	return value

func _read_exact(path: String) -> Dictionary:
	error = ""
	var absolute := Source.project_output(path)
	if absolute.is_empty(): error = "Checkpoint must belong to this project"; return {}
	if not FileAccess.file_exists(absolute): error = "Checkpoint file missing"; return {}
	var parser := JSON.new()
	if parser.parse(FileAccess.get_file_as_string(absolute)) != OK or not parser.data is Dictionary:
		error = "Invalid checkpoint JSON"; return {}
	var envelope: Dictionary = parser.data
	if envelope.get("format") != FORMAT or envelope.get("project") != PROJECT:
		error = "Checkpoint project or format mismatch"; return {}
	var bytes := Marshalls.base64_to_raw(str(envelope.get("payload", "")))
	var checksum := HashingContext.new()
	checksum.start(HashingContext.HASH_SHA256)
	checksum.update(bytes)
	if checksum.finish().hex_encode() != envelope.get("sha256"):
		error = "Checkpoint checksum mismatch"; return {}
	var value: Variant = bytes_to_var(bytes)
	if not value is Dictionary or not value.get("engine") is Dictionary or not value.get("presentation") is Dictionary:
		error = "Checkpoint state missing"; return {}
	var p: Dictionary = value.presentation
	if str(p.get("controller", "")) not in ["room", "opening", "corridor", "kitchen"] or not host.data.room_by_id.has(str(p.get("room_loaded", ""))):
		error = "Checkpoint presentation room/controller invalid"; return {}
	if not p.get("host") is Dictionary or not p.get("camera") is Dictionary or not p.get("actors") is Dictionary or not p.get("props") is Dictionary or not p.get("ui") is Dictionary or not p.get("detective") is Dictionary:
		error = "Checkpoint presentation fields missing"; return {}
	if not p.camera.get("transform") is Transform3D or not p.host.get("det_pos") is Vector2 or not p.host.get("det_path") is Array:
		error = "Checkpoint presentation types invalid"; return {}
	if p.controller != "room" and not p.get("controller_state") is Dictionary:
		error = "Checkpoint controller state missing"; return {}
	if int(value.get("source", {}).get("process_id", -1)) != int(envelope.get("host_pid", -2)):
		error = "Checkpoint host PID mismatch"; return {}
	var current_root := ProjectSettings.globalize_path("res://").simplify_path().trim_suffix("/").replace("\\", "/").to_lower()
	if str(value.get("source", {}).get("project_root", "")).replace("\\", "/").to_lower().trim_suffix("/") != current_root:
		error = "Checkpoint belongs to a different project directory"; return {}
	var candidate = host.Engine_.new(host.data)
	if not host.data.room_by_id.has(str(value.engine.get("room", ""))) or not candidate.load_dict(value.engine):
		error = "Checkpoint rule state invalid"; return {}
	return value

func capture() -> Dictionary:
	if not is_instance_valid(host) or host.eng == null or not is_instance_valid(host.cam) or not host.cam.is_inside_tree(): return {}
	var presentation := {"controller": "room", "host": _fields(host, HOST_FIELDS + EXTRA_HOST_FIELDS), "room_loaded": host._room_loaded,
		"camera": {"transform": host.cam.global_transform, "fov": host.cam.fov, "near": host.cam.near},
		"actors": {}, "props": {}, "ui": {}, "designs": host.designs.duplicate(true), "modal_checks": []}
	for checkbox in host.modal.find_children("*", "CheckBox", true, false):
		presentation.modal_checks.append({"text": checkbox.text, "pressed": checkbox.button_pressed})
	for id in host.figures:
		var actor: Node = host.figures[id]
		if is_instance_valid(actor): presentation.actors[id] = _actor(actor)
	if is_instance_valid(host.det): presentation["detective"] = _actor(host.det)
	for kind in host.evidence_presentations:
		var prop: Node = host.evidence_presentations[kind]
		if is_instance_valid(prop):
			presentation.props[kind] = {"progress": prop.progress, "completed": prop.completed, "nodes": _node_states(prop)}
			var original: Node = prop.get("_original")
			if is_instance_valid(original): presentation.props[kind]["original_nodes"] = _node_states(original)
	for key in ["top_bar", "left_card", "drawer", "room_hint", "subtitle", "sub_name", "sub_next", "fade_rect"]:
		var node: Control = host.get(key)
		var state := {"visible": node.visible, "modulate": node.modulate}
		if node is Label: state["text"] = node.text
		presentation.ui[key] = state
	if is_instance_valid(host.gathering) and host.gathering.active:
		presentation.controller = "corridor"
		presentation["controller_state"] = _fields(host.gathering, CORRIDOR_FIELDS)
		presentation["items"] = _items(host.gathering._items)
		presentation["to_room"] = host.gathering._to_room
	elif is_instance_valid(host.kitchen) and host.kitchen.active:
		presentation.controller = "kitchen"
		presentation["controller_state"] = _fields(host.kitchen, KITCHEN_FIELDS)
		presentation["items"] = _items(host.kitchen._items)
		if is_instance_valid(host.kitchen._order_replay): presentation["reconstruction"] = host.kitchen._order_replay.checkpoint_state()
	elif is_instance_valid(host.opening) and host.opening.active:
		presentation.controller = "opening"
		presentation["controller_state"] = _fields(host.opening, OPENING_FIELDS)
		presentation["items"] = _items(host.opening._items)
		presentation["rig"] = _fields(host.opening._rig, ["sit", "head_yaw", "head_pitch", "head_roll"])
	if is_instance_valid(host.interactions.active): presentation["interaction"] = host.interactions.active.checkpoint_state()
	return {"source": Source.identity(get_tree()), "engine": host.eng.save_dict(), "presentation": presentation,
		"session": {"restored": restored, "frame": Engine.get_process_frames(), "unix_time": Time.get_unix_time_from_system()}}

func restore_file(path: String) -> bool:
	var snapshot := read_snapshot(path)
	if snapshot.is_empty(): return false
	finalized = false
	restoring = true
	host._stop_exploration()
	host._finish_transit_now()
	if host._fade_tween != null: host._fade_tween.kill()
	host._clear_modal()
	host.modal.visible = false
	host._modal_key = ""
	var p: Dictionary = snapshot.presentation
	host.eng.load_dict(snapshot.engine)
	host.designs = p.get("designs", {}).duplicate(true)
	host._set_view("room")
	host._build_room(str(p.room_loaded))
	host._det_to_home()
	var controller: Node
	match str(p.controller):
		"opening":
			host.det.set_pose("lie")
			host.show_intro = true
			host._start_opening()
			controller = host.opening
		"corridor":
			host.start_gathering(str(p.get("to_room", "B-P")))
			controller = host.gathering
			if host._fade_tween != null: host._fade_tween.kill()
			if p.controller_state.phase != "fadeout":
				controller._setup_stage()
				if host._fade_tween != null: host._fade_tween.kill()
				if p.controller_state.phase == "free": controller._enter_free()
				elif p.controller_state.phase == "card": controller._show_card()
		"kitchen":
			host.start_kitchen_exploration()
			controller = host.kitchen
			if p.controller_state.phase == "free": controller._enter_free()
	if is_instance_valid(controller):
		_apply_fields(controller, p.controller_state)
		_apply_items(controller._items, p.get("items", {}))
		if p.has("rig"): _apply_fields(controller._rig, p.rig)
	# Reconstruct callbacks from explicit intents; Callables never enter the file.
	_apply_fields(host, p.host)
	host.det_done = Callable()
	if bool(host._transit.get("active", false)):
		match str(host._transit.phase):
			"exit": host.det_done = func(): host._door_passage.clear(); host._transit_exit_done()
			"fade": host._fade(1.0, 0.22, host._transit_swap)
			"enter": host.det_done = func(): host._door_passage.clear(); host._transit_done()
	elif str(p.controller) == "kitchen" and str(controller.phase) == "enter":
		host.det_done = func(): host._door_passage.clear(); controller._enter_free()
	elif is_instance_valid(controller) and int(controller.get("_busy_item")) >= 0 and not p.has("interaction"):
		var index := int(controller._busy_item)
		host.det_done = func(): controller._arrive(index)
	elif not host._inspect_intent.is_empty() and not p.has("interaction"):
		var evidence_id: String = host._inspect_intent
		host.det_done = func(): host._inspect_arrived(evidence_id)
	for id in p.actors:
		if host.figures.has(id) and is_instance_valid(host.figures[id]): _apply_actor(host.figures[id], p.actors[id])
	_apply_actor(host.det, p.detective)
	for kind in p.props:
		var prop: Node = host.evidence_presentations.get(kind)
		if is_instance_valid(prop):
			prop.progress = float(p.props[kind].progress)
			prop.completed = bool(p.props[kind].completed)
			_apply_nodes(prop, p.props[kind].nodes)
			var original: Node = prop.get("_original")
			if is_instance_valid(original): _apply_nodes(original, p.props[kind].get("original_nodes", {}))
	for key in p.ui:
		_apply_fields(host.get(key), p.ui[key])
	host.cam.global_transform = p.camera.transform
	host.cam.fov = p.camera.fov
	host.cam.near = p.camera.near
	if p.has("interaction"):
		host.eng.s.playing = bool(p.interaction.return_playing)
		host._cine = bool(p.interaction.return_cinematic)
		var index := int(controller._busy_item) if is_instance_valid(controller) else -1
		if index >= 0:
			controller._busy_item = -1
			controller._arrive(index)
		elif not host._inspect_intent.is_empty():
			var evidence_id: String = host._inspect_intent
			host.interactions.begin_gameplay(host, str(p.interaction.kind), func(success: bool): host._complete_evidence_inspection(evidence_id, success))
		else: host.interactions.begin_gameplay(host, str(p.interaction.kind))
		if is_instance_valid(host.interactions.active): host.interactions.active.restore_checkpoint(p.interaction)
	if p.has("reconstruction") and is_instance_valid(controller):
		controller.begin_order_replay("ded_drag")
		if is_instance_valid(controller._order_replay): controller._order_replay.restore_checkpoint(p.reconstruction)
	if str(p.controller) == "corridor" and str(controller.phase) == "fadeout": host._fade(1.0, 0.3, controller._setup_stage)
	elif str(p.controller) == "corridor" and str(controller.phase) == "out": host._fade(1.0, 0.35, controller._swap_to_room)
	elif str(p.controller) == "opening" and str(controller.phase) == "fade": host._fade(0.0, maxf(0.01, 1.8 - float(controller._pt)))
	host.eng.s.playing = snapshot.engine.playing
	if not p.has("interaction") and not p.has("reconstruction"):
		host._sync_modal()
		var checks: Array = host.modal.find_children("*", "CheckBox", true, false)
		var saved_checks: Array = p.get("modal_checks", [])
		for i in mini(checks.size(), saved_checks.size()):
			if checks[i].text == str(saved_checks[i].text): checks[i].button_pressed = bool(saved_checks[i].pressed)
	host._dirty = true
	restoring = false
	restored = true
	var receipt_path := output_path.get_base_dir() + "/restore-receipt.json"
	DirAccess.make_dir_recursive_absolute(receipt_path.get_base_dir())
	var receipt := FileAccess.open(receipt_path, FileAccess.WRITE)
	if receipt != null:
		receipt.store_string(JSON.stringify({"source_identity": Source.identity(get_tree()), "snapshot_path": Source.project_output(path), "recovery_path": recovery_path,
			"room": host.eng.s.room, "controller": p.controller, "phase": p.get("controller_state", {}).get("phase", ""),
			"position": [host.det_pos.x, host.det_pos.y], "acceptance_eligible": false}))
		receipt.close()
	loaded.emit(path)
	return true

static func _fields(object: Object, keys: Array) -> Dictionary:
	var result := {}
	if not is_instance_valid(object): return result
	for key in keys:
		var value: Variant = object.get(key)
		result[key] = value.duplicate(true) if value is Dictionary or value is Array else value
	return result

static func _apply_fields(object: Object, values: Dictionary) -> void:
	if not is_instance_valid(object): return
	for key in values: object.set(key, values[key])

static func _items(items: Array) -> Dictionary:
	var result := {}
	for item in items: result[str(item.id)] = bool(item.get("seen", false))
	return result

static func _apply_items(items: Array, values: Dictionary) -> void:
	for item in items:
		if values.has(str(item.id)): item.seen = values[str(item.id)]

static func _actor(actor: Node3D) -> Dictionary:
	var result := {"transform": actor.transform, "visible": actor.visible, "pose": actor.pose, "clock": actor._t}
	if actor._glb_player != null:
		result["animation"] = actor._glb_player.current_animation
		result["position"] = actor._glb_player.current_animation_position
	return result

static func _apply_actor(actor: Node3D, value: Dictionary) -> void:
	actor.transform = value.transform
	actor.visible = value.visible
	actor.set_pose(str(value.pose))
	actor._t = value.clock
	if actor._glb_player != null and str(value.get("animation", "")) != "":
		actor._glb_player.play(str(value.animation))
		actor._glb_player.seek(float(value.position), true)

static func _node_states(root: Node) -> Dictionary:
	var result := {}
	for node in root.find_children("*", "Node3D", true, false):
		result[str(root.get_path_to(node))] = {"transform": node.transform, "visible": node.visible}
	return result

static func _apply_nodes(root: Node, values: Dictionary) -> void:
	for path in values:
		var node := root.get_node_or_null(NodePath(path))
		if node != null: _apply_fields(node, values[path])
