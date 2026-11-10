@tool
extends "res://tools/building_construction/BuildingConstruction/Shared/RecipeComponent.gd"

# Source: kit/industrial_props.py :: caged_lamp
func _init() -> void:
	recipe_module = "res://tools/building_construction/BuildingConstruction/Props/IndustrialRecipes.gd"
	recipe_function = "caged_lamp"
	parameter_order = ["name", "mats", "height", "light_energy", "parent"]
	recipe_parameters = {"height": 0.5, "light_energy": 22}
