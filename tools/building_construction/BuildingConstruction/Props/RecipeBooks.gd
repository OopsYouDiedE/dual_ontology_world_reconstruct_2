@tool
extends "res://tools/building_construction/BuildingConstruction/Shared/RecipeComponent.gd"

# Source: kit/furniture.py :: books
func _init() -> void:
	recipe_module = "res://tools/building_construction/BuildingConstruction/Tables/FurnitureRecipes.gd"
	recipe_function = "books"
	parameter_order = ["name", "mats", "width", "depth", "height", "count", "seed", "parent"]
	recipe_parameters = {"width": 0.34, "depth": 0.25, "height": 0.17, "count": 3, "seed": 7}
