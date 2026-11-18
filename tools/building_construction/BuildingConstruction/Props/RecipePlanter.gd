@tool
extends "res://tools/building_construction/BuildingConstruction/Shared/RecipeComponent.gd"

# Source: kit/furniture.py :: planter
func _init() -> void:
	recipe_module = "res://tools/building_construction/BuildingConstruction/Tables/FurnitureRecipes.gd"
	recipe_function = "planter"
	parameter_order = ["name", "mats", "width", "height", "flower_count", "seed", "parent"]
	recipe_parameters = {"width": 0.52, "height": 0.66, "flower_count": 7, "seed": 7}
