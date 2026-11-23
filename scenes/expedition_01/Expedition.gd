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
var detail_view:=-1
var mode:=-1
const Sound=preload("FeedbackSound.gd")
var demo_grace:=1.
var observers:=-1
var phase:=0.
var stride:=0.
var subtitle:=Label.new()
var sub_time:=0.
var cues:={}
var foot:=AudioStreamPlayer.new()
var chime:=AudioStreamPlayer.new()
var board_audio:=AudioStreamPlayer3D.new()
var sounds:={}
var alarm_time:=0.
var tutorial_room:=false
var hale_speed:=0.
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
	for a in ["expedition_use","expedition_section","expedition_watch","expedition_shell","expedition_detail"]:
		if not InputMap.has_action(a):InputMap.add_action(a)
	Input.mouse_mode=Input.MOUSE_MODE_VISIBLE
	canvas.add_child(subtitle);subtitle.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE);subtitle.offset_top=-94;subtitle.offset_bottom=-28;subtitle.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER;subtitle.vertical_alignment=VERTICAL_ALIGNMENT_CENTER
	var font:=SystemFont.new();font.font_names=PackedStringArray(["Microsoft YaHei UI","Noto Sans CJK SC"])
	for text in [hud,subtitle]:
		text.add_theme_font_override("font",font);text.add_theme_constant_override("outline_size",6);text.mouse_filter=Control.MOUSE_FILTER_IGNORE
	subtitle.add_theme_font_size_override("font_size",22)
	for kind in ["stone","wood","iron","hum","tick","cue"]:sounds[kind]=Sound.make(kind)
	add_child(foot);add_child(chime);add_child(board_audio);foot.volume_db=-13;chime.volume_db=-14;board_audio.position=Vector3(23.85,.4,12.02);board_audio.max_distance=12;board_audio.volume_db=-9
	for mesh in hale.find_children("*","MeshInstance3D",true,false):
		for i in mesh.mesh.get_surface_count():
			if mesh.mesh.surface_get_material(i).resource_name=="Human.male_elegantsuit01":
				var coat:=StandardMaterial3D.new();coat.albedo_color=Color("d5cfc0");coat.roughness=.92;coat.rim_enabled=true;coat.rim=.42;mesh.set_surface_override_material(i,coat)
	for pos in [Vector3(24.65,2.7,8.1),Vector3(23.85,2.4,12),Vector3(36.3,2.4,8.2)]:
		var lamp:=OmniLight3D.new();lamp.position=pos;lamp.omni_range=4.;lamp.light_energy=.85;lamp.light_color=Color("ffebc5");add_child(lamp)
func light_stage()->void:
	var w:=WorldEnvironment.new();var e:=Environment.new();e.background_mode=Environment.BG_COLOR;e.background_color=Color("e3e2d9");e.ambient_light_source=Environment.AMBIENT_SOURCE_COLOR;e.ambient_light_color=Color("c4ccd3");e.ambient_light_energy=.48;e.tonemap_mode=Environment.TONE_MAPPER_ACES;e.tonemap_exposure=.68;e.ssao_enabled=true;e.sdfgi_enabled=true;w.environment=e;add_child(w)
	var sun:=DirectionalLight3D.new();sun.rotation_degrees=Vector3(-48,-33,0);sun.light_energy=.78;sun.shadow_enabled=true;sun.directional_shadow_max_distance=90;add_child(sun)
	for p in [Vector3(6,3.9,0),Vector3(20,4.1,0),Vector3(32,3.9,0),Vector3(24,3,5),Vector3(24,3,12),Vector3(39,3,10),Vector3(61,6,10)]:
		var l:=OmniLight3D.new();l.position=p;l.omni_range=12;l.light_energy=.52;l.light_color=Color("ffe9cb");add_child(l)
func _input(ev:InputEvent)->void:
	if ev is InputEventMouseButton and ev.button_index==MOUSE_BUTTON_LEFT and ev.pressed and mode<0:Input.mouse_mode=Input.MOUSE_MODE_CAPTURED
	if ev is InputEventMouseMotion and mode<0 and Input.mouse_mode==Input.MOUSE_MODE_CAPTURED:
		walker.rotate_y(-ev.relative.x*.0025);eye.rotation.x=clampf(eye.rotation.x-ev.relative.y*.0025,-1.48,1.48)
	var key:=0
	if ev is InputEventKey and ev.pressed and not ev.echo:key=ev.physical_keycode
	if key==KEY_F4 or ev.is_action_pressed("expedition_section"):section_view();return
	if mode>=0:
		if key==KEY_F6 or ev.is_action_pressed("expedition_detail"):detail_camera();return
		if key==KEY_F5 or ev.is_action_pressed("expedition_shell"):shell_closed=not shell_closed;show_shell()
		return
	if key==KEY_ESCAPE:Input.mouse_mode=Input.MOUSE_MODE_VISIBLE
	if key==KEY_E or ev.is_action_pressed("expedition_use"):use()
	if key==KEY_Q or ev.is_action_pressed("expedition_watch"):order()
func section_view()->void:
	detail_view=-1;survey.projection=Camera3D.PROJECTION_ORTHOGONAL
	mode=(mode+2)%4-1
	var gate_room:=kit.get_child(1 if mode==1 else 0)
	if kit.gate.get_parent()!=gate_room:kit.gate.reparent(gate_room,false)
	shell_closed=false;show_shell()
	plinth.visible=mode>=0;review_witness.visible=mode==2;hale.visible=mode in [-1,0]
	plinth.position.y=-10.22 if mode==2 else -.73
	for i in kit.get_child_count():kit.get_child(i).visible=mode<0 or i==mode
	if mode<0:eye.current=true;return
	var target:Vector3=[Vector3(18,1.5,0),Vector3(30,1.4,8),Vector3(61,.1,10.1)][mode];survey.size=[25.,25.,38.][mode];survey.position=target+[Vector3(-33,28,34),Vector3(19,43,32),Vector3(25,33,43)][mode];survey.look_at(target);survey.current=true
# Inspect the teaching sightline at standing eye height inside the complete building.
func detail_camera()->void:
	detail_view=(detail_view+1)%3;shell_closed=true;show_shell()
	for room in kit.get_children():room.show()
	plinth.hide();review_witness.hide();survey.projection=Camera3D.PROJECTION_PERSPECTIVE;survey.fov=eye.fov
	var stations:=[Vector3(24.65,1.57,7.71),Vector3(38.45,1.57,10.42),Vector3(49.4,1.57,10.5)]
	var sights:=[Vector3(23.85,.05,12.02),Vector3(36.3,1.46,7.42),Vector3(61.,.38,10.1)]
	survey.position=stations[detail_view];survey.look_at(sights[detail_view]);survey.current=true
func show_shell()->void:
	for n in kit.cut:n.visible=mode<0 or shell_closed
	for n in kit.plates:n.visible=mode>=0 and not shell_closed
func say(t:String)->void:notice=t;msg_time=4.
func near(p:Vector3,d:=2.1)->bool:return walker.position.distance_to(p)<d
func use()->void:
	if retry>0:return
	if near(Vector3(23.6,0,4.)):
		say("守则：视线可穿过玻璃。只留一人注视。");return
	if near(Vector3(34,0,14.6)) and not taken:taken=true;equipped=true;oil+=35;kit.supplies.hide();say("灯油 +35，已收起节拍器。");return
	if near(Vector3(36.4,0,8.3)):
		if not learned:say("先去测试室观察琥珀板。");return
		released=true;kit.gate.position.y=4.;say("铁栅已开启，已记录折返点。");return
	if near(Vector3(71.8,0,10.1)) and released:collected=true;kit.core.hide();say("已取得源核，登上二层寻找绿色回程门。");return
	if collected and near(kit.leaf.position,3.):walker.position=Vector3(38.7,.1,8.6);trail.clear();hale.position=walker.position+Vector3.RIGHT;say("沿黄铜管返回长廊。");return
	if collected and walker.position.x<2.3:returned.emit();return
	if equipped and walker.position.x>46:equipped=false;distraction=14.;say("节拍器已启动，脚步声将被掩盖 14 秒。");return
	say("靠近装置后按 E。")
func order()->void:
	if posting or holding:posting=false;holding=false;command_path.clear();trail.clear();say("Hale：收到，我跟着你。");return
	if not learned or not near(Vector3(49,0,10),4.):say("观察测试板后，在源井入口按 Q。");return
	posting=true;command_path=kit.stair_path.duplicate();for i in 20:command_path.append(kit.polar(12.45,PI+(PI*.5)*i/19.,4.8));
	say("Hale：我去北侧观察窗。")
func _physics_process(dt:float)->void:
	if mode>=0 and detail_view>=0:hud.text="EYE HEIGHT   /   %s     F6  next sightline    F4  leave"%["B2 · OBSERVATION WINDOW","B5 · MASTER RELEASE","C1 · GAZE SPAN"][detail_view];return
	if mode>=0:hud.text="SECTION PLATE  %s    /    F4  next view   /   F5  shell or cutaway   /   F6  eye height"%["A · IMMERSION ARCADE","B · ARCHIVE WING","C · SOURCE CAISSON"][mode];return
	var p:=walker.position
	var axis:=Input.get_vector("move_left","move_right","move_up","move_down");var dir:=walker.basis*Vector3(axis.x,0,axis.y);var speed:=3.8
	if Input.is_physical_key_pressed(KEY_CTRL):speed=2.2
	if retry>0:
		retry-=dt;if retry<=0:reset_at_checkpoint()
	else:
		var planar:=Vector2(walker.velocity.x,walker.velocity.z).move_toward(Vector2(dir.x,dir.z)*speed,dt*(26. if dir.length_squared()>0 else 32.))
		walker.velocity.x=planar.x;walker.velocity.z=planar.y;walker.velocity.y-=18*dt
		# Low tread risers: lift only on a grounded horizontal obstruction and verify clearance.
		var step:=dir*speed*dt
		if walker.is_on_floor() and step.length_squared()>.00001 and walker.test_move(walker.transform,step) and not walker.test_move(walker.transform,Vector3.UP*.19):
			var up:=walker.transform;up.origin.y+=.19
			if not walker.test_move(up,step):walker.position.y+=.19
		walker.move_and_slide();walking_feedback(dt)
		var prior:=hale.position;advance_hale(dt);animate_hale(prior,dt);rules(dt)
	msg_time-=dt;distraction=maxf(0,distraction-dt)
	sub_time-=dt;subtitle.visible=sub_time>0
	var goal:="沿长廊前进，在铁栅前走右侧门。" if p.z<2.3 else "从档案翼观察窗看向琥珀板。"
	if tutorial_room:goal="去总控室，沿黄铜导管找到拉杆。" if learned else "观察板面，试着移开视线。"
	if released:goal="到源井入口按 Q 派驻 Hale，再渡桥取回源核。"
	if released and holding:goal="Hale 已就位。避开双重注视，按住 Ctrl 静步过桥。"
	if p.x<4 and p.z<2.3 and Input.mouse_mode!=Input.MOUSE_MODE_CAPTURED:goal="单击画面后用 WASD 前进；Esc 释放鼠标。"
	if collected:goal="从绿色回程门折返，到长廊入口按 E 撤离。"
	if near(Vector3(36.4,0,8.3)):goal="E　操作黄铜拉杆"
	if near(Vector3(34,0,14.6)) and not taken:goal="E　收取灯油与节拍器"
	if near(Vector3(71.8,0,10.1)) and not collected:goal="E　取走源核"
	hud.text="首次远征　·　灯油 %d\n%s"%[ceili(oil),notice if msg_time>0 else goal]
func walking_feedback(dt:float)->void:
	var distance:=Vector2(walker.get_position_delta().x,walker.get_position_delta().z).length()
	if walker.is_on_floor() and distance>.001:
		stride+=distance/.88
		if stride>=1.:
			stride=fmod(stride,1.);var kind:="stone"
			for i in walker.get_slide_collision_count():
				var contact:=walker.get_slide_collision(i)
				if contact.get_normal().y<.7:continue
				var surface:=str(contact.get_collider().get_parent().name)
				if "SouthServiceWalk" in surface:kind="iron"
				elif "Plate" in surface or "Span" in surface:kind="wood"
			foot.stream=sounds[kind];foot.play()
		eye.position.y=lerpf(eye.position.y,1.57+.025*sin(TAU*stride),1.-exp(-22.*dt))
	else:eye.position.y=lerpf(eye.position.y,1.57,1.-exp(-16.*dt))
func animate_hale(prior:Vector3,dt:float)->void:
	var d:=hale.position-prior;d.y=0;var speed:=d.length()/dt
	hale_speed=lerpf(hale_speed,speed,1.-exp(-10.*dt))
	var anim:AnimationPlayer=hale.get_meta("animation_player");var clip:=&"walk" if hale_speed>.18 else &"idle"
	if anim.current_animation!=clip:anim.play(clip,.16)
	anim.speed_scale=clampf(hale_speed/2.5,.75,1.7) if clip==&"walk" else 1.
	if speed>.1:hale.rotation.y=lerp_angle(hale.rotation.y,atan2(d.x,d.z),1.-exp(-12.*dt))
func line_once(id:String,text:String)->void:
	if cues.has(id):return
	cues[id]=true;subtitle.text="Hale："+text;sub_time=4.;chime.stream=sounds.cue;chime.play()
func advance_hale(dt:float)->void:
	if posting:
		if command_path.is_empty():posting=false;holding=true;return
		hale.position=hale.position.move_toward(command_path[0],3.8*dt);if hale.position.distance_to(command_path[0])<.04:command_path.remove_at(0)
	elif not holding:
		if last_pos.distance_to(walker.position)>.22:trail.append(walker.position);last_pos=walker.position
		if trail.size()>5:hale.position=hale.position.move_toward(trail[0],4.5*dt);if hale.position.distance_to(trail[0])<.1:trail.remove_at(0)
func rules(dt:float)->void:
	var p:=walker.position
	update_demo(p,dt)
	if tutorial_room and observers==1:learned=true
	if p.x>44 and not released:walker.position=Vector3(39,0,10);say("先拉开黄铜总闸。")
	if p.x<0:walker.position.x=.05
	if p.y < -1.8:fail("坠入源井");return
	var radial:=Vector2(p.x-kit.CX,p.z-kit.CZ)
	var service:=radial.y>2.65 and radial.length()>12.35 and radial.length()<14.25 and absf(p.y)<.35
	if service or (p.z>13.05 and p.z<15.15 and p.x>27.8 and p.x<41.8):oil=maxf(0,oil-dt*(2.5 if service else 1.))
	if service and oil<=0:fail("检修栈桥：灯油耗尽");return
	var on_bridge:=absf(p.x-61)<9 and absf(p.z-10.1)<1.8 and absf(p.y)<.5
	if on_bridge:
		var aim:=-eye.global_basis.z
		var hit:Variant=Plane(Vector3.UP,0).intersects_ray(eye.global_position,aim)
		var looking:=hit!=null and absf(hit.x-61)<9 and absf(hit.z-10.1)<1.8
		var eye_h:=hale.position+Vector3.UP*1.62
		var watching:=(holding or (posting and hale.position.y>=4.7)) and sees_span(eye_h)
		var watchers:=int(watching)+int(looking);hazard=hazard+1 if watchers!=1 else 0
		if hazard==1 or hazard==25:warning.play()
		if hazard>0:notice="红光：两道视线重合" if watchers==2 else "桥面正在失去支撑";msg_time=.2
		var m:=kit.mat("amber");m.emission=Color.RED if hazard>0 else Color("ffc35a")
		if hazard>=(40 if watchers==2 else 60):fail("桥面过载")
	else:hazard=0;kit.mat("amber").emission=Color("ffc35a")
	if on_bridge and walker.velocity.slide(Vector3.UP).length()>2.2 and distraction<=0:
		chase+=dt
		if chase>1.4:notice="下方有脚步声，按住 Ctrl 静步。";msg_time=.3
		if chase>3.6:fail("井底巡行者已抵达桥面")
	else:chase=maxf(0,chase-2*dt)
# Glass transmits gaze; the plate never occludes its own samples.
func board_seen(origin:Vector3,forward:Vector3)->bool:
	for z in [10.6,12.02,13.4]:
		var target:=Vector3(23.85,.11,z);var d:=target-origin
		if d.length()>9. or forward.dot(d.normalized())<.90:continue
		var ray:=PhysicsRayQueryParameters3D.create(origin,target,2,[kit.test_board.get_child(0).get_rid()]);if get_world_3d().direct_space_state.intersect_ray(ray).is_empty():return true
	return false
func update_demo(p:Vector3,dt:float)->void:
	phase+=dt
	var in_b3:=p.x>20 and p.x<27.8 and p.z>9. and p.z<15.1
	if in_b3:tutorial_room=true;line_once("door","坑底两侧都有缓坡。你看板，我来换位。")
	elif p.distance_to(Vector3(24.65,0,7.71))<2.3:line_once("window","看窗后的板。一个人看能托住，两个人看会过载。")
	var count:=int(board_seen(eye.global_position,-eye.global_basis.z))+int(board_seen(hale.position+Vector3.UP*1.57,hale.basis.z))
	var changed:=count!=observers;observers=count
	demo_grace=1. if count else maxf(0.,demo_grace-dt)
	var faded:=count==0 and demo_grace<=0.
	var board:=kit.test_board as MeshInstance3D;var body:=board.get_child(0) as StaticBody3D
	body.collision_layer=0 if faded else 3
	var m:=kit.mat("test_amber");m.transparency=BaseMaterial3D.TRANSPARENCY_ALPHA;m.emission_enabled=true
	var color:Color=[Color("be832d"),Color("d6f4ff"),Color("ff1926")][count];m.shading_mode=BaseMaterial3D.SHADING_MODE_UNSHADED if count==2 else BaseMaterial3D.SHADING_MODE_PER_PIXEL;m.emission=color;m.emission_energy_multiplier=[.22+.16*sin(phase*13.),1.45,.35+.25*sin(phase*42.)][count];color.a=.16 if faded else 1.;m.albedo_color=color
	board.position.y=move_toward(board.position.y,-.55 if faded else .045,dt*1.8);board.position.x=23.85+(.033*sin(phase*65.) if count==2 else 0.)
	if changed:
		board_audio.stop();alarm_time=0.
		if count==1:board_audio.stream=sounds.hum;board_audio.play()
	if count==2:
		alarm_time-=dt
		if alarm_time<=0.:board_audio.stream=sounds.tick;board_audio.play();alarm_time=.16
		if changed and in_b3:line_once("double","红了！移开视线，留一个人看。")
# Three longitudinal × three transverse × three height samples. Glass is on layer 4;
# masonry is on layer 2. Stop as soon as any part of the span is visible.
func sees_span(origin:Vector3)->bool:
	var space:=get_world_3d().direct_space_state
	for x in [-7.,0.,7.]:
		for z in [-1.35,0.,1.35]:
			for h in [.04,.10,.16]:
				var ray:=PhysicsRayQueryParameters3D.create(origin,Vector3(kit.CX+x,h,kit.CZ+z),2)
				if space.intersect_ray(ray).is_empty():return true
	return false
func fail(reason:String)->void:retry=2.6;say(reason+"　·　正在返回折返点…")
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
