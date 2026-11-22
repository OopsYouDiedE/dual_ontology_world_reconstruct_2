extends RefCounted
## Adapt fitted cast surfaces per instance; imported meshes and textures remain shared.
const FINISH := preload("res://scenes/components/rendering/actors/CastDielectric.gdshader")
const PROFILES := {"coat": 0.68, "shirt": 0.68, "trim": 0.60,
	"trouser": 0.68, "boot": 0.56, "Complexion": 0.38}

static func apply(actor: Node3D) -> void:
	var finishes := {}
	for child in actor.find_children("*", "MeshInstance3D", true, false):
		var mesh := child as MeshInstance3D
		if mesh.mesh == null or mesh.material_override != null: continue
		for surface in mesh.mesh.get_surface_count():
			var imported := mesh.get_active_material(surface) as StandardMaterial3D
			if imported == null or not PROFILES.has(imported.resource_name): continue
			if imported.transparency != BaseMaterial3D.TRANSPARENCY_DISABLED: continue
			if not finishes.has(imported):
				var finish := ShaderMaterial.new()
				finish.shader = FINISH
				finish.set_shader_parameter("base_color", imported.albedo_color)
				if imported.albedo_texture != null:
					finish.set_shader_parameter("base_texture", imported.albedo_texture)
				finish.set_shader_parameter("surface_roughness", imported.roughness)
				finish.set_shader_parameter("double_sided", imported.cull_mode == BaseMaterial3D.CULL_DISABLED)
				finish.set_shader_parameter("toon_strength", PROFILES[imported.resource_name])
				finish.set_shader_parameter("stone_sheen", 0.025 if imported.resource_name == "Complexion" else 0.0)
				finishes[imported] = finish
			mesh.set_surface_override_material(surface, finishes[imported])
