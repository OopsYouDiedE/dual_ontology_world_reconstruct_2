extends RefCounted
## A service line has two ends. A still listener can hear the other relay answer.
const PORTS := [Vector3(32.96, 1.70, 17.43), Vector3(36.04, 1.70, 17.43)]
const HATCH := Vector3(34.50, 1.58, 17.37)
const BEATS := [.48, .72]
var source := -1
var beat := 0
var age := 0.
var heard := false
var clear_sample := true
var open := false

func target() -> int:
	return 1 - source if source >= 0 else -1

func pending() -> bool:
	return source >= 0 and beat < BEATS.size()

func on_felt(p: Vector3, port: int) -> bool:
	return p.y > .51 and absf(p.x - PORTS[port].x) < .53 and p.z > 16.55 and p.z < 17.64

func strike(port: int) -> void:
	source = port
	beat = 0
	age = 0.
	heard = false
	clear_sample = true

## Returns one event per beat. Both beats must be heard in the same listening bay.
func advance(dt: float, feet: Vector3, speed: float) -> String:
	if not pending():
		return ""
	age += dt
	if age < BEATS[beat]:
		return ""
	clear_sample = clear_sample and on_felt(feet, source) and speed < .45
	beat += 1
	if not pending():
		heard = clear_sample
		return "answer" if heard else "masked"
	return "pulse" if clear_sample else "dull"
