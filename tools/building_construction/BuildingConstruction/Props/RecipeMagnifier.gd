@tool
extends "res://tools/building_construction/BuildingConstruction/Shared/RecipeComponent.gd"

# Source: kit/public_props.py :: magnifier
func _init() -> void:
	recipe_module = "res://tools/building_construction/BuildingConstruction/Props/PublicRecipes.gd"
	recipe_function = "magnifier"
	parameter_order = ["name", "mats", "height", "parent"]
	recipe_parameters = {"height": 0.55}
