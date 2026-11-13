extends Node
## 程序化配乐与音效：全部由代码实时合成（AudioStreamGenerator），不读取任何音频文件。
## 设计依据：美术设定案第五部分——解除「不要｜开门」动机绑定；代管者专属阻碍终止（V→VI）。
## 时间／光照／场景状态会改变调性、速度、织体与混响；代管者显形时，句末滑向六级和弦。
##
## 用法：add_child(ProceduralScore.new()); score.start(); score.set_state({"mood":..., "hour":..., "demon":..., "tension":...})

const RATE := 22050
const MAX_VOICES := 24
const MAX_FRAMES_PER_CALL := 2400

const CHORDS := {
	"investigation": {"root": 59, "prog": [[0, 3, 7], [-2, 2, 5], [-4, 0, 3], [-5, -1, 2]], "scale": [0, 2, 3, 5, 7, 8, 10], "bpm": 94, "mode": "pizz"},
	"confrontation": {"root": 59, "prog": [[0, 3, 7], [3, 7, 10], [-2, 2, 5], [5, 8, 12]], "scale": [0, 2, 3, 5, 7, 8, 10], "bpm": 88, "mode": "organ"},
	"daily": {"root": 62, "prog": [[0, 4, 7], [-3, 0, 4], [2, 5, 9], [-1, 2, 7]], "scale": [0, 2, 4, 5, 7, 9, 11], "bpm": 84, "mode": "daily"},
	"dumpling": {"root": 62, "prog": [[0, 2, 4], [-3, 0, 2], [2, 4, 7], [0, 2, 7]], "scale": [0, 2, 4, 7, 9], "bpm": 104, "mode": "pent"},
	"night": {"root": 54, "prog": [[0, 3, 7], [-4, 0, 3], [-2, 2, 5], [-5, -1, 2]], "scale": [0, 2, 3, 5, 7, 8, 10], "bpm": 56, "mode": "night"},
	"demon": {"root": 59, "prog": [[0, 3, 7], [3, 7, 10], [-2, 2, 5], [8, 12, 15]], "scale": [0, 2, 3, 5, 7, 8, 10], "bpm": 72, "mode": "demon"},
	"menu": {"root": 59, "prog": [[0, 3, 7], [-2, 2, 5], [-4, 0, 3], [8, 12, 15]], "scale": [0, 2, 3, 5, 7, 8, 10], "bpm": 63, "mode": "night"},
	"truth": {"root": 59, "prog": [[0, 3, 7], [5, 8, 12], [-4, 0, 3], [0, 4, 7]], "scale": [0, 2, 3, 5, 7, 8, 10], "bpm": 76, "mode": "organ"},
}

enum Wave { SINE, TRI, SAW, NOISE }

var mood := "investigation"
var hour := 8.0
var demon := false
var tension := 0.0
var volume := 0.55
var enabled := true

var _player: AudioStreamPlayer
var _pb: AudioStreamGeneratorPlayback
# 声部采用结构数组（PackedArray），避免逐采样的字典查找：合成开销降低一个数量级。
var _n := 0
var v_f := PackedFloat32Array()
var v_ph := PackedFloat32Array()
var v_age := PackedFloat32Array()
var v_end := PackedFloat32Array()
var v_g := PackedFloat32Array()
var v_att := PackedFloat32Array()
var v_env := PackedFloat32Array()
var v_dec := PackedFloat32Array()
var v_lp := PackedFloat32Array()
var v_y := PackedFloat32Array()
var v_wave := PackedInt32Array()
var v_vib := PackedByteArray()
var v_wet := PackedByteArray()
var _step := 0
var _samples_to_step := 0
var _rng := 20261112
const COMB_LEN := [1553, 1877, 2251]  # 三条互质梳状延迟 → 廉价混响
const COMB_OFF := [0, 1553, 3430]
var _rev := PackedFloat32Array()
var _comb_pos: Array = [0, 0, 0]
var _started := false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS


func start() -> void:
	if _started: return
	_started = true
	var gen := AudioStreamGenerator.new()
	gen.mix_rate = RATE
	gen.buffer_length = 0.3
	_player = AudioStreamPlayer.new()
	_player.stream = gen
	_player.bus = &"Music" if AudioServer.get_bus_index(&"Music") != -1 else &"Master"
	_player.volume_db = linear_to_db(maxf(volume, 0.0001))
	add_child(_player)
	_player.play()
	_pb = _player.get_stream_playback()
	_rev.resize(5681)
	_samples_to_step = 0


func stop() -> void:
	if _player != null: _player.stop()
	_started = false
	_n = 0


func set_state(st: Dictionary) -> void:
	var m := str(st.get("mood", mood))
	if CHORDS.has(m): mood = m
	hour = float(st.get("hour", hour))
	demon = bool(st.get("demon", demon))
	tension = float(st.get("tension", tension))


func set_mood(m: String) -> void:
	if CHORDS.has(m): mood = m


func set_volume(v: float) -> void:
	volume = clampf(v, 0.0, 1.0)
	if _player != null: _player.volume_db = linear_to_db(maxf(volume, 0.0001)) if enabled else -80.0


func set_enabled(on: bool) -> void:
	enabled = on
	if _player != null: _player.volume_db = linear_to_db(maxf(volume, 0.0001)) if on else -80.0
	if on: start()


func _rnd() -> float:
	_rng = (_rng * 1664525 + 1013904223) & 0xFFFFFFFF
	return float(_rng) / 4294967296.0


static func midi_hz(n: float) -> float:
	return 440.0 * pow(2.0, (n - 69.0) / 12.0)


# ───────────────────────── 声部 ─────────────────────────
func _voice(freq: float, dur: float, wave: int, gain: float, attack := 0.008, cutoff := 0.0, vibrato := false, wet := true) -> void:
	if _n >= MAX_VOICES: _remove_voice(0)
	if v_f.size() < MAX_VOICES:
		for a in [v_f, v_ph, v_age, v_end, v_g, v_att, v_env, v_dec, v_lp, v_y]: a.resize(MAX_VOICES)
		v_wave.resize(MAX_VOICES)
		v_vib.resize(MAX_VOICES)
		v_wet.resize(MAX_VOICES)
	var i := _n
	var att := maxf(attack, 0.002)
	v_f[i] = freq
	v_ph[i] = 0.0
	v_age[i] = 0.0
	v_end[i] = dur + 0.05
	v_g[i] = gain
	v_att[i] = att
	v_env[i] = 0.0
	v_dec[i] = exp(-9.0 / maxf(dur + 0.05 - att, 0.01) / RATE)  # 每采样的指数衰减系数
	v_lp[i] = 0.0 if cutoff <= 0.0 else clampf(1.0 - exp(-TAU * cutoff / RATE), 0.0, 1.0)
	v_y[i] = 0.0
	v_wave[i] = wave
	v_vib[i] = 1 if vibrato else 0
	v_wet[i] = 1 if wet else 0
	_n += 1


func _remove_voice(i: int) -> void:
	var last := _n - 1
	if i != last:
		v_f[i] = v_f[last]; v_ph[i] = v_ph[last]; v_age[i] = v_age[last]; v_end[i] = v_end[last]
		v_g[i] = v_g[last]; v_att[i] = v_att[last]; v_env[i] = v_env[last]; v_dec[i] = v_dec[last]
		v_lp[i] = v_lp[last]; v_y[i] = v_y[last]; v_wave[i] = v_wave[last]; v_vib[i] = v_vib[last]; v_wet[i] = v_wet[last]
	_n -= 1


func _tone(midi: float, dur: float, wave: int, gain: float, attack := 0.008, cutoff := 0.0, vibrato := false, wet := true) -> void:
	_voice(midi_hz(midi), dur, wave, gain, attack, cutoff, vibrato, wet)


func _partial(midi: float, dur: float, gains: Array, gain: float) -> void:
	for i in gains.size():
		if gains[i] == 0.0: continue
		_voice(midi_hz(midi) * (i + 1), dur, Wave.SINE, gain * gains[i], 0.03 + i * 0.01)


func _noise(dur: float, freq: float, gain: float, wet := false) -> void:
	_voice(freq, dur, Wave.NOISE, gain, 0.002, freq * 2.0, false, wet)


func _v_pizz(m: float, d: float, v: float) -> void:
	_tone(m, d, Wave.TRI, v, 0.004, 1100.0, false, false)
	_noise(0.035, 900.0, v * 0.25)


func _v_organ(m: float, d: float, v: float) -> void:
	_partial(m, d, [1.0, 0.42, 0.25, 0.12, 0.06], v)


func _v_bell(m: float, d: float, v: float) -> void:
	_partial(m, d, [1.0, 0.5, 1.8, 0.3, 0.9, 0.2], v)


func _v_cello(m: float, d: float, v: float) -> void:
	_tone(m, d, Wave.SAW, v, 0.14, 720.0, true)


func _v_wood(m: float, v: float) -> void:
	_noise(0.06, 1400.0 + (int(m) % 5) * 180.0, v)


func _v_pluck(m: float, d: float, v: float) -> void:
	_tone(m, d, Wave.TRI, v, 0.003, 2400.0, false, false)
	_tone(m + 12.0, d * 0.4, Wave.SINE, v * 0.3)


func _v_wind(m: float, d: float, v: float) -> void:
	_noise(d, 260.0 + (int(m) % 4) * 60.0, v * 0.16, true)


## 每个八分音符调度一次（与 web 版 scheduleStep 一致）。
func _schedule_step(s: int) -> void:
	var cfg: Dictionary = CHORDS.get(mood, CHORDS.investigation)
	var prog: Array = cfg.prog
	var bar := (s / 8) % prog.size()
	var beat := s % 8
	var chord: Array = prog[bar]
	var root: float = cfg.root
	var mode: String = cfg.mode
	var scale: Array = cfg.scale
	var night := hour < 6.0 or hour >= 19.5
	var bright := clampf(1.0 - absf(hour - 13.0) / 12.0, 0.0, 1.0)
	var v := 0.16 + bright * 0.05
	var deceptive := demon or mood == "menu" or mood == "demon"
	if beat == 0:
		var bass: float = root - 24.0 + chord[0]
		if mode == "pizz": _v_pizz(bass, 1.5, v * 0.9)
		else: _v_cello(bass, 1.5, v * 0.9)
		for i in chord.size():
			if deceptive and bar == prog.size() - 1:
				_v_organ(root + 8.0 + [0, 3, 7][i], 1.8, v * 0.42)  # V→VI：滑向六级
			else:
				_v_organ(root + float(chord[i]), 1.7, v * 0.36)
	if beat == 4: _v_cello(root - 24.0 + chord[0] + 7.0, 0.9, v * 0.42)
	var chance := 0.42 if mode == "night" else (0.86 if mode == "pent" else 0.64)
	if _rnd() < chance:
		var deg: float = scale[int(_rnd() * scale.size())]
		var oct := 12.0 if _rnd() < 0.25 else 0.0
		var m := root + 12.0 + deg + oct
		var dur := 0.8 if night else 0.45
		if mode == "pent": _v_pluck(m, dur, v * 0.72)
		elif mode == "night": _v_bell(m, dur, v * 0.72)
		elif mode == "organ" or mode == "demon": _v_organ(m, dur, v * 0.5)
		else: _v_pizz(m, dur, v * 0.72)
	if mode == "pizz" and beat % 2 == 0: _v_wood(0.0, v * 0.20)
	if mode == "pent" and beat % 2 == 1: _v_wood(0.0, v * 0.26)
	if mode == "night" and _rnd() < 0.2: _v_bell(root + 24.0 + float(scale[int(_rnd() * 3)]), 1.2, v * 0.22)
	if mode == "demon" and beat == 7: _v_cello(root - 12.0 + 8.0, 1.4, v * 0.5)
	if _rnd() < 0.06: _v_wind(0.0, 1.4, v * 0.3)
	if tension > 0.5 and beat % 4 == 2: _v_cello(root - 12.0 + 1.0, 0.6, v * 0.28)


# ───────────────────────── 音效 ─────────────────────────
func sfx(kind: String) -> void:
	if not enabled: return
	if not _started: start()
	match kind:
		"click":
			_noise(0.035, 2100.0, 0.10)
			_tone(84, 0.05, Wave.SINE, 0.05, 0.004, 0.0, false, false)
		"pen":
			_noise(0.16, 3200.0, 0.055)
			_noise(0.14, 2600.0, 0.04)
		"door":
			_tone(38, 0.42, Wave.SAW, 0.11, 0.008, 300.0)
			_noise(0.34, 180.0, 0.12)
		"chime": _partial(83, 1.3, [1.0, 0.4, 1.6, 0.2], 0.11)
		"success":
			for m in [71, 74, 78, 83]: _partial(m, 0.6, [1.0, 0.3], 0.09)
		"error":
			_tone(47, 0.5, Wave.SAW, 0.10, 0.008, 420.0)
			_tone(46, 0.5, Wave.SAW, 0.07, 0.008, 380.0)
		"demon":
			_partial(47, 2.0, [1.0, 0.3, 0.18], 0.10)
			_partial(56, 2.0, [1.0, 0.25], 0.09)
		"page": _noise(0.22, 1700.0, 0.06)
		_: _noise(0.04, 1200.0, 0.06)


# ───────────────────────── 合成循环 ─────────────────────────
func _process(_dt: float) -> void:
	if not _started or _pb == null or not enabled: return
	var frames := mini(_pb.get_frames_available(), MAX_FRAMES_PER_CALL)
	if frames <= 0: return
	var cfg: Dictionary = CHORDS.get(mood, CHORDS.investigation)
	var step_len := int(RATE * 60.0 / float(cfg.bpm) / 2.0)
	var buf := PackedVector2Array()
	buf.resize(frames)
	var inv := 1.0 / RATE
	for i in frames:
		if _samples_to_step <= 0:
			_schedule_step(_step)
			_step += 1
			_samples_to_step = step_len
		_samples_to_step -= 1
		var dry := 0.0
		var wet := 0.0
		var k := _n - 1
		while k >= 0:
			var age: float = v_age[k]
			if age >= v_end[k]:
				_remove_voice(k)
				k -= 1
				continue
			var att: float = v_att[k]
			var env: float
			if age < att:
				env = age / att
				v_env[k] = 1.0
			else:
				env = v_env[k]
				env *= v_dec[k]
				v_env[k] = env
			var f: float = v_f[k]
			if v_vib[k] == 1: f *= 1.0 + 0.0028 * sin(TAU * 4.6 * age)
			var ph: float = v_ph[k] + f * inv
			ph -= floorf(ph)
			v_ph[k] = ph
			var x: float
			var w: int = v_wave[k]
			if w == 0: x = sin(ph * TAU)
			elif w == 1: x = 4.0 * absf(ph - 0.5) - 1.0
			elif w == 2: x = 2.0 * ph - 1.0
			else: x = _rnd() * 2.0 - 1.0
			var lp: float = v_lp[k]
			if lp > 0.0:
				var y: float = v_y[k]
				y += lp * (x - y)
				v_y[k] = y
				x = y
			x *= env * v_g[k]
			v_age[k] = age + inv
			dry += x
			if v_wet[k] == 1: wet += x
			k -= 1
		var rev := 0.0
		for c in 3:
			var pos: int = _comb_pos[c]
			var idx: int = COMB_OFF[c] + pos
			var delayed := _rev[idx]
			_rev[idx] = wet + delayed * 0.62
			_comb_pos[c] = (pos + 1) % int(COMB_LEN[c])
			rev += delayed
		var out := clampf((dry * 0.92 + rev * 0.24) * 0.9, -1.0, 1.0)
		buf[i] = Vector2(out, out)
	_pb.push_buffer(buf)
