@tool
extends "res://tools/building_construction/BuildingConstruction/Shared/RecipeComponent.gd"

# Source: kit/decor.py :: library_rail
func _init() -> void:
	recipe_module = "res://tools/building_construction/BuildingConstruction/Props/DecorRecipes.gd"
	recipe_function = "library_rail"
	parameter_order = ["name", "mats", "length", "height", "parent"]
	recipe_parameters = {"length": 4, "height": 3.2}
