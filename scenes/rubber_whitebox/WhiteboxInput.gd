extends RefCounted
## Shared test-player controls, registered only by the whitebox scenes.

const PLAYER_KEYS := {
	&"whitebox_jump": KEY_SPACE, &"whitebox_sprint": KEY_SHIFT,
	&"whitebox_orbit_left": KEY_Q, &"whitebox_orbit_right": KEY_R,
	&"whitebox_reset": KEY_BACKSPACE, &"whitebox_hud": KEY_H,
	&"whitebox_zoom_in": KEY_Z, &"whitebox_zoom_out": KEY_X,
	&"whitebox_tilt_up": KEY_PAGEUP, &"whitebox_tilt_down": KEY_PAGEDOWN,
}

static func install(extra := {}) -> void:
	for bindings: Dictionary in [PLAYER_KEYS, extra]:
		for action: StringName in bindings:
			if InputMap.has_action(action):
				continue
			InputMap.add_action(action)
			var event := InputEventKey.new()
			event.physical_keycode = bindings[action]
			InputMap.action_add_event(action, event)
