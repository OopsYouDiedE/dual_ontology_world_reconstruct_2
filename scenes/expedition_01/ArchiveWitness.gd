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
var paired := false
var note := false
var gaze := Vector3.ZERO
var pose := &""
var overlap := 0.
var recoil_left := 0.
var phase_wait := 0.

func in_window(p:Vector3)->bool:return p.x>21.9 and p.x<27.7 and p.z>=7.29 and p.z<8.88

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
	if beat==Beat.FOLLOW and not lv.learned and in_window(p):
		beat=Beat.WINDOW;lv.trail.clear();route.clear()
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
	match beat:
		Beat.WINDOW:
			if not route.is_empty() and move(lv,route[0],dt):route.remove_at(0)
			if route.is_empty():
				gaze=PLATE-h-Vector3.UP*1.57;face(lv,PLATE,dt)
				pose=&"watch_plate"
			return true
		Beat.WITHDRAW:
			face(lv,p if p.z<8.45 else WINDOW+Vector3.FORWARD,dt,22.);pose=&"ward"
			recoil_left-=dt
			if recoil_left<=0.:beat=Beat.DOOR
			return true
		Beat.DOOR:
			if move(lv,DOOR,dt,5.2):
				pose=&"ward"
				face(lv,Vector3(20.37,0.,7.59),dt)
				if p.z>9.05:beat=Beat.WAIT
				elif p.distance_to(DOOR)<2.60:
					lv.line_once("ward","别进去！板子就在门后。我们得撤回大厅！")
					lv.thought("urgency","回去叫人来不及。总控室只剩这一条路。")
					# One short thought per encounter, even if the player waits at the door.
					beat=Beat.WAIT
			return true
		Beat.WAIT:
			face(lv,Vector3(20.35,0.,7.58),dt)
			pose=&"ward" if p.z<9.05 else &""
			return true
		Beat.PEEK:
			move(lv,JAMB,dt,2.)
			# Peek toward the near bank and listen, not down at the plate.
			face(lv,Vector3(20.70,1.36,10.11),dt);pose=&"peek"
			if lv.learned and (p.x>26.1 or lv.released):
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
	if beat!=Beat.WINDOW or not in_window(lv.walker.position):return
	overlap=overlap+dt if count==2 else 0.
	if overlap<.44:return
	paired=true;beat=Beat.WITHDRAW;recoil_left=.65
	lv.line_once("window","站住！凝视异常板！快移开视线，守则说直视会出事！")
	lv.polish.kick(.14)

func record_lock(lv)->void:
	if note or not paired:return
	note=true;beat=Beat.PEEK
	lv.line_once("evidence","等等……刚才两个人看就暴走了。你一个人盯着，它反而稳了？")
	lv.evidence_thought_delay=.68
	lv.sound_at("ink",lv.walker.position+Vector3.UP,-11.)
	lv.toast("随身手册已新增批注  [1]")
