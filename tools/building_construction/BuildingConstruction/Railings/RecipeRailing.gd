@tool
extends "res://tools/building_construction/BuildingConstruction/Shared/RecipeComponent.gd"

# Source: kit/architecture.py :: railing
func _init() -> void:
	recipe_module = "res://tools/building_construction/BuildingConstruction/Walls/ArchitectureRecipes.gd"
	recipe_function = "railing"
	parameter_order = ["name", "points", "mats", "height", "spacing", "parent", "end_posts"]
	recipe_parameters = {"points": [[0, 0, 0], [4, 0, 0]], "height": 0.88, "spacing": 0.22, "end_posts": [true, true]}
