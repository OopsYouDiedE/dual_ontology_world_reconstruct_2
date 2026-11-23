extends Node3D
## Lab preview of the production rig; no duplicate mesh, material library or clips.
const Cast=preload("res://scenes/rogue_crossing/ProductionCast.gd")
const ACTIONS: Array[StringName]=[&"idle",&"walk",&"run",&"interact"]
const DURATIONS=[2.4,2.7,1.95,.85]
var action_index:=0
var elapsed:=0.0
var playing_sequence:=true
var base:=Vector3.ZERO
var player:AnimationPlayer
func _ready()->void:
	if Cast.attach(self):player=get_meta("animation_player")
func place(s,level:int,stage:int)->void:
	visible=false
	if stage!=5:return
	var keys=s.layout.cells.keys();keys.sort()
	for k in keys:
		var c=s.address(k)
		if c.z!=level or s.active_cores.has(k) or s.active_cores.has(s.key(c.x,c.y,c.z-1)) or s.kit(k).service_floor:continue
		var center=Vector3((c.x+.5)*s.BAY,s.datum(level)+.012,(c.y+.5)*s.BAY)
		for offset in [Vector3.ZERO,Vector3.LEFT*.9,Vector3.RIGHT*.9]:
			var at:Vector3=center+offset
			if s.host.blocked(AABB(at-Vector3(.36,0,.55),Vector3(.72,1.85,1.1))):continue
			base=at;position=base;rotation.y=.3;visible=true;return
func choose(index:int,sequence:bool)->void:
	action_index=index;elapsed=0.;playing_sequence=sequence
	if player:player.stop();player.play(ACTIONS[index])
func _process(delta:float)->void:
	if not visible or not player:return
	elapsed+=delta
	if elapsed>=DURATIONS[action_index]:choose((action_index+1)%ACTIONS.size() if playing_sequence else action_index,playing_sequence)
