@tool
extends "res://tools/building_construction/BuildingConstruction/Shared/RecipeComponent.gd"

# Source: kit/industrial_props.py :: indicator_board
func _init() -> void:
	recipe_module = "res://tools/building_construction/BuildingConstruction/Props/IndustrialRecipes.gd"
	recipe_function = "indicator_board"
	parameter_order = ["name", "mats", "width", "height", "kind", "parent"]
	recipe_parameters = {"width": 0.4, "height": 1.25, "kind": "flood"}
