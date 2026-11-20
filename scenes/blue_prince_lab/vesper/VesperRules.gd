extends RefCounted
## The same cone is sampled by rules (local metres) and materials (world metres).
const SOURCE := Vector3(1.50, 1.48, 2.45)
const WHEEL := Vector3(-2.35, 1.25, -0.25)
const WEIGHT := Vector3(2.60, 2.02, -2.45)
const SPAN := Vector3(0, 0, -2.5)
const TARGETS := [Vector3.ZERO, WHEEL, SPAN]
const HALF_ANGLE := 18.0
const REACH := 11.0
const ACTIONS := [&"leaf", &"lamp", &"wind", &"cross"]
var cinder := false
var aim := 0
var released := false
var crossed := false

func direction() -> Vector3:
	return SOURCE.direction_to(TARGETS[aim])

func local_cinder(p: Vector3, axis := Vector3.ZERO) -> bool:
	var delta := p - SOURCE
	var inside := aim != 0 and delta.length() <= REACH and delta.normalized().dot(direction() if axis==Vector3.ZERO else axis) >= cos(deg_to_rad(HALF_ANGLE))
	return cinder != inside

func bridge_whole(axis := Vector3.ZERO) -> bool:
	# Convex cone and span: check the walking strip at both lips of the trench.
	for x: float in [-0.43, 0.43]:
		for z: float in [-4.0, -1.0]:
			if not local_cinder(Vector3(x, 0, z),axis): return false
	return true

func act(action: StringName) -> String:
	if crossed: return "The witness has signed the night register."
	match action:
		&"leaf":
			cinder = not cinder
			return "The leaf turns. The winding you leave behind stays in the iron."
		&"lamp":
			aim = (aim + 1) % TARGETS.size()
			return ["The shutter closes.", "The lens catches the winding post.", "The lens lies along the broken crossing."][aim]
		&"wind":
			if released: return "The ratchet holds. Its teeth remember."
			if not local_cinder(WEIGHT): return "The counterweight lies cold. Read the leaf of the fire."
			if local_cinder(WHEEL): return "The weight hangs ready, but its winding wheel burned away."
			released = true
			return "One turn. The fire-door bolt lifts in both years."
		&"cross":
			if not released: return "The brass bolt still holds the archive door."
			if local_cinder(Vector3(0, 1.1, -9.13)): return "Only a bricked arch stands in the year of the fire."
			if not bridge_whole(): return "The middle span is missing. Bring its earlier steps into the light."
			crossed = true
			return "Recovered: the night register. The same name signed for the key in both years."
	return ""

func code() -> int:
	return int(cinder) + 2 * aim + 8 * int(released) + 16 * int(crossed)
