extends Node
## Shared locale choice for Godot UI.
signal language_changed(code: String)

const LANGUAGES := ["en"]
const NATIVE_NAMES := {"en": "English"}
const SAVE_PATH := "user://language.cfg"
const ENGLISH_TRANSLATION := preload("res://localization/translations.en.translation")

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	TranslationServer.add_translation(ENGLISH_TRANSLATION)
	_apply("en")

func current_language() -> String:
	var locale := TranslationServer.get_locale()
	return "en" if locale.begins_with("en") else locale

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
	TranslationServer.set_locale(code if LANGUAGES.has(code) else "en")
