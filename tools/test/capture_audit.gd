extends SceneTree
## UI / 场景审计截图：标题、各房间（B-P / C-P / 1F 壁龛 / R05）、推演弹窗、字幕。
## 用法：xvfb-run -a -s "-screen 0 1440x900x24" godot --path . --rendering-driver opengl3 -s tools/test/capture_audit.gd -- out=/tmp/shots/a
const MainScene := preload("res://scenes/main/Main.tscn")
const World := preload("res://scenes/dual_world/DualWorldMain.tscn")

func _arg(k: String, d: String) -> String:
	for a in OS.get_cmdline_user_args():
		if str(a).begins_with(k + "="): return str(a).substr(k.length() + 1)
	return d

func _frames(n: int) -> void:
	for i in n: await process_frame

func _shot(out: String, tag: String) -> void:
	await _frames(8)
	root.get_texture().get_image().save_png("%s_%s.png" % [out, tag])
	print("shot ", tag)

func _initialize() -> void:
	var out := _arg("out", "/tmp/shots/a")
	var only := _arg("only", "all")
	if only in ["all", "title"]:
		var main = MainScene.instantiate()
		root.add_child(main)
		await _frames(6)
		await _shot(out, "01_title_t0")
		var t0 := Time.get_ticks_msec()
		while Time.get_ticks_msec() - t0 < 2500: await process_frame
		await _shot(out, "02_title_t2")
		t0 = Time.get_ticks_msec()
		while Time.get_ticks_msec() - t0 < 4500: await process_frame
		await _shot(out, "03_title_t7")
		main.queue_free()
		await _frames(4)
	if only in ["all", "rooms"]:
		var m = World.instantiate()
		m.show_intro = false
		root.add_child(m)
		await _frames(12)
		m.eng.s.t = 480.0
		m.det.set_pose("stand")
		for rid in ["B-P", "C-P", "1F-Shaft-Monitor", "R05"]:
			m.eng.s.room = rid
			m._dirty = true
			m._room_loaded = ""
			await _frames(20)
			await _shot(out, "10_room_" + rid)
		# 推演弹窗
		m.eng.s.room = "B-P"
		m._room_loaded = ""
		var did := ""
		for dd in m.data.deductions:
			did = str(dd.id)
			break
		m.eng.s.pending_deduction = {"id": did, "next": ""}
		m._dirty = true
		m._panel_cd = 0.0
		await _frames(30)
		await _shot(out, "20_deduction_modal")
		m.eng.s.pending_deduction = {}
		m._dirty = true
		m._panel_cd = 0.0
		await _frames(30)
		# 字幕
		m._on_said("detective", "大衣整整齐齐地挂着。", "say")
		await _frames(30)
		await _shot(out, "30_subtitle")
	quit()
