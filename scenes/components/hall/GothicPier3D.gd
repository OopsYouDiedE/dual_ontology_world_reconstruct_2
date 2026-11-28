@tool
class_name GothicPier3D
extends GothicHallPiece3D
## Clustered Gothic pier: plinth, shaft, three engaged colonnettes facing `inward`, stepped capital.

## +1 = colonnettes face +X (west wall), -1 = face -X (east wall).
@export var inward := 1.0:
	set(v): inward = v; changed()

func plan_outline() -> PackedVector2Array: return _rect_outline(Rect2(-0.4, -0.36, 0.8, 0.72))

func _build() -> void:
	var pier := Node3D.new()
	pier.scale = Vector3(1.48, 1, 1.34)
	add_child(pier)
	_box(pier, Vector3(0.0, 0.14, 0.0), Vector3(0.54, 0.28, 0.54), mat("plinth"))
	_box(pier, Vector3(0.0, 0.34, 0.0), Vector3(0.44, 0.14, 0.44), mat("rib"))
	_box(pier, Vector3(0.0, SPRING_H * 0.5, 0.0), Vector3(0.30, SPRING_H - 0.30, 0.32), mat("wall"))
	for dz in [-0.14, 0.0, 0.14]:
		var cyl := MeshInstance3D.new()
		var cm := CylinderMesh.new()
		cm.top_radius = 0.065; cm.bottom_radius = 0.065; cm.height = SPRING_H - 0.52; cm.radial_segments = 10
		cyl.mesh = cm
		cyl.position = Vector3(inward * 0.16, SPRING_H * 0.5, dz)
		cyl.material_override = mat("rib")
		pier.add_child(cyl)
		for ring: Array in [[0.098, 0.12, 0.47], [0.082, 0.05, SPRING_H - 0.36]]:
			var band := MeshInstance3D.new()
			var bm := CylinderMesh.new()
			bm.top_radius = ring[0]; bm.bottom_radius = ring[0] * 1.08; bm.height = ring[1]; bm.radial_segments = 10
			band.mesh = bm
			band.position = Vector3(inward * 0.16, ring[2], dz)
			band.material_override = mat("rib")
			pier.add_child(band)
	_box(pier, Vector3(inward * 0.04, SPRING_H - 0.26, 0.0), Vector3(0.40, 0.10, 0.42), mat("rib"))
	_box(pier, Vector3(inward * 0.06, SPRING_H - 0.15, 0.0), Vector3(0.48, 0.11, 0.50), mat("rib"))
	_box(pier, Vector3(inward * 0.08, SPRING_H - 0.05, 0.0), Vector3(0.56, 0.10, 0.58), mat("rib"))
