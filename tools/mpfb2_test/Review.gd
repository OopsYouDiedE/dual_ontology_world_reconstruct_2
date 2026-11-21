extends SceneTree
## Isolated asset preview. Run after importing build.py's GLBs.

const CLIP := &"MPFB_Pose_Check"
const TITLES := ["HM08  /  26,928 tris", "BLENDER COLLAPSE  /  4,872 tris",
	"MPFB MALE1591  /  3,312 tris", "MPFB CASUAL SUIT  /  36,872 tris"]
const ASSETS := ["full", "collapse", "proxy", "dressed"]
var actors: Array[Node3D] = []
var players: Array[AnimationPlayer] = []
var skeletons: Array[Skeleton3D] = []
var labels: Array[Label] = []
var camera: Camera3D
var subtitle: Label
var stage: Node3D


func _initialize() -> void:
	call_deferred("run")


func run() -> void:
	var check_only := "--check-only" in OS.get_cmdline_user_args()
	if not check_only and RenderingServer.get_current_rendering_method() != "forward_plus":
		fail("Expected Forward+ for screenshots")
		return
	stage = Node3D.new()
	root.add_child(stage)
	for i in ASSETS.size():
		var scene := load("res://%s.glb" % ASSETS[i]) as PackedScene
		if scene == null:
			fail("GLB failed to load: " + ASSETS[i])
			return
		var model := scene.instantiate() as Node3D
		var rigs := model.find_children("*", "Skeleton3D", true, false)
		var animators := model.find_children("*", "AnimationPlayer", true, false)
		if rigs.size() != 1 or animators.size() != 1:
			fail("Expected one skeleton and animation player in " + ASSETS[i])
			return
		var skeleton := rigs[0] as Skeleton3D
		var player := animators[0] as AnimationPlayer
		if skeleton.get_bone_count() != 53 or not player.has_animation(CLIP):
			fail("Invalid bone or clip count in " + ASSETS[i])
			return
		stage.add_child(model)
		actors.append(model)
		skeletons.append(skeleton)
		players.append(player)
		player.play(CLIP)
		player.pause()
	var measurements := {}
	for i in ASSETS.size():
		var arm := skeletons[i].find_bone("lowerarm_r")
		var knee := skeletons[i].find_bone("calf_r")
		var hips := skeletons[i].find_bone("thigh_r")
		if mini(mini(arm, knee), hips) < 0:
			fail("Missing pose-test bones in " + ASSETS[i])
			return
		set_time(0.0)
		var arm_start := skeletons[i].get_bone_pose_rotation(arm)
		var knee_start := skeletons[i].get_bone_pose_rotation(knee)
		var hip_start := skeletons[i].get_bone_pose_rotation(hips)
		set_time(0.75)
		var arm_deg := rad_to_deg(arm_start.angle_to(skeletons[i].get_bone_pose_rotation(arm)))
		set_time(2.25)
		var knee_deg := rad_to_deg(knee_start.angle_to(skeletons[i].get_bone_pose_rotation(knee)))
		var hip_deg := rad_to_deg(hip_start.angle_to(skeletons[i].get_bone_pose_rotation(hips)))
		if absf(arm_deg - 45.0) > 1.0 or absf(knee_deg - 44.0) > 1.0 or absf(hip_deg - 29.0) > 1.0:
			fail("Failed to sample pose-test animation in " + ASSETS[i])
			return
		measurements[ASSETS[i]] = {"elbow_delta_deg": arm_deg, "knee_delta_deg": knee_deg,
			"hip_delta_deg": hip_deg, "bones": skeletons[i].get_bone_count()}
	print("MPFB2_GODOT_PASS ", JSON.stringify(measurements))
	if check_only:
		quit()
		return
	make_stage()
	arrange(false, 0.0, 0.0, 0.92, 2.24, "01   /   FRONT   /   A-POSE")
	await capture("01-front")
	arrange(false, -1.26, 2.25, 0.92, 2.24, "02   /   SIDE   /   STRIDE & KNEE BEND")
	await capture("02-stride")
	arrange(false, 0.32, 0.0, 1.58, 0.80, "03   /   FACE & SHOULDER   /   A-POSE")
	await capture("03-portrait")
	arrange(true, 0.45, 0.75, 0.92, 2.24, "04   /   STOCK FITTED CLOTHES   /   REACH")
	await capture("04-suit")
	quit()


func fail(message: String) -> void:
	push_error(message)
	quit(1)


func set_time(time: float) -> void:
	for player in players:
		player.seek(time, true)


func add_label(text: String, font_size: int) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", Color("f0e9d9"))
	stage.add_child(label)
	return label


func make_stage() -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color("283844")
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color("dbebff")
	env.ambient_light_energy = 0.45
	var world := WorldEnvironment.new()
	world.environment = env
	stage.add_child(world)
	for spec in [[Vector3(2, 3, 4), 1.3, Color("ffe7cb")],
			[Vector3(-3, 2, -2), 0.95, Color("c7defd")]]:
		var light := DirectionalLight3D.new()
		stage.add_child(light)
		light.position = spec[0]
		light.look_at(Vector3.UP)
		light.light_energy = spec[1]
		light.light_color = spec[2]
	camera = Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	stage.add_child(camera)
	camera.make_current()
	for title in TITLES:
		labels.append(add_label(title, 18))
	subtitle = add_label("", 22)
	subtitle.position = Vector2(26, 17)


func arrange(suit: bool, yaw: float, time: float, center_y: float, size: float, title: String) -> void:
	var center := Vector3(0, center_y, 0)
	camera.position = center + Vector3(0, 0, 5)
	camera.look_at(center)
	camera.size = size
	set_time(time)
	subtitle.text = title
	for i in actors.size():
		actors[i].visible = (i == 3) if suit else (i < 3)
		actors[i].position.x = 0.0 if suit else (i - 1) * size * 0.61
		actors[i].rotation.y = yaw
		labels[i].visible = actors[i].visible
		var anchor := camera.unproject_position(Vector3(actors[i].position.x, center_y, 0))
		labels[i].position = Vector2(anchor.x - labels[i].get_minimum_size().x / 2.0, root.size.y - 44)


func capture(name: String) -> void:
	await RenderingServer.frame_post_draw
	var image := root.get_texture().get_image()
	if image.save_png("res://%s.png" % name) != OK:
		fail("Could not write screenshot " + name)
