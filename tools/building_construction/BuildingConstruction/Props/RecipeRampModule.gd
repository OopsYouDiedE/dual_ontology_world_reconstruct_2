@tool
extends "res://tools/building_construction/BuildingConstruction/Shared/RecipeComponent.gd"

# Source: kit/industrial_props.py :: ramp_module
func _init() -> void:
	recipe_module = "res://tools/building_construction/BuildingConstruction/Props/IndustrialRecipes.gd"
	recipe_function = "ramp_module"
	parameter_order = ["name", "mats", "width", "length", "rise", "landing", "parent"]
	recipe_parameters = {"width": 3.1, "length": 8.2, "rise": 1.4, "landing": 1.2}
