@tool
extends "res://tools/building_construction/BuildingConstruction/Shared/RecipeComponent.gd"

# Source: kit/special_props.py :: cabinet
func _init() -> void:
	recipe_module = "res://tools/building_construction/BuildingConstruction/Props/SpecialRecipes.gd"
	recipe_function = "cabinet"
	parameter_order = ["name", "mats", "width", "depth", "height", "drawers", "parent"]
	recipe_parameters = {"width": 1.2, "depth": 0.5, "height": 1.9, "drawers": 0}
