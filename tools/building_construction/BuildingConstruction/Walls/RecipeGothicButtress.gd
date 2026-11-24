@tool
extends "../Shared/RecipeComponent.gd"

func _init() -> void:
	recipe_module = "res://tools/building_construction/production/rule/GothicRecipes.gd"
	recipe_function = "gothic_flying_buttress"
	parameter_order = ["name", "mats", "projection", "height", "rib_radius", "parent"]
	recipe_parameters = {"projection": 2.4, "height": 4.5, "rib_radius": 0.24}
