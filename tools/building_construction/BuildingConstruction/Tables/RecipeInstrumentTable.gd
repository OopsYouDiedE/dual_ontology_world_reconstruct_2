@tool
extends "res://tools/building_construction/BuildingConstruction/Shared/RecipeComponent.gd"

# Source: kit/outdoor_props.py :: instrument_table
func _init() -> void:
	recipe_module = "res://tools/building_construction/BuildingConstruction/Props/OutdoorRecipes.gd"
	recipe_function = "instrument_table"
	parameter_order = ["name", "mats", "width", "depth", "height", "instrument", "parent"]
	recipe_parameters = {"width": 1.4, "depth": 0.72, "height": 0.88, "instrument": "armillary"}
