@tool
extends Marker3D
class_name AcademyHotspot
## One selectable part of an AcademyInteractable (e.g. "Center Brass Pin" on the pendulum).
## Place as a child of an AcademyInteractable; its global position is the UI anchor.
## Pure scene data: it never references any UI node.

@export var hotspot_id := ""
@export var part_zh := ""
@export var part_en := ""
@export var verb_zh := "查看"
@export var verb_en := "Inspect"
## Emitted to the level as `action_requested(action_id, ctx)` when chosen.
@export var action_id := ""
## Optional manifest dialogue id the level plays when chosen.
@export var dialogue_id := ""
## Only offered once the level raised this flag (AcademyInteractionDirector.set_flag).
@export var unlock_flag := ""
@export var enabled := true

func resolved_id(owner_id: String) -> String:
	return hotspot_id if not hotspot_id.is_empty() else "%s.%s" % [owner_id, name]
