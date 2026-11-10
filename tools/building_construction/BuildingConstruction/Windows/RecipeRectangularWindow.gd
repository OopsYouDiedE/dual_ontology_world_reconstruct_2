@tool
extends "res://tools/building_construction/BuildingConstruction/Shared/RecipeComponent.gd"

# Source: kit/variants.py :: rectangular_window
func _init() -> void:
	recipe_module = "res://tools/building_construction/BuildingConstruction/Doors/VariantRecipes.gd"
	recipe_function = "rectangular_window"
	parameter_order = ["name", "mats", "width", "height", "cols", "rows", "frame_width", "sill", "glass", "parent"]
	recipe_parameters = {"width": 1.8, "height": 2.35, "cols": 4, "rows": 5, "frame_width": 0.13, "sill": true, "glass": true}
