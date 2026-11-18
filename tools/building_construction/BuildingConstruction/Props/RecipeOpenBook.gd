@tool
extends "res://tools/building_construction/BuildingConstruction/Shared/RecipeComponent.gd"

# Source: kit/furniture.py :: open_book
func _init() -> void:
	recipe_module = "res://tools/building_construction/BuildingConstruction/Tables/FurnitureRecipes.gd"
	recipe_function = "open_book"
	parameter_order = ["name", "mats", "width", "depth", "height", "parent"]
	recipe_parameters = {"width": 0.45, "depth": 0.3, "height": 0.055}
