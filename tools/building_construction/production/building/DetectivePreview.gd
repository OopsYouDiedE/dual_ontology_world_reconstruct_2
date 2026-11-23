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
var partner:AnimationPlayer
var room_index:=0
var sites:Array[Vector3]=[]
const RESPONSES=[&"idle",&"walk",&"run",&"listen",&"listen",&"signal",&"examine"]
func _ready()->void:
	for id in ["detective","Vale"]:
		var person=Node3D.new();person.name=id;add_child(person)
		person.position.x=-.56 if id=="detective" else .56
		person.rotation.y=.65 if id=="detective" else -.65
		if Roster.attach(person,id):
			if id=="detective":player=person.get_meta("animation_player")
			else:partner=person.get_meta("animation_player")
func place(s,level:int,stage:int)->void:
	visible=false;sites.clear()
	if stage!=5:return
	var keys=s.layout.cells.keys();keys.sort()
	for k in keys:
		var c=s.address(k)
		if c.z!=level or s.active_cores.has(k) or s.active_cores.has(s.key(c.x,c.y,c.z-1)):continue
		var at=Vector3((c.x+.5)*s.BAY,s.datum(level)+.012,c.y*s.BAY+.85)
		if s.host.blocked(AABB(at-Vector3(.94,0,.28),Vector3(1.88,1.85,.56))):continue
		sites.append(at)
	if not sites.is_empty():show_room(0)
func show_room(step:int)->void:
	if sites.is_empty():return
	room_index=posmod(room_index+step,sites.size());base=sites[room_index];position=base;visible=true
func choose(index:int,sequence:bool)->void:
	action_index=index;elapsed=0.;playing_sequence=sequence
	if player:player.stop();player.play(ACTIONS[index])
	if partner:partner.stop();partner.play(RESPONSES[index])
func _process(delta:float)->void:
	if not visible or not player:return
	elapsed+=delta
	if elapsed>=DURATIONS[action_index]:choose((action_index+1)%ACTIONS.size() if playing_sequence else action_index,playing_sequence)
