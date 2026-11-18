@tool
extends "res://tools/building_construction/BuildingConstruction/Shared/RecipeComponent.gd"

# Source: kit/residential_props.py :: pressure_panel
func _init() -> void:
	recipe_module = "res://tools/building_construction/BuildingConstruction/Props/ResidentialRecipes.gd"
	recipe_function = "pressure_panel"
	parameter_order = ["name", "mats", "width", "height", "parent"]
	recipe_parameters = {"width": 0.65, "height": 0.75}
