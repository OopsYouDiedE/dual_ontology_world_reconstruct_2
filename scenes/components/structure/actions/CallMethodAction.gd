@tool
class_name CallMethodAction
extends LevelAction
## Call a method on a node (arguments as Godot text values).

@export var target: NodePath
@export var method := ""
@export var arguments: PackedStringArray = []

func run(trigger: Node, _ctx: Dictionary) -> void:
	var node := resolve(trigger, target)
	if node != null and node.has_method(method):
		node.callv(method, Array(arguments).map(func(a): return parse(a)))

func describe() -> String:
	return "调用 %s.%s(%s)" % [target, method, ", ".join(arguments)]
