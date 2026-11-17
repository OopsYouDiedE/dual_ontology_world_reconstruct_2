extends Node
## Real-time sampled video evidence; never changes the engine timestep.
var monitor: Control
var directory := ""
var manifest: FileAccess
var worker := Thread.new()
var pending: Dictionary = {}
var sample_clock := 0.0
var sequence := 0
var skipped := 0
var failures := 0
var stopped := false

func configure(source: Control) -> void:
	monitor = source
	directory = monitor.output_dir + "/dynamic"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(directory))
	manifest = FileAccess.open(directory + "/frames.jsonl", FileAccess.WRITE)
	if manifest == null:
		push_error("Dynamic capture manifest could not open")
		set_process(false)
		return
	manifest.store_line(JSON.stringify({"type": "configuration", "sample_hz": 10, "max_width": 1024, "timebase": "RuntimeMonitor elapsed_s", "fixed_timestep": false}))

func _process(delta: float) -> void:
	if stopped or manifest == null or monitor == null: return
	if worker.is_started() and not worker.is_alive(): _join()
	sample_clock += delta
	if sample_clock < 0.1: return
	sample_clock = fmod(sample_clock, 0.1)
	var elapsed := float(Time.get_ticks_usec() - monitor._started_usec) / 1000000.0
	if worker.is_started():
		skipped += 1
		manifest.store_line(JSON.stringify({"type": "missed_sample", "elapsed_s": elapsed, "scene_node": monitor.node_id, "reason": "encoder_busy"}))
		return
	var frame := get_viewport().get_texture().get_image()
	sequence += 1
	var path := directory + "/%07d.png" % sequence
	pending = {"type": "frame", "sequence": sequence, "elapsed_s": elapsed, "scene_node": monitor.node_id, "path": path, "original_width": frame.get_width(), "original_height": frame.get_height()}
	var error := worker.start(_encode.bind(frame, path))
	if error != OK:
		failures += 1
		manifest.store_line(JSON.stringify({"type": "capture_error", "elapsed_s": elapsed, "error": error}))

func _encode(frame: Image, path: String) -> Dictionary:
	if frame.get_width() > 1024:
		frame.resize(1024, maxi(1, roundi(frame.get_height() * 1024.0 / frame.get_width())), Image.INTERPOLATE_BILINEAR)
	var error := frame.save_png(path)
	return {"error": error, "sha256": FileAccess.get_sha256(path) if error == OK else "", "width": frame.get_width(), "height": frame.get_height()}

func _join() -> void:
	var result: Dictionary = worker.wait_to_finish()
	pending.merge(result)
	if int(result.error) != OK: failures += 1
	manifest.store_line(JSON.stringify(pending))
	manifest.flush()
	pending = {}

func finish() -> void:
	if stopped: return
	stopped = true
	if worker.is_started(): _join()
	if manifest != null:
		manifest.store_line(JSON.stringify({"type": "summary", "frames": sequence, "skipped_samples": skipped, "write_failures": failures}))
		manifest.close()
		manifest = null

func _exit_tree() -> void:
	finish()
