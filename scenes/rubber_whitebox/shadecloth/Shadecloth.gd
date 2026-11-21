extends "res://scenes/rubber_whitebox/bellflower/Bellflower.gd"

const VIEWS := ["A-section", "B-floor", "C-folds", "D-sweep"]
const SUBTITLES := ["SECTION  /  LAMP · CANOPY · BLOWERS", "FLOOR  /  THE MOVING UMBRA", "CLOSE-UP  /  HALF-OPEN CLOTH", "SECTION  /  HALF AN ORBIT LATER"]
const REVIEW_ACTIONS := [&"shade_a", &"shade_b", &"shade_c", &"shade_d", &"shade_uncover", &"shade_live", &"shade_play"]
var _sheet: MeshInstance3D
var _indices := PackedInt32Array()
var _uv := PackedVector2Array()
var _fans: Array[Node3D] = []
var _fan_speed := 0.0
var _orbit_period := 840.0
var _fan_phase := 0.0
var _review_keys: Label
var _review := -1
var _uncovered := false
var _review_play := false
var _review_tick := 0
var _title: Label


func _worker_path() -> String:
	return "res://scenes/rubber_whitebox/shadecloth/shadecloth.py"


func _ready() -> void:
	for action in REVIEW_ACTIONS:
		if not InputMap.has_action(action):
			InputMap.add_action(action)
	super._ready()
	if _pipe != null and not _state.is_empty() and not _options.has("auto") and not _options.has("smoke") and not _options.has("walk"):
		_inspect(0)
		_review_play = not _options.has("pause-review")


func _build(packet: Dictionary) -> void:
	super._build(packet)
	_env.ambient_light_energy = 0.43
	_env.ambient_light_color = Color("c5cee0")
	_env.background_color = Color("272f3b")
	_env.fog_density = 0.004
	_env.tonemap_exposure = 1.08
	_env.sdfgi_enabled = true
	_env.sdfgi_energy = 0.23
	_env.sdfgi_use_occlusion = true
	_env.volumetric_fog_enabled = true
	_env.volumetric_fog_density = 0.011
	_env.volumetric_fog_albedo = Color("ded5c3")
	_env.volumetric_fog_length = 31.0
	var lamps := 0
	for source in get_children():
		if source is SpotLight3D:
			source.light_volumetric_fog_energy = 1.25 if lamps == 0 else 0.0
			lamps += 1
			source.shadow_blur = 0.66
			source.shadow_normal_bias = 0.35
			source.shadow_bias = 0.085
	for t in packet.cloth_tri:
		_indices.append_array(PackedInt32Array([int(t[0]), int(t[2]), int(t[1])]))
	var segments: Array = packet.cloth_segments
	for j in range(int(segments[1]) + 1):
		for i in range(int(segments[0]) + 1):
			_uv.append(Vector2(float(i) / float(segments[0]), float(j) / float(segments[1])))
	_sheet = MeshInstance3D.new()
	_sheet.name = "DoubleSidedBlackCloth"
	_sheet.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_DOUBLE_SIDED
	_sheet.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
	var weave := ShaderMaterial.new()
	weave.shader = preload("res://scenes/rubber_whitebox/shadecloth/Weave.gdshader")
	_sheet.material_override = weave
	add_child(_sheet)
	_fan_speed = float(packet.fans.rotor_deg_per_tick)
	_orbit_period = float(packet.cloth_period)
	_fan_phase = float(packet.fan_phase)
	for i in range(int(packet.fans.count)):
		_build_rotor(_groups["fan%d" % i])
	_title = Label.new()
	_title.position = Vector2(36, 29)
	_title.add_theme_font_size_override("font_size", 21)
	_title.add_theme_color_override("font_color", Color("e3cfaf"))
	_title.add_theme_color_override("font_outline_color", Color("171b22"))
	_title.add_theme_constant_override("outline_size", 6)
	_capture_layer.add_child(_title)
	_review_keys = Label.new()
	_review_keys.text = "1–4  Views     Space  Play/Pause     G  Cloth only     Enter  Walk"
	_review_keys.add_theme_font_size_override("font_size", 15)
	_review_keys.add_theme_color_override("font_color", Color("c0b4a4"))
	_review_keys.add_theme_color_override("font_outline_color", Color("171b22"))
	_review_keys.add_theme_constant_override("outline_size", 4)
	_capture_layer.add_child(_review_keys)
	_review_keys.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT)
	_review_keys.position += Vector2(36, -26)
	_title.hide()
	_review_keys.hide()


func _build_part(part: Dictionary) -> void:
	super._build_part(part)
	if str(part.group).begins_with("fan") and part.finish == "black":
		var fan: StaticBody3D = _groups[part.group]
		var casing: MeshInstance3D = fan.get_child(fan.get_child_count() - 2)
		if not _materials.has("cast_iron"):
			var iron := StandardMaterial3D.new()
			iron.albedo_color = Color("46474a")
			iron.metallic = 0.26
			iron.roughness = 0.72
			_materials["cast_iron"] = iron
		casing.material_override = _materials["cast_iron"]
	if part.id in ["lamp/glass", "lamp/glow_rim"]:
		var parent: StaticBody3D = _groups[part.group]
		var visual: MeshInstance3D = parent.get_child(parent.get_child_count() - 2)
		var enamel := StandardMaterial3D.new()
		enamel.albedo_color = Color("ffe1a9")
		enamel.emission_enabled = true
		enamel.emission = enamel.albedo_color
		enamel.emission_energy_multiplier = 2.1 if part.id == "lamp/glass" else 0.62
		visual.material_override = enamel


func _build_rotor(parent: Node3D) -> void:
	var hub := Node3D.new()
	hub.position = Vector3(0, 1.04, 0.35)
	parent.add_child(hub)
	var rotor := SurfaceTool.new()
	rotor.begin(Mesh.PRIMITIVE_TRIANGLES)
	for vane in range(8):
		var angle := float(vane) * TAU / 8.0
		var root := Vector3(0.12, 0.0, 0.0).rotated(Vector3.BACK, angle)
		var middle := Vector3(0.36, 0.11, 0.023).rotated(Vector3.BACK, angle)
		var end := Vector3(0.58, 0.075, -0.018).rotated(Vector3.BACK, angle)
		var edge := Vector3(0.47, -0.16, 0.024).rotated(Vector3.BACK, angle)
		for p in [root, middle, edge, middle, end, edge]:
			rotor.add_vertex(p)
	rotor.generate_normals()
	var vis := MeshInstance3D.new()
	vis.mesh = rotor.commit()
	vis.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var metal := StandardMaterial3D.new()
	metal.albedo_color = Color("695644")
	metal.cull_mode = BaseMaterial3D.CULL_DISABLED
	metal.metallic = 0.46
	metal.roughness = 0.55
	vis.material_override = metal
	hub.add_child(vis)
	_fans.append(hub)


func _apply(state: Dictionary) -> void:
	super._apply(state)
	if state.is_empty():
		return
	var points: Array = state.cloth
	_sheet.visible = not points.is_empty()
	if _sheet.visible:
		var vertices := PackedVector3Array()
		var normals := PackedVector3Array()
		normals.resize(points.size())
		for v in points:
			vertices.append(_vec(v))
		for base in range(0, _indices.size(), 3):
			var i := _indices[base]
			var j := _indices[base + 1]
			var k := _indices[base + 2]
			var n := (vertices[k] - vertices[i]).cross(vertices[j] - vertices[i])
			normals[i] += n
			normals[j] += n
			normals[k] += n
		for i in range(normals.size()):
			normals[i] = normals[i].normalized()
		var arrays := []
		arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX] = vertices
		arrays[Mesh.ARRAY_NORMAL] = normals
		arrays[Mesh.ARRAY_TEX_UV] = _uv
		arrays[Mesh.ARRAY_INDEX] = _indices
		var mesh := ArrayMesh.new()
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		_sheet.mesh = mesh
	var rotor_phase := TAU * (float(state.tick) + _fan_phase) / _orbit_period
	for i in range(_fans.size()):
		var bias := 138.0 * sin(rotor_phase - float(i) * TAU / float(_fans.size()))
		_fans[i].rotation.z = deg_to_rad(fmod(float(state.tick) * _fan_speed + i * 41.0 + bias, 360.0))
	if not _capture:
		_hud.text = _hud.text.replace("THE BELLFLOWER", "THE AIRBORNE SHADE")
		_hud.text += "\n1–4 Review cameras"


func _inspect(index: int) -> void:
	_review = index
	_review_play = false
	_capture = true
	_hud.hide()
	_radar.hide()
	_rays.hide()
	_hit_marks.hide()
	var state := _send({"op": "preview", "view": VIEWS[index], "uncovered": _uncovered})
	_apply(state)
	_review_tick = int(state.tick)
	_title.show()
	_review_keys.show()
	_title.text = "03   /   THE AIRBORNE SHADE\n%s%s" % [SUBTITLES[index], "  ·  UNCOVERED" if _uncovered else ""]


func _physics_process(delta: float) -> void:
	if _review >= 0:
		if _review_play:
			_review_tick += 1
			_apply(_send({"op":"preview", "view":VIEWS[_review], "uncovered":_uncovered, "frame_tick":_review_tick}))
		return
	super._physics_process(delta)


func _live() -> void:
	_review = -1
	_uncovered = false
	_capture = false
	_title.hide()
	_review_keys.hide()
	_hud.show()
	_hit_marks.show()
	_rays.visible = _show_rays
	_apply(_send({"op": "reset"}))


func _input(event: InputEvent) -> void:
	if _pipe != null:
		for i in range(REVIEW_ACTIONS.size()):
			if event.is_action_pressed(REVIEW_ACTIONS[i]):
				if i < VIEWS.size():
					_inspect(i)
				elif i == 4 and _review >= 0:
					_uncovered = not _uncovered
					_inspect(_review)
				elif i == 5:
					_live()
				elif i == 6 and _review >= 0:
					_review_play = not _review_play
				return
	super._input(event)


func _unhandled_key_input(event: InputEvent) -> void:
	if event.pressed and not event.echo and _pipe != null:
		if event.physical_keycode >= KEY_1 and event.physical_keycode <= KEY_4:
			_inspect(event.physical_keycode - KEY_1)
			return
		if event.physical_keycode == KEY_SPACE and _review >= 0:
			_review_play = not _review_play
			return
		if event.physical_keycode == KEY_ENTER and _review >= 0:
			_live()
			return
		if event.physical_keycode == KEY_G and _review >= 0:
			_uncovered = not _uncovered
			_inspect(_review)
			return
		if event.physical_keycode == KEY_ESCAPE:
			get_tree().quit()
			return
	super._unhandled_key_input(event)


func mcp_observe() -> Dictionary:
	var state := super.mcp_observe()
	if not state.is_empty():
		state["view"] = _state.shade_view
		state["cloth_visible"] = _sheet.visible
		state["cloth_vertices"] = _state.cloth.size()
		state["first_vertex_mm"] = _state.cloth[0] if _sheet.visible else []
	return state
