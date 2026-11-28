extends RefCounted
## The design application owns loading; component definitions are scripts.
const COMPONENT_ROOT := "res://tools/building_construction/BuildingConstruction/"
const CATALOG_PATH := "res://tools/building_construction/catalog.json"
const Interactable := preload("res://scenes/components/interaction/AcademyInteractable.gd")

## The one catalog loader shared by ArchBuilder (BuildingSimulator), the Component Library
## (item property tool) and the editor dock. Optional entries whose script is absent from
## this checkout are dropped here, so no tool can offer an item that fails to instantiate.
static func load_catalog(path := CATALOG_PATH) -> Dictionary:
	if not FileAccess.file_exists(path):
		push_error("Could not open the building catalog: " + path)
		return {}
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not parsed is Dictionary or not parsed.has("items"):
		push_error("Invalid building catalog: " + path)
		return {}
	var catalog: Dictionary = parsed
	catalog.items = (catalog.items as Array).filter(func(entry) -> bool:
		return entry is Dictionary and (not entry.get("optional", false) or ResourceLoader.exists(script_path(str(entry.path)))))
	return catalog

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
	# Items that declare an `interaction` block become scene-side selectables. The item
	# only publishes data; whichever level hosts it presents the prompt via its runtime.
	var interaction: Dictionary = entry.get("interaction", {})
	if not interaction.is_empty() and instance.get_node_or_null("Interactable") == null:
		var spec := interaction.duplicate(true)
		spec["id"] = str(spec.get("id", entry.get("id", instance.name)))
		Interactable.attach_to(instance, spec)
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
