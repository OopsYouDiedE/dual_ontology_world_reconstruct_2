@tool
extends "res://tools/building_construction/BuildingConstruction/Shared/RecipeComponent.gd"

# Source: kit/residential_props.py :: framed_mirror
func _init() -> void:
	recipe_module = "res://tools/building_construction/BuildingConstruction/Props/ResidentialRecipes.gd"
	recipe_function = "framed_mirror"
	parameter_order = ["name", "mats", "width", "height", "parent"]
	recipe_parameters = {"width": 0.65, "height": 0.95}
