@tool
extends "res://tools/building_construction/BuildingConstruction/Shared/RecipeComponent.gd"

# Source: kit/outdoor_props.py :: rowboat
func _init() -> void:
	recipe_module = "res://tools/building_construction/BuildingConstruction/Props/OutdoorRecipes.gd"
	recipe_function = "rowboat"
	parameter_order = ["name", "mats", "length", "width", "height", "parent"]
	recipe_parameters = {"length": 2.6, "width": 1.05, "height": 0.55}
