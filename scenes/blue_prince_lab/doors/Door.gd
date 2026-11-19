extends "res://scenes/blue_prince_lab/doors/HingedJoinery.gd"
## Ground x=0, opening plane z=0, front +Z. Left-hand leaf opens toward +Z.

const OPENING_WIDTH := 1.45
const OPENING_HEIGHT := 2.60
const LEAF_WIDTH := 1.426
const LEAF_HEIGHT := 2.568

func _ready() -> void:
	var frame := finish("354250")
	var trim := finish("586777")
	var wood := finish("405266")
	var recess := finish("263647")
	var edge := finish("63768a")
	var field := finish("495f73")
	var brass := finish("b39353", 0.72)
	var jamb := fixed_body()
	for side in [-1.0, 1.0]:
		var x: float = side * (OPENING_WIDTH / 2.0 + 0.0425)
		var at := Vector3(x, OPENING_HEIGHT / 2.0, 0)
		var size := Vector3(0.085, OPENING_HEIGHT, 0.19)
		block(jamb, size, at, frame)
		shape(jamb, size, at)
		for face in [-1.0, 1.0]:
			block(jamb, Vector3(0.046, 2.6, 0.022), Vector3(x, 1.3, face * 0.1), trim)
			block(jamb, Vector3(0.08, 0.19, 0.034), Vector3(x, 0.095, face * 0.106), frame)
	var header := Vector3(0, 2.65, 0)
	var header_size := Vector3(1.62, 0.10, 0.19)
	block(jamb, header_size, header, frame)
	shape(jamb, header_size, header)
	for face in [-1.0, 1.0]:
		block(jamb, Vector3(1.66, 0.044, 0.041), Vector3(0, 2.674, face * 0.105), trim)
	var leaf := hinge("RoomLeaf", Vector3(-0.713, 0.015, 0.037), -90.0)
	block(leaf, Vector3(LEAF_WIDTH, LEAF_HEIGHT, 0.064), Vector3(LEAF_WIDTH / 2, LEAF_HEIGHT / 2, -0.037), wood)
	shape(leaf, Vector3(LEAF_WIDTH, LEAF_HEIGHT, 0.108), Vector3(LEAF_WIDTH / 2, LEAF_HEIGHT / 2, -0.037))
	for face in [-1.0, 1.0]:
		for x in [0.425, 1.001]:
			panel(leaf, Vector3(x, 1.83, -0.037 + face * 0.032), 0.52, 1.11, face, recess, edge, field)
			panel(leaf, Vector3(x, 0.54, -0.037 + face * 0.032), 0.52, 0.77, face, recess, edge, field)
		knob(leaf, Vector3(1.346, 1.075, -0.037 + face * 0.034), face, brass)
		shape(leaf, Vector3(0.05, 0.05, 0.05), Vector3(1.346, 1.09, -0.037 + face * 0.059))
	for y in [0.34, 1.37, 2.23]:
		pin(leaf, Vector3(0, y, 0.007), 0.013, 0.10, brass)
