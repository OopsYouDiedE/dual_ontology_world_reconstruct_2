@tool
extends Node3D
## A physical, double-sided leaf. The caller owns timing and page input.
## x=0 is the binding; z runs from -height/2 to +height/2; y is height.
## At progress 0 the front lies on the right; at 1 the back lies on the left.
## With reverse=true, those two end states are traversed in reverse order.

const LEAF_SHADER: Shader = preload("res://assets/materials/book_leaf_mesh_3d.gdshader")
const COLUMNS := 48
const ROWS := 10

var progress := 0.0
var page_size := Vector2(4.8, 6.8)
var reverse := false
var hardcover := false
var leaf_mesh: MeshInstance3D
var leaf_material: ShaderMaterial

func configure(front: Texture2D, back: Texture2D, size: Vector2, closing := false, rigid := false) -> void:
	assert(front != null and back != null, "Both sides of the leaf need a texture")
	assert(size.x > 0.0 and size.y > 0.0, "Leaf dimensions must be positive")
	page_size = size
	reverse = closing
	hardcover = rigid
	if leaf_mesh == null:
		leaf_mesh = MeshInstance3D.new()
		leaf_mesh.name = "LeafMesh"
		leaf_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
		add_child(leaf_mesh)
	leaf_material = ShaderMaterial.new()
	leaf_material.shader = LEAF_SHADER
	leaf_material.set_shader_parameter("front_texture", front)
	leaf_material.set_shader_parameter("back_texture", back)
	leaf_material.set_shader_parameter("page_size", page_size)
	leaf_material.set_shader_parameter("reverse", reverse)
	leaf_material.set_shader_parameter("flexibility", 0.035 if hardcover else 0.68)
	leaf_material.set_shader_parameter("paper_roughness", 0.91 if hardcover else 0.94)
	leaf_material.set_shader_parameter("edge_color", Color("73685b") if hardcover else Color("c8c3b7"))
	leaf_mesh.material_override = leaf_material
	leaf_mesh.mesh = _build_leaf_mesh(0.055 if hardcover else 0.012)
	# The GPU can place the leaf on either side of the binding or above it.
	# Keep its entire animated volume visible and eligible to cast shadows.
	leaf_mesh.custom_aabb = AABB(
		Vector3(-page_size.x - 0.15, -0.15, -page_size.y * 0.5 - 0.15),
		Vector3(page_size.x * 2.0 + 0.3, page_size.x + 0.3, page_size.y + 0.3))
	set_progress(0.0)

func set_progress(value: float) -> void:
	progress = clampf(value, 0.0, 1.0)
	if leaf_material != null:
		leaf_material.set_shader_parameter("progress", progress)

func set_textures(front: Texture2D, back: Texture2D) -> void:
	assert(front != null and back != null)
	if leaf_material == null:
		return
	leaf_material.set_shader_parameter("front_texture", front)
	leaf_material.set_shader_parameter("back_texture", back)

func set_surface_maps(front_normal: Texture2D, front_roughness: Texture2D, back_normal: Texture2D, back_roughness: Texture2D, cover_mount: bool = false) -> void:
	if leaf_material == null:
		return
	leaf_material.set_shader_parameter("front_normal_texture", front_normal)
	leaf_material.set_shader_parameter("front_roughness_texture", front_roughness)
	leaf_material.set_shader_parameter("back_normal_texture", back_normal)
	leaf_material.set_shader_parameter("back_roughness_texture", back_roughness)
	leaf_material.set_shader_parameter("has_front_normal", front_normal != null)
	leaf_material.set_shader_parameter("has_front_roughness", front_roughness != null)
	leaf_material.set_shader_parameter("has_back_normal", back_normal != null)
	leaf_material.set_shader_parameter("has_back_roughness", back_roughness != null)
	leaf_material.set_shader_parameter("front_paper_mount", cover_mount)
	leaf_material.set_shader_parameter("front_normal_strength", 0.25 if cover_mount else 0.12)
	leaf_material.set_shader_parameter("back_normal_strength", 0.12)

func set_material_masks(front: Texture2D, back: Texture2D) -> void:
	leaf_material.set_shader_parameter("front_material_mask", front)
	leaf_material.set_shader_parameter("back_material_mask", back)
	leaf_material.set_shader_parameter("has_material_masks", true)

## Rect2 in UV space of each side's texture (position = origin, size = extent).
func set_uv_rects(front_rect: Rect2, back_rect: Rect2) -> void:
	if leaf_material == null:
		return
	leaf_material.set_shader_parameter("front_uv_rect", Vector4(front_rect.position.x, front_rect.position.y, front_rect.size.x, front_rect.size.y))
	leaf_material.set_shader_parameter("back_uv_rect", Vector4(back_rect.position.x, back_rect.position.y, back_rect.size.x, back_rect.size.y))

func set_tint(color: Color) -> void:
	if leaf_material != null:
		leaf_material.set_shader_parameter("surface_tint", color)

func set_blank_paper(color: Color) -> void:
	if leaf_material != null:
		leaf_material.set_shader_parameter("blank_paper", color)

func set_direction(closing: bool) -> void:
	reverse = closing
	if leaf_material != null:
		leaf_material.set_shader_parameter("reverse", reverse)
	set_progress(0.0)

func _build_leaf_mesh(thickness: float) -> ArrayMesh:
	var vertices := PackedVector3Array()
	var normals := PackedVector3Array()
	var tangents := PackedFloat32Array()
	var uvs := PackedVector2Array()
	var tags := PackedColorArray()
	var indices := PackedInt32Array()
	# A closed shell needs outward winding AND outward normals on each skin.
	# The back is a real front-facing surface, not an inside face recovered by
	# fragment discard. This keeps color, depth and shadow passes consistent.
	for side in range(2):
		var offset := vertices.size()
		var front := side == 0
		var y := thickness * (0.5 if front else -0.5)
		var normal := Vector3.UP if front else Vector3.DOWN
		var tangent_x := 1.0 if front else -1.0
		for row in range(ROWS + 1):
			for column in range(COLUMNS + 1):
				var uv := Vector2(float(column) / COLUMNS, float(row) / ROWS)
				vertices.append(Vector3(uv.x * page_size.x, y, (uv.y - 0.5) * page_size.y))
				normals.append(normal)
				# Back U grows toward -X so the opened left page is readable.
				# With N/T both reversed there, handedness -1 still gives B=+Z.
				tangents.append_array(PackedFloat32Array([tangent_x, 0.0, 0.0, -1.0]))
				uvs.append(uv if front else Vector2(1.0 - uv.x, uv.y))
				tags.append(Color(float(side), 0.0, 0.0, 1.0))
		for row in range(ROWS):
			for column in range(COLUMNS):
				var a := offset + row * (COLUMNS + 1) + column
				var b := a + 1
				var c := a + COLUMNS + 1
				var d := c + 1
				# Godot uses clockwise front faces, seen from each exterior side.
				if front:
					indices.append_array(PackedInt32Array([a, b, c, b, d, c]))
				else:
					indices.append_array(PackedInt32Array([a, c, b, b, c, d]))
	# The perimeter is subdivided at the same intervals as the page skins.
	var perimeter: Array[Vector2] = []
	for column in range(COLUMNS + 1):
		perimeter.append(Vector2(float(column) / COLUMNS, 0.0))
	for row in range(1, ROWS + 1):
		perimeter.append(Vector2(1.0, float(row) / ROWS))
	for column in range(COLUMNS - 1, -1, -1):
		perimeter.append(Vector2(float(column) / COLUMNS, 1.0))
	for row in range(ROWS - 1, 0, -1):
		perimeter.append(Vector2(0.0, float(row) / ROWS))
	for edge in range(perimeter.size()):
		var a_uv: Vector2 = perimeter[edge]
		var b_uv: Vector2 = perimeter[(edge + 1) % perimeter.size()]
		var direction := (b_uv - a_uv).normalized()
		var normal := Vector3(direction.y, 0.0, -direction.x)
		var offset := vertices.size()
		for corner in range(4):
			var uv := a_uv if corner == 0 or corner == 3 else b_uv
			var y := thickness * (0.5 if corner < 2 else -0.5)
			vertices.append(Vector3(uv.x * page_size.x, y, (uv.y - 0.5) * page_size.y))
			normals.append(normal)
			tangents.append_array(PackedFloat32Array([direction.x, 0.0, direction.y, 1.0]))
			uvs.append(uv)
			tags.append(Color(0.0, 1.0, 0.0, 1.0))
		indices.append_array(PackedInt32Array([offset, offset + 2, offset + 1, offset, offset + 3, offset + 2]))
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_TANGENT] = tangents
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_COLOR] = tags
	arrays[Mesh.ARRAY_INDEX] = indices
	var result := ArrayMesh.new()
	result.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return result
