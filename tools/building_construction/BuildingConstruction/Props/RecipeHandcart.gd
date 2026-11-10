@tool
extends "res://tools/building_construction/BuildingConstruction/Shared/RecipeComponent.gd"

# Source: kit/industrial_props.py :: handcart
func _init() -> void:
	recipe_module = "res://tools/building_construction/BuildingConstruction/Props/IndustrialRecipes.gd"
	recipe_function = "handcart"
	parameter_order = ["name", "mats", "width", "length", "parent"]
	recipe_parameters = {"width": 1.1, "length": 1.6}
