extends SceneTree
## Preview the muscle.py sweep in a disposable Godot project.

const CAST := ["detective", "halvard", "jane", "qingyue"]
const TITLES := ["R-05  /  DETECTIVE  /  M 27  /  177 CM", "R-06  /  HALVARD  /  M 29  /  182 CM*",
	"R-03  /  JANE COX  /  F 19  /  156 CM*", "R-10  /  QINGYUE  /  F 19  /  164 CM*"]
const LEVELS := ["050", "075", "100"]
const FIT_CAPTIONS := ["DESIGN REFERENCE", "GLOBAL ONLY", "LOCAL FIT"]
const CAPTIONS := ["0.50   DEFAULT", "0.75   RAISED", "1.00   MAXIMUM"]
const CLIP := &"MPFB_Pose_Check"
const CAMERA_SIZE := 2.22
var stage: Node3D
var camera: Camera3D
var heading: Label
var subheading: Label
var labels: Array[Label] = []
var actors: Array[Node3D] = []
var players: Array[AnimationPlayer] = []
var design_fit := false
var levels: Array = LEVELS


func _initialize() -> void:
	call_deferred("run")


func run() -> void:
	var args := OS.get_cmdline_user_args()
	var check_only := "--check-only" in args
	design_fit = "--design-fit" in args
	if design_fit:
		levels = ["base", "fit"]
	if not check_only and RenderingServer.get_current_rendering_method() != "forward_plus":
		fail("Expected Forward+ for the comparison sheets")
		return
	stage = Node3D.new()
	root.add_child(stage)
	var receipt := {}
	for name: String in CAST:
		for level: String in levels:
			var stem := "%s-%s" % [name, level]
			var scene := load("res://%s.glb" % stem) as PackedScene
			if scene == null:
				fail("Missing GLB: " + stem)
				return
			var model := scene.instantiate() as Node3D
			stage.add_child(model)
			model.hide()
			var rigs := model.find_children("*", "Skeleton3D", true, false)
			var animations := model.find_children("*", "AnimationPlayer", true, false)
			if rigs.size() != 1 or animations.size() != 1:
				fail("Missing or duplicate rig/player: " + stem)
				return
			var skeleton := rigs[0] as Skeleton3D
			var player := animations[0] as AnimationPlayer
			var arm := skeleton.find_bone("lowerarm_r")
			var knee := skeleton.find_bone("calf_r")
			if mini(arm, knee) < 0 or skeleton.get_bone_count() != 53 or not player.has_animation(CLIP):
				fail("Invalid animation contract: " + stem)
				return
			player.play(CLIP)
			player.pause()
			player.seek(0.0, true)
			var arm_rest := skeleton.get_bone_pose_rotation(arm)
			var knee_rest := skeleton.get_bone_pose_rotation(knee)
			player.seek(0.75, true)
			var elbow := rad_to_deg(arm_rest.angle_to(skeleton.get_bone_pose_rotation(arm)))
			player.seek(2.25, true)
			var calf := rad_to_deg(knee_rest.angle_to(skeleton.get_bone_pose_rotation(knee)))
			if absf(elbow - 45.0) > 1.0 or absf(calf - 44.0) > 1.0:
				fail("Unexpected elbow or knee bend: %s, %.2f, %.2f" % [stem, elbow, calf])
				return
			actors.append(model)
			players.append(player)
			receipt[stem] = {"bones": 53, "elbow_deg": elbow, "knee_deg": calf}
	print("MPFB_MUSCLE_GODOT_PASS ", JSON.stringify(receipt))
	if check_only:
		quit()
		return
	var file := FileAccess.open("res://pose-receipt.json", FileAccess.WRITE)
	if file == null:
		fail("Could not write pose receipt")
		return
	file.store_string(JSON.stringify(receipt, "\t"))
	file.close()
	make_stage()
	if not await capture_sheet("01-front", "FRONT  /  A-POSE", 0.0, 0.0):
		return
	if not await capture_sheet("02-back", "BACK  /  A-POSE", PI, 0.0):
		return
	if not await capture_sheet("03-side", "SIDE  /  A-POSE", -PI / 2.0, 0.0):
		return
	if not await capture_sheet("04-reach", "3/4 FRONT  /  REACH", -0.53, 0.75):
		return
	if not await capture_sheet("05-stride", "3/4 SIDE  /  KNEE BEND", -1.26, 2.25):
		return
	quit()


func fail(message: String) -> void:
	push_error(message)
	quit(1)


func add_label(text: String, font_size: int, color: Color) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	stage.add_child(label)
	return label


func make_stage() -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color("252e36")
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color("e3f1ff")
	env.ambient_light_energy = 0.38
	var world := WorldEnvironment.new()
	world.environment = env
	stage.add_child(world)
	for spec in [[Vector3(2, 3, 4), 1.55, Color("fff0e1")],
			[Vector3(-3, 2, -2), 1.00, Color("d6e8ff")]]:
		var light := DirectionalLight3D.new()
		stage.add_child(light)
		light.position = spec[0]
		light.look_at(Vector3.UP)
		light.light_energy = spec[1]
		light.light_color = spec[2]
	camera = Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = CAMERA_SIZE
	stage.add_child(camera)
	var center := Vector3(0, 0.95, 0)
	camera.position = center + Vector3(0, 0, 5)
	camera.look_at(center)
	camera.make_current()
	heading = add_label("", 32, Color("fff3dd"))
	heading.position = Vector2(28, 15)
	subheading = add_label("", 20, Color("bbcbd8"))
	subheading.position = Vector2(29, 56)
	for caption in (FIT_CAPTIONS if design_fit else CAPTIONS):
		labels.append(add_label(caption, 25, Color("edf0f2")))


func capture_sheet(stem: String, view_title: String, yaw: float, time: float) -> bool:
	var w := int(root.get_visible_rect().size.x)
	var h := int(root.get_visible_rect().size.y)
	var sheet := Image.create_empty(2 * w, 2 * h, false, Image.FORMAT_RGB8)
	var with_reference := design_fit and stem == "01-front"
	var column_count := 3 if with_reference else levels.size()
	for row in CAST.size():
		heading.text = TITLES[row]
		var study := "MPFB LOCAL FIT" if design_fit else "MPFB MUSCLE STUDY"
		subheading.text = "%s    /    %s    /    * REVIEW HEIGHT" % [study, view_title]
		var first := row * levels.size()
		for i in actors.size():
			actors[i].visible = i >= first and i < first + levels.size()
			if not actors[i].visible:
				continue
			var column := i - first + (1 if with_reference else 0)
			var actor := actors[i]
			actor.position.x = (column - (column_count - 1) * 0.5) * CAMERA_SIZE * float(w) / float(h) / column_count
			actor.rotation.y = yaw
			players[i].seek(time, true)
		for i in labels.size():
			labels[i].visible = not (design_fit and i == 0 and not with_reference)
			if labels[i].visible:
				var column := i - (1 if design_fit and not with_reference else 0)
				var pixel_x := (column + 0.5) * w / column_count
				labels[i].position = Vector2(pixel_x - labels[i].get_minimum_size().x / 2, h - 49)
		await process_frame
		await RenderingServer.frame_post_draw
		var shot := root.get_texture().get_image()
		if shot.get_size() != Vector2i(w, h):
			fail("Viewport and capture dimensions differ: %s vs %s" % [Vector2i(w, h), shot.get_size()])
			return false
		shot.convert(Image.FORMAT_RGB8)
		sheet.blit_rect(shot, Rect2i(0, 0, w, h), Vector2i(row % 2 * w, row / 2 * h))
	if sheet.save_png("res://%s.png" % stem) != OK:
		fail("Could not save " + stem)
		return false
	return true
