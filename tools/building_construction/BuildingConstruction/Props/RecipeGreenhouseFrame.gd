@tool
extends "res://tools/building_construction/BuildingConstruction/Shared/RecipeComponent.gd"

# Source: kit/public_props.py :: greenhouse_frame
func _init() -> void:
	recipe_module = "res://tools/building_construction/BuildingConstruction/Props/PublicRecipes.gd"
	recipe_function = "greenhouse_frame"
	parameter_order = ["name", "mats", "width", "depth", "eave", "rise", "bays", "parent"]
	recipe_parameters = {"width": 8, "depth": 8, "eave": 3.5, "rise": 1.25, "bays": 4}
