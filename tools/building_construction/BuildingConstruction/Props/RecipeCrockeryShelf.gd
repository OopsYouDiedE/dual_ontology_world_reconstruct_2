@tool
extends "res://tools/building_construction/BuildingConstruction/Shared/RecipeComponent.gd"

# Source: kit/residential_props.py :: crockery_shelf
func _init() -> void:
	recipe_module = "res://tools/building_construction/BuildingConstruction/Props/ResidentialRecipes.gd"
	recipe_function = "crockery_shelf"
	parameter_order = ["name", "mats", "width", "parent"]
	recipe_parameters = {"width": 1.65}
