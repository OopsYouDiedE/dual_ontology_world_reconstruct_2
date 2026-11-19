extends Node3D
## Optional local-only display of original A26 print meshes. No procedural mechanical substitutes.
const GLB := "res://.runtime/tourbillon-a26/a26-hall-exhibit.glb"
const MANIFEST := "res://.runtime/tourbillon-a26/a26-hall-exhibit.json"
const SOURCE_SHA := "0eff0d11071f4841b60d43aa295fe142dabb0d551048e1242f4b96adaef0d9be"
const FINISH := preload("res://scenes/blue_prince_lab/HallFinish.gdshader")
const PALETTE := {"patina": Color("4d6874"), "brass": Color("b8874e"), "steel": Color("a4b6bf"),
	"plinth": Color("626f7a")}
var parts: Array[Dictionary] = []
var exploded := false
var blend := 0.0
var transition: Tween

func load_local() -> bool:
	if not FileAccess.file_exists(GLB) or not FileAccess.file_exists(MANIFEST):
		push_warning("A26 preview requested; build the local GLB and manifest first.")
		return false
	var manifest: Variant = JSON.parse_string(FileAccess.get_file_as_string(MANIFEST))
	if not manifest is Dictionary or manifest.get("archive_sha256", "") != SOURCE_SHA:
		return false
	var rows: Variant = manifest.get("parts", {})
	if not rows is Dictionary or rows.size() != 13:
		return false
	var doc := GLTFDocument.new()
	var state := GLTFState.new()
	if doc.append_from_file(ProjectSettings.globalize_path(GLB), state) != OK:
		return false
	var model := doc.generate_scene(state)
	if model == null:
		return false
	var finishes := {}
	for key: String in PALETTE:
		var mat := ShaderMaterial.new()
		mat.shader = FINISH
		mat.set_shader_parameter("pigment", PALETTE[key])
		mat.set_shader_parameter("grain", 0.10)
		mat.set_shader_parameter("stone_sheen", 0.0 if key == "plinth" else 0.13)
		finishes[key] = mat
	for key: String in rows:
		var part := model.find_child(key, true, false) as MeshInstance3D
		var row: Variant = rows[key]
		if part == null or part.mesh == null or not row is Dictionary or not finishes.has(row.get("finish", "")):
			model.free()
			parts.clear()
			return false
		var shift: Variant = row.get("explode", [])
		if not shift is Array or shift.size() != 3:
			model.free()
			parts.clear()
			return false
		part.material_override = finishes[row.finish]
		part.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
		parts.append({"mesh": part, "rest": part.position, "shift": Vector3(shift[0], shift[1], shift[2])})
	add_child(model)
	_add_plinth(finishes.plinth)
	return true

func _add_plinth(material: Material) -> void:
	for spec: Array in [[Vector3(1.19,0.11,1.10),0.055],[Vector3(0.99,0.51,0.92),0.355],
			[Vector3(1.22,0.12,1.13),0.67]]:
		var cap := MeshInstance3D.new()
		var stone := BoxMesh.new()
		stone.size = spec[0]
		cap.mesh = stone
		cap.position.y = spec[1]
		cap.material_override = material
		add_child(cap)
	var body := StaticBody3D.new()
	var col := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(1.22, 1.35, 1.13)
	col.shape = shape
	col.position.y = shape.size.y * 0.5
	body.add_child(col)
	add_child(body)

func interact() -> void:
	exploded = not exploded
	if transition:
		transition.kill()
	transition = create_tween().set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN_OUT)
	transition.tween_method(_set_explode, blend, 1.0 if exploded else 0.0, 0.72)

func _set_explode(t: float) -> void:
	blend = t
	for row: Dictionary in parts:
		row.mesh.position = row.rest + row.shift * t
