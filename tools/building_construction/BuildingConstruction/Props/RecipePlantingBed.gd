@tool
extends "res://tools/building_construction/BuildingConstruction/Shared/RecipeComponent.gd"

# Source: kit/public_props.py :: planting_bed
func _init() -> void:
	recipe_module = "res://tools/building_construction/BuildingConstruction/Props/PublicRecipes.gd"
	recipe_function = "planting_bed"
	parameter_order = ["name", "mats", "width", "depth", "height", "seed", "parent"]
	recipe_parameters = {"width": 1.8, "depth": 3.2, "height": 0.65, "seed": 8}
