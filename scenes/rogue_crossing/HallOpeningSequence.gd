extends CanvasLayer
## Opening natural-wake cutscene for the Public Hall (03:38 AM), powered by StoryDirector.
## Strictly obeys the Epistemic Firewall: protagonist wakes naturally in the West Wing,
## walks to the arcade opening, and catches sight of Hale silently timing the central
## Foucault pendulum (H1) while low mist creeps under the North archway.

signal finished

const Cast = preload("res://scenes/rogue_crossing/ProductionCast.gd")
const StoryDirector = preload("res://scenes/components/shared/StoryDirector.gd")

const WAKE_EYE := Vector3(-0.72, 0.86, 0.0)
const STAND_EYE := Vector3(0.62, 1.55, -0.95)
const ARCADE_EYE := Vector3(11.6, 1.58, 19.2)

const BEATS := [
	{
		"id": "natural_wake",
		"speaker": "",
		"text": "凌晨三点三十八分。你在西翼床铺上自然醒来，床畔放着煤油提灯、正常走时的机械怀表与《学院夜间守则抄本》。",
		"text_en": "03:38 AM. You wake naturally on the west-wing cot. Beside you rest a kerosene lantern, a steady pocket watch, and the Academy Night Rules.",
		"duration": 4.2,
		"shot": "wake",
		"shift": 0.0,
	},
	{
		"id": "hale_timing",
		"speaker": "",
		"text": "走出西翼拱廊，整座大厅寂静无人——只有霍铎站在中央傅科摆栏杆旁，低头对着怀表默数，紧盯深石板上的中心铜钉。",
		"text_en": "Stepping into the arcade, the vast Hall is empty save for Hale—standing by the central Foucault pendulum railing, silently timing the bob against his pocket watch.",
		"duration": 4.5,
		"shot": "arcade_reveal",
		"shift": 0.0,
	},
	{
		"id": "pendulum_observe",
		"speaker": "",
		"text": "悬索与黄铜摆锤毫无外力损伤，但摆尖每次掠过都偏离了中心铜钉外侧；远处北翼拱门门缝下，一层薄薄的白雾正贴地渗入。",
		"text_en": "The wire and brass bob are undamaged, yet every sweep curves past the center brass pin—and far ahead, a thin ribbon of pale mist creeps under the north archway.",
		"duration": 4.6,
		"shot": "pendulum_hold",
		"shift": 0.0,
	},
	{
		"id": "hale_handoff",
		"speaker": "Hale",
		"text": "你也醒了？大厅里没东西损坏，唯独北门缝隙在渗白雾和海盐味。整点前得去北翼查一趟——你可以先测测中央的傅科摆，准备好就过来找我。",
		"text_en": "You're awake too? Nothing in the Hall is broken—only the north archway is leaking mist and sea-salt air. Feel free to time the pendulum first, then meet me when ready.",
		"duration": 4.8,
		"shot": "gate_handoff",
		"shift": 0.0,
	},
]

var active: bool:
	get: return is_instance_valid(_director) and _director.active

var beat_index: int:
	get: return _director.beat_index if is_instance_valid(_director) else -1

var _director: CanvasLayer
var _hale_actor: Node3D
var _cot_pos := Vector3.ZERO
var _pendulum_pos := Vector3.ZERO
var _player_eye_pos := Vector3.ZERO
var _player_eye_basis := Basis.IDENTITY
var _player_fov := 73.0

func _ready() -> void:
	layer = 20
	_director = StoryDirector.new()
	add_child(_director)
	_director.finished.connect(func(_skipped: bool) -> void: finished.emit())

func start(viewport: SubViewport, player_cam: Camera3D, cot_pos: Vector3, pendulum_pos: Vector3, _gate_pos: Vector3, shift := Callable()) -> void:
	if active or viewport == null or player_cam == null:
		return
	_cot_pos = cot_pos
	_pendulum_pos = pendulum_pos
	_player_eye_pos = player_cam.global_position
	_player_eye_basis = player_cam.global_transform.basis
	_player_fov = player_cam.fov

	# Place Hale silently timing the central Foucault pendulum (NW edge of the Ø3.2m dial)
	_hale_actor = Node3D.new()
	_hale_actor.name = "OpeningHale"
	viewport.add_child(_hale_actor)
	_hale_actor.position = _pendulum_pos + Vector3(-1.85, 0.0, -1.10)
	Cast.attach_hero(_hale_actor, "hale")
	_hale_actor.look_at(Vector3(_pendulum_pos.x, 0.0, _pendulum_pos.z), Vector3.UP, true)

	_director.play_sequence({
		"beats": BEATS,
		"viewport": viewport,
		"player_cam": player_cam,
		"eyelid_duration": 2.0,
		"shot_driver": _drive_camera,
		"shift_driver": shift,
		"on_beat_enter": _on_beat_enter,
		"on_cleanup": _on_cleanup,
	})

func skip() -> void:
	if is_instance_valid(_director):
		_director.skip()

func _on_beat_enter(beat: Dictionary) -> void:
	if is_instance_valid(_hale_actor) and _hale_actor.has_meta("animation_player"):
		var anim := _hale_actor.get_meta("animation_player") as AnimationPlayer
		anim.play(&"signal" if str(beat.get("speaker", "")) == "Hale" else &"listen", 0.4)

func _on_cleanup(_skipped: bool) -> void:
	if is_instance_valid(_hale_actor):
		_hale_actor.queue_free()
	_hale_actor = null

func _drive_camera(cam: Camera3D, beat: Dictionary, t: float, elapsed: float) -> void:
	var hale_head := (_hale_actor.position if is_instance_valid(_hale_actor) else _pendulum_pos + Vector3(-1.85, 0.0, -1.10)) + Vector3(0.0, 1.62, 0.0)
	var pend_bob := _pendulum_pos + Vector3(0.0, 0.45, 0.0)
	var pend_mid := _pendulum_pos + Vector3(0.0, 1.25, 0.0)
	var cot_eye := _cot_pos + WAKE_EYE
	var stood_eye := _cot_pos + STAND_EYE
	var arcade_end := ARCADE_EYE + Vector3(0.55, 0.0, -0.25)

	match str(beat.get("shot", "")):
		"wake":
			var sway := sin(elapsed * 2.2) * exp(-elapsed * 0.9) * 0.014
			cam.global_position = cot_eye.lerp(stood_eye, t * 0.65) + Vector3(sway, 0.0, 0.0)
			cam.look_at((cot_eye + Vector3(3.0, 0.25, -0.2)).lerp(pend_mid, t * 0.45), Vector3.UP)
			cam.fov = 73.0
		"arcade_reveal":
			var bend := stood_eye + Vector3(0.6, 0.10, 1.20)
			cam.global_position = stood_eye.lerp(bend, t).lerp(bend.lerp(ARCADE_EYE, t), t)
			cam.look_at(pend_mid.lerp(hale_head, 0.45 * t), Vector3.UP)
			cam.fov = lerpf(73.0, 64.0, t)
		"pendulum_hold":
			cam.global_position = ARCADE_EYE.lerp(arcade_end, t)
			cam.look_at(hale_head.lerp(pend_bob, t), Vector3.UP)
			cam.fov = lerpf(64.0, 60.0, t)
		"gate_handoff":
			var return_ctrl := arcade_end.lerp(_player_eye_pos, 0.5) + Vector3(0.0, 0.14, 0.40)
			cam.global_position = arcade_end.lerp(return_ctrl, t).lerp(return_ctrl.lerp(_player_eye_pos, t), t)
			var look_end := _player_eye_pos - _player_eye_basis.z * 3.0
			cam.look_at(pend_bob.lerp(look_end, t), Vector3.UP)
			cam.fov = lerpf(60.0, _player_fov, t)

func snapshot() -> Dictionary:
	return _director.snapshot() if is_instance_valid(_director) else {}
