extends RefCounted
## Exterior geometry belongs to the original window in the same room world.
const Geometry := preload("res://scenes/components/interaction/InteractiveProp3D.gd")
const APERTURE_SHADER := """
shader_type spatial;
uniform mat4 window_from_world;
uniform vec2 aperture_half_size;
uniform vec4 surface_color : source_color;
varying vec3 world_position;
void vertex() {
    world_position = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}
void fragment() {
    vec3 eye = (window_from_world * vec4(INV_VIEW_MATRIX[3].xyz, 1.0)).xyz;
    vec3 point = (window_from_world * vec4(world_position, 1.0)).xyz;
    float along = -eye.z / (point.z - eye.z);
    vec2 aperture = mix(eye.xy, point.xy, along);
    if (along <= 0.0 || along >= 1.0 || any(greaterThan(abs(aperture), aperture_half_size))) discard;
    ALBEDO = surface_color.rgb;
    ROUGHNESS = 0.82;
}
"""

static func install(window: Node3D, glass: MeshInstance3D) -> bool:
	if window.get_node_or_null("WindowCourtyard") != null: return true
	var atmosphere := window.get_node_or_null("WindowAtmosphere") as Node3D
	if atmosphere == null or glass == null: return false
	var inward := glass.global_basis.z.normalized()
	if inward.dot(atmosphere.global_basis.z) < 0: inward = -inward
	var center := glass.to_global(glass.get_aabb().get_center())
	var yard := Node3D.new()
	yard.name = "WindowCourtyard"
	window.add_child(yard)
	yard.global_transform = Transform3D(Basis.looking_at(-inward,Vector3.UP),center)
	# R05 is upstairs: the courtyard paving is below the bedroom floor.
	var floor_y := -center.y - 2.4
	var stone := Color("#8a918d")
	Geometry.box(yard,Vector3(11,0.16,9),Vector3(0,floor_y,-4.8),stone.darkened(0.16)).name = "CourtyardPaving"
	Geometry.box(yard,Vector3(11,5.4,0.3),Vector3(0,floor_y+2.7,-8.5),Color("#777f7b")).name = "FarGardenWall"
	for x in [-5.0,5.0]:
		Geometry.box(yard,Vector3(0.3,5.4,9),Vector3(x,floor_y+2.7,-4.5),stone.darkened(0.18))
	for x in [-3.8,-1.9,0.0,1.9,3.8]:
		Geometry.box(yard,Vector3(0.15,5.5,0.42),Vector3(x,floor_y+2.75,-8.25),stone)
	for z in [-7.8,-6.3,-4.8,-3.3,-1.8]:
		Geometry.box(yard,Vector3(8.8,0.012,0.035),Vector3(0,floor_y+0.086,z),stone.lightened(0.13))
	for x in [-1.5,1.5]:
		Geometry.box(yard,Vector3(1.5,0.44,3.3),Vector3(x,floor_y+0.26,-5.0),Color("#6e7369"))
		Geometry.box(yard,Vector3(1.3,0.4,3.1),Vector3(x,floor_y+0.58,-5.0),Color("#536858"))
		for z in [-4.2,-5.7]:
			Geometry.rod(yard,Vector3(x,floor_y+0.6,z),Vector3(x,floor_y+4.1,z),0.07,Color("#625b4c"))
			var canopy := MeshInstance3D.new()
			var crown := SphereMesh.new()
			crown.radius = 0.9
			crown.height = 2.1
			crown.radial_segments = 8
			crown.rings = 4
			canopy.mesh = crown
			canopy.material_override = Geometry.material(Color("#617864"))
			yard.add_child(canopy)
			canopy.position = Vector3(x,floor_y+4.1,z)
	Geometry.box(yard,Vector3(1.9,0.14,0.55),Vector3(0,floor_y+0.62,-6.8),Color("#7a7464"))
	for x in [-0.72,0.72]: Geometry.box(yard,Vector3(0.15,0.6,0.4),Vector3(x,floor_y+0.3,-6.8),stone.darkened(0.2))
	var pane := Geometry.material(Color(0.72,0.82,0.85,0.10))
	pane.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	pane.cull_mode = BaseMaterial3D.CULL_DISABLED
	glass.material_override = pane
	glass.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# Clip exterior fragments against the real aperture, including cutaway views.
	# This is a material on the live exterior meshes; no copied world or viewport.
	var shader := Shader.new()
	shader.code = APERTURE_SHADER
	for mesh: MeshInstance3D in yard.find_children("*","MeshInstance3D",true,false):
		var color: Color = mesh.material_override.albedo_color
		var material := ShaderMaterial.new()
		material.shader = shader
		material.set_shader_parameter("surface_color",color)
		material.set_shader_parameter("window_from_world",yard.global_transform.affine_inverse())
		material.set_shader_parameter("aperture_half_size",Vector2(glass.get_aabb().size.x,glass.get_aabb().size.y)*0.5)
		mesh.material_override = material
		mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return true
