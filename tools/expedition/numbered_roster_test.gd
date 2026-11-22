extends SceneTree
const Witnesses := preload("res://scenes/rogue_crossing/HallWitnesses.gd")
const Roster := preload("res://scenes/rogue_crossing/Roster.gd")
const Room := preload("res://scenes/rogue_view/RogueRoomView.tscn")

func _initialize() -> void:
	run.call_deferred()

func run() -> void:
	var room := Room.instantiate()
	room.expedition_view = true
	root.add_child(room)
	var vp: SubViewport = room.get_node("RoomViewport")
	var world: WorldEnvironment = vp.get_node("WorldEnvironment")
	assert(world.environment.sdfgi_enabled and world.environment.adjustment_enabled)
	assert(is_equal_approx(world.environment.adjustment_saturation, 0.76))
	assert(room.set_blueprint_room("Foyer", [], "res://content/academy_lots/foyer.xml") == OK)
	var cast := Witnesses.new()
	room.get_node("RoomViewport/Geometry").add_child(cast)
	var ids: Array = Roster.NAMES.duplicate()
	ids.append("detective")
	var rows := {}
	for id in ids:
		rows[id] = {"cell": Vector2i(14 + ids.find(id) % 5, 16 + ids.find(id) / 5), "status": &"idle"}
	assert(cast.sync(rows, 0.0).size() == 17)
	var numbers := {}
	var converted := 0
	var preserved := 0
	for id in ids:
		var number: int = Roster.model_number(id)
		assert(not numbers.has(number) and number >= 1 and number <= 17)
		numbers[number] = true
		var actor: Node3D = cast.actors[id]
		var src: String = actor.get_meta("model_source")
		assert(src.ends_with("model_%02d.glb" % number))
		var styled := 0
		var raw := 0
		for mesh: MeshInstance3D in actor.find_children("*", "MeshInstance3D", true, false):
			for i in mesh.mesh.get_surface_count():
				var material := mesh.get_active_material(i) as ShaderMaterial
				if material != null and material.shader.resource_path.begins_with("res://scenes/components/rendering/actors/"):
					assert(material.get_shader_parameter("expedition_soft_toon") == true)
					assert(is_equal_approx(material.get_shader_parameter("toon_strength"), 0.58))
					styled += 1
				else:
					raw += 1
		assert(styled > 0)
		converted += styled
		preserved += raw
		print("%02d %s styled=%d preserved=%d" % [number, id, styled, raw])
	if DisplayServer.get_name() != "headless":
		assert(vp.has_node("ExpeditionInk"))
		var cam := vp.get_camera_3d()
		cam.projection = Camera3D.PROJECTION_PERSPECTIVE
		cam.position = Vector3(11.5, 1.75, 17.5)
		cam.look_at(Vector3(16.0, 1.4, 17.5))
		for i in 40: await RenderingServer.frame_post_draw
		var image := vp.get_texture().get_image()
		var crop := image.get_region(Rect2i((image.get_width()-1080)/2,0,1080,720))
		DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://.runtime/expedition-render"))
		assert(crop.save_jpg("res://.runtime/expedition-render/numbered-roster-04.jpg", 0.95) == OK)
	print("Numbered roster PASS: 17 models, %d styled surfaces, %d preserved" % [converted, preserved])
	quit()
