@tool
extends "../Shared/RecipeComponent.gd"

func _init() -> void:
	recipe_module = "res://tools/building_construction/production/rule/StructuralRecipes.gd"
	recipe_function = "column"
	parameter_order = ["name", "mats", "height", "radius", "sides", "parent"]
	recipe_parameters = {"height": 2.8, "radius": 0.20, "sides": 12}
