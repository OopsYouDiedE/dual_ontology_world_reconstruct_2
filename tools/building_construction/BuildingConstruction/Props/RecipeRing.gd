@tool
extends "res://tools/building_construction/BuildingConstruction/Shared/RecipeComponent.gd"

# Source: kit/industrial_props.py :: ring
func _init() -> void:
	recipe_module = "res://tools/building_construction/BuildingConstruction/Props/IndustrialRecipes.gd"
	recipe_function = "ring"
	parameter_order = ["name", "outer", "inner", "depth", "mat", "parent", "sides"]
	recipe_parameters = {"outer": 0.25, "inner": 0.18, "depth": 0.1, "sides": 12}
