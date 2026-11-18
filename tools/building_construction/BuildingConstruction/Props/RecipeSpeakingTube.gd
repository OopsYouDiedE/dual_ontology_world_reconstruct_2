@tool
extends "res://tools/building_construction/BuildingConstruction/Shared/RecipeComponent.gd"

# Source: kit/residential_props.py :: speaking_tube
func _init() -> void:
	recipe_module = "res://tools/building_construction/BuildingConstruction/Props/ResidentialRecipes.gd"
	recipe_function = "speaking_tube"
	parameter_order = ["name", "mats", "height", "parent"]
	recipe_parameters = {"height": 1.8}
