@tool
extends "res://tools/building_construction/BuildingConstruction/Shared/RecipeComponent.gd"

# Source: kit/furniture.py :: painting
func _init() -> void:
	recipe_module = "res://tools/building_construction/BuildingConstruction/Tables/FurnitureRecipes.gd"
	recipe_function = "painting"
	parameter_order = ["name", "mats", "width", "height", "depth", "style", "seed", "parent"]
	recipe_parameters = {"width": 1.05, "height": 0.85, "depth": 0.065, "style": "city", "seed": 7}
