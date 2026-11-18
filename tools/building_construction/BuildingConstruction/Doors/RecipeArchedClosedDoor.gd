@tool
extends "res://tools/building_construction/BuildingConstruction/Shared/RecipeComponent.gd"

# Source: kit/variants.py :: arched_closed_door
func _init() -> void:
	recipe_module = "res://tools/building_construction/BuildingConstruction/Doors/VariantRecipes.gd"
	recipe_function = "arched_closed_door"
	parameter_order = ["name", "mats", "width", "height", "rise", "double", "segments", "frame_width", "parent"]
	recipe_parameters = {"width": 2.15, "height": 2.95, "rise": 0.78, "double": true, "segments": 12, "frame_width": 0.14}
