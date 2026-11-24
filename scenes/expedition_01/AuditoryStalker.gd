extends Node3D
## Projected hearing works vertically through the open shaft. No sound crosses its exit.
const CENTER:=Vector3(61,-9.9,10.1)
const BAIT:=CENTER+Vector3(5,0,-7)
var state:="sleep"
var angle:=PI
var quiet:=0.
var exposure:=0.
var ticks:=0
var target:=CENTER
var pulse:=MeshInstance3D.new()
var lure:=Node3D.new()
var voice:=AudioStreamPlayer3D.new()
var clock:=AudioStreamPlayer3D.new()
var t:=0.
var bait_played:=false
var bait_answered:=false
var bait_ticks:=0.
var cast_time:=0.
var cast_start:=Vector3.ZERO
var rage_grace:=0.
func finish(color:Color)->StandardMaterial3D:
	var mat:=StandardMaterial3D.new();mat.albedo_color=color;mat.transparency=BaseMaterial3D.TRANSPARENCY_ALPHA;mat.emission_enabled=true;mat.emission=color;mat.emission_energy_multiplier=1.5;return mat
func _ready()->void:
	var figure:=MeshInstance3D.new();var cap:=CapsuleMesh.new();cap.height=2.4;cap.radius=.48;figure.mesh=cap;figure.position.y=1.2;figure.material_override=finish(Color(.68,.016,.025,.82));add_child(figure)
	var ring:=TorusMesh.new();ring.inner_radius=.88;ring.outer_radius=1.;pulse.mesh=ring;pulse.position.y=.08;pulse.material_override=finish(Color(.9,.025,.025,.65));add_child(pulse)
	# A small wooden travel metronome. Spawn it beyond the camera near plane,
	# not at the eye position, to avoid a close-up flash across the viewport.
	var wood:=StandardMaterial3D.new();wood.albedo_color=Color("462c20");wood.roughness=.78
	var brass:=StandardMaterial3D.new();brass.albedo_color=Color("82633e");brass.metallic=.36;brass.roughness=.72
	add_child(lure);lure.top_level=true;lure.hide()
	lure_piece(Vector3(0,.055,0),Vector3(.084,.11,.073),wood)
	lure_piece(Vector3(0,.123,0),Vector3(.054,.032,.063),wood)
	lure_piece(Vector3(0,.073,.039),Vector3(.010,.082,.007),brass)
	lure_piece(Vector3(.019,.069,-.041),Vector3(.029,.021,.022),brass)
	add_child(voice);add_child(clock);clock.top_level=true;clock.global_position=BAIT;voice.max_distance=46;clock.max_distance=42;hide()
func lure_piece(local_pos:Vector3,dim:Vector3,mat:Material)->void:
	var piece:=MeshInstance3D.new();var box:=BoxMesh.new();box.size=dim;piece.mesh=box
	piece.material_override=mat;lure.add_child(piece);piece.position=local_pos
func throw_from(origin:Vector3,forward:=Vector3.FORWARD)->void:
	cast_time=.65;cast_start=origin+forward*.77+forward.cross(Vector3.UP).normalized()*.17-Vector3.UP*.22
	bait_played=false;bait_answered=false;bait_ticks=0.;lure.global_position=cast_start;lure.rotation=Vector3.ZERO;lure.show()
func stop_audio()->void:
	voice.stop();clock.stop()
func wake()->void:
	stop_audio();bait_answered=false;show();state="patrol";angle=PI;position=CENTER+Vector3(-8,0,0);ticks=0;exposure=0;quiet=0;cast_time=0;rage_grace=0.;lure.hide()
func tone(player:AudioStreamPlayer3D,sound:AudioStream,db:float)->void:
	player.stream=sound;player.volume_db=db;player.play()
## Rule hook: heat multiplies exposure gain; direct_exposure adds independent
## rule pressure (e.g., Single-Lamp Rule or solo-bridge acoustic sonar) even
## when the player stands still or stealth-walks.
func probe(pos:Vector3)->void:
	if state=="hunt":return
	target=Vector3(pos.x,CENTER.y,pos.z);state="investigate";quiet=0;exposure=maxf(exposure,.55);ticks=0
func step(dt:float,p:Vector3,noisy:bool,metal:bool,bait:float,rage:bool,sounds:Dictionary,heat:=1.,direct_exposure:=0.,rage_speed:=5.4)->bool:
	t+=dt
	var in_well:=p.x>46
	var floor_pos:=Vector3(p.x,CENTER.y,p.z)
	if bait>0 and not rage:
		cast_time=maxf(0.,cast_time-dt);var fraction:=1.-cast_time/.65
		var fall:=fraction*fraction
		lure.global_position=Vector3(lerpf(cast_start.x,BAIT.x,fraction),lerpf(cast_start.y,BAIT.y+.4,fall)+.52*sin(fraction*PI),lerpf(cast_start.z,BAIT.z,fraction))
		lure.rotation.z=TAU*fraction
		state="lure";ticks=0;exposure=0;quiet=0;lure.show()
		if cast_time<=0.:
			if not bait_played:
				bait_played=true;bait_ticks=.77;voice.stop();tone(clock,sounds.tick,0.)
			bait_ticks-=dt
			if bait_ticks<=0. and not bait_answered:
				bait_answered=true;target=BAIT;tone(voice,sounds.rumble,3.)
	else:
		lure.hide()
		if state=="lure":state="investigate"
		if in_well and (noisy or rage or direct_exposure>0.):
			quiet=0
			if noisy or rage:
				exposure+=dt*heat
			if direct_exposure>0.:
				exposure+=direct_exposure
			target=floor_pos
			if state!="hunt":state="investigate"
			if state!="hunt" and (exposure>=1.45 or (noisy and position.distance_to(target)<3.5)):
				state="hunt";ticks=0;tone(voice,sounds.scream,1)
		elif metal and state!="hunt":
			state="investigate";quiet=0;target=CENTER+Vector3(0,0,-9);exposure=0
		else:
			quiet+=dt;exposure=maxf(0.,exposure-dt*.45)
			if quiet>=4. or not in_well:state="patrol";ticks=0;exposure=0
	if state=="patrol":
		angle+=dt*.25;target=CENTER+Vector3(cos(angle)*8,0,sin(angle)*8);position=position.move_toward(target,2.*dt)
		if in_well and not voice.playing:tone(voice,sounds.breath,-6)
	elif state=="hunt":
		if rage and rage_grace>0.:
			rage_grace=maxf(0.,rage_grace-dt)
		else:
			ticks+=1
			# The upper landing is separated from the well by the gallery floor.
			var reachable:=Vector3(p.x,minf(p.y,2.85) if rage else p.y,p.z)
			position=position.move_toward(reachable,dt*(rage_speed if rage else 12.))
			if ticks>=40 and position.distance_to(p)<1.45:return true
	elif state!="lure" or bait_answered:position=position.move_toward(target,4.6*dt)
	var r:=.5+fmod(t*(2.8 if state=="hunt" else 1.),1.)*2.5;pulse.scale=Vector3(r,.28,r);return false
