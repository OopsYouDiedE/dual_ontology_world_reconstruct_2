@tool
class_name GothicOculus3D
extends GothicHallPiece3D
## Round clerestory window with quatrefoil tracery, beam and halo. Faces local +Z
## (rotate the node to aim it into the room).

@export var radius := 0.62:
	set(v): radius = v; changed()
@export var glass_texture: Texture2D:
	set(v): glass_texture = v; changed()

func _build() -> void:
	var beam_tex := glass_texture if glass_texture else load_texture(ROSE_SOUTH_TEX)
	var glass := _make_stained_glass_mat(beam_tex, Color("6c92c9"), 0.65)
	var r := radius
	var disc := SurfaceTool.new(); disc.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in 24:
		var a0 := TAU * i / 24.0
		var a1 := TAU * (i + 1) / 24.0
		_add_uv_tri(disc, Vector3.ZERO, Vector3(cos(a0), sin(a0), 0) * r, Vector3(cos(a1), sin(a1), 0) * r,
			Vector2(0.5, 0.5), Vector2(0.5 + 0.5 * cos(a0), 0.5 - 0.5 * sin(a0)), Vector2(0.5 + 0.5 * cos(a1), 0.5 - 0.5 * sin(a1)), Vector3.BACK)
	_commit_mesh(disc, glass, "OculusGlass")
	var tracery := SurfaceTool.new(); tracery.begin(Mesh.PRIMITIVE_TRIANGLES)
	var rings: Array = [[Vector2.ZERO, r, 0.07]]
	for k in 4:
		rings.append([Vector2(cos(k * TAU / 4.0), sin(k * TAU / 4.0)) * r * 0.46, r * 0.46, 0.026])
	for ring: Array in rings:
		var loop := PackedVector3Array()
		for i in 25:
			var a := TAU * i / 24.0
			var c: Vector2 = ring[0] + Vector2(cos(a), sin(a)) * float(ring[1])
			loop.append(Vector3(c.x, c.y, 0.04))
		_sweep_rib(tracery, loop, ring[2])
	tracery.generate_normals(); _commit_mesh(tracery, mat("rib"), "OculusTracery")
	_build_tyndall_beam(self, Vector3(0.0, 0.0, 0.08), Vector3(0.0, -0.40, 1.0).normalized(),
		0.46, 0.92, 4.6, beam_tex, Color("6c92c9"), Vector4(0.0, 0.0, 1.0, 1.0), 0.26, "OculusBeam")
	_build_glass_glow_quad(self, Vector3(0.0, 0.0, 0.11), Vector3(1.75, 0.0, 0.0), Vector3(0.0, 1.75, 0.0), Vector3.BACK,
		beam_tex, Color("7ba8e8"), Vector4(0.0, 0.0, 1.0, 1.0), 0.28, 1.0, "OculusHalo")
