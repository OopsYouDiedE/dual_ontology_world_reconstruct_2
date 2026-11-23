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
static var _hale_library: AnimationLibrary
static var _materials := {}

static func attach(parent: Node3D, variant := -1, expedition_hale := false) -> bool:
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
	if expedition_hale:_groom_hale(body)
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
		skeleton.set_bone_pose_rotation(i, skeleton.get_bone_pose_rotation(i) * Quaternion(axis, 0.44 if expedition_hale else 0.26))
	if expedition_hale:
		if _hale_library == null: _hale_library = _build_clips(body, skeleton, to_rig, true)
	elif _library == null: _library = _build_clips(body, skeleton, to_rig)
	var animation := AnimationPlayer.new()
	body.add_child(animation)
	animation.add_animation_library(&"", _hale_library if expedition_hale else _library)
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

static func _build_clips(body: Node3D, skeleton: Skeleton3D, to_rig: Basis, expedition_hale:=false) -> AnimationLibrary:
	var library := AnimationLibrary.new()
	var path := body.get_path_to(skeleton)
	var lengths := {&"idle": 2.4, &"walk": 0.9, &"run": 0.65, &"interact": 0.85, &"signal": 2.0, &"examine": 2.0, &"listen": 2.0}
	if expedition_hale:lengths[&"gate_effort"]=.82
	for clip: StringName in lengths:
		var anim := Animation.new()
		anim.length = lengths[clip]
		anim.loop_mode = Animation.LOOP_NONE if clip in [&"interact",&"gate_effort"] else Animation.LOOP_LINEAR
		for bone_name: String in BONES:
			var bone := skeleton.find_bone(bone_name)
			if bone < 0: continue
			var track := anim.add_track(Animation.TYPE_ROTATION_3D)
			anim.track_set_path(track, NodePath("%s:%s" % [path, bone_name]))
			var rest := skeleton.get_bone_pose_rotation(bone)
			var axis := (skeleton.get_bone_global_pose(bone).basis.inverse() * to_rig * Vector3.RIGHT).normalized()
			var roll := (skeleton.get_bone_global_pose(bone).basis.inverse() * to_rig * Vector3.BACK).normalized()
			for k in 9:
				var t := k / 8.0
				anim.rotation_track_insert_key(track, t * anim.length,
					rest * Quaternion(roll, _roll(clip,bone_name,t)) * Quaternion(axis, _angle(clip, bone_name, t)+_hale_rest_pitch(bone_name,clip) if expedition_hale else _angle(clip, bone_name, t)))
		library.add_animation(clip, anim)
	return library

static func _roll(clip:StringName,bone:String,t:float)->float:
	if clip not in [&"signal",&"examine",&"listen"]:return 0.
	var w=smoothstep(0.,.23,t)*(1.-smoothstep(.78,1.,t))
	return w*float({"head":.26 if clip==&"listen" else -.07,"upperarm_l":-.22,"upperarm_r":.22,"spine_01":.065}.get(bone,0.))

static func _angle(clip: StringName, bone: String, t: float) -> float:
	var hold := smoothstep(0.0, .23, t) * (1.0 - smoothstep(.78, 1.0, t))
	if clip == &"signal":
		return hold * float({"thigh_l":-.16,"calf_l":.22,"upperarm_r":-.85,"lowerarm_r":-.46,"head":-.10}.get(bone,0.0))
	if clip == &"examine":
		return hold * float({"spine_01":.18,"spine_03":.17,"head":.17,"thigh_r":-.42,"calf_r":.55,"foot_r":-.14,"upperarm_l":.16,"lowerarm_l":-.26,"upperarm_r":-.39,"lowerarm_r":-.20}.get(bone,0.0))
	if clip == &"listen":
		return hold * float({"thigh_l":-.13,"calf_l":.20,"upperarm_l":-.56,"lowerarm_l":-2.24,"head":.16,"spine_03":.08}.get(bone,0.0))
	if clip == &"gate_effort":
		var effort:=hold*(.91+.09*sin(TAU*3.*t))
		if bone.begins_with("upperarm"):return -.64*effort
		if bone.begins_with("lowerarm"):return -.91*effort
		if bone=="spine_03":return .065*effort
		return 0.
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

static func _hale_rest_pitch(bone:String,clip:StringName)->float:
	if clip==&"gate_effort":return 0.
	if bone.begins_with("upperarm"):return .18
	if bone.begins_with("lowerarm"):return .23
	return 0.

# Expedition-only grooming; preserve skin weights and the shared production rig.
static func _groom_hale(body:Node3D)->void:
	for node in body.find_children("Hair_*","MeshInstance3D",true,false):
		var hair:=node as MeshInstance3D
		if hair.name not in [&"Hair_Cap",&"Hair_SolidLocks"] or hair.mesh.get_surface_count()!=1:continue
		var cap:=hair.name==&"Hair_Cap"
		var arrays:=hair.mesh.surface_get_arrays(0)
		var vertices:PackedVector3Array=arrays[Mesh.ARRAY_VERTEX]
		for i in vertices.size():
			var v:=vertices[i]
			var back:=1.-smoothstep(-.040,.057,v.z)
			var temple:=smoothstep(.047,.076,absf(v.x))*smoothstep(.022,.068,v.z)*(1.-smoothstep(.098,.122,v.z))
			if cap:
				var edge:=1.-smoothstep(1.646,1.765,v.y)
				v.y-=edge*(.039*back+.024*temple)
				v.z-=edge*.003*back
			else:
				var fringe:=(1.-smoothstep(1.72,1.787,v.y))*(1.-smoothstep(.022,.085,v.z))
				v.y-=.023*fringe
			vertices[i]=v
		arrays[Mesh.ARRAY_VERTEX]=vertices
		var groom:=ArrayMesh.new();groom.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays)
		groom.surface_set_material(0,hair.mesh.surface_get_material(0));hair.mesh=groom
