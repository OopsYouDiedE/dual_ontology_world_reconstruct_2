@tool
extends "res://tools/building_construction/BuildingConstruction/Shared/RecipeComponent.gd"

# Source: kit/stair_exact.py :: straight_flight
func _init() -> void:
	recipe_module = "res://tools/building_construction/BuildingConstruction/Stairs/FlightRecipes.gd"
	recipe_function = "straight_flight"
	parameter_order = ["name", "start", "end", "width", "mats", "risers", "parent"]
	recipe_parameters = {"start": [0, 0, 0], "end": [2.7, 0, 1.5], "width": 1.8, "risers": 10}
