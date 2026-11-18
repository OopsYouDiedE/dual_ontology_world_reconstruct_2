@tool
extends "res://tools/building_construction/BuildingConstruction/Shared/RecipeComponent.gd"

# Source: kit/openings.py :: closed_door
func _init() -> void:
	recipe_module = "res://tools/building_construction/BuildingConstruction/Windows/OpeningRecipes.gd"
	recipe_function = "closed_door"
	parameter_order = ["name", "mats", "width", "height", "double", "transom", "parent"]
	recipe_parameters = {"width": 1.25, "height": 2.65, "double": false, "transom": false}
