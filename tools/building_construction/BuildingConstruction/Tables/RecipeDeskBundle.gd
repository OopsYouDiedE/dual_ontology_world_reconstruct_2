@tool
extends "res://tools/building_construction/BuildingConstruction/Shared/RecipeComponent.gd"

# Source: kit/residential_props.py :: desk_bundle
func _init() -> void:
	recipe_module = "res://tools/building_construction/BuildingConstruction/Props/ResidentialRecipes.gd"
	recipe_function = "desk_bundle"
	parameter_order = ["name", "mats", "mode", "seed", "parent"]
	recipe_parameters = {"mode": "manuscripts", "seed": 7}
