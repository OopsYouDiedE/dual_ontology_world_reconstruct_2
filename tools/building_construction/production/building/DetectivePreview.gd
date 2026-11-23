extends Node3D
## Lab preview of the production rig; no duplicate mesh, material library or clips.
const Roster=preload("res://scenes/rogue_crossing/Roster.gd")
const ACTIONS: Array[StringName]=[&"idle",&"walk",&"run",&"interact",&"signal",&"examine",&"listen"]
const DURATIONS=[2.4,2.7,1.95,.85,2.,2.,2.]
var action_index:=0
var elapsed:=0.0
var playing_sequence:=true
var base:=Vector3.ZERO
var player:AnimationPlayer
var gestures:Array=[]
var partner:AnimationPlayer
var kinds:Array[int]=[]
var room_index:=0
var sites:Array[Vector3]=[]
const RESPONSES=[&"idle",&"walk",&"run",&"listen",&"listen",&"signal",&"examine"]
func _ready()->void:
	for id in ["detective","Vale"]:
		var person=Node3D.new();person.name=id;add_child(person)
		person.position.x=-.56 if id=="detective" else .56
		person.rotation.y=.65 if id=="detective" else -.65
		if Roster.attach(person,id):
			preload("InquiryClips.gd").install(person)
			preload("res://tools/building_construction/production/building/InvestigationWardrobe.gd").dress(person,id=="Vale")
			var gesture=preload("res://tools/building_construction/production/building/InquiryGesture.gd").new();person.get_meta("skeleton").add_child(gesture);gestures.append(gesture)
			if id=="detective":player=person.get_meta("animation_player")
			else:partner=person.get_meta("animation_player")
func place(s,level:int,stage:int)->void:
	visible=false;sites.clear();kinds.clear()
	if stage!=5:return
	var keys=s.layout.cells.keys();keys.sort()
	for k in keys:
		var c=s.address(k)
		if c.z!=level or s.active_cores.has(k) or s.active_cores.has(s.key(c.x,c.y,c.z-1)):continue
		var at=Vector3((c.x+.5)*s.BAY,s.datum(level)+.012,c.y*s.BAY+.85)
		if s.host.blocked(AABB(at-Vector3(.94,0,.28),Vector3(1.88,1.85,.56))):continue
		sites.append(at);kinds.append(int(s.layout.cells[k]))
	if not sites.is_empty():show_room(0)
func show_room(step:int)->void:
	if sites.is_empty():return
	room_index=posmod(room_index+step,sites.size());base=sites[room_index];position=base;visible=true
	var pump=kinds[room_index]==5
	$detective.position=Vector3(.10,0,.13) if pump else Vector3(-.53,0,.05)
	$Vale.position=Vector3(-.80,0,-.15) if pump else Vector3(.53,0,-.18)
	var target=Vector3(.62,0,.45) # Near end of BayDetails.pump_tray, at z = bay/2 - .8.
	for person in [$detective,$Vale]:
		var aim:Vector3=target-person.position if pump else Vector3(.86 if person==$detective else -.86,0,.50)
		person.rotation.y=atan2(aim.x,aim.z)
func choose(index:int,sequence:bool)->void:
	action_index=index;elapsed=0.;playing_sequence=sequence
	if player:player.stop();player.play(&"kaykit/interact" if index==3 else ACTIONS[index])
	if partner:partner.stop();partner.play(RESPONSES[index])
func _process(delta:float)->void:
	if not visible or not player:return
	elapsed+=delta
	for i in gestures.size():
		gestures[i].motion=ACTIONS[action_index] if i==0 else RESPONSES[action_index];gestures[i].weight=smoothstep(0.,.35,elapsed)*(1.-smoothstep(1.55,2.,elapsed))
	if elapsed>=(player.get_animation(&"kaykit/interact").length if action_index==3 else DURATIONS[action_index]):choose((action_index+1)%ACTIONS.size() if playing_sequence else action_index,playing_sequence)
