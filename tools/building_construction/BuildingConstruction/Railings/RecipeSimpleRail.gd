@tool
extends "res://tools/building_construction/BuildingConstruction/Shared/RecipeComponent.gd"

# Source: kit/industrial_props.py :: simple_rail
func _init() -> void:
	recipe_module = "res://tools/building_construction/BuildingConstruction/Props/IndustrialRecipes.gd"
	recipe_function = "simple_rail"
	parameter_order = ["name", "mats", "points", "height", "spacing", "parent", "post_points"]
	recipe_parameters = {"points": [[0, 0, 0], [4, 0, 0]], "height": 0.9, "spacing": 0.8, "post_points": null}
