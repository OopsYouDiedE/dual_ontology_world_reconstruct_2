@tool
extends "res://tools/building_construction/BuildingConstruction/Shared/RecipeComponent.gd"

# Source: kit/public_props.py :: resonance_tubes
func _init() -> void:
	recipe_module = "res://tools/building_construction/BuildingConstruction/Props/PublicRecipes.gd"
	recipe_function = "resonance_tubes"
	parameter_order = ["name", "mats", "width", "height", "count", "parent"]
	recipe_parameters = {"width": 3.6, "height": 2.9, "count": 11}
