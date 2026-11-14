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
	check(hb.s.ending == "best" and short == 0 and hb.knowledge_count() == data.knowledge.size(),
		"诚实搜证走完五日：证物充足（不足 %d）、集齐 %d/%d 知识并达成 best 结局（实际 %s）" % [short, hb.knowledge_count(), data.knowledge.size(), hb.s.ending])
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
	var recovery := Engine_.new(data)
	for evidence_id in data.deduction_by_id["ded_truth"].evidence:
		recovery.s.evidence[evidence_id] = {"at": recovery.s.t, "room": data.evidence_by_id[evidence_id].room}
	recovery.open_deduction("ded_truth", "c_demon")
	recovery.solve_deduction("ded_truth", "__wrong__")
	var recovery_relations: Dictionary = recovery.s.relations.duplicate(true)
	recovery.s.deductions["ded_cuffs"] = "wrong"
	check(not recovery.retry_deduction("ded_cuffs") and recovery.s.pending_conflict == "c_demon",
		"当前争执不允许重推无关推演，待决争执保持不变")
	recovery.s.pending_choice = {"beat_id": "__retry_guard__"}
	check(not recovery.retry_deduction("ded_truth") and recovery.s.pending_conflict == "c_demon",
		"存在待决抉择时不能重推，避免弹窗重叠")
	recovery.s.pending_choice = {}
	check(recovery.retry_deduction("ded_truth") and recovery.s.pending_deduction.get("next", "") == "c_demon"
		and recovery.s.pending_conflict == "" and recovery.s.waiting,
		"永久争执中可退回对应推演，并保留原争执接续与暂停状态")
	check(not recovery.retry_deduction("ded_truth") and recovery.s.relations == recovery_relations
		and not recovery.s.irreparable and not recovery.s.conflicts.has("c_demon"),
		"重复重推不产生永久裂痕、信任损失或提前结算争执")
	recovery.solve_deduction("ded_truth", data.deduction_by_id["ded_truth"].correct)
	check(recovery.s.pending_conflict == "c_demon" and recovery.s.conflict_queue.count("c_demon") == 1
		and recovery.conflict_options("c_demon").any(func(option): return option.id == data.conflict_by_id["c_demon"].correct),
		"重推成功后返回同一争执，队列无重复且恢复正解选项")
	recovery.resolve_conflict("c_demon", data.conflict_by_id["c_demon"].correct)
	check(recovery.s.conflicts.get("c_demon", "") == "resolved" and not recovery.s.irreparable
		and recovery.s.pending_conflict == "" and not recovery.s.waiting,
		"补救后的永久争执可正确结算，时间等待正常解除")
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
	# 11. 评审包 Terra_20261114 剧情与游玩专项回归
	# 11a. 全部争执当事方词义必须真实分歧（修复 c_quiet 与 c_handcuff 零分歧）
	var lex_div_ok := true
	for cf in data.conflicts:
		var p0: String = str(cf.parties[0])
		var p1: String = str(cf.parties[1])
		if data.sense_of(p0, str(cf.word)) == data.sense_of(p1, str(cf.word)):
			lex_div_ok = false
			print("    词义未分歧：", cf.id, " ", p0, "/", p1, " word=", cf.word)
	check(lex_div_ok, "全部 %d 场争执的当事双方均存在真实词义分歧" % data.conflicts.size())
	# 11b. 第一天「三句答复」推演必须在三问之后、午前争执之前
	var beat_at_map := {}
	for b in data.beats: beat_at_map[str(b.id)] = int(b["at"])
	check(beat_at_map["d1_deduce_truth"] > beat_at_map["d1_q3"] and beat_at_map["d1_deduce_truth"] < beat_at_map["d1_trap"],
		"「三句答复」推演位于三问之后、争执之前（%d > %d 且 < %d）" % [beat_at_map["d1_deduce_truth"], beat_at_map["d1_q3"], beat_at_map["d1_trap"]])
	# 11c. 不作弊诚实通关：靠搜证与探索自然集齐 10/10 知识与全部 33 件证物，达成 best 结局
	var honest := Engine_.new(data)
	honest.s.speed = 60.0
	var guard3 := 0
	while honest.s.ending == "" and guard3 < 200000:
		guard3 += 1
		if not honest.s.pending_deduction.is_empty():
			var dh: Dictionary = data.deduction_by_id[honest.s.pending_deduction.id]
			honest.solve_deduction(dh.id, dh.correct)
		elif honest.s.pending_conflict != "":
			honest.resolve_conflict(honest.s.pending_conflict, data.conflict_by_id[honest.s.pending_conflict].correct)
		elif not honest.s.pending_choice.is_empty():
			var pick3: String = honest.s.pending_choice.choice.options[0].id
			for o in honest.s.pending_choice.choice.options:
				if o.get("correct", false): pick3 = o.id
			honest.choose(honest.s.pending_choice.beat_id, pick3)
		elif not honest.s.get("story_gate", {}).is_empty():
			honest.s.room = str(honest.s.story_gate.room)
			honest.s.story_gate = {}
			honest.process_beats()
		elif honest.search_step():
			pass
		else:
			honest.tick(0.5)
	check(honest.knowledge_count() == data.knowledge.size(), "无作弊诚实通关集齐全部源质知识：%d/%d" % [honest.knowledge_count(), data.knowledge.size()])
	check(honest.s.found_count == data.evidence.size(), "无作弊诚实通关集齐全部证物：%d/%d" % [honest.s.found_count, data.evidence.size()])
	check(honest.s.ending == "best" and not honest.s.irreparable, "无作弊诚实通关达成破晓结局（实际 %s）" % honest.s.ending)
	# 11d. ×240 高倍速解除搜证门槛时不穿透到下一节拍，也不重复摊开案卷
	var ft := Engine_.new(data)
	ft.s.t = float(ft.T(4, 17, 35))
	ft.s.speed = 240.0
	ft.s.room = "B2-valve"
	ft.s.evidence["e_m_timeshare"] = {"at": 0, "room": "1F-Shaft-Monitor", "correct": true}
	ft.s.beat_cursor = 0
	for bi in data.beats.size():
		if str(data.beats[bi].id) == "d4_deduce_valve":
			ft.s.beat_cursor = bi
			break
	ft.process_beats()
	check(not ft.s.hold.is_empty(), "第四天阀路缺证物时正确挂起")
	ft.inspect_evidence("e_v_valve")
	ft.tick(0.1)
	check(ft.s.pending_deduction.get("id", "") == "ded_valve" and ft.s.pending_choice.is_empty() and str(ft.s.current_beat) == "d4_deduce_valve",
		"×240 解除 hold 后立即停在 ded_valve，不穿透进入 d4_strategy")
	# 11e. 第四夜分支：选 watch 不出现摘耳罩；选 trap 才触发摘耳罩反噬
	var d4w := Engine_.new(data)
	d4w.s.choices["d4"] = "watch"
	var b_d4_watch := {}
	for b in data.beats:
		if str(b.id) == "d4_night": b_d4_watch = d4w._resolve_beat(b)
	var watch_has_earmuff := false
	for ln in b_d4_watch.get("lines", []):
		if str(ln[1]).contains("摘下耳罩"): watch_has_earmuff = true
	var d4t := Engine_.new(data)
	d4t.s.choices["d4"] = "trap"
	var b_d4_trap := {}
	for b in data.beats:
		if str(b.id) == "d4_night": b_d4_trap = d4t._resolve_beat(b)
	var trap_has_earmuff := false
	for ln in b_d4_trap.get("lines", []):
		if str(ln[1]).contains("摘下耳罩"): trap_has_earmuff = true
	check((not watch_has_earmuff) and trap_has_earmuff, "第四夜分支真实生效：排轮值无耳罩穿帮，仅耳罩策略触发反噬")
	# 11f. 第三天候选案分支：选 ration 时展示空箱回收原账分支
	var d3r := Engine_.new(data)
	d3r.s.choices["ruanCase"] = "ration"
	var b_d3_ration := {}
	for b in data.beats:
		if str(b.id) == "d3_case": b_d3_ration = d3r._resolve_beat(b)
	check(str(b_d3_ration.get("lines", [])).contains("空箱回收原账"), "第三天候选案响应第二天打谱选择（%s）" % str(b_d3_ration.get("title", "")))
	# 11g. 门锁越权与 17:00 外院返程保护
	var lk := Engine_.new(data)
	lk.s.t = float(lk.T(1, 9, 0))
	lk.s.room = "2F-cross-M"
	lk.set_door_flags()
	check(lk.path_to("D-P", "2F-cross-M").is_empty(), "第一天上午丁区大门未开时，侦探不可借代管者边界门潜入丁区")
	lk.s.t = float(lk.T(2, 17, 30))
	lk.s.room = "W-102"
	lk.set_door_flags()
	check(not lk.path_to("2F-cross-M", "W-102").is_empty(), "17:00 风窗关闭后身处外院仍可安全撤回主楼")
	lk.enter_room("2F-cross-M", true)
	check(lk.path_to("W-102", "2F-cross-M").is_empty(), "撤回主楼后风窗仍保持关闭，不可再次外出")
	# 11h. 结局文案诚实性 + 无裂痕不落入 bitter
	var ep := Engine_.new(data)
	for kid in ["k_contract", "k_pressure", "k_gauge", "k_refraction", "k_meme"]:
		ep.grant_knowledge(kid)
	ep.s.final_choice = "lexeme"
	ep.s.irreparable = false
	check(ep.compute_ending() == "partial", "无不可弥合裂痕且知识 5/10 → partial 留白结局（实际 %s）" % ep.compute_ending())
	ep.s.irreparable = true
	ep.s.deductions["ded_truth"] = "wrong"
	ep.s.ending = ep.compute_ending()
	check(ep.s.ending == "bitter" and not ep.ending_text().contains("也拆穿了那三句真话"),
		"ded_truth 判错时 bitter 结局文案不谎称「也拆穿了那三句真话」")
	# 11i. 重复调查无变化证物不刷屏日志
	var dup := Engine_.new(data)
	dup.s.room = "B-P"
	var before_log: int = dup.s.log.size()
	dup.inspect_evidence("e_b_drag")
	dup.inspect_evidence("e_b_drag")
	check(dup.s.log.size() == before_log + 1, "重复调查读法未变的证物不刷屏日志")
	var rr := Engine_.new(data)
	rr.s.room = "B-P"
	rr.inspect_evidence("e_b_sleeve")
	var was_naive: bool = not bool(rr.s.evidence["e_b_sleeve"].get("correct", true)) and rr.s.misconceptions.size() == 1
	rr.s.deductions["ded_drag"] = "solved"
	rr.open_conflict("c_door")
	rr.resolve_conflict("c_door", "echo")
	var got_acoustic: bool = bool(rr.s.knowledge.has("k_acoustic"))
	rr.grant_knowledge("k_density", "test")
	var flipped_truth: bool = bool(rr.s.evidence["e_b_sleeve"].get("correct", false)) and rr.s.misconceptions.is_empty()
	check(was_naive and got_acoustic and flipped_truth, "拆解争执发放源质知识，且旧证物自动改读为客观读法")
	var cd := Engine_.new(data)
	for eid in ["e_m_pillar", "e_m_record", "e_m_timeshare"]:
		cd.s.evidence[eid] = {"at": 0, "correct": true}
	cd.open_deduction("ded_truth", "c_demon")
	cd.solve_deduction("ded_truth", "lie")
	var hidden_before: bool = cd.conflict_options("c_demon").filter(func(o): return o.id == "lexeme").is_empty()
	var bounced: bool = cd.retry_conflict_deduction("c_demon") and str(cd.s.pending_deduction.get("id", "")) == "ded_truth"
	cd.solve_deduction("ded_truth", "literal")
	var shown_after: bool = cd.s.pending_conflict == "c_demon" and not cd.conflict_options("c_demon").filter(func(o): return o.id == "lexeme").is_empty()
	check(hidden_before and bounced and shown_after, "关键对质（c_demon）判错前置推演后可直接返回重推并解锁正解")
	var lex_ok := true
	for c in data.conflicts:
		var uniq := {}
		for p in c.parties:
			uniq[data.sense_of(str(p), str(c.word))] = true
		if uniq.size() < 2:
			print("    词义无分歧：", c.id, " ", c.word, " ", uniq)
			lex_ok = false
	check(lex_ok, "全部 %d 场争执均存在真实词义分歧（至少 2 种不同义项）" % data.conflicts.size())
	var br_ok := true
	for pair in [["d1_poem", "poem", "stakeout", "indulge"], ["d3_case", "ruanCase", "probe", "page"], ["d4_night", "d4", "lock", "trap"], ["d5_final_verdict", "final", "lexeme", "demon"]]:
		var b_found: Dictionary = {}
		for b in data.beats:
			if b.id == pair[0]: b_found = b
		var ea := Engine_.new(data)
		ea.s.choices[pair[1]] = pair[2]
		var eb := Engine_.new(data)
		eb.s.choices[pair[1]] = pair[3]
		if str(ea.effective_beat_lines(b_found)) == str(eb.effective_beat_lines(b_found)):
			br_ok = false
	check(br_ok, "四大关键抉择（黑板诗／打谱／第四夜／结案页）均产生差异化后续剧情")
	var Lp := load("res://scenes/dual_world/LowpolyRoom.gd")
	var lp_count := 0
	var lp_ok := true
	var dummy_parent := Node3D.new()
	for room in data.rooms:
		var lp = Lp.new()
		var ds := Geo.make_design(room, data)
		if lp.attach(dummy_parent, str(room.id), ds):
			lp_count += 1
			var wr: Rect2 = lp.walk_rect(0.58)
			if wr.size.x < 1.0 or wr.size.y < 1.0 or lp.lamps.is_empty():
				lp_ok = false
			lp.detach()
		lp.free()
	dummy_parent.free()
	check(lp_ok and lp_count == 36, "%d 间 Lowpoly 3D 房间全部完成中心对齐、可行走边界提取与暖色顶灯挂载" % lp_count)
	print("失败 %d" % fails)
	quit(1 if fails > 0 else 0)
