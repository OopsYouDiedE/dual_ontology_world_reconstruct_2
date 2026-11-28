@tool
class_name StructureColumn3D
extends "res://scenes/components/structure/StructurePiece3D.gd"
## A free-standing column: plinth, shaft and capital, with a collider. Its centre is a snap
## point for walls, arches and other columns. Drag the radius handle (3D or plan tab),
## or tune everything in the Inspector.

const Hall := preload("res://scenes/components/hall/GothicHallPiece3D.gd")

enum Style { ROUND, SQUARE, OCTAGONAL, CLUSTERED }

@export var style: Style = Style.ROUND:
	set(v): style = v; shape_changed()
@export_range(0.05, 3.0, 0.01) var radius := 0.25:
	set(v): radius = maxf(0.05, v); shape_changed()
@export_range(0.2, 40.0, 0.01) var height := 3.0:
	set(v): height = maxf(0.2, v); mesh_changed()
@export_range(0.0, 2.0, 0.01) var base_height := 0.25:
	set(v): base_height = v; mesh_changed()
@export_range(0.0, 2.0, 0.01) var capital_height := 0.22:
	set(v): capital_height = v; mesh_changed()
## Shared palette key (wall, rib, vault, plinth, wood, brass, lead…) unless `material` is set.
@export var material_key := "rib":
	set(v): material_key = v; mesh_changed()
@export var material: Material:
	set(v): material = v; mesh_changed()
@export var collision := true:
	set(v): collision = v; mesh_changed()

func plan_kind() -> String:
	return "column"

func shape_key() -> Array:
	return [style, radius]

func plan_outline() -> PackedVector2Array:
	var out := PackedVector2Array()
	var sides := 4 if style == Style.SQUARE else (8 if style == Style.OCTAGONAL else 12)
	var r := _footprint_radius()
	for i in sides:
		var a := TAU * (float(i) + (0.5 if style == Style.SQUARE else 0.0)) / float(sides)
		out.append(to_plan(Vector3(cos(a) * r, 0, sin(a) * r)))
	return out

func plan_handles() -> Array:
	return [{"id": &"radius", "position": to_plan(Vector3(radius, 0, 0))}]

func set_plan_handle(_id: StringName, plan_position: Vector2) -> void:
	radius = snappedf(maxf(0.05, to_plan(Vector3.ZERO).distance_to(plan_position)), 0.01)

func snap_targets() -> PackedVector2Array:
	return PackedVector2Array([to_plan(Vector3.ZERO)])

func _footprint_radius() -> float:
	var r := radius * (1.25 if base_height > 0.0 else 1.0)
	return r * (1.4142 if style == Style.SQUARE else 1.0)

func _mat() -> Material:
	return material if material != null else Hall.mat(material_key)

func rebuild() -> void:
	for child in get_children():
		if is_generated(child):
			remove_child(child)
			child.queue_free()
	var m := _mat()
	var shaft_h := maxf(0.05, height - base_height - capital_height)
	if base_height > 0.0:
		_part(_solid(radius * 1.25, base_height, 1.0), Vector3(0, base_height * 0.5, 0), m, "Base")
	match style:
		Style.CLUSTERED:
			_part(_solid(radius * 0.62, shaft_h, 1.0), Vector3(0, base_height + shaft_h * 0.5, 0), m, "Core")
			for i in 4:
				var a := TAU * float(i) / 4.0 + PI * 0.25
				_part(_solid(radius * 0.36, shaft_h, 1.0), Vector3(cos(a) * radius * 0.62, base_height + shaft_h * 0.5, sin(a) * radius * 0.62), m, "Shaft%d" % i)
		_:
			_part(_solid(radius, shaft_h, 0.96), Vector3(0, base_height + shaft_h * 0.5, 0), m, "Shaft")
	if capital_height > 0.0:
		_part(_solid(radius * 1.32, capital_height, 0.78), Vector3(0, height - capital_height * 0.5, 0), m, "Capital")
	if collision:
		var body := StaticBody3D.new()
		body.name = "Collision"
		var col := CollisionShape3D.new()
		if style == Style.SQUARE:
			var box := BoxShape3D.new()
			box.size = Vector3(radius * 2.0, height, radius * 2.0)
			col.shape = box
		else:
			var cyl := CylinderShape3D.new()
			cyl.radius = radius
			cyl.height = height
			col.shape = cyl
		col.position = Vector3(0, height * 0.5, 0)
		body.add_child(col)
		add_child(body)

## Cylinder/prism of the column style; `taper` narrows the top (capital flare uses < 1).
func _solid(r: float, h: float, taper: float) -> Mesh:
	if style == Style.SQUARE:
		var box := BoxMesh.new()
		box.size = Vector3(r * 2.0, h, r * 2.0)
		return box
	var cyl := CylinderMesh.new()
	cyl.bottom_radius = r * (taper if taper < 1.0 and h < 0.5 else 1.0)
	cyl.top_radius = r * (1.0 if taper < 1.0 and h < 0.5 else taper)
	cyl.height = h
	cyl.radial_segments = 8 if style == Style.OCTAGONAL else 20
	cyl.rings = 1
	return cyl

func _part(mesh: Mesh, pos: Vector3, m: Material, part_name: String) -> void:
	var mi := MeshInstance3D.new()
	mi.name = part_name
	mi.mesh = mesh
	mi.material_override = m
	mi.position = pos
	add_child(mi)
