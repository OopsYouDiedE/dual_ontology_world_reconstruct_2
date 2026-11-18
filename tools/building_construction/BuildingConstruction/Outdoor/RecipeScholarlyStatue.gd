@tool
extends "res://tools/building_construction/BuildingConstruction/Shared/RecipeComponent.gd"

# Source: kit/outdoor_props.py :: scholarly_statue
func _init() -> void:
	recipe_module = "res://tools/building_construction/BuildingConstruction/Props/OutdoorRecipes.gd"
	recipe_function = "scholarly_statue"
	parameter_order = ["name", "mats", "height", "parent"]
	recipe_parameters = {"height": 2.8}
