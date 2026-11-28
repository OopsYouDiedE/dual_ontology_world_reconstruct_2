extends SceneTree
## One-time migration: writes the Public Hall's Gothic architecture, pendulum, lighting and
## furniture into scenes/levels/structures/public_nave.tscn as editable component nodes
## (scenes/components/hall/*), reproducing the former procedural PublicHallGothic exactly.
## After this the scene is the source of truth: edit it in the Godot editor.
##   Godot --headless --path . -s res://tools/building_construction/migrate_public_hall.gd

const SCENE := "res://scenes/levels/structures/public_nave.tscn"
const H := "res://scenes/components/hall/"
const Anchor := preload("res://scenes/components/structure/LevelAnchor3D.gd")

const SPRING_H := 6.0
const WING_ROOF := 5.2
const MIN_X := 11.0
const MAX_X := 21.0
const MIN_Z := 5.0
const MAX_Z := 25.0
const BAYS := 5
const BAY := 4.0
const CX := 16.0
const PENDULUM := Vector3(16, 0, 17)
const NAVE_COT := Vector3(12.45, 0, 22.6)
const WAKE_BED := Vector3(7.65, 0, 18.45)

var scene_root: Node3D

func _initialize() -> void:
	var root_node := (load(SCENE) as PackedScene).instantiate() as Node3D
	scene_root = root_node
	var old := root_node.get_node_or_null("PublicHallGothic")
	if old:
		root_node.remove_child(old)
		old.free()
	var hall: Node3D = load("res://scenes/rogue_view/render/PublicHallGothic.gd").new()
	hall.name = "PublicHallGothic"
	root_node.add_child(hall)
	hall.owner = root_node
	build(hall)
	var packed := PackedScene.new()
	var err := packed.pack(root_node)
	if err == OK:
		err = ResourceSaver.save(packed, SCENE)
	print("MIGRATE_PUBLIC_HALL %s nodes=%d" % [error_string(err), hall.find_children("*", "", true, false).size()])
	root_node.free()
	quit(0 if err == OK else 1)

func group(parent: Node, title: String, pos := Vector3.ZERO) -> Node3D:
	var n := Node3D.new()
	n.name = title
	n.position = pos
	parent.add_child(n)
	n.owner = scene_root
	return n

func piece(parent: Node, script: String, title: String, pos: Vector3, props := {}, yaw := 0.0) -> Node3D:
	var n: Node3D = load(H + script + ".gd").new()
	n.name = title
	n.position = pos
	n.rotation.y = yaw
	for k in props:
		n.set(k, props[k])
	parent.add_child(n, true)
	n.owner = scene_root
	return n

func furniture(parent: Node, title: String, pos: Vector3, yaw: float, props: Dictionary) -> Node3D:
	return piece(parent, "HallFurniture3D", title, pos, props, yaw)

func glb(parent: Node, title: String, file: String, pos: Vector3, yaw: float, scale: float, preset: String) -> Node3D:
	return furniture(parent, title, pos, yaw, {"glb": "res://assets/furniture/kaykit_cc0/%s.glb" % file, "uniform_scale": scale, "preset": preset})

func pool(parent: Node, title: String, pos: Vector3, hex: String, energy: float, reach: float) -> Node3D:
	return piece(parent, "HallLight3D", title, pos, {"mode": "pool", "color": Color(hex), "energy": energy, "reach": reach})

func anchor(parent: Node, id: String, pos: Vector3) -> void:
	var a: Node3D = Anchor.new()
	a.anchor_id = id
	a.name = id.to_pascal_case()
	a.position = pos
	parent.add_child(a)
	a.owner = scene_root

func build(hall: Node3D) -> void:
	# ── Nave architecture ────────────────────────────────────────────────────
	var arch := group(hall, "Nave")
	piece(arch, "GothicVault3D", "Vault", Vector3(MIN_X + 0.3, 0, MIN_Z), {"size": Vector2(MAX_X - MIN_X - 0.6, MAX_Z - MIN_Z), "bays": BAYS})
	var piers := group(arch, "Piers")
	for iz in BAYS + 1:
		var pz := MIN_Z + iz * BAY
		piece(piers, "GothicPier3D", "PierW%d" % iz, Vector3(MIN_X + 0.59, 0, pz), {"inward": 1.0})
		piece(piers, "GothicPier3D", "PierE%d" % iz, Vector3(MAX_X - 0.59, 0, pz), {"inward": -1.0})
	var bays := group(arch, "SideBays")
	for side_i in 2:
		var west := side_i == 0
		var wx := MIN_X + 0.34 if west else MAX_X - 0.34
		var inward := 1.0 if west else -1.0
		var tag := "W" if west else "E"
		for bi in BAYS:
			var z0 := MIN_Z + bi * BAY
			if bi in [2, 3]:
				piece(bays, "GothicOpenArch3D", "OpenArch%s%d" % [tag, bi], Vector3(wx, 0, z0), {"length": BAY, "inward": inward})
				piece(bays, "GothicBlindArcade3D", "Triforium%s%d" % [tag, bi], Vector3(wx, 0, z0 + BAY * 0.5),
					{"length": BAY - 0.9, "bottom": 4.95, "top": 5.86, "count": 4}, atan2(inward, 0.0))
			else:
				piece(bays, "GothicLancetBay3D", "Lancet%s%d" % [tag, bi], Vector3(wx, 0, z0), {"length": BAY, "inward": inward, "variant": (bi + side_i) % 4})
	var gables := group(arch, "Gables")
	piece(gables, "GothicGableWall3D", "NorthGable", Vector3(MIN_X, 0, MIN_Z + 0.04), {"width": MAX_X - MIN_X, "inward": 1.0, "north": true, "portals": true, "rose_height": 6.28})
	piece(gables, "GothicGableWall3D", "SouthGable", Vector3(MIN_X, 0, MAX_Z - 0.04), {"width": MAX_X - MIN_X, "inward": -1.0, "north": false, "portals": false, "rose_height": 6.85})
	piece(gables, "GothicBlindArcade3D", "NorthArcade", Vector3(CX, 0, MIN_Z + 0.04), {"length": MAX_X - MIN_X - 1.6, "bottom": 3.30, "top": 4.15, "count": 10}, 0.0)
	piece(gables, "GothicBlindArcade3D", "SouthArcade", Vector3(CX, 0, MAX_Z - 0.04), {"length": MAX_X - MIN_X - 1.6, "bottom": 2.85, "top": 4.55, "count": 8}, PI)
	var oculi := group(arch, "Oculi")
	for bi in BAYS:
		var oz := MIN_Z + (bi + 0.5) * BAY
		piece(oculi, "GothicOculus3D", "OculusW%d" % bi, Vector3(MIN_X + 0.36, SPRING_H + 1.15, oz), {}, PI * 0.5)
		piece(oculi, "GothicOculus3D", "OculusE%d" % bi, Vector3(MAX_X - 0.36, SPRING_H + 1.15, oz), {}, -PI * 0.5)

	# ── Floor ────────────────────────────────────────────────────────────────
	var floor_g := group(hall, "Floor")
	var x0 := MIN_X + 0.59
	piece(floor_g, "NavePaving3D", "Paving", Vector3(x0, 0, MIN_Z), {"size": Vector2(MAX_X - MIN_X - 1.18, MAX_Z - MIN_Z), "bays": BAYS, "gap": Rect2(14 - x0, 15 - MIN_Z, 4, 4)})
	for s: float in [-1.0, 1.0]:
		piece(floor_g, "HallRug3D", "Runner%s" % ("W" if s < 0 else "E"), Vector3(CX + s * 3.1, 0, (MIN_Z + MAX_Z) * 0.5), {"size": Vector2(1.18, MAX_Z - MIN_Z)})
	var carpet := {"center_height": 0.008, "thickness": 0.014, "edge_offset": 0.96, "edge_size": Vector2(0.035, 0.010), "edge_height": 0.010, "edge_material": "brass"}
	piece(floor_g, "HallRug3D", "NorthCarpet", Vector3(CX, 0, MIN_Z + 4.90), carpet.merged({"size": Vector2(1.90, 8.20)}))
	piece(floor_g, "HallRug3D", "SouthCarpet", Vector3(CX, 0, PENDULUM.z + 5.10), carpet.merged({"size": Vector2(1.90, 4.40)}))

	# ── Pendulum ─────────────────────────────────────────────────────────────
	piece(hall, "FoucaultPendulum3D", "FoucaultPendulum", PENDULUM, {"well_cells": 4})

	# ── Lighting ─────────────────────────────────────────────────────────────
	var lights := group(hall, "Lighting")
	for bi in BAYS:
		var lz := MIN_Z + (bi + 0.5) * BAY
		piece(lights, "HallLantern3D", "LanternW%d" % bi, Vector3(MIN_X + 0.64, SPRING_H - 0.5, lz))
		piece(lights, "HallLantern3D", "LanternE%d" % bi, Vector3(MAX_X - 0.64, SPRING_H - 0.5, lz))
	for spec in [["FloorLampNW", 1.0, -1.0, 2.8, 9.5], ["FloorLampNE", 1.0, 1.0, 2.8, 9.5], ["FloorLampSW", 2.0, -1.0, 2.6, 9.0], ["FloorLampSE", 2.0, 1.0, 2.6, 9.0]]:
		piece(lights, "HallFloorLamp3D", spec[0], Vector3(CX + 3.75 * spec[2], 0, MIN_Z + BAY * spec[1]), {"night_energy": spec[3], "reach": spec[4]})
	for bi in BAYS:
		piece(lights, "HallLight3D", "DayFill%d" % bi, Vector3(CX, SPRING_H + 1.4, MIN_Z + (bi + 0.5) * BAY),
			{"mode": "daylight", "color": Color("e8eff8") if bi % 2 == 0 else Color("fff0d4"), "day_energy": 1.15, "reach": 17.0, "attenuation": 1.15, "specular": 0.0})
	piece(lights, "HallLight3D", "FloorBounce", Vector3(CX, 2.6, (MIN_Z + MAX_Z) * 0.5),
		{"mode": "daylight", "color": Color("f6ebd6"), "day_energy": 0.95, "reach": 24.0, "attenuation": 1.2, "specular": 0.0})
	for i in 3:
		piece(lights, "HallLight3D", "NaveFill%d" % i, Vector3(CX, 4.1, lerpf(MIN_Z + 2.5, MAX_Z - 2.5, i / 2.0)),
			{"mode": "static", "color": Color("ffe9cb"), "energy": 0.52, "reach": 12.0, "attenuation": 1.25})

	# ── Watch alcove (nave cot) and the captain's wake bed lamp ──────────────
	var alcove := group(hall, "WatchCotAlcove")
	piece(alcove, "HallCot3D", "NaveCot", NAVE_COT)
	glb(alcove, "CotStool", "stool", NAVE_COT + Vector3(1.15, 0, -0.25), 0.2, 0.74, "oak_aged")
	glb(alcove, "CotCandles", "candle_triple", NAVE_COT + Vector3(1.15, 0.48, -0.25), 0.15, 0.56, "brass_antique")
	pool(alcove, "CotGlow", NAVE_COT + Vector3(1.15, 0.85, -0.25), "ffc77d", 1.15, 3.6)
	furniture(alcove, "WakeBedLamp", WAKE_BED + Vector3(0.55, 0, -0.78), 0.0, {"recipe": "Lighting/CagedLamp"})
	pool(alcove, "WakeBedGlow", WAKE_BED + Vector3(0.6, 0.55, -0.85), "ffc27a", 1.3, 3.2)

	# ── Watch officer's study (north-west) ───────────────────────────────────
	var study := group(hall, "WatchStudy")
	var lectern := group(study, "EssenceCalibrationLectern", Vector3(PENDULUM.x - 2.65, 0, MIN_Z + 3.40))
	furniture(lectern, "Desk", Vector3.ZERO, PI, {"recipe": "Tables/ReceptionDesk", "params": {"width": 1.80}, "preset": "walnut_varnish", "station_size": Vector2(1.80, 0.90), "station_height": 1.08})
	furniture(lectern, "BankerLamp", Vector3(-0.55, 1.08, 0), 0.0, {"recipe": "Lighting/BankerLamp", "params": {"light_energy": 1.3}})
	var map := furniture(lectern, "Schematic", Vector3(0.18, 1.13, 0.14), 0.0, {"recipe": "Props/Schematic", "params": {"width": 0.95, "height": 0.56}})
	map.rotation.x = -1.28
	glb(lectern, "Candles", "candle_triple", Vector3(0.68, 1.08, -0.12), 0.3, 0.68, "brass_antique")
	glb(study, "OfficerChair", "chair", Vector3(PENDULUM.x - 2.65, 0, MIN_Z + 4.35), PI, 0.76, "walnut_varnish")
	glb(study, "ArchiveShelf", "shelf_large", Vector3(PENDULUM.x - 4.05, 0, MIN_Z + 6.20), PI * 0.5, 0.82, "walnut_varnish")

	# ── Council & reading salon (north-east) ─────────────────────────────────
	var salon := group(hall, "CouncilSalon")
	var px := PENDULUM.x
	glb(salon, "CouncilTable", "table_long", Vector3(px + 3.55, 0, MIN_Z + 5.75), PI * 0.5, 0.78, "walnut_varnish")
	glb(salon, "CouncilCandles", "candle_triple", Vector3(px + 3.55, 0.74, MIN_Z + 5.75), 0.1, 0.64, "brass_antique")
	glb(salon, "ChairW1", "chair", Vector3(px + 2.72, 0, MIN_Z + 5.20), PI * 0.5, 0.76, "walnut_varnish")
	glb(salon, "ChairW2", "chair", Vector3(px + 2.72, 0, MIN_Z + 6.30), PI * 0.5, 0.76, "walnut_varnish")
	glb(salon, "ChairN", "chair", Vector3(px + 3.55, 0, MIN_Z + 4.35), 0.0, 0.76, "walnut_varnish")
	glb(salon, "InstrumentTrunk", "chest", Vector3(px + 3.85, 0, MIN_Z + 3.25), -PI * 0.5, 0.76, "oak_aged")
	pool(salon, "SalonGlow", Vector3(px + 3.40, 1.55, MIN_Z + 5.75), "ffcf8c", 1.6, 4.8)

	# ── Side wings: shells ───────────────────────────────────────────────────
	for side: int in [-1, 1]:
		var wing := group(hall, "WestWing" if side < 0 else "EastWing")
		var shell := group(wing, "Shell")
		var cx := 16.0 + 7.5 * side
		var roof_x := cx - side * 0.15
		for z: float in [13.0, 21.0]:
			piece(shell, "HallBox3D", "EndWall%d" % int(z), Vector3(roof_x, WING_ROOF * 0.5, z), {"size": Vector3(5.3, WING_ROOF, 0.12), "material_key": "wall"})
			piece(shell, "HallBox3D", "EndDado%d" % int(z), Vector3(cx, 0.6, z + (0.08 if z == 13.0 else -0.08)), {"size": Vector3(5, 1.2, 0.12), "material_key": "wood"})
		for bay in 2:
			var z0 := 13.0 + bay * 4.0
			piece(shell, "GothicLancetBay3D", "Lancet%d" % bay, Vector3(cx + 2.5 * side, 0, z0), {"length": 4.0, "inward": float(-side), "variant": bay + (2 if side > 0 else 0), "window_top": WING_ROOF})
		piece(shell, "HallBox3D", "Roof", Vector3(roof_x, WING_ROOF, 17), {"size": Vector3(5.3, 0.18, 8), "material_key": "vault"})
		for z: float in [13.2, 17.0, 20.8]:
			piece(shell, "HallBox3D", "RoofRib", Vector3(cx, WING_ROOF - 0.17, z), {"size": Vector3(5, 0.24, 0.23), "material_key": "rib"})
		piece(shell, "GothicWingPartition3D", "Partition", Vector3(cx, 0, 17), {"side": side})

	# ── West wing: dormitory & infirmary ─────────────────────────────────────
	var dorm := group(hall.get_node("WestWing"), "Dormitory")
	furniture(dorm, "LinenCabinet", Vector3(9.65, 0, 20.62), PI, {"recipe": "Cabinets/LinenCabinet", "station_size": Vector2(1.45, 0.68), "station_height": 1.9})
	furniture(dorm, "Washstand", Vector3(6.53, 0, 16.90), PI / 2, {"recipe": "Props/Washstand"})
	furniture(dorm, "MedicineCabinet", Vector3(7.35, 0, 13.38), 0.0, {"recipe": "Cabinets/MedicineCabinet"})
	furniture(dorm, "CotScreen", Vector3(12.25, 0, 21.55), PI * 0.5, {"recipe": "Props/Screen"})
	furniture(dorm, "ArchScreen", Vector3(10.55, 0, 13.85), PI * 0.5, {"recipe": "Props/Screen"})
	var n := 1
	for z: float in [14.25, 15.85, 18.45, 20.0]:
		furniture(dorm, "Bed%d" % n, Vector3(7.65, 0, z), PI / 2, {"recipe": "Beds/Bed", "params": {"medical": z < 17.0}, "station_size": Vector2(2.15, 1.15), "station_height": 0.52})
		n += 1
	glb(dorm, "Stool1", "stool", Vector3(6.65, 0, 15.05), 0.1, 0.70, "oak_aged")
	glb(dorm, "Stool2", "stool", Vector3(6.65, 0, 19.22), -0.1, 0.70, "oak_aged")
	pool(dorm, "DormGlow", Vector3(9.2, 2.45, 16.2), "c8e2ff", 3.2, 6.2)

	# ── Bay 4 east: scholar's chalkboard alcove ──────────────────────────────
	var scholar := group(hall, "ScholarAlcove")
	furniture(scholar, "Chalkboard", Vector3(20.42, 0.45, 22.6), -PI * 0.5, {"recipe": "Props/Chalkboard"})
	furniture(scholar, "StudyTable", Vector3(19.25, 0, 22.6), PI / 2, {"recipe": "Tables/Table", "params": {"width": 2.0}, "station_size": Vector2(1.35, 2.0), "station_height": 0.75})
	furniture(scholar, "BankerLamp", Vector3(19.35, 0.75, 21.95), 0.0, {"recipe": "Lighting/BankerLamp", "params": {"light_energy": 1.1}})
	glb(scholar, "Chair1", "chair", Vector3(18.35, 0, 22.1), PI * 0.5, 0.76, "walnut_varnish")
	glb(scholar, "Chair2", "chair", Vector3(18.35, 0, 23.1), PI * 0.5, 0.76, "walnut_varnish")

	# ── East wing: refectory & hearth kitchen ────────────────────────────────
	var refectory := group(hall.get_node("EastWing"), "Refectory")
	furniture(refectory, "WorkCounter", Vector3(22.65, 0, 13.52), 0.0, {"recipe": "Tables/WorkCounter", "station_size": Vector2(1.95, 0.72), "station_height": 0.94})
	furniture(refectory, "CrockeryShelf", Vector3(25.75, 0, 18.7), -PI / 2, {"recipe": "Props/CrockeryShelf"})
	furniture(refectory, "RefectoryTable", Vector3(24.15, 0, 18.7), PI / 2, {"recipe": "Tables/Table", "params": {"width": 3.4}, "station_size": Vector2(2.05, 3.4), "station_height": 0.75})
	glb(refectory, "TableCandles", "candle_triple", Vector3(24.15, 0.75, 18.7), 0.0, 0.70, "brass_antique")
	for dx: float in [-0.78, 0.78]:
		furniture(refectory, "Bench", Vector3(24.15 + dx, 0, 18.7), PI / 2, {"recipe": "Chairs/Bench", "params": {"width": 3.1}})
	var stove := Vector3(25.35, 0, 14.55)
	var hearth := group(refectory, "Hearth", stove)
	furniture(hearth, "Stove", Vector3.ZERO, -PI * 0.5, {"recipe": "Props/Stove", "params": {"width": 2.0}, "station_size": Vector2(0.85, 2.05), "station_height": 0.95})
	furniture(hearth, "KitchenHood", Vector3.UP * 1.45, -PI * 0.5, {"recipe": "Props/KitchenHood"})
	piece(hearth, "HallBox3D", "Embers", Vector3(-0.435, 0.5, 0.0), {"size": Vector3(0.06, 0.36, 1.44), "material_key": "embers"})
	for i in 9:
		piece(hearth, "HallBox3D", "GrateBar", Vector3(-0.48, 0.5, (i - 4) * 0.16), {"size": Vector3(0.05, 0.41, 0.034), "material_key": "lead"})
	pool(hearth, "HearthGlow", Vector3(-0.85, 1.02, 0.0), "ff9e50", 5.2, 7.8)
	pool(refectory, "TableGlow", Vector3(22.4, 1.65, 18.7), "ffc788", 2.1, 5.2)
	glb(refectory, "SupplyCrates", "crates_stacked", Vector3(21.65, 0, 20.35), 0.15, 0.70, "oak_aged")

	# ── North apse: library alcoves ──────────────────────────────────────────
	var library := group(hall, "NorthLibrary")
	for x: float in [13.1, 18.9]:
		var t := "W" if x < 16 else "E"
		furniture(library, "Bookshelf" + t, Vector3(x, 0, 5.38), 0.0, {"recipe": "Cabinets/Bookshelf", "params": {"width": 1.95, "bays": 3, "shelves": 5}})
		furniture(library, "Bench" + t, Vector3(x, 0, 6.65), 0.0, {"recipe": "Chairs/Bench", "params": {"width": 1.65}})
	pool(library, "LibraryGlow", Vector3(16, 2.6, 7.2), "ffdb9d", 2.4, 6.2)

	# ── Gameplay anchors ─────────────────────────────────────────────────────
	var anchors := scene_root.get_node_or_null("Anchors")
	if anchors == null:
		anchors = group(scene_root, "Anchors")
	for id in ["spawn", "cot", "north_gate", "lectern"]:
		var existing := anchors.get_node_or_null(id.to_pascal_case())
		if existing:
			anchors.remove_child(existing)
			existing.free()
	anchor(anchors, "spawn", Vector3(16, 0, 24.4))
	anchor(anchors, "cot", WAKE_BED)
	anchor(anchors, "north_gate", Vector3(CX, 0, MIN_Z + 0.45))
	anchor(anchors, "lectern", Vector3(PENDULUM.x - 2.65, 0, MIN_Z + 3.40))
