extends MeshInstance3D
## A ribbon with a top edge as well as a side, readable from overhead or in profile.
var finish := ShaderMaterial.new()

func _init() -> void:
	name = "Hairspring"
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in 97:
		var u := i / 96.0
		var radial := Vector3(cos(TAU*4*u), sin(TAU*4*u), 0)
		var p := radial * lerpf(.032, .15, u) + Vector3(0, 0, .179)
		for j in 4:
			st.set_uv(Vector2(u, 0))
			st.set_normal(Vector3.BACK if j < 2 else radial)
			st.add_vertex(p + radial * (-.002 if j == 0 else .002) + Vector3.BACK * (-.007 if j == 3 else .007))
		if i > 0:
			var k := (i-1)*4
			for j in [0,1,4,1,5,4,2,3,6,3,7,6]: st.add_index(k+j)
	mesh = st.commit()
	finish.shader = preload("res://scenes/blue_prince_lab/reference/Hairspring.gdshader")
	material_override = finish
