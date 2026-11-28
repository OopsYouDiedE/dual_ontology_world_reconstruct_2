@tool
class_name TweenPropertyAction
extends LevelAction
## Animate a property to a value over time (doors, lifts, lights, fades…).

@export var target: NodePath
@export var property := "position:y"
@export var to := "2.0"
## Add `to` to the current value instead of going to it.
@export var relative := false
@export_range(0.0, 60.0, 0.05) var duration := 1.0
@export var transition: Tween.TransitionType = Tween.TRANS_SINE
@export var easing: Tween.EaseType = Tween.EASE_IN_OUT
## Wait for the animation before the next action.
@export var wait := true

func run(trigger: Node, _ctx: Dictionary) -> void:
	var node := resolve(trigger, target)
	if node == null or not trigger.is_inside_tree():
		return
	var tween := trigger.create_tween()
	var step := tween.tween_property(node, NodePath(property), parse(to), duration).set_trans(transition).set_ease(easing)
	if relative:
		step.as_relative()
	if wait:
		await tween.finished

func describe() -> String:
	return "动画 %s.%s → %s（%.2fs）" % [target, property, to, duration]
