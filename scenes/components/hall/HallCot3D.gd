@tool
class_name HallCot3D
extends GothicHallPiece3D
## Folding canvas camp cot (the watchman's cot). Reserves its footprint.

func plan_outline() -> PackedVector2Array: return _rect_outline(Rect2(-0.97, -0.4, 1.94, 0.8))

func _build() -> void:
	var cot := self
	var canvas := mat("canvas")
	_box(cot, Vector3(0, 0.49, 0), Vector3(1.87, 0.065, 0.72), canvas)
	_box(cot, Vector3(-0.63, 0.55, 0), Vector3(0.35, 0.07, 0.54), canvas)
	for dz: float in [-0.38, 0.38]:
		_box(cot, Vector3(0, 0.49, dz), Vector3(1.99, 0.056, 0.056), mat("wood"))
	for dx: float in [-0.69, 0.69]:
		for sign_z: float in [-1, 1]:
			var axle := Node3D.new(); axle.position = Vector3(dx, 0.25, 0); axle.rotation.x = sign_z * 0.98; cot.add_child(axle)
			_box(axle, Vector3.ZERO, Vector3(0.055, 0.91, 0.055), mat("wood"))
	_reserve_station(Vector3.ZERO, Vector2(1.94, 0.8), 0.48)
