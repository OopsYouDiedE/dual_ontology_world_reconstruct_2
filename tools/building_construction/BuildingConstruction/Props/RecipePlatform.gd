@tool
extends "res://tools/building_construction/BuildingConstruction/Shared/RecipeComponent.gd"

# Source: kit/decor.py :: platform
func _init() -> void:
	recipe_module = "res://tools/building_construction/BuildingConstruction/Props/DecorRecipes.gd"
	recipe_function = "platform"
	parameter_order = ["name", "mats", "width", "depth", "height", "thickness", "parent"]
	recipe_parameters = {"width": 2, "depth": 1.5, "height": 1.8, "thickness": 0.18}
