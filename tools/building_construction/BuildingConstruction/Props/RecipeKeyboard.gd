@tool
extends "res://tools/building_construction/BuildingConstruction/Shared/RecipeComponent.gd"

# Source: kit/residential_props.py :: keyboard
func _init() -> void:
	recipe_module = "res://tools/building_construction/BuildingConstruction/Props/ResidentialRecipes.gd"
	recipe_function = "keyboard"
	parameter_order = ["name", "mats", "width", "depth", "height", "parent"]
	recipe_parameters = {"width": 1.7, "depth": 0.7, "height": 1.45}
