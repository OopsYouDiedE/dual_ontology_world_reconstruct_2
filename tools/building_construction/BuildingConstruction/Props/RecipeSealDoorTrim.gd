@tool
extends "res://tools/building_construction/BuildingConstruction/Shared/RecipeComponent.gd"

# Source: kit/residential_props.py :: seal_door_trim
func _init() -> void:
	recipe_module = "res://tools/building_construction/BuildingConstruction/Props/ResidentialRecipes.gd"
	recipe_function = "seal_door_trim"
	parameter_order = ["name", "mats", "width", "height", "parent"]
	recipe_parameters = {"width": 1.3, "height": 2.45}
