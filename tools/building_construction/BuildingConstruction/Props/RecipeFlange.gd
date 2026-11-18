@tool
extends "res://tools/building_construction/BuildingConstruction/Shared/RecipeComponent.gd"

# Source: kit/industrial_props.py :: flange
func _init() -> void:
	recipe_module = "res://tools/building_construction/BuildingConstruction/Props/IndustrialRecipes.gd"
	recipe_function = "flange"
	parameter_order = ["name", "mats", "radius", "parent", "bolts"]
	recipe_parameters = {"radius": 0.12, "bolts": 6}
