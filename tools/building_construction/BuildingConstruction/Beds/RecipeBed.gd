@tool
extends "res://tools/building_construction/BuildingConstruction/Shared/RecipeComponent.gd"

# Source: kit/special_props.py :: bed
func _init() -> void:
	recipe_module = "res://tools/building_construction/BuildingConstruction/Props/SpecialRecipes.gd"
	recipe_function = "bed"
	parameter_order = ["name", "mats", "width", "length", "height", "medical", "parent"]
	recipe_parameters = {"width": 1.15, "length": 2.15, "height": 0.52, "medical": false}
