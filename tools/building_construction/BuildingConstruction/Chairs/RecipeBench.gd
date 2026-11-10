@tool
extends "res://tools/building_construction/BuildingConstruction/Shared/RecipeComponent.gd"

# Source: kit/furniture.py :: bench
func _init() -> void:
	recipe_module = "res://tools/building_construction/BuildingConstruction/Tables/FurnitureRecipes.gd"
	recipe_function = "bench"
	parameter_order = ["name", "mats", "width", "depth", "height", "seat_height", "parent"]
	recipe_parameters = {"width": 1.8, "depth": 0.6, "height": 1.02, "seat_height": 0.45}
