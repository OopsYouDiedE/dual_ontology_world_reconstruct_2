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
		else:
			e.tick(1.0)
	check(e.s.ending == "best", "全部正解 + 九条知识 → 结局 best（实际 %s）" % e.s.ending)
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
	print("失败 %d" % fails)
	quit(1 if fails > 0 else 0)
