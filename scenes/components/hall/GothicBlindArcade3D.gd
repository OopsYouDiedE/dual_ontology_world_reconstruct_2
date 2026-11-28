@tool
class_name GothicBlindArcade3D
extends GothicHallPiece3D
## Row of shallow pointed arches on slender shafts between two stringcourses.
## Runs along local X (centred) and projects toward local +Z (the room side): rotate the
## node to put it on any wall.

@export var length := 8.0:
	set(v): length = v; shape_changed()
@export var bottom := 3.30:
	set(v): bottom = v; changed()
@export var top := 4.15:
	set(v): top = v; changed()
@export_range(1, 32) var count := 8:
	set(v): count = v; changed()

func shape_key() -> Array: return [length]
func plan_outline() -> PackedVector2Array: return _rect_outline(Rect2(-length * 0.5, 0, length, 0.25))

func _strip(holder: Node3D, center: Vector3, along: Vector3, inward: Vector3, l: float, height: float, depth: float, m: Material) -> void:
	_box(holder, center, along.abs() * l + inward.abs() * depth + Vector3(0, height, 0), m)

func _build() -> void:
	# Built in structure axes (the arcade runs along +X or +Z there, projecting toward the
	# room), then held in a child that undoes this node's rotation: rotate the node to put
	# the arcade on any wall and the tracery is identical on every wall.
	var basis := to_scope().basis.orthonormalized()
	var holder := Node3D.new()
	holder.basis = basis.inverse()
	add_child(holder)
	var world_x := basis * Vector3.RIGHT
	var along := Vector3(absf(world_x.x), 0, absf(world_x.z)).round()
	var inward := (basis * Vector3.BACK).round()
	var center := Vector3.ZERO
	var y0 := bottom
	var y1 := top
	_strip(holder, Vector3(center.x, y0, center.z) + inward * 0.08, along, inward, length, 0.10, 0.16, mat("rib"))
	_strip(holder, Vector3(center.x, y1 + 0.05, center.z) + inward * 0.08, along, inward, length, 0.10, 0.17, mat("rib"))
	var bay := length / float(count)
	var spring := y0 + (y1 - y0) * 0.55
	var rise := y1 - 0.06 - spring
	var arches := SurfaceTool.new(); arches.begin(Mesh.PRIMITIVE_TRIANGLES)
	var recess := SurfaceTool.new(); recess.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in count + 1:
		var shaft := center + along * (-length * 0.5 + bay * float(i))
		_strip(holder, Vector3(shaft.x, (y0 + spring) * 0.5, shaft.z) + inward * 0.07, along, inward, 0.07, spring - y0, 0.10, mat("rib"))
	for i in count:
		var mid := center + along * (-length * 0.5 + bay * (float(i) + 0.5))
		var hw := bay * 0.5 - 0.05
		var curve := PackedVector3Array()
		for k in 13:
			var u := (k - 6.0) / 6.0
			curve.append(mid + along * (u * hw) + inward * 0.09 + Vector3(0, spring + rise * pointed_arch_y(u) / CROWN_RISE, 0))
		_sweep_rib(arches, curve, 0.034)
		for k in range(1, curve.size()):
			var a := curve[k - 1] - inward * 0.065
			var b := curve[k] - inward * 0.065
			var a0 := Vector3(a.x, y0 + 0.05, a.z)
			var b0 := Vector3(b.x, y0 + 0.05, b.z)
			_add_quad(recess, a0, a, b, b0); _add_quad(recess, b0, b, a, a0)
	arches.generate_normals(); _commit_mesh(arches, mat("rib"), "BlindArcade", holder)
	recess.generate_normals(); _commit_mesh(recess, mat("vault"), "BlindArcadeField", holder)
