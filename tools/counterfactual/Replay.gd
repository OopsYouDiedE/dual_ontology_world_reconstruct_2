extends RefCounted
## Compile sparse 1-based edge/level input receipts for the real Model.step API.

static func compile(rows: Array) -> Dictionary:
	var ticks := {}
	var last := 0
	for value in rows:
		if not value is Dictionary:
			return {"error": "Each input row must be an object."}
		var row: Dictionary = value
		var tick: Variant = row.get("tick", 0)
		var count: Variant = row.get("for", 1)
		if not _whole_positive(tick) or not _whole_positive(count):
			return {"error": "Input tick and hold duration must be positive whole numbers."}
		var edge: Variant = row.get("press", "")
		var target: Variant = row.get("target", "")
		var hold: Variant = row.get("hold", "")
		if not edge is String or not target is String or not hold is String:
			return {"error": "Input press, target and hold must be strings."}
		if (edge.is_empty() and hold.is_empty()) or (int(count) > 1 and hold.is_empty()):
			return {"error": "Input row needs a press or hold; only a hold can extend a row."}
		if not target.is_empty() and edge != "move":
			return {"error": "Only a move edge takes a target."}
		var first := int(tick)
		var stop := first + int(count)
		for at in range(first, stop):
			var frame: Dictionary = ticks.get(at, {})
			if not edge.is_empty() and at == first:
				if frame.has("press"):
					return {"error": "Two press edges at tick %d." % at}
				frame["press"] = edge
				if not target.is_empty():
					frame["target"] = target
			if not hold.is_empty():
				if frame.has("hold"):
					return {"error": "Two hold levels at tick %d." % at}
				frame["hold"] = hold
			ticks[at] = frame
		last = maxi(last, stop - 1)
	return {"ticks": ticks, "last_tick": last}

static func _whole_positive(number: Variant) -> bool:
	return (number is int or number is float) and number >= 1 and number <= 1_000_000 and number == floorf(number)
