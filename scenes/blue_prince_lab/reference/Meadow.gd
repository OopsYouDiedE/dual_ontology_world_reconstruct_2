extends Node3D
## Each cullable 5 m patch shares one tuft; no per-blade Nodes or frame uploads.
var count := 0
var camp := false
var lamp: OmniLight3D
var age := 0.0

func build(is_camp: bool) -> void:
	camp = is_camp
	var rng := RandomNumberGenerator.new()
	rng.seed = 1927 if camp else 3145
	var material := ShaderMaterial.new()
	material.shader = preload("Grass.gdshader")
	var tuft := SurfaceTool.new()
	tuft.begin(Mesh.PRIMITIVE_TRIANGLES)
	tuft.set_material(material)
	for i in 9:
		var a := rng.randf()*TAU
		var side := Vector3(cos(a),0,sin(a))
		var foot := side*rng.randf_range(.014,.18)
		var w := rng.randf_range(.013,.026)
		var head := foot+Vector3.UP*rng.randf_range(.11,.265)+side*rng.randf_range(.028,.105)
		for j in 3:
			tuft.set_normal(Vector3.UP)
			tuft.set_uv(Vector2(0,1 if j==2 else 0))
			tuft.add_vertex([foot-side.cross(Vector3.UP)*w,foot+side.cross(Vector3.UP)*w,head][j])
	var source := tuft.commit()
	for cz in range(-4,2):
		for cx in range(-3,3):
			var origin := Vector3(cx*5,0,cz*5)
			var spots: Array[Vector3] = []
			for i in (780 if cz>=-2 else 390):
				var p := origin+Vector3(rng.randf()*5,0,rng.randf()*5)
				var path := -.39*p.z-.6+.65*sin(p.z*.28) if camp else 1.32-.34*p.z-.038*p.z*p.z
				var margin := 1.1+.9*(p.z+17)/26 if camp else .52
				if absf(p.x-path)<margin+rng.randf_range(-.18,.12): continue
				if camp and p.x> -1 and p.x<3.75 and p.z> -5.45 and p.z<-.27: continue
				spots.append(p-origin)
			if spots.is_empty(): continue
			var batch := MultiMesh.new()
			batch.transform_format = MultiMesh.TRANSFORM_3D
			batch.use_custom_data = true
			batch.mesh = source
			batch.instance_count = spots.size()
			for j in spots.size():
				var size_factor := rng.randf_range(.66,1.42)
				batch.set_instance_transform(j,Transform3D(Basis(Vector3.UP,rng.randf()*TAU).scaled(Vector3.ONE*size_factor),spots[j]))
				batch.set_instance_custom_data(j,Color(rng.randf(),0,0,1))
			var patch := MultiMeshInstance3D.new()
			patch.multimesh = batch
			patch.layers = 4
			patch.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			patch.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
			patch.position = origin
			add_child(patch)
			count += spots.size()
	if not camp: return
	for i in 12:
		var a := TAU*i/7.0
		var inner := i>=7
		var mesh := CylinderMesh.new()
		mesh.radial_segments = 5
		mesh.rings = 3
		mesh.bottom_radius = .105 if inner else .14
		mesh.top_radius = .008
		mesh.height = rng.randf_range(.32,.50) if inner else rng.randf_range(.44,.72)
		var mat := ShaderMaterial.new()
		mat.shader = preload("Flame.gdshader")
		mat.set_shader_parameter("phase",i*1.74)
		mat.set_shader_parameter("ember",Color("fff6a3" if inner else "ffc049"))
		mat.set_shader_parameter("tip",Color("ffc65e" if inner else "ee5d24"))
		var tongue := MeshInstance3D.new()
		tongue.mesh = mesh
		tongue.material_override = mat
		tongue.layers = 4
		tongue.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		var r := .15 if inner else .24
		tongue.position = Vector3(-.10+cos(a)*r,.17+mesh.height*.5,-1.1+sin(a)*r)
		add_child(tongue)
	lamp = OmniLight3D.new()
	lamp.position = Vector3(-.10,.70,-1.1)
	lamp.light_cull_mask = 4
	lamp.light_color = Color("ff9e48")
	lamp.omni_range = 4.7
	add_child(lamp)

func _process(delta: float) -> void:
	if lamp:
		age += delta
		lamp.light_energy = 2.5+.33*sin(age*6.8)+.21*sin(age*14.3+.9)
