@tool
extends "res://tools/building_construction/BuildingConstruction/Shared/RecipeComponent.gd"

# Source: kit/outdoor_props.py :: tree
func _init() -> void:
	recipe_module = "res://tools/building_construction/BuildingConstruction/Props/OutdoorRecipes.gd"
	recipe_function = "tree"
	parameter_order = ["name", "mats", "height", "crown_radius", "seed", "parent"]
	recipe_parameters = {"height": 3.8, "crown_radius": 1.15, "seed": 7}
