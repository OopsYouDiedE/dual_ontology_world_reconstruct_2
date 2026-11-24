extends SceneTree
## Standalone Expedition playtest, normal first-person controls only.
const Policy=preload("human_sol_policy.gd")
const Vision=preload("human_sol_vision.gd")
const LEVEL="res://scenes/expedition_01/Sortie.tscn"
var level
var vision:=Vision.new()
var tick:=0
var events:=[]
var regions:=[]
var last_prompt:=""
var last_notice:=""
var last_subtitles:=[]
var decisions:=0
var moved:=0.
var newest:=Vector3.INF
var last_progress_tick:=0
var progress_anchor:=Vector3.INF
var seen_gate:=false
var seen_signs:=[]
var heard_side_door:=false
var last_intent:Dictionary={}
var path_samples:=[]
var motor_until:={}
var exploratory:=false
var close_floor:=false
var longest_dwell:=0
var longest_dwell_begin:=0
var longest_dwell_end:=0
var probes:={}
var sampled_heights:={}
var previous_probe:=""
var visible_person_samples:=0
var reading:=""
var read_pages:=[]
var careful_from_manual:=false
var shaft_threat:=false
var escaping:=false
var hint_samples:=0
var hint_reads:=0
var foot_progress_start:=235
const LOOK := ["expedition_look_left","expedition_look_right","expedition_look_up","expedition_look_down"]

func _initialize()->void:run.call_deferred()

func text_of(label:Label)->String:
	if not label.is_visible_in_tree() or not label.get_global_rect().intersects(root.get_visible_rect()):return ""
	var node:CanvasItem=label
	while node!=null:
		if node.modulate.a<.12 or node.self_modulate.a<.12:return ""
		node=node.get_parent() as CanvasItem
	return label.text

func key(code:int)->void:
	for down:bool in [true,false]:
		var event:=InputEventKey.new()
		event.physical_keycode=code;event.pressed=down
		Input.parse_input_event(event)

func record(kind:String,value:Variant)->void:
	var entry:={"tick":tick,"event":kind,"value":value}
	if is_instance_valid(level) and level.is_node_ready() and is_instance_valid(level.walker):
		var feet:Vector3=level.walker.global_position
		entry["feet"]=[feet.x,feet.y,feet.z]
	events.append(entry)
	print("SOL "+JSON.stringify(entry))

func subtitles()->Array:
	var lines:=[]
	for child in level.captions.get_children():
		if child is Label:
			var line:=text_of(child)
			if not line.is_empty():lines.append(line)
	return lines

func use_ring_visible()->bool:
	return level.polish.cross.is_visible_in_tree() and level.polish.ring>.8 and not level.polish.page_reticle

func observe()->Dictionary:
	var p:Vector3=level.walker.global_position
	var forward:Vector3=-level.walker.global_basis.z
	var orders:=[]
	if level.wheel.wheel.is_visible_in_tree() and level.wheel.open:
		for option:Dictionary in level.wheel.options:orders.append(String(option.title))
	return {"amber":vision.amber_marks(level.eye,level.walker,level),"people":vision.people(level.eye,level.walker,level),"pitch":level.eye.rotation.x,"orders":orders,"region":text_of(level.polish.card_title),"oil_warning":level.polish.oil_label.is_visible_in_tree() and level.polish.oil_label.modulate==Color("ff9a80"),"goal":text_of(level.polish.field_note),"captions":subtitles(),"place":Vector2(p.x,p.z),"heading":atan2(-forward.x,-forward.z),"prompt":text_of(level.prompt),
		"signs":vision.read_labels(level.eye,level.walker,level),"walls":vision.flanks(level.eye,level.walker) if exploratory else {},"lanes":vision.sample(level.eye,level.walker,exploratory or close_floor,escaping)}

func motor(action:String, angle:float)->void:
	var frames:=roundi(absf(angle)*Engine.physics_ticks_per_second/1.8)
	if frames>0:
		Input.action_press(action)
		motor_until[action]=tick+frames

func apply(intent:Dictionary)->void:
	for action:String in LOOK:Input.action_release(action)
	motor_until.clear()
	Input.action_release("move_up");Input.action_release("expedition_quiet")
	if intent.has("key"):key(intent.key)
	if intent.has("turn"):
		var turn:float=intent.turn
		var pitch:float=float(intent.pitch)-level.eye.rotation.x
		motor(LOOK[0 if turn>0 else 1],turn)
		motor(LOOK[2 if pitch>0 else 3],pitch)
	if intent.get("move",false):Input.action_press("move_up")
	if intent.get("quiet",false):Input.action_press("expedition_quiet")

func sample_policy(profile:String, run_seed:int)->Dictionary:
	# Local RNG keeps policy sampling independent of scene/audio randomness.
	var rng:=RandomNumberGenerator.new()
	rng.seed=run_seed
	var delay_min:int={"cautious":12,"curious":15,"direct":19}[profile]
	var hold_offset:=rng.randi_range(-3,3)
	return {"hold_offset":hold_offset,"hold":int(Policy.PROFILES[profile].hold)+hold_offset,
		"delay":rng.randi_range(delay_min,delay_min+2),"side":-1. if rng.randi_range(0,1)==0 else 1.}

func run()->void:
	var profile:="cautious"
	var budget:=7200
	var run_seed:=0
	var seeded:=false
	var output:=""
	var capture:=""
	var batch_user_root:=""
	for arg:String in OS.get_cmdline_user_args():
		if arg.begins_with("--run-seed="):
			var value:=arg.get_slice("=",1)
			if not value.is_valid_int():push_error("Expected integer --run-seed");quit(2);return
			run_seed=int(value);seeded=true
		if arg.begins_with("--reading="):reading=arg.get_slice("=",1)
		if arg.begins_with("--profile="):profile=arg.get_slice("=",1)
		if arg.begins_with("--ticks="):budget=int(arg.get_slice("=",1))
		if arg.begins_with("--capture="):capture=arg.trim_prefix("--capture=")
		if arg.begins_with("--output="):output=arg.trim_prefix("--output=")
		if arg.begins_with("--batch-user-root="):batch_user_root=arg.trim_prefix("--batch-user-root=")
	if not Policy.PROFILES.has(profile) or budget<300:
		push_error("Expected --profile=cautious|curious|direct and --ticks >= 300");quit(2);return
	var user_dir:=OS.get_user_data_dir().replace("\\", "/").simplify_path()
	if not batch_user_root.is_empty():
		if DisplayServer.get_name()!="headless" or Engine.physics_ticks_per_second!=60 or not user_dir.begins_with(batch_user_root.simplify_path().trim_suffix("/")+"/"):
			push_error("Batch requires headless 60 Hz and isolated user data; resolved user directory: "+user_dir);quit(2);return
	if not batch_user_root.is_empty() and not seeded:
		push_error("Batch requires --run-seed");quit(2);return
	var variation:=sample_policy(profile,run_seed) if not batch_user_root.is_empty() else {}
	var policy:=Policy.new(profile,variation)
	exploratory=profile=="curious"
	var delay:int=policy.profile.delay
	if seeded:seed(run_seed)
	level=load(LEVEL).instantiate();root.add_child(level)
	var light:=OS.get_cmdline_user_args().has("--strategy-light")
	if light:preload("collision_fixture.gd").apply_lightweight(level)
	var audit_log:=preload("strategy_trace.gd").new();audit_log.start(level)
	if not InputMap.has_action(LOOK[0]):
		push_error("Pass --rogue-mcp-dir= after -- to enable the game's normal look actions");quit(2);return
	var decision_trace:=[]
	var next:=235 if reading.is_empty() else 835
	foot_progress_start=next
	var observed_tick:=-1
	var perception:Dictionary={}
	var outcome:="tick_budget"
	var reason:="Exploration budget exhausted before ending card"
	# Observation at physics_frame runs before the level's next physics update.
	for i in budget+1:
		await physics_frame
		tick=i
		# Equal pre-walk window for all four arms. Use ordinary input and visible page text.
		if reading.begins_with("book-"):
			if tick==5:key(KEY_I)
			if tick in [125,245,365,485]:key(KEY_RIGHT)
			if tick in [120,240,360,480,600] and level.manual.is_visible_in_tree():
				var text:String=level.page.get_parsed_text()
				read_pages.append(text);record("manual_read",text)
				if "脚步声" in text or "footsteps" in text:careful_from_manual=true
			if tick==605:key(KEY_I)
		for action:String in motor_until.keys():
			if tick>=motor_until[action]:Input.action_release(action);motor_until.erase(action)

		var p:Vector3=level.walker.global_position
		if newest.is_finite():moved+=newest.distance_to(p)
		newest=p
		if tick%120==0:path_samples.append([tick,p.x,p.y,p.z])
		var dwell_begin:=maxi(foot_progress_start,last_progress_tick)
		if tick-dwell_begin>longest_dwell:
			longest_dwell=tick-dwell_begin;longest_dwell_begin=dwell_begin;longest_dwell_end=tick
		if not progress_anchor.is_finite() or progress_anchor.distance_to(p)>.65:
			progress_anchor=p;last_progress_tick=tick

		var region:=text_of(level.polish.card_title)
		if not region.is_empty() and region not in regions:
			regions.append(region);record("region_card",region)
			if not reading.ends_with("-skip") and ("源井" in region or "井区" in region or "Caisson" in region):shaft_threat=true
		var prompt:=text_of(level.prompt)
		if not prompt.is_empty() and prompt!=last_prompt:record("prompt",prompt)
		last_prompt=prompt
		if "铁闸" in prompt and "[Q]" in prompt:seen_gate=true
		var notice:=text_of(level.prompt_notice)
		if not notice.is_empty() and notice!=last_notice:record("notice",notice)
		last_notice=notice
		var lines:=subtitles()
		for line:String in lines:
			if line not in last_subtitles:record("caption",line)
			if reading.ends_with("-skip"):continue
			var low:=line.to_lower()
			if "纹丝不动" in line or "拉杆卡死" in line or "拉杆彻底卡死" in line or "推不开" in line or "锁死了" in line or "dead-bolted" in low or "won't budge" in low:heard_side_door=true
			if "动静" in line or "听声" in line or "苏醒" in line or "回声" in line or "脚步声" in line or "just woke" in low or "pacing" in low:shaft_threat=true
			if "拿到了" in line or "源核脱槽" in line or "got the core" in low or "core extracted" in low:escaping=true;shaft_threat=false
		last_subtitles=lines
		var failure:=text_of(level.polish.fail_title)
		var ending:=text_of(level.polish.end_card)
		if not failure.is_empty() or not ending.is_empty():
			outcome="failed" if not failure.is_empty() else "completed"
			reason=failure if not failure.is_empty() else ending
			break
		if tick==next-delay-5 and not last_intent.get("coast",false):
			Input.action_release("move_up");Input.action_release("expedition_quiet")
		if tick==next-delay:
			perception=observe();observed_tick=tick
			if not reading.is_empty():
				var textual:bool=perception.goal!="" or perception.prompt!="" or not perception.signs.is_empty() or not perception.captions.is_empty()
				if textual:hint_samples+=1
				if reading.ends_with("-skip"):
					perception["use_ring"]=use_ring_visible()
					perception.region="";perception.oil_warning=false
					perception.goal="";perception.prompt="";perception.signs=[];perception.captions=[]
				elif textual:hint_reads+=1
			if previous_probe.ends_with("_low") or previous_probe.ends_with("_middle") or previous_probe.ends_with("_high"):
				var height:=previous_probe.get_slice("_",1)
				var band:Dictionary=sampled_heights.get(height,{"samples":0,"prompt_samples":0,"pitch_min":INF,"pitch_max":-INF})
				band.samples+=1
				if not String(perception.prompt).is_empty():band.prompt_samples+=1
				band.pitch_min=minf(band.pitch_min,perception.pitch);band.pitch_max=maxf(band.pitch_max,perception.pitch)
				sampled_heights[height]=band
		if tick==next:
			assert(tick-observed_tick==delay and not perception.is_empty())
			last_intent=policy.decide(perception);decisions+=1
			if last_intent.get("probe","")=="try_visible_ring" and not use_ring_visible():last_intent={"probe":"lost_use_ring"}
			if careful_from_manual and shaft_threat and not escaping and last_intent.get("move",false):last_intent["quiet"]=true
			if escaping and last_intent.get("move",false):last_intent["quiet"]=false
			var motor_text:="轻步前进" if last_intent.get("move",false) and last_intent.get("quiet",false) else "向前走" if last_intent.get("move",false) else "站定"
			var turn_deg:=rad_to_deg(float(last_intent.get("turn",0.)))
			if absf(turn_deg)>=1.:motor_text+="，向%s转 %.0f°"%["左" if turn_deg>0 else "右",absf(turn_deg)]
			if last_intent.has("pitch"):motor_text+="，视线俯仰 %.0f°"%rad_to_deg(float(last_intent.pitch))
			if last_intent.has("key"):motor_text+="，按 "+OS.get_keycode_string(last_intent.key)
			record("decision", "%s（保持 %d 帧）"%[motor_text,int(last_intent.get("hold",policy.profile.hold))])
			if not batch_user_root.is_empty():
				decision_trace.append({"tick":tick,"observed_tick":observed_tick,
					"hold_ticks":int(last_intent.get("hold",policy.profile.hold)),"intent":last_intent.duplicate(true)})
			if not perception.people.is_empty():visible_person_samples+=1
			close_floor=policy.heard_gate or policy.gate_released or policy.core_escape
			previous_probe=last_intent.get("probe","")
			if last_intent.has("probe"):
				var name:String=last_intent.probe
				probes[name]=int(probes.get(name,0))+1
				if name.begins_with("recover") or name.begins_with("companion") or probes[name]==1:
					record("probe",{"kind":name,"people":perception.people if name.begins_with("companion") else [],"pitch":last_intent.get("pitch",0.),"observed_tick":observed_tick,"feet":[p.x,p.y,p.z]})
			for sign:Dictionary in perception.signs:
				if sign.text not in seen_signs:
					seen_signs.append(sign.text);record("read_sign",{"text":sign.text,"observed_tick":observed_tick})
			if last_intent.has("key"):
				record("input",{"key":OS.get_keycode_string(last_intent.key),"observed_tick":observed_tick,"prompt":perception.prompt,"orders":perception.orders,"use_ring":perception.get("use_ring",false)})
			apply(last_intent)
			next+=int(last_intent.get("hold",policy.profile.hold))
	apply({})
	if outcome=="tick_budget":
		if heard_side_door:reason="Budget exhausted after Hale confirmed the gate lock; ending card not reached"
		elif seen_gate:reason="Budget exhausted after seeing the locked-gate interaction prompt"
		if tick-last_progress_tick>600:reason+="; no net displacement above 0.65 m in the last %d ticks"%(tick-last_progress_tick)
	var report:={"profile":profile,"seed":run_seed if seeded else null,"physics_hz":Engine.physics_ticks_per_second,"delay_ticks":delay,"tick":tick,"decisions":decisions,
		"outcome":outcome,"reason":reason,"last_progress_tick":last_progress_tick,"regions":regions,"distance_m":moved,"path_samples":path_samples,
		"feet":[newest.x,newest.y,newest.z],"longest_dwell":[longest_dwell_begin,longest_dwell_end],"probes":probes,"sampled_heights":sampled_heights,"visible_person_samples":visible_person_samples,"events":events}
	if not batch_user_root.is_empty():
		report["user_dir"]=user_dir
		report["policy_parameters"]=policy.profile
		report["decision_trace"]=decision_trace
	if not reading.is_empty():report["reading"]={"arm":reading,"pages":read_pages,"text_samples":hint_samples,"read_samples":hint_reads,"careful_from_manual":careful_from_manual}
	report["fixture"]="light" if light else "full"
	audit_log.finish(report)
	print("SOL_RESULT "+JSON.stringify(report))
	if not output.is_empty():
		var file:=FileAccess.open(output,FileAccess.WRITE)
		if file==null:push_error("Cannot write report: "+output);quit(2);return
		file.store_string(JSON.stringify(report,"\t")+"\n");file.close()
	if not capture.is_empty() and DisplayServer.get_name()!="headless":
		await RenderingServer.frame_post_draw
		var saved:=root.get_texture().get_image().save_png(capture)
		if saved!=OK:push_warning("Cannot save capture: "+capture)
	level.queue_free()
	if DisplayServer.get_name()=="headless":
		# Match WalkTest: unpaced frames can outrun the asynchronous Vorbis mixer.
		for i in 26:
			OS.delay_msec(8)
			await process_frame
	else:
		await process_frame
		await process_frame
	quit(0 if outcome=="completed" else 1)
