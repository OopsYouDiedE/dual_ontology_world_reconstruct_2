@tool
extends "res://tools/building_construction/BuildingConstruction/Shared/RecipeComponent.gd"

# Source: kit/special_props.py :: chessboard
func _init() -> void:
	recipe_module = "res://tools/building_construction/BuildingConstruction/Props/SpecialRecipes.gd"
	recipe_function = "chessboard"
	parameter_order = ["name", "mats", "size", "parent"]
	recipe_parameters = {"size": 0.62}
