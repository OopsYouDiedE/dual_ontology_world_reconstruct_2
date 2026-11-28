@tool
class_name HallRug3D
extends GothicHallPiece3D
## Floor runner / carpet strip (centred on the node, runs along local Z) with two thin
## edge strips (walnut hems or brass bands).

@export var size := Vector2(1.18, 20.0):
	set(v): size = v; shape_changed()
@export var center_height := 0.012:
	set(v): center_height = v; changed()
@export var thickness := 0.016:
	set(v): thickness = v; changed()
@export_enum("runner", "wood", "brass", "rib") var material_key := "runner":
	set(v): material_key = v; changed()
## Edge strips at ±edge_offset from the centre line (0 = none).
@export var edge_offset := 0.56:
	set(v): edge_offset = v; changed()
## Edge strip width (x) and thickness (y).
@export var edge_size := Vector2(0.022, 0.004):
	set(v): edge_size = v; changed()
@export var edge_height := 0.022:
	set(v): edge_height = v; changed()
@export_enum("wood", "brass", "rib", "runner") var edge_material := "wood":
	set(v): edge_material = v; changed()

func shape_key() -> Array: return [size]
func plan_outline() -> PackedVector2Array: return _rect_outline(Rect2(-size * 0.5, size))

func _build() -> void:
	_box(self, Vector3(0, center_height, 0), Vector3(size.x, thickness, size.y), mat(material_key))
	if edge_offset > 0.0:
		for side: float in [-edge_offset, edge_offset]:
			_box(self, Vector3(side, edge_height, 0), Vector3(edge_size.x, edge_size.y, size.y), mat(edge_material))
