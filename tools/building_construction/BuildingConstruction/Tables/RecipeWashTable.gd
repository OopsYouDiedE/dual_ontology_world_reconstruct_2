@tool
extends "res://tools/building_construction/BuildingConstruction/Shared/RecipeComponent.gd"

# Source: kit/residential_props.py :: wash_table
func _init() -> void:
	recipe_module = "res://tools/building_construction/BuildingConstruction/Props/ResidentialRecipes.gd"
	recipe_function = "wash_table"
	parameter_order = ["name", "mats", "width", "depth", "height", "mirror", "parent"]
	recipe_parameters = {"width": 0.98, "depth": 0.6, "height": 0.86, "mirror": true}
