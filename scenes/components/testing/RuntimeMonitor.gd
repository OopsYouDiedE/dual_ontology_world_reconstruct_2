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
var pcm: FileAccess
var capture: AudioEffectCapture
var capture_index := -1
var _label: Label
var _times := PackedFloat64Array()
var _cursor := 0
var _last_usec := 0
var _started_usec := 0
var _sample_clock := 0.0
var _audio_clock := 0.0
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

func configure(directory: String, metadata: Dictionary, content: Control) -> void:
	output_dir = preload("res://mcp/CaptureSource.gd").project_output(directory)
	if output_dir.is_empty(): return
	directory = output_dir
	_owner = content
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(directory))
	metadata["frame_clock"] = "Time.get_ticks_usec, unscaled, includes loading and capture overhead"
	metadata["content_text_policy"] = "visible_active_viewports"
	metadata["source_identity"] = preload("res://mcp/CaptureSource.gd").identity(get_tree())
	metadata["fps_window"] = "last 3600 frames; low FPS = 1000 / mean slowest fraction of frame times"
	metadata["audio_method"] = "FFmpeg ebur128 / ITU BS.1770 K-weighting, 4x true-peak oversampling"
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
	if frames != null: frames.store_line("frame,elapsed_s,node,frame_ms,draw_calls,static_ram_mb,gpu_resource_mb")
	pcm = FileAccess.open(directory + "/mix.f32le", FileAccess.WRITE)
	capture = AudioEffectCapture.new()
	capture.buffer_length = 2.0
	AudioServer.add_bus_effect(0, capture)
	capture_index = AudioServer.get_bus_effect_count(0) - 1
	_start_audio_worker()
	_started_usec = Time.get_ticks_usec()
	_last_usec = _started_usec
	set_process(true)

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

func _process(delta: float) -> void:
	if _finished or _last_usec == 0: return
	var now := Time.get_ticks_usec()
	var ms := float(now - _last_usec) / 1000.0
	_last_usec = now
	_frame_count += 1
	_max_ms = maxf(_max_ms, ms)
	if ms > 33.3: _spikes += 1
	if _times.size() < 3600:
		_times.append(ms)
	else:
		_times[_cursor] = ms
		_cursor = (_cursor + 1) % 3600
	var draw_calls := int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME))
	var static_mb := Performance.get_monitor(Performance.MEMORY_STATIC) / 1048576.0
	var gpu_mb := Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED) / 1048576.0
	if frames != null: frames.store_csv_line([str(_frame_count), "%.6f" % (float(now - _started_usec) / 1000000.0), node_id, "%.4f" % ms, str(draw_calls), "%.3f" % static_mb, "%.3f" % gpu_mb])
	if capture != null and pcm != null:
		var count := capture.get_frames_available()
		if count > 0: pcm.store_buffer(capture.get_buffer(count).to_byte_array())
		_capture_lost = int(capture.get_discarded_frames())
	_audio_clock += delta
	if _audio_clock >= 0.1:
		_audio_clock = 0.0
		if pcm != null: pcm.flush()
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
		if capture != null and capture.get_frames_available() > 0: pcm.store_buffer(capture.get_buffer(capture.get_frames_available()).to_byte_array())
		pcm.flush()
		pcm.close()
		pcm = null
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
	report.finish({"frames": _frame_count, "max_frame_ms": _max_ms, "spikes_over_33_3_ms": _spikes, "audio_discarded_frames": _capture_lost, "acceptance": "pending_independent_evidence_review"})

func _exit_tree() -> void:
	finish()
