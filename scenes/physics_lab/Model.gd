extends RefCounted
## Authoritative fixed-tick model; the viewport only projects this state.

const HZ := 60
const CAUTION := 60
const STOP := 40
const LIGHT_SPEED := 3.0
const WAVE_LENGTH := 4.0
const ECHO_FRAMES := 60
const CELL_COUNT := 4
const PORTALS := [Vector3(-2.65, 0.0, 1.7), Vector3(0.0, 0.0, 1.7),
	Vector3(2.65, 0.0, 1.7), Vector3(3.4, 0.0, -1.95), Vector3(-3.85, 2.0, -1.9),
	Vector3(-2.55, 2.0, -1.9), Vector3(-1.25, 2.0, -1.9), Vector3(0.05, 2.0, -1.9)]
const NONE := -1

var room := 0
var tick := 0
var s: Dictionary


func reset(index: int) -> void:
	room = index
	tick = 0
	s = {"passed": false, "warning": 0, "fault": false}
	match room:
		0: s.merge({"inserted": false, "angle": 45, "power": 0.0})
		1: s.merge({"mirror_offset": 0.0, "zone": 0, "trial": -1, "envelope": 0.0})
		2: s.merge({"gaze": false, "lit": true, "bridge": false, "partner": 0, "hits": 0, "phase": 0, "twin_shutter": 1, "crossing": -1})
		3: s.merge({"sector": 0, "layer": 0, "probe_sector": -1, "probe_layer": -1, "probe_length": 0, "probe_hits": 0, "probe_dir": [], "lower_steps": 0, "yaw": 0, "turns": 0})
		4: s.merge({"sample": 0, "age": 0, "left": 0, "right": 0, "energy_l": 0, "energy_r": 0,
			"register": -1, "erased": 0, "gate": 0, "sorting": false, "transmitted": false})
		5: s.merge({"gravity": -1, "height": 0.0, "target_height": 0.0, "moving": false,
			"loads": [0, 0], "held": -1, "pocket": false, "ascent": 0.0})
		6: s.merge({"form": 0, "latched": [false, false, false], "path": [0], "progress": 1.0, "valid": true})
		7: s.merge({"polarity": 1, "probe_age": -1, "probe_x": 0.0, "probe_z": 0.0, "angle": 0.0, "pending": 0,
			"magnet": -2.5, "stroke": 0, "emf": 0.0, "flux": flux(-2.5), "hold": 0, "pulse_peak": 0.0})
		8: s.merge({"velocity": 0.0, "age": -1, "arrival_l": [], "arrival_r": [], "frame_delta": 20.0 / HZ,
			"proper_rate": 1.0, "length_ratio": 1.0, "record": [], "recording": false, "replay": -1,
			"echo": -1, "player": 0, "blocked": false, "order_seen": false})
		9: s.merge({"tape": [1, 0, 0, 0], "cursor": 0, "head": 0, "parity": 0, "age": -1,
			"halt": "READY", "history": [], "stock": 0})


func command(index: int) -> void:
	match room:
		0:
			match index:
				0:
					s.inserted = not s.inserted
					s.passed = false
				1:
					s.angle = (s.angle + 45) % 180
					s.passed = false
				2: s.passed = s.power >= 0.10
			s.power = malus(s.inserted, s.angle)
		1:
			match index:
				0: s.mirror_offset = 1.0 - s.mirror_offset
				1: s.zone = 1 - s.zone
				2:
					if s.trial < 0:
						s.trial = 0
						s.fault = false
				3:
					s.trial = -1
					s.warning = 0
			s.envelope = envelope(float(s.zone), s.mirror_offset)
		2:
			match index:
				0: s.gaze = not s.gaze
				1: s.lit = not s.lit
				2:
					if s.bridge and s.crossing < 0 and s.partner == 0:
						s.crossing = 0
						s.fault = false
				3:
					s.crossing = -1
					s.partner = 0
					s.warning = 0
		3:
			if index == 0 or index == 1:
				var info := portal(int(s.sector), int(s.layer), index == 0)
				s.lower_steps += 6 + 6 * int(s.layer if index == 0 else info.y)
				s.sector = info.x
				s.layer = info.y
				s.yaw = posmod(int(s.yaw) + info.z, 360)
				s.turns += 1 if index == 0 else -1
			elif index == 2:
				var info := portal(int(s.sector), int(s.layer), true)
				s.probe_sector = info.x
				s.probe_layer = info.y
				var mapped := portal_probe(int(s.layer), info.z)
				s.probe_length = mapped[0]
				s.probe_hits = mapped[1]
				s.probe_dir = mapped[2]
			elif index == 3:
				s.passed = s.layer == 1 and s.sector == 0 and s.probe_layer == 1 and s.probe_hits > 0
		4:
			match index:
				0:
					if not s.transmitted and s.age < 60:
						s.gate = 60 - s.age
				1:
					if s.register == NONE:
						s.register = speed_class(int(s.sample))
				2:
					if s.register != NONE:
						s.register = NONE
						s.erased += 1
				3: s.sorting = not s.sorting
		5:
			match index:
				0:
					if not s.moving: s.gravity = -s.gravity
				1:
					if not s.moving:
						s.target_height = 3.0 if s.height < 1.5 else 0.0
						s.ascent = 0.0
						s.fault = false
						s.moving = true
				2:
					if not s.moving:
						var landing := int(round(s.height / 3.0))
						if s.held == NONE:
							if s.loads[0] == landing: s.held = 0
							elif s.loads[1] == landing: s.held = 1
							if s.held != NONE: s.loads[s.held] = 2
						else:
							s.loads[s.held] = landing
							s.held = NONE
						s.passed = landing == 1 and s.loads == [1, 1]
				3:
					if s.warning > 0:
						s.moving = false
						s.height = 0.0 if s.target_height == 3.0 else 3.0
						s.warning = 0
					elif not s.moving: s.pocket = not s.pocket
		6:
			if index < 3 and s.progress >= 1.0:
				# Magnetise base; immerse magnetic stock; fire floating stock.
				s.valid = s.form == index
				if s.valid:
					s.form += 1
					s.path.append(s.form)
					s.latched[index] = true
					s.progress = 0.0
			elif index == 3 and s.progress >= 1.0 and s.latched == [true, true, true]:
				s.passed = true
		7:
			match index:
				0:
					if s.stroke == 0: s.polarity = -s.polarity
					elif s.pending == 0: s.pending = STOP
				1:
					s.probe_age = 0
					s.probe_x = 0.0
					s.probe_z = 0.0
					s.angle = 0.0
				2: s.stroke = -1 if s.magnet >= 2.5 else 1
				3:
					s.stroke = 0
					s.pending = 0
					s.warning = 0
		8:
			match index:
				0:
					s.age = 0
					s.arrival_l = ["A"]
					s.arrival_r = []
					s.order_seen = false
				1: s.velocity = 1.8 if s.velocity == 0.0 else 0.0
				2:
					if s.replay < 0 and not s.recording:
						if s.record.size() == ECHO_FRAMES:
							s.replay = 0
							s.echo = -1
							s.warning = 0
							s.fault = false
						else:
							s.recording = true
							s.record = []
							s.player = 0
				3: s.player = 1 - s.player
			s.proper_rate = sqrt(1.0 - pow(s.velocity / LIGHT_SPEED, 2))
			s.length_ratio = s.proper_rate
			s.frame_delta = ((20.0 / HZ) - s.velocity * 4.0 / pow(LIGHT_SPEED, 2)) / s.proper_rate
		9:
			if s.age < 0:
				match index:
					0: s.cursor = (s.cursor + 1) % CELL_COUNT
					1: s.tape[s.cursor] = 1 - s.tape[s.cursor]
					2:
						s.head = 0
						s.parity = 0
						s.history = []
						s.halt = "READING"
						s.age = 0
						s.passed = false
					3:
						s.stock = 1 - s.stock
						s.tape[s.cursor] = s.stock


func advance() -> void:
	tick += 1
	match room:
		1:
			if s.trial >= 0:
				s.trial += 1
				var at_risk: bool = s.envelope > 0.1
				if at_risk: s.warning += 1
				else: s.warning = 0
				if s.warning >= STOP:
					s.fault = true
					s.trial = -1
				elif s.trial >= CAUTION and not at_risk:
					s.passed = true
					s.trial = -1
		2: _gaze_tick()
		4: _sort_tick()
		5: _lift_tick()
		6: s.progress = minf(1.0, s.progress + 1.0 / 40.0)
		7: _magnet_tick()
		8: _clock_tick()
		9: _tape_tick()


static func malus(inserted: bool, angle: int) -> float:
	if not inserted or angle % 90 == 0: return 0.0
	var theta := deg_to_rad(float(angle))
	return pow(cos(theta) * sin(theta), 2) / 2.0


static func envelope(x: float, mirror_offset: float) -> float:
	return absf(sin(TAU * (x - mirror_offset) / WAVE_LENGTH))


static func rays(gaze: bool, lit: bool) -> int:
	if not lit: return 0
	var hits := 0
	var center := Vector3(-3.0, 1.54, 2.2)
	var deck := AABB(Vector3(-1.05, -0.10, -1.15), Vector3(2.10, 0.25, 2.30))
	for yaw in range(-4, 5):
		for pitch in range(-1, 2):
			var forward := Vector3(3.0, -1.50, -2.2).normalized() if gaze else Vector3.BACK
			var beam := forward.rotated(forward.cross(Vector3.UP).normalized(), deg_to_rad(float(pitch * 10)))
			beam = beam.rotated(Vector3.UP, deg_to_rad(float(yaw * 10)))
			if deck.intersects_segment(center, center + beam * 9.0): hits += 1
	return hits


func _gaze_tick() -> void:
	s.hits = rays(s.gaze, s.lit)
	if s.hits > 0:
		s.bridge = true
		s.warning = 0
	elif s.crossing >= 0:
		s.warning += 1
		if s.warning >= STOP:
			s.bridge = false
			s.crossing = -1
			s.fault = true
	else: s.bridge = false
	if not s.bridge: s.phase = int(tick / 20.0) % 2
	s.twin_shutter = 0 if s.bridge else 1
	if s.crossing >= 0 and s.hits > 0:
		s.crossing += 1
		if s.crossing >= 80:
			s.partner = 1
			s.crossing = -1
			s.passed = true


static func portal(sector: int, layer: int, forward: bool) -> Vector3i:
	var travel := 1 if forward else -1
	var raw := sector + travel
	return Vector3i(posmod(raw, 4), 1 - layer if raw < 0 or raw > 3 else layer, -90 * travel)


static func portal_probe(layer: int, yaw_deg: int) -> Array:
	# Ray fan enters a 1.2 m aperture from 0.8 m away. Map the hit point and
	# direction rigidly before testing the next segment in the destination chart.
	var mapping := Transform3D(Basis(Vector3.UP, deg_to_rad(yaw_deg)), Vector3.ZERO)
	var center := mapping.basis * Vector3.FORWARD
	var distance_m := 6.0 + 6.0 * layer
	var target := AABB(center * (distance_m + 0.10) - Vector3.ONE * 0.10, Vector3.ONE * 0.20)
	var hits := 0
	var distance_mm := 0
	for yaw in range(-4, 5):
		for pitch in range(-1, 2):
			var incoming := Vector3.FORWARD.rotated(Vector3.RIGHT, deg_to_rad(pitch * 10.0)).rotated(Vector3.UP, deg_to_rad(yaw * 10.0))
			var entry := Vector3(0, 0, 0.8) + incoming * (-0.8 / incoming.z)
			if absf(entry.x) > 0.6 or absf(entry.y) > 0.9: continue
			var start := mapping * entry
			var end := start + mapping.basis * incoming * 14.0
			var hit: Variant = target.intersects_segment(start, end)
			if hit is Vector3:
				hits += 1
				distance_mm = roundi(start.distance_to(hit) * 1000.0)
	return [distance_mm, hits, [center.x, center.y, center.z]]


static func speed_class(sample: int) -> int:
	return [1, 0, 0, 1, 0, 1][sample % 6]


func _sort_tick() -> void:
	if not s.sorting: return
	s.age += 1
	if s.age == 60:
		s.transmitted = s.gate > 0
		var fast := speed_class(int(s.sample))
		var energy := 4 if fast == 1 else 1
		if s.transmitted:
			s.right += 1
			s.energy_r += energy
		else:
			s.left += 1
			s.energy_l += energy
		s.passed = s.left >= 2 and s.right >= 2 and s.energy_r - s.energy_l >= 5
	if s.gate > 0: s.gate -= 1
	if s.age >= 120:
		s.age = 0
		s.sample += 1
		s.transmitted = false
		s.sorting = false  # Rest after each trajectory; each trial is a deliberate action.


func _lift_tick() -> void:
	if not s.moving: return
	var direction := signf(s.target_height - s.height)
	if direction != s.gravity and not s.pocket:
		s.ascent += 0.0375
		if s.ascent >= 0.45 - 1e-9:
			s.warning += 1
		if s.warning >= STOP:
			s.height = 0.0 if s.target_height == 3.0 else 3.0
			s.warning = 0
			s.moving = false
			s.fault = true
			return
	s.height = move_toward(s.height, s.target_height, 0.0375)
	if is_equal_approx(s.height, s.target_height): s.moving = false


static func flux(z: float) -> float:
	return exp(-z * z / 0.72)


func _magnet_tick() -> void:
	if s.pending > 0:
		s.pending -= 1
		s.warning += 1
		if s.pending == 0:
			s.polarity = -s.polarity
			s.warning = 0
	if s.probe_age >= 0 and s.probe_age < 75:
		s.probe_age += 1
		# Exact integration of a constant-speed arc over each field tick. A
		# polarity switch changes curvature without teleporting the probe.
		var a: float = s.angle
		var turn: float = s.polarity * 0.018
		s.angle += turn
		s.probe_x += (cos(a) - cos(s.angle)) * (2.7 * s.polarity)
		s.probe_z += (sin(s.angle) - sin(a)) * (2.7 * s.polarity)
	if s.hold > 0: s.hold -= 1
	var before: float = s.flux
	s.magnet = clampf(s.magnet + 0.035 * s.stroke, -2.5, 2.5)
	if absf(s.magnet) >= 2.5: s.stroke = 0
	s.flux = flux(s.magnet)
	s.emf = (before - s.flux) * HZ
	s.pulse_peak = maxf(s.pulse_peak, absf(s.emf))
	if absf(s.emf) >= 0.70: s.hold = CAUTION
	s.passed = s.hold > 0


func _clock_tick() -> void:
	if s.age >= 0:
		s.age += 1
		# Sources A/B are 4 m apart; B is triggered 20 ticks later.
		# Each clock registers a locally detected photon, including propagation delay.
		if s.age == 20: s.arrival_r.append("B")
		if s.age == 80: s.arrival_r.append("A")
		if s.age == 100: s.arrival_l.append("B")
		s.order_seen = s.arrival_l.size() == 2 and s.arrival_r.size() == 2
		if s.age >= 120: s.age = -1
	if s.recording:
		s.record.append(s.player)
		if s.record.size() == ECHO_FRAMES: s.recording = false
	if s.replay >= 0:
		var next: int = s.record[s.replay]
		# Pad 0 is mutual exclusion; overlap pauses the replay and exposes a recovery window.
		s.blocked = next == 0 and s.player == 0
		if s.blocked:
			s.warning += 1
			if s.warning >= STOP:
				s.fault = true
				s.replay = -1
				s.echo = -1
			return
		s.warning = 0
		s.echo = next
		s.replay += 1
		if s.order_seen and s.frame_delta < 0.0 and s.echo == 0 and s.player == 1:
			s.passed = true
		if s.replay >= ECHO_FRAMES:
			s.replay = -1
			s.echo = -1
	else: s.blocked = false


func _tape_tick() -> void:
	if s.age < 0: return
	s.age += 1
	if s.age % CAUTION != 0: return
	if s.head == CELL_COUNT:
		s.passed = s.parity == 0
		s.halt = "ACCEPT" if s.passed else "REJECT"
		s.age = -1
		return
	var input: int = s.tape[s.head]
	s.history.append([s.head, s.parity, input, s.parity ^ input])
	s.parity ^= input
	s.tape[s.head] = 0
	s.head += 1
