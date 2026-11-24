@tool
extends "../Shared/RecipeComponent.gd"

func _init() -> void:
	recipe_module = "res://tools/building_construction/production/rule/GothicRecipes.gd"
	recipe_function = "gothic_pointed_rib"
	parameter_order = ["name", "mats", "dx", "dy", "rise", "radius", "segments", "parent"]
	recipe_parameters = {"dx": 2.1, "dy": 0.0, "rise": 1.6, "radius": 0.12, "segments": 12}
