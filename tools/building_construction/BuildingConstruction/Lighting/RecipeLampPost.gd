@tool
extends "res://tools/building_construction/BuildingConstruction/Shared/RecipeComponent.gd"

# Source: kit/outdoor_props.py :: lamp_post
func _init() -> void:
	recipe_module = "res://tools/building_construction/BuildingConstruction/Props/OutdoorRecipes.gd"
	recipe_function = "lamp_post"
	parameter_order = ["name", "mats", "height", "energy", "parent"]
	recipe_parameters = {"height": 2.8, "energy": 22}
