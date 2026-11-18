@tool
extends "res://tools/building_construction/BuildingConstruction/Shared/RecipeComponent.gd"

# Source: kit/outdoor_props.py :: dock
func _init() -> void:
	recipe_module = "res://tools/building_construction/BuildingConstruction/Props/OutdoorRecipes.gd"
	recipe_function = "dock"
	parameter_order = ["name", "mats", "width", "length", "parent"]
	recipe_parameters = {"width": 2.3, "length": 3.2}
