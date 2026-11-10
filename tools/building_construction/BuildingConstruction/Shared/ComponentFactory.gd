extends RefCounted
## The design application owns loading; component definitions are scripts.
const COMPONENT_ROOT := "res://tools/building_construction/BuildingConstruction/"

static func script_path(path: String) -> String:
	# Read existing design files that still refer to the former scene wrappers.
	if path.begins_with(COMPONENT_ROOT) and path.ends_with(".tscn"):
		return path.get_basename() + ".gd"
	return path

static func create(path: String) -> Node3D:
	var resolved := script_path(path)
	if not ResourceLoader.exists(resolved):
		push_error("找不到组件脚本：" + resolved)
		return null
	var definition := load(resolved) as Script
	if definition == null or not definition.can_instantiate() or not ClassDB.is_parent_class(definition.get_instance_base_type(), "Node3D"):
		push_error("组件必须是可实例化的 Node3D 脚本：" + resolved)
		return null
	var instance := definition.new() as Node3D
	instance.name = resolved.get_file().get_basename()
	return instance
