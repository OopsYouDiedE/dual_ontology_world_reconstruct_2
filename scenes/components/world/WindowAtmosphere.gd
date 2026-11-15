extends RefCounted
## 窗面薄雾与穿窗直射光；兼容 Compatibility，作用域留在真实开口附近。
const HAZE_SHADER := """
shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never, shadows_disabled;
uniform vec4 haze_tint : source_color = vec4(0.75, 0.82, 0.85, 0.055);
void fragment() {
    vec2 p = UV * 2.0 - 1.0;
    float edge = 1.0 - smoothstep(0.68, 1.0, max(abs(p.x), abs(p.y)));
    float wisps = 0.65 + 0.35 * sin(UV.y * 17.0 + sin(UV.x * 11.0 + TIME * 0.035));
    ALBEDO = haze_tint.rgb;
    ALPHA = haze_tint.a * edge * wisps;
}
"""

static func install_room(room: Node3D, center: Vector3) -> void:
	var instances := room.get_node_or_null("Instances")
	if instances == null: return
	for item in instances.get_children():
		if not item is Node3D or not "window" in item.name.to_lower(): continue
		var glass := item.find_child("Glass", true, false) as MeshInstance3D
		if glass == null or glass.mesh == null: continue
		var bounds := glass.get_aabb()
		var at := glass.to_global(bounds.get_center())
		var inward := Vector3(center.x - at.x, 0, center.z - at.z).normalized()
		install(item, at, inward, Vector2(bounds.size.x, bounds.size.y), str(item.name))

static func install(parent: Node3D, at: Vector3, inward: Vector3, aperture: Vector2, source_id: String) -> void:
	if inward.length_squared() < 0.01: return
	var root := Node3D.new()
	root.name = "WindowAtmosphere"
	root.set_meta("aperture_source", source_id)
	parent.add_child(root)
	root.global_transform = Transform3D(Basis.looking_at(-inward, Vector3.UP), at + inward * 0.06)
	var pane := MeshInstance3D.new()
	pane.name = "WindowLocalHaze"
	var quad := QuadMesh.new()
	quad.size = aperture * 0.96
	pane.mesh = quad
	pane.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var shader := Shader.new()
	shader.code = HAZE_SHADER
	var material := ShaderMaterial.new()
	material.shader = shader
	pane.material_override = material
	root.add_child(pane)
	var light := SpotLight3D.new()
	light.name = "ApertureSunlight"
	light.set_meta("aperture_source", source_id)
	light.spot_range = 6.5
	light.spot_angle = 26.0
	light.spot_angle_attenuation = 0.65
	light.light_energy = 0.0
	light.shadow_enabled = true
	light.shadow_bias = 0.035
	light.shadow_normal_bias = 0.35
	root.add_child(light)
	light.position.z = 0.08
	light.look_at(light.global_position + inward + Vector3(0, -0.62, 0), Vector3.UP)

static func apply(world: Node, lighting: Dictionary) -> void:
	for node in world.find_children("ApertureSunlight", "SpotLight3D", true, false):
		var light := node as SpotLight3D
		light.light_color = lighting.sun_color
		light.light_energy = float(lighting.day) * 2.1
	for node in world.find_children("WindowLocalHaze", "MeshInstance3D", true, false):
		var pane := node as MeshInstance3D
		var material: ShaderMaterial = pane.material_override
		material.set_shader_parameter("haze_tint", Color(0.75, 0.82, 0.85, 0.035 + float(lighting.day) * 0.025))
