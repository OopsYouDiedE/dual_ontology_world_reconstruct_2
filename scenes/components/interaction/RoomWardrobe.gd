extends Node3D
## 给卧室里原有衣柜安装铰链，保留原柜门、嵌板和把手。
const Geometry := preload("res://scenes/components/interaction/InteractiveProp3D.gd")
var tool: Node3D
var hand: Node3D
var progress := 0.0
var completed := false
var _hinges: Array[Node3D] = []
var _sound: AudioStreamPlayer3D
signal sampled

func install(wardrobe: Node3D) -> bool:
	var body := wardrobe.find_child("Body", true, false) as MeshInstance3D
	if body == null: return false
	var door_left := wardrobe.find_child("Front_00", true, false) as Node3D
	var door_right := wardrobe.find_child("Front_01", true, false) as Node3D
	if door_left == null or door_right == null: return false
	wardrobe.add_child(self)
	name = "RoomWardrobeMechanism"
	# 原模型柜身是实心盒；同一家具内改成空腔，外形和占地保持原尺寸。
	body.visible = false
	var wood := Color("#604731")
	for x in [-0.675, 0.675]: Geometry.box(self, Vector3(0.07, 2.17, 0.58), Vector3(x, 1.21, 0), wood)
	Geometry.box(self, Vector3(1.35, 2.17, 0.055), Vector3(0, 1.21, -0.265), wood.darkened(0.2))
	for y in [0.17, 2.265]: Geometry.box(self, Vector3(1.35, 0.065, 0.58), Vector3(0, y, 0), wood)
	Geometry.rod(self, Vector3(-0.61, 1.98, 0), Vector3(0.61, 1.98, 0), 0.016, Color("#ba9f6a"))
	# 正式 R05 的叙事是整齐挂着的大衣。
	Geometry.rod(self, Vector3(0, 1.98, 0.0), Vector3(0, 1.83, 0.0), 0.014, Color("#ba9f6a"))
	Geometry.rod(self, Vector3(-0.27, 1.72, 0), Vector3(0, 1.83, 0), 0.018, wood.lightened(0.2))
	Geometry.rod(self, Vector3(0.27, 1.72, 0), Vector3(0, 1.83, 0), 0.018, wood.lightened(0.2))
	var coat := Color("#374449")
	Geometry.box(self, Vector3(0.49, 0.98, 0.12), Vector3(0, 1.21, 0.035), coat)
	for side in [-1.0, 1.0]:
		Geometry.rod(self, Vector3(side * 0.21, 1.68, 0.035), Vector3(side * 0.33, 1.04, 0.035), 0.082, coat)
		var lapel := Geometry.box(self, Vector3(0.075, 0.26, 0.025), Vector3(side * 0.07, 1.55, 0.11), coat.lightened(0.13))
		lapel.rotation.z = side * 0.3
	for index in 2:
		var hinge := Node3D.new()
		hinge.name = "DoorHinge_%d" % index
		add_child(hinge)
		hinge.position = Vector3(-0.69 if index == 0 else 0.69, 1.2455, 0.308)
		_hinges.append(hinge)
		var pieces := ["Front_00", "Inset_00", "Handle"] if index == 0 else ["Front_01", "Inset_01", "Handle_001"]
		for piece in pieces:
			var mesh := wardrobe.find_child(piece, true, false) as Node3D
			if mesh != null: mesh.reparent(hinge, true)
	_sound = AudioStreamPlayer3D.new()
	_sound.bus = &"Sfx" if AudioServer.get_bus_index("Sfx") >= 0 else &"Master"
	_sound.volume_db = -29.0
	_sound.max_db = -25.0
	add_child(_sound)
	set_meta("focus", Vector3(0, 1.22, 0.12))
	set_meta("camera_offset", Vector3(0.0, 0.18, 2.4))
	return true

func activate() -> void:
	if completed: return
	preload("res://scenes/components/interaction/InteractionSound.gd").play(_sound, "wood")
	var tween := create_tween().set_parallel(true).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tween.tween_property(_hinges[0], "rotation:y", deg_to_rad(-108), 0.24)
	tween.tween_property(_hinges[1], "rotation:y", deg_to_rad(108), 0.24)
	await tween.finished
	progress = 1.0
	completed = true
	sampled.emit()
