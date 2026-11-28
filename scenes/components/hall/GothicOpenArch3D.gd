@tool
class_name GothicOpenArch3D
extends GothicHallPiece3D
## Open pointed arcade into a side wing: spandrel, archivolt, reveal soffit, returned jambs
## (whose cheeks reserve stations). Local origin = wall line at the bay start, runs along +Z.

@export var length := 4.0:
	set(v): length = v; shape_changed()
@export var inward := 1.0:
	set(v): inward = v; changed()

func shape_key() -> Array: return [length]
func plan_outline() -> PackedVector2Array: return _rect_outline(Rect2(-0.4, 0, 0.8, length))

func _build() -> void:
	var x := 0.0
	var z0 := 0.0
	var z1 := length
	var cz := (z0 + z1) * 0.5
	var trim := SurfaceTool.new(); trim.begin(Mesh.PRIMITIVE_TRIANGLES)
	var stone := SurfaceTool.new(); stone.begin(Mesh.PRIMITIVE_TRIANGLES)
	var pts := PackedVector3Array()
	for i in 25:
		var u := (i - 12.0) / 12.0
		var p := Vector3(x, ARCADE_SPRING + ARCADE_RISE * pointed_arch_y(u) / CROWN_RISE, cz + u * ((z1 - z0) * 0.5 - 0.42))
		if i > 0:
			var last := pts[i - 1]
			var top := Vector3(x, SPRING_H + 0.05, p.z)
			var prev := Vector3(x, top.y, last.z)
			_add_quad(stone, last, p, top, prev)
			_add_quad(stone, prev, top, p, last)
		pts.append(p)
	for end_sign: float in [-1, 1]:
		var edge := cz + end_sign * ((z1 - z0) * 0.5 - 0.42)
		var cheek := Vector3(x - inward * 0.13, SPRING_H * 0.5, edge + end_sign * 0.21)
		_box(self, cheek, Vector3(0.36, SPRING_H, 0.42), mat("wall"))
		_reserve_station(cheek * Vector3(1, 0, 1), Vector2(0.36, 0.42), SPRING_H)
		_box(self, Vector3(x + inward * 0.06, ARCADE_SPRING * 0.5, edge), Vector3(0.24, ARCADE_SPRING, 0.18), mat("rib"))
	var soffit := SurfaceTool.new(); soffit.begin(Mesh.PRIMITIVE_TRIANGLES)
	var depth := Vector3(-inward * 0.34, 0, 0)
	for i in range(1, pts.size()):
		var a := pts[i - 1]; var b := pts[i]
		_add_quad(soffit, a, b, b + depth, a + depth); _add_quad(soffit, a + depth, b + depth, b, a)
	soffit.generate_normals(); _commit_mesh(soffit, mat("wall"), "PassageReveal")
	_sweep_rib(trim, pts, 0.145)
	for i in pts.size(): pts[i] += Vector3(inward * 0.08, 0.15, 0)
	_sweep_rib(trim, pts, 0.07)
	trim.generate_normals(); stone.generate_normals()
	_commit_mesh(stone, mat("wall"), "ArcadeSpandrel")
	_commit_mesh(trim, mat("rib"), "OpenArchivolt")
