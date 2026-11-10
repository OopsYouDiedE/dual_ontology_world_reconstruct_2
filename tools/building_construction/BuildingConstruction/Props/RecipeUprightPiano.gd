@tool
extends "res://tools/building_construction/BuildingConstruction/Shared/RecipeComponent.gd"

# Source: kit/residential_props.py :: upright_piano
func _init() -> void:
	recipe_module = "res://tools/building_construction/BuildingConstruction/Props/ResidentialRecipes.gd"
	recipe_function = "upright_piano"
	parameter_order = ["name", "mats", "width", "parent", "depth", "height"]
	recipe_parameters = {"width": 1.7, "depth": 0.7, "height": 1.45}
