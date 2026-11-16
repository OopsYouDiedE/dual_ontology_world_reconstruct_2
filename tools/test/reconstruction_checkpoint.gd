extends SceneTree
## In-room reconstruction checkpoint round trip; creates no production save.
const Main := preload("res://scenes/dual_world/DualWorldMain.tscn")
var failures := 0
func check(ok: bool, what: String) -> void:
	print(("PASS " if ok else "FAIL ")+what)
	if not ok: failures += 1
func _initialize() -> void:
	var m = Main.instantiate()
	m.show_intro = false
	root.add_child(m)
	for i in 8: await process_frame
	m.eng.s.room = "B-P"
	m.eng.s.t = 470.0
	m._room_loaded = ""
	m._ensure_room()
	m._sync_figures(true)
	check(m.start_kitchen_exploration(),"load real kitchen with mock progress")
	m.kitchen._enter_free()
	for evidence in ["e_b_sleeve","e_b_drag","e_b_water","e_b_ratchet"]: m.eng.inspect_evidence(evidence)
	m._sub_queue.clear()
	m.eng.open_deduction("ded_drag")
	check(m.kitchen.begin_order_replay("ded_drag"),"start in-room replay")
	var replay = m.kitchen._order_replay
	replay._performance.set_process(false)
	for phase in [1,5,8,11,14,15,17,18]:
		var perf = replay._performance
		while perf._phase < phase and perf.running: perf._advance_timeline(0.11)
		perf._advance_timeline(0.08)
		var saved = JSON.parse_string(JSON.stringify(replay.checkpoint_state()))
		var order = saved.order.duplicate()
		var before: Dictionary = saved.performance.scene
		replay.stop()
		check(m.kitchen.begin_order_replay("ded_drag"),"new replay for phase "+str(phase))
		replay = m.kitchen._order_replay
		replay._performance.set_process(false)
		replay.restore_checkpoint(saved)
		var after: Dictionary = replay.checkpoint_state().performance
		check(after.phase == saved.performance.phase and absf(after.phase_time-saved.performance.phase_time)<0.00001,"time restored at phase "+str(phase))
		check(JSON.stringify(after.scene) == JSON.stringify(before),"poses, props and camera restored at phase "+str(phase))
		check(replay._order == order and replay._playing,"order and playing state restored")
	var ended := [0]
	replay._performance.finished.connect(func(): ended[0] += 1)
	while replay._playing: replay._performance._advance_timeline(0.1)
	check(ended[0] == 1,"completion emitted exactly once")
	replay._move_card(1,-1)
	var paused = JSON.parse_string(JSON.stringify(replay.checkpoint_state()))
	replay.stop()
	check(m.kitchen.begin_order_replay("ded_drag"),"restart completed replay")
	replay = m.kitchen._order_replay
	replay._performance.set_process(false)
	replay.restore_checkpoint(paused)
	check(not replay._playing and not replay._confirm.disabled,"restore completed replay into waiting state")
	check(replay._order == ["su_open","shen_cloth","detective_pull","huo_lock"],"restore changed player card order")
	check(str(m.eng.s.deductions.get("ded_drag","")) != "solved","restore never submits deduction")
	replay._move_card(2,-1)
	replay._confirm_order()
	check(str(m.eng.s.deductions.get("ded_drag","")) == "solved","one player confirmation completes original deduction")
	m.queue_free()
	await process_frame
	print("RESULT failures=",failures)
	quit(1 if failures else 0)
