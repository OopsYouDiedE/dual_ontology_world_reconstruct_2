extends RefCounted
## Server-side room state. Pressure, retained return and carry load can reinforce one another.
const Rooms := preload("Rooms.gd")
const EFFECTS := {
	"coupon":"The returned copy carries a clean receipt.", "issue":"The hatch issues your field manual.",
	"returns_file":"The empty return comes back, and the trapped porter climbs out behind it.",
	"returns_key":"The cord goes slack. The porter gets the return hatch open from the inside.",
	"booths":"Each booth has its own interval. You can see each other through the brass grille.",
	"sequence":"The first line rests while the next person works. The next return is an ordinary click.",
	"adopt":"You follow their version for this crossing. The common line returns one reply.",
	"pump":"The dry gutter takes the wash. The lower door opens on a clean tread.",
	"awning":"You wait in the lee of the tray. One by one, your packets come out dry.",
	"balance":"The cage settles level with the landing. Your weight no longer jolts the gate.",
	"under":"You release the escape catch and duck underneath the stopped cage.",
	"benches":"Separate benches give each card a place. Everyone makes it to the far door with their own receipt.",
	"one_locker":"The lockers close between crossings. The ward bell sounds further away with each person through.",
	"on_bell":"You cross on the bell, when the pull has slackened.",
	"early":"The seals hold the drawbar for you. You take the porter’s crate before the bell.",
	"shoe":"The service shoe carries the load. You leave by the maintenance passage, past the drawbar.",
	"depositions":"Both accounts go into the arrival book. You bring their signed extracts to the outer wing.",
	"survey":"You copy the audited line onto the survey. The Hall opens the outer wing.",
	"print":"The bath clears around one legible image. The names match your party.",
	"contact":"You take a dry contact print without using the open bath.",
	"parallel":"Each line prints its own slip. Stapled in arrival order, the names match the manifest.",
	"common":"Your agreed order goes out once. The private return clicks shut behind it.",
	"seal":"You file the names, and the Observatory bell rings once, toward the Hall.",
	"wind":"The wheel travels one full turn. The bell sounds over the Hall, with your names in the clamp."
}

var stage: String
var variant: bool
var drive := 0
var wet := 0
var echo := 0
var load_force := 0
var flags := {}
var report: Array[String] = []
var moves: Array[String] = []
var completed := false
var route := ""
var looked := false

func _init(chapter: String, mirror: bool) -> void:
	stage = chapter
	variant = mirror
	drive = 2 + int(variant)
	wet = 2 if stage in ["wash", "airlock", "darkroom"] else 0
	echo = 3 if stage in ["returns", "exchange", "airlock", "shutter", "darkroom", "relay", "meridian"] else 1
	load_force = 3 if stage in ["lift", "shutter", "meridian"] else 1

func read(group: int) -> String:
	if group == 0: looked = true
	var seen := Rooms.observation(stage, group, variant)
	if not moves.is_empty() and group > 0:
		seen += "\n\n" + _symptoms()
	return seen

func _symptoms() -> String:
	if flags.has("brake") and stage == "lift": return "The service rail is motionless. The dog is still seated."
	if flags.has("bath") and stage == "darkroom": return "The test strip stays sharp at the rim of the bath."
	if flags.has("bleed") and stage == "shutter": return "The drawbar has slack. The fixed mark on the register is still readable."
	if flags.has("rewind"): return "One clean sheet winds onto the reel."
	if flags.has("pin"): return "A worn pin now holds the inner catch."
	if flags.has("sleeve"): return "The sleeve holds at the seam. Its outside is beaded with water."
	if flags.has("partition"): return "Your party can see each other through the two grille openings. The lines are apart."
	if flags.has("carrier"): return "The carrier is shut. Its bright edge has stopped moving."
	if flags.has("docket"): return "The sealed docket is ready under the clamp."
	if flags.has("mute"):
		return "The distant bell can be heard separately from the ticking in the cabinet."
	if wet + drive > 4: return "A damp line advances up the rim as the apparatus takes the weight."
	if echo * drive > 5: return "The last click repeats half a beat ahead of the next."
	return "The return has gone quiet for a full beat."

func _control(id: String, text: String) -> Dictionary:
	return {"id":id, "text":text}

func options(group: int, protocols: Array, can_agree: bool) -> Array:
	if completed: return []
	var c := _control
	if group == 0:
		match stage:
			"intake": return [c.call("issue", "Take the Ivory handbook from the dispatch clip")]
			"wash": return [c.call("sleeve", "Pack the papers into the dry sleeve")]
			"meridian": return [c.call("docket", "Seal the paper docket in party order")]
		return []
	match stage:
		"intake": return [c.call("issue", "Take the issued handbook")] if group == 1 else [c.call("coupon", "Recover the returned Ivory copy")]
		"returns":
			return [c.call("tie", "Tie off the return cord"), c.call("slot_reed", "File the REED tag"), c.call("slot_ash", "File the ASH tag")] if group == 1 else [c.call("key", "Use the porter’s service key")]
		"exchange":
			if group == 1:
				var calls := [c.call("mute", "Plug the common mouthpiece"), c.call("all_call", "Follow the notice · all answer the first call")]
				if protocols.size() > 1 and not flags.has("asked"): calls.append(c.call("ask_early", "Ask the crew to switch to the Ivory copy"))
				if _uniform_partners(protocols): calls.append(c.call("adopt", "Follow your companion’s %s procedure this time" % protocols[1]))
				return calls
			return [c.call("partition", "Separate the booths · keep individual copies"), c.call("booths", "Use both booths at the same time"), c.call("sequence", "Run one copy per turn of the spool")]
		"wash":
			return [c.call("unload", "Open the lower relief"), c.call("pump_yard", "Send the wash to the yard"), c.call("pump_cistern", "Send the wash to the cistern")] if group == 1 else [c.call("awning", "Wait out the surge under the drip tray")]
		"lift":
			return [c.call("trim_yard", "Shift the balancing shoe toward the yard"), c.call("trim_hall", "Shift the balancing shoe toward the Hall")] if group == 1 else [c.call("dog", "Seat the safety dog"), c.call("brake", "Set the service brake"), c.call("under", "Release the escape catch")]
		"airlock":
			return [c.call("dry", "Open the dry bench and the drying tray"), c.call("benches", "Cross on separate benches · use your own copies")] if group == 1 else [c.call("pin", "Pin the inner locker"), c.call("one_locker", "Pass one person at a time, resetting both catches"), c.call("together", "Follow the notice · deposit every packet and enter together")]
		"shutter":
			return [c.call("mute", "Mute the repeated bell"), c.call("on_bell", "Wait for the bell and cross")] if group == 1 else [c.call("bleed", "Back off the drawbar"), c.call("early", "Take the red amendment · cross early"), c.call("shoe", "Set the shoe against the service ledge")]
		"hall":
			return [c.call("depositions", "File the two independent witness accounts")] if group == 1 else [c.call("survey", "Copy the audited survey route")]
		"darkroom":
			return [c.call("carrier", "Close and rewind the carrier"), c.call("contact", "Make a dry contact print")] if group == 1 else [c.call("bath", "Set the bath at the pencil mark"), c.call("print_black", "Fix the black-side emulsion"), c.call("print_copper", "Fix the copper-side emulsion")]
		"relay":
			var orders := [c.call("mute", "Close the public horn iris"), c.call("common", "Dispatch under a common order")]
			if can_agree: orders.append(c.call("agree", "Ask the crew to adopt a common Ivory order"))
			return orders if group == 1 else [c.call("partition", "Separate the return windings"), c.call("parallel", "Print independently · attach the slips in arrival order")]
		"meridian":
			return [c.call("mute", "Close the Observatory return"), c.call("seal", "File the party names and ring the morning bell")] if group == 1 else [c.call("brake", "Take the train off the winding wheel"), c.call("wind", "Wind by hand with the sealed docket")]
	return []

func _uniform_partners(protocols: Array) -> bool:
	if protocols.size() < 2 or protocols[1] == protocols[0]: return false
	for i in range(2, protocols.size()):
		if protocols[i] != protocols[1]: return false
	return true

func _uniform(protocols: Array) -> bool:
	for p in protocols:
		if p != protocols[0]: return false
	return true

func _ok(line: String) -> Dictionary:
	return {"line":line, "damage":0, "clear":false}

func _hurt(line: String, damage := 2) -> Dictionary:
	return {"line":line, "damage":damage, "clear":false}

## An order becomes one reservation per person, for a line or a bench in a specific beat.
## Alternatives solve the same disagreement by changing the scheduling resource.
func _manifest(id: String, protocols: Array) -> Array[Dictionary]:
	var packet_room := id in ["benches", "one_locker"]
	var divided := id in ["booths", "benches", "parallel"]
	var serial := id in ["sequence", "one_locker"]
	var compromise := id == "adopt"
	var rows: Array[Dictionary] = []
	for i in protocols.size():
		var edition: String = protocols[1] if compromise else protocols[i]
		var operation: String = {"Ivory":"dry bench / carry", "Cobalt":"pass-through / leave", "Ochre":"drying tray / air"}[edition] if packet_room else {"Ivory":"silence / wait", "Cobalt":"held call / reply", "Ochre":"separate relay / file"}[edition]
		var slot := i % 2 if divided else 0
		var beat := i if serial else (i >> 1 if divided else 0)
		var use: String = Rooms.VERSIONS[edition][1 if packet_room else 0]
		rows.append({"version":edition, "slot":slot, "beat":beat, "operation":operation, "practice":use})
	return rows

func _clear(id: String, protocols: Array, extra := 0) -> Dictionary:
	var manifest: Array[Dictionary] = []
	if id in ["booths", "sequence", "adopt", "benches", "one_locker", "parallel", "common"]:
		manifest = _manifest(id, protocols)
		var reservations := {}
		for p in manifest:
			var key := Vector2i(p.slot, p.beat)
			if reservations.has(key) and reservations[key] != p.operation:
				return _ok("The same station has two incompatible jobs in the same interval. Use two stations or reserve successive turns.")
			reservations[key] = p.operation
	completed = true
	route = id
	report.clear()
	for p in manifest: report.append(p.practice)
	var minutes: int = 3 + (manifest[-1].beat * 6 if not manifest.is_empty() else 0)
	if id in ["awning", "on_bell", "shoe", "under", "wind"]: minutes = 18
	var line: String = EFFECTS[id]
	if flags.has("felt"):
		extra += 2 if stage == "meridian" else 1
		line += " The padded case kept the salvage intact."
	elif flags.has("ratchet"):
		minutes = 3
		line += " The locked shaft saves the reset interval."
	return {"line":line, "damage":0, "clear":true, "bonus":extra, "manifest":manifest, "minutes":minutes}

func _record(id: String, line: String) -> Dictionary:
	flags[id] = true
	return _ok(line)

func tool_group(tool: String) -> int:
	if tool == "felt" and stage in ["returns","exchange","wash","airlock","shutter","darkroom","relay","meridian"]: return 1
	if tool == "ratchet" and stage in ["lift","airlock","shutter","meridian"]: return 2
	return -1

func tool_label(tool: String) -> String:
	return "Pack: fit felt · save the salvage (1 felt)" if tool == "felt" else "Pack: arrest the shaft · fast passage (1 ratchet)"

func use_tool(group: int, tool: String, pack: Dictionary) -> Dictionary:
	if completed or group < 0 or tool_group(tool) != group or flags.has("felt") or flags.has("ratchet") or pack.get(tool,0) < 1: return {}
	pack[tool] -= 1
	moves.append(tool)
	if tool == "felt":
		echo = 0
		wet = 0
		flags.sleeve = true
		flags.carrier = true
		return _record(tool,"The felt seats around the return. Water stays outside and the second signal dies.")
	drive = 0
	load_force = 0
	flags.brake = true
	flags.pin = true
	flags.bleed = true
	return _record(tool,"The ratchet takes the load. The maintenance catch can now be worked by hand.")

func act(group: int, id: String, protocols: Array, can_agree := false, witness_count := 0) -> Dictionary:
	if not options(group, protocols, can_agree).any(func(row): return row.id == id): return {}
	moves.append(id)
	match id:
		"issue", "coupon", "survey": return _clear(id, protocols)
		"tie":
			echo = 0
			return _record(id, "You bind the reel to its cleat. The porter stops knocking.")
		"key":
			if echo * drive > 5: return _ok("The key jumps out of the slot. Something is still pulling the return cord.")
			return _clear("returns_key", protocols)
		"slot_reed", "slot_ash":
			if (id == "slot_ash") != variant:
				return _hurt("The tag comes back with your name across it. A brass catch opens against your wrist.")
			return _clear("returns_file", protocols, 1)
		"mute":
			echo = 0
			return _record(id, "The common return goes quiet. You can hear the smaller fittings working.")
		"partition":
			return _record(id, "The separator engages. The two returns now have their own channels.")
		"ask_early":
			return _record("asked", "Your crew holds onto its copies. ‘Show me the return working. I won’t change the order while it’s still calling.’")
		"all_call":
			return _hurt("The FIRST CALL order fills the common line. The replies come back sharp enough to hurt.") if echo * drive > 5 else _ok("The common mouthpiece is plugged. The replies stop there; the gate stays shut.")
		"booths", "parallel":
			if not flags.has("partition"): return _ok("The returns are still joined. Separate them before taking independent readings.")
			return _clear(id, protocols, 1 if id == "parallel" else 0)
		"sequence":
			if echo * drive > 5: return _ok("Two clicks spill into one turn. Plug the common mouthpiece before spooling one copy at a time.")
			return _clear(id, protocols)
		"adopt":
			if echo * drive > 5: return _ok("The common line repeats even a single reply. Plug the unused mouthpiece first.")
			return _clear(id, protocols)
		"unload":
			drive = 1
			return _record(id, "The relief shudders once. Water falls away from the lower threads.")
		"sleeve": return _record(id, "Your packet goes into the intact sleeve, waxed side out.")
		"pump_yard", "pump_cistern":
			if wet + drive > 4: return _hurt("A hot wash comes up the handwheel. The relief snatches against its stop.")
			if (id == "pump_cistern") != variant: return _hurt("Water pushes through the damp collar and runs down your sleeves.")
			return _clear("pump", protocols, 1)
		"awning":
			if not flags.has("sleeve"): return _ok("Spray reaches under the awning. Close the packet in the dry sleeve before using it.")
			return _clear(id, protocols)
		"dog":
			load_force = 1
			return _record(id, "The dog drops into a notch. The cage stops pulling on the drum.")
		"brake":
			drive = 0
			return _record(id, "The service brake bites. The crawlway cover is still held against the frame.")
		"trim_yard", "trim_hall":
			if drive + load_force > 4: return _hurt("The uncaught cage swings into the landing when you touch the shoe.")
			if (id == "trim_hall") != variant: return _ok("The heavy side sinks further. The dog holds; try the other run.")
			return _clear("balance", protocols, 1)
		"under":
			if not flags.has("brake"): return _ok("The rail is moving past the opening. Set the brake before you get underneath.")
			return _clear(id, protocols)
		"dry":
			wet = 0
			return _record(id, "You swing open the drying tray and put the dry bench down beside it.")
		"benches":
			if wet + drive > 3: return _ok("There’s only one usable bench. Open the drying tray before dividing up.")
			return _clear(id, protocols)
		"pin":
			drive = 0
			return _record(id, "The pin holds the inner catch while you work on the other locker.")
		"one_locker":
			if not flags.has("pin"): return _ok("Both catches fly open together. Hold the inner one with its travel pin first.")
			return _clear(id, protocols, 1)
		"together":
			if not _uniform(protocols): return _ok("Your companions keep hold of their copies. The admission bell rings on an empty joint slot.")
			return _hurt("The combined admission slot stamps a blot across every name.")
		"bleed":
			drive = 1
			return _record(id, "The drawbar recedes a thumb’s width from the jamb.")
		"on_bell":
			if echo * drive > 5: return _ok("You hear the bell twice, the second sound arriving first. Mute the repeating return and listen again.")
			return _clear(id, protocols)
		"early":
			if not variant or drive + load_force > 4: return _hurt("The drawbar catches you before the bell. A failed seal tears through the return slot.", 3)
			return _clear(id, protocols, 2)
		"shoe":
			if not flags.has("bleed"): return _ok("The shoe won’t set while the drawbar presses into the jamb.")
			return _clear(id, protocols)
		"depositions":
			if witness_count < 2: return _ok("The clerk needs two signed accounts. Speak to the witnesses, or use the annotated survey.")
			return _clear(id, protocols, 1)
		"bath":
			wet = 0
			return _record(id, "The bath falls below the pencil mark. The test strip stops bleeding.")
		"print_black", "print_copper":
			if (wet + drive > 4) or ((id == "print_copper") != variant) or (not flags.has("bath") and echo > 2): return _hurt("The faces lose their edges and your fingertips go white. You can still close the carrier.")
			return _clear("print", protocols, 1)
		"carrier":
			echo = 0
			return _record(id, "The carrier shuts. A single dark frame winds back under the clamp.")
		"contact":
			if not flags.has("carrier"): return _ok("You need one protected frame. Close the negative carrier and rewind it.")
			return _clear(id, protocols)
		"agree": return {"line":"They read back the agreed Ivory order. All expedition copies now carry the same countersignature.", "damage":0, "clear":false, "agree":true}
		"common":
			if not _uniform(protocols): return _ok("The crew reads different instructions. File a common order with their consent or run separate windings.")
			if echo * drive > (2 if variant else 5): return _hurt("The horn returns the same order under an extra signature. Something catches your hand in the iris.")
			return _clear(id, protocols, 2)
		"docket": return _record(id, "You seal the hand-carried docket with the party names in crossing order.")
		"seal":
			if echo * drive > 5: return _ok("A second set of names appears in the wet ink. Close the return before filing.")
			return _clear(id, protocols)
		"wind":
			if not flags.has("docket") or not flags.has("brake"): return _ok("The wheel needs a sealed docket in the clamp and the train off its shaft.")
			return _clear(id, protocols)
	return {}
