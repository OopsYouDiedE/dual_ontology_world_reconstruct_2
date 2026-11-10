@tool
extends "res://tools/building_construction/BuildingConstruction/Shared/RecipeComponent.gd"

# Source: kit/flooring.py :: tiled_floor
func _init() -> void:
	recipe_module = "res://tools/building_construction/BuildingConstruction/Floors/FloorRecipes.gd"
	recipe_function = "tiled_floor"
	parameter_order = ["name", "mats", "width", "depth", "tile", "cut", "grout", "border", "seed", "parent"]
	recipe_parameters = {"width": 8, "depth": 6, "tile": 0.8, "cut": 0.12, "grout": 0.012, "border": 0.42, "seed": 12}
