extends Node3D
## Isolated render review; uses Expedition light_stage and material factory unchanged.
const SAMPLE := "res://.runtime/french-gn/main/original-group-bay.glb"
var cam := Camera3D.new()
var view := 0
var meshes := 0
var environment: Environment

func _ready() -> void:
	var stage := preload("res://scenes/expedition_01/Expedition.gd").new()
	stage.light_stage()
	for item in stage.get_children():
		stage.remove_child(item)
		add_child(item)
		if item is WorldEnvironment: environment = item.environment
	stage.free()
	var palette := preload("res://scenes/expedition_01/Masonry.gd").new()
	var state := GLTFState.new()
	var doc := GLTFDocument.new()
	if doc.append_from_file(ProjectSettings.globalize_path(SAMPLE), state) == OK:
		var bay := doc.generate_scene(state)
		add_child(bay)
		for surface in bay.find_children("*", "MeshInstance3D", true, false):
			surface.material_override = palette.mat("chalk")
			surface.gi_mode = GeometryInstance3D.GI_MODE_STATIC
			meshes += 1
	var floor_mesh := MeshInstance3D.new()
	floor_mesh.mesh = BoxMesh.new()
	floor_mesh.mesh.size = Vector3(14,0.2,16)
	floor_mesh.position = Vector3(3,-0.1,-4)
	floor_mesh.material_override = palette.mat("brick")
	add_child(floor_mesh)
	palette.free()
	add_child(cam)
	_set_view()

func _set_view() -> void:
	cam.fov = 55 if view == 0 else 72
	cam.position = Vector3(13,8.8,9) if view == 0 else Vector3(2.25,1.65,4.8)
	cam.look_at(Vector3(3,2.7,-4) if view == 0 else Vector3(3,3.8,-4.5))
	cam.current = true

func _unhandled_input(e: InputEvent) -> void:
	if e.is_action_pressed("ui_accept"):
		view = 1-view
		_set_view()

func mcp_observe() -> Dictionary:
	return {"view":view,"meshes":meshes,"sdfgi":environment.sdfgi_enabled,"ssao":environment.ssao_enabled,"gpu":RenderingServer.get_video_adapter_name(),"scale":get_viewport().scaling_3d_scale, "godot":Engine.get_version_info().string}
