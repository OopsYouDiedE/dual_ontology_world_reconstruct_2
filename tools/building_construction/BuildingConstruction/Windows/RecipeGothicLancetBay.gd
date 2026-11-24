@tool
extends "../Shared/RecipeComponent.gd"

func _init() -> void:
	recipe_module = "res://tools/building_construction/production/rule/GothicRecipes.gd"
	recipe_function = "gothic_lancet_bay"
	parameter_order = ["name", "mats", "width", "height", "sill_height", "bay_variant", "parent"]
	recipe_parameters = {"width": 3.0, "height": 4.65, "sill_height": 1.15, "bay_variant": 0}
