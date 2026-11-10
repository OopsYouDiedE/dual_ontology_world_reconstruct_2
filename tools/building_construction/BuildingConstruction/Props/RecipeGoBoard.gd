@tool
extends "res://tools/building_construction/BuildingConstruction/Shared/RecipeComponent.gd"

# Source: kit/residential_props.py :: go_board
func _init() -> void:
	recipe_module = "res://tools/building_construction/BuildingConstruction/Props/ResidentialRecipes.gd"
	recipe_function = "go_board"
	parameter_order = ["name", "mats", "size", "lines", "parent"]
	recipe_parameters = {"size": 0.72, "lines": 19}
