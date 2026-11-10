@tool
extends "res://tools/building_construction/BuildingConstruction/Shared/RecipeComponent.gd"

# Source: kit/residential_props.py :: rug
func _init() -> void:
	recipe_module = "res://tools/building_construction/BuildingConstruction/Props/ResidentialRecipes.gd"
	recipe_function = "rug"
	parameter_order = ["name", "mats", "width", "depth", "parent"]
	recipe_parameters = {"width": 2.1, "depth": 1.4}
