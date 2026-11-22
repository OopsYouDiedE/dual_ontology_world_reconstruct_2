extends Node3D
## Ten experiment plates. Commands and the 60 Hz model are identical in both camera views.

const EngineModel = preload("res://scenes/physics_lab/Model.gd")
const Kit = preload("res://scenes/physics_lab/Geometry.gd")
const TITLES := ["The Three-Polarizer Gate", "The Standing-Wave Gallery", "The Observer Airlock",
	"The Folded Arcade", "The Sorting Gate", "The Inverted Shaft", "The Alchemical Crossing",
	"The Induction Hall", "Signal Delay & the Echo", "The Tape Antechamber"]
const NOTES := [
	"Crossed panes: dark. Park or insert the middle pane; turn its etched axis and check the detector.",
	"Compare the two lanes. A 1 m reflector shift swaps node and antinode. The trial stops after a visible warning.",
	"Sight holds the deck only while lit. Pass the deck to the second operator; restore sight before the countdown ends.",
	"Walk the four-turn loop. The same numbered frame on the upper landing leads to a longer arcade.",
	"Sample the next pellet, then route it. Keep fast pellets to the right; compare the baskets and clear the bit register.",
	"Bring both weights to the upper shelf, one per trip. The barbs measure travel against gravity; the side pocket bypasses them.",
	"Try the tools out of order, then follow the stock through field, bath and kiln. The three latches release one deck.",
	"Throw a probe, flip the field and repeat. Stroke the magnet through the coil and compare with a stationary magnet.",
	"Separate signal arrivals from frame-corrected order. Record a one-second echo on I, then take II during replay.",
	"Set the four bits. The read/write frame erases each bit and updates parity; the blank marker halts the machine."]
const CONTROLS := [
	["Insert / park", "Turn axis", "Read gate"],
	["Shift reflector", "Change station", "Test 1 s", "Abort test"],
	["Face / look away", "Toggle chamber light", "Send partner", "Recall"],
	["Take right portal", "Take left portal", "Cast probe", "Check return"],
	["Open for pellet", "Read velocity bit", "Erase bit", "Launch / pause"],
	["Flip gravity", "Travel to other floor", "Pick up / set down", "Pocket / brake"],
	["Magnetize", "Immerse", "Fire", "Lower deck"],
	["Flip field", "Throw probe", "Stroke magnet", "Stop magnet"],
	["Emit A / B", "Switch frame", "Record / replay", "Swap pad"],
	["Select next cell", "Flip bit", "Run tape", "Feed stock"]]
const ACTIONS := {&"lab_a": KEY_1, &"lab_b": KEY_2, &"lab_c": KEY_3, &"lab_d": KEY_4,
	&"lab_prev": KEY_BRACKETLEFT, &"lab_next": KEY_BRACKETRIGHT, &"lab_view": KEY_TAB,
	&"lab_reset": KEY_R, &"lab_pause": KEY_SPACE, &"lab_step": KEY_N}
const VIEW := [Vector3(6.4, 7.6, 12.5), Vector3(6.0, 7.5, 12.4), Vector3(5.7, 7.4, 13.0),
	Vector3(6.6, 8.1, 13.6), Vector3(5.2, 7.6, 13.4), Vector3(6.7, 8.0, 13.4),
	Vector3(5.8, 7.4, 12.7), Vector3(5.9, 7.6, 13.2), Vector3(5.6, 7.3, 12.4), Vector3(5.1, 7.6, 12.9)]
const WALK := [Vector3(4.27, 1.56, 3.30), Vector3(3.75, 1.56, 3), Vector3(-3, 1.56, 2.2),
	Vector3(4.8, 1.56, 2.9), Vector3(3.95, 1.56, 3.1), Vector3(-3.9, 1.56, 2.9),
	Vector3(-4.1, 1.56, 2.95), Vector3(3.9, 1.56, 3.1), Vector3(3.8, 1.56, 3.1), Vector3(3.9, 1.56, 3.1)]
var model := EngineModel.new()
var shell := Kit.new()
var stage: Node3D
var camera: Camera3D
var paused := false
var eye := false
var title: Label
var note: Label
var readout: Label
var flag_label: Label
var view_label: Label
var buttons: HBoxContainer


func _ready() -> void:
	for action: StringName in ACTIONS:
		if InputMap.has_action(action): continue
		InputMap.add_action(action)
		var key := InputEventKey.new()
		key.physical_keycode = ACTIONS[action]
		InputMap.action_add_event(action, key)
	for arg in OS.get_cmdline_user_args():
		if arg == "--lab-pause": paused = true
	get_viewport().msaa_3d = Viewport.MSAA_4X
	var lighting := WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color("b9c4cd")
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color("e3e8eb")
	env.ambient_light_energy = 0.30
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.tonemap_exposure = 0.84
	env.sdfgi_enabled = true
	env.sdfgi_min_cell_size = 0.20
	env.ssao_enabled = true
	env.ssao_radius = 0.9
	env.ssao_intensity = 1.58
	lighting.environment = env
	add_child(lighting)
	# A neutral studio softbox above the cutaway; the apparatus casts a soft shadow.
	var keylight := DirectionalLight3D.new()
	keylight.rotation_degrees = Vector3(-52, -39, 0)
	keylight.light_color = Color("fffbf4")
	keylight.light_energy = 0.88
	keylight.shadow_enabled = true
	keylight.light_angular_distance = 0.0
	add_child(keylight)
	camera = Camera3D.new()
	add_child(camera)
	camera.current = true
	make_ui()
	select(0)


func make_ui() -> void:
	var canvas := CanvasLayer.new()
	add_child(canvas)
	var top := VBoxContainer.new()
	top.position = Vector2(36, 24)
	top.add_theme_constant_override("separation", 3)
	canvas.add_child(top)
	text(top, "D U A L   O N T O L O G Y    /    M E C H A N I S M   L A B", 13, Color("4a555d"))
	title = text(top, "", 34, Color("273139"))
	view_label = text(top, "", 13, Color("4a555d"))
	var footer := PanelContainer.new()
	footer.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	footer.offset_top = -122
	var background := StyleBoxFlat.new()
	background.bg_color = Color("ecedea")
	background.border_color = Color("a5adae")
	background.border_width_top = 1
	background.content_margin_left = 36
	background.content_margin_right = 36
	background.content_margin_top = 8
	background.content_margin_bottom = 11
	footer.add_theme_stylebox_override("panel", background)
	canvas.add_child(footer)
	var panel := VBoxContainer.new()
	panel.add_theme_constant_override("separation", 4)
	footer.add_child(panel)
	var row := HBoxContainer.new()
	panel.add_child(row)
	flag_label = text(row, "", 14, Color("4a555d"))
	flag_label.custom_minimum_size.x = 115
	readout = text(row, "", 16, Color("273139"))
	note = text(panel, "", 14, Color("556169"))
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	buttons = HBoxContainer.new()
	buttons.add_theme_constant_override("separation", 9)
	panel.add_child(buttons)
	footer.grow_vertical = Control.GROW_DIRECTION_BEGIN


func text(parent: Node, caption: String, font_size_: int, color: Color) -> Label:
	var l := Label.new()
	l.add_theme_font_size_override("font_size", font_size_)
	l.add_theme_color_override("font_color", color)
	l.text = caption
	parent.add_child(l)
	return l


func make_button(caption: String, callback: Callable) -> void:
	var button := Button.new()
	button.text = caption
	button.focus_mode = Control.FOCUS_NONE
	button.add_theme_font_size_override("font_size", 13)
	for variant: String in ["normal", "hover", "pressed"]:
		var background := StyleBoxFlat.new()
		background.bg_color = Color("f7f7f4") if variant == "normal" else Color("d5dcda")
		background.border_color = Color("b8bfbe") if variant == "normal" else Color("788683")
		background.set_border_width_all(1)
		background.set_content_margin_all(8)
		button.add_theme_stylebox_override(variant, background)
	for color: String in ["font_color", "font_hover_color", "font_pressed_color"]:
		button.add_theme_color_override(color, Color("354148"))
	button.pressed.connect(callback)
	buttons.add_child(button)


func select(index: int) -> void:
	if is_instance_valid(stage):
		remove_child(stage)
		stage.queue_free()
	stage = Node3D.new()
	add_child(stage)
	model.reset(posmod(index, TITLES.size()))
	shell.build(stage, model.room)
	title.text = "%02d    %s" % [model.room + 1, TITLES[model.room]]
	note.text = NOTES[model.room]
	for child in buttons.get_children():
		buttons.remove_child(child)
		child.queue_free()
	for i in range(CONTROLS[model.room].size()):
		make_button("%d   %s" % [i + 1, CONTROLS[model.room][i]], act.bind(i))
	make_button("[   Previous", browse.bind(-1))
	make_button("]   Next", browse.bind(1))
	make_button("Tab   View", toggle_view)
	make_button("R   Reset", restart)
	update_camera()
	refresh()


func browse(increment: int) -> void:
	select(model.room + increment)


func restart() -> void:
	model.reset(model.room)
	update_camera()
	refresh()


func toggle_view() -> void:
	eye = not eye
	update_camera()
	refresh()


func update_camera() -> void:
	if eye:
		camera.projection = Camera3D.PROJECTION_PERSPECTIVE
		camera.fov = 68.0
		camera.v_offset = -0.17
		camera.position = WALK[model.room]
		var target := Vector3(0, 0.83, -0.07)
		if model.room == 3:
			var sector: Vector3 = shell.moving.portals[model.s.sector + 4 * model.s.layer]
			camera.position = sector + Vector3(0.0, 1.54, 1.48)
			target = sector + Vector3(0.0, 1.38, -0.2)
		if model.room == 5: target.y = 1.9
		camera.look_at(target)
	else:
		camera.projection = Camera3D.PROJECTION_ORTHOGONAL
		camera.size = 12.0 if model.room == 3 or model.room == 5 else 11.5
		camera.v_offset = 0.40
		camera.position = VIEW[model.room]
		camera.look_at(Vector3(0.10, 1.02 if model.room == 5 else 0.65, 0.03))


func act(index: int) -> void:
	if index >= CONTROLS[model.room].size(): return
	model.command(index)
	if model.room == 3 and eye: update_camera()
	refresh()


func _physics_process(_delta: float) -> void:
	if not paused:
		model.advance()
		refresh()


func _input(event: InputEvent) -> void:
	for i in range(4):
		if event.is_action_pressed([&"lab_a", &"lab_b", &"lab_c", &"lab_d"][i]): act(i)
	if event.is_action_pressed(&"lab_prev"): browse(-1)
	if event.is_action_pressed(&"lab_next"): browse(1)
	if event.is_action_pressed(&"lab_view"): toggle_view()
	if event.is_action_pressed(&"lab_reset"): restart()
	if event.is_action_pressed(&"lab_pause"):
		paused = not paused
		refresh()
	if event.is_action_pressed(&"lab_step") and paused:
		for i in range(20): model.advance()
		refresh()


func refresh() -> void:
	shell.update(model)
	var s: Dictionary = model.s
	var message := ""
	match model.room:
		0: message = "MIDDLE  %s  %03d°     /     DETECTOR  %05.1f%%    /    THRESHOLD  10%%" % ["IN" if s.inserted else "PARKED", s.angle, s.power * 100.0]
		1: message = "REFLECTOR  +%.1f m     /     STATION  %s     /     AMPLITUDE  %.2f" % [s.mirror_offset, "N" if s.zone == 0 else "A", s.envelope]
		2: message = "%02d / 27 RAYS     /     DECK  %s     /     PARTNER  %s" % [s.hits, "LOCKED" if s.hits > 0 else "UNSTABLE", "ACROSS" if s.partner else "NEAR BANK"]
		3: message = "FLOOR  %s     /     SECTOR  %d     /     PROBE  %s" % ["I" if s.layer == 0 else "II", s.sector + 1, "—" if s.probe_layer < 0 else "%.0f m  →  %s/%d" % [s.probe_length / 1000.0, "II" if s.probe_layer else "I", s.probe_sector + 1]]
		4: message = "VELOCITY  %d m/s     /     ENERGY L:R  %d:%d     /     BIT  %s     /     ERASED  %d" % [2 + 2 * EngineModel.speed_class(s.sample), s.energy_l, s.energy_r, "—" if s.register < 0 else str(s.register), s.erased]
		5: message = "g  %s     /     HEIGHT  %.2f m     /     %s     /     DELIVERED  %d / 2" % ["UP" if s.gravity > 0 else "DOWN", s.height, "SHELTERED" if s.pocket else "FIELD", s.loads.count(1)]
		6: message = "STOCK  %s     /     LATCHES   %d / 3     /     %s" % [["RAW", "MAGNETIC", "FLOATING", "LUMINOUS"][s.form], s.latched.count(true), "STROKE ACCEPTED" if s.valid else "TOOL REJECTED THIS FORM"]
		7: message = "FIELD  %s     /     EMF  %+.2f     /     DOOR HOLD  %02d t" % ["OUT" if s.polarity > 0 else "IN", s.emf, s.hold]
		8: message = "EVENT Δt′  %+.3f s     /     LENGTH & CLOCK  %.2f×     /     ECHO  %02d / 60" % [s.frame_delta, s.proper_rate, s.record.size()]
		9: message = "CELL %02d     /     STATE Q%d     /     %s" % [s.head, s.parity, s.halt]
	readout.text = message
	flag_label.text = "TRIAL STOPPED" if s.fault else ("WARN  %02d" % s.warning if s.warning else ("  ✓   VERIFIED" if s.passed else "EXPERIMENT"))
	view_label.text = ("EYE LEVEL" if eye else "AXONOMETRIC SECTION") + ("     /     PAUSED · N advances 20 ticks" if paused else "     /     60 Hz · Space pauses")


func mcp_observe() -> Dictionary:
	return {"plate": model.room + 1, "title": TITLES[model.room], "tick": model.tick,
		"paused": paused, "camera": "eye" if eye else "section", "state": model.s.duplicate(true)}
