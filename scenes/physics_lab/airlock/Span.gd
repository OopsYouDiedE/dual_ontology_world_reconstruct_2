extends RefCounted
## One independently sampled span. Eye counts are world facts, never permission flags.
const GRACE := 60
const RED_LIMIT := 40
var solid := false
var dark := 0
var red := 0

func step(eyes: int) -> void:
	red = red + 1 if eyes == 2 else 0
	if eyes > 0:
		dark = 0
		solid = true
	elif solid:
		dark += 1
		if dark >= GRACE: solid = false
