extends RefCounted
## Production cast: one measured rig, common animated poses and one Toon finish.
const MODEL := preload("res://assets/characters/toon_cast/detective-6p5.glb")
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
const BONES := ["Spine", "Chest", "Head", "UpperArm.L", "UpperArm.R", "Forearm.L",
	"Forearm.R", "Thigh.L", "Thigh.R", "Shin.L", "Shin.R", "Foot.L", "Foot.R"]
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
	if not recipe.is_empty(): body.scale = Vector3.ONE * (float(recipe[0]) / 1.77)
	_apply_finish(body, variant, recipe)
	if _library == null: _library = _build_clips(body, skeleton)
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
					if stock.resource_name.begins_with("Coat"):
						color = Color(recipe[1]).darkened(0.18 if stock.resource_name.contains("liner") else 0.0)
					elif stock.resource_name.begins_with("Waistcoat"):
						color = Color(recipe[2]).darkened(0.18 if stock.resource_name.contains("edge") else 0.0)
				mat.set_shader_parameter("base_color", color)
				mat.set_shader_parameter("surface_roughness", stock.roughness)
				mat.set_shader_parameter("double_sided", stock.cull_mode == BaseMaterial3D.CULL_DISABLED)
				if stock.albedo_texture: mat.set_shader_parameter("base_texture", stock.albedo_texture)
				finishes[stock] = mat
			mesh.set_surface_override_material(i, finishes[stock])

static func _build_clips(body: Node3D, skeleton: Skeleton3D) -> AnimationLibrary:
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
			var rest := skeleton.get_bone_rest(bone).basis.get_rotation_quaternion()
			var axis := (skeleton.get_bone_global_rest(bone).basis.inverse() * Vector3.RIGHT).normalized()
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
			"UpperArm.R": return -0.56 * reach
			"Forearm.R": return -0.68 * reach
			"Chest": return 0.10 * reach
		return 0.0
	if clip == &"idle":
		return 0.027 * sin(TAU * t) if bone == "Chest" else 0.0
	var stride := sin(TAU * t) * (-1.0 if bone.ends_with(".R") else 1.0)
	var vigor := 1.48 if clip == &"run" else 1.0
	if bone.begins_with("Thigh"): return -0.34 * stride * vigor
	if bone.begins_with("Shin"): return 0.46 * maxf(0.0, -stride) * vigor
	if bone.begins_with("Foot"): return -0.15 * maxf(0.0, -stride) * vigor
	if bone.begins_with("UpperArm"): return 0.22 * stride * vigor
	if bone.begins_with("Forearm"): return -0.10 - 0.18 * maxf(0.0, stride) * vigor
	return 0.0
