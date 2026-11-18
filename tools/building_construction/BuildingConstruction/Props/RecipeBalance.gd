@tool
extends "res://tools/building_construction/BuildingConstruction/Shared/RecipeComponent.gd"

# Source: kit/public_props.py :: balance
func _init() -> void:
	recipe_module = "res://tools/building_construction/BuildingConstruction/Props/PublicRecipes.gd"
	recipe_function = "balance"
	parameter_order = ["name", "mats", "width", "height", "parent"]
	recipe_parameters = {"width": 0.66, "height": 0.68}
