@tool
extends "res://tools/building_construction/BuildingConstruction/Shared/RecipeComponent.gd"

# Source: kit/special_props.py :: record_station
func _init() -> void:
	recipe_module = "res://tools/building_construction/BuildingConstruction/Props/SpecialRecipes.gd"
	recipe_function = "record_station"
	parameter_order = ["name", "mats", "width", "height", "kind", "parent"]
	recipe_parameters = {"width": 0.9, "height": 1.45, "kind": "record"}
