@tool
extends "res://tools/building_construction/BuildingConstruction/Shared/RecipeComponent.gd"

# Source: kit/outdoor_props.py :: rope_coil
func _init() -> void:
	recipe_module = "res://tools/building_construction/BuildingConstruction/Props/OutdoorRecipes.gd"
	recipe_function = "rope_coil"
	parameter_order = ["name", "mats", "radius", "parent"]
	recipe_parameters = {"radius": 0.38}
