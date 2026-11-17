extends Node
## Three-stage, in-room performance: physical anchor -> observed event -> motive/contact detail.
const Figure := preload("res://scenes/dual_world/ProceduralFigure.gd")
const Contact := preload("res://scenes/components/characters/ContactPoseModifier.gd")
const Prop := preload("res://scenes/components/interaction/InteractiveProp3D.gd")
const CHARACTER_STANCES := {"su":Vector2(0.35,0.43),"detective":Vector2(0.61,0.97),"shen":Vector2(-0.06,0.43),"huo":Vector2(0.30,0.43)}
const SHEN_CROUCH_DROP := 0.40
const SHEN_CROUCH_PITCH := 0.62
var host: Control
var root: Node3D
var actors: Dictionary = {}
var drivers: Dictionary = {}
var running := false
var stage := "off"
var _saved: Dictionary = {}
var _inward := Vector3.FORWARD
var _threshold := Vector3.ZERO
var _sound: Node3D
var _target: Node3D
var _door: Node3D
var _door_pivot: Node3D
var _cloth: MeshInstance3D
var _ratchet: Node3D
var _gas: Array[MeshInstance3D] = []
var _clock := 0.0
var _generation := 0
var _tweens: Array[Tween] = []
var _cloth_target: Node3D
var _wrist_target: Node3D
# One explicit timeline makes the active shot seekable at frame boundaries.
const PHASE_DURATIONS := [0.001,1.0,0.65,0.8,0.4,0.42,0.35,0.5,0.9,0.5,0.30,0.65,0.6,0.65,0.4,0.8,1.0,0.8,0.8]
var _phase := -1
var _phase_time := 0.0
var _phase_start: Dictionary = {}
signal observed(event: Dictionary)
signal finished

func begin(h: Control) -> void:
	host = h
	_saved = {"playing":host.eng.s.playing,"cine":host._cine,"az":host.az,"pitch":host.pitch,"dist":host.dist,"focus":host.kitchen.focus}
	_saved["visibility"] = []
	for item in [host.det,host.figures_root,host.det_ring,host.kitchen._hint,host.kitchen._prompt]:
		if is_instance_valid(item):
			_saved.visibility.append([item,item.visible])
			item.visible = false
	for item in host.kitchen._items: item.tag.visible = false
	host.eng.s.playing = false
	host._cine = true
	root = Node3D.new()
	root.name = "MeasuredReconstruction"
	host.det_root.get_parent().add_child(root)
	var marker: Node3D = host.room_mesh.evidence_nodes.get("e_b_water")
	_threshold = marker.global_position if marker != null else host.room_mesh.center()
	_threshold.y = 0
	_inward = (host.room_mesh.center()-_threshold)*Vector3(1,0,1)
	_inward = _inward.normalized() if _inward.length()>0.1 else Vector3.FORWARD
	# Shoot from the clear side of the aisle, inside the kitchen. The old
	# grazing angle placed the cloth rack between the lens and both hands.
	host.az = atan2(_inward.x, _inward.z) - 0.45
	var side := _inward.cross(Vector3.UP).normalized()
	for id in ["su","detective","shen","huo"]:
		var actor: Node3D = Figure.new()
		actor.name = "Memory_"+id
		root.add_child(actor)
		actor.setup(host.data.actor_by_id[id],host.data.rig_spec.get("poses",{}))
		actor.set_pose("stand")
		for mesh in actor.find_children("*","GeometryInstance3D",true,false):
			mesh.transparency = 0.2
			mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		actors[id] = actor
		var body: Node3D = actor.get("_body")
		var skeleton: Skeleton3D = body.get_meta("skeleton",null)
		var driver := Contact.new()
		driver.character_root = actor
		skeleton.add_child(driver)
		drivers[id] = driver
		actor.global_position = _threshold+_inward*(0.75+actors.size()*0.40)+side*(0.0 if id in ["su","detective"] else 0.75)
		actor.visible = false
	_target = Node3D.new()
	root.add_child(_target)
	_wrist_target = Node3D.new()
	root.add_child(_wrist_target)
	_sound = Prop.new()
	_sound.kind = "ratchet"
	_sound.visible = false
	root.add_child(_sound)
	_door = Node3D.new()
	root.add_child(_door)
	_door.global_position = _threshold
	_door.rotation.y = atan2(_inward.x,_inward.z)
	_door_pivot = Node3D.new()
	_door.add_child(_door_pivot)
	_door_pivot.position.x = -0.54
	Prop.box(_door_pivot,Vector3(1.08,1.95,0.065),Vector3(0.54,0.98,0),Color("#57584e"))
	Prop.box(_door_pivot,Vector3(0.06,0.11,0.10),Vector3(0.94,0.92,0.075),Color("#b59965"),0.7)
	_cloth = Prop.box(_door,Vector3(0.65,0.06,0.16),Vector3(0,0.045,0.06),Color("#9e967e"))
	_cloth.visible = false
	_cloth_target = Node3D.new()
	_door.add_child(_cloth_target)
	_cloth_target.position = Vector3(0.08,0.17,0.15)
	_ratchet = Prop.new()
	_ratchet.kind = "ratchet"
	_door.add_child(_ratchet)
	_ratchet.scale = Vector3.ONE*0.24
	_ratchet.position = Vector3(0.43,0.95,0.10)
	for index in 12:
		var mist := MeshInstance3D.new()
		var sphere := SphereMesh.new()
		sphere.radius = 0.11
		sphere.height = 0.18
		mist.mesh = sphere
		var material := Prop.material(Color(0.53,0.27,0.59,0.17))
		material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mist.material_override = material
		root.add_child(mist)
		mist.global_position = _threshold-_inward*(0.35+index*0.10)+side*sin(index*2.2)*0.35+Vector3.UP*(0.2+(index%3)*0.12)
		_gas.append(mist)
	play()

func play() -> void:
	if running: return
	_generation += 1
	running = true
	for actor in actors.values(): actor.visible = false
	_cloth.visible = false
	_door_pivot.rotation.y = 0
	_ratchet.completed = false
	_ratchet.pivot.rotation.z = 0.0
	_place_characters()
	for id in drivers:
		var driver = drivers[id]
		driver.reach_weight = 0.0
		driver.right_target = null
		driver.pelvis_offset_world = Vector3.ZERO
		driver.head_pitch = 0.0
		driver.head_roll = 0.0
		driver.torso_pitch = 0.0
		driver.foot_targets.clear()
		actors[id].rotation.y = atan2(-_inward.x,-_inward.z)
	_phase = 0
	_phase_time = 0.0
	_phase_start = _scene_state()

func _enter_phase(next: int) -> void:
	_phase = next
	_phase_time = 0.0
	var wrist := _slot("su")
	match next:
		1:
			for driver in drivers.values(): driver.plant_feet()
			_stage("anchor")
			actors.su.visible = true
			actors.detective.visible = true
		3: _stage("what")
		4:
			if _target.get_parent() != _door_pivot: _target.reparent(_door_pivot,false)
			_target.position = Vector3(0.94,0.92,0.12)
			drivers.su.right_target = _target
		5: _sound.play_sound("wood")
		6:
			_wrist_target.global_position = _target.global_position
			drivers.su.right_target = _wrist_target
		7: drivers.detective.right_target = wrist
		8: _sound.play_sound("cloth")
		9: observed.emit({"stage":"what","shot":"pull_contact","measurement":test_snapshot()})
		10:
			drivers.detective.reach_weight = 0.0
			actors.su.visible = false
			actors.detective.visible = false
		11:
			actors.shen.visible = true
			drivers.shen.right_target = _cloth_target
		12:
			_cloth.visible = true
			_sound.play_sound("cloth")
			observed.emit({"stage":"what","shot":"cloth_after_pull","measurement":test_snapshot()})
		13:
			actors.shen.visible = false
			actors.huo.visible = true
			drivers.huo.right_target = _target
		14:
			_ratchet.play_sound("metal")
			observed.emit({"stage":"what","shot":"ratchet_last","measurement":test_snapshot()})
		15:
			_ratchet.completed = true
			actors.huo.visible = false
			actors.su.visible = true
			actors.detective.visible = true
			_stage("why")
			drivers.su.head_pitch = -0.16
			drivers.su.head_roll = 0.10
			drivers.detective.head_pitch = 0.12
			drivers.detective.torso_pitch = 0.10
			drivers.detective.reach_weight = 1.0
		16: _sound.play_sound("cloth")
	_phase_start = _scene_state()

func _blend_camera(point: Vector3, distance: float, camera_pitch: float, t: float, yaw_offset := -0.45) -> void:
	var camera: Dictionary = _phase_start.camera
	host.kitchen.focus = _vec(camera.focus).lerp(point,t)
	host.az = lerp_angle(float(camera.az), atan2(_inward.x, _inward.z) + yaw_offset, t)
	host.dist = lerpf(float(camera.dist),distance,t)
	host.pitch = lerpf(float(camera.pitch),camera_pitch,t)

func _apply_phase(value: float) -> void:
	var t := (1.0-cos(clampf(value,0.0,1.0)*PI))*0.5
	var d: Dictionary = _phase_start.drivers
	match _phase:
		1: _blend_camera(_slot("su").global_position,2.1,0.60,t)
		3: _blend_camera(_threshold+Vector3.UP*0.75+_inward*0.65,4.0,0.60,t)
		4: drivers.su.reach_weight = lerpf(float(d.su.reach),1.0,t)
		5: _door_pivot.rotation.y = lerpf(float(_phase_start.door_y),-0.25,t)
		6: _wrist_target.global_position = _vec(_phase_start.wrist_position).lerp(release_wrist_position(),t)
		7: drivers.detective.reach_weight = lerpf(float(d.detective.reach),1.0,t)
		8:
			drivers.su.pelvis_offset_world = _vec(d.su.pelvis).lerp(_inward*0.12-Vector3.UP*0.05,t)
			_wrist_target.global_position = _vec(_phase_start.wrist_position).lerp(_vec(_phase_start.wrist_position)+_inward*0.10,t)
			drivers.su.torso_pitch = lerpf(float(d.su.torso_pitch),0.24,t)
		10: _door_pivot.rotation.y = lerpf(float(_phase_start.door_y),0.0,t)
		11:
			drivers.shen.pelvis_offset_world = _vec(d.shen.pelvis).lerp(-Vector3.UP*SHEN_CROUCH_DROP,t)
			drivers.shen.torso_pitch = lerpf(float(d.shen.torso_pitch),SHEN_CROUCH_PITCH,t)
			drivers.shen.reach_weight = lerpf(float(d.shen.reach),1.0,t)
			_blend_camera(_cloth_target.global_position + Vector3.UP * 0.45,2.3,0.60,t,0.18)
		13:
			drivers.huo.reach_weight = lerpf(float(d.huo.reach),1.0,minf(_phase_time/0.45,1.0))
			_blend_camera(_ratchet.global_position.lerp(actors.huo.global_position + Vector3.UP * 0.95, 0.22),2.3,0.48,t,0.42)
		14:
			var angles := [0.0,0.07,-0.035,0.05,0.0]
			var key := minf(_phase_time/0.055,4.0)
			var index := mini(int(key),3)
			_ratchet.pivot.rotation.z = lerpf(angles[index],angles[index+1],key-index)
		15: _blend_camera(_slot("su").global_position,1.7,0.32,t)
		17: _blend_camera(actors.su.global_position+Vector3.UP*1.1,2.0,0.22,t)

func _advance_timeline(delta: float) -> void:
	var remaining := delta
	while running:
		var duration: float = PHASE_DURATIONS[_phase]
		var step := minf(remaining,maxf(0.0,duration-_phase_time))
		_phase_time += step
		remaining -= step
		_apply_phase(_phase_time/duration)
		if _phase_time + 0.000001 < duration: break
		if _phase + 1 >= PHASE_DURATIONS.size():
			running = false
			observed.emit({"stage":"complete","contact_error_m":drivers.detective.contact_error_m,"acceptance":"pending_runtime_and_blind_review"})
			finished.emit()
			break
		_enter_phase(_phase+1)
		if remaining <= 0.0: break

static func _xyz(v: Vector3) -> Array:
	return [v.x,v.y,v.z]

static func _vec(value: Array) -> Vector3:
	return Vector3(float(value[0]),float(value[1]),float(value[2]))

func _target_name(value: Node3D) -> String:
	if value == _target: return "door"
	if value == _wrist_target: return "wrist"
	if value == _cloth_target: return "cloth"
	if value == _slot("su"): return "su_hand"
	return ""

func _named_target(value: String) -> Node3D:
	match value:
		"door": return _target
		"wrist": return _wrist_target
		"cloth": return _cloth_target
		"su_hand": return _slot("su")
	return null

func _scene_state() -> Dictionary:
	var bodies := {}
	var poses := {}
	for id in actors:
		var actor: Node3D = actors[id]
		var driver = drivers[id]
		var feet := {}
		for side in driver.foot_targets: feet[side] = _xyz(driver.foot_targets[side])
		bodies[id] = {"position":_xyz(actor.global_position),"rotation":_xyz(actor.rotation),"visible":actor.visible}
		poses[id] = {"reach":driver.reach_weight,"head_pitch":driver.head_pitch,"head_roll":driver.head_roll,
			"torso_pitch":driver.torso_pitch,"pelvis":_xyz(driver.pelvis_offset_world),"foot_targets":feet,
			"right_target":_target_name(driver.right_target),"left_target":_target_name(driver.left_target)}
	var mist := []
	for item in _gas: mist.append(_xyz(item.position))
	return {"camera":{"focus":_xyz(host.kitchen.focus),"az":host.az,"dist":host.dist,"pitch":host.pitch},
		"actors":bodies,"drivers":poses,"door_y":_door_pivot.rotation.y,"cloth_visible":_cloth.visible,
		"target_parent":"door" if _target.get_parent() == _door_pivot else "root",
		"target_position":_xyz(_target.position),"wrist_position":_xyz(_wrist_target.global_position),
		"ratchet_z":_ratchet.pivot.rotation.z,"ratchet_completed":_ratchet.completed,"gas":mist}

func _stage_elapsed() -> float:
	var first := 15 if _phase >= 15 else (3 if _phase >= 3 else 1)
	var elapsed := _phase_time
	for index in range(first,_phase): elapsed += PHASE_DURATIONS[index]
	return elapsed

func checkpoint_state() -> Dictionary:
	if not is_instance_valid(root): return {}
	var saved_visibility := []
	for item in _saved.get("visibility",[]): saved_visibility.append(bool(item[1]))
	return {"version":1,"running":running,"stage":stage,"stage_elapsed":_stage_elapsed(),"phase":_phase,"phase_time":_phase_time,
		"clock":_clock,"phase_start":_phase_start.duplicate(true),"scene":_scene_state(),
		"previous":{"playing":_saved.get("playing",false),"cine":_saved.get("cine",false),
			"az":_saved.get("az",0.12),"pitch":_saved.get("pitch",0.95),"dist":_saved.get("dist",7.4),
			"focus":_xyz(_saved.get("focus",Vector3.ZERO)),"visibility":saved_visibility}}

func restore_checkpoint(state: Dictionary) -> void:
	if not is_instance_valid(root) or int(state.get("version",0)) != 1: return
	var phase := int(state.get("phase",-1))
	var scene = state.get("scene",{})
	var start = state.get("phase_start",{})
	if phase < 0 or phase >= PHASE_DURATIONS.size() or not scene is Dictionary or not start is Dictionary or scene.is_empty() or start.is_empty(): return
	_generation += 1
	for tween in _tweens:
		if tween.is_valid(): tween.kill()
	_tweens.clear()
	var previous: Dictionary = state.get("previous",{})
	_saved.playing = bool(previous.get("playing",false))
	_saved.cine = bool(previous.get("cine",false))
	_saved.az = float(previous.get("az",0.12))
	_saved.pitch = float(previous.get("pitch",0.95))
	_saved.dist = float(previous.get("dist",7.4))
	_saved.focus = _vec(previous.get("focus",[0,0,0]))
	var saved_visibility: Array = previous.get("visibility",[])
	for i in mini(saved_visibility.size(),_saved.visibility.size()): _saved.visibility[i][1] = bool(saved_visibility[i])
	var parent: Node = _door_pivot if scene.get("target_parent","") == "door" else root
	if _target.get_parent() != parent: _target.reparent(parent,false)
	_target.position = _vec(scene.target_position)
	_wrist_target.global_position = _vec(scene.wrist_position)
	_door_pivot.rotation.y = float(scene.door_y)
	_cloth.visible = bool(scene.cloth_visible)
	_ratchet.pivot.rotation.z = float(scene.ratchet_z)
	_ratchet.completed = bool(scene.ratchet_completed)
	for id in actors:
		var body: Dictionary = scene.actors[id]
		var pose: Dictionary = scene.drivers[id]
		actors[id].global_position = _vec(body.position)
		actors[id].rotation = _vec(body.rotation)
		actors[id].visible = bool(body.visible)
		var driver = drivers[id]
		driver.reach_weight = float(pose.reach)
		driver.head_pitch = float(pose.head_pitch)
		driver.head_roll = float(pose.head_roll)
		driver.torso_pitch = float(pose.torso_pitch)
		driver.pelvis_offset_world = _vec(pose.pelvis)
		driver.right_target = _named_target(str(pose.right_target))
		driver.left_target = _named_target(str(pose.left_target))
		driver.foot_targets.clear()
		for side in pose.foot_targets: driver.foot_targets[side] = _vec(pose.foot_targets[side])
	for i in mini(_gas.size(),scene.gas.size()): _gas[i].position = _vec(scene.gas[i])
	host.kitchen.focus = _vec(scene.camera.focus)
	host.az = float(scene.camera.az)
	host.pitch = float(scene.camera.pitch)
	host.dist = float(scene.camera.dist)
	_phase = phase
	_phase_time = clampf(float(state.get("phase_time",0.0)),0.0,float(PHASE_DURATIONS[phase]))
	_clock = float(state.get("clock",0.0))
	_phase_start = start.duplicate(true)
	stage = str(state.get("stage","off"))
	running = bool(state.get("running",false))
	host._update_camera()

func _stage(value: String) -> void:
	stage = value
	observed.emit({"stage":stage,"system_time":Time.get_datetime_string_from_system(false,true)})

func _place_characters() -> void:
	var side := Vector3.UP.cross(_inward).normalized()
	for id in CHARACTER_STANCES:
		var stance: Vector2 = CHARACTER_STANCES[id]
		actors[id].global_position = _threshold+side*stance.x+_inward*stance.y

func release_wrist_position() -> Vector3:
	var side := Vector3.UP.cross(_inward).normalized()
	return actors.su.global_position+side*0.23+_inward*0.24+Vector3.UP*0.82

func _slot(id: String) -> Node3D:
	var body: Node3D = actors[id].get("_body")
	return body.get_meta("slot_right_hand",null)

func _camera(point: Vector3,distance: float,pitch: float,duration: float) -> void:
	var tween := _tween().set_parallel(true)
	tween.tween_property(host.kitchen,"focus",point,duration)
	tween.tween_property(host,"dist",distance,duration)
	tween.tween_property(host,"pitch",pitch,duration)
	await tween.finished

func _tween() -> Tween:
	var tween := create_tween().set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	_tweens.append(tween)
	return tween

func _process(delta: float) -> void:
	if host == null or not is_instance_valid(root): return
	_clock += delta
	if running: _advance_timeline(delta)
	host._update_camera()
	for index in _gas.size():
		_gas[index].position.y += sin(_clock*1.7+index)*delta*0.02

func stop() -> void:
	_generation += 1
	running = false
	for tween in _tweens:
		if tween.is_valid(): tween.kill()
	if is_instance_valid(root): root.queue_free()
	if host != null:
		host.eng.s.playing = _saved.get("playing",false)
		host._cine = _saved.get("cine",false)
		host.az = _saved.get("az",0.12)
		host.pitch = _saved.get("pitch",0.95)
		host.dist = _saved.get("dist",7.4)
		if host.kitchen != null: host.kitchen.focus = _saved.get("focus",Vector3.ZERO)
		for item in _saved.get("visibility",[]):
			if is_instance_valid(item[0]): item[0].visible = item[1]
	queue_free()

func test_snapshot() -> Dictionary:
	var contact: Dictionary = {}
	var feet: Dictionary = {}
	var arms: Dictionary = {}
	for id in drivers: contact[id] = drivers[id].contact_error_m
	for id in drivers: feet[id] = drivers[id].foot_error_m
	for id in drivers: arms[id] = drivers[id].arm_measurements.duplicate(true)
	return {"stage":stage,"running":running,"contact_error_m":contact,"foot_anchor_error_m":feet,"arm_measurements":arms,"root_motion":"stationary roots; measured foot targets and pelvis response"}
