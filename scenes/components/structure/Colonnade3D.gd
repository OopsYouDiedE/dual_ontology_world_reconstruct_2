@tool
class_name Colonnade3D
extends "res://scenes/components/structure/StructurePiece3D.gd"
## A row of columns carrying arches, between two points: one node, a handful of exposed
## parameters, built from StructureColumn3D + StructureArch3D pieces (generated, rebuilt
## when a parameter changes). For a hand-arranged combination use StructureAssembly3D.

const Column := preload("res://scenes/components/structure/StructureColumn3D.gd")
const Arch := preload("res://scenes/components/structure/StructureArch3D.gd")

@export var start_point := Vector3.ZERO:
	set(v): start_point = v; shape_changed()
@export var end_point := Vector3(8, 0, 0):
	set(v): end_point = v; shape_changed()
@export_range(1, 64) var bays := 3:
	set(v): bays = maxi(1, v); mesh_changed()
@export_group("Columns")
@export var column_style: Column.Style = Column.Style.ROUND:
	set(v): column_style = v; mesh_changed()
@export_range(0.05, 2.0, 0.01) var column_radius := 0.22:
	set(v): column_radius = v; shape_changed()
@export_range(0.5, 30.0, 0.01) var column_height := 2.6:
	set(v): column_height = v; mesh_changed()
@export_group("Arches")
@export var arch_profile: Arch.Profile = Arch.Profile.POINTED:
	set(v): arch_profile = v; mesh_changed()
## Rise as a fraction of the bay span (0.5 with ROUND = semicircle).
@export_range(0.0, 2.0, 0.01) var rise_ratio := 0.55:
	set(v): rise_ratio = v; mesh_changed()
@export_range(0.05, 2.0, 0.01) var band := 0.28:
	set(v): band = v; mesh_changed()
@export_range(0.05, 3.0, 0.01) var depth := 0.4:
	set(v): depth = v; shape_changed()
## Spandrel fill height above the floor (0 = open arcade).
@export_range(0.0, 40.0, 0.01) var fill_to := 0.0:
	set(v): fill_to = v; mesh_changed()
@export_group("")
@export var material_key := "rib":
	set(v): material_key = v; mesh_changed()

func plan_kind() -> String:
	return "assembly"

func shape_key() -> Array:
	return [start_point, end_point, column_radius, depth]

func neighbor_margin() -> float:
	return maxf(depth * 0.5, column_radius) + 0.05

func plan_outline() -> PackedVector2Array:
	var a := to_plan(start_point)
	var b := to_plan(end_point)
	var side := (b - a).orthogonal().normalized() * maxf(depth * 0.5, column_radius)
	return PackedVector2Array([a + side, b + side, b - side, a - side])

func plan_handles() -> Array:
	return [{"id": &"start", "position": to_plan(start_point)}, {"id": &"end", "position": to_plan(end_point)}]

func set_plan_handle(id: StringName, plan_position: Vector2) -> void:
	match id:
		&"start": start_point = from_plan(plan_position, start_point.y)
		&"end": end_point = from_plan(plan_position, end_point.y)

func snap_targets() -> PackedVector2Array:
	var out := PackedVector2Array()
	for i in bays + 1:
		out.append(to_plan(start_point.lerp(end_point, float(i) / float(bays))))
	return out

func rebuild() -> void:
	for child in get_children():
		if is_generated(child):
			remove_child(child)
			child.queue_free()
	if start_point.distance_to(end_point) < 0.1:
		return
	var bay := start_point.distance_to(end_point) / float(bays)
	var dir := (end_point - start_point).normalized()
	for i in bays + 1:
		var c: Node3D = Column.new()
		c.set_meta(GENERATED_META, true)
		c.name = "Column%d" % i
		c.style = column_style
		c.radius = column_radius
		c.height = column_height
		c.material_key = material_key
		c.position = start_point.lerp(end_point, float(i) / float(bays))
		add_child(c)
	for i in bays:
		var a: Node3D = Arch.new()
		a.set_meta(GENERATED_META, true)
		a.name = "Arch%d" % i
		# The arch springs from the column faces.
		a.start_point = start_point.lerp(end_point, float(i) / float(bays)) + dir * column_radius
		a.end_point = start_point.lerp(end_point, float(i + 1) / float(bays)) - dir * column_radius
		a.profile = arch_profile
		a.spring_height = column_height
		a.rise = maxf(0.0, bay - column_radius * 2.0) * rise_ratio
		a.band = band
		a.depth = depth
		a.jambs = false
		a.fill_to = fill_to
		a.material_key = material_key
		add_child(a)
