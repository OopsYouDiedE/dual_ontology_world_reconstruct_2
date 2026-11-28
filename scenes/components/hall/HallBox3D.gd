@tool
class_name HallBox3D
extends GothicHallPiece3D
## A plain block of hall material (walls of the side wings, roofs, ribs, trims, embers…).
## Size it in the Inspector; centred on the node.

@export var size := Vector3(1, 1, 1):
	set(v): size = v; shape_changed()
@export_enum("wall", "rib", "vault", "plinth", "wood", "runner", "lead", "brass", "canvas", "embers") var material_key := "wall":
	set(v): material_key = v; changed()

func shape_key() -> Array: return [size]
func plan_outline() -> PackedVector2Array: return _rect_outline(Rect2(-size.x * 0.5, -size.z * 0.5, size.x, size.z))

func _build() -> void:
	_box(self, Vector3.ZERO, size, mat(material_key))
