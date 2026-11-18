@tool
extends "res://tools/building_construction/BuildingConstruction/Shared/RecipeComponent.gd"

# Source: kit/industrial_props.py :: gauge
func _init() -> void:
	recipe_module = "res://tools/building_construction/BuildingConstruction/Props/IndustrialRecipes.gd"
	recipe_function = "gauge"
	parameter_order = ["name", "mats", "radius", "needle_degrees", "parent"]
	recipe_parameters = {"radius": 0.2, "needle_degrees": 42}
