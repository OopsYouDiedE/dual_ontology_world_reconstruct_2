@tool
extends "res://tools/building_construction/BuildingConstruction/Shared/RecipeComponent.gd"

# Source: kit/outdoor_props.py :: courtyard_gate
func _init() -> void:
	recipe_module = "res://tools/building_construction/BuildingConstruction/Props/OutdoorRecipes.gd"
	recipe_function = "courtyard_gate"
	parameter_order = ["name", "mats", "width", "height", "rise", "parent"]
	recipe_parameters = {"width": 2.2, "height": 2.7, "rise": 0.65}
