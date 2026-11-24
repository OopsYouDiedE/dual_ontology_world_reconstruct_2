extends Node3D
## Isolated render review; uses Expedition light_stage and material factory unchanged.
const SAMPLE := "res://.runtime/french-gn/main/whole-church.glb"
var cam := Camera3D.new()
var view := 0
var parts := {}
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
			if surface.name == &"Timber_frames": surface.material_override = palette.mat("book")
			parts[str(surface.name)] = surface
	var floor_mesh := MeshInstance3D.new()
	floor_mesh.mesh = BoxMesh.new()
	floor_mesh.mesh.size = Vector3(46,0.2,52)
	floor_mesh.position = Vector3(0,-0.25,14)
	floor_mesh.material_override = palette.mat("brick")
	add_child(floor_mesh)
	palette.free()
	add_child(cam)
	_set_view()

const SHOTS := [
	[Vector3(38,25,-32),Vector3(0,14,14)],
	[Vector3(-30,22,57),Vector3(0,14,15)],
	[Vector3(28,20,-10),Vector3(0,5,15)],
	[Vector3(0,1.65,4.8),Vector3(0,3.3,21)],
	[Vector3(0,1.65,4.8),Vector3(0,3.3,21)],
	[Vector3(13,12,38),Vector3(0,3,23)],
]
func _set_view() -> void:
	parts["Exterior"].visible = view not in [2,4,5]
	cam.fov = 47 if view < 3 else 67
	cam.position = SHOTS[view][0]
	cam.look_at(SHOTS[view][1]); cam.current = true

func _unhandled_input(e: InputEvent) -> void:
	if e.is_action_pressed("ui_accept"):
		view = (view + 1) % SHOTS.size(); _set_view()

func mcp_observe() -> Dictionary:
	return {"view":view,"parts":parts.keys(),"shell":parts["Exterior"].visible,"sdfgi":environment.sdfgi_enabled,"ssao":environment.ssao_enabled,"gpu":RenderingServer.get_video_adapter_name(),"scale":get_viewport().scaling_3d_scale,"godot":Engine.get_version_info().string}
