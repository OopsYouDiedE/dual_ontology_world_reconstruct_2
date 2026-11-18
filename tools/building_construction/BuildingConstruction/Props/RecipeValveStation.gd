@tool
extends "res://tools/building_construction/BuildingConstruction/Shared/RecipeComponent.gd"

# Source: kit/industrial_props.py :: valve_station
func _init() -> void:
	recipe_module = "res://tools/building_construction/BuildingConstruction/Props/IndustrialRecipes.gd"
	recipe_function = "valve_station"
	parameter_order = ["name", "mats", "width", "height", "parent"]
	recipe_parameters = {"width": 1.25, "height": 1.35}
