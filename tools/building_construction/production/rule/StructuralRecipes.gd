@tool
extends RefCounted

const Geo = preload("../../BuildingConstruction/Shared/RecipeGeometry.gd")

static func gen_beam(label: String, mats: Dictionary, length: float, width: float, depth: float, parent = null):
	var group = Geo.gen_group(label, [0, 0, 0], 0, parent)
	Geo.gen_beam("Section", [-length / 2.0, 0, depth / 2.0], [length / 2.0, 0, depth / 2.0], width, depth, mats.wood, group, 0.006)
	return group

static func gen_column(label: String, mats: Dictionary, height: float, radius: float, sides: int, parent = null):
	var group = Geo.gen_group(label, [0, 0, 0], 0, parent)
	var cap := minf(height * 0.15, radius * 0.4)
	Geo.gen_cylinder("Shaft", [0, 0, height / 2.0], radius, height - cap * 2.0, mats.stone, sides, group)
	Geo.gen_cylinder("Base", [0, 0, cap / 2.0], radius * 1.25, cap, mats.stone_dark, sides, group)
	Geo.gen_cylinder("Capital", [0, 0, height - cap / 2.0], radius * 1.2, cap, mats.stone, sides, group)
	return group
