@tool
extends "res://tools/building_construction/BuildingConstruction/Shared/RecipeComponent.gd"

# Source: kit/furniture.py :: bookshelf
func _init() -> void:
	recipe_module = "res://tools/building_construction/BuildingConstruction/Tables/FurnitureRecipes.gd"
	recipe_function = "bookshelf"
	parameter_order = ["name", "mats", "width", "depth", "height", "shelves", "bays", "fill", "seed", "parent"]
	recipe_parameters = {"width": 2.0, "depth": 0.42, "height": 2.55, "shelves": 4, "bays": 2, "fill": 0.78, "seed": 7}
