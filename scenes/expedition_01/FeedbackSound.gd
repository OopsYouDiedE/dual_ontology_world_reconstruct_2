@tool
extends RefCounted
## Edited location and foley recordings. Source and CC0 credits are in audio/README.md.
const SPRING=preload("audio/spring.ogg")
static func loop(source:AudioStreamOggVorbis)->AudioStreamOggVorbis:
	var track:=source.duplicate() as AudioStreamOggVorbis
	track.loop=true
	return track
static func clips()->Dictionary:
	return {
		"cue":preload("audio/cue.ogg"), "page":preload("audio/page.ogg"), "ink":preload("audio/ink.ogg"), "book_close":preload("audio/book_close.ogg"),
		"gate":preload("audio/gate.ogg"), "lever":preload("audio/lever.ogg"), "chain":preload("audio/chain.ogg"),
		"escape":preload("audio/escape.ogg"), "airlock":preload("audio/airlock_soft.ogg"), "opening_tail":preload("audio/opening_tail.ogg"),
		"hum":preload("audio/hum.ogg"), "spring":SPRING, "set":preload("audio/set.ogg"), "tick":preload("audio/tick.ogg"),
		"bell":preload("audio/bell.ogg"), "alarm":preload("audio/alarm.ogg"), "ambience":loop(preload("audio/ambience.ogg")),
		"shaft":loop(preload("audio/shaft.ogg")), "cello":loop(preload("audio/cello.ogg")),
		"stone":preload("audio/stone.ogg"), "wood":preload("audio/wood.ogg"), "iron":preload("audio/iron.ogg"),
		"quiet":preload("audio/quiet.ogg"), "breath":preload("audio/breath.ogg"),
		"gallery_bell":loop(preload("audio/gallery_bell.ogg")), "gallery_impact":preload("audio/gallery_impact.ogg"),
		"glass_breakout":preload("audio/glass_breakout.ogg"), "hale_breath":preload("audio/hale_breath.ogg"),
		"rumble":preload("audio/rumble.ogg"), "scream":preload("audio/scream.ogg"),
	}
