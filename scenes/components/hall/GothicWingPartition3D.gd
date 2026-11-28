@tool
class_name GothicWingPartition3D
extends GothicHallPiece3D
## Cross wall splitting a side wing into two rooms, with a pointed passage facing the nave.
## Local origin = wing centre on the partition line (runs along X); `side` = -1 west, +1 east.

@export var side := -1:
	set(v): side = v; changed()

func _build() -> void:
	var cx := 0.0
	var wall_x := cx + 1.5 * side
	_box(self, Vector3(wall_x, WING_ROOF * 0.5, 0), Vector3(2, WING_ROOF, 0.17), mat("wall"))
	_box(self, Vector3(wall_x, 0.54, 0), Vector3(2, 1.08, 0.24), mat("wood"))
	var opening := cx - side
	var curve := PackedVector3Array()
	var web := SurfaceTool.new(); web.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in 25:
		var u := (i - 12.0) / 12.0
		var pt := Vector3(opening + 1.5 * u, WING_SPRING + 1.52 * pointed_arch_y(u) / CROWN_RISE, 0)
		if i > 0:
			var last := curve[i - 1]; var a := Vector3(last.x, WING_ROOF, 0); var b := Vector3(pt.x, WING_ROOF, 0)
			_add_quad(web, last, a, b, pt); _add_quad(web, pt, b, a, last)
		curve.append(pt)
	web.generate_normals(); _commit_mesh(web, mat("wall"), "WingDoorHead")
	var bead := SurfaceTool.new(); bead.begin(Mesh.PRIMITIVE_TRIANGLES); _sweep_rib(bead, curve, 0.10)
	bead.generate_normals(); _commit_mesh(bead, mat("rib"), "WingArchivolt")
	for dx: float in [-1.5, 1.5]: _box(self, Vector3(opening + dx, WING_SPRING * 0.5, 0), Vector3(0.19, WING_SPRING, 0.23), mat("rib"))
