@tool
extends "res://tools/building_construction/BuildingConstruction/Shared/RecipeComponent.gd"

# Source: kit/industrial_props.py :: schematic
func _init() -> void:
	recipe_module = "res://tools/building_construction/BuildingConstruction/Props/IndustrialRecipes.gd"
	recipe_function = "schematic"
	parameter_order = ["name", "mats", "width", "height", "parent"]
	recipe_parameters = {"width": 2.2, "height": 1.05}
