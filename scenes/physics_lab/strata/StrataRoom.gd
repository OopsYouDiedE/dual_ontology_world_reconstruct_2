extends Node3D

const Kit := preload("res://scenes/physics_lab/shutter_loom/ShutterRoom.gd")
const STONE := Color("a9a594")
const DEEP := Color("596764")
const IRON := Color("45535b")
const BRASS := Color("bb8750")
const COPPER := Color("ce7952")
const CERAMIC := Color("a2c5c0")
const POWER := Color("fed88c")
const ALERT := Color("f58464")
const HEIGHT_SCALE := 0.0045
const RAIL_X := -0.95
const STAIR_X := 1.30
var book := Kit.new()
var deck := Node3D.new()
var core_token := Node3D.new()
var core: MeshInstance3D
var strain_meter: MeshInstance3D
var bank_meter: MeshInstance3D
var hatch_left: MeshInstance3D
var hatch_right: MeshInstance3D
var band_rails: Array[Array] = []
var couplers: Array[MeshInstance3D] = []
var cue_beacons: Array[MeshInstance3D] = []
var press_halos: Array[MeshInstance3D] = []
var anchor_y: Array[float] = []
var start_z: Array[float] = []


func height(cm: int) -> float:
	return cm * HEIGHT_SCALE


func build(terrain: Dictionary) -> void:
	add_child(deck)
	add_child(book)
	book.deck = deck
	for landing: Dictionary in terrain.landings:
		anchor_y.append(height(landing.height_cm))
		start_z.append(1.95 - 1.36 * landing.id)
	book.box(deck, Vector3(0, -0.44, -0.04), Vector3(5.20, 0.84, 5.57), DEEP.darkened(0.18))
	book.box(deck, Vector3(0, -0.79, -0.04), Vector3(5.31, 0.13, 5.68), BRASS.darkened(0.38))
	for i in terrain.landings.size():
		var landing: Dictionary = terrain.landings[i]
		build_landing(i, landing.name)
		if i < terrain.bands.size(): build_band(i, terrain.bands[i])
	var top := Vector3(-0.40, anchor_y[-1], start_z[-1] - 0.38)
	book.arch(top + Vector3(0, 1.13, -0.14), 0.70, 0.65, 0.105)
	for x in [-0.70, 0.70]:
		book.box(deck, top + Vector3(x, 0.59, -0.14), Vector3(0.18, 1.18, 0.28), STONE)
		horizontal(top + Vector3(x, 1.14, -0.14), Vector3(0.29, 0.13, 0.31), BRASS)
	hatch_left = book.box(deck, top + Vector3(-0.28, 0.55, -0.15), Vector3(0.56, 1.08, 0.13), IRON)
	hatch_right = book.box(deck, top + Vector3(0.28, 0.55, -0.15), Vector3(0.56, 1.08, 0.13), IRON)
	deck.add_child(core_token)
	book.box(core_token, Vector3(0, 0.057, 0), Vector3(0.48, 0.11, 0.42), IRON)
	book.drum(core_token, Vector3(0, 0.147, 0), 0.18, 0.08, BRASS)
	core = book.drum(core_token, Vector3(0, 0.34, 0), 0.143, 0.31, COPPER)
	book.drum(core_token, Vector3(0, 0.505, 0), 0.168, 0.057, BRASS)
	strain_meter = book.box(core_token, Vector3(-0.23, 0.26, 0.07), Vector3(0.052, 0.05, 0.052), ALERT, true)
	bank_meter = book.box(core_token, Vector3(0.23, 0.26, 0.07), Vector3(0.052, 0.05, 0.052), POWER, true)


func horizontal(p: Vector3, size: Vector3, tone: Color) -> void:
	book.box(deck, p, size, tone)


func build_landing(i: int, caption: String) -> void:
	var y := anchor_y[i]
	var z := start_z[i]
	var p := Vector3(0, y, z)
	horizontal(p - Vector3(0, 0.15, 0), Vector3(3.88, 0.24, 1.16), DEEP)
	horizontal(p - Vector3(0, 0.035, 0), Vector3(3.73, 0.08, 1.13), STONE)
	horizontal(p + Vector3(0, -0.07, 0.575), Vector3(3.91, 0.075, 0.05), BRASS)
	for x in [-1.80, 1.80]:
		horizontal(p + Vector3(x, 0.26, -0.41), Vector3(0.12, 0.54, 0.14), IRON)
		horizontal(p + Vector3(x, 0.55, -0.41), Vector3(0.17, 0.08, 0.18), BRASS)
	for n in 6:
		horizontal(p + Vector3(-1.60 + 0.64 * n, 0.012, 0.355), Vector3(0.48, 0.025, 0.035), DEEP)
	var press := Vector3(-0.29, y, z - 0.14)
	book.drum(deck, press + Vector3(0, 0.061, 0), 0.31, 0.12, BRASS.darkened(0.30))
	var ring := TorusMesh.new()
	ring.inner_radius = 0.24
	ring.outer_radius = 0.31
	press_halos.append(book.mesh(deck, ring, press + Vector3(0, 0.128, 0), book.mat(CERAMIC, true)))
	couplers.append(book.box(deck, p + Vector3(-1.54, 0.098, -0.13), Vector3(0.33, 0.18, 0.32), COPPER))
	cue_beacons.append(book.drum(deck, p + Vector3(1.72, 0.22, 0.23), 0.12, 0.39, ALERT, true))
	var title := Label3D.new()
	title.text = "%02d  /  %s" % [i, caption.to_upper()]
	title.font_size = 40
	title.pixel_size = 0.0046
	title.outline_size = 6
	title.modulate = Color("f6e4bd")
	deck.add_child(title)
	title.position = p + Vector3(0.25, 0.116, 0.47)
	title.rotation.x = -PI * 0.31


func build_band(i: int, band: Dictionary) -> void:
	var a := Vector3(RAIL_X, anchor_y[i], start_z[i])
	var b := Vector3(RAIL_X, anchor_y[i + 1], start_z[i + 1])
	var rails: Array[MeshInstance3D] = []
	for x in [-0.195, 0.195]:
		var offset := Vector3(x, 0, 0)
		rails.append(bar(a + offset, b + offset, 0.074, COPPER))
	var count := roundi((b.y - a.y) * (3.7 + band.rail_hand_strain_per_tick / 4.0))
	for tooth in count + 1:
		var p := a.lerp(b, float(tooth) / count)
		horizontal(p, Vector3(0.64, 0.038, 0.12), IRON)
	band_rails.append(rails)
	var stair_a := Vector3(STAIR_X, a.y, a.z)
	var stair_b := Vector3(STAIR_X, b.y, b.z)
	var steps := ceili((b.y - a.y) / 0.145)
	for n in range(1, steps):
		var t := float(n) / steps
		var p := stair_a.lerp(stair_b, t)
		p.x += stair_dogleg(t)
		horizontal(p - Vector3(0, 0.043, 0), Vector3(0.65, 0.091, 0.27), CERAMIC.darkened(0.28 + i * 0.05))
		horizontal(p + Vector3(0, 0.011, 0.105), Vector3(0.59, 0.022, 0.027), STONE)
	for side in [-1.0, 1.0]:
		var xoff := Vector3(side * 0.36, -0.07, 0)
		var middle := stair_a.lerp(stair_b, 0.5) + Vector3(stair_dogleg(0.5), 0, 0)
		bar(stair_a + xoff, middle + xoff, 0.065, DEEP)
		bar(middle + xoff, stair_b + xoff, 0.065, DEEP)
	for x in [-1.81, 1.77]:
		var foot := Vector3(x, a.y - 0.10, a.z - 0.49)
		var head := Vector3(x, b.y - 0.10, b.z - 0.49)
		bar(foot, head, 0.16, DEEP)
		bar(foot, head + Vector3(0, -0.21, 0.45), 0.087, BRASS.darkened(0.28))
	bar(Vector3(-1.81, a.y + 0.68, a.z - 0.57), Vector3(1.77, a.y + 0.68, a.z - 0.57), 0.058, IRON)


func bar(a: Vector3, b: Vector3, width: float, color: Color) -> MeshInstance3D:
	var delta := b - a
	var shape := book.box(deck, a.lerp(b, 0.5), Vector3(width, delta.length(), width), color)
	shape.quaternion = Quaternion(Vector3.UP, delta.normalized())
	return shape


func stair_dogleg(progress: float) -> float:
	return 0.50 * (1.0 - absf(2.0 * progress - 1.0))


func draw(state: Dictionary) -> void:
	var landing: int = state.landing
	var target := mini(landing + 1, anchor_y.size() - 1)
	var y := height(state.height_cm)
	var t := clampf((y - anchor_y[landing]) / maxf(0.01, anchor_y[target] - anchor_y[landing]), 0.0, 1.0)
	var x := -0.29
	if state.route == "rail": x = RAIL_X
	if state.route == "stairs": x = STAIR_X + stair_dogleg(t)
	var z := lerpf(start_z[landing], start_z[target], t)
	if state.route == "anchor": z -= 0.14
	if state.mode == "return": x = -1.81
	core_token.position = Vector3(x, y + 0.04, z)
	core.material_override = book.mat(COPPER if state.form == "copper" else CERAMIC, state.circuit == "hatch")
	core.rotation.y = state.tick * 0.075 if state.mode == "thermal_press" else 0.0
	set_fill(strain_meter, float(state.strain) / state.strain_hard)
	set_fill(bank_meter, float(state.charge) / state.charge_max)
	for i in band_rails.size():
		for rail: MeshInstance3D in band_rails[i]:
			rail.material_override = book.mat(POWER if state.circuit == "rail" and i == landing else COPPER, state.circuit == "rail" and i == landing)
	for i in couplers.size():
		couplers[i].material_override = book.mat(POWER if state.circuit == "regenerative" and i == landing else IRON, state.circuit == "regenerative" and i == landing)
		press_halos[i].visible = state.mode == "thermal_press" and i == landing
		cue_beacons[i].visible = not state.warnings.is_empty() and i == landing
	var separation := 0.54 if state.mode == "won" else 0.28
	hatch_left.position.x = -0.40 - separation
	hatch_right.position.x = -0.40 + separation


func set_fill(needle: MeshInstance3D, ratio: float) -> void:
	needle.scale.y = 0.03 + 0.43 * clampf(ratio, 0.0, 1.0)
	needle.position.y = 0.09 + needle.scale.y * 0.5
