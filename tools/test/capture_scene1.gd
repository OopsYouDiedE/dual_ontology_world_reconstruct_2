extends SceneTree
## 第一幕截图：真实进入 DualWorldMain，按 WakeOpening 阶段与起床过程抽帧。
## 用法：xvfb-run -a godot --path . --rendering-driver opengl3 -s tools/test/capture_scene1.gd -- out=/tmp/shots/s1 scale=1.0
const Main := preload("res://scenes/dual_world/DualWorldMain.tscn")

func _arg(k: String, d: String) -> String:
	for a in OS.get_cmdline_user_args():
		if str(a).begins_with(k + "="): return str(a).substr(k.length() + 1)
	return d

func _shot(out: String, n: int, tag: String) -> void:
	var p := "%s_%02d_%s.png" % [out, n, tag]
	root.get_texture().get_image().save_png(p)
	print("shot ", p)

func _initialize() -> void:
	var out := _arg("out", "/tmp/shots/s1")
	Engine.time_scale = float(_arg("scale", "1.0"))
	var m = Main.instantiate()
	root.add_child(m)
	var n := 0
	var last := ""
	var t0 := Time.get_ticks_msec()
	var mid_clock := 0.0
	var free_clock := 0.0
	var free_step := 0
	var prev := Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < 150000:
		await process_frame
		var nowt := Time.get_ticks_msec()
		var dt := float(nowt - prev) / 1000.0
		prev = nowt
		var o = m.opening
		if o == null or not o.active:
			if last == "free": break
			continue
		if o.phase != last:
			last = o.phase
			mid_clock = 0.0
			for i in 6: await process_frame
			n += 1
			_shot(out, n, "phase_" + o.phase)
		if o.phase in ["lie", "sit", "look", "getup"]:
			if o._pt - mid_clock >= 0.8:
				mid_clock = o._pt
				n += 1
				_shot(out, n, o.phase + "_mid")
		if o.phase == "free":
			free_clock = o._free_t
			if free_step == 0 and free_clock > 1.5:
				free_step = 1
				n += 1
				_shot(out, n, "free_stand")
				Input.action_press("move_right")
			elif free_step == 1 and free_clock > 3.0:
				Input.action_release("move_right")
				n += 1
				_shot(out, n, "free_walk")
				free_step = 2
				var item_i := 0
				for i in o._items.size():
					if str(o._items[i].id) == "lamp": item_i = i
				o.interact(item_i)
			elif free_step == 2 and free_clock > 5.5:
				n += 1
				_shot(out, n, "free_interact")
				break
	print("det pos=", m.det_pos, " pose=", m.det.pose, " top_bar=", m.top_bar.visible, " drawer=", m.drawer.visible, " left_card=", m.left_card.visible)
	quit()
