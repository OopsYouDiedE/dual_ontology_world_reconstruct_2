extends SceneTree
## 第二幕截图：直接调用 start_gathering，按阶段 / 台词抽帧。Engine.time_scale 加速。
const Main := preload("res://scenes/dual_world/DualWorldMain.tscn")
func _arg(k: String, d: String) -> String:
	for a in OS.get_cmdline_user_args():
		if str(a).begins_with(k + "="): return str(a).substr(k.length() + 1)
	return d
func _initialize() -> void:
	var out := _arg("out", "/tmp/shots/s2")
	Engine.time_scale = float(_arg("scale", "2.0"))
	var m = Main.instantiate()
	m.show_intro = false
	root.add_child(m)
	for i in 12: await process_frame
	m.eng.s.t = 440.0
	m.det.set_pose("stand")
	m.start_gathering("B-P")
	var shot := {}
	var t0 := Time.get_ticks_msec()
	var last_phase := ""
	var last_line := -1
	var n := 0
	while Time.get_ticks_msec() - t0 < 170000:
		await process_frame
		var g = m.gathering
		if g == null:
			if shot.has("done"): break
			if last_phase == "out":
				for i in 60: await process_frame
				root.get_texture().get_image().save_png("%s_final_room.png" % out)
				print("room after: ", m.eng.s.room, " loaded=", m._room_loaded, " det=", m.det_pos, " cine=", m._cine, " playing=", m.eng.s.playing)
				shot["done"] = true
			continue
		var key: String = g.phase + ":" + str(g._line)
		if g.phase != last_phase or g._line != last_line:
			var want: bool = (g.phase in ["exit", "hear", "approach", "join", "card"]) or (g.phase == "talk" and g._line in [1, 3, 5, 8, 12])
			if want and not shot.has(key):
				for i in 14: await process_frame
				shot[key] = true
				n += 1
				var p := "%s_%02d_%s_%d.png" % [out, n, g.phase, g._line]
				root.get_texture().get_image().save_png(p)
				print("shot ", p, " det=", m.det_pos, " subtitle=", m.subtitle.text.left(14))
			last_phase = g.phase
			last_line = g._line
	print("end loop; gathering=", m.gathering, " last=", last_phase)
	quit()
