extends RefCounted
## The 60 Hz authoritative room. Rendering and input never write this state.

const STEP := 20
const WARN := 48
const FORGE := 40
const OPEN := 100
const LIMIT := 22
const GONE := Vector2i(99, 99)
const ANCHOR := Vector2i(0, 0)
const WEST := Vector2i(-1, 0)
const FIRE := Vector2i(-2, 0)
const NORTH := Vector2i(0, -1)
const CALL := Vector2i(0, -2)
const ORE := Vector2i(0, 1)
const KILN := Vector2i(1, 1)
const FILTER := Vector2i(1, 0)
const LAND := Vector2i(2, 0)
const SPAN := Vector2i(3, 0)
const FAR := Vector2i(4, 0)
const EXIT := Vector2i(4, -1)
const EDGES := [[ANCHOR, WEST], [WEST, FIRE], [ANCHOR, NORTH], [NORTH, CALL],
	[ANCHOR, ORE], [ORE, KILN], [KILN, FILTER], [FILTER, LAND],
	[LAND, SPAN], [SPAN, FAR], [FAR, EXIT]]
const DIRS := {"north": Vector2i.UP, "south": Vector2i.DOWN, "west": Vector2i.LEFT, "east": Vector2i.RIGHT}
const PLACES := {ANCHOR: "Anchor", WEST: "Flue walk", FIRE: "Furnace plate", NORTH: "Signal walk",
	CALL: "Bridge plate", ORE: "Ore rack", KILN: "Kiln", FILTER: "Screen gallery", LAND: "Bridge landing",
	SPAN: "Turntable", FAR: "Far gallery", EXIT: "Exit socket"}

enum Item {EMPTY, RAW, KEY, SPENT}
enum SpanMode {PARKED, WARNING, OPENED, CLOSING}
var tick := 0
var player := ANCHOR
var item := Item.EMPTY
var recording := false
var tape: Array[Vector2i] = []
var rewind := 0
var replay_tick := -1
var echo := GONE
var firing := 0
var span := SpanMode.PARKED
var span_clock := 0
var won := false
var message := "The anchor records footsteps. The room resets; the footsteps repeat."
var events: Array[Dictionary] = []


func command(verb: String) -> void:
	if won or (verb != "use" and verb != "wait" and not DIRS.has(verb)):
		return
	if rewind > 0:
		# Ignore movement while the anchor warns, even on the command that crosses tick 48.
		_advance(STEP)
		return
	if verb == "use":
		if _use(): return
	elif DIRS.has(verb):
		_move(player + DIRS[verb])
	_advance(STEP)
	if recording:
		tape.append(player)
		if tape.size() == LIMIT + 1:
			_start_rewind()


func _move(dest: Vector2i) -> void:
	if not ([player, dest] in EDGES or [dest, player] in EDGES):
		message = "Stonework ends the walk here. Follow the joined brass strips."
		return
	if ((player == KILN and dest == FILTER) or (player == FILTER and dest == KILN)) and item == Item.RAW:
		message = "The screen rejects raw ore. It passes people and the cooled key."
		mark("screen_reject")
		return
	if (player == SPAN or dest == SPAN) and (not span_walkable() or (dest == SPAN and span_clock == 0)):
		message = "The turntable must be locked across the gap."
		mark("span_reject")
		return
	player = dest
	message = "At %s." % PLACES[player]


## True for a zero-tick control or a finished run.
func _use() -> bool:
	if recording:
		if tape.size() > 1:
			_start_rewind()
			return true
		message = "Move or wait to put a beat on the tape."
		return true
	match player:
		ANCHOR:
			# An empty, settled world is the sole permitted checkpoint.
			if item == Item.EMPTY and replay_tick < 0 and span == SpanMode.PARKED:
				recording = true
				tape = [ANCHOR]
				message = "Recording. Record pressure by waiting on a plate; R resets the room."
				mark("record")
				return true
			message = "The anchor is busy or the ore is away from its rack. R resets the room."
		ORE:
			if item == Item.EMPTY:
				item = Item.RAW
				message = "Raw ore lifted."
				mark("lift")
		KILN:
			if item == Item.RAW and on_plate(FIRE) and firing == 0:
				firing = FORGE
				message = "Firing: keep the furnace plate and the kiln occupied."
				mark("forge_heat")
			elif item != Item.KEY:
				message = "The kiln needs ore and steady pressure on the furnace plate."
		EXIT:
			if item == Item.KEY:
				item = Item.SPENT
				won = true
				message = "The cooling key fits. The watch is ended."
				mark("exit")
				return true
		_:
			message = "This station operates by pressure or passage."
	return false


func _start_rewind() -> void:
	recording = false
	rewind = WARN
	message = "REWIND WARNING — the anchor will restore the room on the third beat."
	mark("rewind_warn")


func _advance(count: int) -> void:
	for i in count:
		tick += 1
		if rewind > 0:
			rewind -= 1
			if rewind == 0:
				player = ANCHOR
				item = Item.EMPTY
				firing = 0
				span = SpanMode.PARKED
				span_clock = 0
				replay_tick = 0
				echo = ANCHOR
				message = "The room is restored. The teal echo can hold plates."
				mark("rewind_commit")
			continue
		if replay_tick >= 0:
			replay_tick += 1
			# A recorded move takes effect at the start of its beat, as live moves do.
			var sample := ceili(float(replay_tick) / STEP)
			if sample < tape.size():
				echo = tape[sample]
			else:
				echo = GONE
				replay_tick = -1
				mark("echo_end")
		if firing > 0:
			if player != KILN or not on_plate(FIRE) or item != Item.RAW:
				firing = 0
				message = "Firing interrupted. The ore is still raw."
				mark("forge_cancel")
			else:
				firing -= 1
				if firing == 0:
					item = Item.KEY
					message = "The kiln has made a cooling key. It passes the screen."
					mark("forge_key")
		_turntable()


func _turntable() -> void:
	var condition := on_plate(CALL) and player == LAND and item == Item.KEY
	match span:
		SpanMode.PARKED:
			if condition:
				span = SpanMode.WARNING
				span_clock = WARN
				message = "ALIGNMENT WARNING — the bridge plate must remain down."
				mark("span_warn")
		SpanMode.WARNING:
			if not condition:
				span = SpanMode.PARKED
				span_clock = 0
				message = "Alignment cancelled. Keep the bridge plate and landing occupied."
				mark("span_cancel")
			else:
				span_clock -= 1
				if span_clock == 0:
					span = SpanMode.OPENED
					span_clock = OPEN
					message = "Turntable pinned. Cross to the far bank."
					mark("span_open")
		SpanMode.OPENED:
			span_clock -= 1
			if span_clock == 0:
				span = SpanMode.CLOSING
				span_clock = WARN
				message = "PARKING WARNING — walk off the moving deck."
				mark("span_close_warn")
		SpanMode.CLOSING:
			span_clock = maxi(0, span_clock - 1)
			if span_clock == 0 and player != SPAN:
				span = SpanMode.PARKED
				message = "Turntable parked across the empty channel."
				mark("span_close")


func on_plate(pos: Vector2i) -> bool:
	return player == pos or echo == pos


func span_walkable() -> bool:
	return span == SpanMode.OPENED or span == SpanMode.CLOSING


func mark(kind: String) -> void:
	events.append({"kind": kind, "tick": tick})


func state() -> Dictionary:
	var tape_places: Array[String] = []
	for pos in tape: tape_places.append(PLACES[pos])
	return {"tick": tick, "player": PLACES[player], "item": Item.keys()[item], "recording": recording,
		"tape": tape_places, "rewind_ticks": rewind, "replay_tick": replay_tick,
		"echo": PLACES.get(echo, "—"), "fire_plate": on_plate(FIRE), "call_plate": on_plate(CALL),
		"firing_ticks": firing, "span": SpanMode.keys()[span], "span_ticks": span_clock,
		"won": won, "message": message, "events": events.duplicate(true)}
