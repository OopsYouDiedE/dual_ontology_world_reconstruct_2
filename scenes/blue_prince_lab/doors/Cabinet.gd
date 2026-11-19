extends "res://scenes/blue_prince_lab/doors/HingedJoinery.gd"
## Centered on x/z with ground origin. Front +Z, both leaves swing outward.

const WIDTH := 1.02
const HEIGHT := 1.19
const DEPTH := 0.48

func _ready() -> void:
	var case_mat := finish("4c3730")
	var timber := finish("665044")
	var edge := finish("866c56")
	var recess := finish("352a25")
	var brass := finish("ad874a", 0.73)
	var carcass := fixed_body()
	_board(carcass, Vector3(WIDTH, 0.049, DEPTH), Vector3(0, 1.1655, 0), timber)
	_board(carcass, Vector3(0.984, 0.023, 0.45), Vector3(0, 1.129, -0.007), edge)
	_board(carcass, Vector3(0.976, 0.085, 0.442), Vector3(0, 0.0425, -0.011), case_mat)
	_board(carcass, Vector3(0.968, 1.03, 0.03), Vector3(0, 0.60, -0.215), case_mat)
	for side in [-1.0, 1.0]:
		_board(carcass, Vector3(0.047, 1.03, 0.425), Vector3(side * 0.46, 0.60, -0.0025), case_mat)
		block(carcass, Vector3(0.018, 0.97, 0.014), Vector3(side * 0.47, 0.61, 0.212), edge)
	for y in [0.11, 0.57]:
		_board(carcass, Vector3(0.88, 0.028, 0.38), Vector3(0, y, -0.015), timber)
	for side in [-1.0, 1.0]:
		var leaf := hinge("LeftLeaf" if side < 0.0 else "RightLeaf", Vector3(side * 0.442, 0.10, 0.237), side * 105.0)
		var cx: float = -side * 0.217
		var center := Vector3(cx, 0.50, -0.021)
		block(leaf, Vector3(0.434, 1.00, 0.038), center, timber)
		shape(leaf, Vector3(0.434, 1.00, 0.065), center + Vector3(0, 0, 0.01))
		panel(leaf, Vector3(cx, 0.68, -0.002), 0.32, 0.49, 1.0, recess, edge, case_mat)
		panel(leaf, Vector3(cx, 0.24, -0.002), 0.32, 0.30, 1.0, recess, edge, case_mat)
		knob(leaf, Vector3(-side * 0.387, 0.53, 0), 1.0, brass)
		shape(leaf, Vector3(0.05, 0.05, 0.05), Vector3(-side * 0.387, 0.545, 0.025))
		for y in [0.16, 0.84]:
			pin(leaf, Vector3(0, y, 0.006), 0.009, 0.069, brass)

func _board(body: PhysicsBody3D, size: Vector3, at: Vector3, mat: Material) -> void:
	block(body, size, at, mat)
	shape(body, size, at)
