@tool
class_name LevelEventAction
extends LevelAction
## Send an action id to the level (AcademyLevelBase._on_level_action), optionally set a flag
## and play a declared dialogue line.

@export var action_id := ""
@export var dialogue_id := ""
## Flag set in the level's unlocked_flags (unlocks hotspots that wait on it).
@export var set_flag := ""

func run(trigger: Node, ctx: Dictionary) -> void:
	var level := level_of(trigger)
	if level == null:
		return
	if set_flag != "" and "unlocked_flags" in level:
		level.unlocked_flags[set_flag] = true
	if action_id != "":
		level._on_level_action(action_id, ctx)
	if dialogue_id != "" and level.has_method("play_dialogue"):
		level.play_dialogue(dialogue_id)

func describe() -> String:
	return "关卡事件 %s%s%s" % [action_id, (" · 台词 " + dialogue_id) if dialogue_id != "" else "", (" · 标记 " + set_flag) if set_flag != "" else ""]
