extends SceneTree
const S=preload("../production/building/BuildingSolver.gd")
const V=preload("../production/building/BuildingView.gd")
const PLAYER=preload("res://scenes/rogue_player/RoguePlayer.tscn")
var actor
var ticks=0
var max_dy=0.0
var airborne=0
func _initialize()->void:run.call_deferred()
func walk(action:String,axis:int,target:float,sign_:int)->bool:
	Input.action_press(action)
	for i in 240:
		var prev:Vector3=actor.position
		await physics_frame
		ticks+=1;max_dy=maxf(max_dy,absf(actor.position.y-prev.y))
		if not actor.is_on_floor():airborne+=1
		if sign_*(actor.position[axis]-target)>=0:
			Input.action_release(action);return true
	Input.action_release(action);return false
func run()->void:
	var s=S.new();s.build(S.example());var view=V.new();root.add_child(view);view.render(s,-1,false)
	actor=PLAYER.instantiate();actor.first_person=true;actor.spawn_at(Vector3(.99,.01,4.55),0);root.add_child(actor);actor.set_controls_enabled(true)
	for i in 10:await physics_frame
	for leg in [["move_up",2,.68,-1,1.65],["move_right",0,2.29,1,1.65],["move_down",2,4.55,1,3.3]]:
		var reached=await walk(leg[0],leg[1],leg[2],leg[3]);print("U stair leg ",leg[0]," feet=",actor.position," grounded=",actor.is_on_floor()," tick=",ticks)
		if not reached or absf(actor.position.y-leg[4])>.04 or not actor.is_on_floor():quit(1);return
	print("U stair: ticks=",ticks," airborne=",airborne," max |dy|=",max_dy);quit(0 if max_dy<.10 and airborne==0 else 1)
