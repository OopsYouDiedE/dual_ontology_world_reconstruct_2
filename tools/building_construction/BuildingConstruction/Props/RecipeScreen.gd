@tool
extends "res://tools/building_construction/BuildingConstruction/Shared/RecipeComponent.gd"

# Source: kit/special_props.py :: screen
func _init() -> void:
	recipe_module = "res://tools/building_construction/BuildingConstruction/Props/SpecialRecipes.gd"
	recipe_function = "screen"
	parameter_order = ["name", "mats", "width", "height", "parent"]
	recipe_parameters = {"width": 1.8, "height": 1.8}
