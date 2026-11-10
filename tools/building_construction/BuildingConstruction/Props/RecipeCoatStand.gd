@tool
extends "res://tools/building_construction/BuildingConstruction/Shared/RecipeComponent.gd"

# Source: kit/decor.py :: coat_stand
func _init() -> void:
	recipe_module = "res://tools/building_construction/BuildingConstruction/Props/DecorRecipes.gd"
	recipe_function = "coat_stand"
	parameter_order = ["name", "mats", "height", "parent"]
	recipe_parameters = {"height": 1.95}
