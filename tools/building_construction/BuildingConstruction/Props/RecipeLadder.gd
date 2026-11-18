@tool
extends "res://tools/building_construction/BuildingConstruction/Shared/RecipeComponent.gd"

# Source: kit/furniture.py :: ladder
func _init() -> void:
	recipe_module = "res://tools/building_construction/BuildingConstruction/Tables/FurnitureRecipes.gd"
	recipe_function = "ladder"
	parameter_order = ["name", "mats", "width", "depth", "height", "rungs", "parent"]
	recipe_parameters = {"width": 0.46, "depth": 0.3, "height": 2.2, "rungs": 7}
