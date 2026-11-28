@tool
class_name LevelAction
extends Resource
## One step a LevelTrigger3D runs when it fires. Add actions to a trigger's `actions` list in
## the Inspector (New → SetPropertyAction, TweenPropertyAction, …); they run in order.
## Node paths are relative to the trigger (the scene root is tried as a fallback).
## Values are typed as Godot text: 1.5, true, Vector3(0, 2, 0), Color(1, 0.8, 0.6), "text".

## Seconds to wait before this step.
@export_range(0.0, 60.0, 0.05) var delay := 0.0

## Run the step. May await (tweens, animations) when the step should finish before the next.
func run(_trigger: Node, _ctx: Dictionary) -> void:
	pass

## One line for the plan view, the F2 blueprint and the trigger manifest.
func describe() -> String:
	return get_script().resource_path.get_file().get_basename()

static func resolve(trigger: Node, path: NodePath) -> Node:
	if path.is_empty():
		return null
	var node := trigger.get_node_or_null(path)
	if node == null and trigger.owner != null:
		node = trigger.owner.get_node_or_null(path)
	if node == null:
		push_warning("LevelAction: '%s' not found from %s" % [path, trigger.name])
	return node

## Parse a typed value written in the Inspector ("Vector3(0, 2, 0)", "1.5", "true", "\"text\"").
static func parse(text: String) -> Variant:
	var t := text.strip_edges()
	if t == "":
		return null
	var v = str_to_var(t)
	return t if v == null and t != "null" else v

## The AcademyLevelBase (or any ancestor answering _on_level_action) that owns the trigger.
static func level_of(trigger: Node) -> Node:
	var n := trigger.get_parent()
	while n != null:
		if n.has_method("_on_level_action"):
			return n
		n = n.get_parent()
	return null
