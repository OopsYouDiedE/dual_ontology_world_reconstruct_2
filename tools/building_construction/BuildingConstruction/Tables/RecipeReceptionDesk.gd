@tool
extends "res://tools/building_construction/BuildingConstruction/Shared/RecipeComponent.gd"

# Source: kit/furniture.py :: reception_desk
func _init() -> void:
	recipe_module = "res://tools/building_construction/BuildingConstruction/Tables/FurnitureRecipes.gd"
	recipe_function = "reception_desk"
	parameter_order = ["name", "mats", "width", "depth", "height", "panels", "details", "parent"]
	recipe_parameters = {"width": 2.35, "depth": 0.95, "height": 1.08, "panels": 3, "details": true}
