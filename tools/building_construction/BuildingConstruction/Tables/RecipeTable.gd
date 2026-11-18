@tool
extends "res://tools/building_construction/BuildingConstruction/Shared/RecipeComponent.gd"

# Source: kit/furniture.py :: table
func _init() -> void:
	recipe_module = "res://tools/building_construction/BuildingConstruction/Tables/FurnitureRecipes.gd"
	recipe_function = "table"
	parameter_order = ["name", "mats", "width", "depth", "height", "shape", "parent"]
	recipe_parameters = {"width": 1.6, "depth": 0.85, "height": 0.78, "shape": "rect"}
