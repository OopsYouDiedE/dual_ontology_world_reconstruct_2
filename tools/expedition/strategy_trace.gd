extends RefCounted
## Observer-only, attached after the playable scene is ready. Never feeds the controller.
const TARGETS := {"":"空处", "gate":"铁闸", "hale":"Hale", "note":"档案残页", "niche_oil":"壁龛油壶", "loot":"灯油", "clock":"节拍器", "clock_locked":"上锁的节拍器柜", "relay":"传声器", "lever":"总闸", "north":"北窗", "core":"备用源核", "return":"应急门", "exit":"气密门", "solo_exit":"应急滑门", "vault_oil":"备用油罐", "stele1":"铁网刻板", "stele2":"灯律刻板", "throw":"投掷节拍器", "maintenance_lift":"检修升闸", "maintenance_oil":"检修油壶"}
const ORDERS := {"north":"北窗盯桥／召回", "try_gate":"请 Hale 试闸", "trail":"跟随", "hold":"原地待命", "advise":"询问 Hale"}
const FLAGS := {"learned":"独自走过试板", "released":"总闸已合上", "collected":"已拔出备用源核", "clock_taken":"已取得节拍器", "taken":"已收起档案翼灯油", "niche_taken":"已提起壁龛油壶", "posting":"Hale 动身去北窗", "holding":"Hale 已在北窗就位", "shortcut_open":"已推开应急门", "shortcut_used":"已进入返回廊", "return_gate_open":"回廊升闸已开", "reunited":"已与 Hale 会合", "exit_open":"已开启气密门", "finished":"已触发撤离结局", "solo_escape":"已使用单人滑门", "demo_locked":"试板已稳定", "crossing_locked":"开始稳定通过试板"}
var lv
var origin:int
var previous:={}
var events:=[]
var player:=[]
var companion:=[]
var active:=true

func start(level)->void:
	lv=level;origin=Engine.get_physics_frames()+1
	lv.audit_action.connect(on_action)
	lv.captions.posted.connect(on_caption)
	lv.get_tree().physics_frame.connect(sample)
	sample()

func now()->int:return maxi(0,Engine.get_physics_frames()-origin)

func mark(kind:String, text:String, at_hale:=false)->void:
	if not active:return
	var p:Vector3=lv.hale.global_position if at_hale else lv.walker.global_position
	events.append({"tick":now(),"event":kind,"value":text,"feet":[p.x,p.y,p.z]})

func on_caption(speaker:String,text:String)->void:
	mark("dialogue",(speaker+"：" if speaker!="" else "心声：")+text)

func on_action(kind:String,detail:String)->void:
	match kind:
		"use":mark("intent","尝试交互："+str(TARGETS.get(detail,detail)))
		"order":mark("intent","下令："+str(ORDERS.get(detail,detail)))
		_:mark(kind,detail)

func watch(id:String,value:Variant,label:String)->void:
	if previous.has(id) and previous[id]!=value and label!="":mark("confirmed",label,id in ["posting","holding"])
	previous[id]=value

func point(target:Array,p:Vector3,t:int)->void:
	var row:=[t,p.x,p.y,p.z]
	if target.is_empty() or target[-1][0]!=t:target.append(row)
	else:target[-1]=row

func sample(force:=false)->void:
	if not active or not is_instance_valid(lv):return
	var t:=now()
	if force or t%12==0:
		point(player,lv.walker.global_position,t);point(companion,lv.hale.global_position,t)
	for id in FLAGS:
		var value:bool=lv.get(id)
		watch(id,value,FLAGS[id] if value else "")
	watch("stance",lv.stance,["改为轻步","改为步行","改为奔跑"][lv.stance])
	watch("lamp",lv.lamp_on,"点亮提灯" if lv.lamp_on else "熄灭提灯")
	watch("manual",lv.manual.visible,"翻开手册" if lv.manual.visible else "收起手册")
	watch("page",lv.book_page,"翻到手册第 %d 页"%(lv.book_page+1))
	watch("wheel",lv.wheel_open,"展开指令轮盘" if lv.wheel_open else "收起指令轮盘")
	watch("throw",lv.distraction>0,"已抛出节拍器" if lv.distraction>0 else "")
	watch("lock",lv.cues.has("gate"),"确认铁闸推不开")
	watch("observers",lv.observers,"试板前的视线数：%d"%lv.observers if lv.observers>=0 else "")
	watch("relay",lv.service_signal.heard,"听清回声" if lv.service_signal.heard else "")
	watch("cabinet",lv.service_signal.open,"节拍器柜已开")
	watch("maint",lv.kit.maintenance.opened,"检修升闸升起")
	watch("maint_oil",lv.kit.maintenance.oil_taken,"已取检修廊灯油")
	watch("plate",lv.contracts.a_state,"板面："+str({"overlap":"两人同时注视","blackout":"熄灭","idle":"恢复空闲"}.get(lv.contracts.a_state,lv.contracts.a_state)))
	watch("calls",lv.contracts.b_calls,"井底呼唤计数：%d"%lv.contracts.b_calls)
	watch("hunter",lv.hunter.state,"井底猎手："+str({"sleep":"休眠","patrol":"巡行","investigate":"循声查探","lure":"转向诱饵","hunt":"追捕"}.get(lv.hunter.state,lv.hunter.state)))
	watch("failed",lv.retry>0,"本次失败："+lv.fail_reason if lv.retry>0 else "重新出发")

func finish(report:Dictionary)->void:
	sample(true);active=false
	if is_instance_valid(lv):lv.get_tree().physics_frame.disconnect(sample)
	report["path_samples"]=player;report["hale_path_samples"]=companion
	var all:Array=report.get("events",[]).duplicate()
	all.append_array(events);all.sort_custom(func(a,b):return a.tick<b.tick)
	report["events"]=all
