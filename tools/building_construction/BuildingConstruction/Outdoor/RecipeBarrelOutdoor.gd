@tool
extends "res://tools/building_construction/BuildingConstruction/Shared/RecipeComponent.gd"

# Source: kit/outdoor_props.py :: barrel
func _init() -> void:
	recipe_module = "res://tools/building_construction/BuildingConstruction/Props/OutdoorRecipes.gd"
	recipe_function = "barrel"
	parameter_order = ["name", "mats", "radius", "height", "parent"]
	recipe_parameters = {"radius": 0.38, "height": 0.85}
