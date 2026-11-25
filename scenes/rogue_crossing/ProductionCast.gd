extends RefCounted
## Production cast: one MPFB2 R-05 rig, 25-sample 3-axis biomechanical poses
## (pitch + hip/chest counter-yaw + weight roll) and one Toon finish.
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

## Story heroes built by tools/cast (detective, hale, quer, lucian, demon): own GLB, baked clips.
const HERO_DIR := "res://assets/characters/heroes/%s.glb"
const HERO_ONE_SHOT := [&"interact", &"gate_effort", &"repair"]

static func attach_hero(parent: Node3D, id: String) -> bool:
	var scene := load(HERO_DIR % id) as PackedScene
	if scene == null: return false
	var body := scene.instantiate() as Node3D
	_apply_finish(body, -2, [], id)
	var animation := body.find_children("*", "AnimationPlayer", true, false)[0] as AnimationPlayer
	for clip in animation.get_animation_list():
		animation.get_animation(clip).loop_mode = Animation.LOOP_NONE if StringName(clip) in HERO_ONE_SHOT else Animation.LOOP_LINEAR
	parent.add_child(body)
	parent.set_meta("model_source", HERO_DIR % id)
	parent.set_meta("hero", id)
	parent.set_meta("skeleton", body.find_children("*", "Skeleton3D", true, false)[0])
	parent.set_meta("animation_player", animation)
	animation.play(&"idle")
	return true

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
	if expedition_hale: preload("res://scenes/rogue_crossing/HaleFieldDress.gd").fit(body)
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

static func _apply_finish(body: Node3D, variant: int, recipe: Array, key: Variant = null) -> void:
	if key == null: key = variant
	if not _materials.has(key): _materials[key] = {}
	var finishes: Dictionary = _materials[key]
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
	var lengths := {&"idle": 3.2, &"walk": 0.92, &"run": 0.62, &"interact": 0.85, &"signal": 2.0, &"examine": 2.0, &"listen": 2.0}
	var clip_bones:=BONES.duplicate()
	if expedition_hale:
		lengths[&"gate_effort"]=1.14
		lengths[&"ward"]=1.65;lengths[&"watch_plate"]=1.9;lengths[&"peek"]=2.2
		for side in ["l","r"]:
			for digit in ["index","middle","ring","pinky","thumb"]:
				for joint in range(1,4):clip_bones.append("%s_%02d_%s"%[digit,joint,side])
	for clip: StringName in lengths:
		var anim := Animation.new()
		anim.length = lengths[clip]
		anim.loop_mode = Animation.LOOP_NONE if clip in [&"interact",&"gate_effort"] else Animation.LOOP_LINEAR
		for bone_name: String in clip_bones:
			var bone := skeleton.find_bone(bone_name)
			if bone < 0: continue
			var track := anim.add_track(Animation.TYPE_ROTATION_3D)
			anim.track_set_path(track, NodePath("%s:%s" % [path, bone_name]))
			var rest := skeleton.get_bone_pose_rotation(bone)
			var b_inv := skeleton.get_bone_global_pose(bone).basis.inverse()
			var axis := (b_inv * to_rig * Vector3.RIGHT).normalized()
			var roll := (b_inv * to_rig * Vector3.BACK).normalized()
			var yaw_ax := (b_inv * to_rig * Vector3.UP).normalized()
			var samples:=33 if clip==&"gate_effort" else 25
			for k in samples:
				var t:=float(k)/(samples-1)
				var pitch:=_angle(clip,bone_name,t)
				var sway:=_roll(clip,bone_name,t)
				var twist:=_yaw(clip,bone_name,t)
				var curl:=0.
				if expedition_hale:
					pitch+=_hale_rest_pitch(bone_name,clip,t)
					sway+=_hale_stance_roll(bone_name,clip)
					curl=_hale_finger_curl(bone_name,clip,t)
				var q := rest * Quaternion(yaw_ax, twist) * Quaternion(roll, sway) * Quaternion(axis, pitch) * Quaternion(Vector3.RIGHT, curl)
				anim.rotation_track_insert_key(track,t*anim.length,q)
		library.add_animation(clip, anim)
	return library

static func _yaw(clip:StringName,bone:String,t:float)->float:
	# Biomechanical hip-vs-chest counter-rotation during locomotion and natural head scan on idle.
	if clip==&"idle":
		if bone=="head":return 0.065*sin(TAU*t)+0.025*sin(TAU*2.0*t+.6)
		if bone=="spine_03":return 0.022*sin(TAU*t+.4)
		return 0.
	if clip in [&"walk",&"run"]:
		var vigor:=1.45 if clip==&"run" else 1.0
		var phase:=sin(TAU*t)
		if bone=="spine_01":return 0.055*phase*vigor
		if bone=="spine_03":return -0.095*phase*vigor
		if bone=="head":return 0.042*phase*vigor
		return 0.
	if clip==&"watch_plate":
		if bone=="head":return 0.04*sin(TAU*t)
	if clip==&"peek":
		if bone=="head":return 0.07*sin(TAU*t)
	return 0.

static func _roll(clip:StringName,bone:String,t:float)->float:
	if clip==&"idle":
		if bone=="spine_01":return 0.016*sin(TAU*t)
		if bone=="head":return -0.020*sin(TAU*t+.35)
		if bone=="upperarm_l":return 0.018*sin(TAU*t)
		if bone=="upperarm_r":return -0.018*sin(TAU*t)
		return 0.
	if clip in [&"walk",&"run"]:
		var vigor:=1.35 if clip==&"run" else 1.0
		var phase:=cos(TAU*t)
		if bone=="spine_01":return 0.040*phase*vigor
		if bone=="spine_03":return -0.032*phase*vigor
		if bone=="head":return -0.014*phase*vigor
		return 0.
	if clip==&"ward":return float({"upperarm_r":.32,"spine_01":-.09,"head":.09}.get(bone,0.))
	if clip==&"peek":return float({"head":-.12,"spine_03":-.11}.get(bone,0.))
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
		var reach:=_gate_reach(t)
		var thrust:=reach*maxf(0.,cos(TAU*(t-.32)/.29))
		if bone.begins_with("upperarm"):return -.53*reach-.08*thrust
		if bone.begins_with("lowerarm"):return -.64*reach+.047*thrust
		if bone=="spine_01":return .035*thrust
		if bone=="spine_03":return .075*thrust
		return 0.
	if clip==&"watch_plate":
		var breath:=0.018*sin(TAU*t)
		return float({"head":.25+breath,"spine_03":.12+breath*.7}.get(bone,0.))
	if clip==&"ward":
		var breath:=0.02*sin(TAU*t)
		return float({"upperarm_r":-.91+breath,"lowerarm_r":-.75,"upperarm_l":-.20,"head":-.10,"spine_03":-.09+breath*.6}.get(bone,0.))
	if clip==&"peek":
		var breath:=0.018*sin(TAU*t)
		return float({"head":.09+breath,"spine_01":.07,"spine_03":.17+breath*.6,"upperarm_l":-.15}.get(bone,0.))
	if clip == &"interact":
		var reach := sin(PI * t)
		match bone:
			"upperarm_r": return -0.56 * reach
			"lowerarm_r": return -0.68 * reach
			"spine_03": return 0.12 * reach
			"head": return 0.08 * reach
		return 0.0
	if clip == &"idle":
		var breath := sin(TAU * t)
		match bone:
			"spine_03": return 0.032 * breath
			"head": return -0.018 * breath + 0.014 * sin(TAU * 2.0 * t)
			"upperarm_l", "upperarm_r": return 0.022 * breath
			"lowerarm_l", "lowerarm_r": return -0.035 - 0.015 * breath
		return 0.0
	var stride := sin(TAU * t) * (-1.0 if bone.ends_with("_r") else 1.0)
	var double_bob := cos(TAU * 2.0 * t)
	var is_run := clip == &"run"
	var vigor := 1.48 if is_run else 1.0
	if bone == "spine_01": return (0.11 if is_run else 0.03) + 0.022 * double_bob * vigor
	if bone == "spine_03": return (0.09 if is_run else 0.02) - 0.018 * double_bob * vigor
	if bone == "head": return (-0.09 if is_run else -0.02)
	if bone.begins_with("thigh"): return -0.36 * stride * vigor
	if bone.begins_with("calf"): return 0.50 * maxf(0.0, -stride) * vigor + (0.06 if is_run else 0.02)
	if bone.begins_with("foot"): return -0.18 * maxf(0.0, -stride) * vigor + 0.07 * maxf(0.0, stride)
	if bone.begins_with("upperarm"): return 0.26 * stride * vigor
	if bone.begins_with("lowerarm"): return (-0.28 if is_run else -0.14) - 0.22 * maxf(0.0, stride) * vigor
	return 0.0

static func _gate_reach(t:float)->float:
	return smoothstep(.02,.26,t)*(1.-smoothstep(.69,1.,t))

static func _hale_rest_pitch(bone:String,clip:StringName,t:float)->float:
	var neutral:=1.-_gate_reach(t) if clip==&"gate_effort" else 1.
	if bone.begins_with("upperarm"):return .18*neutral
	if bone.begins_with("lowerarm"):return .23*neutral
	if clip not in [&"idle",&"gate_effort",&"ward",&"watch_plate",&"peek"]:return 0.
	var step:=1. if bone.ends_with("_l") else -1.
	if bone.begins_with("thigh"):return .047*step
	if bone.begins_with("foot"):return -.047*step
	return 0.

static func _hale_stance_roll(bone:String,clip:StringName)->float:
	if clip not in [&"idle",&"gate_effort",&"ward",&"watch_plate",&"peek"]:return 0.
	var side:=1. if bone.ends_with("_l") else -1.
	if bone.begins_with("thigh"):return -.071*side
	if bone.begins_with("foot"):return .071*side
	return 0.

static func _hale_finger_curl(bone:String,clip:StringName,t:float)->float:
	if bone.get_slice("_",0) not in ["index","middle","ring","pinky","thumb"]:return 0.
	var joint:=int(bone.get_slice("_",1))-1
	var grip:=_gate_reach(t) if clip==&"gate_effort" else 0.
	if bone.ends_with("_l") and clip!=&"gate_effort":grip=.27 # relaxed carry hand
	if bone.begins_with("thumb"):return float([.12,.38,.38][joint])*grip
	return float([.10,.09,.06][joint])+float([.81,1.02,.68][joint])*grip
