@tool
extends "res://tools/building_construction/BuildingConstruction/Shared/RecipeComponent.gd"

# Source: kit/outdoor_props.py :: planter_bed
func _init() -> void:
	recipe_module = "res://tools/building_construction/BuildingConstruction/Props/OutdoorRecipes.gd"
	recipe_function = "planter_bed"
	parameter_order = ["name", "mats", "width", "depth", "height", "shrubs", "parent"]
	recipe_parameters = {"width": 2.0, "depth": 0.85, "height": 0.42, "shrubs": true}
