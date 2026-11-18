extends RefCounted
## Read-only encounter catalog. Each call returns its own option array.

const NAMES := ["Mara", "Elias", "June", "Rowan", "Iris"]
const SKILLS := {
	"Mara": "Sound mapping: identifies which direction an echo actually came from.",
	"Elias": "Optics: catches reflections acting ahead of their subjects.",
	"June": "Archive work: distinguishes a true record from an overwritten one.",
	"Rowan": "Cartography: aligns routes against landmarks that stay put.",
	"Iris": "Rhythm counting: recognizes an extra beat in a repeating signal.",
}

const ENCOUNTERS := [
	{
		"key": "empty_pool",
		"clue": "The motel pool is dry. EXIT is painted above a ladder. Your whisper comes back from the tiled stairs; the ladder answers in a stranger's voice.",
		"options": ["Take the ladder", "Take the tiled stairs", "Follow the stranger's voice"],
		"safe": 1,
		"rule": "In the empty pool, use the route that returns your own voice.",
		"helper": "Mara",
	},
	{
		"key": "borrowed_reflection",
		"clue": "Three mirrors stand in a school corridor. The tall one blinks first; the silver one never blinks. In the hand mirror, your reflection blinks when you do.",
		"options": ["Take the hand mirror", "Take the tall mirror", "Take the silver mirror"],
		"safe": 0,
		"rule": "Carry only the mirror that moves in time with you.",
		"helper": "Elias",
	},
	{
		"key": "future_checkout",
		"clue": "The library has your checkout slip dated tomorrow and another dated today. Today's ink is still wet. A blank slip begins printing your name by itself.",
		"options": ["Stamp tomorrow's slip", "Wait for the blank slip", "Stamp today's slip"],
		"safe": 2,
		"rule": "Check out on the day you are living; the library can reserve later dates for itself.",
		"helper": "June",
	},
	{
		"key": "paper_constellation",
		"clue": "A child's paper sky hangs behind the playroom glass. When you sidestep, the moon and blue star slide toward you. Their side of the glass fogs with breath. One pinprick stays above the chimney.",
		"options": ["Walk toward the painted moon", "Walk toward the fixed light", "Walk toward the blue star"],
		"safe": 1,
		"rule": "Follow the light that stays over the chimney. The moving stars are tracking you.",
		"helper": "Rowan",
	},
	{
		"key": "extra_bell",
		"clue": "The station timetable promises two chimes for your train. The first carriage rings once, the middle rings twice, and the rear rings three times. No conductor is visible.",
		"options": ["Board the middle carriage", "Board the first carriage", "Board the rear carriage"],
		"safe": 0,
		"rule": "Board the carriage whose chime count matches the timetable.",
		"helper": "Iris",
	},
]


static func encounter(seed_value: int, id: String) -> Dictionary:
	var definition: Dictionary = ENCOUNTERS[_catalog_index(seed_value, id)]
	var order := _shuffle(definition.options.size(), ("options:%d:%s" % [seed_value, id]).sha256_buffer())
	var options: Array = []
	for source_index in order:
		options.append(definition.options[source_index])
	return {
		"key": definition.key,
		"clue": definition.clue,
		"options": options,
		"safe": order.find(definition.safe),
		"rule": definition.rule,
		"helper": definition.helper,
	}


static func _catalog_index(seed_value: int, id: String) -> int:
	var section := id.get_slice("_", 0)
	var suffix := id.get_slice("_", 1)
	var size := ENCOUNTERS.size()
	if section in ["approach", "expedition"] and id.get_slice_count("_") == 2 and suffix.is_valid_int():
		var room_number := suffix.to_int()
		if room_number > 0:
			var offset := room_number - 1
			@warning_ignore("integer_division")
			var block := offset / size
			# Every contiguous, aligned five-room block draws all rules once.
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
