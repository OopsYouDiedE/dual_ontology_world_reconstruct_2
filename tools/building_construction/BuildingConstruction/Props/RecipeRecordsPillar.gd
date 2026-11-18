@tool
extends "res://tools/building_construction/BuildingConstruction/Shared/RecipeComponent.gd"

# Source: kit/public_props.py :: records_pillar
func _init() -> void:
	recipe_module = "res://tools/building_construction/BuildingConstruction/Props/PublicRecipes.gd"
	recipe_function = "records_pillar"
	parameter_order = ["name", "mats", "radius", "height", "parent"]
	recipe_parameters = {"radius": 0.66, "height": 1.75}
