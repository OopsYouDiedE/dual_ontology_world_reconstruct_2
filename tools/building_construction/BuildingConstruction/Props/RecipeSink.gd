@tool
extends "res://tools/building_construction/BuildingConstruction/Shared/RecipeComponent.gd"

# Source: kit/special_props.py :: sink
func _init() -> void:
	recipe_module = "res://tools/building_construction/BuildingConstruction/Props/SpecialRecipes.gd"
	recipe_function = "sink"
	parameter_order = ["name", "mats", "width", "depth", "height", "parent"]
	recipe_parameters = {"width": 1.3, "depth": 0.65, "height": 0.88}
