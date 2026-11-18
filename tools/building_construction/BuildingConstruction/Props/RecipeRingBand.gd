@tool
extends "res://tools/building_construction/BuildingConstruction/Shared/RecipeComponent.gd"

# Source: kit/public_props.py :: ring_band
func _init() -> void:
	recipe_module = "res://tools/building_construction/BuildingConstruction/Props/PublicRecipes.gd"
	recipe_function = "ring_band"
	parameter_order = ["name", "mats", "radius", "width", "depth", "segments", "parent"]
	recipe_parameters = {"radius": 1.0, "width": 0.07, "depth": 0.045, "segments": 24}
