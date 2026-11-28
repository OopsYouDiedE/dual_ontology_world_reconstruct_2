@tool
extends Node3D
class_name AcademyInteractable
## Scene-side "selectable object". Drop it into any level, attach it to any catalog item
## (AcademyFurnitureCatalog / ArchBuilder ComponentFactory), or edit it in the Component
## Library inspector. It only publishes data (AcademyInteractionSchema descriptors) and
## emits `activated`; it never touches the interaction HUD or any other UI node.
##
## Hotspots: child AcademyHotspot nodes. With no children the interactable offers one
## default hotspot at its own position using the title/verb below.

const Schema := preload("res://scenes/components/interaction/AcademyInteractionSchema.gd")
const R18n := preload("res://scenes/components/shared/R18n.gd")
const GROUP := &"academy_interactable"

signal activated(hotspot_id: String, action_id: String)

@export var interactable_id := ""
@export var title_zh := ""
@export var title_en := ""
@export var verb_zh := "查看"
@export var verb_en := "Inspect"
@export var action_id := ""
@export var dialogue_id := ""
@export var unlock_flag := ""
@export var enabled := true
## Offset of the UI anchor from this node's origin (e.g. lift above a table top).
@export var anchor_offset := Vector3(0.0, 0.75, 0.0)
@export_range(0.5, 6.0, 0.05) var dist_selected := 2.85
@export_range(1.0, 10.0, 0.05) var dist_activatable := 4.6
@export_range(2.0, 20.0, 0.1) var dist_potential := 9.5

func _enter_tree() -> void:
	add_to_group(GROUP)

func resolved_id() -> String:
	if not interactable_id.is_empty():
		return interactable_id
	var host := get_parent()
	return str(host.name) if host != null else str(name)

func display_title() -> String:
	var t := R18n.pick(title_zh, title_en)
	if t.is_empty():
		t = title_en if not title_en.is_empty() else title_zh
	return t if not t.is_empty() else resolved_id()

func anchor_world() -> Vector3:
	return global_position + anchor_offset if is_inside_tree() else position + anchor_offset

## Build the UI-agnostic descriptor. `flags` = level unlock flags; `on_activate` lets the
## director route the activation (it still emits `activated` on this node).
func describe(flags: Dictionary, on_activate: Callable = Callable()) -> Dictionary:
	if not enabled or not is_visible_in_tree():
		return {}
	if not unlock_flag.is_empty() and not bool(flags.get(unlock_flag, false)):
		return {}
	var gid := resolved_id()
	var hotspots: Array = []
	for child in get_children():
		if not child is AcademyHotspot:
			continue
		var hs := child as AcademyHotspot
		if not hs.enabled:
			continue
		if not hs.unlock_flag.is_empty() and not bool(flags.get(hs.unlock_flag, false)):
			continue
		var hid := hs.resolved_id(gid)
		var act := hs.action_id if not hs.action_id.is_empty() else action_id
		var dlg := hs.dialogue_id
		var part := R18n.pick(hs.part_zh, hs.part_en)
		hotspots.append(Schema.hotspot(hid, part if not part.is_empty() else display_title(),
			R18n.pick(hs.verb_zh, hs.verb_en), hs.global_position,
			_activation(hid, act, dlg, on_activate), {"action_id": act}))
	if hotspots.is_empty():
		hotspots.append(Schema.hotspot(gid, display_title(), R18n.pick(verb_zh, verb_en), anchor_world(),
			_activation(gid, action_id, dialogue_id, on_activate), {"action_id": action_id}))
	return Schema.group(gid, display_title(), anchor_world(), hotspots, {
		"dist_selected": dist_selected,
		"dist_activatable": dist_activatable,
		"dist_potential": dist_potential,
	})

func _activation(hid: String, act: String, dlg: String, on_activate: Callable) -> Callable:
	return func() -> void:
		activated.emit(hid, act)
		if on_activate.is_valid():
			on_activate.call(self, hid, act, dlg)

## Attach an interactable to any spawned item (catalog furniture, ArchBuilder component).
## `spec` keys mirror the exported properties above, plus optional `hotspots: Array[Dictionary]`
## ({id, part_zh, part_en, verb_zh, verb_en, action_id, dialogue_id, unlock_flag, offset: Vector3}).
static func attach_to(item: Node3D, spec: Dictionary) -> AcademyInteractable:
	if item == null or spec.is_empty():
		return null
	var it := AcademyInteractable.new()
	it.name = "Interactable"
	it.interactable_id = str(spec.get("id", item.name))
	it.title_zh = str(spec.get("title_zh", ""))
	it.title_en = str(spec.get("title_en", ""))
	it.verb_zh = str(spec.get("verb_zh", it.verb_zh))
	it.verb_en = str(spec.get("verb_en", it.verb_en))
	it.action_id = str(spec.get("action_id", ""))
	it.dialogue_id = str(spec.get("dialogue_id", ""))
	it.unlock_flag = str(spec.get("unlock_flag", ""))
	it.anchor_offset = _vec(spec.get("anchor_offset", it.anchor_offset), it.anchor_offset)
	for key in ["dist_selected", "dist_activatable", "dist_potential"]:
		if spec.has(key):
			it.set(key, float(spec[key]))
	for hdef in spec.get("hotspots", []):
		var hs := AcademyHotspot.new()
		hs.name = str(hdef.get("id", "Hotspot"))
		hs.hotspot_id = str(hdef.get("id", ""))
		hs.part_zh = str(hdef.get("part_zh", ""))
		hs.part_en = str(hdef.get("part_en", ""))
		hs.verb_zh = str(hdef.get("verb_zh", hs.verb_zh))
		hs.verb_en = str(hdef.get("verb_en", hs.verb_en))
		hs.action_id = str(hdef.get("action_id", ""))
		hs.dialogue_id = str(hdef.get("dialogue_id", ""))
		hs.unlock_flag = str(hdef.get("unlock_flag", ""))
		hs.position = _vec(hdef.get("offset", Vector3.ZERO), Vector3.ZERO)
		it.add_child(hs)
	item.add_child(it)
	return it

## Catalog JSON stores vectors as [x, y, z]; scripts pass Vector3.
static func _vec(value, fallback: Vector3) -> Vector3:
	if value is Vector3:
		return value
	if value is Array and (value as Array).size() == 3:
		return Vector3(float(value[0]), float(value[1]), float(value[2]))
	return fallback
