extends Node3D
## Plays the imported actor's own action. This scene owns only lighting and playback UI.

const CLIP := &"MPFB_Pose_Check"
const TOON := preload("res://tools/mpfb2_test/academy_toon.gdshader")
const HULL := preload("res://tools/mpfb2_test/academy_hull.gdshader")

@onready var actor: Node3D = $R05
@onready var replay: Button = $Overlay/Panel/Margin/Rows/Replay
@onready var status: Label = $Overlay/Panel/Margin/Rows/Status

var player: AnimationPlayer
var rig: Skeleton3D
var finished := false


func _ready() -> void:
	var players := actor.find_children("*", "AnimationPlayer", true, false)
	var rigs := actor.find_children("*", "Skeleton3D", true, false)
	player = players[0] as AnimationPlayer if players.size() == 1 else null
	rig = rigs[0] as Skeleton3D if rigs.size() == 1 else null
	if player == null or rig == null or not player.has_animation(CLIP):
		push_error("R-05 is missing its embedded %s action or authoring rig" % CLIP)
		status.text = "Embedded action unavailable"
		replay.disabled = true
		return
	apply_review_materials()
	replay.pressed.connect(play_original)
	player.animation_finished.connect(_on_finished)
	play_original()


func play_original() -> void:
	finished = false
	player.stop(true)
	player.play(CLIP, 0.0)
	player.advance(0.0)
	status.text = "Playing embedded action"


func _on_finished(clip: StringName) -> void:
	if clip == CLIP:
		finished = true
		status.text = "Finished · replay to start again"


func apply_review_materials() -> void:
	for node in actor.find_children("*", "MeshInstance3D", true, false):
		var mesh := node as MeshInstance3D
		var skin := mesh.name == &"Academy_HeadBody"
		var hair := mesh.name.begins_with("Hair")
		if not skin and not hair and mesh.name not in [&"Shirt", &"Shorts"]:
			continue
		var source := mesh.mesh.surface_get_material(0) as StandardMaterial3D
		if source == null:
			continue
		var toon := ShaderMaterial.new()
		toon.shader = TOON
		toon.set_shader_parameter("pigment", source.albedo_color)
		toon.set_shader_parameter("band_width", 0.10 if skin else 0.08)
		if skin and source.albedo_texture != null:
			toon.set_shader_parameter("use_pigment_tex", true)
			toon.set_shader_parameter("pigment_tex", source.albedo_texture)
		var ink := ShaderMaterial.new()
		ink.shader = HULL
		ink.set_shader_parameter("use_vertex_alpha", skin)
		ink.set_shader_parameter("width_m", 0.00135 if skin else (0.00155 if hair else 0.00215))
		toon.next_pass = ink
		mesh.material_override = toon


func mcp_observe() -> Dictionary:
	if player == null or rig == null or not player.has_animation(CLIP):
		return {"ready": false}
	var clip := player.get_animation(CLIP)
	var center := replay.get_global_rect().get_center()
	return {
		"ready": true, "model": actor.scene_file_path, "clip": str(CLIP),
		"clips": Array(player.get_animation_list()), "length": clip.length,
		"playing": player.is_playing(), "finished": finished,
		"seconds": player.current_animation_position if player.is_playing() else clip.length,
		"bones": rig.get_bone_count(), "rig_path": str(player.get_node(player.root_node).get_path_to(rig)),
		"right_elbow": bone_sample(&"lowerarm_r"), "right_knee": bone_sample(&"calf_r"),
		"replay_center": [center.x, center.y],
	}


func bone_sample(bone: StringName) -> Array[float]:
	var index := rig.find_bone(bone)
	if index < 0:
		return []
	var pose := rig.get_bone_pose_rotation(index)
	return [pose.x, pose.y, pose.z, pose.w]
