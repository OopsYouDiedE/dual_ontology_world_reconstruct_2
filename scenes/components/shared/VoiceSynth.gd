extends Node
## Copyright-free procedural human vocal-tract mumble synthesizer (NO musical instruments).
## Generates warm, hushed human mumbling using a soft Rosenberg glottal pulse filtered
## through 3 vocal-tract formant resonators (F1/F2/F3) + breathy consonant air + natural pitch contour.

const SAMPLE_RATE := 22050

# Formant frequencies (F1, F2, F3 in Hz) for muffled, non-harsh human vowels (uh, oo, oh, mm, eh)
const VOWELS := [
	[420.0, 1080.0, 2250.0], # ə (uh)
	[340.0, 820.0, 2150.0],  # u (oo)
	[460.0, 920.0, 2200.0],  # o (oh)
	[310.0, 1150.0, 2100.0], # m (nasal hum)
	[510.0, 1320.0, 2300.0], # e (soft eh)
]

const PROFILES := {
	"hale": {
		"f0_hz": 116.0,       # Warm low baritone male voice
		"f0_span": 16.0,
		"tract_scale": 0.94,  # Slightly deeper vocal tract
		"breath": 0.14,
		"syllable_ms": 105.0,
		"gap_ms": 42.0,
		"cutoff": 1450.0,     # Keeps speech hushed & warm, never piercing
	},
	"elder": {
		"f0_hz": 98.0,        # Deep gravelly elder voice
		"f0_span": 12.0,
		"tract_scale": 0.88,
		"breath": 0.18,
		"syllable_ms": 118.0,
		"gap_ms": 54.0,
		"cutoff": 1280.0,
	},
	"resident": {
		"f0_hz": 168.0,       # Soft alto / mid-low human voice
		"f0_span": 22.0,
		"tract_scale": 1.06,
		"breath": 0.15,
		"syllable_ms": 92.0,
		"gap_ms": 38.0,
		"cutoff": 1580.0,
	},
}

var _player: AudioStreamPlayer

func _ready() -> void:
	_player = AudioStreamPlayer.new()
	_player.volume_db = -14.0
	add_child(_player)

func speak_line(text: String, speaker_id: String = "hale") -> void:
	if not is_instance_valid(_player) or text.strip_edges().is_empty():
		return
	var profile: Dictionary = PROFILES.get(speaker_id.to_lower(), PROFILES["hale"])
	var wav := synthesize_mumble_wav(text, profile)
	if wav != null:
		_player.stream = wav
		_player.play()

func stop_voice() -> void:
	if is_instance_valid(_player):
		_player.stop()

## Synthesizes a copyright-free human mumble AudioStreamWAV (no musical notes).
static func synthesize_mumble_wav(text: String, profile: Dictionary) -> AudioStreamWAV:
	var f0_base: float = float(profile.get("f0_hz", 116.0))
	var f0_span: float = float(profile.get("f0_span", 16.0))
	var tract_scale: float = float(profile.get("tract_scale", 0.95))
	var breath_amt: float = float(profile.get("breath", 0.14))
	var syl_samples := int(SAMPLE_RATE * float(profile.get("syllable_ms", 105.0)) / 1000.0)
	var gap_samples := int(SAMPLE_RATE * float(profile.get("gap_ms", 42.0)) / 1000.0)
	var cutoff_hz: float = float(profile.get("cutoff", 1450.0))

	var syllables: Array[Dictionary] = []
	var chars := text.strip_edges()
	var idx := 0
	var max_syls := 14
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
		syllables.append({
			"v": int((ch * 19 + idx * 7) % VOWELS.size()),
			"tail": 0,
			"seed": ch * 13 + idx * 29,
		})
		idx += 2

	if syllables.is_empty():
		return null

	var total_samples := 0
	for s in syllables:
		total_samples += syl_samples + gap_samples + (gap_samples if int(s["tail"]) != 0 else 0)
	total_samples += int(SAMPLE_RATE * 0.10)

	var pcm := PackedByteArray()
	pcm.resize(total_samples * 2)

	var dt := 1.0 / float(SAMPLE_RATE)
	var rc := 1.0 / (TAU * cutoff_hz)
	var lp_a := dt / (rc + dt)
	var lp := 0.0

	# Two parallel 2-pole formant resonator states (F1, F2)
	var y1_1 := 0.0; var y1_2 := 0.0
	var y2_1 := 0.0; var y2_2 := 0.0

	var cursor := 0
	var rng := RandomNumberGenerator.new()
	for s_i in syllables.size():
		var s: Dictionary = syllables[s_i]
		rng.seed = int(s["seed"])
		var vowel: Array = VOWELS[int(s["v"])]
		var f1: float = float(vowel[0]) * tract_scale
		var f2: float = float(vowel[1]) * tract_scale

		# Resonator coefficients for F1 (BW 95Hz) and F2 (BW 140Hz)
		var r1 := exp(-PI * 95.0 * dt)
		var c1 := 2.0 * r1 * cos(TAU * f1 * dt)
		var g1 := 1.0 - r1 * r1

		var r2 := exp(-PI * 140.0 * dt)
		var c2 := 2.0 * r2 * cos(TAU * f2 * dt)
		var g2 := (1.0 - r2 * r2) * 0.48

		var tail_ch := int(s["tail"])
		# Natural speech declination across sentence + punctuation contour (non-musical)
		var sentence_decl := 1.0 - 0.11 * (float(s_i) / float(maxi(syllables.size(), 1)))
		var f0_start := (f0_base + rng.randf_range(-f0_span, f0_span)) * sentence_decl
		var f0_end := f0_start * (1.16 if tail_ch in [0xFF1F, 63] else (0.84 if tail_ch in [0x3002, 46] else (1.05 if tail_ch in [0xFF0C, 44] else 0.94)))

		var phase := 0.0
		for n in syl_samples:
			var u := float(n) / float(syl_samples)
			# Soft syllable envelope with gentle consonant breath at onset
			var env := 1.0
			if u < 0.18:
				env = 0.5 - 0.5 * cos(PI * u / 0.18)
			elif u > 0.58:
				env = 0.5 + 0.5 * cos(PI * (u - 0.58) / 0.42)

			# Subtle human vocal vibrato/jitter (~5.2Hz)
			var vib := 1.0 + 0.012 * sin(float(cursor) * dt * TAU * 5.2)
			var freq := lerpf(f0_start, f0_end, u) * vib
			phase = fmod(phase + freq * dt, 1.0)

			# Soft Rosenberg glottal pulse (smooth vocal-cord wave, not harsh sawtooth/square)
			var glottal := 0.0
			if phase < 0.42:
				glottal = 0.5 * (1.0 - cos(PI * phase / 0.42))
			elif phase < 0.60:
				glottal = cos(PI * 0.5 * (phase - 0.42) / 0.18)
			glottal = (glottal - 0.35) * 1.45

			# Breathy consonant onset + aspiration noise
			var air := rng.randf_range(-1.0, 1.0) * breath_amt * (1.8 if u < 0.16 else 0.65)
			var exc := (glottal + air) * env

			# Pass through vocal-tract formant resonators F1 + F2
			var o1 := g1 * exc + c1 * y1_1 - (r1 * r1) * y1_2
			y1_2 = y1_1; y1_1 = o1
			var o2 := g2 * exc + c2 * y2_1 - (r2 * r2) * y2_2
			y2_2 = y2_1; y2_1 = o2

			var vocal := (o1 * 0.72 + o2 * 0.38) * 0.44
			lp += lp_a * (vocal - lp)

			var i16 := clampi(int(lp * 32767.0), -32768, 32767)
			var bi := cursor * 2
			pcm[bi] = i16 & 0xFF
			pcm[bi + 1] = (i16 >> 8) & 0xFF
			cursor += 1

		var rest := gap_samples + (gap_samples if tail_ch != 0 else 0)
		for _r in rest:
			y1_1 *= 0.92; y1_2 *= 0.92; y2_1 *= 0.92; y2_2 *= 0.92
			lp *= 0.94
			var i16 := clampi(int(lp * 32767.0), -32768, 32767)
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
