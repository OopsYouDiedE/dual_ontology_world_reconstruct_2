extends SceneTree

const Rules = preload("res://scenes/physics_lab/chronograph/ChronographRules.gd")
var fails := 0


func _initialize() -> void:
	var specification: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://tools/chronograph/golden.json"))
	var m := Rules.new()
	for beat: Dictionary in specification.beats:
		commands(m, beat.actions)
		var snapshot := m.state()
		for field: String in beat.expect:
			var wanted: Variant = beat.expect[field]
			check(snapshot[field] == wanted, "%s: %s expected %s, got %s" % [beat.label, field, wanted, snapshot[field]])
	print("GOLDEN EVENTS ", JSON.stringify(m.events))
	check(distance(m, "rewind_warn", "rewind_commit") == 48, "rewind is announced 48 ticks before restore")
	check(distance(m, "span_warn", "span_open") == 48, "bridge is announced 48 ticks before alignment")
	check(distance(m, "forge_heat", "forge_key") == 40, "40 firing ticks")
	check(m.won, "golden reaches exit")
	var repeated := Rules.new()
	for beat: Dictionary in specification.beats: commands(repeated, beat.actions)
	check(m.state() == repeated.state(), "exact repeat produces identical state")

	m = Rules.new()
	commands(m, ["east", "south", "use", "east", "north", "use"])
	check(m.player == Rules.KILN and m.item == Rules.Item.RAW, "wrong-route / raw ore blocked / no plate no forge")
	check(has_event(m, "screen_reject"), "screen rejected raw ore auditable")
	check(not has_event(m, "forge_heat"), "kiln without pressure never starts")
	m = Rules.new()
	commands(m, ["south", "east", "north", "east", "east"])
	check(m.player == Rules.LAND and not m.span_walkable(), "empty bearer passes screen, parked deck denies crossing")

	m = Rules.new()
	commands(m, ["use", "south", "east", "use", "west", "west", "west"])
	check(m.player == Rules.ANCHOR and m.item == Rules.Item.EMPTY and m.rewind == 0, "use ends a tape command; replay routes cannot create side effects")
	# Verified rewind on a blocked command restores checkpoint and consumes that full beat.
	m = Rules.new()
	commands(m, ["use", "north", "north", "use", "east", "east"])
	check(m.rewind == 8 and m.player == Rules.CALL, "48 tick warning still visible after two beats")
	m.command("west")
	check(m.player == Rules.ANCHOR and m.replay_tick == 12, "rewind restore is atomic; input during warning ignored")
	commands(m, ["wait", "wait"])
	check(m.echo == Rules.GONE and m.replay_tick == -1, "ended tape leaves no persistent pressure")
	m = Rules.new()
	m.command("use")
	for i in Rules.LIMIT: m.command("wait")
	check(m.tape.size() == Rules.LIMIT + 1 and m.rewind == Rules.WARN, "full tape automatically raises rewind warning")

	# Cancelled heat and alignment use normal input on intentionally short timelines.
	m = Rules.new()
	commands(m, ["use", "west", "west", "wait", "wait", "wait", "east", "use", "wait", "wait", "wait",
		"south", "use", "east", "use", "wait"])
	check(has_event(m, "forge_cancel") and m.item == Rules.Item.RAW, "ending pressure before 40 firing ticks rolls heating back")
	m = Rules.new()
	var pre_span: Array = specification.beats.slice(0, 7)
	for beat: Dictionary in pre_span: commands(m, beat.actions)
	m.command("west")
	check(has_event(m, "span_cancel") and not m.span_walkable(), "carrier leaving alignment station cancels preview")
	m = Rules.new()
	for beat: Dictionary in specification.beats.slice(0, 9): commands(m, beat.actions)
	for i in 9: m.command("wait")
	check(m.player == Rules.SPAN and m.span_walkable(), "closing interlock supports an occupant")
	check(not has_event(m, "span_close"), "closing interlock did not move occupied floor")
	m.command("east")
	check(distance(m, "span_close_warn", "span_close") >= 48, "parking waits 48 ticks and defers while occupied")
	print("CHRONOGRAPH VERIFY failures=", fails)
	quit(int(fails > 0))


func commands(model: Rules, inputs: Array) -> void:
	for input: String in inputs: model.command(input)


func has_event(model: Rules, kind: String) -> bool:
	return model.events.any(func(event: Dictionary) -> bool: return event.kind == kind)


func distance(model: Rules, first: String, last: String) -> int:
	var a := -1
	for event in model.events:
		if event.kind == first: a = event.tick
		if event.kind == last and a >= 0: return event.tick - a
	return -1


func check(condition: bool, what: String) -> void:
	if not condition:
		printerr("FAIL: ", what)
		fails += 1
