extends RefCounted
## Palette and brushwork for the existing cutaway rooms; no new geometry or colliders.
const PAINT := preload("res://assets/materials/room_paint.gdshader")
const ROOMS := {
	"R05": {"wood": Color("#725b48"), "stone": Color("#b0a79c"), "cloth": Color("#63776c"), "wash": 0.34},
	"B-P": {"wood": Color("#8f583b"), "stone": Color("#c9b596"), "cloth": Color("#827861"), "wash": 0.38},
	"A-P": {"wood": Color("#605a4d"), "stone": Color("#aaa597"), "cloth": Color("#797058"), "wash": 0.31},
	"C-P": {"wood": Color("#527071"), "stone": Color("#b4c3c3"), "cloth": Color("#7a9290"), "wash": 0.38},
	"D-P": {"wood": Color("#704e4a"), "stone": Color("#aba3a0"), "cloth": Color("#6a746b"), "wash": 0.35},
	"F03": {"wood": Color("#835840"), "stone": Color("#bba99b"), "cloth": Color("#8c6155"), "wash": 0.38},
}

static func apply(room_id: String, room: Node3D) -> void:
	if not ROOMS.has(room_id): return
	var instances := room.get_node_or_null("Instances")
	if instances == null: return
	var palette: Dictionary = ROOMS[room_id]
	var materials := {}
	for prop in instances.get_children():
		if not prop is Node3D or not prop.visible: continue
		var tag := String(prop.name).to_lower()
		var architecture := "architecture" in tag
		for node in prop.find_children("*", "MeshInstance3D", true, false):
			var mesh_node := node as MeshInstance3D
			if mesh_node.mesh == null or mesh_node.material_override != null: continue
			for index in mesh_node.mesh.get_surface_count():
				var source := mesh_node.get_active_material(index) as StandardMaterial3D
				if source == null or source.albedo_texture != null or source.transparency != BaseMaterial3D.TRANSPARENCY_DISABLED: continue
				if source.emission_enabled: continue
				var finish := _finish(source.resource_name, tag, architecture)
				if finish < 0: continue
				var key := "%s:%d:%s" % [source.get_instance_id(), finish, architecture]
				if not materials.has(key): materials[key] = _paint(source, finish, palette, architecture)
				mesh_node.set_surface_override_material(index, materials[key])

static func _finish(material_name: String, prop: String, architecture: bool) -> int:
	var tone := material_name.to_lower()
	if tone.begins_with("lp_wood"): return 0
	if architecture and (tone.begins_with("lp_tile") or tone == "lp_stone"): return 1
	if "bed" in prop and tone in ["lp_green", "lp_book_green", "lp_cream"]: return 2
	return -1

static func _paint(source: StandardMaterial3D, finish: int, palette: Dictionary, architecture: bool) -> ShaderMaterial:
	var original := source.albedo_color
	var tint: Color = palette[["wood", "stone", "cloth"][finish]]
	# Keep the authored values for trim and tile alternation; the wash moves
	# hue and saturation without painting over the dark inlay or clue decals.
	var value := maxf(original.v, 0.001)
	var tinted := Color.from_hsv(tint.h, tint.s, value * (1.06 if finish == 0 else 1.0))
	return finish_material(original.lerp(tinted, 0.72 if architecture else 0.42), finish,
		float(palette.wash) * (0.42 if finish == 1 else 1.0), source.roughness, source.metallic, architecture)

static func finish_material(pigment: Color, finish: int, weight: float, roughness := 0.86, metallic := 0.0, fixed := true) -> ShaderMaterial:
	var layer := ShaderMaterial.new()
	layer.shader = PAINT
	layer.set_shader_parameter("pigment", pigment)
	layer.set_shader_parameter("roughness_value", clampf(roughness, 0.55, 0.93))
	layer.set_shader_parameter("sheen", metallic)
	layer.set_shader_parameter("paint_weight", weight)
	layer.set_shader_parameter("finish_kind", finish)
	layer.set_shader_parameter("fixed_surface", fixed)
	return layer
