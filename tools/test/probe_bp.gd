extends SceneTree
## 启动 DualWorldMain（跳过开场），进入指定房间，打印几何并截图。
const Main := preload("res://scenes/dual_world/DualWorldMain.tscn")
func _arg(k: String, d: String) -> String:
	for a in OS.get_cmdline_user_args():
		if str(a).begins_with(k + "="): return str(a).substr(k.length() + 1)
	return d
func _initialize() -> void:
	var m = Main.instantiate()
	m.show_intro = false
	root.add_child(m)
	for i in 10: await process_frame
	var room := _arg("room", "B-P")
	m.eng.s.t = 481.0 if room == "B-P" else m.eng.s.t
	m.eng.enter_room(room)
	for i in 90: await process_frame
	var ds: Dictionary = m.room_mesh.design
	print("design w=", ds.w, " d=", ds.d, " loaded=", m._room_loaded, " lowpoly=", m._lowpoly_ok)
	if m._lowpoly_ok:
		print("walk_rect=", m.lowpoly.walk_rect(0.0), " center=", m.lowpoly.center())
		for r in m.lowpoly.obstacle_rects(): print(" obstacle ", r)
		var rt: Node3D = m.lowpoly.get("_root")
		for n in rt.get_children(): print(" child ", n.name, " ", (n as Node3D).global_position if n is Node3D else "")
	for op in ds.walls[0].openings: print(" opening ", op)
	print("actors=", m.eng.actors_in_room(room), " det_pos=", m.det_pos)
	m.top_bar.visible = false; m.left_card.visible = false; m.drawer.visible = false
	for i in 20: await process_frame
	root.get_texture().get_image().save_png(_arg("out", "/tmp/shots/bp.png"))
	quit()
