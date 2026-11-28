extends RefCounted
class_name AcademyLevelPipeline
## Single unified level construction & capability pipeline for ALL current and future levels
## in The Sleeping Academy (Public Hall, Campaign Rooms, Expedition-01, and Chapters 2+).
##
## Everything (rendering, camera feel, keybinds, dual-mode 3-state interaction UI,
## bottom subtitle dialogue, and Q radial teammate wheel) is unified by default.
## Only explicit level-specific exceptions (e.g. `allow_jump = false` in Public Hall)
## are declared in the level capability profile.

const Stage := preload("res://scenes/components/rendering/AcademyStage.gd")
const UnifiedInput := preload("res://scenes/components/shared/AcademyUnifiedInput.gd")
const DualHud := preload("res://scenes/components/shared/DualModeInteractionHud.gd")
const DialoguePresenter := preload("res://scenes/components/shared/UnifiedDialoguePresenter.gd")
const TeammateWheel := preload("res://scenes/components/shared/UnifiedTeammateWheel.gd")

static func capabilities_hall() -> Dictionary:
	return {
		"level_kind": "hall",
		"is_safe_hub": true,
		"allow_jump": false,         # Explicit exception: cannot jump inside Public Hall
		"allow_lamp": false,         # Explicit exception: lit safe hub
		"allow_stomp": false,        # Explicit exception: safe hub
		"allow_command_wheel": true, # Unified Q teammate radial wheel
		"allow_dialogue_captions": true,
		"allow_dual_interaction_ui": true,
		"attach_ink": true,
		"attach_essence": true,
	}

static func capabilities_campaign_room() -> Dictionary:
	return {
		"level_kind": "campaign_room",
		"is_safe_hub": false,
		"allow_jump": false,
		"allow_lamp": false,
		"allow_stomp": false,
		"allow_command_wheel": true,
		"allow_dialogue_captions": true,
		"allow_dual_interaction_ui": true,
		"attach_ink": true,
		"attach_essence": true,
	}

static func capabilities_expedition() -> Dictionary:
	return {
		"level_kind": "expedition",
		"is_safe_hub": false,
		"allow_jump": true,
		"allow_lamp": true,
		"allow_stomp": true,
		"allow_command_wheel": true,
		"allow_dialogue_captions": true,
		"allow_dual_interaction_ui": true,
		"attach_ink": true,
		"attach_essence": true,
	}

## Unified viewport & rendering stage bootstrap.
static func bootstrap_viewport(vp: Viewport, world_env: WorldEnvironment, capabilities: Dictionary) -> Dictionary:
	return Stage.apply_to_viewport(
		vp,
		world_env,
		bool(capabilities.get("attach_ink", true)),
		bool(capabilities.get("attach_essence", false))
	)

## Unified UI, dialogue, and teammate interaction stack bootstrap.
static func bootstrap_ui_stack(owner: Node, ui_parent: Node, capabilities: Dictionary, mode_pill_y := 62.0, caption_bottom := -96.0) -> Dictionary:
	UnifiedInput.ensure_default_actions()
	var stack := {
		"capabilities": capabilities.duplicate(true),
		"dual_ui": null,
		"dialogue": null,
		"teammate_wheel": null,
	}
	if bool(capabilities.get("allow_dual_interaction_ui", true)):
		var hud := DualHud.new()
		hud.mode_pill_y = mode_pill_y
		ui_parent.add_child(hud)
		stack.dual_ui = hud
	if bool(capabilities.get("allow_dialogue_captions", true)):
		var dlg := DialoguePresenter.new()
		owner.add_child(dlg)
		dlg.setup(ui_parent, caption_bottom)
		stack.dialogue = dlg
	if bool(capabilities.get("allow_command_wheel", true)):
		var tw := TeammateWheel.new()
		owner.add_child(tw)
		tw.setup(ui_parent)
		stack.teammate_wheel = tw
	return stack
