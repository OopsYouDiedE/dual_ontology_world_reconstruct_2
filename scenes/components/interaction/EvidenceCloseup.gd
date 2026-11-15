extends Control
## A real 3D macro viewport. Mouse strokes sample the surface; dragging aligns the hand and cuff.
const Prop := preload("res://scenes/components/interaction/InteractiveProp3D.gd")
var kind := "wardrobe"
var prop: Node3D
var camera: Camera3D
var viewport: SubViewport
var stage: Node3D
var _dragging := false
var _last := Vector2.ZERO
var _camera_tween: Tween
var _close_button: Button
var _has_result := false
var _closing := false
var wrist_anchor: Node3D
var anchor_camera: Camera3D
var anchor_container: Control
var _container: SubViewportContainer
var _display := Rect2()
var _anchor_point := Vector2.ZERO
signal finished(success: bool)
signal observed(event: Dictionary)

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	var container := SubViewportContainer.new()
	_container = container
	container.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	container.stretch = true
	container.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(container)
	viewport = SubViewport.new()
	viewport.size = Vector2i(1000, 650)
	viewport.own_world_3d = true
	viewport.audio_listener_enable_3d = true
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	container.add_child(viewport)
	stage = Node3D.new()
	viewport.add_child(stage)
	var environment := WorldEnvironment.new()
	environment.environment = Environment.new()
	environment.environment.background_mode = Environment.BG_COLOR
	environment.environment.background_color = Color("#182125")
	environment.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.environment.ambient_light_color = Color("#a3adb4")
	environment.environment.ambient_light_energy = 0.55
	stage.add_child(environment)
	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-48, -36, 0)
	light.light_color = Color("#ffe5ba")
	light.light_energy = 1.2
	light.shadow_enabled = true
	stage.add_child(light)
	Prop.box(stage, Vector3(8, 0.08, 8), Vector3(0, -0.06, 0), Color("#31372f"))
	prop = Prop.new()
	prop.kind = kind
	stage.add_child(prop)
	camera = Camera3D.new()
	camera.near = 0.01
	camera.fov = 42.0
	stage.add_child(camera)
	var focus: Vector3 = prop.get_meta("focus", Vector3(0, 0.7, 0))
	var offset: Vector3 = prop.get_meta("camera_offset", Vector3(2, 1, 3))
	camera.position = focus + offset * 1.22
	camera.look_at(focus)
	camera.current = true
	_camera_tween = create_tween().set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	_camera_tween.tween_property(camera, "position", focus + offset, 0.8)
	_close_button = Button.new()
	_close_button.text = "×"
	_close_button.position = Vector2(18, 18)
	_close_button.custom_minimum_size = Vector2(44, 44)
	_close_button.pressed.connect(close)
	add_child(_close_button)
	prop.sampled.connect(_on_sampled)
	gui_input.connect(_on_input)
	observed.emit({"kind": kind, "phase": "anchor", "time_usec": Time.get_ticks_usec()})
	if kind in ["wardrobe", "ratchet", "grille", "seal"]:
		await get_tree().create_timer(0.85).timeout
		if is_inside_tree() and not _closing: prop.activate()

func _on_sampled() -> void:
	_has_result = true
	observed.emit({"kind": kind, "phase": "result", "time_usec": Time.get_ticks_usec()})

func _on_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		_dragging = event.pressed
		_last = event.position
	elif event is InputEventMouseMotion and _dragging:
		var delta: Vector2 = event.position - _last
		_last = event.position
		var area := _display if _display.size.x > 0 else Rect2(Vector2.ZERO,size)
		if not area.has_point(event.position): return
		var normalized: Vector2 = (event.position-area.position)/area.size
		if kind in ["water", "cloth", "chalk", "drag", "boots"]:
			var local: Vector2 = (normalized - Vector2(0.5, 0.5)) * Vector2(0.8, 0.4)
			prop.sweep(delta.length(), local)
		elif kind in ["hand", "sleeve", "copper"]:
			prop.align_hand(Vector2((normalized.x - 0.5) * 0.9, 0))
		accept_event()

func close() -> void:
	if _closing: return
	_closing = true
	if _camera_tween != null: _camera_tween.kill()
	var focus: Vector3 = prop.get_meta("focus", Vector3.ZERO)
	var tween := create_tween().set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	tween.tween_property(camera, "position", camera.position + (camera.position - focus) * 0.18, 0.35)
	await tween.finished
	finished.emit(_has_result)
	queue_free()

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		close()
		get_viewport().set_input_as_handled()

func _process(_delta: float) -> void:
	if not is_instance_valid(wrist_anchor) or anchor_camera == null or anchor_container == null: return
	var projected := anchor_camera.unproject_position(wrist_anchor.global_position)
	var source_size := Vector2(anchor_camera.get_viewport().size)
	_anchor_point = anchor_container.get_global_rect().position + projected/source_size*anchor_container.size
	var panel_size := Vector2(minf(520,size.x*0.43),minf(370,size.y*0.44))
	var left := clampf(_anchor_point.x+24,12,size.x-panel_size.x-12)
	var top := clampf(_anchor_point.y-panel_size.y*0.4,64,size.y-panel_size.y-16)
	_display = Rect2(Vector2(left,top),panel_size)
	_container.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
	_container.position = _display.position
	_container.size = _display.size
	_close_button.position = _display.position+Vector2(8,8)
	queue_redraw()

func _draw() -> void:
	if _display.size.x <= 0: return
	draw_line(_anchor_point,_display.position+Vector2(0,_display.size.y*0.4),Color("#c9ab68"),2,true)
	draw_rect(_display.grow(2),Color("#c9ab68"),false,2)

func test_snapshot() -> Dictionary:
	return {"kind":kind,"completed":_has_result,"progress":prop.progress if prop != null else 0.0,"wrist_anchor":wrist_anchor.get_path() if is_instance_valid(wrist_anchor) else "","display_rect":[_display.position.x,_display.position.y,_display.size.x,_display.size.y]}
