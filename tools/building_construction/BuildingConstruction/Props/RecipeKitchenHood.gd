@tool
extends "res://tools/building_construction/BuildingConstruction/Shared/RecipeComponent.gd"

# Source: kit/residential_props.py :: kitchen_hood
func _init() -> void:
	recipe_module = "res://tools/building_construction/BuildingConstruction/Props/ResidentialRecipes.gd"
	recipe_function = "kitchen_hood"
	parameter_order = ["name", "mats", "width", "parent", "depth", "height"]
	recipe_parameters = {"width": 2.25, "depth": 0.8, "height": 1.65}
