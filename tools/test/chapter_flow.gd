extends SceneTree
## 纯引擎章节回归。正式版写入 tools/test/chapter_flow.gd 后，以 Godot headless 执行。
## 覆盖章节边界，不替代从开场到 d1_plan 的 UI 流程探针。

const Data := preload("res://scenes/dual_world/DualData.gd")
const Engine_ := preload("res://scenes/dual_world/DualEngine.gd")

var fails := 0


func _check(ok: bool, text: String) -> void:
	print(("PASS  " if ok else "FAIL  ") + text)
	if not ok: fails += 1


func _beat_index(engine, id: String) -> int:
	for i in engine.d.beats.size():
		if str(engine.d.beats[i].id) == id: return i
	return -1


func _ready_for_rest(engine) -> void:
	engine.s.t = float(engine.T(1, 21, 35))
	engine.s.day = 1
	engine.s.room = "F03"
	engine.s.current_beat = "d1_plan"
	engine.s.flags["day2_plan"] = true
	engine.s.beat_cursor = _beat_index(engine, "d2_wind")
	engine.s.waiting = false
	engine.s.hold = {}
	engine.s.postponed = {}
	engine.s.story_gate = {}
	engine.s.playing = true


func _poem_branch(branch: String) -> void:
	var engine = Engine_.new(Data.get_data())
	engine.s.t = float(engine.T(1, 13, 15))
	engine.s.room = "2F-cross-M"
	engine.s.beat_cursor = _beat_index(engine, "d1_poem_hint")
	engine.process_beats()
	_check(str(engine.s.pending_choice.get("beat_id", "")) == "d1_poem_hint", "%s：黑板诗抉择正常出现" % branch)
	engine.choose("d1_poem_hint", branch)
	_check(str(engine.s.choices.get("poem", "")) == branch, "%s：抉择写入状态" % branch)
	engine.s.t = float(engine.T(1, 13, 35))
	engine.process_beats()
	_check(str(engine.s.current_beat) == "d1_poem", "%s：汇入黑板诗事件" % branch)
	var poem: Dictionary = {}
	for beat in engine.d.beats:
		if str(beat.id) == "d1_poem":
			poem = beat
			break
	var lines: Array = engine.effective_beat_lines(poem)
	_check(not lines.is_empty(), "%s：黑板诗分支有台词" % branch)
	engine.s.t = float(engine.T(1, 15, 30))
	engine.process_beats()
	_check(str(engine.s.current_beat) == "d1_institutes", "%s：三条路线汇回四院讲义事件" % branch)


func _initialize() -> void:
	var data = Data.get_data()

	# 自然时间：从 d1_plan 21:35 正常走到 22:00，章节完成但不设置全故事结局。
	var natural = Engine_.new(data)
	_ready_for_rest(natural)
	natural.tick(5.0)
	var natural_status: Dictionary = natural.chapter_status()
	_check(bool(natural_status.complete), "自然时间在第一天 22:00 完成第一章")
	_check(bool(natural_status.ready_for_rest), "章节状态开放休息／继续入口")
	_check(not bool(natural.s.playing), "第一章完成后时间暂停")
	_check(str(natural.s.ending) == "", "第一章完成不写入全故事结局")
	_check(int(natural.s.t) == natural.CHAPTER_ONE_END_T, "自然时间停在第一天 22:00")

	# 高倍速：同一边界不能越过第二天节拍。
	var fast = Engine_.new(data)
	_ready_for_rest(fast)
	fast.s.speed = 240.0
	fast.tick(1.0)
	_check(bool(fast.s.chapter_complete), "高倍速仍在第一章边界停下")
	_check(str(fast.s.current_beat) == "d1_plan", "高倍速未消费第二天节拍")

	# 下一节拍：从 d1_plan 只到章节完成，不跳到 d2_wind。
	var jumped = Engine_.new(data)
	_ready_for_rest(jumped)
	jumped.next_beat()
	_check(bool(jumped.s.chapter_complete), "下一节拍完成第一章")
	_check(str(jumped.s.current_beat) == "d1_plan", "下一节拍未跳过章节边界")

	# 第一章结章必须先消费 d1_plan，并清空所有待处理事项。
	var plan_index := _beat_index(jumped, "d1_plan")
	var unconsumed = Engine_.new(data)
	unconsumed.s.t = float(unconsumed.CHAPTER_ONE_END_T)
	unconsumed.s.beat_cursor = plan_index
	unconsumed.s.playing = true
	unconsumed._complete_chapter_one()
	_check(not bool(unconsumed.s.chapter_complete), "d1_plan 未消费时不能直接完成第一章")
	unconsumed.process_beats()
	_check(bool(unconsumed.s.chapter_complete) and str(unconsumed.s.current_beat) == "d1_plan" and bool(unconsumed.s.flags.get("day2_plan", false)), "process_beats 消费 d1_plan 后完成第一章")
	var unconsumed_tick = Engine_.new(data)
	unconsumed_tick.s.t = float(unconsumed_tick.CHAPTER_ONE_END_T)
	unconsumed_tick.s.beat_cursor = plan_index
	unconsumed_tick.s.playing = true
	unconsumed_tick.tick(1.0)
	_check(bool(unconsumed_tick.s.chapter_complete) and str(unconsumed_tick.s.current_beat) == "d1_plan", "tick 消费 d1_plan 后完成第一章")
	var unconsumed_jump = Engine_.new(data)
	unconsumed_jump.s.t = float(unconsumed_jump.CHAPTER_ONE_END_T)
	unconsumed_jump.s.beat_cursor = plan_index
	unconsumed_jump.s.playing = true
	unconsumed_jump.next_beat()
	_check(bool(unconsumed_jump.s.chapter_complete) and str(unconsumed_jump.s.current_beat) == "d1_plan", "next_beat 消费 d1_plan 后完成第一章")

	var pending = Engine_.new(data)
	_ready_for_rest(pending)
	pending.s.t = float(pending.CHAPTER_ONE_END_T)
	pending.s.pending_deduction = {"id": "ded_drag", "next": ""}
	pending.s.waiting = true
	pending.tick(1.0)
	pending.process_beats()
	pending.next_beat()
	_check(not bool(pending.s.chapter_complete) and int(pending.s.t) == pending.CHAPTER_ONE_END_T, "待处理推演时 tick、process_beats 与 next_beat 都保留第一章")

	# 三条黑板诗路线都汇入同一个后续事件。
	for branch in ["stakeout", "expose", "indulge"]:
		_poem_branch(branch)

	# 存读档与显式继续：保留长期状态，第二天从 07:00 和首个第二天节拍之前开始。
	natural.s.evidence["e_b_drag"] = {"at": 480.0, "room": "B-P", "correct": false}
	natural.s.knowledge["k_contract"] = true
	natural.s.choices["poem"] = "stakeout"
	var su_detective := Data.pair_key("su", "detective")
	natural.s.relations[su_detective]["trust"] = 78
	var saved := natural.save_dict()
	var loaded = Engine_.new(data)
	_check(loaded.load_dict(saved), "第一章结章存档可读取")
	_check(bool(loaded.chapter_status().complete), "读档保留第一章完成状态")
	_check(loaded.continue_chapter(), "完成第一章后可显式进入第二章")
	_check(int(loaded.s.chapter) == 2 and int(loaded.s.t) == loaded.CHAPTER_TWO_START_T and str(loaded.s.room) == "R05", "第二章从 R05 的第二天 07:00 开始")
	_check(loaded.s.playing and not bool(loaded.s.chapter_complete), "继续后恢复推进且清除完成标记")
	_check(str(loaded.s.choices.get("poem", "")) == "stakeout" and loaded.s.evidence.has("e_b_drag") and loaded.s.knowledge.has("k_contract"), "继续第二章保留证物、知识与抉择")
	_check(int(loaded.s.relations[su_detective].trust) == 78, "继续第二章保留关系账本")
	_check(loaded.s.beat_cursor == _beat_index(loaded, "d2_wind"), "继续不跳过第二天首个节拍")

	# 老档迁移：没有章节字段但已到第二天的存档推断为第二章。
	var legacy = Engine_.new(data)
	var old_save := legacy.save_dict()
	old_save.erase("chapter")
	old_save.erase("chapter_complete")
	old_save.t = float(legacy.T(2, 7, 0))
	old_save.day = 2
	var migrated = Engine_.new(data)
	_check(migrated.load_dict(old_save), "旧版第二天存档可读取")
	_check(int(migrated.s.chapter) == 2 and not bool(migrated.s.chapter_complete), "旧版第二天存档迁移到第二章")

	# 开发跳日入口遵从同一状态机。
	var dev_jump = Engine_.new(data)
	dev_jump.jump_day(2)
	_check(int(dev_jump.s.chapter) == 2 and int(dev_jump.s.t) == dev_jump.T(2, 7, 0), "jump_day(2) 进入第二章起点")
	dev_jump.jump_day(1)
	_check(int(dev_jump.s.chapter) == 1 and not bool(dev_jump.s.chapter_complete), "jump_day(1) 返回未完成的第一章起点")

	print("RESULT fails=", fails)
	quit(1 if fails > 0 else 0)
