@tool
extends "res://tools/building_construction/BuildingConstruction/Shared/RecipeComponent.gd"

# Source: kit/residential_props.py :: vent_grille
func _init() -> void:
	recipe_module = "res://tools/building_construction/BuildingConstruction/Props/ResidentialRecipes.gd"
	recipe_function = "vent_grille"
	parameter_order = ["name", "mats", "width", "height", "parent"]
	recipe_parameters = {"width": 0.75, "height": 0.42}
