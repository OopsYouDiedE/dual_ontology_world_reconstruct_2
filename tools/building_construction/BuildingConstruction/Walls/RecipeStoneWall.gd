@tool
extends "res://tools/building_construction/BuildingConstruction/Shared/RecipeComponent.gd"

# Source: kit/outdoor_props.py :: stone_wall
func _init() -> void:
	recipe_module = "res://tools/building_construction/BuildingConstruction/Props/OutdoorRecipes.gd"
	recipe_function = "stone_wall"
	parameter_order = ["name", "mats", "length", "height", "thickness", "pier_spacing", "parent"]
	recipe_parameters = {"length": 4, "height": 1.05, "thickness": 0.32, "pier_spacing": 3.0}
