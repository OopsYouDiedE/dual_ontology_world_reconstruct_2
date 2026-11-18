@tool
extends "res://tools/building_construction/BuildingConstruction/Shared/RecipeComponent.gd"

# Source: kit/furniture.py :: book
func _init() -> void:
	recipe_module = "res://tools/building_construction/BuildingConstruction/Tables/FurnitureRecipes.gd"
	recipe_function = "book"
	parameter_order = ["name", "mats", "width", "depth", "height", "colour", "parent"]
	recipe_parameters = {"width": 0.075, "depth": 0.23, "height": 0.31, "colour": "book_red"}
