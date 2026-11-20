extends "res://scenes/blue_prince_lab/doors/HingedJoinery.gd"
## Ground x=0, opening plane z=0, front +Z. Left-hand leaf opens toward +Z.

const OPENING_WIDTH := 1.45
const OPENING_HEIGHT := 2.60
const LEAF_WIDTH := 1.426
const LEAF_HEIGHT := 2.568

@export var hall_finish := false

func _ready() -> void:
	var frame := finish("535e63" if hall_finish else "354250")
	var trim := finish("8b9498" if hall_finish else "586777")
	var wood := finish("7c878b" if hall_finish else "405266")
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
		if hall_finish and face > 0.0:
			_carved_fields(leaf)
		else:
			for x in [0.425, 1.001]:
				panel(leaf, Vector3(x, 1.83, -0.037 + face * 0.032), 0.52, 1.11, face, recess, edge, field)
				panel(leaf, Vector3(x, 0.54, -0.037 + face * 0.032), 0.52, 0.77, face, recess, edge, field)
		knob(leaf, Vector3(1.346, 1.075, -0.037 + face * 0.034), face, brass)
		shape(leaf, Vector3(0.05, 0.05, 0.05), Vector3(1.346, 1.09, -0.037 + face * 0.059))
	for y in [0.34, 1.37, 2.23]:
		pin(leaf, Vector3(0, y, 0.007), 0.013, 0.10, brass)


func _carved_fields(leaf: Node3D) -> void:
	# Raised paired fields. Their bevels and the exposed bed form the forked recess.
	var bevel := finish("748087")
	var stone := finish("aab4b8")
	for hand: float in [-1.0, 1.0]:
		var outline := PackedVector2Array([Vector2(.026,.13), Vector2(.63,.31), Vector2(.63,2.40), Vector2(.46,2.39), Vector2(.22,1.98), Vector2(.095,1.49), Vector2(.026,1.34)])
		var field_shape := PackedVector2Array([Vector2(.026,1.46), Vector2(.12,1.65), Vector2(.235,2.06), Vector2(.44,2.42), Vector2(.026,2.42)])
		for profile: PackedVector2Array in [outline,field_shape]:
			_carve_profile(leaf, profile, hand, stone, bevel)

func _carve_profile(leaf: Node3D, profile: PackedVector2Array, hand: float, stone: StandardMaterial3D, bevel: StandardMaterial3D) -> void:
	var center := Vector2.ZERO
	for v in profile: center += v
	center /= profile.size()
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var face_poly := PackedVector2Array()
	for v in profile: face_poly.append(Vector2(LEAF_WIDTH/2.0 + hand*v.x,v.y))
	var indices := Geometry2D.triangulate_polygon(face_poly)
	for k in indices: st.add_vertex(Vector3(face_poly[k].x,face_poly[k].y,.028))
	st.generate_normals()
	stone.cull_mode = BaseMaterial3D.CULL_DISABLED
	piece(leaf,st.commit(),Vector3.ZERO,stone)
	var rim := SurfaceTool.new()
	rim.begin(Mesh.PRIMITIVE_TRIANGLES)
	for k in profile.size():
		var j := (k+1)%profile.size()
		var u := face_poly[k]; var v := face_poly[j]
		var uk := (profile[k]-center).normalized()*.014; var vj := (profile[j]-center).normalized()*.014
		var a := Vector3(u.x,u.y,.028); var b := Vector3(v.x,v.y,.028)
		var c := Vector3(v.x+hand*vj.x,v.y+vj.y,-.002); var d := Vector3(u.x+hand*uk.x,u.y+uk.y,-.002)
		for vertex in [a,b,c,a,c,d]: rim.add_vertex(vertex)
	rim.generate_normals(); bevel.cull_mode = BaseMaterial3D.CULL_DISABLED
	piece(leaf,rim.commit(),Vector3.ZERO,bevel)
