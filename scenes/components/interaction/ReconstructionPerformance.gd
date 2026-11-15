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
	host.az = atan2(_inward.x,_inward.z)+1.05
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
	var generation := _generation
	running = true
	for actor in actors.values(): actor.visible = false
	_cloth.visible = false
	_door_pivot.rotation.y = 0
	for driver in drivers.values(): driver.reach_weight = 0.0
	_place_characters()
	for driver in drivers.values():
		driver.pelvis_offset_world = Vector3.ZERO
		driver.head_pitch = 0.0
		driver.head_roll = 0.0
		driver.torso_pitch = 0.0
		driver.foot_targets.clear()
	for id in ["su","detective"]: actors[id].rotation.y = atan2(-_inward.x,-_inward.z)
	for id in ["shen","huo"]: actors[id].rotation.y = atan2(-_inward.x,-_inward.z)
	await get_tree().process_frame
	if generation != _generation: return
	for driver in drivers.values(): driver.plant_feet()
	_stage("anchor")
	actors.su.visible = true
	actors.detective.visible = true
	var wrist := _slot("su")
	await _camera(wrist.global_position,2.1,0.60,1.0)
	if generation != _generation: return
	await get_tree().create_timer(0.65).timeout
	if generation != _generation: return
	_stage("what")
	await _camera(_threshold+Vector3.UP*0.75+_inward*0.65,4.0,0.60,0.8)
	if generation != _generation: return
	var su_driver: SkeletonModifier3D = drivers.su
	var det_driver: SkeletonModifier3D = drivers.detective
	if _target.get_parent() != _door_pivot: _target.reparent(_door_pivot,false)
	_target.position = Vector3(0.94,0.92,0.12)
	su_driver.right_target = _target
	var handle_reach := _tween()
	handle_reach.tween_property(su_driver,"reach_weight",1.0,0.4)
	await handle_reach.finished
	if generation != _generation: return
	var open := _tween()
	open.tween_property(_door_pivot,"rotation:y",-0.25,0.42)
	_sound.play_sound("wood")
	await open.finished
	if generation != _generation: return
	_wrist_target.global_position = _target.global_position
	su_driver.right_target = _wrist_target
	var release := _tween()
	release.tween_property(_wrist_target,"global_position",release_wrist_position(),0.35)
	await release.finished
	if generation != _generation: return
	det_driver.right_target = wrist
	var reach := _tween()
	reach.tween_property(det_driver,"reach_weight",1.0,0.5)
	await reach.finished
	if generation != _generation: return
	# Planted feet stay fixed as the hips and torso yield under the pull.
	var retreat := _tween().set_parallel(true)
	retreat.tween_property(su_driver,"pelvis_offset_world",_inward*0.12-Vector3.UP*0.05,0.9)
	retreat.tween_property(_wrist_target,"global_position",_wrist_target.global_position+_inward*0.10,0.9)
	retreat.tween_property(su_driver,"torso_pitch",0.24,0.9)
	_sound.play_sound("cloth")
	await retreat.finished
	if generation != _generation: return
	observed.emit({"stage":"what","shot":"pull_contact","measurement":test_snapshot()})
	await get_tree().create_timer(0.5).timeout
	if generation != _generation: return
	det_driver.reach_weight = 0.0
	actors.su.visible = false
	actors.detective.visible = false
	var close := _tween()
	close.tween_property(_door_pivot,"rotation:y",0.0,0.30)
	await close.finished
	if generation != _generation: return
	actors.shen.visible = true
	drivers.shen.right_target = _cloth_target
	var crouch := _tween().set_parallel(true)
	crouch.tween_property(drivers.shen,"pelvis_offset_world",-Vector3.UP*SHEN_CROUCH_DROP,0.65)
	crouch.tween_property(drivers.shen,"torso_pitch",SHEN_CROUCH_PITCH,0.65)
	crouch.tween_property(drivers.shen,"reach_weight",1.0,0.65)
	await _camera(_threshold+Vector3.UP*0.30,2.1,0.45,0.65)
	if generation != _generation: return
	_cloth.visible = true
	_sound.play_sound("cloth")
	observed.emit({"stage":"what","shot":"cloth_after_pull","measurement":test_snapshot()})
	await get_tree().create_timer(0.6).timeout
	if generation != _generation: return
	actors.shen.visible = false
	actors.huo.visible = true
	drivers.huo.right_target = _target
	var lock_reach := _tween()
	lock_reach.tween_property(drivers.huo,"reach_weight",1.0,0.45)
	await _camera(_target.global_position,1.9,0.30,0.65)
	if generation != _generation: return
	_ratchet.activate()
	observed.emit({"stage":"what","shot":"ratchet_last","measurement":test_snapshot()})
	await get_tree().create_timer(0.4).timeout
	if generation != _generation: return
	actors.huo.visible = false
	actors.su.visible = true
	actors.detective.visible = true
	_stage("why")
	drivers.su.head_pitch = -0.16
	drivers.su.head_roll = 0.10
	drivers.detective.head_pitch = 0.12
	drivers.detective.torso_pitch = 0.10
	det_driver.reach_weight = 1.0
	await _camera(wrist.global_position,1.7,0.32,0.8)
	if generation != _generation: return
	_sound.play_sound("cloth")
	await get_tree().create_timer(1.0).timeout
	if generation != _generation: return
	await _camera(actors.su.global_position+Vector3.UP*1.1,2.0,0.22,0.8)
	if generation != _generation: return
	await get_tree().create_timer(0.8).timeout
	if generation != _generation: return
	running = false
	observed.emit({"stage":"complete","contact_error_m":det_driver.contact_error_m,"acceptance":"pending_runtime_and_blind_review"})
	finished.emit()

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
