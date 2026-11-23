extends RefCounted
## Production cast: one MPFB2 R-05 rig, common animated poses and one Toon finish.
const MODEL := preload("res://assets/characters/mpfb/r05_formal.glb")
const FINISH := preload("res://scenes/components/rendering/actors/CastDielectric.gdshader")
const BODIES := [
	[1.66, "36586a", "775a36"], [1.73, "69483c", "81643b"],
	[1.81, "45475e", "526451"], [1.61, "516458", "774e3c"],
	[1.84, "4b555b", "6c555e"], [1.70, "6c5440", "4c6564"],
	[1.64, "6b514f", "697b56"], [1.76, "41586a", "80664d"],
	[1.79, "5d5668", "52635a"], [1.68, "45716c", "8b6c45"],
	[1.63, "6a4654", "586783"], [1.74, "606251", "8c6142"],
	[1.72, "3d535d", "8b714a"], [1.82, "62523f", "527476"],
	[1.67, "63516e", "786647"], [1.71, "4f6271", "75594d"],
]
const BONES := ["spine_01", "spine_03", "head", "upperarm_l", "upperarm_r", "lowerarm_l",
	"lowerarm_r", "thigh_l", "thigh_r", "calf_l", "calf_r", "foot_l", "foot_r"]
static var _library: AnimationLibrary
static var _materials := {}

static func attach(parent: Node3D, variant := -1) -> bool:
	if variant < -1 or variant >= BODIES.size(): return false
	var body := MODEL.instantiate() as Node3D
	if body == null: return false
	var skeletons := body.find_children("*", "Skeleton3D", true, false)
	if skeletons.is_empty():
		body.free()
		return false
	var skeleton := skeletons[0] as Skeleton3D
	var recipe: Array = BODIES[variant] if variant >= 0 else []
	if not recipe.is_empty(): body.scale = Vector3.ONE * (float(recipe[0]) / 1.802522)
	_apply_finish(body, variant, recipe)
	# Preserve the approved R-05 neutral pose, including fingers and shoulders.
	var native := body.find_children("*", "AnimationPlayer", true, false)[0] as AnimationPlayer
	native.play(&"MPFB_Pose_Check")
	native.seek(0.0, true)
	native.pause()
	var to_rig := _relative_to_body(body, skeleton).basis.inverse()
	for shoulder in ["upperarm_l", "upperarm_r"]:
		var i := skeleton.find_bone(shoulder)
		var joint := skeleton.get_bone_global_pose(i)
		var side := signf((to_rig.inverse() * joint.origin).x)
		var axis := (joint.basis.inverse() * to_rig * Vector3.BACK).normalized() * -side
		skeleton.set_bone_pose_rotation(i, skeleton.get_bone_pose_rotation(i) * Quaternion(axis, 0.26))
	if _library == null: _library = _build_clips(body, skeleton, to_rig)
	var animation := AnimationPlayer.new()
	body.add_child(animation)
	animation.add_animation_library(&"", _library)
	parent.add_child(body)
	parent.set_meta("model_source", MODEL.resource_path)
	parent.set_meta("cast_variant", variant)
	parent.set_meta("skeleton", skeleton)
	parent.set_meta("animation_player", animation)
	animation.play(&"idle")
	return true

static func _apply_finish(body: Node3D, variant: int, recipe: Array) -> void:
	if not _materials.has(variant): _materials[variant] = {}
	var finishes: Dictionary = _materials[variant]
	for mesh: MeshInstance3D in body.find_children("*", "MeshInstance3D", true, false):
		if mesh.mesh == null: continue
		for i in mesh.mesh.get_surface_count():
			var stock := mesh.get_active_material(i) as StandardMaterial3D
			if stock == null: continue
			if not finishes.has(stock):
				var mat := ShaderMaterial.new()
				mat.shader = FINISH
				mat.set_shader_parameter("toon_on", true)
				mat.set_shader_parameter("toon_strength", 0.86)
				var color := stock.albedo_color
				if not recipe.is_empty():
					if stock.resource_name == "Human.male_elegantsuit01": color *= Color(recipe[1]).lightened(0.35)
					elif stock.resource_name == "Human.shoes04": color *= Color(recipe[2]).lightened(0.35)
				mat.set_shader_parameter("base_color", color)
				mat.set_shader_parameter("surface_roughness", stock.roughness)
				mat.set_shader_parameter("double_sided", stock.cull_mode == BaseMaterial3D.CULL_DISABLED)
				if stock.albedo_texture: mat.set_shader_parameter("base_texture", stock.albedo_texture)
				finishes[stock] = mat
			mesh.set_surface_override_material(i, finishes[stock])

static func _relative_to_body(body: Node3D, node: Node3D) -> Transform3D:
	var result := Transform3D.IDENTITY
	while node != body:
		result = node.transform * result
		node = node.get_parent_node_3d()
	return result

static func _build_clips(body: Node3D, skeleton: Skeleton3D, to_rig: Basis) -> AnimationLibrary:
	var library := AnimationLibrary.new()
	var path := body.get_path_to(skeleton)
	var lengths := {&"idle": 2.4, &"walk": 0.9, &"run": 0.65, &"interact": 0.85}
	for clip: StringName in lengths:
		var anim := Animation.new()
		anim.length = lengths[clip]
		anim.loop_mode = Animation.LOOP_NONE if clip == &"interact" else Animation.LOOP_LINEAR
		for bone_name: String in BONES:
			var bone := skeleton.find_bone(bone_name)
			if bone < 0: continue
			var track := anim.add_track(Animation.TYPE_ROTATION_3D)
			anim.track_set_path(track, NodePath("%s:%s" % [path, bone_name]))
			var rest := skeleton.get_bone_pose_rotation(bone)
			var axis := (skeleton.get_bone_global_pose(bone).basis.inverse() * to_rig * Vector3.RIGHT).normalized()
			for k in 9:
				var t := k / 8.0
				anim.rotation_track_insert_key(track, t * anim.length,
					rest * Quaternion(axis, _angle(clip, bone_name, t)))
		library.add_animation(clip, anim)
	return library

static func _angle(clip: StringName, bone: String, t: float) -> float:
	if clip == &"interact":
		var reach := sin(PI * t)
		match bone:
			"upperarm_r": return -0.56 * reach
			"lowerarm_r": return -0.68 * reach
			"spine_03": return 0.10 * reach
		return 0.0
	if clip == &"idle":
		return 0.027 * sin(TAU * t) if bone == "spine_03" else 0.0
	var stride := sin(TAU * t) * (-1.0 if bone.ends_with("_r") else 1.0)
	var vigor := 1.48 if clip == &"run" else 1.0
	if bone.begins_with("thigh"): return -0.34 * stride * vigor
	if bone.begins_with("calf"): return 0.46 * maxf(0.0, -stride) * vigor
	if bone.begins_with("foot"): return -0.15 * maxf(0.0, -stride) * vigor
	if bone.begins_with("upperarm"): return 0.22 * stride * vigor
	if bone.begins_with("lowerarm"): return -0.10 - 0.18 * maxf(0.0, stride) * vigor
	return 0.0
