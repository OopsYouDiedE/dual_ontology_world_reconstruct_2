@tool
extends "res://tools/building_construction/BuildingConstruction/Shared/RecipeComponent.gd"

# Source: kit/industrial_props.py :: drain_grate
func _init() -> void:
	recipe_module = "res://tools/building_construction/BuildingConstruction/Props/IndustrialRecipes.gd"
	recipe_function = "drain_grate"
	parameter_order = ["name", "mats", "width", "length", "parent"]
	recipe_parameters = {"width": 0.32, "length": 4}
