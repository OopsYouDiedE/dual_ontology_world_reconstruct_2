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

## Catalog metadata identifies the live implementation; the public component
## path keeps the node type and serialized scene contract stable.
static func create_entry(entry: Dictionary, overrides: Dictionary = {}) -> Node3D:
	var instance := create(str(entry.path))
	if instance == null: return null
	var production: Dictionary = entry.get("production", {})
	if not production.is_empty() and "recipe_module" in instance:
		instance.set("recipe_module", str(production.generator))
	var parameters: Dictionary = entry.get("defaults", {}).duplicate(true)
	parameters.merge(overrides.duplicate(true), true)
	for key in parameters:
		instance.set(key, parameters[key])
	return instance

static func production_note(entry: Dictionary) -> String:
	var production: Dictionary = entry.get("production", {})
	return "Production: %s\n%s" % [production.get("kind", "assembly"), production.get("generator", entry.path)]

## Defaults for the JSON/YAML authoring inspector, sourced from the same recipe
## instance that will generate the model. Catalog overrides take precedence.
static func parameter_defaults(entry: Dictionary) -> Dictionary:
	var parameters: Dictionary = entry.get("defaults", {}).duplicate(true)
	var instance := create(str(entry.path))
	if instance == null: return parameters
	if "recipe_parameters" in instance:
		var declared: Dictionary = instance.get("recipe_parameters").duplicate(true)
		declared.merge(parameters, true)
		parameters = declared
	instance.free()
	return parameters
