@tool
extends "res://tools/building_construction/BuildingConstruction/Shared/RecipeComponent.gd"

# Source: kit/special_props.py :: chalkboard
func _init() -> void:
	recipe_module = "res://tools/building_construction/BuildingConstruction/Props/SpecialRecipes.gd"
	recipe_function = "chalkboard"
	parameter_order = ["name", "mats", "width", "height", "parent"]
	recipe_parameters = {"width": 3.3, "height": 1.7}
