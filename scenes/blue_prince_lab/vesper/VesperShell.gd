extends "res://scenes/blue_prince_lab/HallShell.gd"
## Reuse the hall mouldings and real wall apertures. Open a well through both floor skins.
func _build_subfloor() -> void:
	for limits: Vector2 in [Vector2(-9.66,-4), Vector2(-1,8.88)]:
		var mid := (limits.x + limits.y) * .5
		_solid(Vector3(0,-.60,mid), Vector3(9.78,1.20,limits.y-limits.x),"grout")
	_solid(Vector3(0,-3.5,-2.5),Vector3(9.78,.4,3.0),"reveal")

func _build_floor() -> void:
	for limits: Vector2 in [Vector2(-9.24,-4),Vector2(-1,8.85)]:
		var depth := (limits.y-limits.x)/4.
		for i in 4:
			var z := limits.x + (i+.5)*depth
			for j in 4:
				_box(Vector3((j-1.5)*2.39,-.009,z),Vector3(2.37,.034,depth-.018),"floor_b" if (i+j)%2 else "floor_a")
		_box(Vector3(0,.023,(limits.x+limits.y)*.5),Vector3(1.86,.022,limits.y-limits.x),"carpet")
	for z: float in [-.95,-4.05]:
		_box(Vector3(0,-.06,z),Vector3(9.54,.18,.12),"ivory")
