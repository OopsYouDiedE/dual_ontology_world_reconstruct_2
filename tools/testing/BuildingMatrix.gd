extends RefCounted
## Exhaustive Cartesian product of declared states, using the production component factory.
const Factory := preload("res://tools/building_construction/BuildingConstruction/Shared/ComponentFactory.gd")
const ROOT := "res://tools/building_construction/BuildingConstruction/"
const Floor := preload("res://tools/building_construction/BuildingConstruction/Floors/ArchitectFloor.gd")

static func cases() -> Array:
	var result: Array = []
	for half in [false, true]:
		for door_open in [false, true]:
			for window_open in [false, true]:
				for lamp_on in [false, true]:
					for tiled in [false, true]:
						for stair_high in [false, true]:
							result.append({"id": "building_%02d" % result.size(), "half_wall": half, "door_open": door_open, "window_open": window_open, "lamp_on": lamp_on, "tiled": tiled, "stair_high": stair_high})
	return result

static func build(parent: Node3D, state: Dictionary) -> Array:
	var nodes: Array = []
	var wall := Factory.create(ROOT + "Walls/SmartWall3D.gd")
	wall.set("start_point", Vector3(-2.5, 0, -1.7))
	wall.set("end_point", Vector3(2.5, 0, -1.7))
	wall.set("wall_height", 1.1 if bool(state.get("half_wall", false)) else 2.8)
	wall.register_opening(2.9, 3.7, 1.05, 2.05)
	parent.add_child(wall)
	nodes.append(wall)
	var floor: Node3D
	if bool(state.get("tiled", false)):
		floor = Factory.create(ROOT + "Floors/RecipeTiledFloor.gd")
		floor.set("width", 6.0)
		floor.set("depth", 5.0)
	else:
		floor = Floor.build({"name": "Floor", "y": 0.0, "style": "parquet_wood", "polygons": [[[-3.0, -2.5], [3.0, -2.5], [3.0, 2.5], [-3.0, 2.5]]]})
	parent.add_child(floor)
	nodes.append(floor)
	var door := Factory.create(ROOT + "Doors/HingedDoor3D.gd")
	parent.add_child(door)
	door.position = Vector3(-2.4, 0, 0)
	door.set("current_angle", -85.0 if bool(state.get("door_open", false)) else 0.0)
	nodes.append(door)
	var window := Factory.create(ROOT + "Windows/HingedWindow3D.gd")
	window.set("min_angle", -75.0)
	window.set("max_angle", 75.0)
	parent.add_child(window)
	window.position = Vector3(0.8, 1.05, -1.54)
	window.set("current_angle", -55.0 if bool(state.get("window_open", false)) else 0.0)
	nodes.append(window)
	var stairs := Factory.create(ROOT + "Stairs/SmartStair3D.gd")
	stairs.set("start_point", Vector3(-0.2, 0, 0.4))
	stairs.set("end_point", Vector3(2.4, 1.7 if bool(state.get("stair_high", false)) else 0.7, 0.4))
	parent.add_child(stairs)
	nodes.append(stairs)
	var lamp := Factory.create(ROOT + "Lighting/RecipePendantLamp.gd")
	lamp.set("light", bool(state.get("lamp_on", true)))
	parent.add_child(lamp)
	lamp.position = Vector3(0, 2.5, 0)
	for light in lamp.find_children("*", "Light3D", true, false): light.visible = bool(state.get("lamp_on", true))
	nodes.append(lamp)
	return nodes
