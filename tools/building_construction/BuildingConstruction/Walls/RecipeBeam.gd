@tool
extends "../Shared/RecipeComponent.gd"

func _init() -> void:
	recipe_module = "res://tools/building_construction/production/rule/StructuralRecipes.gd"
	recipe_function = "beam"
	parameter_order = ["name", "mats", "length", "width", "depth", "parent"]
	recipe_parameters = {"length": 2.4, "width": 0.20, "depth": 0.30}
