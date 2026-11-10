@tool
extends "res://tools/building_construction/BuildingConstruction/Shared/RecipeComponent.gd"

# Source: kit/public_props.py :: dish_rack
func _init() -> void:
	recipe_module = "res://tools/building_construction/BuildingConstruction/Props/PublicRecipes.gd"
	recipe_function = "dish_rack"
	parameter_order = ["name", "mats", "width", "height", "parent"]
	recipe_parameters = {"width": 1.7, "height": 1.7}
