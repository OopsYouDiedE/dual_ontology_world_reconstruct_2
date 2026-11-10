@tool
extends "res://tools/building_construction/BuildingConstruction/Shared/RecipeComponent.gd"

# Source: kit/industrial_props.py :: platform_scale
func _init() -> void:
	recipe_module = "res://tools/building_construction/BuildingConstruction/Props/IndustrialRecipes.gd"
	recipe_function = "platform_scale"
	parameter_order = ["name", "mats", "width", "depth", "parent"]
	recipe_parameters = {"width": 1.4, "depth": 1.1}
