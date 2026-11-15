extends Node3D
## 卧室观察直接装在原家具上；微距仍由正式房间相机完成。
const Geometry := preload("res://scenes/components/interaction/InteractiveProp3D.gd")
const Sound := preload("res://scenes/components/interaction/InteractionSound.gd")
var kind := ""
var tool: Node3D
var hand: Node3D
var progress := 0.0
var completed := false
var _original: Node3D
var _moving: Array[Node3D] = []
var _sound: AudioStreamPlayer3D
var _running := false
signal sampled

func install(original: Node3D, observation: String) -> bool:
	_original = original
	kind = observation
	original.add_child(self)
	name = "RoomObservation_" + kind
	match kind:
		"bed":
			for piece in ["Blanket", "Fold", "FootDrape", "Pillow"]:
				var mesh := original.find_child(piece, true, false) as Node3D
				if mesh != null: _moving.append(mesh)
			set_meta("focus", Vector3(0, 0.67, 0.2))
			set_meta("camera_offset", Vector3(1.75, 1.3, 1.15))
		"desk": _install_notebook()
		"lamp":
			var shade := original.find_child("Green_shade", true, false) as Node3D
			if shade != null:
				var hinge := Node3D.new()
				add_child(hinge)
				hinge.position = Vector3(0, 0.45, 0.025)
				shade.reparent(hinge, true)
				var rim := original.find_child("Shade_front_rim", true, false) as Node3D
				if rim != null: rim.reparent(hinge, true)
				_moving.append(hinge)
			set_meta("focus", Vector3(0, 0.34, 0.025))
			set_meta("camera_offset", Vector3(0.3, 0.35, 0.95))
		"wash": _install_water()
		"window":
			var glass := original.find_child("Glass", true, false) as MeshInstance3D
			var center := to_local(glass.to_global(glass.get_aabb().get_center())) if glass != null else Vector3(0, 0.8, 0)
			set_meta("focus", center)
			set_meta("camera_offset", Vector3(0.3, 0.25, 4.2))
			set_meta("camera_fov", 58.0)
		_: return false
	_sound = AudioStreamPlayer3D.new()
	_sound.bus = &"Sfx" if AudioServer.get_bus_index("Sfx") >= 0 else &"Master"
	_sound.volume_db = -31.0
	_sound.max_db = -27.0
	add_child(_sound)
	return true

func _install_notebook() -> void:
	# 原桌上 Paper 保留在原位置，增加封面、折页和中断的笔迹。
	var paper := _original.find_child("Paper", true, false) as MeshInstance3D
	if paper == null: return
	global_transform = paper.global_transform
	var page_size := paper.get_aabb().size
	var width := maxf(page_size.x, 0.22)
	var depth := maxf(page_size.z, 0.26)
	var hinge := Node3D.new()
	hinge.name = "NotebookCoverHinge"
	add_child(hinge)
	hinge.position = Vector3(-width * 0.5, 0.012, 0)
	Geometry.box(hinge, Vector3(width, 0.015, depth), Vector3(width * 0.5, 0, 0), Color("#34423e"))
	_moving.append(hinge)
	for row in 2:
		var count := 8 if row == 0 else 3
		for column in count:
			var at := Vector3(-width * 0.32 + column * width * 0.065, 0.011, -depth * 0.18 + row * depth * 0.15)
			var stroke := Geometry.box(self, Vector3(width * 0.043, 0.001, depth * 0.012), at, Color("#3c342b"))
			stroke.rotation.y = sin(column * 2.1) * 0.24
	set_meta("focus", Vector3(0, 0.025, 0))
	set_meta("camera_offset", Vector3(0.12, 0.72, 0.45))

func _install_water() -> void:
	var bowl := _original.find_child("Bowl", true, false) as MeshInstance3D
	if bowl == null: return
	var bounds := bowl.get_aabb()
	var top := bowl.to_global(bounds.get_center() + Vector3(0, bounds.size.y * 0.35, 0))
	var center := to_local(top)
	for index in 3:
		var ripple := MeshInstance3D.new()
		ripple.name = "BasinRipple_%d" % index
		var ring := TorusMesh.new()
		ring.inner_radius = 0.07 + index * 0.035
		ring.outer_radius = ring.inner_radius + 0.004
		ring.rings = 24
		ring.ring_segments = 6
		ripple.mesh = ring
		ripple.material_override = Geometry.material(Color("#a1c4c5"))
		ripple.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(ripple)
		ripple.position = center + Vector3(0, index * 0.001, 0)
		ripple.scale = Vector3(0.05, 0.12, 0.05)
		ripple.visible = false
		_moving.append(ripple)
	set_meta("focus", center)
	set_meta("camera_offset", Vector3(0.3, 0.66, 0.95))

func activate() -> void:
	if _running: return
	if completed:
		sampled.emit()
		return
	_running = true
	var tween := create_tween().set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	match kind:
		"bed":
			Sound.play(_sound, "cloth")
			for mesh in _moving:
				if mesh.name == "Pillow":
					tween.parallel().tween_property(mesh, "rotation:y", 0.16, 0.55)
				elif mesh.name == "Blanket":
					tween.parallel().tween_property(mesh, "scale:z", mesh.scale.z * 0.52, 0.55)
					tween.parallel().tween_property(mesh, "position:z", mesh.position.z + 0.35, 0.55)
				elif mesh.name == "Fold":
					tween.parallel().tween_property(mesh, "position:z", mesh.position.z + 0.7, 0.55)
		"desk":
			Sound.play(_sound, "paper")
			if not _moving.is_empty(): tween.tween_property(_moving[0], "rotation:z", deg_to_rad(155.0), 0.65)
		"lamp":
			Sound.play(_sound, "metal")
			if not _moving.is_empty():
				var shade := _moving[0]
				var initial := shade.rotation.x
				tween.tween_property(shade, "rotation:x", initial + 0.1, 0.22)
				tween.tween_property(shade, "rotation:x", initial, 0.3)
		"wash":
			Sound.play(_sound, "water")
			for ripple in _moving:
				ripple.visible = true
				tween.parallel().tween_property(ripple, "scale", Vector3(1, 0.12, 1), 0.85)
		"window": tween.tween_interval(0.65)
	tween.tween_interval(0.1)
	await tween.finished
	if not is_inside_tree(): return
	_running = false
	progress = 1.0
	completed = true
	sampled.emit()
