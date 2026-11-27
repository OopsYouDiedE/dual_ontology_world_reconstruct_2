extends Node
## Non-harsh procedural character voice synthesizer for The Sleeping Academy.
## Supports two gentle voice modes designed to avoid piercing chiptune highs:
##   1. "mumble"  — Soft low-pass dual-formant vocal hum + breath air (Animalese/Hollow Knight style)
##   2. "chamber" — Warm low-register chamber instrument tones (muted cello / bass marimba / soft flute)
##
## Usage:
##   var synth := preload("res://scenes/components/shared/VoiceSynth.gd").new()
##   add_child(synth)
##   synth.speak_line("……醒醒。先别急着起身，看着我——能看清吗？", "hale")

const SAMPLE_RATE := 22050

const PROFILES := {
	"hale": {
		"mode": "chamber_mumble",
		"base_hz": 146.83, # D3 warm baritone / cello
		"scale": [1.0, 1.122, 1.189, 1.335, 1.498], # D minor pentatonic
		"f1": 380.0,
		"f2": 1020.0,
		"breath": 0.08,
		"syllable_ms": 96.0,
		"gap_ms": 48.0,
		"cutoff": 1450.0,
	},
	"elder": {
		"mode": "chamber",
		"base_hz": 130.81, # C3 warm bass marimba / wood
		"scale": [1.0, 1.122, 1.260, 1.498, 1.682],
		"f1": 340.0,
		"f2": 920.0,
		"breath": 0.04,
		"syllable_ms": 108.0,
		"gap_ms": 62.0,
		"cutoff": 1300.0,
	},
	"resident": {
		"mode": "mumble",
		"base_hz": 196.00, # G3 soft alto hum
		"scale": [1.0, 1.122, 1.189, 1.335, 1.498],
		"f1": 460.0,
		"f2": 1240.0,
		"breath": 0.09,
		"syllable_ms": 84.0,
		"gap_ms": 44.0,
		"cutoff": 1650.0,
	},
}

var _player: AudioStreamPlayer

func _ready() -> void:
	_player = AudioStreamPlayer.new()
	_player.volume_db = -8.0
	add_child(_player)

func speak_line(text: String, speaker_id: String = "hale") -> void:
	if not is_instance_valid(_player) or text.strip_edges().is_empty():
		return
	var profile: Dictionary = PROFILES.get(speaker_id.to_lower(), PROFILES["hale"])
	var wav := synthesize_wav(text, profile)
	if wav != null:
		_player.stream = wav
		_player.play()

func stop_voice() -> void:
	if is_instance_valid(_player):
		_player.stop()

## Synthesizes a smooth, low-pass filtered AudioStreamWAV for a line of dialogue.
static func synthesize_wav(text: String, profile: Dictionary) -> AudioStreamWAV:
	var mode: String = str(profile.get("mode", "chamber_mumble"))
	var base_hz: float = float(profile.get("base_hz", 146.83))
	var scale: Array = profile.get("scale", [1.0, 1.122, 1.189, 1.335, 1.498])
	var breath_amt: float = float(profile.get("breath", 0.08))
	var syl_samples := int(SAMPLE_RATE * float(profile.get("syllable_ms", 92.0)) / 1000.0)
	var gap_samples := int(SAMPLE_RATE * float(profile.get("gap_ms", 48.0)) / 1000.0)
	var cutoff_hz: float = float(profile.get("cutoff", 1500.0))

	# Group every 2-3 printable characters into one gentle syllable so speech feels unhurried.
	var syllables: Array[Dictionary] = []
	var chars := text.strip_edges()
	var idx := 0
	var max_syls := 12
	while idx < chars.length() and syllables.size() < max_syls:
		var ch := chars.unicode_at(idx)
		if ch <= 32:
			idx += 1
			continue
		var is_pause := ch in [0x3002, 0xFF0C, 0xFF1F, 0xFF01, 0x2014, 0x2026, 46, 44, 63, 33]
		if is_pause:
			if not syllables.is_empty():
				syllables[-1]["tail"] = ch
			idx += 1
			continue
		var degree := int((ch * 31 + idx * 17) % scale.size())
		syllables.append({"deg": degree, "tail": 0, "seed": ch + idx * 13})
		idx += 2

	if syllables.is_empty():
		return null

	var total_samples := 0
	for s in syllables:
		total_samples += syl_samples + gap_samples + (gap_samples if int(s["tail"]) != 0 else 0)
	total_samples += int(SAMPLE_RATE * 0.12) # soft room tail

	var pcm := PackedByteArray()
	pcm.resize(total_samples * 2)

	# One-pole low-pass filter state to guarantee zero harsh high-frequency buzz
	var rc := 1.0 / (TAU * cutoff_hz)
	var dt := 1.0 / float(SAMPLE_RATE)
	var alpha := dt / (rc + dt)
	var lp := 0.0
	var lp2 := 0.0

	var cursor := 0
	var rng := RandomNumberGenerator.new()
	for s_i in syllables.size():
		var s: Dictionary = syllables[s_i]
		rng.seed = int(s["seed"])
		var ratio: float = float(scale[int(s["deg"])])
		var f0 := base_hz * ratio * rng.randf_range(0.985, 1.015)
		var tail_ch := int(s["tail"])
		var pitch_end := 1.0
		if tail_ch in [0xFF1F, 63]: # question mark -> gentle upward inflection
			pitch_end = 1.14
		elif tail_ch in [0x3002, 46]: # period -> calm downward cadence
			pitch_end = 0.89
		elif tail_ch in [0xFF0C, 44]: # comma -> slight lift
			pitch_end = 1.04

		var phase := 0.0
		for n in syl_samples:
			var u := float(n) / float(syl_samples)
			# Smooth raised-cosine attack (22%) and gentle decay (50%) — never clicks
			var env := 1.0
			if u < 0.22:
				env = 0.5 - 0.5 * cos(PI * u / 0.22)
			elif u > 0.48:
				env = 0.5 + 0.5 * cos(PI * (u - 0.48) / 0.52)

			var freq := lerpf(f0, f0 * pitch_end, u * u)
			phase += TAU * freq * dt

			var raw := 0.0
			if mode == "chamber":
				# Warm wood/cello fundamental + soft octave & 3rd harmonic
				raw = 0.68 * sin(phase) + 0.22 * sin(phase * 2.0) * (1.0 - 0.5 * u) + 0.08 * sin(phase * 3.0) * exp(-u * 3.5)
			elif mode == "mumble":
				# Soft vocal hum: fundamental + muted formant resonances + air
				raw = 0.62 * sin(phase) + 0.26 * sin(phase * 2.0 + 0.4) + 0.12 * sin(phase * 3.0)
				raw += rng.randf_range(-1.0, 1.0) * breath_amt
			else:
				# Hybrid chamber_mumble (warm cello-hum for Hale)
				raw = 0.64 * sin(phase) + 0.24 * sin(phase * 2.0) * (1.0 - 0.35 * u) + 0.10 * sin(phase * 3.0) * (1.0 - 0.5 * u)
				raw += rng.randf_range(-1.0, 1.0) * breath_amt

			var sample_val := raw * env * 0.55
			# Two-stage gentle low-pass filter
			lp += alpha * (sample_val - lp)
			lp2 += alpha * (lp - lp2)

			var i16 := clampi(int(lp2 * 32767.0), -32768, 32767)
			var bi := cursor * 2
			pcm[bi] = i16 & 0xFF
			pcm[bi + 1] = (i16 >> 8) & 0xFF
			cursor += 1

		var rest := gap_samples + (gap_samples if tail_ch != 0 else 0)
		for _r in rest:
			lp *= 0.96
			lp2 *= 0.96
			var i16 := clampi(int(lp2 * 32767.0), -32768, 32767)
			var bi := cursor * 2
			pcm[bi] = i16 & 0xFF
			pcm[bi + 1] = (i16 >> 8) & 0xFF
			cursor += 1

	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = SAMPLE_RATE
	wav.stereo = false
	wav.data = pcm
	return wav
