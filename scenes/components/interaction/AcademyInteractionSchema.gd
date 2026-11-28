extends RefCounted
class_name AcademyInteractionSchema
## The single data contract between "things you can select in the scene" and
## "the UI that presents them" (DualModeInteractionHud C+ / Detroit three-state).
##
## Scene side (AcademyInteractable nodes, level providers, room target lists) only ever
## produces descriptors built here. UI side only ever consumes descriptors validated here.
## Neither side references the other.
##
## Group descriptor:
##   id: String (unique per frame)          title: String
##   anchor_world: Vector3                  hotspots: Array[Dictionary] (>= 1)
##   optional: dist_selected / dist_activatable / dist_potential: float, force_selected: bool
## Hotspot descriptor:
##   id: String (unique per frame)          part_name: String     verb: String
##   world_pos: Vector3                     callback: Callable (fires on E / 1-4 / click)
##   optional: force_selected: bool, action_id: String

const KEY_PREFIXES := ["E · ", "[E] ", "E - ", "E: ", "[E]"]

static func hotspot(id: String, part_name: String, verb: String, world_pos: Vector3, callback: Callable, extra := {}) -> Dictionary:
	var h := {
		"id": id,
		"part_name": part_name,
		"verb": strip_key_prefix(verb) if not verb.is_empty() else part_name,
		"world_pos": world_pos,
		"callback": callback,
	}
	h.merge(extra, true)
	return h

static func group(id: String, title: String, anchor_world: Vector3, hotspots: Array, extra := {}) -> Dictionary:
	var typed: Array[Dictionary] = []
	for h in hotspots:
		if h is Dictionary:
			typed.append(h)
	var g := {
		"id": id,
		"title": title,
		"anchor_world": anchor_world,
		"hotspots": typed,
	}
	g.merge(extra, true)
	return g

## One group with one hotspot: the common "single object, single verb" case.
static func single(id: String, title: String, world_pos: Vector3, verb: String, callback: Callable, extra := {}) -> Dictionary:
	var hs := hotspot(id, title, verb, world_pos, callback)
	if extra.has("force_selected"):
		hs["force_selected"] = extra.force_selected
	return group(id, title, world_pos, [hs], extra)

## The UI draws its own key cap, so verbs never carry "E · " style prefixes.
static func strip_key_prefix(verb: String) -> String:
	for pref in KEY_PREFIXES:
		if verb.begins_with(pref):
			return verb.substr(pref.length()).strip_edges()
	return verb

## Returns a list of human-readable contract violations (empty when valid).
static func validate_groups(groups: Array) -> PackedStringArray:
	var errors := PackedStringArray()
	var group_ids := {}
	var hotspot_ids := {}
	for gi in groups.size():
		var g = groups[gi]
		if not g is Dictionary:
			errors.append("group[%d] is not a Dictionary" % gi)
			continue
		var gid := str(g.get("id", ""))
		if gid.is_empty():
			errors.append("group[%d] has empty id" % gi)
		elif group_ids.has(gid):
			errors.append("duplicate group id '%s'" % gid)
		group_ids[gid] = true
		if not g.get("anchor_world", null) is Vector3:
			errors.append("group '%s' anchor_world must be Vector3" % gid)
		var hs = g.get("hotspots", [])
		if not hs is Array or (hs as Array).is_empty():
			errors.append("group '%s' needs at least one hotspot" % gid)
			continue
		for h in hs:
			if not h is Dictionary:
				errors.append("group '%s' has a non-Dictionary hotspot" % gid)
				continue
			var hid := str(h.get("id", ""))
			if hid.is_empty():
				errors.append("group '%s' has a hotspot with empty id" % gid)
			elif hotspot_ids.has(hid) and hotspot_ids[hid] != gid:
				errors.append("hotspot id '%s' reused across groups '%s' and '%s'" % [hid, hotspot_ids[hid], gid])
			hotspot_ids[hid] = gid
			if not h.get("world_pos", null) is Vector3:
				errors.append("hotspot '%s' world_pos must be Vector3" % hid)
			var cb = h.get("callback", null)
			if not (cb is Callable and (cb as Callable).is_valid()):
				errors.append("hotspot '%s' has no valid callback" % hid)
	return errors
