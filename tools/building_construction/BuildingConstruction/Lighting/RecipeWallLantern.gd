@tool
extends "res://tools/building_construction/BuildingConstruction/Shared/RecipeComponent.gd"

# Source: kit/lighting.py :: wall_lantern
func _init() -> void:
	recipe_module = "res://tools/building_construction/BuildingConstruction/Lighting/LightingRecipes.gd"
	recipe_function = "wall_lantern"
	parameter_order = ["name", "mats", "height", "parent", "light", "light_energy"]
	recipe_parameters = {"height": 0.65, "light": true, "light_energy": 12.0}
