@tool
extends "res://tools/building_construction/BuildingConstruction/Shared/RecipeComponent.gd"

# Source: kit/industrial_props.py :: interlock_handle
func _init() -> void:
	recipe_module = "res://tools/building_construction/BuildingConstruction/Props/IndustrialRecipes.gd"
	recipe_function = "interlock_handle"
	parameter_order = ["name", "mats", "radius", "parent"]
	recipe_parameters = {"radius": 0.23}
