extends RefCounted
class_name AcademyUnifiedInput
## Global input & interaction UI preference authority for ALL levels in The Sleeping Academy
## (Public Hall, Campaign Crossing Rooms, Expedition-01, and all future chapters).
##
## Conflict-free canonical keymap:
##   W/A/S/D     -> Move
##   Shift/Ctrl  -> Sprint / Quiet pace
##   Space       -> Hop / Advance cutscene
##   E           -> Primary Interact (all levels, both C+ and Detroit modes)
##   V           -> Hot-toggle Interaction UI Style (C+ Aggregated <-> Detroit Distributed)
##   Wheel / 1-3 -> Cycle/select sub-actions in C+ multi-action mode
##   Q           -> Teammate Command Wheel / Quick Order
##   R           -> Lantern Toggle (Lone-Lamp Rule)
##   F           -> Stomp / Acoustic Probe
##   Tab / I     -> Field Manual / Handbook
##   F8          -> Locale Toggle (zh / en)
##   Esc         -> Release mouse / Close overlay

const ACTION_INTERACT := &"interact"
const ACTION_TOGGLE_UI := &"toggle_interaction_ui"
const PREFS_PATH := "user://academy_ui_prefs.cfg"

enum UiMode { AGGREGATED_CPLUS = 0, DISTRIBUTED_DETROIT = 1 }

static var _loaded := false
static var _ui_mode: int = UiMode.AGGREGATED_CPLUS

static func ensure_default_actions() -> void:
	if not InputMap.has_action(ACTION_INTERACT):
		InputMap.add_action(ACTION_INTERACT)
		var key := InputEventKey.new()
		key.physical_keycode = KEY_E
		InputMap.action_add_event(ACTION_INTERACT, key)
		var pad := InputEventJoypadButton.new()
		pad.button_index = JOY_BUTTON_A
		InputMap.action_add_event(ACTION_INTERACT, pad)
	if not InputMap.has_action(ACTION_TOGGLE_UI):
		InputMap.add_action(ACTION_TOGGLE_UI)
		var vkey := InputEventKey.new()
		vkey.physical_keycode = KEY_V
		InputMap.action_add_event(ACTION_TOGGLE_UI, vkey)

static func get_ui_mode() -> int:
	if not _loaded:
		_loaded = true
		if not ("--no-rule-save" in OS.get_cmdline_user_args()):
			var cfg := ConfigFile.new()
			if cfg.load(PREFS_PATH) == OK:
				var saved := int(cfg.get_value("interaction_ui", "mode", UiMode.AGGREGATED_CPLUS))
				if saved in [UiMode.AGGREGATED_CPLUS, UiMode.DISTRIBUTED_DETROIT]:
					_ui_mode = saved
	return _ui_mode

static func set_ui_mode(new_mode: int) -> void:
	_loaded = true
	_ui_mode = UiMode.DISTRIBUTED_DETROIT if new_mode == UiMode.DISTRIBUTED_DETROIT else UiMode.AGGREGATED_CPLUS
	if not ("--no-rule-save" in OS.get_cmdline_user_args()):
		var cfg := ConfigFile.new()
		cfg.load(PREFS_PATH)
		cfg.set_value("interaction_ui", "mode", _ui_mode)
		cfg.save(PREFS_PATH)

static func toggle_ui_mode() -> int:
	var next := UiMode.DISTRIBUTED_DETROIT if get_ui_mode() == UiMode.AGGREGATED_CPLUS else UiMode.AGGREGATED_CPLUS
	set_ui_mode(next)
	return next
