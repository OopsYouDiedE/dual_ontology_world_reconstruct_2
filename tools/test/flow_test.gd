extends SceneTree
## 全流程：第一幕（床上醒来 → 自由操作 → 查看寝室门）→ 第二幕（走廊对话圈）→ 进入 B-P。
const Main := preload("res://scenes/dual_world/DualWorldMain.tscn")
func _initialize() -> void:
	Engine.time_scale = 4.0
	var m = Main.instantiate()
	root.add_child(m)
	m.skip_subtitles = true
	var t0 := Time.get_ticks_msec()
	var log := {}
	var door_done := false
	while Time.get_ticks_msec() - t0 < 200000:
		await process_frame
		var o = m.opening
		if o != null and o.active and not log.has("opening:" + o.phase):
			log["opening:" + o.phase] = true
			print("[opening] phase=", o.phase)
		if o != null and o.active and o.phase == "free" and not door_done:
			# 把所有物件都"看"一遍再去门口，和玩家路径一致
			for i in o._items.size():
				if str(o._items[i].id) == "door":
					o.interact(i)
					door_done = true
		var g = m.gathering
		if g != null and not log.has("g:" + g.phase):
			log["g:" + g.phase] = true
			print("[gathering] t=", (Time.get_ticks_msec() - t0) / 1000, "s phase=", g.phase, " room=", m.eng.s.room, " chrome_top=", m.top_bar.visible)
		if g == null and log.has("g:card"):
			for i in 40: await process_frame
			print("[done] room=", m.eng.s.room, " loaded=", m._room_loaded, " cine=", m._cine, " playing=", m.eng.s.playing, " chrome_top=", m.top_bar.visible, " sun=", m.sun.visible, " room_mesh_visible=", m.room_mesh.visible, " beat=", m.eng.s.current_beat)
			quit()
			return
	print("TIMEOUT gathering=", m.gathering, " phase=", (m.gathering.phase if m.gathering else "-"), " pt=", (m.gathering._pt if m.gathering else 0.0), " line=", (m.gathering._line if m.gathering else 0), " fade_alpha=", m.fade_rect.modulate.a)
	quit()
