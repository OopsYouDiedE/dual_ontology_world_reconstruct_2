extends Control
## Metrics are measured from wall-clock frames and the actual post-mix audio bus.
const Timeline := preload("res://scenes/components/testing/YamlTimeline.gd")
const FONT := preload("res://assets/external/NotoSansSC/NotoSansSC[wght].ttf")
var node_id := "boot"
var output_dir := ""
var latest: Dictionary = {}
var audio: Dictionary = {}
var report := Timeline.new()
var frames: FileAccess
var pcm := preload("res://scenes/components/testing/AsyncPcmWriter.gd").new()
var capture: AudioEffectCapture
var capture_index := -1
var background_streams: Array[Dictionary] = []
var text_changes: FileAccess
var _last_text_signature := ""
var _audio_route_initial: Dictionary = {}
var _audio_route_stable := true
var _audio_route_last: Dictionary = {}
var _audio_route_events: Array[Dictionary] = []
var _master_capture_usec := 0
var _label: Label
var _times := PackedFloat64Array()
var _cursor := 0
var _last_usec := 0
var _started_usec := 0
var _sample_clock := 0.0
var _frame_count := 0
var _spikes := 0
var _max_ms := 0.0
var _finished := false
var _worker_pid := -1
var _capture_lost := 0
var _last_audio_frames := 0
var _owner: Control
var measurement_context := "rendered_runtime"
var _audio_snapshot_errors := 0
var sample_context: Dictionary = {}
var _scene_identity := ""
var _warmup_until_usec := 0
var _warmup_reason := "cold_start"
var _steady_spikes := 0
var _warmup_frames := 0

func configure(directory: String, metadata: Dictionary, content: Control) -> void:
	output_dir = preload("res://mcp/CaptureSource.gd").project_output(directory)
	if output_dir.is_empty(): return
	directory = output_dir
	_owner = content
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(directory))
	metadata["frame_clock"] = "Time.get_ticks_usec, unscaled, includes loading and capture overhead"
	metadata["warmup_policy"] = "Cold start and each constructed room/stage: first 1.5 s recorded separately; only explicitly marked steady frames determine the 33.3 ms veto"
	metadata["content_text_policy"] = "visible_active_viewports"
	metadata["source_identity"] = preload("res://mcp/CaptureSource.gd").identity(get_tree(), str(metadata.get("launch_scene", "")))
	metadata["fps_window"] = "last 3600 frames; low FPS = 1000 / mean slowest fraction of frame times"
	metadata["audio_method"] = "FFmpeg ebur128 / ITU BS.1770 K-weighting, 4x true-peak oversampling"
	metadata["audio_capture_buffer_s"] = 15.0
	metadata["background_audio_scope"] = "Music and existing Ambient buses; Master captures full mix. Music is background music; Sfx and Voice are excluded from background capture."
	metadata["background_bus_inventory"] = []
	for bus_name in ["Music", "Ambient"]:
		if AudioServer.get_bus_index(bus_name) >= 0: metadata["background_bus_inventory"].append(bus_name)
	metadata["audio_dba"] = {"value": null, "reason": "digital output has no calibrated acoustic SPL reference; use LUFS"}
	metadata["vram_method"] = "Godot renderer resource allocation; not driver-wide dedicated GPU residency"
	metadata["render_backend"] = RenderingServer.get_current_rendering_method()
	metadata["start_local"] = Time.get_datetime_string_from_system(false, true)
	metadata["start_unix"] = Time.get_unix_time_from_system()
	measurement_context = "headless_development" if DisplayServer.get_name() == "headless" else "rendered_runtime"
	if "--write-movie" in OS.get_cmdline_args(): measurement_context = "fixed_step_movie"
	metadata["measurement_context"] = measurement_context
	metadata["realtime_performance_eligible"] = measurement_context == "rendered_runtime"
	if not report.begin(directory + "/timeline.yaml", metadata):
		push_error(report.error)
		return
	frames = FileAccess.open(directory + "/frames.csv", FileAccess.WRITE)
	if frames != null: frames.store_line("frame,elapsed_s,node,frame_ms,draw_calls,static_ram_mb,gpu_resource_mb,measurement_phase,warmup_reason")
	if pcm.start(directory + "/mix.f32le") != OK: push_error("Audio recording file could not open")
	capture = AudioEffectCapture.new()
	# Scene construction can block longer than the default ring. Preserve its
	# audio while the unscaled frame clock continues to report that stall.
	capture.buffer_length = 15.0
	AudioServer.add_bus_effect(0, capture)
	_master_capture_usec = Time.get_ticks_usec()
	capture_index = AudioServer.get_bus_effect_count(0) - 1
	_start_audio_worker()
	for bus_name in ["Music", "Ambient"]:
		_start_background_capture(bus_name)
	text_changes = FileAccess.open(directory + "/visible-text-changes.jsonl", FileAccess.WRITE)
	_audio_route_initial = _audio_route_snapshot()
	_started_usec = Time.get_ticks_usec()
	_audio_route_last = _audio_route_initial.duplicate(true)
	_audio_route_events.append({"elapsed_s": 0.0, "snapshot": _audio_route_last.duplicate(true)})
	_last_usec = _started_usec
	_warmup_until_usec = _started_usec + 1500000
	set_process(true)

func tag_scene(identity: String) -> void:
	if identity == _scene_identity: return
	_warmup_reason = "cold_start" if _scene_identity.is_empty() else "scene_load"
	_scene_identity = identity
	_warmup_until_usec = Time.get_ticks_usec() + 1500000

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_theme_font_override("font", FONT)
	var background := ColorRect.new()
	background.color = Color("#111b20")
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(background)
	_label = Label.new()
	_label.position = Vector2(14, 6)
	_label.add_theme_font_override("font", FONT)
	_label.add_theme_font_size_override("font_size", 14)
	_label.add_theme_color_override("font_color", Color("#cbd8cd"))
	_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_label)
	set_process(false)

func _start_audio_worker() -> void:
	var python := ProjectSettings.globalize_path("res://.runtime/python/Scripts/python.exe")
	if not FileAccess.file_exists(python): python = "python"
	var script := ProjectSettings.globalize_path("res://tools/testing/audio_watch.py")
	_worker_pid = OS.create_process(python, [script, "--pcm", ProjectSettings.globalize_path(output_dir + "/mix.f32le"), "--rate", str(int(AudioServer.get_mix_rate())), "--out", ProjectSettings.globalize_path(output_dir + "/audio.json"), "--stop", ProjectSettings.globalize_path(output_dir + "/audio.stop"), "--owner", str(OS.get_process_id())], false)
	if _worker_pid < 0: audio = {"status": "unavailable", "reason": "audio worker could not start"}

func _start_background_capture(bus_name: String) -> void:
	var bus := AudioServer.get_bus_index(bus_name)
	if bus < 0: return
	var stem := "background-" + bus_name.to_lower()
	var writer = preload("res://scenes/components/testing/AsyncPcmWriter.gd").new()
	if writer.start(output_dir + "/" + stem + ".f32le") != OK:
		push_error("Background audio recording file could not open: " + bus_name)
		return
	var effect := AudioEffectCapture.new()
	effect.buffer_length = 15.0
	AudioServer.add_bus_effect(bus, effect)
	var capture_start_usec := Time.get_ticks_usec()
	var python := ProjectSettings.globalize_path("res://.runtime/python/Scripts/python.exe")
	if not FileAccess.file_exists(python): python = "python"
	var script := ProjectSettings.globalize_path("res://tools/testing/audio_watch.py")
	var pid := OS.create_process(python, [script, "--pcm", ProjectSettings.globalize_path(output_dir + "/" + stem + ".f32le"), "--rate", str(int(AudioServer.get_mix_rate())), "--out", ProjectSettings.globalize_path(output_dir + "/" + stem + ".json"), "--stop", ProjectSettings.globalize_path(output_dir + "/" + stem + ".stop"), "--owner", str(OS.get_process_id())], false)
	background_streams.append({"bus": bus_name, "stem": stem, "capture": effect, "writer": writer, "worker_pid": pid, "capture_start_usec": capture_start_usec})

func _audio_route_snapshot() -> Dictionary:
	# Godot 4.7.2 processes bus effects before each bus fader and send.
	var result := {"buses": {}, "any_solo": false}
	for index in AudioServer.bus_count:
		if AudioServer.is_bus_solo(index): result.any_solo = true
	for name in ["Master", "Music", "Ambient"]:
		var index := AudioServer.get_bus_index(name)
		if index < 0: continue
		var effects: Array[String] = []
		var capture_active := false
		for effect_index in AudioServer.get_bus_effect_count(index):
			if AudioServer.is_bus_effect_enabled(index, effect_index):
				var effect := AudioServer.get_bus_effect(index, effect_index)
				if (name == "Master" and effect == capture) or (name != "Master" and _is_background_effect(effect)): capture_active = true
				else: effects.append(effect.get_class())
		result.buses[name] = {"volume_db": AudioServer.get_bus_volume_db(index), "muted": AudioServer.is_bus_mute(index), "bypass": AudioServer.is_bus_bypassing_effects(index), "send": str(AudioServer.get_bus_send(index)) if name != "Master" else "", "other_effects": effects, "capture_active": capture_active}
	return result

func _is_background_effect(effect: AudioEffect) -> bool:
	for stream in background_streams:
		if stream.capture == effect: return true
	return false

func _record_audio_route(now: int) -> void:
	var current := _audio_route_snapshot()
	if current == _audio_route_last: return
	_audio_route_stable = false
	_audio_route_last = current.duplicate(true)
	_audio_route_events.append({"elapsed_s": float(now - _started_usec) / 1000000.0, "snapshot": current})

func _record_visible_text(now: int) -> void:
	if text_changes == null or _owner == null: return
	var entries: Array = []
	preload("res://scenes/components/testing/VisibleText.gd").collect(_owner, _owner.get_viewport(), entries)
	var stable: Array = []
	for entry in entries: stable.append({"path": entry.path, "text": entry.text, "class": entry.get("class"), "category": entry.get("category")})
	var signature := JSON.stringify({"node": node_id, "entries": stable})
	if signature == _last_text_signature: return
	_last_text_signature = signature
	text_changes.store_line(JSON.stringify({"frame": _frame_count, "elapsed_s": float(now - _started_usec) / 1000000.0, "scene_node": node_id, "entries": entries}))

func _process(delta: float) -> void:
	if _finished or _last_usec == 0: return
	var now := Time.get_ticks_usec()
	var ms := float(now - _last_usec) / 1000.0
	_last_usec = now
	_frame_count += 1
	_max_ms = maxf(_max_ms, ms)
	if ms > 33.3: _spikes += 1
	var warming := now <= _warmup_until_usec
	if warming: _warmup_frames += 1
	elif ms > 33.3: _steady_spikes += 1
	if _times.size() < 3600:
		_times.append(ms)
	else:
		_times[_cursor] = ms
		_cursor = (_cursor + 1) % 3600
	var draw_calls := int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME))
	var static_mb := Performance.get_monitor(Performance.MEMORY_STATIC) / 1048576.0
	var gpu_mb := Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED) / 1048576.0
	if frames != null: frames.store_csv_line([str(_frame_count), "%.6f" % (float(now - _started_usec) / 1000000.0), node_id, "%.4f" % ms, str(draw_calls), "%.3f" % static_mb, "%.3f" % gpu_mb, "loading_warmup" if warming else "steady", _warmup_reason if warming else ""])
	if capture != null and pcm != null:
		var count := capture.get_frames_available()
		if count > 0: pcm.enqueue(capture.get_buffer(count).to_byte_array())
		_capture_lost = int(capture.get_discarded_frames())
	for stream in background_streams:
		var effect: AudioEffectCapture = stream.capture
		var count := effect.get_frames_available()
		if count > 0: stream.writer.enqueue(effect.get_buffer(count).to_byte_array())
	_record_audio_route(now)
	_record_visible_text(now)
	_sample_clock += delta
	if _sample_clock < 0.5: return
	_sample_clock = 0.0
	var audio_path := output_dir + "/audio.json"
	if FileAccess.file_exists(audio_path):
		# A Windows snapshot replacement can race a reader. Preserve the previous
		# measurement and record the failed read without raising a host parse error.
		var snapshot := JSON.new()
		var text := FileAccess.get_file_as_string(audio_path)
		if snapshot.parse(text) == OK and snapshot.data is Dictionary: audio = snapshot.data
		else: _audio_snapshot_errors += 1
	var sorted := _times.duplicate()
	sorted.sort()
	var total := 0.0
	for value in sorted: total += value
	latest = {
		"system_time": Time.get_datetime_string_from_system(false, true),
		"elapsed_s": float(now - _started_usec) / 1000000.0, "scene_node": node_id,
		"frame": _frame_count, "avg_fps": 1000.0 * sorted.size() / maxf(total, 0.001),
		"low_5_fps": _low(sorted, 0.05), "low_1_fps": _low(sorted, 0.01),
		"frame_p95_ms": _percentile(sorted, 0.95), "frame_p99_ms": _percentile(sorted, 0.99),
		"max_frame_ms": _max_ms, "spikes_over_33_3_ms": _spikes,
		"steady_spikes_over_33_3_ms": _steady_spikes, "loading_warmup_frames": _warmup_frames,
		"measurement_phase": "loading_warmup" if warming else "steady", "audio_writer": pcm.stats(),
		"draw_calls": draw_calls, "static_ram_mb": static_mb,
		"ram_mb": audio.get("ram_mb"), "gpu_resource_mb": gpu_mb if gpu_mb > 0.0 else null,
		"audio": audio.duplicate(true), "audio_discarded_frames": _capture_lost,
		"audio_snapshot_read_retries": _audio_snapshot_errors,
		"content_text": visible_text(_owner),
		"monitor_characters": _label.text.length() if visible else 0,
		"monitor_visible": visible,
		"measurement_context": measurement_context
	}
	latest.merge(sample_context, true)
	_update_label()
	latest["monitor_characters"] = _label.text.length() if visible else 0
	latest["total_visible_characters"] = int(latest.content_text.characters) + int(latest.monitor_characters)
	report.append(latest)
	if frames != null: frames.flush()

static func _percentile(sorted: PackedFloat64Array, fraction: float) -> float:
	return sorted[clampi(int(ceil(sorted.size() * fraction)) - 1, 0, sorted.size() - 1)] if not sorted.is_empty() else 0.0

static func _low(sorted: PackedFloat64Array, fraction: float) -> float:
	var count := maxi(1, int(ceil(sorted.size() * fraction)))
	var sum := 0.0
	for index in range(maxi(0, sorted.size() - count), sorted.size()): sum += sorted[index]
	return 1000.0 * count / maxf(sum, 0.001)

static func visible_text(root: Node) -> Dictionary:
	if root == null: return {"characters": 0, "strings": []}
	var strings: Array[String] = []
	var entries: Array = []
	preload("res://scenes/components/testing/VisibleText.gd").collect(root, root.get_viewport(), entries)
	for entry in entries: strings.append(str(entry.text))
	var count := 0
	for value in strings: count += value.length()
	return {"characters": count, "strings": strings}

func _number(value: Variant, decimals := 1) -> String:
	return ("%.*f" % [decimals, float(value)]) if value != null else "—"

func _update_label() -> void:
	_label.text = "%s   %s\nAvg FPS %s   5%% Low %s   1%% Low %s   P95/P99 %s/%s ms   Draw %s\nVRAM %s MB   RAM %s MB   LUFS avg/peak %s/%s   dBTP %s   dBA —" % [
		latest.system_time, node_id, _number(latest.avg_fps), _number(latest.low_5_fps), _number(latest.low_1_fps), _number(latest.frame_p95_ms), _number(latest.frame_p99_ms), str(latest.draw_calls), _number(latest.gpu_resource_mb), _number(latest.ram_mb), _number(audio.get("integrated_lufs")), _number(audio.get("max_momentary_lufs")), _number(audio.get("true_peak_dbtp"))]

func finish() -> void:
	if _finished: return
	_finished = true
	set_process(false)
	if pcm != null:
		if capture != null and capture.get_frames_available() > 0: pcm.enqueue(capture.get_buffer(capture.get_frames_available()).to_byte_array())
		pcm.finish()
	_record_audio_route(Time.get_ticks_usec())
	var background_status := {}
	for stream in background_streams:
		var effect: AudioEffectCapture = stream.capture
		var count := effect.get_frames_available()
		if count > 0: stream.writer.enqueue(effect.get_buffer(count).to_byte_array())
		var stats: Dictionary = stream.writer.finish()
		background_status[stream.bus] = {"writer": stats, "discarded_frames": effect.get_discarded_frames(), "worker_pid": stream.worker_pid, "start_offset_s": float(_started_usec - int(stream.capture_start_usec)) / 1000000.0}
		var bus := AudioServer.get_bus_index(stream.bus)
		if bus >= 0:
			for index in AudioServer.get_bus_effect_count(bus):
				if AudioServer.get_bus_effect(bus, index) == effect:
					AudioServer.remove_bus_effect(bus, index)
					break
		var background_stop := FileAccess.open(output_dir + "/" + stream.stem + ".stop", FileAccess.WRITE)
		if background_stop != null: background_stop.store_string("finalize"); background_stop.close()
	if text_changes != null: text_changes.flush(); text_changes.close(); text_changes = null
	if output_dir != "":
		var stop := FileAccess.open(output_dir + "/audio.stop", FileAccess.WRITE)
		if stop != null: stop.store_string("finalize"); stop.close()
	if capture_index >= 0:
		# Find the same effect by identity; another component may have changed indices.
		for index in AudioServer.get_bus_effect_count(0):
			if AudioServer.get_bus_effect(0, index) == capture:
				AudioServer.remove_bus_effect(0, index)
				break
	if frames != null: frames.flush(); frames.close(); frames = null
	report.finish({"frames": _frame_count, "max_frame_ms": _max_ms, "spikes_over_33_3_ms": _spikes, "steady_spikes_over_33_3_ms": _steady_spikes, "loading_warmup_frames": _warmup_frames, "audio_writer": pcm.stats(), "audio_discarded_frames": _capture_lost, "background_audio": background_status, "master_start_offset_s": float(_started_usec - _master_capture_usec) / 1000000.0, "audio_route": {"stable": _audio_route_stable, "snapshot": _audio_route_initial, "changes": _audio_route_events, "capture_point": "last enabled bus effect, before bus volume and send"}, "acceptance": "pending_independent_evidence_review"})

func _exit_tree() -> void:
	finish()
