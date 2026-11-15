extends "res://tools/mocap/MocapPreview.gd"
const Face := preload("res://scenes/components/characters/ExpressionController.gd")
var controller: Node
var _expression_index := 0
var _expression_clock := 0.0
var _expression_captures: Array = []
const ORDER := ["neutral","concern","resolve","fear","relief"]

func configure_test_context(configuration: Dictionary, directory: String) -> void:
	_fixture_configuration = configuration.duplicate(true)
	_fixture_output = directory+"/expressions"

func _ready() -> void:
	super._ready()
	for child in get_children():
		if child is HBoxContainer: child.hide()
	get_viewport().files_dropped.disconnect(_files_dropped)
	controller = Face.new()
	actor.add_child(controller)
	controller.install(actor)
	controller.set_expression("neutral",0.01)
	for environment in actor.get_parent().find_children("*","WorldEnvironment",true,false):
		environment.environment.tonemap_mode = Environment.TONE_MAPPER_ACES
		environment.environment.tonemap_exposure = 0.85
		environment.environment.ambient_light_energy = 0.35
	for light in actor.get_parent().find_children("*","DirectionalLight3D",true,false): light.light_energy = 0.75
	var position := skeleton.global_transform*skeleton.get_bone_global_pose(preload("res://scenes/components/characters/ImportedCharacter.gd")._find_mixamo_bone(skeleton,"Head")).origin
	camera.position = position+Vector3(0,0.10,1.25)
	camera.look_at(position+Vector3(0,0.10,0))
	camera.fov = 30
	var next := Button.new()
	next.text = "下一表情"
	next.add_theme_font_override("font",FONT)
	next.position = Vector2(18,18)
	next.pressed.connect(_next)
	add_child(next)

func _next() -> void:
	_expression_index = (_expression_index+1)%ORDER.size()
	controller.set_expression(ORDER[_expression_index])
	_expression_clock = 0.0

func _process(delta: float) -> void:
	if controller == null: return
	_expression_clock += delta
	_elapsed += delta
	if _expression_clock >= 1.2 and _expression_captures.size() == _expression_index:
		_expression_captures.append(controller.test_snapshot())
		_capture()
		var file := FileAccess.open(output_dir+"/expression-report.json",FileAccess.WRITE)
		if file != null: file.store_string(JSON.stringify(_expression_captures,"\t"))
	if _arg("expression-auto","false") == "true" and _expression_clock>2.0 and _expression_index<ORDER.size()-1: _next()
	var duration := float(_arg("test-duration","0"))
	if duration>0 and _elapsed>=duration and not _shutdown:
		_shutdown = true
		get_tree().quit()

func test_snapshot() -> Dictionary:
	return mcp_observe()

func mcp_observe() -> Dictionary:
	var result: Dictionary = controller.test_snapshot() if controller != null else {}
	result.merge({"mode":"expression","output_directory":output_dir,"capture_count":_expression_captures.size(),"model_source":actor.get_meta("model_source","") if actor != null else ""},true)
	return result

func _capture() -> void:
	if DisplayServer.get_name() == "headless": return
	await RenderingServer.frame_post_draw
	_capture_index += 1
	var path := output_dir+"/expression-%03d.png" % _capture_index
	if Receipt.save(get_viewport().get_texture().get_image(),path,get_tree(),"expression-development-preview"):
		var metadata: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(path+".json"))
		metadata["expression"] = controller.test_snapshot()
		metadata["model_source"] = actor.get_meta("model_source","")
		metadata["model_sha256"] = FileAccess.get_sha256(str(metadata.model_source))
		var file := FileAccess.open(path+".json",FileAccess.WRITE)
		if file != null: file.store_string(JSON.stringify(metadata,"\t"))
