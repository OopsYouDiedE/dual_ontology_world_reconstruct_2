extends CanvasLayer
## Opening awakening cutscene and camera choreography for the Public Hall.
##
## Story beat:
##   1. The captain wakes on a west-wing dormitory bed; Hale shakes them awake.
##   2. The wing is already warping: lamp edges split into red and blue fringes.
##   3. Through the wing arcade the camera finds the drifting Foucault Pendulum.
##   4. Hale explains the stalled Essence return and the spare core left in the shaft.
##   5. Two-person rule: only the two of them are up; Hale goes ahead to the north gate.

signal finished

const Cast = preload("res://scenes/rogue_crossing/ProductionCast.gd")
const UiStyle = preload("res://scenes/components/shared/UiTheme.gd")

# Offsets from the wake bed centre. The bed runs along X with its head against the west wall.
const WAKE_EYE := Vector3(-0.72, 0.86, 0.0)
const HALE_SPOT := Vector3(1.85, 0.0, -0.5)
const STAND_EYE := Vector3(0.62, 1.55, -0.95)
# World point in the open west arcade bay from which the pendulum is framed.
const ARCADE_EYE := Vector3(11.6, 1.6, 19.2)

# Essence instability per beat: sharpest on waking, easing into the hall's residual drift.
const BEATS := [
	{
		"id": "wake_shake",
		"speaker": "Hale",
		"text": "……醒醒。先别急着起身，看着我——能看清吗？",
		"folio": "04:00  /  常数锚定厅 · 西翼宿舍",
		"duration": 3.4,
		"shot": "wake",
		"shift": 0.95
	},
	{
		"id": "wake_focus",
		"speaker": "",
		"text": "提灯在墙上拖出一红一蓝两道边。床架的线条在晃，像隔着一层热浪看东西——不是没睡醒。",
		"folio": "04:00  /  常数锚定厅 · 西翼宿舍",
		"duration": 3.8,
		"shot": "hale_closeup",
		"shift": 0.8
	},
	{
		"id": "pendulum_drift",
		"speaker": "Hale",
		"text": "你也看见了：朝你来的发蓝，离你去的发红——源质在漂。中央铜摆过南象限慢了半拍，刻痕已经越过红线三格。",
		"folio": "04:01  /  西翼拱廊 · 望向常数锚定井",
		"duration": 5.0,
		"shot": "pendulum_push",
		"shift": 0.6
	},
	{
		"id": "essence_reason",
		"speaker": "Hale",
		"text": "稳压井的源质回流断了。前班撤出时把隔离闸反锁在里面，备用源核还在井下。不换上它，整座学院只会漂得更厉害。",
		"folio": "04:01  /  常数锚定井 · 源质失衡",
		"duration": 4.8,
		"shot": "pendulum_hold",
		"shift": 0.5
	},
	{
		"id": "north_gate_handoff",
		"speaker": "Hale",
		"text": "井区守则只放双人编队过闸，整座大厅醒着的只剩你和我。灯和手册在你床头——拿上，北门见。",
		"folio": "04:02  /  西翼宿舍 · 出发",
		"duration": 5.2,
		"shot": "gate_handoff",
		"shift": 0.3
	}
]

var active := false
var beat_index := -1
var _beat_elapsed := 0.0
var _total_elapsed := 0.0

var _viewport: SubViewport
var _player_cam: Camera3D
var _cutscene_cam: Camera3D
var _hale_actor: Node3D
var _cot_pos := Vector3.ZERO
var _pendulum_pos := Vector3.ZERO
var _player_eye_pos := Vector3.ZERO
var _player_eye_basis := Basis.IDENTITY
var _shift := Callable()
var _shift_from := 0.0

var _top_lid: ColorRect
var _bot_lid: ColorRect
var _fade_rect: ColorRect
var _folio_label: Label
var _speaker_label: Label
var _caption_label: Label
var _hint_label: Label

func _ready() -> void:
	layer = 20
	_build_overlay()
	visible = false

func _build_overlay() -> void:
	_fade_rect = ColorRect.new()
	_fade_rect.color = Color(0.02, 0.025, 0.025, 1.0)
	_fade_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_fade_rect)
	_fade_rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	_top_lid = ColorRect.new()
	_top_lid.color = Color(0.015, 0.018, 0.018, 1.0)
	_top_lid.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_top_lid)
	_top_lid.anchor_left = 0.0
	_top_lid.anchor_right = 1.0
	_top_lid.anchor_top = 0.0
	_top_lid.anchor_bottom = 0.5

	_bot_lid = ColorRect.new()
	_bot_lid.color = Color(0.015, 0.018, 0.018, 1.0)
	_bot_lid.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_bot_lid)
	_bot_lid.anchor_left = 0.0
	_bot_lid.anchor_right = 1.0
	_bot_lid.anchor_top = 0.5
	_bot_lid.anchor_bottom = 1.0

	var margin := MarginContainer.new()
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	margin.add_theme_constant_override("margin_left", 64)
	margin.add_theme_constant_override("margin_right", 64)
	margin.add_theme_constant_override("margin_bottom", 46)
	add_child(margin)
	margin.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	# Grow upward from the bottom edge so the speaker and the line stay on screen.
	margin.grow_vertical = Control.GROW_DIRECTION_BEGIN

	var plate := PanelContainer.new()
	plate.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var style := StyleBoxFlat.new()
	# Same caption plate and typeface as the expedition subtitles.
	style.bg_color = Color(.035, .029, .023, .89)
	style.border_color = UiStyle.ACCENT
	style.border_width_left = 3
	style.set_corner_radius_all(4)
	style.set_content_margin_all(16)
	plate.add_theme_stylebox_override("panel", style)
	margin.add_child(plate)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 6)
	plate.add_child(vbox)

	_folio_label = Label.new()
	_folio_label.add_theme_font_size_override("font_size", 12)
	_folio_label.add_theme_color_override("font_color", Color("d8b97b"))
	vbox.add_child(_folio_label)

	_speaker_label = Label.new()
	_speaker_label.add_theme_font_size_override("font_size", 17)
	_speaker_label.add_theme_color_override("font_color", Color("f2ca82"))
	vbox.add_child(_speaker_label)

	_caption_label = Label.new()
	_caption_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_caption_label.add_theme_font_size_override("font_size", 19)
	_caption_label.add_theme_color_override("font_color", Color("f6ebd6"))
	vbox.add_child(_caption_label)

	_hint_label = Label.new()
	_hint_label.text = "Space / E · 下一句     |     Esc · 跳过开场"
	_hint_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_hint_label.add_theme_font_size_override("font_size", 12)
	_hint_label.add_theme_color_override("font_color", Color("a89c88"))
	vbox.add_child(_hint_label)
	var font := UiStyle.make_font()
	for label: Label in [_folio_label, _speaker_label, _caption_label, _hint_label]:
		label.add_theme_font_override("font", font)

## `shift` receives the essence instability (0–1) each frame while the sequence runs.
func start(viewport: SubViewport, player_cam: Camera3D, cot_pos: Vector3, pendulum_pos: Vector3, _gate_pos: Vector3, shift := Callable()) -> void:
	if active or viewport == null or player_cam == null:
		return
	_viewport = viewport
	_player_cam = player_cam
	_cot_pos = cot_pos
	_pendulum_pos = pendulum_pos
	_shift = shift
	_shift_from = float(BEATS[0].shift)
	_player_eye_pos = player_cam.global_position
	_player_eye_basis = player_cam.global_transform.basis

	# Hale stands past the foot of the bed, turned toward the pillow.
	_hale_actor = Node3D.new()
	_hale_actor.name = "OpeningHale"
	_viewport.add_child(_hale_actor)
	_hale_actor.position = _cot_pos + HALE_SPOT
	Cast.attach_hero(_hale_actor, "hale")
	var pillow := _cot_pos + WAKE_EYE
	_hale_actor.look_at(Vector3(pillow.x, 0.0, pillow.z), Vector3.UP, true)

	_cutscene_cam = Camera3D.new()
	_cutscene_cam.name = "HallOpeningCamera"
	_cutscene_cam.fov = 74.0
	_viewport.add_child(_cutscene_cam)
	_cutscene_cam.make_current()

	active = true
	visible = true
	_total_elapsed = 0.0
	beat_index = -1
	_advance_beat()

func _advance_beat() -> void:
	beat_index += 1
	_beat_elapsed = 0.0
	if beat_index >= BEATS.size():
		finish()
		return
	var beat: Dictionary = BEATS[beat_index]
	if beat_index > 0: _shift_from = float(BEATS[beat_index - 1].shift)
	_folio_label.text = beat.folio
	_speaker_label.text = beat.speaker if not str(beat.speaker).is_empty() else "（意识渐清）"
	_caption_label.text = beat.text
	# Hale talks with his hands on his lines and listens on the captain's.
	if is_instance_valid(_hale_actor) and _hale_actor.has_meta("animation_player"):
		(_hale_actor.get_meta("animation_player") as AnimationPlayer).play(&"signal" if beat.speaker == "Hale" else &"listen", 0.4)

func skip() -> void:
	if active:
		finish()

func finish() -> void:
	if not active:
		return
	active = false
	visible = false
	if is_instance_valid(_player_cam):
		_player_cam.make_current()
	if is_instance_valid(_cutscene_cam):
		_cutscene_cam.queue_free()
		_cutscene_cam = null
	if is_instance_valid(_hale_actor):
		_hale_actor.queue_free()
		_hale_actor = null
	finished.emit()

func _unhandled_input(event: InputEvent) -> void:
	if not active or not (event is InputEventKey) or not event.pressed or event.echo:
		return
	if event.physical_keycode == KEY_ESCAPE:
		skip()
		get_viewport().set_input_as_handled()
	elif event.physical_keycode in [KEY_SPACE, KEY_E, KEY_ENTER]:
		_advance_beat()
		get_viewport().set_input_as_handled()

func _process(delta: float) -> void:
	if not active or not is_instance_valid(_cutscene_cam):
		return
	_total_elapsed += delta
	_beat_elapsed += delta

	# Eyelid opening & fade-in during the first 2.6 seconds
	var open_t := clampf(_total_elapsed / 2.6, 0.0, 1.0)
	var ease_open := 1.0 - pow(1.0 - open_t, 3.0)
	_fade_rect.color.a = clampf(1.0 - open_t * 1.4, 0.0, 1.0)
	_top_lid.anchor_bottom = lerpf(0.5, 0.0, ease_open)
	_bot_lid.anchor_top = lerpf(0.5, 1.0, ease_open)

	var beat: Dictionary = BEATS[beat_index]
	var t := clampf(_beat_elapsed / float(beat.duration), 0.0, 1.0)
	var smooth := t * t * (3.0 - 2.0 * t)
	_apply_camera_shot(str(beat.shot), smooth)
	if _shift.is_valid():
		# A slow surge rides on top of the per-beat level so the warp never sits still.
		_shift.call(lerpf(_shift_from, float(beat.shift), smooth) * (0.9 + 0.1 * sin(_total_elapsed * 2.3)))

	if _beat_elapsed >= float(beat.duration):
		_advance_beat()

func _apply_camera_shot(shot: String, t: float) -> void:
	var hale_head := (_hale_actor.position if is_instance_valid(_hale_actor) else _cot_pos + HALE_SPOT) + Vector3(0.0, 1.62, 0.0)
	var pend_mid := _pendulum_pos + Vector3(0.0, 1.95, 0.0)
	var cot_eye := _cot_pos + WAKE_EYE
	var stood_eye := _cot_pos + STAND_EYE

	match shot:
		"wake":
			# Lying on the watch cot, two gentle shoulder-shake jolts as Hale wakes the captain
			var shake := sin(_beat_elapsed * 16.0) * exp(-_beat_elapsed * 1.6) * 0.045
			_cutscene_cam.global_position = cot_eye + Vector3(shake, 0.04 * t, 0.0)
			_cutscene_cam.look_at(hale_head + Vector3(0.0, -0.25 + 0.25 * t, 0.0), Vector3.UP)
			_cutscene_cam.rotate_object_local(Vector3.FORWARD, lerpf(0.14, 0.04, t) + shake * 1.4)
			_cutscene_cam.fov = 75.0
		"hale_closeup":
			# Sitting up, focusing on Hale's face and lantern
			_cutscene_cam.global_position = cot_eye.lerp(stood_eye, t)
			_cutscene_cam.look_at(hale_head, Vector3.UP)
			_cutscene_cam.fov = lerpf(75.0, 68.0, t)
		"pendulum_push":
			# Walk the eye out to the wing arcade, arcing round Hale, and find the drifting pendulum
			var bend := stood_eye + Vector3(0.6, 0.15, 1.4)
			_cutscene_cam.global_position = stood_eye.lerp(bend, t).lerp(bend.lerp(ARCADE_EYE, t), t)
			_cutscene_cam.look_at(hale_head.lerp(pend_mid, t), Vector3.UP)
			_cutscene_cam.fov = lerpf(68.0, 58.0, t)
		"pendulum_hold":
			# Ease forward in the arcade mouth; the look slides down the cable to the drift ring
			_cutscene_cam.global_position = ARCADE_EYE + Vector3(0.6 * t, 0.0, -0.2 * t)
			_cutscene_cam.look_at(pend_mid.lerp(_pendulum_pos + Vector3(0.0, 1.45, 0.0), t), Vector3.UP)
			_cutscene_cam.fov = lerpf(58.0, 62.0, t)
		"gate_handoff":
			# Back on your feet by the bed: turn from Hale toward the arcade, no fly-through
			_cutscene_cam.global_position = _player_eye_pos
			var look_end := _player_eye_pos - _player_eye_basis.z * 3.0
			_cutscene_cam.look_at(hale_head.lerp(look_end, t), Vector3.UP)
			_cutscene_cam.fov = lerpf(62.0, _player_cam.fov, t)

func snapshot() -> Dictionary:
	return {
		"active": active,
		"beat_index": beat_index,
		"beat_count": BEATS.size(),
		"beat_id": str(BEATS[beat_index].id) if beat_index >= 0 and beat_index < BEATS.size() else "",
		"camera_pos": _cutscene_cam.global_position if is_instance_valid(_cutscene_cam) else Vector3.ZERO,
		"camera_fov": _cutscene_cam.fov if is_instance_valid(_cutscene_cam) else 0.0,
	}
