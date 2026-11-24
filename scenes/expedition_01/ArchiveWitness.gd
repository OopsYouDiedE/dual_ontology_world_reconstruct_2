extends RefCounted
## Hale's side of the B2/B3 experiment. No cutscene or camera override:
## the evidence is made from the same unobstructed rays that drive the plate.
enum Beat { FOLLOW, WINDOW, WITHDRAW, DOOR, WAIT, PEEK, CROSS, DONE }
const PLATE := Vector3(23.85,.11,12.02)
const WINDOW := Vector3(23.28,0.,8.42)
const DOOR := Vector3(21.43,0.,8.46)
const JAMB := Vector3(21.18,0.,8.54)
var beat := Beat.FOLLOW
var route := PackedVector3Array()
var facts := preload("ArchiveFacts.gd").new()
var paired: bool:
	get: return facts.has_fact("dual_gaze_b2")
var note: bool:
	get: return facts.allows("comparison")
var gaze := Vector3.ZERO
var pose := &""
var overlap := 0.
var recoil_left := 0.
var phase_wait := 0.
var entered_trial := false

func in_trial(p:Vector3)->bool:
	return p.x>20. and p.x<27.8 and p.z>=9.05 and p.z<15.1

func reset_motion(downstream:bool)->void:
	beat=Beat.DONE if downstream else Beat.FOLLOW
	route.clear();overlap=0.;entered_trial=false;pose=&"";gaze=Vector3.ZERO

func in_window(p:Vector3)->bool:return p.x>21.9 and p.x<27.7 and p.z>=7.29 and p.z<8.88
func in_doorway(p:Vector3)->bool:return p.x>=19.8 and p.x<=22.8 and p.z>=7.2 and p.z<=9.2

func move(lv,point:Vector3,dt:float,speed:=4.8)->bool:
	lv.hale.position=lv.hale.position.move_toward(point,dt*speed)
	return lv.hale.position.distance_to(point)<.025

func face(lv,target:Vector3,dt:float,rate:=15.)->void:
	var d:Vector3=target-lv.hale.position
	if Vector2(d.x,d.z).length()>.035:
		lv.hale.rotation.y=lerp_angle(lv.hale.rotation.y,atan2(d.x,d.z),1.-exp(-rate*dt))

func step(lv,dt:float)->bool:
	var p:Vector3=lv.walker.position
	var h:Vector3=lv.hale.position
	pose=&"";gaze=Vector3.ZERO
	# A hold order freezes the voluntary demonstration as well as following.
	if in_trial(p) and not entered_trial:
		entered_trial=true
		facts.decide("trial_entry",true,"B3 is open; the window trial is optional")
	if lv.hale_hold and beat!=Beat.FOLLOW and beat!=Beat.DONE:return true
	if beat==Beat.FOLLOW and not lv.hale_hold and h.distance_to(p)<18. and (in_window(p) or in_doorway(p) or entered_trial):
		beat=Beat.WINDOW;lv.trail.clear();lv.hale_hold=false;route.clear()
		if h.x>27.72:
			if h.z<2.32:
				route.append(Vector3(31.,0.,0.))
				route.append(Vector3(31.,0.,4.93))
			route.append(Vector3(27.42,0.,4.93))
		if h.z<7.38:
			route.append(Vector3(26.28,0.,5.06 if h.z<5.55 or h.x>27.72 else h.z))
			route.append(Vector3(26.28,0.,8.53))
		elif h.z<8.41 and h.x>WINDOW.x+.2:
			route.append(Vector3(h.x,0.,8.53))
		route.append(WINDOW)
	if beat==Beat.WINDOW and (entered_trial or (p.x<21.9 and p.z>=7.29)):
		# Go around the shelves via the window bank, then stop outside the door.
		if route.is_empty():beat=Beat.DOOR
	if beat in [Beat.DOOR, Beat.WAIT, Beat.PEEK] and in_window(p) and not paired and not lv.hale_hold:
		beat=Beat.WINDOW;entered_trial=false;route=PackedVector3Array([WINDOW])
	if beat in [Beat.WINDOW, Beat.DOOR, Beat.WAIT, Beat.PEEK] and p.z<7.15 and p.x<29.:
		reset_motion(false);lv.trail.clear();return false
	match beat:
		Beat.WINDOW:
			if not route.is_empty() and move(lv,route[0],dt):route.remove_at(0)
			if route.is_empty() and in_window(p) and not entered_trial:
				gaze=PLATE-lv.hale.position-Vector3.UP*1.57;face(lv,PLATE,dt)
				pose=&"watch_plate"
			return true
		Beat.WITHDRAW:
			face(lv,p if p.z<8.45 else WINDOW+Vector3.FORWARD,dt,22.);pose=&"ward"
			recoil_left-=dt
			if recoil_left<=0.:beat=Beat.DOOR
			return true
		Beat.DOOR:
			var at_door:=move(lv,DOOR,dt,5.2)
			if at_door or h.distance_to(DOOR)<1.25:
				pose=&"ward"
				face(lv,Vector3(20.37,0.,7.59),dt)
				if p.distance_to(DOOR)<3.25:
					var prev_id:String=lv.captions.entries.get("Hale",{}).get("id","")
					var can_speak:bool=not lv.captions.entries.has("Hale") or prev_id in ["start","sealed_well","collapse","hale_gate"]
					if not lv.cues.has("ward_paired") and not lv.cues.has("ward_unseen") and can_speak:
						if facts.evaluate("door_paired"):
							lv.line_once("ward_paired","别迈过那道门槛！《守则》写着双人互保，可刚才我们隔着窗同看，板子差点炸裂……你若非要独身试板，我就在门外替你守着退路。")
						else:
							lv.line_once("ward_unseen","里面是琥珀测试室，师兄的抄表记录就断在这里。我不敢违背旧守则贸然进去——我在门边守着，有异动立刻退回来。")
					if lv.cues.has("ward_paired") or lv.cues.has("ward_unseen"):beat=Beat.WAIT
				if entered_trial and (at_door or lv.cues.has("ward_paired") or lv.cues.has("ward_unseen")):beat=Beat.PEEK
			return true
		Beat.WAIT:
			face(lv,Vector3(20.35,0.,7.58),dt)
			pose=&"ward" if p.z<9.05 else &""
			if entered_trial:beat=Beat.PEEK
			return true
		Beat.PEEK:
			move(lv,JAMB,dt,2.)
			# Peek toward the near bank and listen, not down at the plate.
			face(lv,Vector3(20.70,1.36,10.11),dt);pose=&"peek"
			if (p.x>26.1 and p.z>=13.65 or lv.released) and not lv.hale_hold and facts.evaluate("hale_follow"):
				beat=Beat.CROSS;phase_wait=0.
				route=PackedVector3Array([Vector3(20.98,0.,8.53),Vector3(20.98,0.,9.74),Vector3(23.85,0.,9.82),Vector3(23.85,0.,14.11),Vector3(27.26,0.,14.11),Vector3(28.6,0.,14.10)])
			return true
		Beat.CROSS:
			if route.is_empty():
				beat=Beat.DONE;lv.trail.clear()
				# Rejoin the known path, not a diagonal through the archive walls.
				lv.trail.append_array(PackedVector3Array([Vector3(34.,0.,14.10),Vector3(38.8,0.,14.10),Vector3(38.8,0.,10.1)]))
				return true
			if route.size()==3:
				var target:=Vector3(23.85,.11,13.46)
				gaze=target-h-Vector3.UP*1.57;face(lv,target,dt)
				if h.z<10.36:
					phase_wait=phase_wait+dt if lv.observers==1 else 0.
					if phase_wait<.45:pose=&"watch_plate";return true
			if move(lv,route[0],dt,5.25):route.remove_at(0)
			return true
	return false

func compare(lv,count:int,dt:float)->void:
	if beat!=Beat.WINDOW or not in_window(lv.walker.position):
		overlap=0.;return
	overlap=overlap+dt if count==2 else 0.
	if overlap<.44:return
	facts.record("dual_gaze_b2","two unobstructed window rays for 0.44 s")
	lv.line_once("window","糟了——板面翻红了！玻璃挡不住视线，我们俩同时盯着它了！快，谁先看到的谁立刻移开眼！")
	if lv.contracts.a_role==lv.contracts.Seer.HALE:
		beat=Beat.WITHDRAW;recoil_left=.65;lv.polish.kick(.14)

func handoff(lv)->void:
	if beat not in [Beat.WINDOW,Beat.WITHDRAW] or not in_window(lv.walker.position):return
	facts.record("dual_gaze_b2","Contract A verified two unobstructed rays at the window")
	facts.record("handoff_b2","Contract A accepted the first seer's withdrawal")
	update_annotation(lv)
	if beat==Beat.WINDOW:beat=Beat.WITHDRAW;recoil_left=.65

func record_lock(lv)->void:
	facts.record("solo_lock_b3","player-only unobstructed gaze sustained to lock")
	update_annotation(lv)

func update_annotation(lv)->void:
	if not facts.evaluate("comparison") or lv.cues.has("evidence"):return
	lv.cues["evidence"]=true
	lv.evidence_thought_delay=.68
	lv.sound_at("ink",lv.walker.position+Vector3.UP,-11.)
	lv.toast("随身手册已新增批注")

func sees_crossing(lv)->bool:
	if beat!=Beat.PEEK or lv.hale_hold or pose!=&"peek" or gaze!=Vector3.ZERO:return false
	var origin:Vector3=lv.hale.global_position+Vector3.UP*1.57
	var target:Vector3=lv.walker.global_position+Vector3.UP*1.15
	var offset:=target-origin
	# Hale's character forward is +Z. Check his actual yaw after turn limiting,
	# then cast from his eyes to the player, not to the plate.
	if offset.length_squared()>36. or lv.hale.global_basis.z.normalized().dot(offset.normalized())<.64:return false
	var query:=PhysicsRayQueryParameters3D.create(origin,target,2)
	return lv.get_world_3d().direct_space_state.intersect_ray(query).is_empty()

func record_crossing(lv, crossed_in_hale_view:bool)->void:
	facts.record("solo_crossing_b3","player reached the far bank after a locked crossing")
	if crossed_in_hale_view:
		facts.record("hale_saw_crossing_b3","Hale had a clear doorway sightline during the locked crossing")
	if facts.evaluate("hale_comparison"):
		lv.line_once("hale_evidence","……我真不敢相信。在窗边我们俩同看，它几乎当场崩塌；刚才你在里面孤身盯住它，竟稳稳走了过去。旧守则……真的写反了。")
