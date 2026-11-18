@tool
extends "res://tools/building_construction/BuildingConstruction/Shared/RecipeComponent.gd"

# Source: kit/public_props.py :: stamp_press
func _init() -> void:
	recipe_module = "res://tools/building_construction/BuildingConstruction/Props/PublicRecipes.gd"
	recipe_function = "stamp_press"
	parameter_order = ["name", "mats", "width", "height", "parent"]
	recipe_parameters = {"width": 0.5, "height": 0.65}
