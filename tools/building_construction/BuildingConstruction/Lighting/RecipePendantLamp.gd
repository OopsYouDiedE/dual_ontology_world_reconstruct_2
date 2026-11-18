@tool
extends "res://tools/building_construction/BuildingConstruction/Shared/RecipeComponent.gd"

# Source: kit/lighting.py :: pendant_lamp
func _init() -> void:
	recipe_module = "res://tools/building_construction/BuildingConstruction/Lighting/LightingRecipes.gd"
	recipe_function = "pendant_lamp"
	parameter_order = ["name", "mats", "drop", "radius", "parent", "light", "light_energy"]
	recipe_parameters = {"drop": 0.8, "radius": 0.27, "light": true, "light_energy": 10.0}
