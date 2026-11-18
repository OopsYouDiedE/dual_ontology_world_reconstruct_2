@tool
extends "res://tools/building_construction/BuildingConstruction/Shared/RecipeComponent.gd"

# Source: kit/residential_props.py :: paneled_bed
func _init() -> void:
	recipe_module = "res://tools/building_construction/BuildingConstruction/Props/ResidentialRecipes.gd"
	recipe_function = "paneled_bed"
	parameter_order = ["name", "mats", "width", "length", "height", "parent"]
	recipe_parameters = {"width": 1.35, "length": 2.25, "height": 0.56}
