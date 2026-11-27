extends CanvasLayer
## Opening awakening cutscene for the Public Hall, powered by the unified skippable StoryDirector.
## Features natural drowsy double-blink wake-up, smooth Bezier camera arcs toward the lowered
## Panthéon Foucault Pendulum, and a seamless zero-teleport return into first-person control.

signal finished

const Cast = preload("res://scenes/rogue_crossing/ProductionCast.gd")
const StoryDirector = preload("res://scenes/components/shared/StoryDirector.gd")

const WAKE_EYE := Vector3(-0.72, 0.86, 0.0)
const HALE_SPOT := Vector3(1.85, 0.0, -0.5)
const STAND_EYE := Vector3(0.62, 1.55, -0.95)
const ARCADE_EYE := Vector3(11.6, 1.58, 19.2)

const BEATS := [
	{
		"id": "wake_shake",
		"speaker": "Hale",
		"text": "……醒醒。先别急着起身，看着我——能看清吗？",
		"text_en": "...Wake up. Don't get up too fast—look at me. Can you focus?",
		"duration": 3.4,
		"shot": "wake",
		"shift": 0.85,
	},
	{
		"id": "wake_focus",
		"speaker": "",
		"text": "提灯在墙上拖出一红一蓝两道边。床架的线条在晃，像隔着一层热浪看东西——不是没睡醒。",
		"text_en": "The lantern drags red and blue fringes across the plaster. Bedframe edges waver through heat-haze—this isn't lingering sleep.",
		"duration": 3.8,
		"shot": "hale_closeup",
		"shift": 0.72,
	},
	{
		"id": "pendulum_drift",
		"speaker": "Hale",
		"text": "你也看见了：朝你来的发蓝，离你去的发红——源质在漂。中央铜摆过南象限慢了半拍，刻痕已经越过红线三格。",
		"text_en": "You see it too: blueshift toward you, red away—the Essence is drifting. The central pendulum drags half a beat past south, three marks past the red line.",
		"duration": 5.0,
		"shot": "pendulum_push",
		"shift": 0.55,
	},
	{
		"id": "essence_reason",
		"speaker": "Hale",
		"text": "稳压井的源质回流断了。前班撤出时把隔离闸反锁在里面，备用源核还在井下。不换上它，整座学院只会漂得更厉害。",
		"text_en": "The Stabilizer return loop snapped. Last watch bolted the isolating gate from inside, and the spare core is still down the well. Without it, the whole Academy keeps drifting.",
		"duration": 4.8,
		"shot": "pendulum_hold",
		"shift": 0.45,
	},
	{
		"id": "north_gate_handoff",
		"speaker": "Hale",
		"text": "井区守则只放双人编队过闸，整座大厅醒着的只剩你和我。灯和手册在你床头——拿上，北门见。",
		"text_en": "Caisson rules only pass pairs through the gate, and we're the only two awake in the Hall. Your lamp and manual are by the cot—take them and meet me at the north gate.",
		"duration": 4.6,
		"shot": "gate_handoff",
		"shift": 0.25,
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

	_hale_actor = Node3D.new()
	_hale_actor.name = "OpeningHale"
	viewport.add_child(_hale_actor)
	_hale_actor.position = _cot_pos + HALE_SPOT
	Cast.attach_hero(_hale_actor, "hale")
	var pillow := _cot_pos + WAKE_EYE
	_hale_actor.look_at(Vector3(pillow.x, 0.0, pillow.z), Vector3.UP, true)

	_director.play_sequence({
		"beats": BEATS,
		"viewport": viewport,
		"player_cam": player_cam,
		"eyelid_duration": 2.4,
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
	var hale_head := (_hale_actor.position if is_instance_valid(_hale_actor) else _cot_pos + HALE_SPOT) + Vector3(0.0, 1.62, 0.0)
	# Aim cleanly at the lowered Panthéon Foucault Pendulum bob & brass railing dial
	var pend_bob := _pendulum_pos + Vector3(0.0, 0.58, 0.0)
	var pend_mid := _pendulum_pos + Vector3(0.0, 1.35, 0.0)
	var cot_eye := _cot_pos + WAKE_EYE
	var stood_eye := _cot_pos + STAND_EYE
	var arcade_end := ARCADE_EYE + Vector3(0.55, 0.0, -0.25)

	match str(beat.get("shot", "")):
		"wake":
			# Gentle shoulder-wake sway (smooth damped roll, no harsh jitter)
			var sway := sin(elapsed * 4.5) * exp(-elapsed * 1.1) * 0.022
			cam.global_position = cot_eye + Vector3(sway, 0.05 * t, 0.0)
			cam.look_at(hale_head + Vector3(0.0, -0.20 + 0.20 * t, 0.0), Vector3.UP)
			cam.rotate_object_local(Vector3.FORWARD, lerpf(0.11, 0.02, t) + sway * 1.2)
			cam.fov = 74.0
		"hale_closeup":
			# Smooth sit-up arc focusing on Hale
			var mid_lift := cot_eye.lerp(stood_eye, 0.5) + Vector3(0.0, 0.14, -0.10)
			cam.global_position = cot_eye.lerp(mid_lift, t).lerp(mid_lift.lerp(stood_eye, t), t)
			cam.look_at(hale_head, Vector3.UP)
			cam.fov = lerpf(74.0, 67.0, t)
		"pendulum_push":
			# Smooth Bezier glide out to the west arcade, revealing the lowered Panthéon pendulum
			var bend := stood_eye + Vector3(0.6, 0.12, 1.35)
			cam.global_position = stood_eye.lerp(bend, t).lerp(bend.lerp(ARCADE_EYE, t), t)
			cam.look_at(hale_head.lerp(pend_mid, t), Vector3.UP)
			cam.fov = lerpf(67.0, 58.0, t)
		"pendulum_hold":
			# Ease forward & tilt down onto the brass bob and red calibration bezel
			cam.global_position = ARCADE_EYE.lerp(arcade_end, t)
			cam.look_at(pend_mid.lerp(pend_bob, t), Vector3.UP)
			cam.fov = lerpf(58.0, 61.0, t)
		"gate_handoff":
			# Seamless curved return glide back into exact first-person player eye (zero hard teleport!)
			var return_ctrl := arcade_end.lerp(_player_eye_pos, 0.5) + Vector3(0.0, 0.16, 0.45)
			cam.global_position = arcade_end.lerp(return_ctrl, t).lerp(return_ctrl.lerp(_player_eye_pos, t), t)
			var look_end := _player_eye_pos - _player_eye_basis.z * 3.0
			cam.look_at(pend_bob.lerp(look_end, t), Vector3.UP)
			cam.fov = lerpf(61.0, _player_fov, t)

func snapshot() -> Dictionary:
	return _director.snapshot() if is_instance_valid(_director) else {}
