@tool
extends "res://tools/building_construction/BuildingConstruction/Shared/RecipeComponent.gd"

# Source: kit/public_props.py :: medicine_cabinet
func _init() -> void:
	recipe_module = "res://tools/building_construction/BuildingConstruction/Props/PublicRecipes.gd"
	recipe_function = "medicine_cabinet"
	parameter_order = ["name", "mats", "width", "height", "parent"]
	recipe_parameters = {"width": 1.5, "height": 2.2}
