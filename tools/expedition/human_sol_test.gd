extends SceneTree
const Vision=preload("human_sol_vision.gd")
const Policy=preload("human_sol_policy.gd")
var failures:=0

func _initialize()->void:run.call_deferred()

func check(ok:bool, message:String)->void:
	if not ok:failures+=1;push_error(message)

func wall(z:float)->MeshInstance3D:
	var mesh:=MeshInstance3D.new();mesh.mesh=BoxMesh.new();mesh.position.z=z
	var body:=StaticBody3D.new();mesh.add_child(body)
	var shape:=CollisionShape3D.new();shape.shape=BoxShape3D.new();body.add_child(shape)
	root.add_child(mesh)
	return mesh

func run()->void:
	var eye:=Camera3D.new();root.add_child(eye);eye.current=true
	var near_wall:=wall(-2.)
	wall(-5.)
	await physics_frame
	await physics_frame
	var vision:=Vision.new();var space:=eye.get_world_3d().direct_space_state
	var probe:=Vector3(0,0,-6)
	var front:=vision.hit(eye,space,RID(),probe)
	check(front.has("point") and absf(front.get("point",Vector3.ZERO).z+1.5)<.02,"Near surface must occlude the far one")
	near_wall.hide()
	var far:=vision.hit(eye,space,RID(),probe)
	check(far.has("point") and absf(far.get("point",Vector3.ZERO).z+4.5)<.02,"Hidden collision proxy must not appear as geometry")
	check(vision.hit(eye,space,RID(),Vector3(4,0,-1)).is_empty(),"Offscreen probe")
	check(vision.hit(eye,space,RID(),Vector3(0,0,3)).is_empty(),"Behind camera")
	check(vision.hit(eye,space,RID(),Vector3(0,0,-11)).is_empty(),"Beyond range")
	var body:=CharacterBody3D.new();root.add_child(body)
	var sign:=Label3D.new();sign.text="档案室 / ARCHIVE";sign.pixel_size=.013
	sign.position=Vector3(0.,0.,-4.);root.add_child(sign)
	check(vision.read_labels(eye,body,root).size()==1,"Readable unoccluded sign")
	near_wall.show()
	check(vision.read_labels(eye,body,root).is_empty(),"Occluded sign cannot feed the policy")
	near_wall.hide();sign.hide()
	check(vision.read_labels(eye,body,root).is_empty(),"Hidden sign cannot feed the policy")
	sign.show();sign.position.x=7.
	check(vision.read_labels(eye,body,root).is_empty(),"Off-screen sign cannot feed the policy")
	sign.position=Vector3(0.,0.,-4.);sign.rotation.y=PI;sign.double_sided=false
	check(vision.read_labels(eye,body,root).is_empty(),"One-sided back face cannot feed the policy")
	var delays:=[]
	for id:String in Policy.PROFILES:
		var policy:=Policy.new(id)
		delays.append(policy.profile.delay)
		var frame:={"orders":[],"captions":[],"place":Vector2.ZERO,"prompt":"","lanes":[]}
		check(not policy.decide(frame).get("move",false),"Empty visual field causes sweep rather than blind walk")
		frame.prompt="[E] 晃动铁闸　[Q] 请 Hale 试试"
		check(policy.decide(frame).get("key",0)==KEY_Q,"Gate prompt selects Q")
		frame.prompt="";frame.orders=["原地待命","让 Hale 试闸"]
		check(policy.decide(frame).get("key",0)==KEY_2,"Uses displayed menu index, even if rearranged")
		frame.orders=["去北窗盯桥","原地待命"]
		check(policy.decide(frame).get("key",0)==KEY_1,"Selects the live north-window title")
		frame.orders=["原地待命","听他的建议","去北窗盯桥"]
		check(policy.decide(frame).get("key",0)==KEY_3,"Selects the live north-window title by its reordered index")
		frame.orders=["召回 Hale","原地待命"]
		check(policy.decide(frame).get("key",0)==KEY_Q,"Recall is not a bridge-watch assignment")
	check(delays==[12,16,21],"Three distinct delays in the required range")
	var learner:=Policy.new("curious")
	var trial:={"captions":[],"amber":[Vector2(0,-1),Vector2(0,-4)]}
	check(learner.try_plate(trial,Vector2(0,-.30),0).is_empty(),"Uninstructed agent cannot read a suppressed subtitle")
	trial.captions=["Hold steady two more seconds."];trial.amber=[]
	check(learner.try_plate(trial,Vector2.ZERO,0).is_empty(),"A subtitle alone supplies no location")
	trial.captions=[];trial.amber=[Vector2(0,-1),Vector2(0,-4)]
	var steady:=learner.try_plate(trial,Vector2(0,-.30),0)
	check(steady.get("probe","")=="steady_amber" and steady.hold>=150 and not steady.get("move",false),"Hold gaze before stepping onto plate")
	check(learner.try_plate(trial,Vector2(0,-.30),0).get("move",false),"Resume forward travel after gaze hold")
	var follow:=Policy.new("curious")
	var frame:={"orders":[],"captions":[],"place":Vector2.ZERO,"heading":0.,"prompt":"","walls":{-1: .38},"lanes":[
		{"turn":0.,"depth":2.,"end":Vector2(0.,-2.)},
		{"turn":.24,"depth":2.,"end":Vector2(-.45,-2.)}]}
	var track:=follow.decide(frame)
	check(track.get("probe","")=="wall_track" and track.turn>0.,"Steer away when followed flank is too close")
	frame.lanes.clear()
	var heights:={}
	for i in 12:
		var intent:=follow.decide(frame)
		if String(intent.get("probe","")).begins_with("recover"):
			check(not intent.get("move",false),"Never move into an unsurveyed recovery heading")
			heights[intent.pitch]=true
	check(heights.size()==3,"A stationary stall initiates low/middle/high recovery, even without attempted movement")
	frame.prompt="[E] Interact with a visible control"
	check(follow.decide(frame).get("key",0)==KEY_E,"A prompt sampled during recovery preempts its scan")
	var detour:=Policy.new("direct")
	var encounter:={"orders":[],"captions":[],"place":Vector2.ZERO,"heading":0.,"prompt":"","lanes":[],"signs":[]}
	for distance:float in [0.,1.4,2.8,4.2]:
		encounter.place=Vector2(0.,-distance)
		detour.decide(encounter)
	encounter.captions=["Hale：纹丝不动。档案翼那边还有一扇门，我陪你过去。"]
	var flank:=detour.decide(encounter)
	check(detour.side_hint and detour.rewind_index>=0 and flank.get("probe","")=="inspect_flank" and not flank.get("move",false),"Side-door cue starts a stationary first look on the remembered return trail")
	encounter.captions=[];encounter.signs=[{"text":"ARCHIVE","turn":0.}]
	encounter.lanes=[{"depth":2.,"turn":0.,"end":Vector2(2.,-5.)}]
	check(detour.decide(encounter).get("probe","")=="follow_archive_sign","A currently readable sign can redirect rewind along visible floor")
	var reader:=Policy.new("direct")
	encounter.prompt="[E] 阅读 试验记录"
	check(reader.decide(encounter).get("key",0)==KEY_E,"First reading is actionable")
	encounter.place=Vector2(2.,0.)
	check(reader.decide(encounter).get("key",0)!=KEY_E,"Moving to another cell does not re-read the same prompt")
	var rig:=Skeleton3D.new();root.add_child(rig);rig.position=Vector3(0.,-.65,-4.)
	for i in 17:
		rig.add_bone("sample_%d"%i)
		rig.set_bone_pose_position(i,Vector3(0.,i*.10,0.))
	var jacket:=MeshInstance3D.new();jacket.mesh=BoxMesh.new();jacket.skin=Skin.new()
	rig.add_child(jacket);jacket.skeleton=NodePath("..")
	await physics_frame
	check(vision.people(eye,body,root).size()==1,"A detectable skinned silhouette in view")
	near_wall.show();near_wall.scale=Vector3(2.,3.,1.)
	await physics_frame
	await physics_frame
	check(vision.people(eye,body,root).is_empty(),"Wall occludes multiple figure bands")
	near_wall.hide();rig.position.x=8.
	check(vision.people(eye,body,root).is_empty(),"No off-screen figure")
	rig.position.x=0.;jacket.hide()
	check(vision.people(eye,body,root).is_empty(),"Hidden skin gives no detectable figure")
	var who:=Policy.new("direct")
	var glimpse:={"orders":[],"captions":[],"place":Vector2.ZERO,"heading":0.,"prompt":"","signs":[],
		"people":[{"turn":.16,"range":2.8}],"lanes":[{"turn":.16,"depth":2.25,"end":Vector2(-.36,-2.22)}]}
	check(not String(who.decide(glimpse).get("probe","")).begins_with("companion"),"A visible figure alone is not an invitation")
	glimpse.place=Vector2(0.,-.25)
	glimpse.captions=["Hale：纹丝不动。刚才经过那扇绿门通档案翼，走，回去看看。"]
	var walk:=who.decide(glimpse)
	check(walk.get("probe","")=="companion_follow" and walk.get("move",false),"Explicit invitation prioritizes visible companion over sign/rewind")
	glimpse.captions=[];glimpse.people=[]
	var lost:=who.decide(glimpse)
	check(lost.get("probe","")=="companion_search" and not lost.get("move",false),"Occlusion does not turn last bearing into locomotion")
	glimpse.people=[{"turn":0.,"range":2.8}];glimpse.lanes=[]
	check(not who.decide(glimpse).get("move",false),"A visible figure cannot authorize movement without visible floor")
	if failures==0:print("PASS Human Sol: depth occlusion/frustum/range, sign visibility, wall offset, recovery heights, breadcrumb rewind, prompt memory, visible wheel titles, companion occlusion and pursuit, and 3 profiles")
	quit(0 if failures==0 else 1)
