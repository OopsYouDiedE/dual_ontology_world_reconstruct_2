extends RefCounted
## 「双本体」规则引擎（自 web 整合版迁入）：时间 / 节拍 / 证物 / 主观词义 / 认知冲突 / 关系账本 / 结局。
##
## 规则只有一条：世界事实只有一份；每个人只保存自己听到、看到、推断到的那一份。
## 期待落空时只有一方得到申诉证据，另一方永远不知道自己「违约」了。
## 纯 GDScript，不依赖 C# Core；状态是一份可 JSON 序列化的 Dictionary（见 save_dict / load_dict）。

const Data := preload("res://scenes/dual_world/DualData.gd")

signal changed(why: String)
signal said(who: String, text: String, kind: String)
signal sfx(kind: String)

const END_T := 4 * 1440 + 23 * 60 + 59
## 默认倍速：×5（旧版是 ×20，台词、搜证都来不及看）。
const DEFAULT_SPEED := 5.0
const LOCKS := ["zone.0", "zone.1", "zone.2", "zone.3", "service_map", "demon", "wind", "granary", "archive"]
const OUTER_ROOMS := ["Wind-Corridor", "W-102", "S-102", "B-102", "F-104"]

var d: RefCounted
var s: Dictionary = {}


func _init(data: RefCounted = null) -> void:
	d = data if data != null else Data.get_data()
	new_game(false)


func T(day: int, hour: int, minute: int = 0) -> int:
	return Data.t_minutes(day, hour, minute)


# ───────────────────────── 新局 / 存读档 ─────────────────────────
func new_game(announce := true) -> void:
	var rel := {}
	for p in d.relation_pairs:
		rel[Data.pair_key(p[0], p[1])] = {"trust": 62, "damage": 0, "permanent": false, "grievances": []}
	s = {
		"version": 1, "t": T(1, 7, 0), "playing": true, "speed": DEFAULT_SPEED, "waiting": false, "hold": {},
		"day": 1, "room": "R05", "author_view": false,
		"beat_cursor": 0, "pending_choice": {}, "pending_conflict": "", "conflict_queue": [],
		"pending_deduction": {}, "postponed": {}, "current_beat": "", "story_gate": {},
		"evidence": {}, "knowledge": {}, "beliefs": {}, "misconceptions": [], "log": [],
		"conflicts": {}, "choices": {}, "flags": {}, "relations": rel, "irreparable": false,
		"deductions": {}, "case_notes": [], "debug_log": [], "doors": {}, "found_count": 0,
		"inspected": {}, "ending": "", "final_choice": "", "selected_actor": "detective",
		"selected_evidence": "", "unlocked_terms": {},
	}
	set_door_flags()
	_log("system", "《安眠者有福 · 门的这一侧》—— 第一天清晨。侦探在 R05 居室的床上醒来——四人里醒得最晚。", [])
	if announce:
		_debug("new", "新局：源质知识为空；第一章的错误动机由缺知识驱动。")
		changed.emit("new")


func save_dict() -> Dictionary:
	return s.duplicate(true)


func load_dict(st: Dictionary) -> bool:
	if st.is_empty() or not st.has("t"):
		return false
	new_game(false)
	for k in st: s[k] = st[k]
	if not s.has("unlocked_terms") or typeof(s["unlocked_terms"]) != TYPE_DICTIONARY:
		s["unlocked_terms"] = {}
	s.waiting = not s.pending_choice.is_empty() or s.pending_conflict != "" or not s.pending_deduction.is_empty()
	set_door_flags()
	changed.emit("load")
	return true


# ───────────────────────── 日志 ─────────────────────────
func _debug(kind: String, text: String) -> void:
	s.debug_log.append({"t": s.t, "kind": kind, "text": text})
	if s.debug_log.size() > 300: s.debug_log.pop_front()


func _log(kind: String, text: String, who: Array) -> void:
	s.log.append({"t": s.t, "kind": kind, "text": text, "who": who})
	if s.log.size() > 420: s.log.pop_front()


func say(who: String, text: String, kind := "") -> void:
	s.last_line = {"who": who, "text": text, "kind": kind}
	said.emit(who, text, kind)


# ───────────────────────── 时间 ─────────────────────────
func clock() -> Dictionary:
	var t: float = s.t
	var day := int(floor(t / 1440.0)) + 1
	var within := fposmod(t, 1440.0)
	var h := int(floor(within / 60.0))
	var m := int(floor(fmod(within, 60.0)))
	return {"day": mini(5, day), "hour": h + m / 60.0, "h": h, "m": m, "text": "%02d:%02d" % [h, m]}


func phase() -> Dictionary:
	for p in d.phases:
		if s.t >= p["from"] and s.t < p["to"]:
			return p
	return d.phases[d.phases.size() - 1]


func set_speed(v: float) -> void:
	s.speed = v
	changed.emit("speed")


func toggle_play() -> void:
	s.playing = not s.playing
	changed.emit("play")


# ───────────────────────── 门锁 / 路径 ─────────────────────────
func set_door_flags() -> void:
	var t: float = s.t
	var c := clock()
	var f: Dictionary = s.flags
	s.doors = {
		"zone.0": t >= T(1, 9, 20) or f.has("service_map"),
		"zone.1": t >= T(1, 9, 20) or f.has("service_map"),
		"zone.2": t >= T(1, 9, 20) or f.has("service_map"),
		"zone.3": t >= T(1, 11, 0),
		"service_map": f.has("service_map"),
		"demon": true,
		"wind": c.day >= 2 and c.hour >= 9.0 and c.hour < 17.0,
		"granary": f.has("granary"),
		"archive": t >= T(5, 9, 0) or s.author_view,
	}


func unlocked(door: Dictionary) -> bool:
	set_door_flags()
	if s.author_view: return true
	var only: Variant = door.get("only", null)
	if only is Array and not only.is_empty():
		if only.has("demon") and not only.has("detective"):
			return false
	var lock: Variant = door.get("lock", null)
	if lock == null: return true
	if str(lock) == "wind" and not s.doors.get("wind", false):
		# 风窗 17:00 关闭后，若侦探仍身处外院，允许单向撤回主楼，不把玩家锁死在院外
		if str(s.room) in OUTER_ROOMS and (str(door.a) in OUTER_ROOMS or str(door.b) in OUTER_ROOMS):
			if str(door.a) == "2F-cross-M" or str(door.b) == "2F-cross-M" or str(door.a) == str(s.room) or str(door.b) == str(s.room):
				return true
	return s.doors.get(str(lock), false)


## 广度优先寻路；返回房间 id 序列，不可达返回空数组。
func path_to(target: String, start := "") -> Array:
	if start == "": start = s.room
	if start == target: return [target]
	var adj := {}
	for dr in d.doors:
		if not adj.has(dr.a): adj[dr.a] = []
		if not adj.has(dr.b): adj[dr.b] = []
		adj[dr.a].append([dr.b, dr])
		adj[dr.b].append([dr.a, dr])
	var queue: Array = [[start]]
	var seen := {start: true}
	while not queue.is_empty():
		var path: Array = queue.pop_front()
		var last: String = path[path.size() - 1]
		for pair in adj.get(last, []):
			var nb: String = pair[0]
			if seen.has(nb) or not unlocked(pair[1]): continue
			var np := path.duplicate()
			np.append(nb)
			if nb == target: return np
			seen[nb] = true
			queue.append(np)
	return []


func enter_room(id: String, silent := false) -> bool:
	if not d.room_by_id.has(id): return false
	var path := path_to(id)
	if path.is_empty() and not s.author_view:
		notice("门从里面闩着，现在过不去。")
		sfx.emit("error")
		return false
	s.room = id
	s.inspected[id] = true
	if not silent:
		var extra := "（经 %d 段接驳）" % (path.size() - 2) if path.size() > 2 else ""
		_log("move", "进入 %s%s" % [d.room_by_id[id].label, extra], [s.selected_actor])
		sfx.emit("door")
	changed.emit("room")
	return true


var notices: Array = []

func notice(text: String) -> void:
	notices.append({"text": text, "at": Time.get_ticks_msec()})
	if notices.size() > 4: notices.pop_front()
	changed.emit("notice")


# ───────────────────────── 证物与知识 ─────────────────────────
func knowledge_count() -> int:
	return s.knowledge.size()


func unlock_term(term: String) -> void:
	if term == "" or not d.terms.has(term): return
	if not s.has("unlocked_terms") or typeof(s["unlocked_terms"]) != TYPE_DICTIONARY:
		s["unlocked_terms"] = {}
	s["unlocked_terms"][term] = true


func grant_knowledge(id: String, why := "") -> bool:
	if not d.know_by_id.has(id) or s.knowledge.has(id): return false
	var kd: Dictionary = d.know_by_id[id]
	s.knowledge[id] = {"at": s.t, "why": why}
	_log("knowledge", "【新知 · %s】%s" % [kd.title, kd.text], [])
	_debug("knowledge", "【%s】%s（来源：%s）" % [kd.title, kd.text, why if why != "" else "调查"])
	notice("获得源质知识：【%s】" % kd.title)
	sfx.emit("page")
	_recheck_evidence_knowledge()
	changed.emit("knowledge")
	return true


## 补齐源质知识后，自动复核已取得的旧证物并触发级联知识解锁。
func _recheck_evidence_knowledge() -> void:
	var newly_granted: Array = []
	for eid in s.evidence.keys():
		if not d.evidence_by_id.has(eid): continue
		var e: Dictionary = d.evidence_by_id[eid]
		var was_correct: bool = bool(s.evidence[eid].get("correct", false))
		var r := read_evidence(str(eid))
		s.evidence[eid]["correct"] = r.correct
		if r.correct:
			s.misconceptions = s.misconceptions.filter(func(m): return m.eid != eid)
			var who: Array = e.actors if not e.get("actors", []).is_empty() else ["detective"]
			for a in who:
				if not s.beliefs.has(a): s.beliefs[a] = {}
				s.beliefs[a][eid] = "truth"
			if not was_correct:
				s.case_notes.append({"eid": eid, "at": s.t, "text": e.truth, "reread": true})
				_log("evidence", "【证物改读 · %s】%s" % [e.label, e.truth], who)
				_debug("evidence", "%s → 补齐知识后改读为客观读法：%s" % [e.label, e.truth])
			for k in e.get("grants", []):
				if not s.knowledge.has(k): newly_granted.append([str(k), str(e.label)])
	for pair in newly_granted:
		grant_knowledge(pair[0], pair[1])


## 读证物：缺少前置源质知识时只能得到「当前读法」；作者视角只改变显示，不替人物补知识。
func read_evidence(eid: String) -> Dictionary:
	if not d.evidence_by_id.has(eid): return {}
	var e: Dictionary = d.evidence_by_id[eid]
	var need: Array = []
	for k in e.get("need", []):
		if not s.knowledge.has(k): need.append(k)
	var correct := need.is_empty()
	return {
		"correct": correct, "need": need,
		"text": e.truth if (correct or s.author_view) else e.naive,
		"author_only": (not correct) and s.author_view,
	}


func inspect_evidence(eid: String) -> bool:
	if not d.evidence_by_id.has(eid): return false
	var e: Dictionary = d.evidence_by_id[eid]
	if s.room != e.room and not s.author_view:
		notice("得先到那间房去。")
		sfx.emit("error")
		return false
	var first: bool = not s.evidence.has(eid)
	var prev_correct: bool = bool(s.evidence.get(eid, {}).get("correct", false))
	s.evidence[eid] = {"at": s.t, "room": e.room}
	s.selected_evidence = eid
	# 配对互证解锁（例如对照「四锚分时日志」与「清场录音：23:31」解锁「两个时间节点」）
	var pair_id := str(e.get("unlock_pair", ""))
	if pair_id != "" and s.evidence.has(pair_id):
		for k in e.get("grants", []): grant_knowledge(str(k), e.label)
	var r := read_evidence(eid)
	s.evidence[eid]["correct"] = r.correct
	# 仅在首次调查或知识补齐改读时写入玩家日志，避免复查同一证物刷屏重复记录
	if first or (r.correct and not prev_correct):
		_log("evidence", "【%s】%s" % [e.label, r.text], e.get("actors", []))
	say("detective", r.text, "truth" if r.correct else "think")
	sfx.emit("pen")
	# 主观认知：各人保存自己那一份（知识补齐才会改）
	var who: Array = e.actors if not e.get("actors", []).is_empty() else ["detective"]
	for a in who:
		if not s.beliefs.has(a): s.beliefs[a] = {}
		s.beliefs[a][eid] = "truth" if r.correct else "naive"
	var mis: Array = s.misconceptions
	if not r.correct:
		var have := false
		for m in mis:
			if m.eid == eid: have = true
		if not have:
			mis.append({"eid": eid, "at": s.t, "text": e.naive, "need": r.need, "lex": e.get("lex", [])})
	else:
		s.misconceptions = mis.filter(func(m): return m.eid != eid)
		for k in e.get("grants", []): grant_knowledge(str(k), e.label)
	if first:
		s.found_count += 1
		s.case_notes.append({"eid": eid, "at": s.t, "text": r.text})
	elif r.correct and not prev_correct:
		s.case_notes.append({"eid": eid, "at": s.t, "text": r.text})
	_debug("evidence", "%s → %s：%s" % [e.label, "客观读法" if r.correct else "当前读法", r.text])
	changed.emit("evidence")
	return true


# ───────────────────────── 主观词义 ─────────────────────────
## 各当事人对冲突关键词取的义项。
func conflict_senses(cid: String) -> Array:
	var out: Array = []
	if not d.conflict_by_id.has(cid): return out
	var c: Dictionary = d.conflict_by_id[cid]
	for id in c.parties:
		out.append({"id": id, "name": d.actor_name(id), "sense": d.sense_label(id, c.word),
			"sense_id": d.sense_of(id, c.word), "color": d.actor_by_id[id].color})
	return out


## 说话者说出一个词、听者怎么理解。字面为真；是否「期待落空」取决于两人义项是否相同。
func utter(speaker: String, term: String, listener: String) -> Dictionary:
	var a: String = d.sense_of(speaker, term)
	var b: String = d.sense_of(listener, term)
	return {
		"term": term, "word": d.terms.get(term, {}).get("word", term),
		"meant": d.sense_label(speaker, term), "heard": d.sense_label(listener, term),
		"mismatch": a != b,
		"literal_true": true,  # 契约第八条：字面语义在客观现实中不得为假
	}


# ───────────────────────── 推演 / 争执 ─────────────────────────
func open_deduction(did: String, next := "") -> void:
	if not d.deduction_by_id.has(did) or s.deductions.has(did):
		if next != "": open_conflict(next)
		return
	if not s.pending_deduction.is_empty() and str(s.pending_deduction.get("id", "")) == did:
		if next != "": s.pending_deduction["next"] = next
		s.waiting = true
		changed.emit("deduction")
		return
	if not s.get("postponed", {}).is_empty() and str(s.postponed.get("id", "")) == did:
		if next != "": s.postponed["next"] = next
	s.pending_deduction = {"id": did, "next": next}
	s.waiting = true
	_log("beat", "摊开案卷 · %s" % d.deduction_by_id[did].title, [s.selected_actor])
	_debug("deduction", "推演开启 %s（争执前必经的一步）" % did)
	sfx.emit("page")
	changed.emit("deduction")


func solve_deduction(did: String, hyp_id: String, picked: Array = []) -> void:
	if s.pending_deduction.is_empty() or s.pending_deduction.id != did: return
	var dd: Dictionary = d.deduction_by_id[did]
	var pool: Array = picked if not picked.is_empty() else dd.evidence.filter(func(e): return s.evidence.has(e))
	var relevant: Array = pool.filter(func(e): return dd.evidence.has(e))
	var need_min := int(dd.get("minEvidence", 2))
	var solved: bool = hyp_id == dd.correct and relevant.size() >= need_min
	s.deductions[did] = "solved" if solved else "wrong"
	s.case_notes.append({"did": did, "at": s.t, "text": dd.note if solved else "这一页先空着，回头再核。"})
	var nxt: String = s.pending_deduction.next
	s.pending_deduction = {}
	_refresh_waiting()
	_log("deduce", "案卷推演 · %s → %s" % [dd.title, "已解开" if solved else "暂留空白"], [s.selected_actor])
	_debug("deduction", "%s → %s（假设 %s，证物 %d/%d 件）" % [did, s.deductions[did], hyp_id, relevant.size(), need_min])
	if solved:
		notice("推演成立：「%s」已记入案卷。" % dd.title)
		sfx.emit("success")
	else:
		notice("推演未成立：「%s」留白，可在「案卷 → 推演」或争执前重新推演。" % dd.title)
		sfx.emit("error")
	if nxt != "": open_conflict(nxt)
	changed.emit("deduction")


## 重新推演：只允许对「判错」的推演重试；对应争执若还没拆解，推演完成后会重新弹出争执。
func retry_deduction(did: String) -> bool:
	if not d.deduction_by_id.has(did) or not s.pending_deduction.is_empty() or not s.pending_choice.is_empty(): return false
	if not s.get("postponed", {}).is_empty() or not s.get("hold", {}).is_empty(): return false
	if s.deductions.get(did, "") != "wrong": return false
	var next := ""
	if s.pending_conflict != "":
		var conflict: Dictionary = d.conflict_by_id.get(s.pending_conflict, {})
		if conflict.get("deduction", null) != did: return false
		next = str(s.pending_conflict)
		_pop_conflict(next)
	if next == "":
		for conflict in d.conflicts:
			if conflict.get("deduction", null) == did and not s.conflicts.has(conflict.id):
				next = str(conflict.id)
				break
	s.deductions.erase(did)
	_debug("deduction", "重新推演 %s（接续争执：%s）" % [did, next if next != "" else "无"])
	open_deduction(did, next)
	return true


## 在争执弹窗里直接翻回案卷重做前置推演（尤其适用于不可搁置的 c_demon）。
func retry_conflict_deduction(cid: String) -> bool:
	if cid == "" or s.pending_conflict != cid or not d.conflict_by_id.has(cid): return false
	var c: Dictionary = d.conflict_by_id[cid]
	var did: String = str(c.get("deduction", "")) if c.get("deduction", null) != null else ""
	return retry_deduction(did)


## 证物不够时先关掉推演弹窗去取证：时间继续冻结，直到证物够了（或再无可取）才重新弹出同一个推演。
func postpone_deduction() -> bool:
	if s.pending_deduction.is_empty(): return false
	s.postponed = s.pending_deduction.duplicate()
	s.pending_deduction = {}
	_refresh_waiting()
	_log("system", "【先去取证】%s 先放一放，证物齐了再回来推演。" % d.deduction_by_id[s.postponed.id].title, [])
	_debug("deduction", "推演 %s 被推迟，等待取证" % s.postponed.id)
	changed.emit("hold")
	return true


## 推演弹窗里该显示的取证进度。
func deduction_progress(did: String) -> Dictionary:
	var g := gate_status(did)
	g["can_answer"] = bool(g.ok) or bool(g.stuck) or s.author_view
	return g


func _refresh_waiting() -> void:
	s.waiting = not s.pending_choice.is_empty() or s.pending_conflict != "" or not s.pending_deduction.is_empty()


## 争执里的正解，只有先完成对应推演才出现在侦探眼前。
func conflict_options(cid: String) -> Array:
	if not d.conflict_by_id.has(cid): return []
	var c: Dictionary = d.conflict_by_id[cid]
	var out: Array = []
	for o in c.options:
		var hidden: bool = c.get("deduction", null) != null and o.id == c.correct and s.deductions.get(c.deduction, "") != "solved"
		if not hidden: out.append(o)
	return out


func open_conflict(cid: String) -> void:
	if not d.conflict_by_id.has(cid) or s.conflicts.has(cid): return
	var c: Dictionary = d.conflict_by_id[cid]
	var ded: Variant = c.get("deduction", null)
	if ded != null and not s.deductions.has(ded):
		open_deduction(str(ded), cid)
		return
	unlock_term(str(c.get("word", "")))
	for tw in c.get("extra_words", []): unlock_term(str(tw))
	if not s.conflict_queue.has(cid): s.conflict_queue.append(cid)
	s.pending_conflict = s.conflict_queue[0]
	s.waiting = true
	_log("confront", "争执 · %s" % c.title, c.parties)
	_debug("conflict", "%s（%s）：%s %s" % [c.title, cid, c.get("wrong", ""), c.get("note", "")])
	sfx.emit("error")
	changed.emit("conflict")


func _pop_conflict(cid: String) -> void:
	s.conflict_queue = s.conflict_queue.filter(func(x): return x != cid)
	s.pending_conflict = s.conflict_queue[0] if not s.conflict_queue.is_empty() else ""
	_refresh_waiting()


func _rel(a: String, b: String) -> Dictionary:
	var k := Data.pair_key(a, b)
	if not s.relations.has(k):
		s.relations[k] = {"trust": 62, "damage": 0, "permanent": false, "grievances": []}
	return s.relations[k]


func resolve_conflict(cid: String, option_id: String, defer := false) -> void:
	if not d.conflict_by_id.has(cid): return
	# 幂等保护：该争执既不是当前弹窗、也不在队列里（已处理过），重复点击旧按钮不再结算
	if cid != s.pending_conflict and not s.conflict_queue.has(cid): return
	var c: Dictionary = d.conflict_by_id[cid]
	unlock_term(str(c.get("word", "")))
	for tw in c.get("extra_words", []): unlock_term(str(tw))
	var wrong: bool = defer or option_id != c.correct
	if defer and not c.get("permanent", false):
		_pop_conflict(cid)
		_log("say", "【%s】先搁下，这一页留白。" % c.title, c.parties)
		_debug("conflict", "%s：被搁置，未拆解" % c.title)
		changed.emit("conflict")
		return
	s.conflicts[cid] = "failed" if wrong else "resolved"
	_pop_conflict(cid)
	var label := "先搁下"
	for o in c.options:
		if o.id == option_id: label = o.label
	_log("say", "%s · %s" % [c.title, label], c.parties)
	_debug("conflict", "%s → %s（%s）；词义 %s，判定 %s" % [c.title, "误判" if wrong else "正确", option_id if option_id != "" else "defer", c.word, c.correct])
	var a: String = c.parties[0]
	var b: String = c.parties[1]
	if wrong:
		sfx.emit("error")
		if c.get("permanent", false):
			s.irreparable = true
			for pr in [["ward", "quer"], ["moran", "selma"], ["su", "detective"]]:
				var r2 := _rel(pr[0], pr[1])
				r2.trust = maxi(4, int(r2.trust) - 46)
				r2.damage = int(r2.damage) + 46
				r2.permanent = true
				r2.grievances.append({"who": pr[0], "other": pr[1], "one_sided": true, "at": s.t,
					"text": "第一天的真话被各自听成不同事实。事后查明真相也不会复原这一条。"})
			_debug("relation", "不可弥合：沃德／雀儿、莫兰／赛尔玛、苏泠／侦探三组信任永久受损；事后查明真相也不会复原。")
		else:
			var rel := _rel(a, b)
			rel.trust = maxi(0, int(rel.trust) - 22)
			rel.damage = int(rel.damage) + 22
			rel.grievances.append({
				"who": a, "other": b, "one_sided": true, "at": s.t,
				"text": "%s把「%s」记成「%s」，%s记成「%s」。期待落空，只有前者提出申诉；后者并不知道自己「违约」了。" % [
					d.actor_name(a), d.terms[c.word].word, d.sense_label(a, c.word),
					d.actor_name(b), d.sense_label(b, c.word)]})
	else:
		sfx.emit("success")
		var r3 := _rel(a, b)
		var cap := 38 if bool(r3.get("permanent", false)) else 100
		r3.trust = mini(cap, int(r3.trust) + 16)
		var rewards: Array = c.get("need", []).duplicate()
		for reward in c.get("grants", []):
			if not rewards.has(reward): rewards.append(reward)
		for reward in rewards:
			grant_knowledge(str(reward), c.title)
		if cid == "c_demon": grant_knowledge("k_contract", "第一天的对照")
	changed.emit("conflict")


func choose(beat_id: String, option_id: String) -> void:
	var beat: Dictionary = {}
	for b in d.beats:
		if b.id == beat_id: beat = b
	if beat.is_empty() or not beat.has("choice"): return
	# 幂等保护：只有当前挂起的抉择才能结算
	if s.pending_choice.is_empty() or str(s.pending_choice.get("beat_id", "")) != beat_id: return
	var opt: Dictionary = {}
	for o in beat.choice.options:
		if o.id == option_id: opt = o
	if opt.is_empty(): return
	s.choices[beat.choice.id] = option_id
	for k in opt.get("set", {}): s.flags[k] = opt.set[k]
	if beat.choice.id == "final": s.final_choice = option_id
	for tr in opt.get("trust", []):
		if tr is Array and tr.size() >= 3:
			var rel := _rel(str(tr[0]), str(tr[1]))
			var delta := int(tr[2])
			rel.trust = clampi(int(rel.trust) + delta, 4, 100)
			if delta < 0: rel.damage = int(rel.damage) + (-delta)
	s.pending_choice = {}
	_refresh_waiting()
	var resolved_beat := _resolve_beat(beat)
	_log("choice", "%s → %s" % [resolved_beat.title, opt.label], [s.selected_actor])
	_debug("choice", "%s / %s %s" % [resolved_beat.title, option_id, "（设计中为正解）" if opt.get("correct", false) else ""])
	var after_lines: Array = opt.get("after_lines", [])
	if after_lines.is_empty():
		say("detective", opt.label, "")
	else:
		for ln in after_lines:
			var who: String = str(ln[0])
			var nm: String = "" if who == "narrator" else d.actor_name(who) + "："
			_log("say", nm + str(ln[1]), [who])
			say(who, str(ln[1]), str(ln[2]) if ln.size() > 2 else "")
	sfx.emit("error" if opt.get("correct", true) == false else "click")
	changed.emit("choice")


# ───────────────────────── 节拍 ─────────────────────────
func effective_beat_branch(b: Dictionary) -> Dictionary:
	var bc := str(b.get("branch_choice", ""))
	if bc == "" or not b.has("branches"): return {}
	var chosen := str(s.choices.get(bc, s.flags.get(bc, "")))
	if chosen != "" and b.branches.has(chosen):
		return b.branches[chosen]
	return {}


func effective_beat_lines(b: Dictionary) -> Array:
	var br := effective_beat_branch(b)
	if not br.is_empty() and br.has("lines"):
		return br.lines
	return b.get("lines", [])


func next_beat() -> void:
	if s.waiting or not s.get("hold", {}).is_empty() or not s.get("story_gate", {}).is_empty() or not s.get("postponed", {}).is_empty():
		notice("请先处理当前现场取证或弹窗事项。")
		return
	for b in d.beats:
		if b["at"] > s.t + 0.01:
			s.t = float(b["at"])
			process_beats()
			changed.emit("jump")
			return
	finish()


func jump_day(day: int) -> void:
	var target := float(T(day, 7, 0))
	if target < s.t:
		var keep := {"author_view": s.author_view}
		new_game(false)
		for k in keep: s[k] = keep[k]
	s.t = target
	s.postponed = {}
	s.hold = {}
	s.beat_cursor = d.beats.size()
	for i in d.beats.size():
		if d.beats[i]["at"] >= s.t:
			s.beat_cursor = i
			break
	process_beats()
	changed.emit("jump")


## 根据已作出的抉择 / 标记解析条件分支节拍（保持原数据不可变）。
func _resolve_beat(b: Dictionary) -> Dictionary:
	var variants: Dictionary = b.get("variants", {})
	var out := b.duplicate(false)
	for key in variants:
		var val := str(s.choices.get(key, s.flags.get(key, "")))
		var table: Dictionary = variants[key]
		if val != "" and table.has(val):
			var patch: Dictionary = table[val]
			for pk in patch: out[pk] = patch[pk]
	var branch := effective_beat_branch(b)
	for key in branch: out[key] = branch[key]
	return out


func process_beats() -> void:
	if s.waiting: return
	var fired := 0
	while s.beat_cursor < d.beats.size() and d.beats[s.beat_cursor]["at"] <= s.t:
		var b: Dictionary = _resolve_beat(d.beats[s.beat_cursor])
		# 场景门：标记为现场到达型的节拍不会把玩家瞬移到房间；时间停住，等玩家亲自走到场景。
		if b.get("requires_room", false) and not s.author_view and str(b.get("room", "")) != str(s.room):
			var target_room := str(b.get("room", ""))
			if str(s.get("story_gate", {}).get("beat", "")) != str(b.id):
				s.story_gate = {"beat": b.id, "room": target_room}
				s.t = float(b.at)
				notice("剧情停在现场门口：请亲自前往「%s」，不会自动切图。" % d.room_by_id[target_room].label if d.room_by_id.has(target_room) else "请前往剧情现场。")
			break
		if not s.get("story_gate", {}).is_empty() and str(s.story_gate.get("beat", "")) == str(b.id):
			s.story_gate = {}
		# 搜证门槛：推演节拍触发前，侦探必须亲自在现场拿到足够的相关证物。
		if _hold_for_evidence(b): break
		s.beat_cursor += 1
		s.current_beat = b.id
		if b.has("room") and d.room_by_id.has(b.room) and not b.get("remote", false) and s.room != b.room and not s.author_view:
			s.room = b.room  # 剧情推进时主角自动跟随到场（隔墙/远程事件不瞬移主角）
		var where: String = " · " + d.room_by_id[b.room].label if b.has("room") and d.room_by_id.has(b.room) else ""
		var lines := effective_beat_lines(b)
		var cast := _beat_speakers(b)
		_log("beat", "【%s】%s" % [b.title, where], cast)
		for ln in lines:
			var who: String = ln[0]
			var nm: String = "" if who == "narrator" else d.actor_name(who) + "："
			_log("say", nm + str(ln[1]), [who])
			say(who, ln[1], str(ln[2]) if ln.size() > 2 else "")
		var br := effective_beat_branch(b)
		for td in br.get("trust_delta", []):
			if td.size() >= 3:
				var rel := _rel(str(td[0]), str(td[1]))
				var delta := int(td[2])
				rel.trust = clampi(int(rel.trust) + delta, 0, 100)
				if delta < 0:
					rel.damage = int(rel.damage) - delta
					rel.grievances.append({
						"who": str(td[0]), "other": str(td[1]), "one_sided": true, "at": s.t,
						"text": "%s认为在「%s」的处置上被当作诱饵替自己做了决定。" % [d.actor_name(str(td[0])), b.title]
					})
		for tw in b.get("unlock_terms", []): unlock_term(str(tw))
		if b.has("grant"): grant_knowledge(b.grant, b.title)
		if b.has("flag"): s.flags[b.flag] = true
		if b.has("deduction") and not s.deductions.has(b.deduction): open_deduction(b.deduction)
		if b.has("openConflict") and not s.conflicts.has(b.openConflict): open_conflict(b.openConflict)
		if b.has("choice"):
			s.pending_choice = {"beat_id": b.id, "choice": b.choice}
			s.waiting = true
		if b.get("mustChoose", false) and not s.conflicts.has("c_demon") and not s.conflict_queue.has("c_demon"):
			open_conflict("c_demon")
		fired += 1
		# 一次只交付一个场景：字幕读完后再继续时间线，禁止同一帧跨房间连播多幕。
		break
	s.day = clock().day
	set_door_flags()
	if fired > 0: changed.emit("beat")


## 以「游戏分钟」推进（真实秒 × 倍率）。有待决事项时时间冻结，直到玩家处理。
func tick(dt: float) -> void:
	if not s.playing or s.waiting or s.ending != "": return
	if not s.get("story_gate", {}).is_empty():
		if str(s.room) != str(s.story_gate.get("room", "")): return
		s.story_gate = {}
		process_beats()
		if s.waiting or not s.get("hold", {}).is_empty() or not s.get("story_gate", {}).is_empty(): return
	if not s.get("hold", {}).is_empty():  # 等侦探搜证：时间不走，每帧复核门槛
		process_beats()
		# 门槛解除后若已弹出推演/争执/抉择或进入新门禁，必须立刻返回，禁止同帧推进时间穿透到下一节拍
		if s.waiting or not s.get("hold", {}).is_empty() or not s.get("story_gate", {}).is_empty(): return
	if not s.get("postponed", {}).is_empty():  # 玩家主动推迟了推演：证物够了再弹回来
		var pp: Dictionary = s.postponed
		var gp := gate_status(str(pp.id))
		if not (gp.ok or gp.stuck): return
		s.postponed = {}
		open_deduction(str(pp.id), str(pp.get("next", "")))
		return
	if s.t >= END_T:
		finish()
		return
	var next_t := minf(float(END_T), s.t + dt * s.speed)
	# 高倍速（如 ×60/×240）下精确停靠在下一未触发节拍时刻，避免跳过风窗或连撞多拍
	if s.beat_cursor < d.beats.size():
		var beat_at := float(d.beats[s.beat_cursor]["at"])
		if s.t < beat_at and next_t > beat_at:
			next_t = beat_at
	s.t = next_t
	set_door_flags()
	process_beats()
	if s.t >= END_T and not s.waiting: finish()


# ───────────────────────── 搜证门槛 / 自动搜证 ─────────────────────────
func _reachable(room: String, from: String) -> bool:
	return room == from or not path_to(room, from).is_empty()


## 某个推演当前的取证情况：have 已取得的相关证物数，need 需要数，
## missing 还能取到的相关证物（从 from 房间出发走得到），stuck = 不够且再没有能取的了。
func gate_status(did: String, from := "") -> Dictionary:
	if from == "": from = s.room
	var dd: Dictionary = d.deduction_by_id[did]
	var need := int(dd.get("minEvidence", 2))
	var have := 0
	var missing: Array = []
	for eid in dd.evidence:
		if s.evidence.has(eid): have += 1
		elif _reachable(str(d.evidence_by_id[eid].room), from): missing.append(eid)
	var ok := have >= need
	return {"ok": ok, "have": have, "need": need, "missing": missing, "stuck": not ok and missing.is_empty()}


## 节拍带推演、而侦探手里证物不够 → 先把侦探带到现场并挂起，返回 true 表示这一拍先不触发。
func _hold_for_evidence(b: Dictionary) -> bool:
	if s.author_view or not b.has("deduction") or s.deductions.has(b.deduction):
		if not s.get("hold", {}).is_empty() and s.hold.get("beat", "") == b.get("id", ""): s.hold = {}
		return false
	var room: String = str(b.room) if b.has("room") and d.room_by_id.has(b.room) else s.room
	var hold: Dictionary = s.get("hold", {})
	if hold.get("beat", "") != b.id:
		# 刚到这一拍：侦探先到现场（剧情位置），推演之前不弹窗
		s.t = minf(float(s.t), float(b["at"]))
		if s.room != room:
			s.room = room
			s.inspected[room] = true
			_log("move", "赶到 %s" % d.room_by_id[room].label, [s.selected_actor])
			sfx.emit("door")
			changed.emit("room")
	var g := gate_status(b.deduction, s.room)
	if g.ok:
		s.hold = {}
		return false
	if g.stuck:
		# 再没有能取到的证物了：不让游戏卡死，凭现有线索推演（推演本身会因证物不足判错）
		s.hold = {}
		_log("system", "【线索有限】能取到的相关证物都已查过，只能凭现有线索推演。", [])
		return false
	s.t = minf(float(s.t), float(b["at"]))
	if hold.get("beat", "") != b.id:
		s.hold = {"beat": b.id, "deduction": b.deduction}
		_log("system", "【先搜证】%s：手头相关证物 %d/%d 件，推演前先到现场查看。" % [d.deduction_by_id[b.deduction].title, g.have, g.need], [])
		_debug("gate", "推演 %s 被挂起：证物 %d/%d" % [b.deduction, g.have, g.need])
		notice("先搜证：「%s」还差 %d 件相关证物。" % [d.deduction_by_id[b.deduction].title, g.need - g.have])
		changed.emit("hold")
	return true


func hold_text() -> String:
	var h: Dictionary = s.get("hold", {})
	if h.is_empty() and not s.get("postponed", {}).is_empty(): h = {"deduction": s.postponed.id}
	if h.is_empty(): return ""
	var g := gate_status(str(h.deduction))
	var rooms: Array = []
	for eid in g.missing:
		var lb := str(d.room_by_id[d.evidence_by_id[eid].room].label)
		if not rooms.has(lb): rooms.append(lb)
	return "等待搜证 · %s：证物 %d/%d%s" % [d.deduction_by_id[h.deduction].title, g.have, g.need,
		("  可查：" + "、".join(rooms)) if not rooms.is_empty() else ""]


## 侦探下一件该查的证物（自动搜证用）：
## 1) 先搜完本房；2) 若有被挂起/推迟的推演，优先去查该推演还缺的最近证物；
## 3) 空闲探索时段，优先趁白天风窗去查外院四室，再查其它可达房间遗漏的证物。
func next_search_target() -> String:
	for e in d.evidence:
		if e.room == s.room and not s.evidence.has(e.id): return str(e.id)
	var h: Dictionary = s.get("hold", {})
	if h.is_empty() and not s.get("postponed", {}).is_empty(): h = {"deduction": s.postponed.id}
	if not h.is_empty():
		var best := ""
		var best_len := 1 << 30
		for eid in gate_status(str(h.deduction)).missing:
			var pth: Array = path_to(str(d.evidence_by_id[eid].room))
			if not pth.is_empty() and pth.size() < best_len:
				best = str(eid)
				best_len = pth.size()
		return best
	if not s.get("story_gate", {}).is_empty(): return ""
	# 空闲探索：优先白天开放的外院四室（避免 17:00 关窗错过），其次最近可达未查证物
	var best_any := ""
	var best_score := 1 << 30
	for e in d.evidence:
		if s.evidence.has(e.id): continue
		var rm := str(e.room)
		var pth: Array = path_to(rm)
		if pth.is_empty(): continue
		var score := pth.size()
		if rm in OUTER_ROOMS: score -= 100  # 白天风窗限时开放，优先搜完四院
		if score < best_score:
			best_score = score
			best_any = str(e.id)
	return best_any


## 无界面的一步搜证（脚本 / 测试用）：同房直接查，不同房先进房。返回是否做了事。
func search_step() -> bool:
	var eid := next_search_target()
	if eid == "": return false
	if d.evidence_by_id[eid].room == s.room: return inspect_evidence(eid)
	return enter_room(str(d.evidence_by_id[eid].room))


# ───────────────────────── 人物位置 ─────────────────────────
## 五天所有场景统一按当前生效分支台词的实际说话者确定镜头内角色。
func _beat_speakers(b: Dictionary) -> Array:
	var out: Array = []
	for ln in effective_beat_lines(b):
		if ln.size() < 2: continue
		var who := str(ln[0])
		if who != "narrator" and d.actor_by_id.has(who) and not out.has(who): out.append(who)
	return out


func room_occupants() -> Dictionary:
	var occ := {}
	var put := func(id: String, room: String) -> void:
		if not d.actor_by_id.has(id) or not d.room_by_id.has(room): return
		if not occ.has(room): occ[room] = []
		if not occ[room].has(id): occ[room].append(id)
	var busy := {}
	# 挂起在现场等待搜证／到达时，对应现场等候的当事人留在现场房间
	var hold_beat_id := str(s.get("hold", {}).get("beat", s.get("story_gate", {}).get("beat", "")))
	if hold_beat_id != "":
		for b in d.beats:
			if str(b.id) == hold_beat_id:
				var target_rm := str(b.get("room", ""))
				for wid in b.get("waiters", []):
					busy[str(wid)] = true
					put.call(str(wid), target_rm)
				break
	# 争执弹窗激活时，争执当事人留在当前房间
	if s.pending_conflict != "" and d.conflict_by_id.has(s.pending_conflict):
		var cf: Dictionary = d.conflict_by_id[s.pending_conflict]
		for pid in cf.get("parties", []):
			if str(pid) == "detective": continue
			busy[str(pid)] = true
			put.call(str(pid), str(s.room))
	var last: Dictionary = {}
	for b in d.beats:
		if b["at"] <= s.t and b.has("lines") and d.beats.find(b) < s.beat_cursor: last = _resolve_beat(b)
	# 只显示当前场景真正开口的角色；名单不再把整张地图/全体角色瞬间搬来。
	# 场景人物在短暂交谈后回到自己的日常位置，不会在错误房间滞留数小时。
	if not last.is_empty() and s.t - float(last["at"]) < float(last.get("duration", 25)):
		for id in _beat_speakers(last):
			if busy.has(id): continue
			busy[id] = true
			put.call(id, str(last.get("room", "")))
		if last.get("demon", false): busy["demon"] = true
	var h: float = clock().hour
	for a in d.actors:
		if busy.has(a.id): continue
		if a.id == "demon":
			put.call(a.id, "D-gate")
			continue
		var r: String = a.home
		# 开场：侦探在 R05 床上醒来（四人里最晚）；其余三人已在乙区小厨房。
		if s.t < T(1, 8, 30):
			r = "R05" if a.id == "detective" else ("B-P" if a.home in ["R06", "R07", "R08"] else a.home)
		elif h >= 12.0 and h < 17.0 and s.t >= T(1, 11, 0):
			r = "T01" if s.day == 1 else "2F-cross-M"
		elif h >= 17.5 and h < 21.0:
			r = "F03"
		elif h >= 7.2 and h < 11.5 and s.t >= T(1, 11, 0):
			r = "2F-cross-M"
		put.call(a.id, r)
	return occ


func actors_in_room(room: String) -> Array:
	var list: Array = room_occupants().get(room, [])
	return list.slice(0, 12)


func current_demon() -> bool:
	var last: Dictionary = {}
	for b in d.beats:
		if b["at"] <= s.t and b.get("demon", false) and d.beats.find(b) < s.beat_cursor: last = b
	return not last.is_empty() and s.t - last["at"] < 95


## 音乐状态：程序化配乐据此改变调性、速度与织体。
func music_state() -> Dictionary:
	var c := clock()
	var mood := "investigation"
	if s.ending != "": mood = "truth"
	elif current_demon(): mood = "demon"
	elif s.pending_conflict != "" or not s.pending_choice.is_empty(): mood = "confrontation"
	elif s.t >= T(1, 17, 30) and s.t < T(1, 21) and s.day == 1: mood = "dumpling"
	elif c.hour >= 20.0 or c.hour < 6.0: mood = "night"
	elif s.day >= 2 and c.hour >= 9.0 and c.hour < 17.0: mood = "daily"
	var tension := (0.5 if s.irreparable else 0.0) + (0.3 if s.pending_conflict != "" else 0.0)
	return {"mood": mood, "hour": c.hour, "demon": current_demon(), "tension": tension}


# ───────────────────────── 结局 ─────────────────────────
func compute_ending() -> String:
	var k := knowledge_count()
	if k < 4 or s.final_choice == "fate": return "lost"
	if s.final_choice == "demon": return "trapped"
	if s.irreparable: return "bitter"
	if k >= 6: return "best"
	return "partial" if d.endings.has("partial") else "bitter"


## 依实际查清的知识项与推演状态生成结局正文，避免结局文本宣称「已查清／已拆穿」未完成的线索。
func ending_text(ending_id := "") -> String:
	var eid := ending_id if ending_id != "" else str(s.ending)
	if not d.endings.has(eid): return ""
	if eid != "bitter":
		return str(d.endings[eid].text)
	var parts: Array = []
	if s.knowledge.has("k_pressure"): parts.append("23:31 与 23:55 的分别")
	if s.knowledge.has("k_acoustic"): parts.append("管里的余音")
	if s.knowledge.has("k_imprint"): parts.append("窗上的影子")
	if s.knowledge.has("k_gauge"): parts.append("反着的读数")
	var truth_solved := str(s.deductions.get("ded_truth", "")) == "solved"
	var head := ""
	if not parts.is_empty():
		head = "你最终查清了" + "、".join(parts)
	else:
		head = "你最终拼出了部分灾变当夜的轮廓"
	if truth_solved:
		head += "，也拆穿了那三句真话。"
	else:
		head += "，但第一天那三句真话的机关仍未彻底拆开。"
	return head + "可是第一天上午的话已经落地：沃德与雀儿、莫兰与赛尔玛、苏泠与你之间，有些东西事后也补不回来。"


## 按实际查明的推演、源质知识与人际裂痕生成与本局状态严格吻合的结局叙述。
func ending_summary() -> String:
	var eid := str(s.ending if s.ending != "" else compute_ending())
	return ending_text(eid)


func finish() -> void:
	if s.ending != "": return
	s.ending = compute_ending()
	s.playing = false
	_debug("ending", "结局 %s · %s" % [s.ending, d.endings[s.ending].title])
	sfx.emit("chime")
	changed.emit("ending")


func force_ending() -> void:
	if s.final_choice == "": s.final_choice = "lexeme"
	s.t = maxf(s.t, float(T(5, 21, 0)))
	finish()
