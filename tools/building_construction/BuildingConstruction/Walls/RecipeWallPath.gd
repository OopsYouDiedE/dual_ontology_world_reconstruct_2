@tool
extends "res://tools/building_construction/BuildingConstruction/Shared/RecipeComponent.gd"

# Source: kit/architecture.py :: wall_path
func _init() -> void:
	recipe_module = "res://tools/building_construction/BuildingConstruction/Walls/ArchitectureRecipes.gd"
	recipe_function = "wall_path"
	parameter_order = ["name", "points", "height", "thickness", "mats", "openings", "panel_height", "parent"]
	recipe_parameters = {"points": [[0, 0, 0], [4, 0, 0]], "height": 3.0, "thickness": 0.24, "openings": [], "panel_height": 1.05}
