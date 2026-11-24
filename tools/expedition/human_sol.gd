extends SceneTree
## Standalone Expedition playtest, normal first-person controls only.
const Policy=preload("human_sol_policy.gd")
const Vision=preload("human_sol_vision.gd")
const LEVEL="res://scenes/expedition_01/Expedition.tscn"
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
	events.append(entry)
	print("SOL "+JSON.stringify(entry))

func subtitles()->Array:
	var lines:=[]
	for child in level.captions.get_children():
		if child is Label:
			var line:=text_of(child)
			if not line.is_empty():lines.append(line)
	return lines

func observe()->Dictionary:
	var p:Vector3=level.walker.global_position
	var forward:Vector3=-level.walker.global_basis.z
	var orders:=[]
	if level.wheel.wheel.is_visible_in_tree() and level.wheel.open:
		for option:Dictionary in level.wheel.options:orders.append(String(option.title))
	return {"people":vision.people(level.eye,level.walker,level),"pitch":level.eye.rotation.x,"orders":orders,"captions":subtitles(),"place":Vector2(p.x,p.z),"heading":atan2(-forward.x,-forward.z),"prompt":text_of(level.prompt),
		"signs":vision.read_labels(level.eye,level.walker,level),"walls":vision.flanks(level.eye,level.walker) if exploratory else {},"lanes":vision.sample(level.eye,level.walker,exploratory or close_floor)}

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

func run()->void:
	var profile:="cautious"
	var budget:=7200
	var run_seed:=0
	var seeded:=false
	var output:=""
	var capture:=""
	for arg:String in OS.get_cmdline_user_args():
		if arg.begins_with("--run-seed="):
			var value:=arg.get_slice("=",1)
			if not value.is_valid_int():push_error("Expected integer --run-seed");quit(2);return
			run_seed=int(value);seeded=true
		if arg.begins_with("--profile="):profile=arg.get_slice("=",1)
		if arg.begins_with("--ticks="):budget=int(arg.get_slice("=",1))
		if arg.begins_with("--capture="):capture=arg.trim_prefix("--capture=")
		if arg.begins_with("--output="):output=arg.trim_prefix("--output=")
	if not Policy.PROFILES.has(profile) or budget<300:
		push_error("Expected --profile=cautious|curious|direct and --ticks >= 300");quit(2);return
	var policy:=Policy.new(profile)
	exploratory=profile=="curious"
	var delay:int=policy.profile.delay
	if seeded:seed(run_seed)
	level=load(LEVEL).instantiate();root.add_child(level)
	if not InputMap.has_action(LOOK[0]):
		push_error("Pass --rogue-mcp-dir= after -- to enable the game's normal look actions");quit(2);return
	var next:=235
	var observed_tick:=-1
	var perception:Dictionary={}
	var outcome:="tick_budget"
	var reason:="Exploration budget exhausted before ending card"
	# Observation at physics_frame runs before the level's next physics update.
	for i in budget+1:
		await physics_frame
		tick=i
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
			if "纹丝不动" in line:heard_side_door=true
		last_subtitles=lines
		var failure:=text_of(level.polish.fail_title)
		var ending:=text_of(level.polish.end_card)
		if not failure.is_empty() or not ending.is_empty():
			outcome="failed" if not failure.is_empty() else "completed"
			reason=failure if not failure.is_empty() else ending
			break
		if tick==next-delay-5:
			Input.action_release("move_up");Input.action_release("expedition_quiet")
		if tick==next-delay:
			perception=observe();observed_tick=tick
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
			if not perception.people.is_empty():visible_person_samples+=1
			close_floor=policy.heard_gate
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
				record("input",{"key":OS.get_keycode_string(last_intent.key),"observed_tick":observed_tick,"prompt":perception.prompt,"orders":perception.orders})
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
	await process_frame
	await process_frame
	quit(0 if outcome=="completed" else 1)
