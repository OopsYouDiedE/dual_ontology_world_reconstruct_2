extends Node
## Shared locale choice for Godot UI.
signal language_changed(code: String)

const LANGUAGES := ["zh_CN", "ja", "en"]
const NATIVE_NAMES := {"zh_CN": "简体中文", "ja": "日本語", "en": "English"}
const SAVE_PATH := "user://language.cfg"

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	var saved := ConfigFile.new()
	var system_locale := OS.get_locale()
	var code := "ja" if system_locale.begins_with("ja") else "en" if system_locale.begins_with("en") else "zh_CN"
	if saved.load(SAVE_PATH) == OK:
		code = str(saved.get_value("language", "locale", code))
	_apply(code)

func current_language() -> String:
	var locale := TranslationServer.get_locale()
	return "ja" if locale.begins_with("ja") else "en" if locale.begins_with("en") else "zh_CN"

func set_language(code: String) -> void:
	if not LANGUAGES.has(code): return
	var changed := current_language() != code
	_apply(code)
	var saved := ConfigFile.new()
	saved.set_value("language", "locale", code)
	var error := saved.save(SAVE_PATH)
	if error != OK: push_warning("Could not save UI language: %s" % error_string(error))
	if changed: language_changed.emit(code)

func _apply(code: String) -> void:
	TranslationServer.set_locale(code if LANGUAGES.has(code) else "zh_CN")
