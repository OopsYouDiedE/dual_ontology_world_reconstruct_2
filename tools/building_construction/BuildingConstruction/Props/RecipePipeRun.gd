@tool
extends "res://tools/building_construction/BuildingConstruction/Shared/RecipeComponent.gd"

# Source: kit/industrial_props.py :: pipe_run
func _init() -> void:
	recipe_module = "res://tools/building_construction/BuildingConstruction/Props/IndustrialRecipes.gd"
	recipe_function = "pipe_run"
	parameter_order = ["name", "mats", "nodes", "radius", "sides", "collars", "parent"]
	recipe_parameters = {"nodes": [[0, 0, 0], [0, 1, 0], [1, 1, 1]], "radius": 0.09, "sides": 8, "collars": true}
