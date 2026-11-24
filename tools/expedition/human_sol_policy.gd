extends RefCounted
## Pure decision policy: input is one delayed observation, output is a held intent.
const PROFILES := {
	"cautious": {"delay":12, "hold":41, "side":1., "quiet":true, "inertia":.60},
	"curious": {"wall_follow":true,"delay":16, "hold":43, "side":-1., "quiet":false, "inertia":.27},
	"direct": {"delay":21, "hold":48, "side":1., "quiet":false, "inertia":1.15},
}
var profile:Dictionary
var visits:Dictionary = {}
var touched:Dictionary = {}
var scanning:=0
var spin:=1.
var last_cell:=Vector2i(99999,99999)
var previous:=Vector2.INF
var gate_order:=false
var last_move:=false
var drought:=0
var heard_gate:=false
var breadcrumbs:Array[Vector2]=[]
var rewind_index:=-1
var rewind_tries:=0
var confirmed_dead:=Vector2.INF
var side_hint:=false
var examined_text:={}
var door_pressure:=0
var branch_attempts:={}
var scan_index:=0
var route_anchor:=Vector2.INF
var archive_approached:=false
var invitation_used:=false
var follow_budget:=0
var follow_misses:=0
var follow_near:=0
var companion_bearing:=INF
var wall_mode:=false
var survey_left:=0
var wall_steps:=0
var recovery_step:=-1
var recovery_sign:=1.
var recovery_anchor:=Vector2.INF
var no_progress:=0
var blocked_edges:={}
var attempted_edge:=Vector3i.ZERO
var last_tracked_walk:=false
const HEIGHTS := [-.65, -.17, .37]

func _init(id:String, variation:Dictionary={})->void:
	profile=PROFILES[id].duplicate()
	profile.merge(variation,true)
	wall_mode=profile.get("wall_follow",false)
	spin=profile.side

func cell(p:Vector2)->Vector2i:
	return Vector2i((p/.85).round())

func decide(o:Dictionary)->Dictionary:
	var p:Vector2=o.place
	var current:=cell(p)
	var heading:float=o.get("heading",0.)
	if current!=last_cell:
		visits[current]=int(visits.get(current,0))+1
		last_cell=current
	var stuck:=last_move and previous.distance_to(p)<.14
	if last_tracked_walk and stuck:blocked_edges[attempted_edge]=int(blocked_edges.get(attempted_edge,0))+1
	last_tracked_walk=false
	if wall_mode:
		if not recovery_anchor.is_finite() or recovery_anchor.distance_to(p)>.85:
			recovery_anchor=p;no_progress=0
		else:no_progress+=1
	if stuck:drought+=1
	elif last_move:drought=0
	previous=p
	last_move=false
	if not o.orders.is_empty():
		for i in mini(5,o.orders.size()):
			if "试闸" in o.orders[i] or "盯北窗" in o.orders[i] or o.orders[i]=="去北窗盯桥" or "Try gate" in o.orders[i]:
				return {"key":KEY_1+i,"hold":145 if gate_order else 100}
		return {"key":KEY_Q}
	if not heard_gate and (breadcrumbs.is_empty() or breadcrumbs[-1].distance_to(p)>1.10):
		breadcrumbs.append(p)
		if breadcrumbs.size()>80:breadcrumbs.pop_front()
	for caption:String in o.captions:
		var cue:=caption.to_lower()
		if not invitation_used and invites_companion(cue):
			invitation_used=true;follow_budget=13
		if "侧门" in cue or "档案翼" in cue or "旁边有没有路" in cue or "side door" in cue or "archive wing" in cue:
			side_hint=true
		if not heard_gate and ("纹丝不动" in cue or "闸门推不开" in cue or "won't budge" in cue or "拉杆彻底卡死" in cue or "dead-bolted from the inside" in cue):
			heard_gate=true;confirmed_dead=p
			rewind_index=breadcrumbs.size()-1
			route_anchor=p
	var plate:=try_plate(o,p,heading)
	if not plate.is_empty():return plate
	if follow_budget>0:
		var escort:=follow_companion(o,p,heading)
		if not escort.is_empty():return escort
	var prompt:String=o.prompt
	var target:=prompt.split("　")[0]
	var token:=[target,current]
	if "铁闸" in prompt and "[Q]" in prompt and not gate_order:
		gate_order=true
		return {"key":KEY_Q}
	var reading:=("阅读" in prompt or " read " in prompt.to_lower())
	if "[E]" in prompt and "[Q]" not in prompt and not touched.has(token) and not (reading and examined_text.has(target)):
		touched[token]=true
		if reading:examined_text[target]=true
		return {"key":KEY_E,"hold":65}
	if "[Q]" in prompt and "指派" in prompt and not touched.has(token):
		touched[token]=true
		return {"key":KEY_Q}
	if heard_gate and side_hint and not archive_approached:
		var detour:=look_for_side_door(o,p,heading)
		if not detour.is_empty():return detour
	if wall_mode:return follow_wall(o,heading,p)
	var best:Dictionary={}
	var top:=-INF
	for lane:Dictionary in o.lanes:
		var count:=int(visits.get(cell(lane.end),0))
		var score:float=lane.depth*.53 - dead_penalty(p,lane.end) - count*1.75 - absf(lane.turn)*profile.inertia + lane.turn*spin*.09
		if lane.depth<1.25 or int(blocked_edges.get(edge(p,heading+float(lane.turn)),0))>=2 or (stuck and absf(lane.turn)<.23):continue
		if score>top:top=score;best=lane
	if best.is_empty() or drought>=2 or (top<-.35 and scanning<8):
		drought=0
		scanning+=1
		return {"turn":spin*.55,"pitch": (0. if scanning%3==1 else -.42)}
	scanning=0
	return tracked_walk(best,p,heading,"",.45,-.42,profile.hold)

func edge(p:Vector2, heading:float)->Vector3i:
	var c:=cell(p)
	return Vector3i(c.x,c.y,posmod(roundi(heading/TAU*12.),12))

func dead_penalty(p:Vector2, destination:Vector2)->float:
	if not confirmed_dead.is_finite():return 0.
	var remaining:=destination.distance_to(confirmed_dead)
	if remaining<p.distance_to(confirmed_dead)-.25 and remaining<4.5:return 3.5*(1.-remaining/5.)
	return 0.

func tracked_walk(lane:Dictionary,p:Vector2,heading:float,tag:String,limit:float,pitch:float,hold:int)->Dictionary:
	var turn:float=lane.turn
	last_move=absf(turn)<limit
	last_tracked_walk=last_move
	attempted_edge=edge(p,heading+turn)
	var intent:={"turn":turn,"move":last_move,"pitch":pitch,"quiet":profile.quiet,"hold":hold}
	if not tag.is_empty():intent["probe"]=tag
	return intent

func wall_walk(lane:Dictionary,p:Vector2,heading:float,tag:String)->Dictionary:
	var hold:=32 if float(lane.depth)<1. else (40 if float(lane.depth)<1.4 else 48)
	return tracked_walk(lane,p,heading,tag,.39,-.58,hold+int(profile.get("hold_offset",0)))

func follow_wall(o:Dictionary, heading:float, p:Vector2)->Dictionary:
	var flank:float=o.get("walls",{}).get(int(spin),INF)
	var wanted:=0.
	if is_finite(flank):wanted=clampf((flank-.78)*.55,-.38,.40)*spin
	else:wanted=spin*.19
	var found:Dictionary={}
	var top:=-INF
	for lane:Dictionary in o.lanes:
		var turn:float=lane.turn
		var blocked:=int(blocked_edges.get(edge(p,heading+turn),0))
		if blocked>=2 and (recovery_step<24 or blocked>=4):continue
		var score:=minf(lane.depth,3.)*.56-absf(turn-wanted)*1.55
		score-=dead_penalty(p,lane.end)
		score-=minf(4.,float(visits.get(cell(lane.end),0)))*.47+blocked*1.6
		if score>top:top=score;found=lane
	if recovery_step<0 and (no_progress>=7 or (found.is_empty() and no_progress>=4)):
		recovery_step=0;recovery_sign=-recovery_sign;survey_left=0
	if recovery_step>=0:
		# Cover one full turn in half-radian stations. Examine low, eye-level, and high
		# at every station. Attempt only a surveyed, currently supported escape lane.
		if recovery_step>0 and recovery_step%3==1 and not found.is_empty() and absf(found.turn)<.39 and (top>-.25 or recovery_step>=25):
			recovery_step=-1;no_progress=0
			return wall_walk(found,p,heading,"recover_exit")
		if recovery_step>=39:
			# Another pass switches the wall side, without clearing learned collisions.
			spin=-spin;recovery_sign=-recovery_sign;recovery_step=0
		var height:=recovery_step%3
		var turn:=recovery_sign*.49 if height==0 else 0.
		recovery_step+=1
		return {"turn":turn,"pitch":HEIGHTS[height],"hold":48,
			"probe":["recover_low","recover_middle","recover_high"][height]}
	if survey_left>0:
		var index:=3-survey_left
		survey_left-=1
		return {"turn":spin*.32 if index==0 else 0.,"pitch":HEIGHTS[index],"hold":47,
			"probe":["scan_low","scan_middle","scan_high"][index]}
	if not found.is_empty():
		wall_steps+=1
		if wall_steps%9==0:survey_left=3
		return wall_walk(found,p,heading,"wall_track" if is_finite(flank) else "seek_wall")
	return {"turn":spin*.42,"pitch":-.58,"hold":48,"probe":"seek_wall"}

func trail_gap(p:Vector2)->float:
	var gap:=INF
	for prior:Vector2 in breadcrumbs:gap=minf(gap,p.distance_to(prior))
	return gap

func yaw_to(delta:Vector2)->float:
	return atan2(-delta.x,-delta.y)

func look_for_side_door(o:Dictionary,p:Vector2,heading:float)->Dictionary:
	if door_pressure>0 and trail_gap(p)>2.2:
		archive_approached=true
		return {"probe":"leave_trail","hold":profile.hold}
	if rewind_tries>=72:return {}
	rewind_tries+=1
	var pair:=edge(p,heading)
	if door_pressure<7:
		for sign:Dictionary in o.get("signs",[]):
			if not ("档案室" in sign.text or "ARCHIVE" in String(sign.text).to_upper()):continue
			var best:Dictionary={}
			var top:=-INF
			for lane:Dictionary in o.lanes:
				var err:=absf(angle_difference(sign.turn,lane.turn))
				if err>.74 or dead_penalty(p,lane.end)>1.8:continue
				var key:=edge(p,heading+float(lane.turn))
				if int(blocked_edges.get(key,0))>0 or int(branch_attempts.get(key,0))>=2:continue
				var score:=minf(lane.depth,3.6)*.42+minf(trail_gap(lane.end),2.6)*.80-err*.95
				if score>top:top=score;best=lane
			if not best.is_empty():
				var key:=edge(p,heading+float(best.turn))
				branch_attempts[key]=int(branch_attempts.get(key,0))+1
				door_pressure+=1
				return tracked_walk(best,p,heading,"follow_archive_sign",.42,-.35,profile.hold)
			if absf(sign.turn)>.38 and int(branch_attempts.get(pair,0))<1:
				branch_attempts[pair]=1
				return {"turn":clampf(sign.turn,-.85,.85),"pitch":-.40,"hold":62,"probe":"inspect_archive_sign"}
	if route_anchor.distance_to(p)>1.65:
		route_anchor=p;scan_index=0;door_pressure=0
	while rewind_index>=0 and p.distance_to(breadcrumbs[rewind_index])<1.30:rewind_index-=1
	if rewind_index<0:return {}
	var homeward:=yaw_to(breadcrumbs[rewind_index]-p)
	# At each retreat station, inspect both flanks before taking the next familiar step.
	if scan_index<2:
		var side:float=profile.side if scan_index==0 else -float(profile.side)
		scan_index+=1
		return {"turn":angle_difference(heading,homeward+side*.95),"pitch":-.13,"hold":128,"probe":"inspect_flank"}
	var desired:=angle_difference(heading,homeward)
	if absf(desired)>.64:
		return {"turn":desired,"pitch":-.57,"hold":128,"probe":"face_own_trail"}
	var best:Dictionary={}
	var top:=-INF
	for lane:Dictionary in o.lanes:
		var err:=absf(angle_difference(desired,lane.turn))
		if err>.76:continue
		var failures:=int(blocked_edges.get(edge(p,heading+float(lane.turn)),0))
		if failures>=2 or dead_penalty(p,lane.end)>1.8:continue
		var score:=minf(lane.depth,2.85)*.47-err*1.75-failures*1.6
		if score>top:top=score;best=lane
	if not best.is_empty():
		return tracked_walk(best,p,heading,"rewind_own_trail",.44,-.56,profile.hold)
	# Try the preceding breadcrumb rather than repeatedly pushing the same obstacle.
	rewind_index-=1
	return {"turn":0.,"pitch":-.65,"hold":51,"probe":"skip_blocked_trail_step"}

func invites_companion(cue:String)->bool:
	if not (cue.begins_with("hale：") or cue.begins_with("hale:")):return false
	return "跟我走" in cue or "走，回去看看" in cue or "follow me" in cue or "come with me" in cue

func follow_companion(o:Dictionary,p:Vector2,heading:float)->Dictionary:
	follow_budget-=1
	var figure:Dictionary={}
	var best_cost:=INF
	for person:Dictionary in o.get("people",[]):
		var bearing:=heading+float(person.turn)
		var continuity:=absf(angle_difference(companion_bearing,bearing)) if is_finite(companion_bearing) else absf(person.turn)*.4
		var cost:=float(person.range)*.21+continuity
		if cost<best_cost:best_cost=cost;figure=person
	if figure.is_empty():
		follow_misses+=1
		if follow_misses>4:follow_budget=0;return {}
		# Last sighting can direct the next glance, never a step into unseen space.
		var turn:=float(profile.side)*1.42
		if follow_misses==1 and is_finite(companion_bearing):
			var residual:=angle_difference(heading,companion_bearing)
			if absf(residual)>.23:turn=clampf(residual,-1.42,1.42)
		return {"probe":"companion_search","turn":turn,"pitch":-.18,"hold":roundi(absf(turn)/.03)+int(profile.delay)+4}
	follow_misses=0
	var aim:float=figure.turn
	companion_bearing=heading+aim
	if float(figure.range)<1.30:
		follow_near+=1
		if follow_near>=2:follow_budget=0;return {}
		return {"probe":"companion_wait","turn":aim,"pitch":-.15,"hold":51}
	follow_near=0
	var best:Dictionary={}
	var top:=-INF
	for lane:Dictionary in o.lanes:
		var error:=absf(angle_difference(lane.turn,aim))
		if error>.40 or int(blocked_edges.get(edge(p,heading+float(lane.turn)),0))>0:continue
		var score:=minf(lane.depth,float(figure.range))*.32-error*1.6
		if score>top:top=score;best=lane
	if not best.is_empty() and absf(best.turn)<.43:
		var hold:=mini(int(profile.hold),int(profile.delay)+10+roundi(maxf(0.,float(figure.range)-1.05)*15.))
		return tracked_walk(best,p,heading,"companion_follow",.43,-.32,hold)
	if absf(aim)>.18:
		return {"probe":"companion_align","turn":aim,"pitch":-.32,"hold":maxi(48,roundi(absf(aim)/.03)+int(profile.delay)+4)}
	return {"probe":"companion_observe","turn":0.,"pitch":-.50,"hold":43}

# Commit to a crossing using two personally seen surface points and a visible settling subtitle.
var approach:=Vector2.INF
var far_mark:=Vector2.INF
var amber_lesson:=false
var plate_phase:=0
var plate_attempts:=0
var plate_retry:=0
func try_plate(o:Dictionary,p:Vector2,heading:float)->Dictionary:
	if plate_retry>0:
		plate_retry-=1;return {}
	for caption:String in o.captions:
		if "稳住视线两秒" in caption or "hold steady two more seconds" in caption.to_lower():amber_lesson=true
	if plate_phase==0:
		if not amber_lesson:return {}
		var marks:Array=o.get("amber",[])
		if marks.size()!=2:return {}
		var near_mark:Vector2=marks[0] if p.distance_to(marks[0])<p.distance_to(marks[1]) else marks[1]
		far_mark=marks[1] if near_mark==marks[0] else marks[0]
		approach=near_mark+(near_mark-far_mark).normalized()*.70
		plate_phase=1;plate_attempts=0
	plate_attempts+=1
	if plate_attempts>(80 if plate_phase==3 else 28):
		plate_phase=0;plate_retry=12;return {}
	if plate_phase==1 and p.distance_to(approach)<.45:plate_phase=2
	var axis:=approach.direction_to(far_mark)
	var target:=approach if plate_phase==1 else far_mark+axis*.85
	var delta:=target-p
	var turn:=angle_difference(heading,yaw_to(delta))
	if plate_phase==3 and (p-far_mark).dot(axis)>.57:
		plate_phase=0;plate_retry=25;return {}
	if plate_phase==2 and absf(turn)<.13:
		plate_phase=3
		return {"turn":turn,"pitch":-.65,"hold":165,"probe":"steady_amber"}
	var walking:=absf(turn)<.20
	return {"turn":turn,"pitch":-atan2(1.6,maxf(.16,(far_mark-p).dot(axis)-.19)) if plate_phase==3 else -.53,"move":walking,"quiet":walking,"hold":int(profile.delay)+maxi(14,ceili(absf(turn)/.03)+3),"probe":"amber_approach" if plate_phase==1 else "amber_cross"}
