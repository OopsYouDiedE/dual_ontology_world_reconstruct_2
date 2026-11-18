@tool
extends "res://tools/building_construction/BuildingConstruction/Shared/RecipeComponent.gd"

# Source: kit/public_props.py :: watering_can
func _init() -> void:
	recipe_module = "res://tools/building_construction/BuildingConstruction/Props/PublicRecipes.gd"
	recipe_function = "watering_can"
	parameter_order = ["name", "mats", "radius", "height", "parent"]
	recipe_parameters = {"radius": 0.18, "height": 0.35}
