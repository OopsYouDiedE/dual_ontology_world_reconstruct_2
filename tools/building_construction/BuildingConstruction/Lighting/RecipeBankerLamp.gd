@tool
extends "res://tools/building_construction/BuildingConstruction/Shared/RecipeComponent.gd"

# Source: kit/lighting.py :: banker_lamp
func _init() -> void:
	recipe_module = "res://tools/building_construction/BuildingConstruction/Lighting/LightingRecipes.gd"
	recipe_function = "banker_lamp"
	parameter_order = ["name", "mats", "height", "width", "parent", "light", "light_energy"]
	recipe_parameters = {"height": 0.55, "width": 0.43, "light": true, "light_energy": 8.0}
