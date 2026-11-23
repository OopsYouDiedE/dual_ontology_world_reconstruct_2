extends Node3D
signal returned
const Kit=preload("ExpeditionKit.gd")
const Cast=preload("res://scenes/rogue_crossing/ProductionCast.gd")
var kit:=Kit.new()
var walker:=CharacterBody3D.new()
var eye:=Camera3D.new()
var survey:=Camera3D.new()
var hale:=Node3D.new()
var trail:=PackedVector3Array()
var hud:=Label.new()
var plinth:=MeshInstance3D.new()
var review_witness:=Node3D.new()
var warning:=AudioStreamPlayer3D.new()
var chase:=0.0
var shell_closed:=false
var mode:=-1
var learned:=false
var released:=false
var collected:=false
var equipped:=false
var taken:=false
var posting:=false
var holding:=false
var command_path:=PackedVector3Array()
var oil:=65.0
var distraction:=0.
var hazard:=0
var retry:=0.
var notice:=""
var msg_time:=0.
var last_pos:=Vector3.ZERO
func _ready()->void:
	add_child(kit);kit.build();light_stage();review_props()
	var c:=CollisionShape3D.new();var shape:=CapsuleShape3D.new();shape.radius=.32;shape.height=1.75;c.shape=shape;c.position.y=.875;walker.add_child(c);walker.floor_max_angle=deg_to_rad(60);walker.floor_constant_speed=true;walker.floor_snap_length=.28;add_child(walker);walker.position=Vector3(1,.03,0);walker.rotation.y=-PI/2;walker.add_child(eye);eye.position.y=1.57;eye.fov=73;eye.current=true
	add_child(hale);Cast.attach(hale,1);hale.position=Vector3(.1,0,.7);add_child(survey);survey.far=600;survey.projection=Camera3D.PROJECTION_ORTHOGONAL
	var canvas:=CanvasLayer.new();canvas.layer=8;add_child(canvas);canvas.add_child(hud);hud.position=Vector2(22,17);hud.add_theme_font_size_override("font_size",17);hud.add_theme_constant_override("outline_size",6)
	for a in ["expedition_use","expedition_section","expedition_watch","expedition_shell"]:
		if not InputMap.has_action(a):InputMap.add_action(a)
	Input.mouse_mode=Input.MOUSE_MODE_CAPTURED
func light_stage()->void:
	var w:=WorldEnvironment.new();var e:=Environment.new();e.background_mode=Environment.BG_COLOR;e.background_color=Color("e3e2d9");e.ambient_light_source=Environment.AMBIENT_SOURCE_COLOR;e.ambient_light_color=Color("c4ccd3");e.ambient_light_energy=.48;e.tonemap_mode=Environment.TONE_MAPPER_ACES;e.tonemap_exposure=.68;e.ssao_enabled=true;e.sdfgi_enabled=true;w.environment=e;add_child(w)
	var sun:=DirectionalLight3D.new();sun.rotation_degrees=Vector3(-48,-33,0);sun.light_energy=.78;sun.shadow_enabled=true;sun.directional_shadow_max_distance=90;add_child(sun)
	for p in [Vector3(6,3.9,0),Vector3(20,4.1,0),Vector3(32,3.9,0),Vector3(24,3,5),Vector3(24,3,12),Vector3(39,3,10),Vector3(61,6,10)]:
		var l:=OmniLight3D.new();l.position=p;l.omni_range=12;l.light_energy=.52;l.light_color=Color("ffe9cb");add_child(l)
func _input(ev:InputEvent)->void:
	if ev is InputEventMouseButton and ev.pressed and mode<0:Input.mouse_mode=Input.MOUSE_MODE_CAPTURED
	if ev is InputEventMouseMotion and mode<0 and Input.mouse_mode==Input.MOUSE_MODE_CAPTURED:
		walker.rotate_y(-ev.relative.x*.0025);eye.rotation.x=clampf(eye.rotation.x-ev.relative.y*.0025,-1.48,1.48)
	var key:=0
	if ev is InputEventKey and ev.pressed and not ev.echo:key=ev.physical_keycode
	if key==KEY_F4 or ev.is_action_pressed("expedition_section"):section_view();return
	if mode>=0:
		if key==KEY_F5 or ev.is_action_pressed("expedition_shell"):shell_closed=not shell_closed;show_shell()
		return
	if key==KEY_ESCAPE:Input.mouse_mode=Input.MOUSE_MODE_VISIBLE
	if key==KEY_E or ev.is_action_pressed("expedition_use"):use()
	if key==KEY_Q or ev.is_action_pressed("expedition_watch"):order()
func section_view()->void:
	mode=(mode+2)%4-1
	shell_closed=false;show_shell()
	plinth.visible=mode>=0;review_witness.visible=mode==2;hale.visible=mode in [-1,0]
	plinth.position.y=-10.22 if mode==2 else -.73
	for i in kit.get_child_count():kit.get_child(i).visible=mode<0 or i==mode
	if mode<0:eye.current=true;return
	var target:Vector3=[Vector3(18,1.5,0),Vector3(30,1.4,8),Vector3(61,.1,10.1)][mode];survey.size=[25.,25.,38.][mode];survey.position=target+[Vector3(-33,28,34),Vector3(-26,33,-35),Vector3(25,33,43)][mode];survey.look_at(target);survey.current=true
func show_shell()->void:
	for n in kit.cut:n.visible=mode<0 or shell_closed
	for n in kit.plates:n.visible=mode>=0 and not shell_closed
func say(t:String)->void:notice=t;msg_time=4.
func near(p:Vector3,d:=2.1)->bool:return walker.position.distance_to(p)<d
func use()->void:
	if retry>0:return
	if near(Vector3(23.6,0,4.)):
		say("Field note: Glass transmits a gaze. One observer is enough.");return
	if near(Vector3(34,0,14.6)) and not taken:taken=true;equipped=true;oil+=35;kit.supplies.hide();say("Oil +35   /   Metronome packed");return
	if near(Vector3(36.4,0,8.3)):
		released=true;kit.gate.position.y=4.;say("Master release open. Checkpoint recorded.");return
	if near(Vector3(71.8,0,10.1)) and released:collected=true;kit.core.hide();say("Source secured. Climb to the green return door.");return
	if collected and near(kit.leaf.position,3.):walker.position=Vector3(38.7,.1,8.6);trail.clear();hale.position=walker.position+Vector3.RIGHT;say("Return passage  /  Follow the brass pipe to the arcade.");return
	if collected and walker.position.x<2.3:returned.emit();return
	if equipped and walker.position.x>46:equipped=false;distraction=14.;say("Metronome below: footsteps masked for 14 seconds.");return
	say("Approach the fitting to operate it.")
func order()->void:
	if posting or holding:posting=false;holding=false;command_path.clear();trail.clear();say("Hale: holding at the handover post.");return
	if not learned or not near(Vector3(49,0,10),4.):say("Test the amber board, then post Hale from the entry platform.");return
	posting=true;command_path=kit.stair_path.duplicate();for i in 20:command_path.append(kit.polar(12.45,PI+(PI*.5)*i/19.,4.8));
	say("Hale: taking the north window.")
func _physics_process(dt:float)->void:
	if mode>=0:hud.text="SECTION PLATE  %s    /    F4  next view   /   F5  shell or cutaway"%["A · IMMERSION ARCADE","B · ARCHIVE WING","C · SOURCE CAISSON"][mode];return
	var p:=walker.position
	var axis:=Input.get_vector("move_left","move_right","move_up","move_down");var dir:=walker.basis*Vector3(axis.x,0,axis.y);var speed:=1.45 if p.x<36 and absf(p.z)<2.2 else 3.6
	if Input.is_physical_key_pressed(KEY_CTRL):speed*=.53
	if retry>0:
		retry-=dt;if retry<=0:reset_at_checkpoint()
	else:
		walker.velocity.x=dir.x*speed;walker.velocity.z=dir.z*speed;walker.velocity.y-=18*dt
		# Low tread risers: lift only on a grounded horizontal obstruction and verify clearance.
		var step:=dir*speed*dt
		if walker.is_on_floor() and step.length_squared()>.00001 and walker.test_move(walker.transform,step) and not walker.test_move(walker.transform,Vector3.UP*.19):
			var up:=walker.transform;up.origin.y+=.19
			if not walker.test_move(up,step):walker.position.y+=.19
		walker.move_and_slide();advance_hale(dt);rules(dt)
	msg_time-=dt;distraction=maxf(0,distraction-dt)
	var goal:="Find the side door before the iron gate." if p.x<35 and p.z<2.3 else "Find the amber test board and brass master release."
	if released:goal="Cross the caisson. Recover the source on the east platform."
	if collected:goal="Return to the arcade entrance and press E to extract."
	if near(Vector3(36.4,0,8.3)):goal="E  Operate master release"
	if near(Vector3(34,0,14.6)) and not taken:goal="E  Collect oil and metronome"
	if near(Vector3(71.8,0,10.1)) and not collected:goal="E  Take source core"
	hud.text="FIRST EXPEDITION   /   HALE     •     OIL %d\n%s\nWASD  Walk     Mouse  Look     E  Use     Q  Post Hale     Ctrl  Quiet step     F4  Section plates"%[ceili(oil),notice if msg_time>0 else goal]
func advance_hale(dt:float)->void:
	if posting:
		if command_path.is_empty():posting=false;holding=true;return
		hale.position=hale.position.move_toward(command_path[0],3.8*dt);if hale.position.distance_to(command_path[0])<.04:command_path.remove_at(0)
	elif not holding:
		if last_pos.distance_to(walker.position)>.22:trail.append(walker.position);last_pos=walker.position
		if trail.size()>5:hale.position=hale.position.move_toward(trail[0],4.5*dt);if hale.position.distance_to(trail[0])<.1:trail.remove_at(0)
func rules(dt:float)->void:
	var p:=walker.position
	if near(Vector3(23.85,0,12),1.55) and not learned:learned=true;say("Hale: one observer holds it. My field copy was wrong.")
	if p.x>44 and not released:walker.position=Vector3(39,0,10);say("Release the brass isolator first.")
	if p.x<0:walker.position.x=.05
	if p.y < -1.8:fail("Fall into the caisson");return
	if p.z>13.05 and p.z<15.15 and p.x>27.8 and p.x<41.8 or p.x>47 and p.z>13 and p.y<1:oil=maxf(0,oil-dt)
	var on_bridge:=absf(p.x-61)<9 and absf(p.z-10.1)<1.8 and absf(p.y)<.5
	if on_bridge:
		var aim:=-eye.global_basis.z
		var hit:Variant=Plane(Vector3.UP,0).intersects_ray(eye.global_position,aim)
		var looking:=hit!=null and absf(hit.x-61)<9 and absf(hit.z-10.1)<1.8
		var eye_h:=hale.position+Vector3.UP*1.62
		var sight:=PhysicsRayQueryParameters3D.create(eye_h,Vector3(61,.1,10.1),2)
		var watching:=holding and get_world_3d().direct_space_state.intersect_ray(sight).is_empty()
		var watchers:=int(watching)+int(looking);hazard=hazard+1 if watchers!=1 else 0
		if hazard==1 or hazard==25:warning.play()
		if hazard>0:notice="RED / DOUBLE EXPOSURE" if watchers==2 else "AMBER / BRIDGE LOSING SUPPORT";msg_time=.2
		var m:=kit.mat("amber");m.emission=Color.RED if hazard>0 else Color("ffc35a")
		if hazard>=(40 if watchers==2 else 60):fail("Bridge interlock tripped")
	else:hazard=0;kit.mat("amber").emission=Color("ffc35a")
	if on_bridge and walker.velocity.slide(Vector3.UP).length()>2.2 and distraction<=0:
		chase+=dt
		if chase>1.4:notice="Footsteps below. Hold Ctrl to cross quietly.";msg_time=.3
		if chase>3.6:fail("The listener reached the span")
	else:chase=maxf(0,chase-2*dt)
func fail(reason:String)->void:retry=2.6;say(reason+"   /   Restoring checkpoint…")
func reset_at_checkpoint()->void:
	walker.position=Vector3(38.6,.15,10) if released else Vector3(1,.1,0);walker.velocity=Vector3.ZERO;hale.position=walker.position+Vector3(.1,0,.7);hazard=0;holding=false;posting=false;trail.clear();command_path.clear()
func observation()->Dictionary:return {"phase":"first_expedition","section":mode,"position":str(walker.position),"checkpoint":released,"learned":learned,"core":collected,"hale_posted":holding}

func review_props()->void:
	var ground:=PlaneMesh.new();ground.size=Vector2(400,400);plinth.mesh=ground;var g:=StandardMaterial3D.new();g.albedo_color=Color("a0998e");plinth.material_override=g;add_child(plinth);plinth.hide()
	add_child(review_witness);review_witness.position=kit.polar(12.45,PI*1.5,4.8);Cast.attach(review_witness,1);review_witness.rotation.y=PI
	var cone:=MeshInstance3D.new();var mesh:=CylinderMesh.new();var target:=Vector3(61,.05,10.1);var top:=review_witness.position+Vector3.UP*1.6;mesh.height=top.distance_to(target);mesh.top_radius=.025;mesh.bottom_radius=1.45;cone.mesh=mesh;var m:=StandardMaterial3D.new();m.transparency=BaseMaterial3D.TRANSPARENCY_ALPHA;m.shading_mode=BaseMaterial3D.SHADING_MODE_UNSHADED;m.albedo_color=Color(.18,.75,.77,.27);cone.material_override=m;review_witness.add_child(cone);cone.global_position=(target+top)*.5;cone.global_basis=Basis(Quaternion(Vector3.UP,(top-target).normalized()));review_witness.hide()
	var sound:=AudioStreamWAV.new();sound.mix_rate=16000;sound.format=AudioStreamWAV.FORMAT_16_BITS;var data:=PackedByteArray();data.resize(4800)
	for i in 2400:data.encode_s16(2*i,int(7500*sin(TAU*460*i/16000.)*(1.-i/2400.)))
	sound.data=data;warning.stream=sound;warning.position=Vector3(61,1,10.1);add_child(warning)
