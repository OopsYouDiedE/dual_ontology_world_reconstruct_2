@tool
extends "res://tools/building_construction/BuildingConstruction/Shared/RecipeComponent.gd"

# Source: kit/openings.py :: arched_window
func _init() -> void:
	recipe_module = "res://tools/building_construction/BuildingConstruction/Windows/OpeningRecipes.gd"
	recipe_function = "arched_window"
	parameter_order = ["name", "mats", "width", "height", "rise", "cols", "rows", "parent", "segments", "frame_width", "glass"]
	recipe_parameters = {"width": 1.4, "height": 3.0, "rise": null, "cols": 4, "rows": 5, "segments": 10, "frame_width": 0.12, "glass": true}
