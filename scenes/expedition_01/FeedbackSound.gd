@tool
extends RefCounted
## Edited location and foley recordings. Source and CC0 credits are in audio/README.md.
const SPRING=preload("audio/spring.ogg")
static func clips()->Dictionary:
	var bed:=preload("audio/ambience.ogg").duplicate() as AudioStreamOggVorbis
	bed.loop=true
	return {
		"cue":preload("audio/cue.ogg"), "page":preload("audio/page.ogg"), "ink":preload("audio/ink.ogg"),
		"gate":preload("audio/gate.ogg"), "lever":preload("audio/lever.ogg"), "chain":preload("audio/chain.ogg"),
		"escape":preload("audio/escape.ogg"), "airlock":preload("audio/airlock.ogg"),
		"hum":preload("audio/hum.ogg"), "spring":SPRING, "set":preload("audio/set.ogg"), "tick":preload("audio/tick.ogg"),
		"bell":preload("audio/bell.ogg"), "alarm":preload("audio/alarm.ogg"), "ambience":bed,
		"stone":preload("audio/stone.ogg"), "wood":preload("audio/wood.ogg"), "iron":preload("audio/iron.ogg"),
		"quiet":preload("audio/quiet.ogg"), "breath":preload("audio/breath.ogg"),
		"rumble":preload("audio/rumble.ogg"), "scream":preload("audio/scream.ogg"),
	}
