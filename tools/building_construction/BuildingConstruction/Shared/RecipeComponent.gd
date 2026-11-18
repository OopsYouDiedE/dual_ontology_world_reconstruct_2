@tool
extends Node3D

const Geometry = preload("res://tools/building_construction/BuildingConstruction/Shared/RecipeGeometry.gd")

@export var recipe_module := ""
@export var recipe_function := ""
@export var recipe_parameters: Dictionary = {}
var parameter_order: Array = []
var rebuild_pending := false

func _ready() -> void:
	rebuild()

func _get_property_list() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for key in recipe_parameters:
		var value = recipe_parameters[key]
		result.append({"name":key,"type":typeof(value),"usage":PROPERTY_USAGE_DEFAULT | PROPERTY_USAGE_SCRIPT_VARIABLE})
	return result

func _get(property: StringName):
	return recipe_parameters.get(str(property))

func _set(property: StringName, value) -> bool:
	if not recipe_parameters.has(str(property)): return false
	recipe_parameters[str(property)] = value
	if is_inside_tree() and not rebuild_pending:
		rebuild_pending = true
		rebuild.call_deferred()
	return true

func rebuild() -> void:
	rebuild_pending = false
	if recipe_module.is_empty() or recipe_function.is_empty(): return
	var module = load(recipe_module)
	if module == null or not module.has_method("gen_"+recipe_function):
		push_error("无法加载生成配方："+recipe_module+" / "+recipe_function)
		return
	var palette = Geometry.outdoor_palette(Geometry.industrial_palette(Geometry.gen_palette()))
	var args = []
	for key in parameter_order:
		match key:
			"name": args.append(str(name))
			"mats": args.append(palette)
			"mat": args.append(palette.wood)
			"parent": args.append(null)
			_: args.append(recipe_parameters.get(key))
	var record = module.callv("gen_"+recipe_function,args)
	if record == null:
		push_error("生成配方未返回组件："+recipe_function)
		return
	var generated = Geometry.finish(record)
	if generated == null: return
	var old = get_node_or_null("Generated")
	if old != null: remove_child(old); old.queue_free()
	generated.name = "Generated"
	add_child(generated)
	for part in generated.find_children("*","MeshInstance3D",true,false):
		if part.mesh.get_surface_count() == 0: continue
		var body = StaticBody3D.new()
		body.name = "Collision"
		part.add_child(body)
		var collision = CollisionShape3D.new()
		collision.shape = part.mesh.create_trimesh_shape()
		body.add_child(collision)
