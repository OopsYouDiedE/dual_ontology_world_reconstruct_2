@tool
extends "res://tools/building_construction/BuildingConstruction/Shared/RecipeComponent.gd"

# Source: kit/special_props.py :: crates
func _init() -> void:
	recipe_module = "res://tools/building_construction/BuildingConstruction/Props/SpecialRecipes.gd"
	recipe_function = "crates"
	parameter_order = ["name", "mats", "width", "depth", "height", "stack", "parent"]
	recipe_parameters = {"width": 0.9, "depth": 0.7, "height": 0.75, "stack": 2}
