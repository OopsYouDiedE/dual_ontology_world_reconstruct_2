@tool
extends "res://tools/building_construction/BuildingConstruction/Shared/RecipeComponent.gd"

# Source: kit/outdoor_props.py :: oath_platform
func _init() -> void:
	recipe_module = "res://tools/building_construction/BuildingConstruction/Props/OutdoorRecipes.gd"
	recipe_function = "oath_platform"
	parameter_order = ["name", "mats", "width", "depth", "height", "parent"]
	recipe_parameters = {"width": 4.2, "depth": 2.4, "height": 0.6}
