extends Node
class_name AcademyLevelRuntime
## THE single runtime composition root every level installs (Public Hall, campaign rooms,
## Expedition-01, AcademyLevelBase levels, and every future level).
##
##   var rt := AcademyLevelRuntime.install(self, ui_parent, AcademyLevelPipeline.capabilities_hall())
##   rt.set_view_provider(func(): return {camera=..., rect=..., vp_size=..., player_pos=..., can_show=...})
##   rt.interactions.register_provider("hall", _hall_groups)      # or place AcademyInteractable nodes
##   rt.set_wheel_options_provider(_wheel_options)
##   func _input(e): if rt.handle_input(e): get_viewport().set_input_as_handled()
##
## Layering (each layer only knows the one below it):
##   level logic ─▶ AcademyLevelRuntime ─▶ { AcademyInteractionDirector ─▶ DualModeInteractionHud,
##                                            UnifiedDialoguePresenter, UnifiedTeammateWheel }
##   rendering   ─▶ AcademyLevelPipeline.bootstrap_viewport ─▶ AcademyStage (env / ink / essence)
## Levels must not instantiate those UI nodes or render passes themselves; the architecture
## audit (AcademyArchitectureAudit) fails CI when they do.

const LevelPipeline := preload("res://scenes/components/shared/AcademyLevelPipeline.gd")
const Director := preload("res://scenes/components/interaction/AcademyInteractionDirector.gd")
const Schema := preload("res://scenes/components/interaction/AcademyInteractionSchema.gd")

signal wheel_order_selected(order_id: String)
signal wheel_opened
signal wheel_closed

const NODE_NAME := "AcademyLevelRuntime"

var capabilities: Dictionary = {}
var dual_ui        # DualModeInteractionHud (presenter only)
var dialogue       # UnifiedDialoguePresenter
var teammate_wheel # UnifiedTeammateWheel
var interactions: AcademyInteractionDirector
var wheel_options_provider: Callable

## Install (or fetch the already installed) runtime on `host`.
## opts: mode_pill_y (float), caption_bottom (float), auto_refresh (bool),
##       caption_auto_advance (bool; false when the host advances captions itself)
static func install(host: Node, ui_parent: Node, caps: Dictionary, opts := {}) -> AcademyLevelRuntime:
	var existing := host.get_node_or_null(NODE_NAME) as AcademyLevelRuntime
	if existing != null:
		existing.set_capabilities(caps)
		return existing
	var rt := AcademyLevelRuntime.new()
	rt.name = NODE_NAME
	host.add_child(rt)
	rt._build(host, ui_parent, caps, opts)
	return rt

static func find(host: Node) -> AcademyLevelRuntime:
	return host.get_node_or_null(NODE_NAME) as AcademyLevelRuntime if host != null else null

func _build(host: Node, ui_parent: Node, caps: Dictionary, opts: Dictionary) -> void:
	capabilities = caps.duplicate(true)
	var stack := LevelPipeline.bootstrap_ui_stack(self, ui_parent, capabilities,
		float(opts.get("mode_pill_y", 62.0)), float(opts.get("caption_bottom", -96.0)))
	dual_ui = stack.dual_ui
	dialogue = stack.dialogue
	teammate_wheel = stack.teammate_wheel
	if is_instance_valid(dialogue) and opts.has("caption_auto_advance"):
		dialogue.auto_advance = bool(opts.caption_auto_advance)
	interactions = Director.new()
	interactions.name = "InteractionDirector"
	interactions.presenter = dual_ui
	interactions.auto_refresh = bool(opts.get("auto_refresh", true)) and dual_ui != null
	interactions.add_scan_root(host)
	add_child(interactions)
	if is_instance_valid(teammate_wheel):
		teammate_wheel.order_selected.connect(func(id: String): wheel_order_selected.emit(id))
		teammate_wheel.wheel_opened.connect(func(): wheel_opened.emit())
		teammate_wheel.wheel_closed.connect(func(): wheel_closed.emit())

func set_capabilities(caps: Dictionary) -> void:
	capabilities = caps.duplicate(true)

func allows(capability: String, default_value := false) -> bool:
	return bool(capabilities.get(capability, default_value))

func set_view_provider(provider: Callable) -> void:
	interactions.view_provider = provider

func set_wheel_options_provider(provider: Callable) -> void:
	wheel_options_provider = provider

func refresh_interactions() -> void:
	interactions.refresh()

func is_wheel_open() -> bool:
	return is_instance_valid(teammate_wheel) and teammate_wheel.is_open()

func is_interaction_active() -> bool:
	return is_instance_valid(dual_ui) and dual_ui.active_enabled

## Unified input routing: Q teammate wheel first (if the level allows it), then the
## interaction UI (E / V / 1-4 / mouse wheel). Returns true when consumed.
func handle_input(event: InputEvent, allow_interact := true) -> bool:
	if is_instance_valid(teammate_wheel) and allows("allow_command_wheel", true):
		if teammate_wheel.handle_input(event, wheel_options_provider):
			return true
		if teammate_wheel.is_open():
			return false
	if is_instance_valid(dual_ui) and dual_ui.active_enabled:
		return dual_ui.handle_input(event, allow_interact)
	return false

func toggle_ui_mode() -> void:
	if is_instance_valid(dual_ui):
		dual_ui.toggle_mode()

func toast(text: String, duration := 2.4) -> void:
	if is_instance_valid(dual_ui):
		dual_ui.show_toast(text, duration)

func say(id: String, speaker: String, text: String, voice_profile := "resident") -> void:
	if is_instance_valid(dialogue):
		dialogue.say(id, speaker, text, voice_profile)

func thought(id: String, text: String) -> void:
	if is_instance_valid(dialogue):
		dialogue.thought(id, text)

func interaction_snapshot() -> Dictionary:
	var snap: Dictionary = dual_ui.get_state_snapshot() if is_instance_valid(dual_ui) else {}
	snap["capabilities"] = capabilities.duplicate()
	snap["group_ids"] = interactions.last_groups().map(func(g): return str(g.get("id", "")))
	return snap
