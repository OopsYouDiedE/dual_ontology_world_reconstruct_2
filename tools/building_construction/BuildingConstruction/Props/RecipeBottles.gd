@tool
extends "res://tools/building_construction/BuildingConstruction/Shared/RecipeComponent.gd"

# Source: kit/special_props.py :: bottles
func _init() -> void:
	recipe_module = "res://tools/building_construction/BuildingConstruction/Props/SpecialRecipes.gd"
	recipe_function = "bottles"
	parameter_order = ["name", "mats", "count", "spacing", "parent"]
	recipe_parameters = {"count": 6, "spacing": 0.17}
