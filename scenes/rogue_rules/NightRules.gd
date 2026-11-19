extends RefCounted
## Card and decisions share the same catalog; physical truth is derived from seed + room, not from sanity.

const SAVE_PATH := "user://night_field_card_v1.json"
const ORIGINAL := [
	"1. Compare the corridor's two clocks. If they disagree, turn back. If they match, walk on.",
	"2. When rain climbs toward the ceiling, keep to the brass strip until the lamp steadies.",
	"3. Never step through a shutter before its bell. A signature in red does not outrank a seal.",
	"4. Match signals to their source. Use fixed landmarks, and trust physical traces over voices.",
]
const FIRST_NOTE := "If the lights go out, keep one hand on the wall."

static func truth(seed_value: int, room: String, topic: String) -> bool:
	return (("%d:%s:%s" % [seed_value, room, topic]).sha256_buffer()[0] & 1) == 0

static func encounter(stage: String, variant: bool) -> Dictionary:
	match stage:
		"echo":
			return {"objective": "Compare your watch with the brass clock", "clue":
				"Your stopped watch reads 04:10. The riveted brass face reads %s. Do not read the glass." % ("04:11" if variant else "04:10"),
				"options": ["Walk on", "Turn back into the loop", "Force the unmarked door"], "safe": 1 if variant else 0,
				"rule": ORIGINAL[0], "helper": "Elias", "hint": "My watch agrees with yours. Check the face under the rivets."}
		"rain":
			return {"objective": "Find the brass strip at the lamp", "clue":
				"Rain climbs in the open aisle. Follow the brass strip to its end, then use E or confirm below. The red strip is exposed.",
				"options": ["Wait at the end of the brass strip", "Run across the exposed red strip"], "safe": 0,
				"rule": ORIGINAL[1], "helper": "Rowan", "hint": "Follow the BRASS marker to its end. I'll count the flashes from the dry side."}
		"rewrite":
			var trace := "The floor has an intact double seal; fresh bootprints cross it." if variant else "One seal has been scraped away. Bootprints stop at the shutter."
			return {"objective": "Read the Curator's red amendment", "clue":
				"THE CURATOR has written across rule 3: ‘CROSS BEFORE THE BELL.’\n" + trace,
				"options": ["Keep the original · wait for the bell", "Trust the red amendment · cross early"], "safe": 0,
				"rule": ORIGINAL[2], "helper": "June", "hint": "Only an intact double seal can hold the shutter open before the bell."}
	return {}

static func load_notes() -> Array[String]:
	var notes: Array[String] = [FIRST_NOTE]
	if not FileAccess.file_exists(SAVE_PATH): return notes
	var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(SAVE_PATH))
	if not data is Array: return notes
	notes.clear()
	for value in data:
		if value is String and not value.is_empty() and notes.size() < 4:
			notes.append(value.left(160))
	return notes

static func save_notes(notes: Array[String]) -> bool:
	var file := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if file == null: return false
	file.store_string(JSON.stringify(notes))
	return file.get_error() == OK

static func death_note(stage: String) -> String:
	match stage:
		"echo": return "Echo Corridor: two hands must agree. The clock behind glass is not a second source."
		"rain": return "Time Rain: the red aisle ages what it touches. Wait under the brass lamp."
		"rewrite": return "Curator's shutter: early crossing needs an intact double seal. Bootprints alone are not permission."
	return "When a room speaks your name, find the physical trace before you answer."
