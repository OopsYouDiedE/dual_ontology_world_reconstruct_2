extends SceneTree
## 新动词与规则回归：R 提灯、F 跺脚、Q 跟随/留守、E 交谈、两块规则刻板、独自撤离、独灯律开关。
var level
func _initialize()->void:run.call_deferred()
func demand(ok:bool,msg:String)->bool:
	if not ok:push_error(msg);quit(1)
	return ok
func wait_frames(n:int)->void:
	for i in n:await physics_frame
func _key(code:Key)->InputEventKey:
	var k:=InputEventKey.new();k.physical_keycode=code;k.pressed=true;return k
# The handbook may name its historical clauses. Player dialogue, failure titles,
# contextual prompts and orders must avoid debug labels, future facts and room IDs.
func clean_copy(text:String, context:String)->bool:
	var blocked:=RegEx.new()
	blocked.compile(r"\b[A-C][1-6]\b|契约\s*[AB]|全听见了|它记住你了|每一步都会被追|信任\s*\+|静步成契|只认静止的手|代价：|触发契约|折返点|\b(?:Shift|Ctrl|Space)\b")
	return demand(blocked.search(text)==null,"player copy leaked debug or author text in %s: %s"%[context,text])

func check_dialogue_source()->bool:
	# This complements runtime checks for story lines on branches the verb test
	# deliberately does not play through. Match production call arguments only.
	var authored:=RegEx.new()
	authored.compile("(?:show_line|line_once|thought)\\(\"[^\"]+\",\"([^\"]+)\"")
	for path in ["Expedition.gd","ArchiveWitness.gd"]:
		var source:=FileAccess.get_file_as_string("res://scenes/expedition_01/"+path)
		for hit in authored.search_all(source):
			if not clean_copy(hit.get_string(1),path):return false
	return true

func run()->void:
	level=preload("Expedition.tscn").instantiate();root.add_child(level)
	await physics_frame;await physics_frame
	if not check_dialogue_source():return
	# F3 改变独立图层，保留玩家灯油与准星。
	if not demand(not level.polish.debug_layer.visible and level.polish.panel.visible,"default HUD exposed diagnostics"):return
	if not demand(level.polish.objective_label.text=="取回备用源核" and level.polish.objective_label.text not in level.hud.text,"player and debug objectives should serve separate roles"):return
	level.collected=true;level.polish._hud(0.)
	if not demand(level.polish.objective_label.text=="带源核回锚定厅","player objective did not update after picking up the core"):return
	level.collected=false;level.polish._hud(0.)
	level._input(_key(KEY_F3))
	if not demand(level.polish.debug_layer.visible and level.polish.panel.visible and level.polish.cross.visible,"F3 replaced the player HUD"):return
	level._input(_key(KEY_I));await process_frame
	if not demand(level.manual.visible and level.book_controls.visible and not level.polish.debug_layer.visible,"manual should hide debug behind its own system chrome"):return
	level._input(_key(KEY_I));await process_frame
	if not demand(level.polish.debug_layer.visible and not level.book_controls.visible,"closing the manual should restore F3 state"):return
	level._input(_key(KEY_F3))
	if not demand(not level.polish.debug_layer.visible,"F3 did not hide diagnostics"):return
	# 命令选项展示请求，失败卡只向玩家展示眼前发生的事。
	for item in level.order_options():
		if not demand(not item.has("cost") and not str(item.hint).is_empty(),"wheel option exposed back-end costs"):return
		if not clean_copy(str(item.title)+" "+str(item.hint),"wheel"):return
	var near_hale:Vector3=level.hale.position
	var trust_before:int=level.contracts.trust
	level.hale.position+=Vector3(20,0,0);level.hale_hold=true;level.contracts.trust=2
	level.captions.clear()
	level._input(_key(KEY_Q))
	if not demand(level.wheel_open,"Q did not open the wheel with Hale on hold"):return
	for i in level.wheel.options.size():
		if level.wheel.options[i].id=="advise":level.wheel.index=i
	level._input(_key(KEY_E))
	if not demand(level.hale_hold and not level.captions.entries.has("Hale") and "听不清" in level.notice,"remote advice produced an audible Hale line"):return
	if not clean_copy(level.notice,"remote Q notice"):return
	level.show_line("far_test","你听得见吗？")
	if not demand(not level.captions.entries.has("Hale"),"remote hold played an ambient Hale line"):return
	level.hale.position=near_hale;level.hale_hold=false;level.contracts.trust=trust_before
	level.show_line("near_test","我在这儿。")
	if not demand(level.captions.entries.has("Hale"),"nearby Hale captions were suppressed too"):return
	if not clean_copy(level.captions.entries["Hale"].label.text,"nearby caption"):return
	level.captions.clear()
	level.set_physics_process(false)
	level.fail("桥面过载")
	if not demand(level.polish.fail_title.text=="桥面塌了" and not level.polish.fail_body.visible,"player failure card exposed rule diagnostics"):return
	if not clean_copy(level.polish.fail_title.text,"failure title"):return
	level.retry=0.;level.fail_reason="";level.polish.fail_time=0.;level.polish.reset_beat()
	level.set_physics_process(true)
	# R 提灯开关
	var lamp:bool=level.lamp_on
	level._input(_key(KEY_R))
	if not demand(level.lamp_on==not lamp,"R did not toggle the lantern"):return
	level._input(_key(KEY_R))
	if not demand(level.lamp_on==lamp,"R did not restore the lantern"):return
	# F 跺脚：冷却生效 + 猎手被引动；冷却中不能再跺（先下井）
	level.released=true;level.hunter.wake()
	level.walker.position=Vector3(52,.1,10.1);level.hale.position=Vector3(53.4,0,10.1)
	await physics_frame
	level._input(_key(KEY_F))
	if not demand(level.stomp_cool>5.,"stomp cooldown missing"):return
	if not demand(level.hunter.state=="investigate","stomp did not pull the hunter"):return
	level.stomp_cool=3.
	level._input(_key(KEY_F))
	if not demand(level.stomp_cool<4.,"stomp ignored its cooldown"):return
	# 独灯律判定钩子：井内双灯亮 → both_lamp；熄灯 → 合规
	level.lamp_on=true
	await physics_frame;await physics_frame
	if not demand(level.both_lamp,"独灯律: dual lamps not detected in the shaft"):return
	level.hale.position=Vector3(35,0,10);await physics_frame;await physics_frame
	if not demand(not level.both_lamp,"a lamp outside the shaft counted against the player"):return
	level.hale.position=Vector3(53.4,0,10.1)
	level.lamp_on=false
	await physics_frame
	if not demand(not level.both_lamp,"独灯律: dousing one lamp should comply"):return
	level.lamp_on=true
	# Q 跟随/留守：准星对 Hale 切换
	level.walker.position=Vector3(1,.1,0);level.hale.position=Vector3(3.2,0,0)
	level.eye.look_at(level.hale.position+Vector3.UP*1.25)
	var f:String=level.focus()
	if not demand(f=="hale","focus should be hale, got "+f):return
	level.order()
	if not demand(level.hale_hold,"Q did not order Hale to stay"):return
	level.eye.look_at(level.hale.position+Vector3.UP*1.25)
	level.order()
	if not demand(not level.hale_hold,"Q did not resume follow"):return
	# E 交谈：情境台词池
	level.eye.look_at(level.hale.position+Vector3.UP*1.25)
	level.use()
	if not demand(level.cues.has("talk_rules") or level.cues.has("talk_idle"),"talk produced no line"):return
	# Shift log 渲染为中文；现场批注与刻文都要等亲历后才出现。
	level.render_book()
	if not demand("井区值班日志" in level.page.text and "Shift log" not in level.page.text and "手写批注" not in level.page.text,"initial Shift log leaked language or field evidence"):return
	if not demand("Shift" not in level.page.text and "Shift" in level.book_controls.text,"keys belong to system chrome"):return
	level.book_page=4;level.render_book()
	if not demand("留页待抄" in level.page.text and "同声律" not in level.page.text and "独灯律" not in level.page.text,"initial page 5 exposed unread inscriptions"):return
	# 残页通过真实焦点/互动进入字幕，保留记录者实际目击的内容。
	level.walker.position=Vector3(23.6,.1,2.7)
	level.eye.look_at(Vector3(23.6,1.03,4))
	if not demand(level.focus()=="note","archive fragment not in focus"):return
	level.use()
	if not demand(level.captions.entries.has("残页"),"archive fragment missing from player captions"):return
	var fragment:String=level.captions.entries["残页"].label.text
	if not demand("玻璃外那块板" in fragment and not level.archive.note,"archive fragment should report the witnessed ripple without unlocking the comparison"):return
	if not clean_copy(fragment,"archive fragment"):return
	# 刻板①《同声律》：B4 阁楼
	level.walker.position=Vector3(31.5,.62,16.6)
	level.eye.look_at(level.STELE_A)
	f=level.focus()
	if not demand(f=="stele1","focus stele1 got "+str(f)):return
	level.use()
	if not demand(level.cues.has("stele_sound"),"stele1 unread"):return
	level.render_book()
	if not demand("同声律" in level.page.text and "独灯律" not in level.page.text and "均已核对" not in level.page.text,"page 5 exposed the unread second inscription"):return
	# 刻板②《独灯律》：回廊阀室
	level.walker.position=Vector3(52.3,1.14,23.6)
	level.eye.look_at(level.STELE_B)
	f=level.focus()
	if not demand(f=="stele2","focus stele2 got "+str(f)):return
	level.use()
	if not demand(level.cues.has("stele_light"),"stele2 unread"):return
	if not demand(level.cues.has("stele_sound"),"stele2 should complete the pair"):return
	level.oil=45.;level.eye.look_at(level.kit.vault_can.global_position)
	if not demand(level.focus()=="vault_oil","reserve oil unreachable"):return
	level.use()
	if not demand(level.oil==65. and level.focus()!="vault_oil","reserve oil must pay once"):return
	# 手册第 5 页收录两份规则
	level.book_page=4;level.render_book()
	if not demand("同声律" in level.page.text and "独灯律" in level.page.text and "两处刻文均已核对" in level.page.get_parsed_text(),"manual page 5 missing the rules"):return
	# 独自撤离：应急滑门双出口
	level.exit_open=true;level.collected=true
	level.walker.position=Vector3(-1.2,.1,.2)
	level.eye.look_at(level.SOLO_HATCH)
	f=level.focus()
	if not demand(f=="solo_exit","focus solo got "+str(f)):return
	var got:=[false]
	level.returned.connect(func():got[0]=true)
	level.use()
	for i in 900:
		await physics_frame
		if got[0]:break
	if not demand(got[0] and level.finished and level.solo_escape,"solo exit did not finish the expedition"):return
	print("PASS: lamp / stomp / heat-rules / hold-follow / talk / steles / manual p5 / solo exit")
	level.queue_free()
	for tick in 26:
		OS.delay_msec(8)
		await process_frame
	quit(0)
