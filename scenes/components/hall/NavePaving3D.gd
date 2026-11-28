@tool
class_name NavePaving3D
extends GothicHallPiece3D
## Pale stone bands across the nave floor at every pier plus two edge borders; bands
## stop short of `gap` (the pendulum dial), given in local XZ.

@export var size := Vector2(8.82, 20.0):
	set(v): size = v; shape_changed()
@export_range(1, 12) var bays := 5:
	set(v): bays = v; changed()
@export var gap := Rect2():
	set(v): gap = v; changed()

func shape_key() -> Array: return [size]
func plan_outline() -> PackedVector2Array: return _rect_outline(Rect2(Vector2.ZERO, size))

func _build() -> void:
	var x0 := 0.0
	var x1 := size.x
	var min_z := 0.0
	var bay_len := size.y / float(bays)
	var max_z := min_z + bays * bay_len
	for edge: float in [x0 + 0.36, x1 - 0.36]:
		_box(self, Vector3(edge, 0.004, (min_z + max_z) * 0.5), Vector3(0.18, 0.008, max_z - min_z), mat("rib"))
	for iz in range(bays + 1):
		var z := clampf(min_z + iz * bay_len, min_z + 0.12, max_z - 0.12)
		var spans := [Vector2(x0, x1)]
		if gap.has_area() and z > gap.position.y - 0.3 and z < gap.end.y + 0.3:
			spans = [Vector2(x0, gap.position.x - 0.3), Vector2(gap.end.x + 0.3, x1)]
		for s: Vector2 in spans:
			_box(self, Vector3((s.x + s.y) * 0.5, 0.004, z), Vector3(s.y - s.x, 0.008, 0.2), mat("rib"))
