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
var hunter:=preload("AuditoryStalker.gd").new()
var manual:=PanelContainer.new()
var page:=Label.new()
var prompt:=Label.new()
var read_book:=false
var running:=false
var subtitle_id:=""
var next_thought:=false
var crossing:=false
var backed_off:=false
var checkpoint_oil:=65.
var checkpoint_item:=false
var metal_foot:=AudioStreamPlayer3D.new()
var metal_beat:=0.
var emergency:=OmniLight3D.new()
var siren:=AudioStreamPlayer.new()
var halo:=OmniLight3D.new()
var finished:=false
var practice_note:=false
var shell_closed:=false
var detail_view:=-1
var mode:=-1
const Sound=preload("FeedbackSound.gd")
const Polish=preload("ExpeditionPolish.gd")
var polish:=Polish.new()
var look_sens:=.0022
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
var gate_rattle:Tween
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
	for a in ["expedition_quiet","expedition_use","expedition_section","expedition_watch","expedition_shell","expedition_detail"]:
		if not InputMap.has_action(a):InputMap.add_action(a)
	Input.mouse_mode=Input.MOUSE_MODE_VISIBLE
	canvas.add_child(subtitle);subtitle.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE);subtitle.offset_top=-94;subtitle.offset_bottom=-28;subtitle.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER;subtitle.vertical_alignment=VERTICAL_ALIGNMENT_CENTER
	var font:=Polish.make_font()
	for text in [hud,subtitle]:
		text.add_theme_font_override("font",font);text.add_theme_constant_override("outline_size",6);text.mouse_filter=Control.MOUSE_FILTER_IGNORE
	subtitle.add_theme_font_size_override("font_size",22)
	for kind in ["stone","wood","iron","hum","tick","cue","bell","slam","scream","breath","alarm"]:sounds[kind]=Sound.make(kind)
	add_child(foot);add_child(chime);add_child(board_audio);foot.volume_db=-21;chime.volume_db=-14;board_audio.position=Vector3(23.85,.4,12.02);board_audio.max_distance=12;board_audio.volume_db=-9
	for mesh in hale.find_children("*","MeshInstance3D",true,false):
		for i in mesh.mesh.get_surface_count():
			if mesh.mesh.surface_get_material(i).resource_name=="Human.male_elegantsuit01":
				var coat:=StandardMaterial3D.new();coat.albedo_color=Color("d5cfc0");coat.roughness=.92;coat.rim_enabled=true;coat.rim=.42;mesh.set_surface_override_material(i,coat)
	for pos in [Vector3(23.6,2.1,4.),Vector3(24.65,2.7,8.1),Vector3(23.85,2.4,12),Vector3(36.3,2.4,8.2)]:
		var lamp:=OmniLight3D.new();lamp.position=pos;lamp.omni_range=4.;lamp.light_energy=.85;lamp.light_color=Color("ffebc5");lamp.omni_attenuation=1.3;lamp.shadow_enabled=pos.z>=11.9 and pos.x<30;add_child(lamp)
	add_child(hunter);hale.add_child(metal_foot);metal_foot.stream=sounds.iron;metal_foot.volume_db=-12;add_child(siren)
	add_child(halo);halo.position=Vector3(31,2.1,2.9);halo.light_color=Color("ffbd70");halo.omni_range=6;halo.light_energy=1.4;halo.shadow_enabled=true
	add_child(emergency);emergency.position=Vector3(71,3.2,10);emergency.light_color=Color.RED;emergency.omni_range=17;emergency.hide()
	canvas.add_child(prompt);prompt.set_anchors_and_offsets_preset(Control.PRESET_CENTER);prompt.offset_left=-320;prompt.offset_right=320;prompt.offset_top=-10;prompt.offset_bottom=76;prompt.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER;prompt.add_theme_font_override("font",font);prompt.add_theme_constant_override("outline_size",6);prompt.mouse_filter=Control.MOUSE_FILTER_IGNORE
	canvas.add_child(manual);manual.set_anchors_and_offsets_preset(Control.PRESET_CENTER);manual.offset_left=-267;manual.offset_right=267;manual.offset_top=-155;manual.offset_bottom=155
	var paper:=StyleBoxFlat.new();paper.bg_color=Color("282a25");paper.border_color=Color("ac9568");paper.set_border_width_all(2);paper.content_margin_left=32;paper.content_margin_right=32;manual.add_theme_stylebox_override("panel",paper);manual.add_child(page);page.vertical_alignment=VERTICAL_ALIGNMENT_CENTER;page.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART;page.add_theme_font_override("font",font);page.add_theme_font_size_override("font_size",19);manual.hide()
	add_child(polish);polish.setup(self,canvas)
func toggle_book()->void:
	manual.visible=not manual.visible;read_book=true
	page.text="远征员随身规则手册　／　01\n━━━━━━━━━━━━━━━━━━━━\n井区交班记录：异常板遇到目光时会改变。玻璃后的目击也须登记。\n\n值守须知：铁网上的响动会传到井底。\n\nShift　切换走／跑　　 Ctrl　按住静步\nE　互动　　Q　指派 Hale　　[ ]　调整视角灵敏度\n1　合上手册"
	if learned:page.text=page.text.replace("异常板遇到目光时会改变。玻璃后的目击也须登记。","我的实测：独自注视时，板面承住了我。Hale 记得的条文却禁止直视。")
	prompt.visible=not manual.visible;subtitle.visible=not manual.visible and sub_time>0;polish.on_book(manual.visible)
func sound_at(kind:String,pos:Vector3,db:float)->void:
	var audio:=AudioStreamPlayer3D.new();add_child(audio);audio.position=pos;audio.stream=sounds[kind];audio.volume_db=db;audio.max_distance=90;audio.finished.connect(audio.queue_free);audio.play()
func light_stage()->void:
	var w:=WorldEnvironment.new();var e:=Environment.new()
	e.background_mode=Environment.BG_COLOR;e.background_color=Color("e3e2d9")
	e.ambient_light_source=Environment.AMBIENT_SOURCE_COLOR;e.ambient_light_color=Color("c9d0d8");e.ambient_light_energy=.55
	# Tone: ACES kept for contrast, exposure lifted from .68 so the vaults read without washing the walls out.
	e.tonemap_mode=Environment.TONE_MAPPER_ACES;e.tonemap_exposure=.84;e.tonemap_white=6.
	e.adjustment_enabled=true;e.adjustment_contrast=1.1;e.adjustment_saturation=1.0
	# Contact shading + one-bounce GI. SDFGI is trimmed to 3 cascades (the level is ~75 m long).
	e.ssao_enabled=true;e.ssao_radius=1.3;e.ssao_intensity=2.2;e.ssao_power=1.6;e.ssao_detail=.6;e.ssao_light_affect=.25
	e.sdfgi_enabled=true;e.sdfgi_cascades=3;e.sdfgi_min_cell_size=.3;e.sdfgi_use_occlusion=true;e.sdfgi_bounce_feedback=.45;e.sdfgi_energy=.9;e.sdfgi_y_scale=Environment.SDFGI_Y_SCALE_75_PERCENT
	# Soft bloom for lamps, emissive boards and the alarm; thin aerial fog for depth down the long arcade.
	e.glow_enabled=true;e.glow_intensity=.3;e.glow_strength=.85;e.glow_bloom=.02;e.glow_hdr_threshold=1.3;e.glow_blend_mode=Environment.GLOW_BLEND_MODE_SOFTLIGHT
	e.fog_enabled=true;e.fog_light_color=Color("e7e0d0");e.fog_density=.0028;e.fog_aerial_perspective=.2;e.fog_sky_affect=0.
	w.environment=e;add_child(w)
	var sun:=DirectionalLight3D.new();sun.rotation_degrees=Vector3(-48,-33,0);sun.light_energy=.8;sun.light_color=Color("fff1dc");sun.shadow_enabled=true
	sun.directional_shadow_max_distance=64;sun.directional_shadow_mode=DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS;sun.directional_shadow_blend_splits=true
	sun.shadow_bias=.04;sun.shadow_normal_bias=1.4;sun.light_angular_distance=.45;add_child(sun)
	for p in [Vector3(6,3.9,0),Vector3(20,4.1,0),Vector3(32,3.9,0),Vector3(24,3,5),Vector3(24,3,12),Vector3(39,3,10),Vector3(61,6,10)]:
		var l:=OmniLight3D.new();l.position=p;l.omni_range=12;l.light_energy=.52;l.light_color=Color("ffe9cb");l.omni_attenuation=1.25;add_child(l)
	# Extra fills: arcade bays that were left murky, and a cold under-light that makes the shaft floor readable.
	for x in [13.,26.]:
		var f:=OmniLight3D.new();f.position=Vector3(x,3.2,0);f.omni_range=9;f.light_energy=.38;f.light_color=Color("ffdcae");f.omni_attenuation=1.4;add_child(f)
	var well:=OmniLight3D.new();well.position=Vector3(61,-8.2,10.1);well.omni_range=16;well.light_energy=.7;well.light_color=Color("8fc4d8");well.omni_attenuation=1.2;add_child(well)
func _input(ev:InputEvent)->void:
	if finished:return
	if ev is InputEventKey and ev.pressed and not ev.echo and mode<0:
		if ev.physical_keycode in [KEY_1,KEY_KP_1]:toggle_book();return
		if ev.physical_keycode==KEY_SHIFT and not manual.visible:running=not running;return
	if manual.visible:return
	if ev is InputEventMouseButton and ev.button_index==MOUSE_BUTTON_LEFT and ev.pressed and mode<0:Input.mouse_mode=Input.MOUSE_MODE_CAPTURED
	if ev is InputEventMouseMotion and mode<0 and Input.mouse_mode==Input.MOUSE_MODE_CAPTURED:
		walker.rotate_y(-ev.relative.x*look_sens);eye.rotation.x=clampf(eye.rotation.x-ev.relative.y*look_sens,-1.48,1.48)
	var key:=0
	if ev is InputEventKey and ev.pressed and not ev.echo:key=ev.physical_keycode
	if key==KEY_F4 or ev.is_action_pressed("expedition_section"):section_view();return
	if mode>=0:
		if key==KEY_F6 or ev.is_action_pressed("expedition_detail"):detail_camera();return
		if key==KEY_F5 or ev.is_action_pressed("expedition_shell"):shell_closed=not shell_closed;show_shell()
		return
	if key==KEY_BRACKETLEFT or key==KEY_BRACKETRIGHT:
		look_sens=clampf(look_sens*(1.12 if key==KEY_BRACKETRIGHT else 1./1.12),.0008,.006);say("视角灵敏度 %d%%"%roundi(look_sens/.0022*100.));return
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
	plinth.hide();review_witness.hide();survey.projection=Camera3D.PROJECTION_PERSPECTIVE;survey.fov=Polish.BASE_FOV
	var stations:=[Vector3(24.65,1.57,7.71),Vector3(38.45,1.57,10.42),Vector3(49.4,1.57,10.5)]
	var sights:=[Vector3(23.85,.05,12.02),Vector3(36.3,1.46,7.42),Vector3(61.,.38,10.1)]
	survey.position=stations[detail_view];survey.look_at(sights[detail_view]);survey.current=true
func show_shell()->void:
	for n in kit.cut:n.visible=mode<0 or shell_closed
	for n in kit.plates:n.visible=mode>=0 and not shell_closed
func say(t:String)->void:notice=t;msg_time=4.
func near(p:Vector3,d:=2.1)->bool:return walker.position.distance_to(p)<d
func aimed(pos:Vector3,reach:float,cone:=.96)->bool:
	var delta:=pos-eye.global_position
	if delta.length()>reach or (-eye.global_basis.z).dot(delta.normalized())<cone:return false
	var hit:=get_world_3d().direct_space_state.intersect_ray(PhysicsRayQueryParameters3D.create(eye.global_position,pos,2))
	return hit.is_empty() or Vector3(hit.position).distance_to(pos)<.65
func focus()->String:
	if not released and walker.position.x<35.9 and aimed(Vector3(36.,1.57,0),2.,.91):return "gate"
	if not taken and aimed(Vector3(34.14,.5,14.67),2.8):return "loot"
	if aimed(Vector3(23.6,1.03,4),2.8):return "note"
	if not released and aimed(Vector3(36.3,1.35,7.72),3.):return "lever"
	if released and not collected and aimed(kit.core.position,2.8):return "core"
	if collected and aimed(kit.leaf.position,3.5):return "return"
	if collected and aimed(Vector3(.16,1.5,0),3.):return "exit"
	if learned and released and near(Vector3(49,0,10),4.5) and aimed(kit.polar(12.45,1.5*PI,6.42),24,.976):return "north"
	if equipped and walker.position.x>46:
		var landing:Variant=Plane(Vector3.UP,hunter.CENTER.y).intersects_ray(eye.global_position,-eye.global_basis.z)
		if landing!=null and landing.distance_to(hunter.CENTER)<13.:return "throw"
	return ""
func use()->void:
	if retry>0 or manual.visible:return
	var target:=focus()
	if target!="":polish.kick(.07)
	match target:
		"gate":
			if gate_rattle and gate_rattle.is_running():gate_rattle.kill()
			kit.gate.position.x=0.
			gate_rattle=create_tween().set_process_mode(Tween.TWEEN_PROCESS_PHYSICS)
			gate_rattle.tween_property(kit.gate,"position:x",.055,.055)
			gate_rattle.tween_property(kit.gate,"position:x",-.018,.075)
			gate_rattle.tween_property(kit.gate,"position:x",0.,.09)
			say("铁闸从里面闩住了。")
			line_once("gate","走右边侧门，穿过档案翼找总闸。",4.5)
		"note":say("残页：隔着玻璃也有反应。昨夜值班记录的最后一行被撕掉了。")
		"loot":taken=true;equipped=true;oil=minf(100.,oil+35);kit.supplies.hide();say("收起了发条节拍器与煤油罐。")
		"lever":
			if not learned:return
			if gate_rattle and gate_rattle.is_running():gate_rattle.kill()
			kit.gate.position.x=0.
			released=true;kit.gate.position.y=4.;checkpoint_oil=oil;checkpoint_item=equipped;hunter.wake();polish.kick(.5);polish.punch(-5.);sound_at("slam",kit.panel.position,2);sound_at("scream",hunter.position,4);line_once("release","主闸开了！……嘘，听见井底的声音没？压低脚步，别跑！")
		"core":
			collected=true;polish.kick(.45);polish.punch(-4.);kit.core.hide();emergency.show();siren.stream=sounds.alarm;siren.play();line_once("core","拿到手了！别走回头桥，上右边楼梯踹开绿门直接冲回主廊！")
		"return":walker.position=Vector3(38.7,.1,8.6);trail.clear();holding=false;posting=false;command_path.clear();hale.position=walker.position+Vector3.RIGHT
		"exit":
			finished=true;Input.mouse_mode=Input.MOUSE_MODE_VISIBLE;hud.text="撤离成功　·　备用源核已送回稳压室";polish.finish("撤 离 成 功","备用源核已送回稳压室");subtitle.hide();prompt.hide();returned.emit()
		"throw":equipped=false;polish.kick(.14);polish.punch(-2.);distraction=12.;hunter.throw_from(eye.global_position);sound_at("iron",hunter.BAIT,2)
func order()->void:
	if focus()!="north" or manual.visible or retry>0:return
	if posting or holding:posting=false;holding=false;command_path.clear();trail.clear();return
	posting=true;command_path=kit.stair_path.duplicate();for i in 20:command_path.append(kit.polar(12.45,PI+(PI*.5)*i/19.,4.8));
	line_once("post","明白，我去北窗帮你盯死桥面——过桥时千万别回头跟我对看！")
func _physics_process(dt:float)->void:
	if manual.visible or finished:return
	prompt.visible=mode<0;subtitle.visible=mode<0 and sub_time>0
	if mode>=0 and detail_view>=0:hud.text="EYE HEIGHT   /   %s     F6  next sightline    F4  leave"%["B2 · OBSERVATION WINDOW","B5 · MASTER RELEASE","C1 · GAZE SPAN"][detail_view];return
	if mode>=0:hud.text="SECTION PLATE  %s    /    F4  next view   /   F5  shell or cutaway   /   F6  eye height"%["A · IMMERSION ARCADE","B · ARCHIVE WING","C · SOURCE CAISSON"][mode];return
	var axis:=Input.get_vector("move_left","move_right","move_up","move_down");var dir:=walker.basis*Vector3(axis.x,0,axis.y);var speed:=5.8 if running else 3.8
	if Input.is_physical_key_pressed(KEY_CTRL) or Input.is_action_pressed("expedition_quiet"):speed=2.2
	if retry>0:
		retry-=dt;if retry<=0:reset_at_checkpoint()
	else:
		var current:=Vector2(walker.velocity.x,walker.velocity.z);var wish:=Vector2(dir.x,dir.z)*speed
		# Snappier reversals, a soft start, and a short glide-to-stop; weak steering in the air.
		var accel:=24. if dir.length_squared()>0 else 30.
		if dir.length_squared()>0 and current.dot(wish)<0.:accel=46.
		if not walker.is_on_floor():accel*=.25
		var planar:=current.move_toward(wish,dt*accel)
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
	subtitle.modulate.a=clampf(sub_time/.35,0.,1.)
	if sub_time<=0 and next_thought:
		next_thought=false;subtitle_id="thought";subtitle.text="我心想：难道他所记忆的规则和我的不同吗？";sub_time=4.5
	hud.text="目标：%s"%["从绿色捷径门撤回大厅" if collected else ("从右侧门去档案翼找总闸" if cues.has("gate") and not released else "取回深井对岸的备用源核")]
	hud.modulate=Color.WHITE
	var hints:={"gate":"[E] 试推铁闸","note":"[E] 阅读残页","loot":"[E] 拾取补给","lever":"[E] 拉下主闸","core":"[E] 拔出源核","return":"[E] 推开捷径门","exit":"[E] 返回大厅","north":"[Q] 召回 Hale" if holding or posting else "[Q] 指派 Hale 盯桥","throw":"[E] 投出节拍器"}
	var seen:=focus();polish.focus_id=seen;var hint:=str(hints.get(seen,""));prompt.text=(notice if msg_time>0 else hint if hint!="" else "[1] 打开规则手册" if not read_book else "")
func walking_feedback(dt:float)->void:
	var distance:=Vector2(walker.get_position_delta().x,walker.get_position_delta().z).length()
	if walker.is_on_floor() and distance>.001:
		stride+=distance/(1.75 if running else 1.55)
		if stride>=1.:
			stride=fmod(stride,1.);var kind:="stone"
			for i in walker.get_slide_collision_count():
				var contact:=walker.get_slide_collision(i)
				if contact.get_normal().y<.7:continue
				var surface:=str(contact.get_collider().get_parent().name)
				if "SouthServiceWalk" in surface:kind="iron"
				elif "Plate" in surface or "Span" in surface:kind="wood"
			foot.stream=sounds[kind];foot.pitch_scale=randf_range(.93,1.07);foot.volume_db=-27. if speed_quiet() else (-17. if running else -21.);foot.play()

func speed_quiet()->bool:return Input.is_physical_key_pressed(KEY_CTRL) or Input.is_action_pressed("expedition_quiet")
func animate_hale(prior:Vector3,dt:float)->void:
	var d:=hale.position-prior;d.y=0;var speed:=d.length()/dt
	hale_speed=lerpf(hale_speed,speed,1.-exp(-10.*dt))
	var anim:AnimationPlayer=hale.get_meta("animation_player");var clip:=&"walk" if hale_speed>.18 else &"idle"
	if anim.current_animation!=clip:anim.play(clip,.16)
	anim.speed_scale=clampf(hale_speed/2.5,.75,1.7) if clip==&"walk" else 1.
	if speed>.1:hale.rotation.y=lerp_angle(hale.rotation.y,atan2(d.x,d.z),1.-exp(-12.*dt))
func line_once(id:String,text:String,duration:=4.5)->void:
	if cues.has(id):return
	cues[id]=true;if id in Polish.CINEMATIC_LINES:polish.letterbox(duration+.6)
	subtitle_id=id;subtitle.text="Hale："+text;sub_time=duration;chime.stream=sounds.cue;chime.play()
func advance_hale(dt:float)->void:
	if tutorial_room and not learned and not holding:
		var station:=Vector3(21.1,0,9.6);hale.position=hale.position.move_toward(station,dt*3.8)
		if hale.position.distance_to(station)<.15:hale.rotation.y=lerp_angle(hale.rotation.y,-PI/2 if backed_off else .78,1.-exp(-8*dt))
		trail.clear();return
	if posting:
		if command_path.is_empty():posting=false;holding=true;return
		hale.position=hale.position.move_toward(command_path[0],3.8*dt);if hale.position.distance_to(command_path[0])<.04:command_path.remove_at(0)
	elif not holding:
		if last_pos.distance_to(walker.position)>.22:trail.append(walker.position);last_pos=walker.position
		if trail.size()>5:hale.position=hale.position.move_toward(trail[0],4.5*dt);if hale.position.distance_to(trail[0])<.1:trail.remove_at(0)
func in_archive_without_proof(p:Vector3)->bool:
	return not learned and p.distance_to(Vector3(27.4,0,14.1))<1.1
func rules(dt:float)->void:
	var p:=walker.position
	update_demo(p,dt)
	if phase>=2 and not cues.has("start"):
		kit.airlock.position.y=2.4;polish.kick(.55);polish.punch(4.);sound_at("slam",Vector3(.2,1,0),0);sound_at("bell",Vector3(25,2,0),2);line_once("start","稳压室撑不到天亮了。前组把备用源核掉在深井对岸——先去前面看看铁闸。")
	if not released and not tutorial_room and p.x>30 and absf(p.z)<2.3:halo.light_energy=2.3
	oil=maxf(0.,oil-dt*.025)
	if p.x>44 and not released:walker.position=Vector3(39,0,10);say("先拉开黄铜总闸。")
	if in_archive_without_proof(p) and not practice_note:
		practice_note=true;say("门闩上刻着一块板。刚才的通行记录还是空白。")
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
		var m:=kit.bridge.material_override as StandardMaterial3D;m.albedo_color=Color("ff1930") if watchers==2 else Color("8e6337") if watchers==0 else Color("d4f1ff");m.emission=m.albedo_color
		if hazard>=(40 if watchers==2 else 60):fail("桥面过载")
	else:
		hazard=0;var m:=kit.bridge.material_override as StandardMaterial3D;m.albedo_color=Color("d4f1ff") if holding else Color("ffc35a");m.emission=m.albedo_color
	if released:
		var grate:=posting and hale_speed>.35 and hale.position.y>1.
		metal_beat-=dt
		if grate and metal_beat<=0:metal_foot.play();metal_beat=.55
		var loud:=walker.is_on_floor() and Vector2(walker.velocity.x,walker.velocity.z).length()>2.35
		if hunter.step(dt,p,loud,grate,distraction,collected,sounds):fail("听觉猎手扑到了你身上")
		if collected:
			emergency.light_energy=1.8+1.4*sin(phase*7.)
			if not siren.playing:siren.play()
# Glass transmits gaze; the plate never occludes its own samples.
func board_seen(origin:Vector3,forward:Vector3)->bool:
	var intersection:Variant=Plane(Vector3.UP,.11).intersects_ray(origin,forward)
	if intersection!=null and absf(intersection.x-23.85)<.90 and absf(intersection.z-12.02)<1.60 and origin.distance_to(intersection)<9.:
		var direct:=PhysicsRayQueryParameters3D.create(origin,intersection,2,[kit.test_board.get_child(0).get_rid()]);if get_world_3d().direct_space_state.intersect_ray(direct).is_empty():return true
	for z in [10.6,12.02,13.4]:
		var target:=Vector3(23.85,.11,z);var d:=target-origin
		if d.length()>9. or forward.dot(d.normalized())<.90:continue
		var ray:=PhysicsRayQueryParameters3D.create(origin,target,2,[kit.test_board.get_child(0).get_rid()]);if get_world_3d().direct_space_state.intersect_ray(ray).is_empty():return true
	return false
func update_demo(p:Vector3,dt:float)->void:
	phase+=dt
	var in_b3:=p.x>20 and p.x<27.8 and p.z>9. and p.z<15.1
	if in_b3:tutorial_room=true
	elif p.z<8.95 and board_seen(eye.global_position,-eye.global_basis.z):line_once("window","停下！那是凝视异常板——学院守则写了，直视它的人都会出事，别碰！")
	var self_sees:=board_seen(eye.global_position,-eye.global_basis.z)
	var count:=int(self_sees)+int(board_seen(hale.position+Vector3.UP*1.57,hale.basis.z))
	if subtitle_id=="double" and count!=2:sub_time=minf(sub_time,.35)
	if not learned and in_b3:
		if p.z<10.45 or p.y<-.10:crossing=false
		if absf(p.x-23.85)<.92 and p.z>10.48 and p.z<12.8 and p.y>=0 and self_sees and count==1:crossing=true
		if crossing and p.z<13.4 and (count!=1 or not self_sees):crossing=false
		if crossing and p.z>=13.65 and p.y>=0:
			learned=true;kit.evidence_gate.position.y=4.;line_once("evidence","等等……你一个人盯着它居然撑住了？官方守则根本是怕误看才一刀切封禁的……",5.5);next_thought=true
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
		if changed and in_b3:backed_off=true;line_once("double","红了！快别看——我早说过看它要命！")
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
func fail(reason:String)->void:retry=3.;polish.fail_beat();say(reason+"　·　正在返回折返点…")
func reset_at_checkpoint()->void:
	crossing=false;distraction=0.;running=false;collected=false;kit.core.show();siren.stop();emergency.hide();cues.erase("core");cues.erase("post");sub_time=0
	if released:hunter.wake();oil=checkpoint_oil;equipped=checkpoint_item
	walker.position=Vector3(38.6,.15,10) if released else Vector3(1,.1,0);walker.velocity=Vector3.ZERO;hale.position=walker.position+Vector3(.1,0,.7);polish.reset_beat();hazard=0;holding=false;posting=false;trail.clear();command_path.clear()
func observation()->Dictionary:return {"phase":"first_expedition","section":mode,"position":str(walker.position),"checkpoint":released,"learned":learned,"core":collected,"hale_posted":holding}

func review_props()->void:
	var ground:=PlaneMesh.new();ground.size=Vector2(400,400);plinth.mesh=ground;var g:=StandardMaterial3D.new();g.albedo_color=Color("a0998e");plinth.material_override=g;add_child(plinth);plinth.hide()
	add_child(review_witness);review_witness.position=kit.polar(12.45,PI*1.5,4.8);Cast.attach(review_witness,1);review_witness.rotation.y=PI
	var cone:=MeshInstance3D.new();var mesh:=CylinderMesh.new();var target:=Vector3(61,.05,10.1);var top:=review_witness.position+Vector3.UP*1.6;mesh.height=top.distance_to(target);mesh.top_radius=.025;mesh.bottom_radius=1.45;cone.mesh=mesh;var m:=StandardMaterial3D.new();m.transparency=BaseMaterial3D.TRANSPARENCY_ALPHA;m.shading_mode=BaseMaterial3D.SHADING_MODE_UNSHADED;m.albedo_color=Color(.18,.75,.77,.27);cone.material_override=m;review_witness.add_child(cone);cone.global_position=(target+top)*.5;cone.global_basis=Basis(Quaternion(Vector3.UP,(top-target).normalized()));review_witness.hide()
	var sound:=AudioStreamWAV.new();sound.mix_rate=16000;sound.format=AudioStreamWAV.FORMAT_16_BITS;var data:=PackedByteArray();data.resize(4800)
	for i in 2400:data.encode_s16(2*i,int(7500*sin(TAU*460*i/16000.)*(1.-i/2400.)))
	sound.data=data;warning.stream=sound;warning.position=Vector3(61,1,10.1);add_child(warning)
