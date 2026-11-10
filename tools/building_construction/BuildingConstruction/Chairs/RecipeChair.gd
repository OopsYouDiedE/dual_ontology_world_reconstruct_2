@tool
extends "res://tools/building_construction/BuildingConstruction/Shared/RecipeComponent.gd"

# Source: kit/furniture.py :: chair
func _init() -> void:
	recipe_module = "res://tools/building_construction/BuildingConstruction/Tables/FurnitureRecipes.gd"
	recipe_function = "chair"
	parameter_order = ["name", "mats", "width", "depth", "height", "seat_height", "arms", "parent"]
	recipe_parameters = {"width": 0.52, "depth": 0.53, "height": 0.98, "seat_height": 0.44, "arms": false}
