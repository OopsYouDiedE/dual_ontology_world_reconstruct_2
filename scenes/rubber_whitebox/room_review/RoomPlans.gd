extends RefCounted
## Metre-scale review plans, one per Night Watch stage. Coordinates are (X, Z).
## Fixtures are solid clearance envelopes by default, with some raised or floor-only.

const ORDER: Array[String] = ["intake", "returns", "exchange", "wash", "lift", "airlock", "shutter", "hall", "darkroom", "relay", "meridian"]

static func plan(id: String) -> Dictionary:
	match id:
		"intake":
			return _room(Vector2(12, 13), 3.7, 0.0, "Read the issue counter from the entry. Leave past the returned-packet rack.", [], [
				_fixture("ISSUE HATCH", -3.0, -1.05, 3.45, 1.3, 1.35),
				_fixture("ISSUE CABINET", -3.05, -3.05, 3.6, 0.85, 2.5),
				_fixture("RETURNED PACKETS", 3.0, -2.4, 2.45, 1.15, 1.52),
				_fixture("QUEUE RAIL", -2.75, 3.3, 3.05, 0.17, 0.88, "dark"),
			], [])
		"returns":
			return _room(Vector2(13, 14), 4.05, 3.55, "Keep the return enclosure in sight. Leave on the service side of the return desk.", [
				_partition(Vector2(-6.5, -3.7), Vector2(-0.7, -3.7), 2.63, [[3.65, 1.70, 2.18]]),
				_partition(Vector2(-0.7, -3.7), Vector2(-0.7, -7.0), 2.63),
			], [
				_fixture("RETURN DESK", -3.05, -0.55, 3.7, 1.15, 1.10),
				_fixture("DEAD-LETTER REEL", 2.9, -1.6, 1.55, 1.30, 1.40, "metal", 0.0, "drum"),
				_fixture("RETURN HATCH", -3.0, -5.75, 2.20, 0.68, 1.8),
			], [Vector2(0, 0.65), Vector2(0, -3.36), Vector2(3.55, -5.05)])
		"exchange":
			return _room(Vector2(16, 15), 4.25, 0.0, "Read the two independent booths and the central shared speaking line.", [
				_partition(Vector2(-8, -1.8), Vector2(-1.85, -1.8), 2.60, [[3.65, 1.8, 2.22]]),
				_partition(Vector2(1.85, -1.8), Vector2(8, -1.8), 2.60, [[2.50, 1.8, 2.22]]),
				_partition(Vector2(-1.85, -1.8), Vector2(-1.85, -5.3), 2.60),
				_partition(Vector2(1.85, -1.8), Vector2(1.85, -5.3), 2.60),
			], [
				_fixture("BOOTH A", -4.35, -4.25, 2.25, 0.85, 1.18),
				_fixture("BOOTH B", 4.35, -4.25, 2.25, 0.85, 1.18),
				_fixture("SHARED SPEAKING LINE", -4.0, 1.35, 2.65, 0.85, 1.72, "metal"),
			], [])
		"wash":
			return _room(Vector2(14, 16), 4.6, -3.6, "Follow the dry route past the drip tray. Leave room for the wet-side controls.", [
				_partition(Vector2(-0.85, -1.30), Vector2(-0.85, -6.0), 1.10),
			], [
				_fixture("PUMP CONTROL", 3.0, 1.5, 2.60, 1.28, 1.32),
				_fixture("CISTERN", 3.5, -4.75, 3.5, 3.5, 2.5, "metal", 0, "drum"),
				_fixture("DRIP TRAY", -3.6, -2.45, 3.1, 2.9, 0.30, "water", 2.62),
				_fixture("WET BAY", 3.25, -3.3, 6.20, 6.5, 0.014, "water", 0.004, "mat"),
			], [Vector2(0, 3.65), Vector2(-3.6, 1.38)])
		"lift":
			return _room(Vector2(15, 15), 5.55, 3.6, "Allow space for the freight cage and the separate walk-under escape route.", [
				_partition(Vector2(-7.5, -2.65), Vector2(1.25, -2.65), 3.25, [[4.45, 3.8, 2.8]]),
			], [
				_fixture("FREIGHT CAGE", -3.06, -3.15, 3.3, 2.6, 2.1, "metal", 0.32),
				_fixture("WINDING DRUM", -4.25, 1.1, 2.5, 2.5, 1.30, "pale", 0.0, "drum"),
				_fixture("SAFETY DOG", -1.6, 0.73, 0.8, 0.86, 1.15),
				_fixture("ESCAPE LINTEL", 3.6, -3.0, 3.6, 1.75, 0.38, "pale", 2.55),
				_fixture("COUNTERWEIGHT", -5.9, -5.55, 0.84, 0.94, 1.25, "dark", 2.72),
			], [Vector2(0, 2.72), Vector2(3.6, 0.85)])
		"airlock":
			return _room(Vector2(14, 16), 4.2, 0.0, "Walk the two independent paths around the common locker.", [
				_partition(Vector2(-7, -0.7), Vector2(7, -0.7), 2.95, [[3.45, 2.25, 2.32], [10.55, 2.25, 2.32]]),
			], [
				_fixture("COMMON LOCKER", 0.0, -0.2, 1.88, 0.82, 1.77),
				_fixture("DRY BENCH A", -5.7, 2.4, 1.45, 2.40, 0.86),
				_fixture("DRY BENCH B", 5.7, 2.4, 1.45, 2.40, 0.86),
				_fixture("PASS-THROUGH", 0.0, -4.1, 2.15, 1.35, 1.2, "metal"),
			], [Vector2(0, 3.15), Vector2(3.55, 1.6), Vector2(3.55, -5.8), Vector2(0, -6.25)],
			[Vector2(0, 3.15), Vector2(-3.55, 1.6), Vector2(-3.55, -5.8), Vector2(0, -6.25)])
		"shutter":
			return _room(Vector2(16, 15), 4.6, 0.0, "Read the bell from the hold line. Compare the main opening with the maintenance bypass.", [
				_partition(Vector2(-8, -1.6), Vector2(8, -1.6), 3.85, [[8.0, 3.25, 2.76], [13.45, 1.85, 2.18]]),
			], [
				_fixture("BELL REGISTER", -4.5, 1.0, 2.2, 0.85, 1.58, "metal"),
				_fixture("DRAWBAR", -2.25, -0.98, 0.62, 0.70, 1.52),
				_fixture("SHUTTER / STOWED", 0.0, -1.32, 3.40, 0.40, 0.54, "dark", 2.86),
				_fixture("SERVICE SHOE", 6.68, -0.72, 0.90, 0.72, 0.55),
			], [], [Vector2(0, 3.25), Vector2(5.45, 0.95), Vector2(5.45, -4.25), Vector2(0, -5.75)])
		"hall":
			return _room(Vector2(19, 18), 5.75, 0.0, "Keep the assembly aisle wide between witnesses, recovery, and the survey desk.", [], [
				_fixture("ARRIVAL BOOK", -4.10, 2.2, 3.0, 1.35, 1.12),
				_fixture("WITNESS DESKS", -5.65, -2.0, 3.5, 1.45, 1.10),
				_fixture("RECOVERY BAY", 5.80, 0.40, 3.20, 2.1, 0.63),
				_fixture("SURVEY REEL", 4.15, -3.8, 2.35, 1.15, 1.35, "metal"),
				_fixture("SUPPLY LOCKERS", -6.65, -6.25, 3.35, 0.95, 1.9),
			], [])
		"darkroom":
			return _room(Vector2(14, 15), 3.8, 3.8, "Separate wet processing from the dry contact-print route and its clear approach.", [
				_partition(Vector2(0.2, -2.1), Vector2(0.2, -6.05), 2.22),
			], [
				_fixture("PROCESSING BATH", -3.7, -2.15, 3.55, 1.65, 0.88, "water"),
				_fixture("NEGATIVE CARRIER", -3.7, 0.7, 2.6, 0.88, 1.36),
				_fixture("CONTACT PRESS", 5.58, -2.95, 1.4, 2.65, 1.2),
				_fixture("DRY PRINT RACK", 5.65, -5.50, 1.40, 1.52, 2.05, "metal"),
			], [Vector2(0, 2.1), Vector2(3.8, -0.72)])
		"relay":
			return _room(Vector2(16, 16), 4.55, 0.0, "Read two distinct dispatch lanes and their reunion at the outgoing arch.", [
				_partition(Vector2(0, 1.8), Vector2(0, -5.45), 1.15),
			], [
				_fixture("LINE A / RECEIPTS", -5.3, -1.75, 2.45, 2.90, 1.26),
				_fixture("LINE B / RECEIPTS", 5.3, -1.75, 2.45, 2.90, 1.26),
				_fixture("PUBLIC DISPATCH HORN", 0.0, -1.6, 1.4, 1.4, 1.08, "metal", 1.15, "drum"),
				_fixture("OUTGOING DOCKET", -4.22, -6.6, 1.45, 0.7, 1.0),
			], [Vector2(0, 3.85), Vector2(2.85, 2.4), Vector2(2.85, -5.95), Vector2(0, -6.55)],
			[Vector2(0, 3.85), Vector2(-2.85, 2.4), Vector2(-2.85, -5.95), Vector2(0, -6.55)])
		"meridian":
			return _room(Vector2(16, 17), 5.65, 0.0, "Finish at the bell. Check the sightline from the register and clearance around the wheel.", [], [
				_fixture("DAWN REGISTER", -3.65, 0.35, 2.45, 1.12, 1.17),
				_fixture("MANUAL WHEEL", 4.36, -3.1, 1.95, 1.95, 1.24, "metal", 0.0, "drum"),
				_fixture("BELL PLINTH", 0.0, -6.5, 4.9, 2.6, 0.53),
				_fixture("DAWN BELL", 0.0, -6.55, 2.35, 2.35, 1.93, "metal", 2.65, "drum"),
				_fixture("BELL PIER A", -2.12, -6.55, 0.55, 0.75, 3.85, "pale", 0.53),
				_fixture("BELL PIER B", 2.12, -6.55, 0.55, 0.75, 3.85, "pale", 0.53),
				_fixture("BELL BEAM", 0.0, -6.55, 4.8, 0.78, 0.52, "pale", 4.38),
			], [], [], -4.37)
	return {}

static func _room(size: Vector2, height: float, exit_x: float, brief: String, walls: Array, fixtures: Array,
		turns: Array, alternative := [], finish_z := INF) -> Dictionary:
	var start := Vector2(0.0, size.y * 0.5 - 1.25)
	var finish := Vector2(exit_x, -size.y * 0.5 - 0.85 if finish_z == INF else finish_z)
	return {"size": size, "height": height, "brief": brief, "walls": walls, "fixtures": fixtures,
		"exit_x": exit_x, "terminal": finish_z != INF, "start": start, "finish": finish,
		"route": [start] + turns + [finish], "alternative": [] if alternative.is_empty() else [start] + alternative + [finish]}

static func _partition(a: Vector2, b: Vector2, height: float, openings := []) -> Dictionary:
	return {"a": a, "b": b, "height": height, "openings": openings}

static func _fixture(label: String, x: float, z: float, width: float, depth: float, height: float,
		finish := "pale", base := 0.0, shape := "box") -> Dictionary:
	return {"label": label, "at": Vector3(x, base + height * 0.5, z), "size": Vector3(width, height, depth), "finish": finish, "shape": shape}
