extends RefCounted
## 共享物理短音，现场家具和证物使用同一声学实现。
static func play(player: AudioStreamPlayer3D, cue: String) -> void:
	# Short deterministic physical transients; generated PCM remains audible evidence.
	if player == null: return
	var rate := 22050
	var duration := 0.65 if cue == "wood" else 0.32
	var data := PackedByteArray()
	data.resize(int(rate * duration) * 2)
	var seed_value := 7919
	for index in int(rate * duration):
		var time := float(index) / rate
		seed_value = (seed_value * 16807) % 2147483647
		var noise := float(seed_value) / 1073741823.5 - 1.0
		var value := 0.0
		match cue:
			"wood": value = (sin(time * TAU * 116.0) * 0.6 + sin(time * TAU * 183.0) * 0.2 + noise * 0.1) * exp(-time * 9.0)
			"metal": value = (sin(time * TAU * 870.0) + sin(time * TAU * 1733.0) * 0.3) * exp(-time * 18.0)
			_: value = noise * 0.35 * sin(minf(time / 0.04, 1.0) * PI / 2.0) * exp(-time * 9.0)
		data.encode_s16(index * 2, int(clampf(value, -1.0, 1.0) * 26000.0))
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = rate
	stream.data = data
	player.stream = stream
	player.play()
	preload("res://scenes/components/testing/AudioCueTelemetry.gd").record("spatial_effect")
