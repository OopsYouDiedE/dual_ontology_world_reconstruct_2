extends SceneTree
## Development recording verifies real mixed PCM survives the asynchronous drain.
func _initialize() -> void: call_deferred("run")
func run() -> void:
	var content := Control.new()
	root.add_child(content)
	var monitor := preload("res://scenes/components/testing/RuntimeMonitor.gd").new()
	content.add_child(monitor)
	monitor.visible = false
	var directory := "res://.runtime/monitor-probe-" + str(OS.get_process_id())
	monitor.configure(directory, {"mock": true, "entry": "development_probe"}, content)
	monitor.tag_scene("probe-room")
	var pcm := PackedByteArray()
	pcm.resize(44100 * 2)
	for i in 44100: pcm.encode_s16(i * 2, int(sin(float(i) / 44100.0 * TAU * 440.0) * 1000.0))
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = 44100
	stream.data = pcm
	stream.loop_mode = AudioStreamWAV.LOOP_FORWARD
	stream.loop_end = 44100
	var player := AudioStreamPlayer.new()
	player.stream = stream
	content.add_child(player)
	player.play()
	await create_timer(1.9).timeout
	monitor.finish()
	player.stop()
	var written: Dictionary = monitor.pcm.stats()
	var timeline := FileAccess.get_file_as_string(directory + "/timeline.yaml")
	var frames := FileAccess.get_file_as_string(directory + "/frames.csv")
	var ok := int(written.error) == OK and int(written.bytes_written) > 1000 and int(written.bytes_queued) == 0 and ",steady," in frames and ",loading_warmup," in frames and '"summary":' in timeline and monitor._capture_lost == 0
	print("MONITOR_RECORDING " + JSON.stringify({"passed": ok, "audio_writer": written, "discarded_frames": monitor._capture_lost, "frames": monitor._frame_count, "output": directory, "acceptance_eligible": false}))
	var until := Time.get_ticks_msec() + 4000
	while monitor._worker_pid > 0 and OS.is_process_running(monitor._worker_pid) and Time.get_ticks_msec() < until: await process_frame
	content.queue_free()
	await process_frame
	quit(0 if ok else 1)
