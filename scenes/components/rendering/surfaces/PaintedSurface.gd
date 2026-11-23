extends RefCounted
## Opaque painted architecture, joinery and interactive fixtures share Hall 04 light.
static func make(color: Color, roughness := 0.89, emission := Color.BLACK) -> ShaderMaterial:
	var mat := ShaderMaterial.new()
	mat.shader = preload("PaintedSurface.gdshader")
	mat.set_shader_parameter("pigment", color)
	mat.set_shader_parameter("roughness", roughness)
	mat.set_shader_parameter("emission", emission)
	return mat
## Named, untextured finishes on the authored clockwork kits; pivots and hitboxes stay authored.
const KIT_PIGMENTS := {"walnut":"53616b", "oxblood":"687884", "dark":"303940", "paper":"d9d5bd", "ivory":"d3d0bf", "ink":"30333a"}

static func finish_kit(root: Node3D) -> int:
	var applied := 0
	var paints := {}
	for part: MeshInstance3D in root.find_children("*", "MeshInstance3D", true, false):
		for i in part.mesh.get_surface_count():
			var source := part.get_active_material(i) as StandardMaterial3D
			if not source or not KIT_PIGMENTS.has(source.resource_name): continue
			if not paints.has(source.resource_name):
				paints[source.resource_name] = make(Color(KIT_PIGMENTS[source.resource_name]), source.roughness)
			part.set_surface_override_material(i, paints[source.resource_name])
			applied += 1
	return applied
