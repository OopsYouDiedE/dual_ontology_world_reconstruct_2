extends "res://scenes/character_review/R05NativeMotion.gd"
## Local wardrobe review: each outfit carries the selected character's own embedded action.

const DIR := "res://.runtime/mpfb2-wardrobe/"
const FIT_DIR := "res://.runtime/mpfb2-fit/godot/"
const STATIC_DIR := "res://.runtime/academy-body-pilot/anatomy-photo-relief-final/models/"
const STATIC_MODELS := {
	"lucian": "02-lucian.glb", "ward": "03-ward.glb",
	"shending": "04-shen-ding.glb", "caretaker": "07-caretaker.glb",
}
const CAST := {
	"r05": ["R-05", "Detective", {"base": "Trial clothes", "suit": "Formal suit", "jacket": "Casual jacket", "shirt": "Striped shirt"}],
	"halvard": ["R-06", "Halvard", {"base": "Trial clothes", "jacket": "Casual jacket", "workwear": "Work overalls"}],
	"jane": ["R-03", "Jane", {"base": "Trial clothes", "shorts": "Denim shorts", "sport": "Sportswear"}],
	"qingyue": ["R-10", "Qingyue", {"base": "Trial clothes", "skirt": "Formal skirt", "jeans": "T-shirt & jeans"}],
	"lucian": ["R-01", "Lucian", {"base": "Original base"}],
	"ward": ["R-04", "Ward", {"base": "Original base"}],
	"shending": ["R-07", "Shen Ding", {"base": "Original base"}],
	"caretaker": ["Caretaker", "", {"base": "Original base"}],
}
const POSES := {"front": 0.0, "reach": 0.75, "knee": 2.25, "side": 0.0, "back": 0.0}
const CAPTIONS := {"front": "Front", "reach": "Reach", "knee": "Knee bend", "side": "Side", "back": "Back"}
var characters: Dictionary[String, Button]
var options: Dictionary[String, Button]
var samples: Dictionary[String, Button]
var control: Node3D
var outfits: GridContainer
var show_shoes: CheckButton
var character := "r05"
var selected := "base"
var pose := "front"
var report_error := ""


func _ready() -> void:
	super._ready()
	if player == null or rig == null or not player.has_animation(CLIP):
		return
	control = actor
	var rows: VBoxContainer = $Overlay/Panel/Margin/Rows
	var cast_grid := make_grid(rows)
	for id: String in CAST:
		var button := make_button(cast_grid, CAST[id][0])
		button.pressed.connect(_switch.bind(id, "base"))
		button.disabled = id != "r05" and not FileAccess.file_exists(path_for(id, "base"))
		characters[id] = button
	outfits = make_grid(rows)
	var grid := make_grid(rows)
	for id: String in POSES:
		var button := make_button(grid, CAPTIONS[id])
		button.pressed.connect(_set_pose.bind(id))
		samples[id] = button
	show_shoes = CheckButton.new()
	show_shoes.text = "Show shoe mesh"
	show_shoes.button_pressed = true
	show_shoes.toggled.connect(_set_shoes_visible)
	rows.add_child(show_shoes)
	refresh_outfits()
	update_shoe_control()
	_set_pose("front")


func make_grid(parent: VBoxContainer) -> GridContainer:
	var grid := GridContainer.new()
	grid.columns = 2
	parent.add_child(grid)
	return grid


func make_button(parent: GridContainer, text_: String) -> Button:
	var button := Button.new()
	button.text = text_
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	parent.add_child(button)
	return button


func path_for(who: String, id: String) -> String:
	if id == "base" and who in STATIC_MODELS:
		return STATIC_DIR + str(STATIC_MODELS[who])
	if id == "base":
		return FIT_DIR + who + "-fit.glb"
	return DIR + "%s_%s.glb" % [who, id]


func refresh_outfits() -> void:
	var row: Array = CAST[character]
	$Overlay/Panel/Margin/Rows/Title.text = row[0] if row[1] == "" else "%s / %s" % [row[0], row[1]]
	var still := character in STATIC_MODELS
	replay.disabled = still
	samples["reach"].disabled = still
	samples["knee"].disabled = still
	# These four source GLBs were exported at a normalized height of 1 m.
	# Match the framing with the camera, leaving the source model unchanged.
	var camera: Camera3D = $Camera
	var ratio := 1.0 / 1.77 if still else 1.0
	camera.size = 2.26 * ratio
	camera.position = Vector3(0, 1.34, 4) * ratio
	for child in outfits.get_children():
		outfits.remove_child(child)
		child.queue_free()
	options.clear()
	var labels: Dictionary = CAST[character][2]
	for id: String in labels:
		var button := make_button(outfits, labels[id])
		button.pressed.connect(_switch.bind(character, id))
		button.disabled = id != "base" and not FileAccess.file_exists(path_for(character, id))
		options[id] = button


func _switch(who: String, id: String) -> void:
	if who == character and id == selected:
		_set_pose(pose)
		return
	var next := control if who == "r05" and id == "base" else load_variant(who, id)
	if next == null:
		fail_outfit("Could not import %s / %s" % [who, id])
		return
	var players := next.find_children("*", "AnimationPlayer", true, false)
	var rigs := next.find_children("*", "Skeleton3D", true, false)
	var still := who in STATIC_MODELS
	var valid: bool = players.is_empty() and rigs.is_empty() if still else (
		players.size() == 1 and rigs.size() == 1 and players[0].has_animation(CLIP))
	if not valid:
		if next != control:
			next.free()
		fail_outfit("Unexpected action or rig configuration: %s / %s" % [who, id])
		return
	var changed_character := character != who
	if player != null:
		player.pause()
	actor.hide()
	if actor != control:
		actor.queue_free()
	if next != control:
		add_child(next)
		if not still:
			players[0].animation_finished.connect(_on_finished)
	actor = next
	actor.show()
	player = null if still else players[0]
	rig = null if still else rigs[0]
	character = who
	selected = id
	report_error = ""
	if changed_character:
		refresh_outfits()
	apply_review_materials()
	update_shoe_control()
	_set_pose("front" if changed_character else pose)


func shoe_meshes() -> Array[Node]:
	return actor.find_children("Wardrobe_Shoes*", "MeshInstance3D", true, false)


func _set_shoes_visible(value: bool) -> void:
	for mesh: MeshInstance3D in shoe_meshes():
		mesh.visible = value


func update_shoe_control() -> void:
	show_shoes.disabled = shoe_meshes().is_empty()
	_set_shoes_visible(show_shoes.button_pressed)


func load_variant(who: String, id: String) -> Node3D:
	var importer := GLTFDocument.new()
	var state := GLTFState.new()
	var error := importer.append_from_file(ProjectSettings.globalize_path(path_for(who, id)), state)
	if error != OK:
		return null
	var obj := importer.generate_scene(state, 30.0, false, false) as Node3D
	if obj != null:
		obj.name = "%s_%s" % [who, id]
	return obj


func fail_outfit(reason: String) -> void:
	report_error = reason
	status.text = reason
	push_error(reason)


func play_original() -> void:
	if player == null:
		return
	pose = "live"
	actor.rotation.y = 0.27
	super.play_original()


func _set_pose(id: String) -> void:
	if id == "live":
		play_original()
		return
	pose = id
	finished = false
	var offset := 0.0 if player == null else 0.27
	actor.rotation.y = {"back": PI + offset, "side": PI * 0.5}.get(id, offset)
	if player == null:
		status.text = "Original base (static) / " + str(CAPTIONS[id])
		return
	player.play(CLIP, 0.0)
	player.advance(0.0)
	player.seek(POSES[id], true)
	player.pause()
	status.text = "%s / %s" % [CAST[character][2][selected], CAPTIONS[id]]


func apply_review_materials() -> void:
	super.apply_review_materials()
	for node in actor.find_children("*", "MeshInstance3D", true, false):
		var item := node as MeshInstance3D
		if item.mesh == null:
			continue
		var skin := item.mesh.resource_name == &"Review_Body"
		if not skin and not item.name.begins_with("Wardrobe"):
			continue
		for index in item.mesh.get_surface_count():
			var source := item.mesh.surface_get_material(index) as StandardMaterial3D
			if source == null:
				continue
			var shader := ShaderMaterial.new()
			shader.shader = TOON
			shader.set_shader_parameter("pigment", source.albedo_color)
			shader.set_shader_parameter("band_width", 0.10 if skin else 0.08)
			if source.albedo_texture != null:
				shader.set_shader_parameter("use_pigment_tex", true)
				shader.set_shader_parameter("pigment_tex", source.albedo_texture)
			var line := ShaderMaterial.new()
			line.shader = HULL
			line.set_shader_parameter("width_m", 0.00135 if skin else 0.0017)
			shader.next_pass = line
			item.set_surface_override_material(index, shader)


func mcp_observe() -> Dictionary:
	var still := character in STATIC_MODELS
	var state := {"ready": true, "bones": 0, "clips": [], "playing": false} if still else super.mcp_observe()
	if not state.get("ready", false):
		return state
	state["test_mode"] = "static" if still else "native_motion"
	if still:
		state["mesh_count"] = actor.find_children("*", "MeshInstance3D", true, false).size()
		state["base_clothing"] = actor.find_children("Underwear*", "MeshInstance3D", true, false).size()
	state["character"] = character
	state["model"] = control.scene_file_path if character == "r05" and selected == "base" else path_for(character, selected)
	state["outfit"] = selected
	state["pose"] = pose
	if pose in POSES:
		state["seconds"] = POSES[pose]
	state["wardrobe_error"] = report_error
	state["cast_buttons"] = button_coords(characters)
	state["wardrobe_buttons"] = button_coords(options)
	state["pose_buttons"] = button_coords(samples)
	if not show_shoes.disabled:
		var center := show_shoes.get_global_rect().get_center()
		state["shoe_button"] = [center.x, center.y]
		state["shoes_visible"] = (shoe_meshes()[0] as MeshInstance3D).visible
	state["garment_meshes"] = actor.find_children("Wardrobe*", "MeshInstance3D", true, false).size()
	return state


func button_coords(buttons: Dictionary[String, Button]) -> Dictionary:
	var coords := {}
	for id: String in buttons:
		if buttons[id].disabled:
			continue
		var center := buttons[id].get_global_rect().get_center()
		coords[id] = [center.x, center.y]
	return coords
