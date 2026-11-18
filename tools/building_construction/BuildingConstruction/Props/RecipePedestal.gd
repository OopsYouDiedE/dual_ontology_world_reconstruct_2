@tool
extends "res://tools/building_construction/BuildingConstruction/Shared/RecipeComponent.gd"

# Source: kit/decor.py :: pedestal
func _init() -> void:
	recipe_module = "res://tools/building_construction/BuildingConstruction/Props/DecorRecipes.gd"
	recipe_function = "pedestal"
	parameter_order = ["name", "mats", "height", "width", "parent"]
	recipe_parameters = {"height": 0.8, "width": 0.48}
