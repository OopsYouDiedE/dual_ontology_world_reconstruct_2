@tool
class_name SetPropertyAction
extends LevelAction
## Set a property (or sub-property, e.g. "position:y") on a node.

@export var target: NodePath
@export var property := "visible"
@export var value := "true"

func run(trigger: Node, _ctx: Dictionary) -> void:
	var node := resolve(trigger, target)
	if node != null:
		node.set_indexed(NodePath(property), parse(value))

func describe() -> String:
	return "设置 %s.%s = %s" % [target, property, value]
