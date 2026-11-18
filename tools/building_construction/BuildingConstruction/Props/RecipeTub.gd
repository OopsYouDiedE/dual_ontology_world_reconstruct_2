@tool
extends "res://tools/building_construction/BuildingConstruction/Shared/RecipeComponent.gd"

# Source: kit/special_props.py :: tub
func _init() -> void:
	recipe_module = "res://tools/building_construction/BuildingConstruction/Props/SpecialRecipes.gd"
	recipe_function = "tub"
	parameter_order = ["name", "mats", "width", "depth", "height", "parent"]
	recipe_parameters = {"width": 1.6, "depth": 0.8, "height": 0.6}
