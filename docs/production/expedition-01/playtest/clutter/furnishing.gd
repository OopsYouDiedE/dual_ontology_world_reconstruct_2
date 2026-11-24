extends RefCounted
## Workshop/dispatch prototype. Structural parts share the stress box/support contract.
const Layout = preload('res://layout.gd')

static func part(items: Array, id: String, kind: String, station: String,
		x: float, bottom: float, z: float, size: Vector3, parent: String = '', layer: int = 1) -> void:
	var item := Layout.box(id, Vector3(x, bottom + size.y / 2, z), size, parent, layer)
	item['kind'] = kind
	item['station'] = station
	items.append(item)

static func generate(seed: int, room_id: String, density: float, max_layers: int) -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed ^ room_id.sha256_text().substr(0, 12).hex_to_int()
	# Hand-authored service relationships stay legible; seed changes who gets which wall and the dressing.
	var side := -1.0 if rng.randf() < 0.5 else 1.0
	var work_z := side * 3.49
	var dispatch_z := -side * 3.49
	var work_x := -2.55
	var dispatch_x := 2.55
	var items: Array = []
	part(items, 'bench_pedestal', 'pedestal', 'workshop', work_x, 0, work_z, Vector3(1.26,0.82,0.66))
	part(items, 'bench_top', 'worktop', 'workshop', work_x, 0.82, work_z, Vector3(2.62,0.11,0.86), 'bench_pedestal', 2)
	part(items, 'tool_cupboard', 'tool_cabinet', 'workshop', -0.42, 0, side * 3.62, Vector3(1.18,1.95,0.66))
	part(items, 'work_stool', 'stool_base', 'workshop', -0.83, 0, side * 2.44, Vector3(0.30,0.43,0.30))
	part(items, 'stool_seat', 'stool_seat', 'workshop', -0.83, 0.43, side * 2.44, Vector3(0.44,0.08,0.44), 'work_stool', 2)
	part(items, 'dispatch_drawers', 'drawers', 'dispatch', dispatch_x, 0, dispatch_z, Vector3(1.70,0.88,0.70))
	part(items, 'dispatch_top', 'countertop', 'dispatch', dispatch_x, 0.88, dispatch_z, Vector3(1.90,0.10,0.84), 'dispatch_drawers', 2)
	part(items, 'stock_cupboard', 'stock_cabinet', 'dispatch', 0.68, 0, -side * 3.64, Vector3(1.02,1.72,0.62))
	# Portable dressing is confined to two active surfaces and one stock bay, not spread over the floor.
	var tray_x := work_x + rng.randf_range(-0.69, -0.44)
	var parcel_x := dispatch_x + rng.randf_range(0.22, 0.50)
	if rng.randf() < density:
		part(items, 'tool_tray', 'tray', 'workshop', tray_x, 0.93, work_z + side * 0.12, Vector3(0.54,0.12,0.34), 'bench_top', 3)
	if rng.randf() < density:
		part(items, 'outgoing_parcel', 'parcel', 'dispatch', parcel_x, 0.98, dispatch_z, Vector3(0.41,0.23,0.35), 'dispatch_top', 3)
	if rng.randf() < density:
		part(items, 'stock_crate', 'crate', 'dispatch', -0.58, 0, -side * 3.58, Vector3(0.70,0.37,0.59))
		if max_layers > 1:
			part(items, 'stock_crate_small', 'crate', 'dispatch', -0.58, 0.37, -side * 3.58, Vector3(0.50,0.27,0.43), 'stock_crate', 2)
	return {'schema': 'clutter-layout/v1', 'mode': 'furnished', 'room_id': room_id, 'seed': seed,
		'room_size': [10, 3.2, 8], 'door_width': Layout.DOOR, 'route_clear_half_width': Layout.CLEAR_HALF,
		'density': density, 'max_layers': max_layers, 'items': items,
		'route': [[-6.2, 0, 0], [6.2, 0, 0]],
		'stations': [
			{'id': 'workshop', 'function': 'Tool prep & repair', 'target': 'bench_top',
			 'route': [[work_x, 0, 0], [work_x, 0, side * 2.44]]},
			{'id': 'dispatch', 'function': 'Sort & dispatch', 'target': 'dispatch_top',
			 'route': [[dispatch_x, 0, 0], [dispatch_x, 0, -side * 2.44]]},
		]}
