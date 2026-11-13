extends SceneTree
## 无界面校验「双本体」引擎与房间几何：
##   godot --headless --path . --script res://tools/dual_world/dual_verify.gd
## 退出码 0 = 全部通过。

const Engine_ := preload("res://scenes/dual_world/DualEngine.gd")
const Data := preload("res://scenes/dual_world/DualData.gd")
const Geo := preload("res://scenes/dual_world/RoomGeometry.gd")

var fails := 0


func check(ok: bool, text: String) -> void:
	print(("  [通过] " if ok else "  [失败] ") + text)
	if not ok: fails += 1


func _init() -> void:
	var data := Data.get_data()
	check(data.rooms.size() == 47 or data.rooms.size() > 40, "房间数据载入：%d 间" % data.rooms.size())
	check(data.actors.size() == 17, "人物 17 名（含代管者）")
	# 1. 主观词义：同词、不同事实
	var e := Engine_.new(data)
	var u := e.utter("detective", "save", "su")
	check(u.mismatch and u.meant != u.heard, "「救」：侦探=%s / 苏泠=%s" % [u.meant, u.heard])
	var u2 := e.utter("ward", "close", "huo")
	check(u2.mismatch, "「关门」：沃德=%s / 霍铎=%s" % [u2.meant, u2.heard])
	# 2. 知识门槛：缺源质知识只能读到当前读法
	var r := e.read_evidence("e_b_sleeve")
	check(not r.correct and r.text == data.evidence_by_id["e_b_sleeve"].naive, "缺知识时证物只给「当前读法」")
	e.grant_knowledge("k_acoustic")
	e.grant_knowledge("k_density")
	r = e.read_evidence("e_b_sleeve")
	check(r.correct, "补齐知识后给出客观读法")
	# 3. 门锁与路径
	e.new_game()
	check(e.path_to("1F-Shaft-Monitor", "B-P").is_empty(), "第一天清晨：四区大门尚未开放，无路可走")
	e.s.t = float(e.T(1, 12, 0))
	e.set_door_flags()
	check(not e.path_to("T01", "B-P").is_empty(), "午间四区大门开放后可达讲堂")
	# 4. 自动打通五日：每个争执取错误答案 → 关系永久受损
	e.new_game()
	e.s.speed = 600.0
	var guard := 0
	while e.s.ending == "" and guard < 200000:
		guard += 1
		if not e.s.pending_deduction.is_empty():
			var dd: Dictionary = data.deduction_by_id[e.s.pending_deduction.id]
			e.solve_deduction(dd.id, "__none__")
		elif e.s.pending_conflict != "":
			e.resolve_conflict(e.s.pending_conflict, "__wrong__")
		elif not e.s.pending_choice.is_empty():
			e.choose(e.s.pending_choice.beat_id, e.s.pending_choice.choice.options[0].id)
		elif not e.s.get("story_gate", {}).is_empty():
			e.s.room = str(e.s.story_gate.room)
			e.s.story_gate = {}
			e.process_beats()
		elif not e.s.get("story_gate", {}).is_empty():
			e.s.room = str(e.s.story_gate.room) # 自动化仅模拟玩家到达指定房间
			e.s.story_gate = {}
			e.process_beats()
		elif not e.s.hold.is_empty():
			if not e.search_step(): e.tick(1.0)  # 侦探先搜证，门槛才会放行
		else:
			e.tick(1.0)
	check(e.s.ending != "", "五日走完并得到结局：%s" % e.s.ending)
	check(e.s.irreparable, "第一天对质全错 → 不可弥合标记成立")
	check(e.s.ending in ["bitter", "lost", "trapped"], "不可弥合时不会出现最佳结局")
	# 5. 理想路径：全部正解
	e.new_game()
	e.s.speed = 600.0
	for k in data.knowledge: e.grant_knowledge(k.id)
	guard = 0
	while e.s.ending == "" and guard < 200000:
		guard += 1
		if not e.s.pending_deduction.is_empty():
			var dd2: Dictionary = data.deduction_by_id[e.s.pending_deduction.id]
			for ev in dd2.evidence:
				e.s.evidence[ev] = {"at": 0}
			e.solve_deduction(dd2.id, dd2.correct)
		elif e.s.pending_conflict != "":
			e.resolve_conflict(e.s.pending_conflict, data.conflict_by_id[e.s.pending_conflict].correct)
		elif not e.s.pending_choice.is_empty():
			var pick: String = e.s.pending_choice.choice.options[0].id
			for o in e.s.pending_choice.choice.options:
				if o.get("correct", false): pick = o.id
			e.choose(e.s.pending_choice.beat_id, pick)
		elif not e.s.hold.is_empty():
			for ev in data.deduction_by_id[e.s.hold.deduction].evidence:
				e.s.evidence[ev] = {"at": 0}
			e.tick(1.0)
		elif not e.s.get("story_gate", {}).is_empty():
			e.s.room = str(e.s.story_gate.room)
			e.s.story_gate = {}
			e.process_beats()
		else:
			e.tick(1.0)
	check(e.s.ending == "best", "全部正解 + 九条知识 → 结局 best（实际 %s）" % e.s.ending)
	# 5b. 搜证门槛：不搜证就停在推演节拍；默认倍速不再是 ×20；搜够证物才放行
	var g := Engine_.new(data)
	check(g.s.speed == 5.0, "默认倍速 ×5（实际 ×%s）" % g.s.speed)
	# 剧情回归：开场只播侦探本地台词；到厨房事件时不瞬移；抵达后才进入搜证。
	var story := Engine_.new(data)
	story.process_beats()
	var wake_lines: Array = story.s.log.filter(func(it): return str(it.get("kind", "")) == "say")
	var wake_local: bool = wake_lines.size() == 2
	for it in wake_lines: wake_local = wake_local and it.who.size() == 1 and str(it.who[0]) == "detective"
	check(story.s.current_beat == "d1_wake" and wake_local, "开场只播放 R05 侦探本人台词（不泄露其他房间对白）")
	check(story.actors_in_room("R05").has("detective") and story.actors_in_room("R05").size() == 1 and story.actors_in_room("B-P").has("huo") and story.actors_in_room("B-P").has("shen") and story.actors_in_room("B-P").has("su"), "开场人物按房间分布：侦探独自在卧室，三人实体留在厨房")
	story.s.t = float(story.T(1, 8, 0))
	story.process_beats()
	check(story.s.room == "R05" and str(story.s.story_gate.get("room", "")) == "B-P" and story.s.current_beat == "d1_wake", "08:00 厨房剧情在 R05 等待玩家前往，不自动切图")
	story.enter_room("B-P")
	story.tick(0.01)
	check(story.s.room == "B-P" and not story.s.hold.is_empty(), "玩家抵达厨房后才触发现场搜证门槛")
	g.s.speed = 600.0
	for _i in 2000: g.tick(1.0)
	if not g.s.get("story_gate", {}).is_empty():
		g.s.room = str(g.s.story_gate.room)
		g.s.story_gate = {}
		g.process_beats()
	g.tick(0.01)
	check(not g.s.hold.is_empty() and g.s.pending_deduction.is_empty() and g.s.deductions.is_empty(),
		"没有证物时推演不会弹出，时间停在节拍上（%s）" % g.hold_text())
	var steps := 0
	while g.s.deductions.is_empty() and g.s.pending_deduction.is_empty() and steps < 200:
		steps += 1
		if not g.search_step(): g.tick(1.0)
	var got: int = 0
	for ev in data.deduction_by_id["ded_drag"].evidence:
		if g.s.evidence.has(ev): got += 1
	check(not g.s.pending_deduction.is_empty() and got >= 2, "搜到 %d 件相关证物后才弹出推演" % got)
	# 诚实搜证机器人走完五日：每个推演弹出时的证物数
	var hb := Engine_.new(data)
	hb.s.speed = 600.0
	var short := 0
	var guard2 := 0
	while hb.s.ending == "" and guard2 < 200000:
		guard2 += 1
		if not hb.s.pending_deduction.is_empty():
			var dq: Dictionary = data.deduction_by_id[hb.s.pending_deduction.id]
			var cnt := 0
			for ev in dq.evidence:
				if hb.s.evidence.has(ev): cnt += 1
			print("    推演 %s：证物 %d/%d" % [dq.id, cnt, int(dq.get("minEvidence", 2))])
			if cnt < int(dq.get("minEvidence", 2)): short += 1
			hb.solve_deduction(dq.id, dq.correct)
		elif hb.s.pending_conflict != "":
			hb.resolve_conflict(hb.s.pending_conflict, data.conflict_by_id[hb.s.pending_conflict].correct)
		elif not hb.s.pending_choice.is_empty():
			hb.choose(hb.s.pending_choice.beat_id, hb.s.pending_choice.choice.options[0].id)
		elif not hb.s.get("story_gate", {}).is_empty():
			hb.s.room = str(hb.s.story_gate.room)
			hb.s.story_gate = {}
			hb.process_beats()
		elif not hb.s.hold.is_empty():
			if not hb.search_step(): hb.tick(1.0)
		else:
			hb.search_step()
			hb.tick(1.0)
	check(hb.s.ending != "" and short == 0, "诚实搜证走完五日：每个推演都有足够证物（不足 %d 个）" % short)
	# 6. 存读档
	var snap := e.save_dict()
	var e2 := Engine_.new(data)
	check(e2.load_dict(JSON.parse_string(JSON.stringify(snap))) and e2.s.ending == "best", "存读档往返（经 JSON）")
	# 7. 房间几何：所有房间的自动布置都无越界、无重叠、开洞合法
	var bad := 0
	for room in data.rooms:
		var ds := Geo.make_design(room, data)
		var v := Geo.validate(ds)
		if not v.ok:
			bad += 1
			for it in v.issues:
				if not it.ok: print("    ", room.id, " ", it.text)
	check(bad == 0, "%d 间房的自动布置通过几何校验" % data.rooms.size())
	# 8. 设计校验：每个推演在其节拍时刻、用真实门锁，可达（含所在房间）证物数 ≥ minEvidence
	for b in data.beats:
		if not b.has("deduction"): continue
		var dv := Engine_.new(data)
		dv.s.t = float(b["at"])
		dv.set_door_flags()
		var from: String = str(b.room) if b.has("room") and data.room_by_id.has(b.room) else dv.s.room
		var gs := dv.gate_status(str(b.deduction), from)
		var reach := 0
		for eid in data.deduction_by_id[b.deduction].evidence:
			if str(data.evidence_by_id[eid].room) == from or not dv.path_to(str(data.evidence_by_id[eid].room), from).is_empty(): reach += 1
		check(reach >= int(gs.need), "设计校验 %s（节拍 %s）：节拍时刻可达证物 %d ≥ 需要 %d" % [b.deduction, b.id, reach, int(gs.need)])
	# 9. 幂等：同一帧重复触发 resolve_conflict / choose，只结算一次
	var ie := Engine_.new(data)
	ie.open_conflict("c_borrow")
	var rk := Data.pair_key(data.conflict_by_id["c_borrow"].parties[0], data.conflict_by_id["c_borrow"].parties[1])
	var wrong_id := ""
	for o in data.conflict_by_id["c_borrow"].options:
		if o.id != data.conflict_by_id["c_borrow"].correct: wrong_id = o.id
	var before: int = ie.s.relations[rk].trust
	ie.resolve_conflict("c_borrow", wrong_id)
	ie.resolve_conflict("c_borrow", wrong_id)
	ie.resolve_conflict("c_borrow", "", true)
	check(ie.s.relations[rk].trust == before - 22 and ie.s.relations[rk].grievances.size() == 1,
		"重复点击争执选项只结算一次（信任 %d → %d，申诉 %d 条）" % [before, ie.s.relations[rk].trust, ie.s.relations[rk].grievances.size()])
	var ce := Engine_.new(data)
	var cbeat: Dictionary = {}
	for b in data.beats:
		if b.has("choice"): cbeat = b; break
	if not cbeat.is_empty():
		ce.s.pending_choice = {"beat_id": cbeat.id, "choice": cbeat.choice}
		ce.choose(cbeat.id, cbeat.choice.options[0].id)
		ce.s.flags["__probe__"] = true
		ce.choose(cbeat.id, cbeat.choice.options[cbeat.choice.options.size() - 1].id)
		check(ce.s.choices[cbeat.choice.id] == cbeat.choice.options[0].id, "重复触发 choose 只认第一次")
	# 10. 重新推演 / 推迟取证
	var re := Engine_.new(data)
	re.s.room = "A-P"  # 节拍会把侦探带到现场，证物就在本房
	re.open_deduction("ded_cuffs", "c_handcuff")
	check(re.postpone_deduction() and re.s.pending_deduction.is_empty() and not re.s.waiting, "证物不足可先关掉推演去取证")
	for _i in 50: re.tick(1.0)
	check(re.s.t == float(re.T(1, 7, 0)) and re.s.pending_deduction.is_empty(), "推迟期间时间保持冻结")
	for eid in ["e_a_cuffs", "e_a_grate"]: re.inspect_evidence(eid)
	re.tick(1.0)
	check(not re.s.pending_deduction.is_empty() and re.s.pending_deduction.id == "ded_cuffs", "证物齐了推演自动弹回")
	re.solve_deduction("ded_cuffs", "__none__")
	check(re.s.deductions["ded_cuffs"] == "wrong" and re.s.pending_conflict == "c_handcuff", "判错 → 争执弹出且正解被隐藏")
	re.resolve_conflict("c_handcuff", "", true)
	check(re.retry_deduction("ded_cuffs") and not re.s.pending_deduction.is_empty(), "判错的推演可重新推演")
	re.solve_deduction("ded_cuffs", data.deduction_by_id["ded_cuffs"].correct)
	check(re.s.deductions["ded_cuffs"] == "solved" and re.s.pending_conflict == "c_handcuff", "重新推演成功 → 争执重新弹出，正解出现")
	check(not re.retry_deduction("ded_cuffs"), "已解开的推演不能重试")
	var narrative_ok: bool = data.beats.size() >= 35
	var seen_days := {}
	for b in data.beats:
		seen_days[int(b.get("day", 0))] = true
		var prior := -1
		for ln in b.get("lines", []):
			if ln.size() < 2: narrative_ok = false; continue
			var who := str(ln[0])
			if who != "narrator" and not data.actor_by_id.has(who): narrative_ok = false
			if who != "narrator" and not b.get("present", []).has(who): narrative_ok = false
		if b.has("room") and not data.room_by_id.has(str(b.room)): narrative_ok = false
	check(narrative_ok and seen_days.size() == 5, "五日全部剧情节拍有有效地点与本场出场角色（%d 节拍）" % data.beats.size())
	print("失败 %d" % fails)
	quit(1 if fails > 0 else 0)
