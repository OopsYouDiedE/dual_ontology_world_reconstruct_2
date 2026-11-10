@tool
extends "res://tools/building_construction/BuildingConstruction/Shared/RecipeComponent.gd"

# Source: kit/outdoor_props.py :: water_patch
func _init() -> void:
	recipe_module = "res://tools/building_construction/BuildingConstruction/Props/OutdoorRecipes.gd"
	recipe_function = "water_patch"
	parameter_order = ["name", "mats", "width", "depth", "seed", "parent"]
	recipe_parameters = {"width": 10, "depth": 4.2, "seed": 3}
