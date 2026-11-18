@tool
extends "res://tools/building_construction/BuildingConstruction/Shared/RecipeComponent.gd"

# Source: kit/variants.py :: round_window
func _init() -> void:
	recipe_module = "res://tools/building_construction/BuildingConstruction/Doors/VariantRecipes.gd"
	recipe_function = "round_window"
	parameter_order = ["name", "mats", "radius", "segments", "frame_width", "grid", "glass", "parent"]
	recipe_parameters = {"radius": 0.95, "segments": 12, "frame_width": 0.13, "grid": "cross", "glass": true}
