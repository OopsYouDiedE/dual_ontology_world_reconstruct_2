extends CanvasLayer
## Reusable Unity-Timeline-inspired dynamic story & cutscene director for The Sleeping Academy.
## Packages camera choreography, eyelids/fades, Chapter-1 unified captions, soft human mumble
## voiceover, shader cues, and actor animations into one skippable, data-driven sequence.
##
## Guaranteed deterministic cleanup on both normal completion and instant Esc skip.

signal finished(skipped: bool)
signal beat_changed(index: int, beat_id: String)

const DialoguePresenter = preload("res://scenes/components/shared/UnifiedDialoguePresenter.gd")
const UiStyle = preload("res://scenes/components/shared/UiTheme.gd")
const R18n = preload("res://scenes/components/shared/R18n.gd")

var active := false
var beat_index := -1
var total_elapsed := 0.0
var beat_elapsed := 0.0

var _beats: Array = []
var _viewport: SubViewport
var _player_cam: Camera3D
var _cutscene_cam: Camera3D
var _shot_driver: Callable = Callable()
var _shift_driver: Callable = Callable()
var _on_beat_enter: Callable = Callable()
var _on_cleanup: Callable = Callable()
var _eyelid_duration := 2.4
var _shift_from := 0.0

var _fade_rect: ColorRect
var _top_lid: ColorRect
var _bot_lid: ColorRect
var _captions: VBoxContainer
var _hint_label: Label
var _voice: Node
var _presenter: Node

func _ready() -> void:
	layer = 20
	_build_ui()
	visible = false

func _build_ui() -> void:
	_fade_rect = ColorRect.new()
	_fade_rect.color = Color(0.018, 0.022, 0.024, 1.0)
	_fade_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_fade_rect)
	_fade_rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	_top_lid = ColorRect.new()
	_top_lid.color = Color(0.012, 0.015, 0.016, 1.0)
	_top_lid.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_top_lid)
	_top_lid.anchor_left = 0.0
	_top_lid.anchor_right = 1.0
	_top_lid.anchor_top = 0.0
	_top_lid.anchor_bottom = 0.5

	_bot_lid = ColorRect.new()
	_bot_lid.color = Color(0.012, 0.015, 0.016, 1.0)
	_bot_lid.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_bot_lid)
	_bot_lid.anchor_left = 0.0
	_bot_lid.anchor_right = 1.0
	_bot_lid.anchor_top = 0.5
	_bot_lid.anchor_bottom = 1.0

	var font := UiStyle.make_font()
	# Cutscene lines use the same caption bar + formant voice as every level.
	_presenter = DialoguePresenter.new()
	_presenter.auto_advance = false  # beats own their timing
	add_child(_presenter)
	_presenter.setup(self, -52.0)
	_captions = _presenter.captions

	_hint_label = Label.new()
	_hint_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_hint_label.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	_hint_label.offset_bottom = -18.0
	_hint_label.offset_top = -40.0
	_hint_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	UiStyle.style_label(_hint_label, font, 12, Color("b9a68a"), 3)
	add_child(_hint_label)

	_voice = _presenter.voice

## Starts a packaged dynamic story sequence.
## `config` keys:
##   beats: Array[Dictionary]   (id, duration, speaker, text, text_en, shot, shift, voice)
##   viewport: SubViewport
##   player_cam: Camera3D
##   shot_driver: Callable(cam: Camera3D, beat: Dictionary, smooth_t: float, beat_elapsed: float)
##   shift_driver: Callable(value: float)
##   on_beat_enter: Callable(beat: Dictionary)
##   on_cleanup: Callable(skipped: bool)
##   eyelid_duration: float (default 2.4; <= 0 disables eyelids)
func play_sequence(config: Dictionary) -> void:
	if active:
		skip()
	_beats = config.get("beats", [])
	_viewport = config.get("viewport")
	_player_cam = config.get("player_cam")
	if _beats.is_empty() or _viewport == null or _player_cam == null:
		return
	_shot_driver = config.get("shot_driver", Callable())
	_shift_driver = config.get("shift_driver", Callable())
	_on_beat_enter = config.get("on_beat_enter", Callable())
	_on_cleanup = config.get("on_cleanup", Callable())
	_eyelid_duration = float(config.get("eyelid_duration", 2.4))
	_shift_from = float(_beats[0].get("shift", 0.0))

	_cutscene_cam = Camera3D.new()
	_cutscene_cam.name = "StoryDirectorCamera"
	_cutscene_cam.fov = float(_player_cam.fov)
	_viewport.add_child(_cutscene_cam)
	_cutscene_cam.make_current()

	active = true
	visible = true
	total_elapsed = 0.0
	beat_elapsed = 0.0
	beat_index = -1
	_top_lid.visible = _eyelid_duration > 0.0
	_bot_lid.visible = _eyelid_duration > 0.0
	_fade_rect.visible = _eyelid_duration > 0.0
	_advance_beat()

func _input(event: InputEvent) -> void:
	if not active:
		return
	if event is InputEventMouseButton and event.pressed:
		var mb := (event as InputEventMouseButton).button_index
		if mb == MOUSE_BUTTON_LEFT:
			_advance_beat()
			get_viewport().set_input_as_handled()
		elif mb == MOUSE_BUTTON_RIGHT:
			skip()
			get_viewport().set_input_as_handled()
		return
	if not event is InputEventKey or not event.pressed or event.echo:
		return
	var code := (event as InputEventKey).physical_keycode
	if code == KEY_ESCAPE:
		skip()
		get_viewport().set_input_as_handled()
	elif code in [KEY_SPACE, KEY_E, KEY_ENTER]:
		_advance_beat()
		get_viewport().set_input_as_handled()

func _advance_beat() -> void:
	beat_index += 1
	beat_elapsed = 0.0
	if beat_index >= _beats.size():
		_finish(false)
		return
	var beat: Dictionary = _beats[beat_index]
	if beat_index > 0:
		_shift_from = float(_beats[beat_index - 1].get("shift", 0.0))
	if is_instance_valid(_hint_label):
		_hint_label.text = R18n.pick(
			"左键 / Space / E · 下一句     |     右键 / Esc · 跳过全部",
			"LMB / Space / E · Next     |     RMB / Esc · Skip all"
		)
	var line_text := str(beat.get("text_en", beat.get("text", "")) if R18n.is_en() else beat.get("text", ""))
	var speaker_name := str(beat.get("speaker", ""))
	if is_instance_valid(_captions):
		_captions.clear()
		if not line_text.is_empty():
			_captions.post(str(beat.get("id", "beat_%d" % beat_index)), speaker_name, line_text)
	if is_instance_valid(_voice):
		_voice.stop_voice()
		var v_id := str(beat.get("voice", speaker_name)).to_lower()
		if not v_id.is_empty() and not line_text.is_empty():
			_voice.speak_line(line_text, v_id)
	if _on_beat_enter.is_valid():
		_on_beat_enter.call(beat)
	beat_changed.emit(beat_index, str(beat.get("id", "")))

func skip() -> void:
	if active:
		_finish(true)

func _finish(skipped: bool) -> void:
	if not active:
		return
	active = false
	visible = false
	if is_instance_valid(_voice):
		_voice.stop_voice()
	if is_instance_valid(_captions):
		_captions.clear()
	if is_instance_valid(_player_cam):
		_player_cam.make_current()
	if is_instance_valid(_cutscene_cam):
		_cutscene_cam.queue_free()
	_cutscene_cam = null
	if _on_cleanup.is_valid():
		_on_cleanup.call(skipped)
	finished.emit(skipped)

func _process(delta: float) -> void:
	if not active or not is_instance_valid(_cutscene_cam) or beat_index < 0 or beat_index >= _beats.size():
		return
	total_elapsed += delta
	beat_elapsed += delta

	# Natural drowsy double-blink eyelid opening during wake-up
	if _eyelid_duration > 0.0:
		var u := clampf(total_elapsed / _eyelid_duration, 0.0, 1.0)
		var open_amt: float
		if u < 0.34:
			# First groggy half-open
			open_amt = ease_out_cubic(u / 0.34) * 0.52
		elif u < 0.48:
			# Brief natural blink dip
			var b := (u - 0.34) / 0.14
			open_amt = lerpf(0.52, 0.22, sin(b * PI))
		else:
			# Full clear opening
			open_amt = lerpf(0.42, 1.0, ease_out_cubic((u - 0.48) / 0.52))
		_fade_rect.color.a = clampf(1.0 - u * 1.45, 0.0, 1.0)
		_top_lid.anchor_bottom = lerpf(0.5, 0.0, open_amt)
		_bot_lid.anchor_top = lerpf(0.5, 1.0, open_amt)

	var beat: Dictionary = _beats[beat_index]
	var dur := maxf(float(beat.get("duration", 3.5)), 0.1)
	var t := clampf(beat_elapsed / dur, 0.0, 1.0)
	var smooth := ease_in_out_cubic(t)
	if _shot_driver.is_valid():
		_shot_driver.call(_cutscene_cam, beat, smooth, beat_elapsed)
	if _shift_driver.is_valid():
		var target_shift := float(beat.get("shift", 0.0))
		_shift_driver.call(lerpf(_shift_from, target_shift, smooth) * (0.92 + 0.08 * sin(total_elapsed * 2.1)))

	if beat_elapsed >= dur:
		_advance_beat()

static func ease_out_cubic(x: float) -> float:
	var c := clampf(x, 0.0, 1.0)
	return 1.0 - pow(1.0 - c, 3.0)

static func ease_in_out_cubic(x: float) -> float:
	var c := clampf(x, 0.0, 1.0)
	return 4.0 * c * c * c if c < 0.5 else 1.0 - pow(-2.0 * c + 2.0, 3.0) * 0.5

func snapshot() -> Dictionary:
	return {
		"active": active,
		"beat_index": beat_index,
		"beat_count": _beats.size(),
		"beat_id": str(_beats[beat_index].get("id", "")) if beat_index >= 0 and beat_index < _beats.size() else "",
		"camera_pos": _cutscene_cam.global_position if is_instance_valid(_cutscene_cam) else Vector3.ZERO,
		"camera_fov": _cutscene_cam.fov if is_instance_valid(_cutscene_cam) else 0.0,
	}
