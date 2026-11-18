@tool
extends "res://tools/building_construction/BuildingConstruction/Shared/RecipeComponent.gd"

# Source: kit/industrial_props.py :: reaction_vessel
func _init() -> void:
	recipe_module = "res://tools/building_construction/BuildingConstruction/Props/IndustrialRecipes.gd"
	recipe_function = "reaction_vessel"
	parameter_order = ["name", "mats", "radius", "height", "parent"]
	recipe_parameters = {"radius": 0.72, "height": 2.7}
