@tool
extends "res://tools/building_construction/BuildingConstruction/Shared/RecipeComponent.gd"

# Source: kit/industrial_props.py :: heavy_lock
func _init() -> void:
	recipe_module = "res://tools/building_construction/BuildingConstruction/Props/IndustrialRecipes.gd"
	recipe_function = "heavy_lock"
	parameter_order = ["name", "mats", "width", "parent"]
	recipe_parameters = {"width": 0.22}
