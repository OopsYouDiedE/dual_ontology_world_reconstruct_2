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
func run()->void:
	level=preload("Expedition.tscn").instantiate();root.add_child(level)
	await physics_frame;await physics_frame
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
	# 刻板①《同声律》：B4 阁楼
	level.walker.position=Vector3(31.5,.62,16.6)
	level.eye.look_at(level.STELE_A)
	f=level.focus()
	if not demand(f=="stele1","focus stele1 got "+str(f)):return
	level.use()
	if not demand(level.cues.has("stele_sound"),"stele1 unread"):return
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
	if not demand("Shared Footfall" in level.page.text and "One Lamp" in level.page.text,"manual page 5 missing the rules"):return
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
