@tool
extends "res://tools/building_construction/BuildingConstruction/Shared/RecipeComponent.gd"

# Source: kit/special_props.py :: vessel
func _init() -> void:
	recipe_module = "res://tools/building_construction/BuildingConstruction/Props/SpecialRecipes.gd"
	recipe_function = "vessel"
	parameter_order = ["name", "mats", "radius", "height", "kind", "parent"]
	recipe_parameters = {"radius": 0.12, "height": 0.3, "kind": "bottle"}
