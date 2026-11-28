@tool
class_name PlayAnimationAction
extends LevelAction
## Play an animation of an AnimationPlayer (authored in Godot's Animation panel).

@export var player: NodePath
@export var animation := ""
@export var backwards := false
@export var wait := false

func run(trigger: Node, _ctx: Dictionary) -> void:
	var p := resolve(trigger, player) as AnimationPlayer
	if p == null:
		return
	if backwards:
		p.play_backwards(animation)
	else:
		p.play(animation)
	if wait:
		await p.animation_finished

func describe() -> String:
	return "播放动画 %s:%s" % [player, animation]
