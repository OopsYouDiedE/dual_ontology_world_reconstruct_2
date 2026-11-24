@tool
extends "../Shared/RecipeComponent.gd"

func _init() -> void:
	recipe_module = "res://tools/building_construction/production/rule/GothicRecipes.gd"
	recipe_function = "gothic_vault_bay"
	parameter_order = ["name", "mats", "span_x", "span_y", "spring_height", "crown_rise", "rib_radius", "web_res", "parent"]
	recipe_parameters = {"span_x": 4.2, "span_y": 4.2, "spring_height": 3.6, "crown_rise": 1.8, "rib_radius": 0.11, "web_res": 11}
