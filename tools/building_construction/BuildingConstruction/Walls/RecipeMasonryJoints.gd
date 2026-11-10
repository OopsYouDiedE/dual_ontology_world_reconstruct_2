@tool
extends "res://tools/building_construction/BuildingConstruction/Shared/RecipeComponent.gd"

# Source: kit/industrial_props.py :: masonry_joints
func _init() -> void:
	recipe_module = "res://tools/building_construction/BuildingConstruction/Props/IndustrialRecipes.gd"
	recipe_function = "masonry_joints"
	parameter_order = ["name", "mats", "length", "height", "openings", "brick_width", "row_height", "parent"]
	recipe_parameters = {"length": 4.0, "height": 3.0, "openings": [], "brick_width": 1.08, "row_height": 0.47}
