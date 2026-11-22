extends SceneTree
## Headless fixed-tick acceptance tests. Invoke with Godot --headless -s <this file>.

const Model = preload("res://scenes/physics_lab/Model.gd")
var failures: Array[String] = []


func _initialize() -> void:
	var checks := [polarizers, standing_wave, observer, portals, sorting, gravity, alchemy, induction, clocks, tape]
	for test: Callable in checks:
		var start := failures.size()
		test.call()
		print("%s %s" % ["PASS" if failures.size() == start else "FAIL", test.get_method()])
	print("%d mechanism checks, %d failures" % [checks.size(), failures.size()])
	quit(0 if failures.is_empty() else 1)


func check(condition: bool, message: String) -> void:
	if condition: return
	failures.append(message)
	printerr(message)


func plate(index: int) -> Model:
	var m := Model.new()
	m.reset(index)
	return m


func advance(m: Model, ticks: int) -> void:
	for i in range(ticks): m.advance()


func polarizers() -> void:
	check(Model.malus(false, 45) == 0.0, "crossed pair is dark")
	check(Model.malus(true, 90) == 0.0, "collinear insertion does not help")
	check(is_equal_approx(Model.malus(true, 45), 0.125), "unpolarized transfer at 45°")
	check(is_equal_approx(Model.malus(true, 135), 0.125), "polarizer axes are not oriented arrows")
	var m := plate(0)
	m.command(0); m.command(2); m.command(0)
	check(not m.s.passed, "removing pane closes the gate")


func standing_wave() -> void:
	check(Model.envelope(0, 0) < 1e-7 and Model.envelope(1, 0) > 0.99, "reference extrema")
	check(Model.envelope(0, 1) > 0.99 and Model.envelope(1, 1) < 1e-7, "one-quarter wavelength interchanges extrema")
	check(Model.envelope(0, 2) < 1e-7, "one-half wavelength does not interchange extrema")
	var m := plate(1)
	m.command(0); m.command(2)
	advance(m, 39)
	check(m.s.warning == 39 and not m.s.fault, "39 ticks of recoverable wave warning")
	advance(m, 1)
	check(m.s.fault, "persistent antinode stops at tick 40")


func observer() -> void:
	check(Model.rays(true, true) > 0 and Model.rays(true, false) == 0 and Model.rays(false, true) == 0, "geometric gaze and light both required")
	var m := plate(2)
	m.command(0); advance(m, 1)
	check(m.s.twin_shutter == 0 and m.s.bridge, "linked anti-state")
	m.command(2); advance(m, 20)
	m.command(0); advance(m, 39)
	check(m.s.crossing == 20 and m.s.warning == 39, "loss suspends crossing during grace window")
	m.command(0); advance(m, 60)
	check(m.s.passed and m.s.partner == 1 and m.s.warning == 0, "reacquire before the stop")


func portals() -> void:
	for layer in range(2):
		for sector in range(4):
			var f := Model.portal(sector, layer, true)
			var r := Model.portal(f.x, f.y, false)
			check(r == Vector3i(sector, layer, 90), "portal map has inverse")
	var m := plate(3)
	for i in range(4): m.command(0)
	m.command(2)
	check(m.s.probe_length == 12000 and m.s.probe_hits == 1 and m.s.probe_layer == 1, "mapped ray sees upper chart")
	for i in range(4): m.command(0)
	check(m.s.layer == 0 and m.s.sector == 0 and m.s.yaw == 0, "eight right turns return to original frame")


func sorting() -> void:
	var m := plate(4)
	m.command(2)
	check(m.s.erased == 0, "clearing an empty latch is not an erasure")
	for bit: int in [1, 0, 0, 1]:
		m.command(1)
		check(m.s.register == bit, "sample bit before modifying gate")
		if bit == 1: m.command(0)
		m.command(3); advance(m, 120); m.command(2)
	check(m.s.passed and m.s.energy_l == 2 and m.s.energy_r == 8 and m.s.erased == 4, "two fast and two slow at equal counts")


func gravity() -> void:
	var m := plate(5)
	m.command(1); advance(m, 50)
	check(m.s.warning == 39 and not m.s.fault, "threshold then 39-tick warning")
	advance(m, 1)
	check(m.s.fault and m.s.height == 0, "hazard restores last landing")
	m.command(3); m.command(1); advance(m, 80)
	check(is_equal_approx(m.s.height, 3.0) and m.s.gravity == -1, "field-free shaft permits standard ascent")


func alchemy() -> void:
	var m := plate(6)
	m.command(1)
	check(m.s.form == 0 and not m.s.valid, "bath rejects raw specimen")
	m.command(0); m.command(1)
	check(m.s.form == 1, "second stroke waits for the carriage")
	advance(m, 40); m.command(1); advance(m, 40); m.command(2); advance(m, 40); m.command(3)
	check(m.s.passed and m.s.path == [0, 1, 2, 3], "ordered tools deploy deck")


func induction() -> void:
	var m := plate(7)
	advance(m, 100)
	check(m.s.emf == 0 and m.s.hold == 0, "static flux does not induce emf")
	m.command(1); advance(m, 60)
	var out: float = m.s.probe_x
	m.command(0); m.command(1); advance(m, 60)
	check(out > 0 and is_equal_approx(out, -m.s.probe_x), "field reverses sides")
	var x: float = m.s.probe_x
	m.command(0); advance(m, 1)
	check(absf(m.s.probe_x - x) < 0.05, "reversal preserves trajectory continuity")
	m.command(2); advance(m, 60); m.command(0); advance(m, 39)
	check(m.s.polarity == 1 and m.s.warning == 39, "40-tick live reversal warning")
	advance(m, 1)
	check(m.s.polarity == -1 and m.s.hold == 60, "switch commits on tick 40; capacitor holds 60 ticks")
	m.command(3); advance(m, 59)
	check(m.s.emf == 0 and m.s.hold == 1, "hold is a device timer, not continuing induction")
	advance(m, 1)
	check(m.s.hold == 0, "device timer expires")


func clocks() -> void:
	var a := plate(8)
	var b := plate(8)
	var receipts: Array[String] = []
	for m: Model in [a, b]:
		m.command(0); advance(m, 100)
		check(m.s.arrival_l == ["A", "B"] and m.s.arrival_r == ["B", "A"], "local photon arrival orders differ")
		m.command(1)
		check(is_equal_approx(m.s.frame_delta, -7.0 / 12.0) and is_equal_approx(m.s.proper_rate, 0.8), "Lorentz transform order and clock rate")
		m.command(2); advance(m, 60); m.command(2); advance(m, 39)
		check(m.s.warning == 39 and m.s.replay == 0, "blocked echo reports before rollback")
		advance(m, 1)
		check(m.s.fault and m.s.replay == -1, "roll back echo, retain recording")
		m.command(2); m.command(3); advance(m, 60)
		check(m.s.passed, "two pads overlap in time")
		receipts.append(JSON.stringify(m.s).sha256_text())
	check(receipts[0] == receipts[1], "identical command and tick sequence yields identical replay digest")
	print("echo state SHA256: " + receipts[0])


func tape() -> void:
	for n in range(16):
		var m := plate(9)
		var parity := 0
		for i in range(4):
			var symbol := (n >> i) & 1
			parity ^= symbol
			if m.s.tape[i] != symbol: m.command(1)
			m.command(0)
		m.command(2); advance(m, 59)
		check(m.s.head == 0, "head waits 60 ticks")
		advance(m, 241)
		check(m.s.passed == (parity == 0) and m.s.history.size() == 4 and m.s.tape == [0, 0, 0, 0], "all four-bit tapes: head, rewrite and halt parity")
