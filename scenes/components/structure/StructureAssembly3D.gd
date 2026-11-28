@tool
class_name StructureAssembly3D
extends "res://scenes/components/structure/StructurePiece3D.gd"
## Several structure pieces combined into one: the members are ordinary authored children
## (walls, columns, arches, furniture…), and selected member properties are exposed as this
## node's own parameters in the Inspector ("参数/<name>"). Setting a parameter writes every
## bound member property, so one value can drive many pieces (e.g. a shared height).
## Save the assembly as its own .tscn to reuse it; instances keep their own parameter values.
##
## bindings: {param name: PackedStringArray["Member/Path:property", ...]}
## values:   {param name: value}   (what the Inspector edits; applied on load)

@export var bindings: Dictionary = {}:
	set(v): bindings = v; notify_property_list_changed()
@export var values: Dictionary = {}

const PREFIX := "参数/"

func plan_kind() -> String:
	return "assembly"

func _ready() -> void:
	apply_all()
	super._ready()

## Union of the members' plan outlines (bounding rectangle).
func plan_outline() -> PackedVector2Array:
	var box := Rect2()
	var first := true
	for m in members():
		var r: Rect2 = m.plan_bounds() if m.has_method("plan_bounds") else Rect2(_plan_of(m), Vector2.ZERO)
		box = r if first else box.merge(r)
		first = false
	if first:
		var c := to_plan(Vector3.ZERO)
		box = Rect2(c - Vector2.ONE * 0.5, Vector2.ONE)
	return PackedVector2Array([box.position, Vector2(box.end.x, box.position.y), box.end, Vector2(box.position.x, box.end.y)])

func members() -> Array:
	return get_children().filter(func(n): return n is Node3D and not is_generated(n))

func _plan_of(n: Node3D) -> Vector2:
	var xf := to_scope() * transform.affine_inverse() * n.transform
	return Vector2(xf.origin.x, xf.origin.z)

## This assembly as a reusable scene: its authored members (not generated meshes), with the
## current parameter values, at the origin.
func to_packed_scene() -> PackedScene:
	var copy: Node3D = duplicate(Node.DUPLICATE_SIGNALS | Node.DUPLICATE_GROUPS | Node.DUPLICATE_SCRIPTS)
	copy.transform = Transform3D.IDENTITY
	_own_copy(copy, copy, self)
	var packed := PackedScene.new()
	var err := packed.pack(copy)
	copy.free()
	return packed if err == OK else null

static func _own_copy(node: Node, new_root: Node, source: Node) -> void:
	for i in mini(node.get_child_count(), source.get_child_count()):
		var original := source.get_child(i)
		if original.owner == null or original.has_meta(GENERATED_META):
			continue
		node.get_child(i).owner = new_root
		_own_copy(node.get_child(i), new_root, original)

# ── exposed parameters ────────────────────────────────────────────────────────

## Expose `member_path:property` as parameter `param` (adds to an existing parameter).
func expose(param: String, member_path: String, property: String) -> void:
	var list: PackedStringArray = bindings.get(param, PackedStringArray())
	var key := "%s:%s" % [member_path, property]
	if key not in list:
		list.append(key)
	var next := bindings.duplicate()
	next[param] = list
	bindings = next
	if not values.has(param):
		var node := get_node_or_null(member_path)
		if node != null:
			values[param] = node.get(property)
	notify_property_list_changed()

func unexpose(param: String) -> void:
	var next := bindings.duplicate()
	next.erase(param)
	values.erase(param)
	bindings = next

func set_param(param: String, value: Variant) -> void:
	values[param] = value
	_apply(param)

func get_param(param: String) -> Variant:
	return values.get(param)

func apply_all() -> void:
	for param in bindings:
		_apply(param)

func _apply(param: String) -> void:
	if not values.has(param):
		return
	for target: String in bindings.get(param, PackedStringArray()):
		var node := get_node_or_null(target.get_slice(":", 0))
		var prop := target.get_slice(":", 1)
		if node != null and prop != "":
			node.set(prop, values[param])

func _get_property_list() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for param in bindings:
		var sample = values.get(param)
		if sample == null:
			for target: String in bindings[param]:
				var node := get_node_or_null(target.get_slice(":", 0))
				if node != null:
					sample = node.get(target.get_slice(":", 1))
					break
		out.append({"name": PREFIX + str(param), "type": typeof(sample) if sample != null else TYPE_FLOAT, "usage": PROPERTY_USAGE_EDITOR})
	return out

func _set(property: StringName, value: Variant) -> bool:
	if str(property).begins_with(PREFIX):
		set_param(str(property).trim_prefix(PREFIX), value)
		return true
	return false

func _get(property: StringName) -> Variant:
	if str(property).begins_with(PREFIX):
		return values.get(str(property).trim_prefix(PREFIX))
	return null
