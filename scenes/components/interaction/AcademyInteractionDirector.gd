extends Node
class_name AcademyInteractionDirector
## Bridges scene-side selectables and the interaction UI.
##
##   scene side  ──descriptors──▶  Director  ──present()──▶  presenter (DualModeInteractionHud)
##   (AcademyInteractable nodes,                                  ▲ never sees scene nodes
##    registered provider Callables)                              │
##   ◀──activated / action_requested──────────────────────────────┘ (via hotspot callbacks)
##
## Levels never call the HUD to show prompts. They (a) place AcademyInteractable nodes or
## (b) register a provider Callable returning AcademyInteractionSchema groups, and
## (c) give the director a view provider (camera / rect / player position / can_show).

const Schema := preload("res://scenes/components/interaction/AcademyInteractionSchema.gd")
const Interactable := preload("res://scenes/components/interaction/AcademyInteractable.gd")

## Fired for AcademyInteractable activations: ctx = {group_id, hotspot_id, node, dialogue_id}.
signal action_requested(action_id: String, ctx: Dictionary)
## Fired when an activated interactable/hotspot declares a dialogue id.
signal dialogue_requested(dialogue_id: String)

## Any object exposing `sync_groups(camera, rect, vp_size, player_pos, groups, enabled)`.
var presenter: Object
## Callable() -> {camera: Camera3D, rect: Rect2, vp_size: Vector2, player_pos: Vector3, can_show: bool}
var view_provider: Callable
## When true the director refreshes every frame; hosts with their own update cadence call refresh().
var auto_refresh := true
## Only AcademyInteractable nodes below these roots are collected (default: the host).
var scan_roots: Array[Node] = []
var flags: Dictionary = {}
var validate_contract := OS.is_debug_build()

var _providers: Dictionary = {}   # name -> Callable() -> Array
var _provider_order: PackedStringArray = []
var _excluded_ids: Dictionary = {}
var _reported: Dictionary = {}
var _last_groups: Array[Dictionary] = []

func register_provider(provider_name: String, provider: Callable) -> void:
	if not _providers.has(provider_name):
		_provider_order.append(provider_name)
	_providers[provider_name] = provider

func unregister_provider(provider_name: String) -> void:
	_providers.erase(provider_name)
	var idx := _provider_order.find(provider_name)
	if idx >= 0:
		_provider_order.remove_at(idx)

func has_provider(provider_name: String) -> bool:
	return _providers.has(provider_name)

func add_scan_root(node: Node) -> void:
	if node != null and not scan_roots.has(node):
		scan_roots.append(node)

func set_flag(flag: String, value := true) -> void:
	flags[flag] = value

## Hide groups by id this frame onward (e.g. a provider already wires that target itself).
func set_excluded_ids(ids: PackedStringArray) -> void:
	_excluded_ids.clear()
	for id in ids:
		_excluded_ids[id] = true

func last_groups() -> Array[Dictionary]:
	return _last_groups

func _process(_dt: float) -> void:
	if auto_refresh:
		refresh()

## Collect descriptors from every source and hand them to the presenter.
func refresh() -> void:
	if presenter == null:
		return
	var view: Dictionary = view_provider.call() if view_provider.is_valid() else {}
	if not bool(view.get("can_show", false)) or not is_instance_valid(view.get("camera", null)):
		_last_groups = []
		presenter.sync_groups(null, Rect2(), Vector2.ONE, Vector3.ZERO, _last_groups, false)
		return
	var groups := collect()
	presenter.sync_groups(view.camera, view.get("rect", Rect2()), view.get("vp_size", Vector2.ONE),
		view.get("player_pos", Vector3.ZERO), groups, true)

func hide_all() -> void:
	_last_groups = []
	if presenter != null:
		presenter.sync_groups(null, Rect2(), Vector2.ONE, Vector3.ZERO, _last_groups, false)

func collect() -> Array[Dictionary]:
	var groups: Array[Dictionary] = []
	var seen := {}
	for provider_name in _provider_order:
		var provider: Callable = _providers[provider_name]
		if not provider.is_valid():
			continue
		var produced = provider.call()
		if not produced is Array:
			_report("provider '%s' must return an Array" % provider_name)
			continue
		for g in produced:
			_append(groups, seen, g)
	for node in _scene_interactables():
		_append(groups, seen, node.describe(flags, _on_interactable))
	if validate_contract:
		for err in Schema.validate_groups(groups):
			_report(err)
	_last_groups = groups
	return groups

func _append(groups: Array[Dictionary], seen: Dictionary, g) -> void:
	if not g is Dictionary or (g as Dictionary).is_empty():
		return
	var gid := str(g.get("id", ""))
	if _excluded_ids.has(gid) or seen.has(gid):
		return
	seen[gid] = true
	groups.append(g)

func _scene_interactables() -> Array:
	var out: Array = []
	if not is_inside_tree():
		return out
	var roots := scan_roots if not scan_roots.is_empty() else [get_parent()]
	for node in get_tree().get_nodes_in_group(Interactable.GROUP):
		if not node is Interactable:
			continue
		for r in roots:
			if is_instance_valid(r) and (r == node or r.is_ancestor_of(node)):
				out.append(node)
				break
	return out

func _on_interactable(node: Node, hotspot_id: String, action_id: String, dialogue_id: String) -> void:
	if not dialogue_id.is_empty():
		dialogue_requested.emit(dialogue_id)
	action_requested.emit(action_id, {
		"group_id": node.resolved_id() if node.has_method("resolved_id") else str(node.name),
		"hotspot_id": hotspot_id,
		"node": node,
		"dialogue_id": dialogue_id,
	})

func _report(msg: String) -> void:
	if _reported.has(msg):
		return
	_reported[msg] = true
	push_warning("AcademyInteractionDirector contract: " + msg)
