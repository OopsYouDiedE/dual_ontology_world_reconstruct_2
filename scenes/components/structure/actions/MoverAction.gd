@tool
class_name MoverAction
extends LevelAction
## Drive a LevelMover3D: open, close, toggle or play its cycle.

enum Command { OPEN, CLOSE, TOGGLE, PLAY }
@export var mover: NodePath
@export var command: Command = Command.TOGGLE
@export var wait := false

func run(trigger: Node, _ctx: Dictionary) -> void:
	var m := resolve(trigger, mover)
	if m == null or not m.has_method("open"):
		return
	match command:
		Command.OPEN: m.open()
		Command.CLOSE: m.close()
		Command.TOGGLE: m.toggle()
		Command.PLAY: m.play()
	if wait and m.has_signal("motion_finished"):
		await m.motion_finished

func describe() -> String:
	return "%s %s" % [["打开", "关闭", "切换", "播放"][command], mover]
