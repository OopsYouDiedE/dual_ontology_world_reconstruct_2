extends Node
## 全局配乐与音效（自动加载为 GameAudio）。配乐两条轨交叉淡化、无缝循环；音效走小型播放器池。
## 场景脚本经 Sound.gd 调用，自动加载缺席时（无头检查脚本）静默跳过。
## 曲目与音效保存在 ShareAsset/Internal/Props/Audio 下。

const LIFECYCLE := preload("res://scenes/components/shared/HostLifecycle.gd")
const MusicContext := preload("res://scenes/components/shared/MusicContext.gd")
const MUSIC_PATH := "res://assets/environment/Audio/Music/%s.ogg"
const SFX_PATH := "res://assets/environment/Audio/Sfx/%s.ogg"
const MUSIC_DB := -9.0
# A through-composed title must end naturally; repeat only background cues.
const NON_LOOPING_CUES := {"main_theme": true}
const DUCK_DB := -9.0
const SILENT_DB := -60.0
const SFX_VOICES := 8

var _music: Array[AudioStreamPlayer] = []
var _active := 0
var _current := ""
var _ducked := false
var _fade: Tween
var _sfx: Array[AudioStreamPlayer] = []
var _next_sfx := 0
var _cache := {}
var _scene_music := ""
var _music_token_serial := 0
var _presentation_music_token := 0

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	get_tree().auto_accept_quit = false
	get_tree().root.close_requested.connect(quit_cleanly)
	for i in 2:
		var player := AudioStreamPlayer.new()
		player.name = "Music%d" % i
		player.bus = _bus_or_master(&"Music")
		player.volume_db = SILENT_DB
		add_child(player)
		_music.append(player)
	for i in SFX_VOICES:
		var player := AudioStreamPlayer.new()
		player.name = "Sfx%d" % i
		player.bus = _bus_or_master(&"Sfx")
		add_child(player)
		_sfx.append(player)

## 配乐/音效/语音走各自的总线（default_bus_layout.tres；音量由 GameSettings 管理），缺总线时退回 Master。
static func _bus_or_master(bus: StringName) -> StringName:
	return bus if AudioServer.get_bus_index(bus) != -1 else &"Master"

func apply_music_scene(snapshot: Dictionary) -> void:
	var next := MusicContext.background(snapshot)
	if next == "": return
	_scene_music = next
	if _presentation_music_token == 0:
		play_music(_scene_music)

func begin_presentation_music(presentation: Dictionary) -> int:
	if _scene_music == "" or not MusicContext.is_formal_confrontation(presentation):
		return 0
	_music_token_serial += 1
	_presentation_music_token = _music_token_serial
	play_music("confrontation", 0.8)
	return _presentation_music_token

func end_presentation_music(token: int) -> void:
	# A late callback from an old UI must not interrupt a new presentation.
	if token == 0 or token != _presentation_music_token: return
	_presentation_music_token = 0
	if _scene_music != "": play_music(_scene_music, 1.2)

func _clear_music_context() -> void:
	_scene_music = ""
	_presentation_music_token = 0

func play_music(id: String, fade := 1.6) -> void:
	if id == "main_theme": _clear_music_context()
	# Formal confrontation is scoped to delivered dialogue, never a generic BGM.
	if id == "confrontation" and _presentation_music_token == 0:
		id = _scene_music
		if id == "": return
	if id == _current and _music[_active].playing:
		return
	var stream := _load(MUSIC_PATH % id)
	if stream == null:
		return
	_current = id
	var looped: AudioStream = stream.duplicate()
	if looped is AudioStreamOggVorbis:
		looped.loop = not NON_LOOPING_CUES.has(id)
	var old := _music[_active]
	_active = 1 - _active
	var new := _music[_active]
	new.stream = looped
	new.volume_db = SILENT_DB
	new.play()
	_fade_to(new, old, fade)

func stop_music(fade := 1.6) -> void:
	_clear_music_context()
	_current = ""
	_fade_to(null, _music[_active], fade)

## 重演回放时压低配乐，结束后恢复。
func duck(on: bool) -> void:
	if _ducked == on:
		return
	_ducked = on
	var player := _music[_active]
	if player.playing and _current != "":
		if _fade:
			_fade.kill()
		_fade = create_tween()
		_fade.tween_property(player, "volume_db", _target_db(), 0.6)

func play_sfx(id: String, volume_db := 0.0, pitch := 1.0) -> void:
	var stream := _load(SFX_PATH % id)
	if stream == null:
		return
	var player := _sfx[_next_sfx]
	_next_sfx = (_next_sfx + 1) % _sfx.size()
	player.stream = stream
	player.volume_db = volume_db
	player.pitch_scale = pitch
	player.play()

func _target_db() -> float:
	return MUSIC_DB + (DUCK_DB if _ducked else 0.0)

func _fade_to(incoming: AudioStreamPlayer, outgoing: AudioStreamPlayer, seconds: float) -> void:
	if _fade:
		_fade.kill()
	_fade = create_tween().set_parallel(true)
	if incoming:
		_fade.tween_property(incoming, "volume_db", _target_db(), seconds)
	if outgoing and outgoing.playing:
		_fade.tween_property(outgoing, "volume_db", SILENT_DB, seconds)
		_fade.chain().tween_callback(outgoing.stop)

func _load(path: String) -> AudioStream:
	if not _cache.has(path):
		_cache[path] = load(path) if ResourceLoader.exists(path) else null
		if _cache[path] == null:
			push_warning("GameAudio: 缺少音频 " + path)
	return _cache[path]

## Release playback before the audio server and scene tree are destroyed.
func release_audio() -> void:
	_clear_music_context()
	if _fade:
		_fade.kill()
		_fade = null
	for player in _music + _sfx:
		if is_instance_valid(player):
			player.stop()
			player.stream = null
	_cache.clear()
	_current = ""
	_ducked = false

## stop() queues playback deletion; the driver must complete later mix steps first.
func release_audio_and_wait_for_mix() -> bool:
	var stopped_at := Time.get_ticks_usec()
	release_audio()
	var deadline := stopped_at + 500000
	var last_mix_at := stopped_at
	var completed_mixes := 0
	while Time.get_ticks_usec() < deadline:
		await get_tree().process_frame
		# Driver mix time is distinct from render frames, including on the dummy driver.
		var sampled_at := Time.get_ticks_usec()
		var mix_at := sampled_at - int(AudioServer.get_time_since_last_mix() * 1000000.0)
		# A 1ms separation rejects timestamp sampling jitter, rather than counting it as a mix.
		if mix_at > last_mix_at + 1000:
			last_mix_at = mix_at
			completed_mixes += 1
			if completed_mixes == 2:
				print_verbose("GameAudio: two driver mix steps completed after playback release.")
				return true
	push_error("GameAudio: audio driver did not complete two mix steps within the 500ms shutdown bound.")
	return false

func quit_cleanly(exit_code := 0) -> void:
	await LIFECYCLE.quit(get_tree(), exit_code)

func _exit_tree() -> void:
	release_audio()
