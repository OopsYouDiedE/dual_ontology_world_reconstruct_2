extends CanvasLayer
## Opening awakening cutscene and camera choreography for the Public Hall.
##
## Story beat (2nd-pass human-realism revision):
##   1. Protagonist wakes from a short watch nap (eyelid fade + gentle shoulder-shake).
##   2. Hale—apologetic, keeping his voice low so sleeping residents don't panic—explains
##      he triple-checked the meridian scale before waking the captain.
##   3. Camera pans and pushes toward the suspended brass Foucault Pendulum drifting off
##      the southern quadrant red mark; Hale notes the Essence return line stalled.
##   4. Camera turns toward the North Departure Gate beneath the rose window; Hale reminds
##      the captain that airlock regulations require two-person sign-off and leaves the
##      lantern & manual at hand, handing control smoothly back to first-person play.

signal finished

const Cast = preload("res://scenes/rogue_crossing/ProductionCast.gd")

const BEATS := [
	{
		"id": "wake_shake",
		"speaker": "Hale",
		"text": "……醒醒，先别出声。对不住，我知道你刚换班躺下不到两小时。",
		"folio": "04:00  /  常数锚定厅 · 值守卧榻",
		"duration": 3.4,
		"shot": "wake"
	},
	{
		"id": "wake_focus",
		"speaker": "",
		"text": "提灯的光晃得眼眶发酸。大厅里太安静了——连中央铜摆那点惯常的底噪都变了调。",
		"folio": "04:00  /  常数锚定厅 · 值守卧榻",
		"duration": 3.5,
		"shot": "hale_closeup"
	},
	{
		"id": "pendulum_drift",
		"speaker": "Hale",
		"text": "我拿着尺子复核了三遍，不是我眼花。你看中央的傅科摆——过南象限时明显拖慢了半拍，进动刻痕已经越过红线三格了。",
		"folio": "04:01  /  常数锚定井 · 傅科摆偏航",
		"duration": 4.8,
		"shot": "pendulum_push"
	},
	{
		"id": "essence_reason",
		"speaker": "Hale",
		"text": "稳压室那头的源质回流断了。我没敢拉全厅警报，大伙折腾一整夜刚睡安稳，闹起来只会更乱。",
		"folio": "04:01  /  常数锚定井 · 源质失衡",
		"duration": 4.4,
		"shot": "pendulum_hold"
	},
	{
		"id": "north_gate_handoff",
		"speaker": "Hale",
		"text": "按守则，开外翼气密闸必须队长签字、双人编队，我一个人进不去。手册和灯我都替你放手边了——缓过神就来北门汇合，我们去取源质回来校正。",
		"folio": "04:02  /  北端气密出征闸门",
		"duration": 5.2,
		"shot": "gate_handoff"
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
var _gate_pos := Vector3.ZERO
var _player_eye_pos := Vector3.ZERO
var _player_eye_basis := Basis.IDENTITY

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

	var plate := PanelContainer.new()
	plate.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.04, 0.048, 0.045, 0.88)
	style.border_color = Color("a88953")
	style.set_border_width_all(1)
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

func start(viewport: SubViewport, player_cam: Camera3D, cot_pos: Vector3, pendulum_pos: Vector3, gate_pos: Vector3) -> void:
	if active or viewport == null or player_cam == null:
		return
	_viewport = viewport
	_player_cam = player_cam
	_cot_pos = cot_pos
	_pendulum_pos = pendulum_pos
	_gate_pos = gate_pos
	_player_eye_pos = player_cam.global_position
	_player_eye_basis = player_cam.global_transform.basis

	# Spawn Hale beside the watch cot using the unified 6.5-head production cast
	_hale_actor = Node3D.new()
	_hale_actor.name = "OpeningHale"
	_viewport.add_child(_hale_actor)
	var hale_pos := _cot_pos + Vector3(0.95, 0.0, -0.55)
	_hale_actor.position = hale_pos
	Cast.attach(_hale_actor, 0)
	_hale_actor.look_at(Vector3(_cot_pos.x, 0.0, _cot_pos.z), Vector3.UP, true)

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
	_folio_label.text = beat.folio
	_speaker_label.text = beat.speaker if not str(beat.speaker).is_empty() else "（意识渐清）"
	_caption_label.text = beat.text

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

	if _beat_elapsed >= float(beat.duration):
		_advance_beat()

func _apply_camera_shot(shot: String, t: float) -> void:
	var hale_head := (_hale_actor.position if is_instance_valid(_hale_actor) else _cot_pos + Vector3(0.95, 0.0, -0.55)) + Vector3(0.0, 1.48, 0.0)
	var pend_mid := _pendulum_pos + Vector3(0.0, 1.95, 0.0)
	var gate_look := _gate_pos + Vector3(0.0, 2.25, 0.0)
	var cot_eye := _cot_pos + Vector3(0.0, 0.86, 0.0)
	var stood_eye := _cot_pos + Vector3(0.35, 1.52, -0.35)

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
			# Pan and push toward the drifting brass Foucault Pendulum under the Gothic vault
			var push_pos := stood_eye.lerp(_pendulum_pos + Vector3(0.0, 1.65, 6.7), t)
			_cutscene_cam.global_position = push_pos
			_cutscene_cam.look_at(hale_head.lerp(pend_mid, t), Vector3.UP)
			_cutscene_cam.fov = lerpf(68.0, 58.0, t)
		"pendulum_hold":
			# Slight upward tilt along the cable to the vaulted keystone, then down to the red drift ring
			var hold_pos := _pendulum_pos + Vector3(0.0, 1.65, 6.7 - 0.25 * t)
			var look_pt := pend_mid.lerp(_pendulum_pos + Vector3(0.0, 1.45, 0.0), t)
			_cutscene_cam.global_position = hold_pos
			_cutscene_cam.look_at(look_pt, Vector3.UP)
			_cutscene_cam.fov = lerpf(58.0, 62.0, t)
		"gate_handoff":
			# Pan from pendulum to North Departure Gate & smoothly settle into player's first-person eye
			var start_pos := _pendulum_pos + Vector3(0.0, 1.65, 6.45)
			_cutscene_cam.global_position = start_pos.lerp(_player_eye_pos, t)
			var look_end := _player_eye_pos - _player_eye_basis.z * 3.0
			_cutscene_cam.look_at(gate_look.lerp(look_end, t), Vector3.UP)
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
