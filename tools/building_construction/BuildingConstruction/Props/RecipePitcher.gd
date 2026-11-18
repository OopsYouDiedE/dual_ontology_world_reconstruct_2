@tool
extends "res://tools/building_construction/BuildingConstruction/Shared/RecipeComponent.gd"

# Source: kit/residential_props.py :: pitcher
func _init() -> void:
	recipe_module = "res://tools/building_construction/BuildingConstruction/Props/ResidentialRecipes.gd"
	recipe_function = "pitcher"
	parameter_order = ["name", "mats", "radius", "height", "parent"]
	recipe_parameters = {"radius": 0.11, "height": 0.3}
