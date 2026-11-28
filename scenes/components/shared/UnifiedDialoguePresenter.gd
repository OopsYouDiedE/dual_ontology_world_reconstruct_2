extends Node
class_name UnifiedDialoguePresenter
## Unified bottom subtitle + formant speech presenter shared across Public Hall,
## Campaign Rooms, Expedition-01, StoryDirector cutscenes, and all future levels.

const CaptionsScene := preload("res://scenes/components/shared/AcademyCaptions.gd")
const VoiceSynthScript := preload("res://scenes/components/shared/VoiceSynth.gd")
const UiStyle := preload("res://scenes/components/shared/UiTheme.gd")

signal line_posted(speaker: String, text: String)

var captions: VBoxContainer
var voice: Node

func setup(ui_parent: Node, bottom_offset := -92.0) -> void:
	if not is_instance_valid(captions):
		captions = CaptionsScene.new()
		ui_parent.add_child(captions)
		captions.setup(UiStyle.make_font())
		captions.offset_bottom = bottom_offset
		captions.offset_top = bottom_offset - 195.0
		captions.posted.connect(func(sp: String, tx: String): line_posted.emit(sp, tx))
	if not is_instance_valid(voice):
		voice = VoiceSynthScript.new()
		add_child(voice)

func say(id: String, speaker: String, text: String, voice_profile := "resident") -> void:
	if is_instance_valid(captions):
		captions.post(id, speaker, text)
	if is_instance_valid(voice) and not text.is_empty():
		voice.speak_line(text, voice_profile)

func thought(id: String, text: String) -> void:
	if is_instance_valid(captions):
		captions.post(id, "", text)

func clear() -> void:
	if is_instance_valid(captions):
		captions.clear()

func has_active_caption() -> bool:
	return is_instance_valid(captions) and not captions.entries.is_empty()

func get_active_speakers() -> Array:
	return captions.entries.keys() if is_instance_valid(captions) else []

func _process(dt: float) -> void:
	if is_instance_valid(captions):
		captions.advance(dt)
