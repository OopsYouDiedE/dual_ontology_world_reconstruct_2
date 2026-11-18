extends RefCounted
## Template-specific encounters; the journal records three shared field rules.

const NAMES := ["Mara", "Elias", "June", "Rowan", "Iris"]
const SKILLS := {
	"Mara": "Sound mapping: separates the source of a sound from its echoes.",
	"Elias": "Close observation: catches reflections, moisture, and shifts in alignment.",
	"June": "Records and traces: checks what was physically left behind.",
	"Rowan": "Cartography: takes bearings from landmarks fixed to the building.",
	"Iris": "Timing: counts the beats and puts actions in the right order.",
}

const RULES := [
	"Act when the signal matches what actually happens.",
	"Take your bearing from something fixed to the building.",
	"Follow the physical trace when a claim contradicts it.",
]

# Rows follow RULES order: objective, clue, correct action, two alternatives, helper, hint.
const ROOMS := {
	"kitchen": [
		[
			"Check the kettle on the stove",
			"Steam rises from the real kitchen stove. The speaking tube whistles before its steam arrives; the kettle whistles only as steam reaches its spout.",
			["Use the kettle whistle", "Answer the speaking tube", "Pull the door chain"],
			"Mara", "Listen for the whistle that follows the steam.",
		],
		[
			"Check the chain at the kitchen door",
			"The outer door has a ratchet chain. Its wall anchor stays still when the door shudders; the loose tail and swinging door handle both jump.",
			["Brace the chain at its wall anchor", "Catch the loose chain tail", "Brace against the door handle"],
			"Rowan", "The wall anchor is fixed to the room.",
		],
		[
			"Check the stove and wall speaking tube",
			"A kettle has just boiled dry. A fresh ring of soot on the stove shows which burner was used; the speaking tube insists it was the clean burner.",
			["Check the burner with the soot ring", "Check the clean burner", "Question the speaking tube"],
			"June", "Use the physical trace on the stove.",
		],
	],
	"lecture": [
		[
			"Watch the lecturer’s chalk tray",
			"Chalk taps the tray in time with the lecturer’s hand. The upper seats echo before each tap; the blackboard answers one beat late.",
			["Signal with the chalk on the tray", "Answer the upper seats", "Tap back on the blackboard"],
			"Iris", "Use the sound that coincides with the hand.",
		],
		[
			"Sight along the tiered seats and blackboard",
			"From the tiered seats, the lectern and its chalk tray seem to slide sideways. The bottom edge of the wall-mounted blackboard stays aligned with the brickwork.",
			["Align with the blackboard edge", "Align with the lectern", "Align with the chalk tray"],
			"Elias", "Compare each landmark against the wall as you move.",
		],
		[
			"Read the blackboard from the lectern",
			"The back row calls out a room number. At the lectern you can see fresh chalk fills the wide number on the board, while the number below it is an erased outline.",
			["Copy the fresh chalk number", "Copy the erased outline", "Copy the number called from the back row"],
			"June", "Fresh chalk fills a stroke; an erasure leaves a ghost.",
		],
	],
	"clinic": [
		[
			"Inspect the dressing station",
			"At the medical desk, the order is clean dressing, change, then used dressing into the sealed bag. A voice at the cot is already calling for disposal before the change.",
			["Set out a clean dressing first", "Seal the disposal bag first", "Carry the used dressing back to the clean desk"],
			"Iris", "The used-dressing step belongs after the change.",
		],
		[
			"Check the cot and medical desk",
			"The clinic cot rolls when you lean on it, and the dirty-dressing bag swings. The medical desk stays flush with the wall.",
			["Take your bearing from the medical desk", "Take your bearing from the cot", "Take your bearing from the hanging bag"],
			"Rowan", "Use the piece that keeps its position against the wall.",
		],
		[
			"Inspect the clean and used dressings",
			"At the medical desk one packet still has its seal; a loose dressing has a brown stain. The cot’s empty tray has CLEAN scratched into it.",
			["Take the sealed dressing packet", "Take the stained dressing", "Use the empty tray as a dressing"],
			"June", "The intact packet is evidence that its contents are clean.",
		],
	],
	"dining": [
		[
			"Check the serving hatch beside the long table",
			"At the serving hatch the plate touches the counter on the second tap. The long table rattles a beat early and the kitchen doorway echoes late.",
			["Collect the plate on the second tap", "Follow the table rattle", "Answer the doorway echo"],
			"Iris", "Time the pickup to the plate arriving on the counter.",
		],
		[
			"Sight the long table from the service counter",
			"The long dining table and its benches creep apart when you turn your head. The serving counter stays square to the kitchen opening.",
			["Cross beside the fixed serving counter", "Cross along the drifting long table", "Follow the moving benches"],
			"Rowan", "The counter still lines up with the kitchen opening.",
		],
		[
			"Inspect the long table and serving counter",
			"A wet plate ring at the serving counter lines up with drops leading to one place at the long table. The other place settings are dry despite the sound of cutlery.",
			["Set the plate at the place with the drip trail", "Set the plate at the sound of cutlery", "Set the plate at a dry place"],
			"June", "Follow the drops from the serving counter to the place setting.",
		],
	],
	"valve_gallery": [
		[
			"Watch the low valve and bypass return",
			"The return pipe gives a second knock as the gauge settles. A knock at the low valve comes first, while a knock in the wall never moves the needle.",
			["Wait for the second knock at the return", "Follow the first knock at the low valve", "Follow the knock in the wall"],
			"Mara", "Match the knock to the needle settling.",
		],
		[
			"Check the low valve against its pipe supports",
			"The low valve wheel turns and the bypass line shivers. Only the pipe bracket bolted to the stone keeps the same position as you pass.",
			["Mark the bolted pipe bracket", "Mark the moving valve wheel", "Mark the shaking bypass line"],
			"Rowan", "Take position from the stone, not the moving hardware.",
		],
		[
			"Inspect the bypass and the low valve",
			"A fresh wet line runs along the bypass return; the low valve body is dry. A handprint on the wall points away from the pipe.",
			["Trace the wet bypass return", "Trace the dry valve body", "Follow the handprint away from the pipe"],
			"Elias", "Fresh moisture gives the return path away.",
		],
	],
	"service_stair": [
		[
			"Listen at the service stair and food lift",
			"The food-lift cable stops rattling as the tray reaches the landing. The steps creak early and the shaft echoes after the tray arrives.",
			["Cross when the food-lift cable falls quiet", "Cross at the first creak on the steps", "Cross at the shaft echo"],
			"Mara", "The cable goes quiet precisely when the tray reaches the landing.",
		],
		[
			"Check the service landing against the shaft",
			"The food-lift tray drops and its rope slips through the guide. The stone landing where the service stair turns stays level with its mortar line.",
			["Take your bearing from the stone landing", "Take your bearing from the food-lift tray", "Take your bearing from the sliding rope"],
			"Rowan", "The mortar line marks the fixed landing.",
		],
		[
			"Inspect the stairs beside the food-lift opening",
			"Flour from the food tray leaves a tread mark on the service stair. Loose flour on the shaft lip has no tread, though a voice calls from below.",
			["Follow the flour tread on the stair", "Follow the flour at the shaft lip", "Follow the voice down the shaft"],
			"June", "A tread mark shows where somebody actually stood.",
		],
	],
	"foyer": [
		[
			"Watch the forked foyer stair",
			"On the split stair, footsteps on the left flight match the moving feet. The right flight answers early and the upper gallery echoes late.",
			["Take the flight whose steps match the feet", "Take the flight that sounds first", "Follow the gallery echo"],
			"Mara", "Separate footsteps at their source from the gallery echo.",
		],
		[
			"Sight the split stair and upper gallery",
			"Both flights seem to swing away as you turn. The continuous upper gallery still meets the same wall corner.",
			["Use the fixed gallery corner", "Follow the swinging left flight", "Follow the swinging right flight"],
			"Rowan", "Use the gallery’s joint with the wall.",
		],
		[
			"Inspect the treads at the fork",
			"One flight has fresh scuffs leading up to the gallery. The other has dust across every tread. A voice upstairs points to the dusty side.",
			["Follow the freshly scuffed treads", "Follow the dusty treads", "Follow the voice instead of the treads"],
			"June", "Fresh scuffs show which flight was crossed.",
		],
	],
	"living_hall": [
		[
			"Watch the four-zone reconciliation table",
			"At the living-hall table, three tallies are set down. The fourth call comes while the last place is still empty. A second call comes as the last tally arrives.",
			["Reconcile when the fourth tally arrives", "Reconcile at the first call", "File the three tallies as complete"],
			"Iris", "Count the tallies on the table, then act.",
		],
		[
			"Sight the gathering table from the four zone entrances",
			"As you sidestep, loose chairs drift toward the zone entrances. The reconciliation table stays centered on the same floor joint.",
			["Meet at the table over the floor joint", "Follow the drifting chairs", "Meet at the shifting zone entrance"],
			"Rowan", "The floor joint gives you a stable meeting point.",
		],
		[
			"Compare the four zones’ tallies at the table",
			"Three tallies look identical from the doorway; the fourth has a fresh correction. At the table the marks on the back of its slip match the amended total.",
			["Use the correction backed by the slip", "Use the uncorrected doorway tally", "Copy the matching-looking totals unchecked"],
			"June", "Match the amended total to the marks on the slip.",
		],
	],
}

const STANDARD_ROOMS := ["kitchen", "lecture", "clinic", "dining", "valve_gallery", "service_stair"]


static func encounter(seed_value: int, id: String, template: String = "") -> Dictionary:
	var room := template if ROOMS.has(template) else id
	if not ROOMS.has(room):
		var entropy := ("room:%d:%s" % [seed_value, id]).sha256_buffer()
		room = STANDARD_ROOMS[_word(entropy, 0) % STANDARD_ROOMS.size()]
	var rule_index := _catalog_index(seed_value, id)
	var row: Array = ROOMS[room][rule_index]
	var order := _shuffle(3, ("options:%d:%s" % [seed_value, id]).sha256_buffer())
	var options: Array = []
	for source_index in order:
		options.append(row[2][source_index])
	return {
		"key": "%s_%d" % [room, rule_index],
		"objective": row[0],
		"clue": row[1],
		"options": options,
		"safe": order.find(0),
		"rule": RULES[rule_index],
		"helper": row[3],
		"hint": row[4],
	}

static func _catalog_index(seed_value: int, id: String) -> int:
	var section := id.get_slice("_", 0)
	var suffix := id.get_slice("_", 1)
	var size := RULES.size()
	if section in ["approach", "expedition"] and id.get_slice_count("_") == 2 and suffix.is_valid_int():
		var room_number := suffix.to_int()
		if room_number > 0:
			var offset := room_number - 1
			@warning_ignore("integer_division")
			var block := offset / size
			# Every contiguous, aligned three-room block draws all rules once.
			var deck := _shuffle(size, ("deck:%d:%s:%d" % [seed_value, section, block]).sha256_buffer())
			return deck[offset % size]
	return _word(("rule:%d:%s" % [seed_value, id]).sha256_buffer(), 0) % size


static func _shuffle(size: int, entropy: PackedByteArray) -> Array:
	var order := range(size)
	for i in range(size - 1, 0, -1):
		var j := _word(entropy, 4 * (size - 1 - i)) % (i + 1)
		var swap: int = order[i]
		order[i] = order[j]
		order[j] = swap
	return order


static func _word(bytes: PackedByteArray, offset: int) -> int:
	return (int(bytes[offset]) << 24) | (int(bytes[offset + 1]) << 16) | (int(bytes[offset + 2]) << 8) | int(bytes[offset + 3])
