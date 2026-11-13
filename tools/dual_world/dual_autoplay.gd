extends SceneTree
## 真实时间下的「侦探自己动起来」回归：不开 instant_story，默认设置运行，
## 检查：默认倍速 ×5、侦探自己走动搜证、没有证物时不会弹出推演。
##   godot --headless --path . --script res://tools/dual_world/dual_autoplay.gd
const MainScene := preload("res://scenes/dual_world/DualWorldMain.tscn")

var main: Control
var fails := 0
var t0 := 0.0
var moved := 0.0
var last_pos := Vector2.ZERO
var first_ded_evidence := -1
var rooms_seen := {}


func _initialize() -> void:
	main = MainScene.instantiate()
	root.add_child(main)
	t0 = Time.get_ticks_msec() / 1000.0


func check(ok: bool, text: String) -> void:
	print(("  [通过] " if ok else "  [失败] ") + text)
	if not ok: fails += 1


func _process(_delta: float) -> bool:
	var el := Time.get_ticks_msec() / 1000.0 - t0
	var s: Dictionary = main.eng.s
	if el < 0.5:
		check(is_equal_approx(float(s.speed), 5.0), "开局默认速度 ×%s" % s.speed)
		last_pos = main.det_pos
	moved += main.det_pos.distance_to(last_pos)
	last_pos = main.det_pos
	rooms_seen[s.room] = true
	if first_ded_evidence < 0 and not s.pending_deduction.is_empty():
		first_ded_evidence = s.evidence.size()
		print("    第一次推演弹出：已取得证物 %d 件，t=%d，用时 %.1fs" % [first_ded_evidence, int(s.t), el])
	if main.modal.visible and not s.pending_deduction.is_empty():
		pass
	if el > 45.0:
		check(moved > 3.0, "侦探自己走动了 %.1f 米" % moved)
		check(s.evidence.size() >= 3, "自动搜证：已查 %d 件证物" % s.evidence.size())
		check(first_ded_evidence >= 2 or first_ded_evidence == -1, "推演弹出时证物数 %d" % first_ded_evidence)
		print("  时间 %d  房间 %s  hold=%s" % [int(s.t), s.room, main.eng.hold_text()])
		print("失败 %d" % fails)
		quit(1 if fails > 0 else 0)
	return false
