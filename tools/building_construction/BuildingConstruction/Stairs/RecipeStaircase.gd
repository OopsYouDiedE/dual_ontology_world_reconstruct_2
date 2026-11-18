@tool
extends "res://tools/building_construction/BuildingConstruction/Shared/RecipeComponent.gd"

# Source: kit/architecture.py :: staircase
func _init() -> void:
	recipe_module = "res://tools/building_construction/BuildingConstruction/Walls/ArchitectureRecipes.gd"
	recipe_function = "staircase"
	parameter_order = ["name", "points", "width", "mats", "step_rise", "landing_depth", "parent"]
	recipe_parameters = {"points": [[0, 0, 0], [3, 0, 1.8]], "width": 1.8, "step_rise": 0.18, "landing_depth": null}
