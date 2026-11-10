extends Control

var turntable: Node3D
var angle := 0.0

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	z_index = 100
	var background := ColorRect.new()
	background.color = Color("202b37")
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(background)
	var column := VBoxContainer.new()
	column.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(column)
	var header := HBoxContainer.new()
	column.add_child(header)
	var back := Button.new()
	back.text = "返回建筑器"
	back.pressed.connect(func():
		if get_tree().current_scene == self:
			get_tree().change_scene_to_file("res://tools/building_construction/BuildingSimulator.tscn")
		else:
			queue_free())
	header.add_child(back)
	var title := Label.new()
	title.text = "五人模型预览 · 原有网格、材质与骨骼"
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(title)
	for direction in [-1, 1]:
		var rotate := Button.new()
		rotate.text = "向左转" if direction < 0 else "向右转"
		rotate.pressed.connect(func(): angle += direction * PI / 4.0; _rotate_models())
		header.add_child(rotate)
	var container := SubViewportContainer.new()
	container.stretch = true
	container.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.add_child(container)
	var viewport := SubViewport.new()
	viewport.size = Vector2i(1440, 820)
	viewport.own_world_3d = true
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	container.add_child(viewport)
	var world := Node3D.new()
	viewport.add_child(world)
	var environment := WorldEnvironment.new()
	environment.environment = Environment.new()
	environment.environment.background_mode = Environment.BG_COLOR
	environment.environment.background_color = Color("202b37")
	environment.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.environment.ambient_light_color = Color("ddd6ca")
	environment.environment.ambient_light_energy = 0.65
	world.add_child(environment)
	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-40, -30, 0)
	light.light_energy = 1.4
	light.shadow_enabled = true
	world.add_child(light)
	var camera := Camera3D.new()
	camera.position = Vector3(0, 3.2, 8.8)
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 8.2
	world.add_child(camera)
	camera.look_at(Vector3(0, 0.8, 0))
	var floor_mesh := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(12, 8)
	floor_mesh.mesh = plane
	var material := StandardMaterial3D.new()
	material.albedo_color = Color("50555b")
	material.roughness = 0.9
	floor_mesh.material_override = material
	world.add_child(floor_mesh)
	turntable = Node3D.new()
	world.add_child(turntable)
	var catalog = load("res://scenes/components/characters/ModelCatalog.cs").new()
	var roster: Array = catalog.ReadRoster()
	for index in range(roster.size()):
		var declaration: Dictionary = roster[index]
		var actor := preload("res://scenes/components/characters/CharacterModel.tscn").instantiate()
		turntable.add_child(actor)
		actor.position.x = (index - (roster.size() - 1) / 2.0) * 1.5
		actor.configure(declaration)
		var caption := Label3D.new()
		caption.text = declaration.label
		caption.font_size = 52
		caption.pixel_size = 0.0035
		caption.position = Vector3(actor.position.x, 1.65, 0)
		caption.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		world.add_child(caption)
	var note := Label.new()
	note.text = "美术资源预览；数日自主决策推演通过正式 CLI 运行。"
	note.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(note)

func _rotate_models() -> void:
	for actor in turntable.get_children():
		actor.rotation.y = angle
