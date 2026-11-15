extends Control
## Local drag/drop video processing, measured-motion preview and AnimationLibrary export.
const Character := preload("res://scenes/components/characters/ImportedCharacter.gd")
const Motion := preload("res://scenes/components/characters/VideoMotionLibrary.gd")
const Source := preload("res://mcp/CaptureSource.gd")
const Receipt := preload("res://mcp/CaptureReceipt.gd")
const FONT := preload("res://assets/external/NotoSansSC/NotoSansSC[wght].ttf")
var actor: Node3D
var player: AnimationPlayer
var skeleton: Skeleton3D
var camera: Camera3D
var status_label: Label
var motion_path := ""
var output_dir := ""
var last_report: Dictionary = {}
var process_id := -1
var _poll := 0.0
var _shutdown := false
var _capture_index := 0
var _elapsed := 0.0
var _capture_times: Array[float] = []
var _time_index := 0
var _playback_samples: Array = []
var _fixture_configuration: Dictionary = {}
var _fixture_output := ""

func configure_test_context(configuration: Dictionary, directory: String) -> void:
	_fixture_configuration = configuration.duplicate(true)
	_fixture_output = directory+"/mocap"

func _arg(key: String, fallback := "") -> String:
	if not _fixture_configuration.is_empty():
		if key == "test-duration": return "0"
		if key == "test-output": return _fixture_output
		if _fixture_configuration.has(key): return str(_fixture_configuration[key])
	for item in OS.get_cmdline_user_args():
		if item.begins_with("--"+key+"="): return item.substr(key.length()+3)
	return fallback

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_build_stage()
	var bar := HBoxContainer.new()
	bar.position = Vector2(18,14)
	add_child(bar)
	for item in [["选视频",_choose],["播放",_toggle],["重建",_rebuild],["采集",_capture]]:
		var button := Button.new()
		button.text = str(item[0])
		button.add_theme_font_override("font",FONT)
		button.pressed.connect(item[1])
		bar.add_child(button)
	status_label = Label.new()
	status_label.add_theme_font_override("font",FONT)
	status_label.text = "拖入视频或动作"
	bar.add_child(status_label)
	get_viewport().files_dropped.connect(_files_dropped)
	output_dir = Source.project_output(_arg("test-output","res://.runtime/mocap/previews/"+Time.get_datetime_string_from_system().replace(":","-")))
	if output_dir.is_empty(): status_label.text = "输出路径错误"; return
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(output_dir))
	motion_path = _arg("motion")
	for value in _arg("capture-times","0.25,2.5,4.8").split(",",false): _capture_times.append(float(value))
	if not motion_path.is_empty(): _load_motion(motion_path)
	var video := _arg("video")
	if not video.is_empty(): _start_video(video)

func _build_stage() -> void:
	var layer := SubViewportContainer.new()
	layer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	layer.stretch = true
	layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(layer)
	var viewport := SubViewport.new()
	viewport.size = Vector2i(1280,800)
	viewport.own_world_3d = true
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	layer.add_child(viewport)
	var world := Node3D.new()
	viewport.add_child(world)
	var environment := WorldEnvironment.new()
	environment.environment = Environment.new()
	environment.environment.background_mode = Environment.BG_COLOR
	environment.environment.background_color = Color("#17242c")
	environment.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.environment.ambient_light_color = Color("#a6bbc7")
	environment.environment.ambient_light_energy = 0.6
	world.add_child(environment)
	var key := DirectionalLight3D.new()
	key.rotation_degrees = Vector3(-48,-32,0)
	key.light_energy = 1.3
	key.shadow_enabled = true
	world.add_child(key)
	var floor := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(24,10)
	floor.mesh = plane
	var material := StandardMaterial3D.new()
	material.albedo_color = Color("#425057")
	material.roughness = 0.95
	floor.material_override = material
	world.add_child(floor)
	actor = Node3D.new()
	actor.name = "MeasuredActor"
	world.add_child(actor)
	if not Character.attach(actor,"res://assets/characters/UserModels/model_06.glb",1.32,-90.0,"detective"):
		push_error("Real target model failed to load")
		return
	player = actor.get_meta("animation_player",null)
	skeleton = actor.get_meta("skeleton",null)
	camera = Camera3D.new()
	camera.position = Vector3(0,1.7,5.5)
	world.add_child(camera)
	camera.look_at(Vector3(-0.7,0.65,0))
	camera.fov = 40
	camera.current = true

func _choose() -> void:
	var dialog := FileDialog.new()
	dialog.access = FileDialog.ACCESS_FILESYSTEM
	dialog.file_mode = FileDialog.FILE_MODE_OPEN_FILE
	dialog.use_native_dialog = true
	dialog.filters = PackedStringArray(["*.mp4,*.avi,*.mov,*.mkv;视频","*.json;动作"])
	dialog.file_selected.connect(func(path: String): _files_dropped(PackedStringArray([path])); dialog.queue_free())
	add_child(dialog)
	dialog.popup_centered_ratio(0.7)

func _files_dropped(paths: PackedStringArray) -> void:
	if paths.is_empty(): return
	if paths[0].get_extension().to_lower() == "json": motion_path = paths[0]; _load_motion(motion_path)
	else: _start_video(paths[0])

func _start_video(path: String) -> void:
	if process_id > 0 and OS.is_process_running(process_id): return
	var python := ProjectSettings.globalize_path("res://.runtime/mocap/Scripts/python.exe")
	if not FileAccess.file_exists(python) or not FileAccess.file_exists(path): status_label.text = "视频或环境缺失"; return
	var job := output_dir+"/job-"+str(Time.get_ticks_usec())
	motion_path = job+"/motion.json"
	var args := PackedStringArray([ProjectSettings.globalize_path("res://tools/mocap/video_to_motion.py"),"--video",ProjectSettings.globalize_path(path),"--output",ProjectSettings.globalize_path(job),"--seconds",_arg("seconds","20"),"--subject-x",_arg("subject-x","0.5"),"--subject-y",_arg("subject-y","0.5"),"--crop-width",_arg("crop-width","1.0"),"--crop-height",_arg("crop-height","1.0")])
	process_id = OS.create_process(python,args,false)
	status_label.text = "正在提取" if process_id > 0 else "进程启动失败"

func _load_motion(path: String) -> void:
	if player == null or skeleton == null: status_label.text = "角色骨架缺失"; return
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not parsed is Dictionary: status_label.text = "动作数据错误"; return
	var root := player.get_node(player.root_node)
	var built := Motion.build(skeleton,String(root.get_path_to(skeleton)),parsed,actor,1.32,{"root_policy":_arg("root-policy","measured")})
	if built.has("error"): status_label.text = "重定向失败"; push_error(str(built.error)); return
	player.stop()
	if player.has_animation_library("measured"): player.remove_animation_library("measured")
	player.add_animation_library("measured",built.library)
	var export_path := output_dir+"/retargeted.res"
	var code := ResourceSaver.save(built.library,export_path)
	last_report = built.report
	last_report.merge({"motion_path":ProjectSettings.globalize_path(path),"motion_sha256":FileAccess.get_sha256(path),"animation_path":ProjectSettings.globalize_path(export_path),"export_error":code,"source_identity":Source.identity(get_tree()),"host_pid":OS.get_process_id()},true)
	last_report["animation_sha256"] = FileAccess.get_sha256(export_path) if code == OK else ""
	var target_model := str(actor.get_meta("model_source",""))
	last_report["target_model"] = target_model
	last_report["target_model_sha256"] = FileAccess.get_sha256(target_model)
	last_report["retarget_script_sha256"] = FileAccess.get_sha256("res://scenes/components/characters/VideoMotionLibrary.gd")
	_write_report()
	if code != OK: status_label.text = "导出失败"; return
	var low := Motion.point(last_report.root_min_m)
	var high := Motion.point(last_report.root_max_m)
	var center := (low+high)*0.5+Vector3(0,0.7,0)
	var distance := maxf(5.0,(high.x-low.x+2.0)*0.85)
	camera.position = center+Vector3(0,1.0,distance)
	camera.look_at(center)
	player.play("measured/video")
	player.advance(0.0)
	var quality: Dictionary = last_report.get("source_quality", {})
	var detected := int(quality.get("detected_frames", 0))
	var input_frames := int(quality.get("input_frames", 0))
	var held := int(quality.get("held_frames", 0))
	if bool(quality.get("requires_manual_motion_review", false)):
		status_label.text = "已导出·%d/%d检测·%d保持·待人工审片" % [detected, input_frames, held]
	else:
		status_label.text = "已导出·需修正" if float(last_report.max_rotation_step_deg) > 45.0 else "已导出·待检查"

func _write_report() -> void:
	var file := FileAccess.open(output_dir+"/retarget-report.json",FileAccess.WRITE)
	if file != null: file.store_string(JSON.stringify(last_report,"\t"))

func _toggle() -> void:
	if player == null or not player.has_animation("measured/video"): return
	if player.is_playing(): player.pause()
	else: player.play("measured/video")

func _rebuild() -> void:
	if not motion_path.is_empty() and FileAccess.file_exists(motion_path): _load_motion(motion_path)

func _capture() -> void:
	if DisplayServer.get_name() == "headless": return
	await RenderingServer.frame_post_draw
	_capture_index += 1
	var path := output_dir+"/preview-%03d.png" % _capture_index
	if Receipt.save(get_viewport().get_texture().get_image(),path,get_tree(),"mocap-development-preview"):
		var metadata: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(path+".json"))
		metadata["motion_path"] = motion_path
		metadata["animation_time"] = player.current_animation_position if player != null else 0.0
		var file := FileAccess.open(path+".json",FileAccess.WRITE)
		if file != null: file.store_string(JSON.stringify(metadata,"\t"))

func _process(delta: float) -> void:
	_elapsed += delta
	if _time_index < _capture_times.size() and _elapsed >= _capture_times[_time_index]:
		_time_index += 1
		_capture()
	_poll += delta
	if _poll < 0.3: return
	_poll = 0.0
	if skeleton != null and player != null and player.has_animation("measured/video"):
		var points: Dictionary = {}
		for name in ["Hips","LeftFoot","RightFoot","LeftHand","RightHand"]:
			var bone := Character._find_mixamo_bone(skeleton,name)
			var value := skeleton.global_transform * skeleton.get_bone_global_pose(bone).origin
			points[name] = [value.x,value.y,value.z]
		_playback_samples.append({"elapsed_s":_elapsed,"animation_time":player.current_animation_position,"joints":points})
		var file := FileAccess.open(output_dir+"/playback-observations.json",FileAccess.WRITE)
		if file != null: file.store_string(JSON.stringify(_playback_samples))
	if process_id > 0:
		var path := motion_path.get_base_dir()+"/status.json"
		var snapshot := JSON.new()
		var parsed: Variant = null
		if FileAccess.file_exists(path) and snapshot.parse(FileAccess.get_file_as_string(path)) == OK: parsed = snapshot.data
		if parsed is Dictionary and str(parsed.get("phase","")) == "complete":
			process_id = -1
			_load_motion(motion_path)
		elif not OS.is_process_running(process_id):
			process_id = -1
			status_label.text = "提取失败·查看报告"
	var duration := float(_arg("test-duration","0"))
	if duration > 0 and _elapsed > duration and not _shutdown:
		_shutdown = true
		await _capture()
		get_tree().quit()

func mcp_observe() -> Dictionary:
	return {"mode":"mocap", "motion_path":motion_path,"output_directory":output_dir,"processing":process_id>0,"report":last_report,"animation_time":player.current_animation_position if player != null else 0.0,"status":status_label.text}

func test_snapshot() -> Dictionary:
	return mcp_observe()
