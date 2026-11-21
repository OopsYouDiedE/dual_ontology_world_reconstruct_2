extends "res://scenes/character_review/R05NativeMotion.gd"
## Local wardrobe review: each outfit carries the selected character's own embedded action.

const DIR := "res://.runtime/mpfb2-wardrobe/"
const DETAIL_DIR := "res://.runtime/mpfb2-detail/"
const PORTRAIT_HEIGHTS := {
	"r05": 1.77, "halvard": 1.82, "jane": 1.56, "qingyue": 1.64,
	"lucian": 1.79, "ward": 1.80, "shending": 1.75, "caretaker": 1.84,
}
const PAINT_STOCK := {"r05": "r05_jacket", "qingyue": "qingyue_skirt"}
const DETAIL_LABELS := {"detail": "Refined body", "paint_stock": "Stock color", "paint": "Academy repaint"}
const FIT_DIR := "res://.runtime/mpfb2-fit/godot/"
const CAST := {
	"r05": ["R-05", "Detective", {"base": "Trial clothes", "suit": "Formal suit", "jacket": "Casual jacket", "shirt": "Striped shirt"}],
	"halvard": ["R-06", "Halvard", {"base": "Trial clothes", "jacket": "Casual jacket", "workwear": "Work overalls"}],
	"jane": ["R-03", "Jane", {"base": "Trial clothes", "shorts": "Denim shorts", "sport": "Sportswear"}],
	"qingyue": ["R-10", "Qingyue", {"base": "Trial clothes", "skirt": "Formal skirt", "jeans": "T-shirt & jeans"}],
	"lucian": ["R-01", "Lucian", {"base": "Trial clothes", "shirt": "Striped shirt", "fitted": "Fitted T-shirt"}],
	"ward": ["R-04", "Ward", {"base": "Trial clothes", "suit": "Formal suit", "fitted": "Fitted T-shirt"}],
	"shending": ["R-07", "Shen Ding", {"base": "Trial clothes", "workwear": "Work overalls", "fitted": "Fitted T-shirt"}],
	"caretaker": ["Caretaker", "", {"base": "Trial clothes", "suit": "Formal suit", "fitted": "Fitted T-shirt"}],
}
const POSES := {"front": 0.0, "reach": 0.75, "knee": 2.25, "side": 0.0, "back": 0.0, "portrait": 0.0, "profile": 0.0}
const CAPTIONS := {"front": "Front", "reach": "Reach", "knee": "Knee bend", "side": "Side", "back": "Back", "portrait": "Face", "profile": "Face profile"}
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
	if id == "detail":
		return DETAIL_DIR + ("r05/r05-styled.glb" if who == "r05" else "godot/" + who + "-fit.glb")
	if id == "paint_stock" or id == "paint":
		return DETAIL_DIR + PAINT_STOCK[who] + ("_paint.glb" if id == "paint" else ".glb")
	if id == "before":
		return DIR + "face-before/" + who + "-fit.glb"
	if id == "base":
		return FIT_DIR + who + "-fit.glb"
	return DIR + "%s_%s.glb" % [who, id]


func refresh_outfits() -> void:
	var row: Array = CAST[character]
	$Overlay/Panel/Margin/Rows/Title.text = row[0] if row[1] == "" else "%s / %s" % [row[0], row[1]]
	for child in outfits.get_children():
		outfits.remove_child(child)
		child.queue_free()
	options.clear()
	var labels: Dictionary = CAST[character][2].duplicate()
	if FileAccess.file_exists(path_for(character, "before")):
		labels["before"] = "Previous face"
	if FileAccess.file_exists(path_for(character, "detail")):
		labels["detail"] = DETAIL_LABELS["detail"]
	if character in PAINT_STOCK:
		for id in ["paint_stock", "paint"]:
			if FileAccess.file_exists(path_for(character, id)):
				labels[id] = DETAIL_LABELS[id]
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
	if players.size() != 1 or rigs.size() != 1 or not players[0].has_animation(CLIP):
		if next != control:
			next.free()
		fail_outfit("Missing native action or rig: %s / %s" % [who, id])
		return
	var changed_character := character != who
	player.pause()
	actor.hide()
	if actor != control:
		actor.queue_free()
	if next != control:
		add_child(next)
		players[0].animation_finished.connect(_on_finished)
	actor = next
	actor.show()
	player = players[0]
	rig = rigs[0]
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


func frame_view(close_up: bool) -> void:
	var camera: Camera3D = $Camera
	if close_up:
		camera.position = Vector3(0, PORTRAIT_HEIGHTS[character] - 0.128, 2.4)
		camera.rotation_degrees.x = 0.0
		camera.size = 0.41
	else:
		camera.position = Vector3(0, 1.34, 4)
		camera.rotation_degrees.x = -5.0
		camera.size = 2.26


func play_original() -> void:
	frame_view(false)
	pose = "live"
	actor.rotation.y = 0.27
	super.play_original()


func _set_pose(id: String) -> void:
	if id == "live":
		play_original()
		return
	pose = id
	finished = false
	frame_view(id == "portrait" or id == "profile")
	actor.rotation.y = {"back": PI + 0.27, "side": PI * 0.5, "portrait": 0.0, "profile": PI * 0.5}.get(id, 0.27)
	player.play(CLIP, 0.0)
	player.advance(0.0)
	player.seek(POSES[id], true)
	player.pause()
	var label: String = "Previous face" if selected == "before" else str(DETAIL_LABELS.get(selected, CAST[character][2].get(selected, selected)))
	status.text = "%s / %s" % [label, CAPTIONS[id]]


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
	var state := super.mcp_observe()
	if not state.get("ready", false):
		return state
	state["character"] = character
	state["test_mode"] = "native_motion"
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
