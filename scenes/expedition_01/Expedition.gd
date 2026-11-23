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
var page:=RichTextLabel.new()
var book_page:=0
var caption_toast:=Label.new()
var toast_time:=0.
var lantern:=SpotLight3D.new()
var hale_lantern:=OmniLight3D.new()
var hale_prop:Node3D
var hale_rig:Skeleton3D
var hale_hand:=-1
var north_beacon:=OmniLight3D.new()
var ambient_bed:=AudioStreamPlayer.new()
var player_lamp:Node3D
var darkroom_mix:=0.
var evidence_thought_delay:=-1.
var demo_single_time:=0.
var demo_locked:=false
const GAZE_LOCK_TIME:=2.35
const HALE_WAIT:=Vector3(1.12,0.,1.19)
const HALE_ENTER:=Vector3(-2.87,0.,.87)
var plate_finish:=ShaderMaterial.new()
var sight_blend:=0.
var overload_blend:=0.
var plate_presence:=1.
var prompt:=Label.new()
var read_book:=false
var running:=false
var subtitle_id:=""
var crossing:=false
var crossing_locked:=false
var backed_off:=false
var checkpoint_oil:=65.
var checkpoint_item:=false
var metal_foot:=AudioStreamPlayer3D.new()
var metal_beat:=0.
var emergency:=OmniLight3D.new()
var siren:=AudioStreamPlayer3D.new()
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
var captions:=preload("ExpeditionCaptions.gd").new()
var cues:={}
var foot:=AudioStreamPlayer.new()
var chime:=AudioStreamPlayer.new()
var board_audio:=AudioStreamPlayer3D.new()
var sounds:={}
var tutorial_room:=false
var hale_gate_attempt:=false
var hale_gate_target:=Vector3.ZERO
var hale_gate_effort:=0.
var hale_speed:=0.
var hale_loco:AnimationNodeStateMachinePlayback
var hale_clip:=&""
var watch_route:=PackedVector3Array()
var hale_return_path:=PackedVector3Array()
var shortcut_open:=false
var shortcut_time:=0.
var shortcut_used:=false
var exit_open:=false
var reunited:=false
var exit_requested:=false
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
	add_child(hale);Cast.attach(hale,1,true);setup_hale_animation();hale.position=Vector3(3.15,0,1.22);hale.rotation.y=PI*.5;add_child(survey);survey.far=600;survey.projection=Camera3D.PROJECTION_ORTHOGONAL
	var canvas:=CanvasLayer.new();canvas.layer=8;add_child(canvas);canvas.add_child(hud);hud.position=Vector2(22,17);hud.add_theme_font_size_override("font_size",17);hud.add_theme_constant_override("outline_size",6)
	for a in ["expedition_quiet","expedition_use","expedition_section","expedition_watch","expedition_shell","expedition_detail"]:
		if not InputMap.has_action(a):InputMap.add_action(a)
	Input.mouse_mode=Input.MOUSE_MODE_VISIBLE
	var font:=Polish.make_font()
	hud.add_theme_font_override("font",font);hud.mouse_filter=Control.MOUSE_FILTER_IGNORE
	canvas.add_child(captions);captions.setup(font)
	canvas.add_child(caption_toast);caption_toast.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT)
	caption_toast.offset_left=-440.;caption_toast.offset_top=-176.;caption_toast.offset_right=-28.;caption_toast.offset_bottom=-140.
	caption_toast.horizontal_alignment=HORIZONTAL_ALIGNMENT_RIGHT
	caption_toast.add_theme_font_override("font",font);caption_toast.add_theme_font_size_override("font_size",17)
	caption_toast.add_theme_constant_override("outline_size",6);caption_toast.hide()
	plate_finish.shader=preload("GazePlate.gdshader");kit.test_board.material_override=plate_finish
	player_lamp=Node3D.new();eye.add_child(player_lamp);player_lamp.position=Vector3(.34,-.42,-.25)
	player_lamp.add_child(lantern);lantern.position=Vector3(0,.065,-.08);lantern.rotation.x=-.17
	lantern.light_color=Color("ffcc8c");lantern.spot_attenuation=1.1;lantern.spot_angle_attenuation=1.25
	lantern.shadow_enabled=true;lantern.shadow_bias=.045;lantern.shadow_normal_bias=.40
	hale_prop=build_lantern(Vector3(-.27,1.06,.27));hale_prop.hide()
	hale_rig=hale.get_meta("skeleton");hale_hand=hale_rig.find_bone("hand_l")
	hale_prop.add_child(hale_lantern);hale_lantern.position=Vector3(0,.08,.13)
	hale_lantern.light_color=Color("f6c184");hale_lantern.omni_range=3.6;hale_lantern.light_energy=.42
	add_child(north_beacon);north_beacon.position=kit.north_spot.global_position+Vector3(.38,1.8,-.9)
	north_beacon.light_color=Color("ffca80");north_beacon.omni_range=3.5;north_beacon.light_energy=.85;north_beacon.hide()
	kit.section=kit.get_child(0);kit.plaque("稳压室",Vector3(.25,2.94,0),.98,PI*.5)
	kit.section=kit.get_child(2);kit.plaque("北窗",kit.polar(10.9,1.5*PI,6.82),.68)
	sounds=Sound.clips()
	add_child(ambient_bed);ambient_bed.stream=sounds.ambience;ambient_bed.volume_db=-42.;ambient_bed.play()
	add_child(foot);add_child(chime);add_child(board_audio);foot.volume_db=-21;chime.volume_db=-14;board_audio.position=Vector3(23.85,.4,12.02);board_audio.max_distance=12;board_audio.volume_db=-9
	for pos in [Vector3(23.6,2.1,4.),Vector3(24.65,2.7,8.1),Vector3(23.85,2.4,12),Vector3(36.3,2.4,8.2),Vector3(.8,2.55,0)]:
		var lamp:=OmniLight3D.new();lamp.position=pos;lamp.omni_range=4.;lamp.light_energy=.62;lamp.light_color=Color("ffebc5");lamp.omni_attenuation=1.3;lamp.shadow_enabled=true;lamp.shadow_bias=.035;lamp.shadow_normal_bias=.42;add_child(lamp)
	var annex:=OmniLight3D.new();add_child(annex);annex.position=Vector3(-3.4,2.22,0)
	annex.omni_range=6.2;annex.light_energy=2.4;annex.light_color=Color("ffc475");annex.shadow_enabled=true
	var return_lamp:=OmniLight3D.new();add_child(return_lamp);return_lamp.position=Vector3(78.72,6.92,12.45)
	return_lamp.omni_range=4.1;return_lamp.light_energy=.81;return_lamp.light_color=Color("ffd99d");return_lamp.shadow_enabled=true
	add_child(hunter);hale.add_child(metal_foot);metal_foot.stream=sounds.iron;metal_foot.volume_db=-12;add_child(siren);siren.position=Vector3(73.15,5.25,9.25);siren.max_distance=24.;siren.volume_db=-17.
	add_child(halo);halo.position=Vector3(31,2.1,2.9);halo.light_color=Color("ffbd70");halo.omni_range=6;halo.light_energy=1.4;halo.shadow_enabled=true
	add_child(emergency);emergency.position=Vector3(73.15,5.25,9.25);emergency.light_color=Color("ff5234");emergency.omni_range=5.6;emergency.omni_attenuation=1.7;emergency.hide()
	canvas.add_child(prompt);prompt.set_anchors_and_offsets_preset(Control.PRESET_CENTER);prompt.offset_left=-320;prompt.offset_right=320;prompt.offset_top=23;prompt.offset_bottom=68;prompt.vertical_alignment=VERTICAL_ALIGNMENT_TOP;prompt.add_theme_font_size_override("font_size",19);prompt.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER;prompt.add_theme_font_override("font",font);prompt.add_theme_constant_override("outline_size",6);prompt.mouse_filter=Control.MOUSE_FILTER_IGNORE
	canvas.add_child(manual);manual.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	manual.offset_left=-305;manual.offset_right=305;manual.offset_top=-194;manual.offset_bottom=194
	var paper:=StyleBoxFlat.new();paper.bg_color=Color("e3cda2");paper.border_color=Color("63472b");paper.set_border_width_all(3)
	paper.set_corner_radius_all(4);paper.shadow_color=Color(0,0,0,.7);paper.shadow_size=20
	paper.content_margin_left=34;paper.content_margin_right=34;paper.content_margin_top=28;paper.content_margin_bottom=22
	manual.add_theme_stylebox_override("panel",paper);manual.add_child(page);page.bbcode_enabled=true;page.scroll_active=false
	page.add_theme_font_override("normal_font",font);page.add_theme_font_override("bold_font",font)
	page.add_theme_color_override("default_color",Color("31241a"));page.add_theme_font_size_override("normal_font_size",18)
	page.add_theme_font_size_override("bold_font_size",22);manual.hide()
	add_child(polish);polish.setup(self,canvas)
	update_target()
func toggle_book()->void:
	manual.visible=not manual.visible;read_book=true
	if manual.visible:
		book_page=0;render_book();toast_time=0.;caption_toast.hide()
		if captions.entries.has("Hale") and captions.entries.Hale.id=="start" and captions.entries.Hale.remaining<2.6:
			captions.remove_speaker("Hale")
	play_ui("page",-19.)
	prompt.visible=not manual.visible;captions.visible=not manual.visible;polish.on_book(manual.visible)
func render_book()->void:
	if book_page==0:
		page.text="[b]远征员随身规则手册[/b]　01 / 02\n[color=#796346]━━━━━━━━━━━━━━━━━━━━[/color]\n\n井区交班记录　琥珀异常板遇目光即生异变，隔窗目击亦须登记。\n\n学院守则摘录　严禁直视异常板，违者按失控事故处置。\n\n值守须知　铁网步声直通井底，深井值守严禁奔跑。"
		if learned:page.append_text("\n\n[font_size=16][color=#862f25]手写批注　单目持续注视可锁稳。若两目交错恐生变故。[/color][/font_size]")
	else:
		page.text="[b]远征员随身规则手册[/b]　02 / 02\n[color=#796346]━━━━━━━━━━━━━━━━━━━━[/color]\n\n出勤备忘\n\nShift　切换走／跑　　 Ctrl　按住静步\nE　互动　　Q　指派 Hale\n方括号键　调整视角灵敏度"
	page.append_text("\n\n[color=#68503b]← / →　翻页　　　　1　合册[/color]")
func play_ui(kind:String,db:float)->void:
	chime.stream=sounds[kind];chime.volume_db=db;chime.play()
func build_lantern(offset:Vector3)->Node3D:
	var prop:=Node3D.new();hale.add_child(prop);prop.position=offset
	var frame:=StandardMaterial3D.new();frame.albedo_color=Color("795732");frame.metallic=.55;frame.roughness=.54
	var flame:=StandardMaterial3D.new();flame.albedo_color=Color("ffbf6c");flame.emission_enabled=true;flame.emission=Color("ffaf51");flame.emission_energy_multiplier=2.5
	for y in [-.066,.066]:
		var cap:=MeshInstance3D.new();cap.mesh=BoxMesh.new();cap.mesh.size=Vector3(.15,.024,.115);cap.material_override=frame;prop.add_child(cap);cap.position.y=y
	for x in [-.061,.061]:
		for z in [-.047,.047]:
			var rib:=MeshInstance3D.new();rib.mesh=BoxMesh.new();rib.mesh.size=Vector3(.013,.12,.013);rib.material_override=frame;prop.add_child(rib);rib.position=Vector3(x,0,z)
	var handle:=MeshInstance3D.new();handle.mesh=TorusMesh.new();handle.mesh.inner_radius=.039;handle.mesh.outer_radius=.047;handle.rotation.x=PI*.5;handle.position.y=.095;handle.material_override=frame;prop.add_child(handle)
	var wick:=MeshInstance3D.new();wick.mesh=SphereMesh.new();wick.mesh.radius=.024;wick.mesh.height=.078;wick.material_override=flame;prop.add_child(wick)
	return prop
func toast(text:String)->void:
	caption_toast.text=text;caption_toast.show();toast_time=captions.reading_time(text)
func sound_at(kind:String,pos:Vector3,db:float)->void:
	var audio:=AudioStreamPlayer3D.new();add_child(audio);audio.position=pos;audio.stream=sounds[kind];audio.volume_db=db;audio.max_distance=90;audio.finished.connect(audio.queue_free);audio.play()
func light_stage()->void:
	var w:=WorldEnvironment.new();var e:=Environment.new()
	e.background_mode=Environment.BG_COLOR;e.background_color=Color("e3e2d9")
	e.ambient_light_source=Environment.AMBIENT_SOURCE_COLOR;e.ambient_light_color=Color("c9d0d8");e.ambient_light_energy=.55
	# Tone: ACES kept for contrast, exposure lifted from .68 so the vaults read without washing the walls out.
	e.tonemap_mode=Environment.TONE_MAPPER_FILMIC;e.tonemap_exposure=.78;e.tonemap_white=3.5
	e.adjustment_enabled=true;e.adjustment_contrast=1.1;e.adjustment_saturation=1.0
	# Contact shading + one-bounce GI. SDFGI is trimmed to 3 cascades (the level is ~75 m long).
	e.ssao_enabled=true;e.ssao_radius=1.3;e.ssao_intensity=2.2;e.ssao_power=1.6;e.ssao_detail=.6;e.ssao_light_affect=.25
	e.sdfgi_enabled=true;e.sdfgi_cascades=3;e.sdfgi_min_cell_size=.3;e.sdfgi_use_occlusion=true;e.sdfgi_bounce_feedback=.45;e.sdfgi_energy=.9;e.sdfgi_y_scale=Environment.SDFGI_Y_SCALE_75_PERCENT
	# Soft bloom for lamps, emissive boards and the alarm; thin aerial fog for depth down the long arcade.
	e.glow_enabled=true;e.glow_intensity=.3;e.glow_strength=.85;e.glow_bloom=.02;e.glow_hdr_threshold=1.3;e.glow_blend_mode=Environment.GLOW_BLEND_MODE_SOFTLIGHT
	e.fog_enabled=true;e.fog_light_color=Color("e7e0d0");e.fog_density=.0028;e.fog_aerial_perspective=.2;e.fog_sky_affect=0.
	w.environment=e;add_child(w)
	var sun:=DirectionalLight3D.new();sun.rotation_degrees=Vector3(-48,-33,0);sun.light_energy=.31;sun.light_color=Color("fff1dc");sun.shadow_enabled=true
	sun.directional_shadow_max_distance=64;sun.directional_shadow_mode=DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS;sun.directional_shadow_blend_splits=true
	sun.shadow_bias=.025;sun.shadow_normal_bias=.55;sun.light_angular_distance=.45;add_child(sun)
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
	if manual.visible:
		if ev is InputEventKey and ev.pressed and not ev.echo and ev.physical_keycode in [KEY_LEFT,KEY_RIGHT]:
			book_page=1-book_page;render_book();play_ui("page",-19.)
		return
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
func thought(id:String,text:String)->void:
	subtitle_id=id;captions.post(id,"",text)
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
	if learned and not released and aimed(Vector3(36.3,1.35,7.72),3.):return "lever"
	if released and not collected and aimed(kit.core.position,2.8):return "core"
	if collected and not shortcut_open and aimed(kit.leaf.global_position,3.5,.94):return "return"
	if collected and not exit_open and walker.position.x>=0. and aimed(Vector3(.37,1.5,0),3.):return "exit"
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
			polish.kick(.22)
			sound_at("gate",Vector3(36.,1.46,0),-6.)
			thought("gate_test","插销从里面闩死了。")
			confirm_gate_locked()
		"note":say("残页：隔着玻璃也有反应。昨夜值班记录的最后一行被撕掉了。")
		"loot":
			taken=true;equipped=true;oil=minf(100.,oil+35);kit.supplies.hide()
			play_ui("cue",-16.);toast("收起了前班遗落的煤油罐与发条节拍器。")
			thought("bait_hint","上了发条扔下去，能把井底的耳朵引开。")
		"lever":
			if not learned:return
			hale_gate_attempt=false;hale.rotation.x=0.
			released=true;kit.gate.position.y=4.;checkpoint_oil=oil;checkpoint_item=equipped;hunter.wake();polish.kick(.5);polish.punch(-5.);sound_at("lever",kit.panel.position,-4.);sound_at("chain",Vector3(36.,2.,0.),-3.);line_once("release","主闸通了！放轻脚步，铁网会把声音传到井底。")
		"core":
			collected=true;begin_hale_return();polish.kick(.32);polish.punch(-4.);kit.core.hide();emergency.show();siren.stream=sounds.alarm;siren.play();line_once("core","源核离座，井底已经听见了！别回桥，上左侧楼梯，撞开绿漆应急门！")
		"return":
			shortcut_open=true;polish.kick(.38);sound_at("escape",kit.leaf.global_position,-5.)
			create_tween().set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT).tween_property(kit.leave_pivot,"rotation:y",1.43,.42)
		"exit":
			exit_open=true;create_tween().tween_property(kit.airlock,"position:y",5.4,.45)
			sound_at("airlock",Vector3(.1,1.45,0),-6.)
		"throw":equipped=false;polish.kick(.14);polish.punch(-2.);distraction=12.;hunter.throw_from(eye.global_position)
	update_target()
func finish_expedition()->void:
	finished=true;Input.mouse_mode=Input.MOUSE_MODE_VISIBLE
	hud.text="撤离成功　·　备用源核已送回稳压室"
	polish.finish("撤 离 成 功","备用源核已送回稳压室 · 远征记录已归档")
	captions.hide();caption_toast.hide();prompt.hide();siren.stop();hunter.stop_audio();returned.emit()
func begin_hale_return()->void:
	if not (holding or posting):
		# The south bypass also rejoins the evacuation route: Hale waits by the west entrance.
		if hale.position.x>46.:
			hale_return_path=PackedVector3Array([Vector3(48.3,0.,10.1),Vector3(38.7,0.,10.1),Vector3(38.7,0.,0.),Vector3(2.4,0.,0.),HALE_WAIT])
		return
	var traversed:=watch_route.size() if holding else watch_route.size()-command_path.size()
	hale_return_path.clear()
	for i in range(traversed-1,-1,-1):hale_return_path.append(watch_route[i])
	for point in [Vector3(48.3,0.,10.1),Vector3(38.7,0.,10.1),Vector3(38.7,0.,0.),Vector3(34.,0.,0.),Vector3(2.4,0.,0.),HALE_WAIT]:hale_return_path.append(point)
	holding=false;posting=false;command_path.clear();trail.clear()
func order()->void:
	if manual.visible or retry>0:return
	var target:=focus()
	if target=="gate":
		if hale_gate_attempt:return
		hale_gate_attempt=true;hale_gate_effort=.82
		hale_gate_target=kit.gate_spots[0 if walker.position.z>=0. else 1].global_position
		trail.clear()
		return
	if target!="north":return
	if posting or holding:posting=false;holding=false;command_path.clear();trail.clear();return
	posting=true;command_path=kit.stair_path.duplicate();command_path.insert(0,Vector3(48.65,0.,9.21))
	for i in 19:command_path.append(kit.polar(12.45,PI+(PI*.5)*i/19.,4.8))
	command_path.append(kit.north_spot.global_position)
	watch_route=command_path.duplicate()
	captions.post("north_order","我","去北窗帮我盯住桥面。")
	line_once("post","明白！桥面只能承住一道目光。过桥时看前方，别低头看桥！")
func _physics_process(dt:float)->void:
	if finished:
		ambient_bed.volume_db=move_toward(ambient_bed.volume_db,-72.,54.*dt)
		if ambient_bed.volume_db<=-72.:ambient_bed.stop()
		return
	if manual.visible:
		if captions.entries.has("Hale") and captions.entries.Hale.id=="start":captions.advance(dt)
		return
	prompt.visible=mode<0;captions.visible=mode<0
	if mode>=0 and detail_view>=0:hud.text="EYE HEIGHT   /   %s     F6  next sightline    F4  leave"%["B2 · OBSERVATION WINDOW","B5 · MASTER RELEASE","C1 · GAZE SPAN"][detail_view];return
	if mode>=0:hud.text="SECTION PLATE  %s    /    F4  next view   /   F5  shell or cutaway   /   F6  eye height"%["A · IMMERSION ARCADE","B · ARCHIVE WING","C · SOURCE CAISSON"][mode];return
	if shortcut_time>0.:
		shortcut_time-=dt
		if shortcut_time<=0.:
			walker.position=Vector3(38.7,.10,8.6);walker.velocity=Vector3.ZERO
			walker.rotation.y=0.;eye.rotation=Vector3.ZERO;polish.reset_beat()
		return
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
		if shortcut_open and not shortcut_used and walker.position.x>kit.RETURN_DEPTH and walker.position.y>4.55 and absf(walker.position.z-12.45)<.8:
			shortcut_used=true;shortcut_time=.26;polish.fade_to(1.,.23);return
		if exit_open and walker.position.x<kit.AIRLOCK_DEPTH:exit_requested=true
		if exit_requested and walker.position.x<kit.AIRLOCK_DEPTH and hale.position.x< -1.85 and hale_return_path.is_empty() and not captions.entries.has("Hale"):
			finish_expedition();return
		var prior:=hale.position;advance_hale(dt);animate_hale(prior,dt);rules(dt)
	msg_time-=dt;distraction=maxf(0,distraction-dt)
	captions.advance(dt)
	toast_time-=dt;caption_toast.visible=toast_time>0. and mode<0
	north_beacon.visible=holding
	update_lantern(dt)
	ambient_bed.volume_db=move_toward(ambient_bed.volume_db,-29. if collected else -35. if walker.position.x>46. else -42.,5.*dt)
	if evidence_thought_delay>0.:
		evidence_thought_delay-=dt
		if evidence_thought_delay<=0.:thought("thought","单道目光反而锁住了它。把这条记下来。")
	update_target()
	hud.modulate=Color.WHITE
	var hints:={"gate":"Hale 正在试铁闸…" if hale_gate_attempt else "[E] 晃动铁闸　[Q] 请 Hale 试试","note":"[E] 阅读残页","loot":"[E] 拾取补给","lever":"[E] 扳下总闸","core":"[E] 拔出源核","return":"[E] 撞开应急门","exit":"[E] 开启气密门","north":"[Q] 召回 Hale" if holding or posting else "[Q] 指派 Hale 盯桥","throw":"[E] 投出节拍器（诱饵）"}
	var seen:=focus();polish.focus_id=seen
	var hint:=str(hints.get(seen,""));prompt.text=hint if hint!="" else notice if msg_time>0 else "[1] 打开规则手册" if not read_book else ""
func update_lantern(dt:float)->void:
	var p:=walker.position
	var dark:=p.z>13.05 and p.z<15.15 and p.x>27.8 and p.x<41.8
	darkroom_mix=move_toward(darkroom_mix,1. if dark else 0.,dt*4.)
	var env:Environment=get_world_3d().environment
	env.ambient_light_energy=lerpf(.55,.09,darkroom_mix)
	env.sdfgi_energy=lerpf(.90,.48,darkroom_mix)
	var fuel:=sqrt(oil/100.)
	var flicker:=1.+.045*sin(phase*15.7)+.026*sin(phase*27.3)
	lantern.light_energy=2.85*fuel*flicker
	lantern.spot_range=lerpf(1.8,8.3,fuel);lantern.spot_angle=lerpf(26.,50.,fuel)
	player_lamp.position=Vector3(.34+.024*sin(TAU*stride),-.42+.023*cos(TAU*stride),-.25)
	hale_prop.visible=released
	if released and hale_hand>=0:
		var grip:=hale.to_local(hale_rig.to_global(hale_rig.get_bone_global_pose(hale_hand).origin))
		hale_prop.position=grip+Vector3(0,-.14,.032)
	hale_lantern.light_energy=(1.22 if posting else .48)*flicker
func update_target()->void:
	var goal:="取回深井对岸的备用源核"
	if exit_requested:goal="进入稳压室门厅"
	elif shortcut_used:goal="沿主廊返回稳压室"
	elif collected:goal="上螺旋梯 · 经绿门撤离"
	elif holding:goal="Hale 已就位 · 看前方过桥"
	elif posting:goal="Hale 正前往北窗"
	elif released:goal="进源井 · 静步接近桥头"
	elif equipped:goal="去总控室扳下总闸"
	elif learned:goal="穿过档案翼，前往总控室"
	elif demo_locked:goal="板面已稳 · 保持视线穿过"
	elif tutorial_room and cues.has("red"):goal="观察异常板，等待波纹收束"
	elif cues.has("gate"):goal="从右侧门去档案翼找总闸"
	hud.text="目标："+goal
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
				if "SouthServiceWalk" in surface or "Span" in surface or contact.get_collider().is_in_group("expedition_iron_tread"):kind="iron"
				elif "Plate" in surface:kind="wood"
			foot.stream=sounds.quiet if speed_quiet() else sounds[kind];foot.pitch_scale=randf_range(.93,1.07);foot.volume_db=-27. if speed_quiet() else (-17. if running else -21.);foot.play()

func speed_quiet()->bool:return Input.is_physical_key_pressed(KEY_CTRL) or Input.is_action_pressed("expedition_quiet")
func setup_hale_animation()->void:
	var anim:AnimationPlayer=hale.get_meta("animation_player")
	var tree:=AnimationTree.new();var machine:=AnimationNodeStateMachine.new()
	var states: Array[StringName]=[&"idle",&"walk",&"run",&"gate_effort"]
	for clip in states:
		var node:=AnimationNodeAnimation.new();node.animation=clip;machine.add_node(clip,node)
	for origin in states:
		for destination in states:
			if origin==destination:continue
			var blend:=AnimationNodeStateMachineTransition.new();blend.xfade_time=.14
			machine.add_transition(origin,destination,blend)
	anim.get_parent().add_child(tree);tree.anim_player=tree.get_path_to(anim);tree.tree_root=machine;tree.active=true
	hale_loco=tree.get("parameters/playback");hale_loco.start(&"idle")
func animate_hale(prior:Vector3,dt:float)->void:
	var d:=hale.position-prior;d.y=0;var speed:=d.length()/dt
	hale_speed=lerpf(hale_speed,speed,1.-exp(-10.*dt))
	var pushing:=hale_gate_attempt and hale.position.distance_to(hale_gate_target)<.025
	var clip:=&"gate_effort" if pushing else &"run" if hale_speed>4.8 else &"walk" if hale_speed>.18 else &"idle"
	if hale_clip!=clip:hale_loco.travel(clip);hale_clip=clip
	if speed>.1:hale.rotation.y=lerp_angle(hale.rotation.y,atan2(d.x,d.z),1.-exp(-12.*dt))
func line_once(id:String,text:String)->void:
	if cues.has(id):return
	cues[id]=true
	show_line(id,text)
func show_line(id:String,text:String)->void:
	if id in Polish.CINEMATIC_LINES:polish.letterbox(captions.reading_time(text)+.4)
	subtitle_id=id;captions.post(id,"Hale",text.trim_prefix("Hale："));play_ui("cue",-23.)
func confirm_gate_locked()->void:
	cues["gate"]=true
func advance_hale(dt:float)->void:
	if not hale_return_path.is_empty():
		var next:=hale_return_path[0]
		hale.position=hale.position.move_toward(next,dt*5.8)
		if hale.position.distance_to(next)<.03:hale_return_path.remove_at(0)
		return
	if shortcut_used and not reunited and walker.position.x<9. and hale.position.distance_to(walker.position)<7.:
		reunited=true;show_line("reunion","我从北廊绕回来了。今晚的见闻，回锚定厅后记进手册吧。")
		return
	if shortcut_used and not hale_gate_attempt:
		var destination:=HALE_ENTER if exit_open and walker.position.x<.35 else HALE_WAIT
		if hale.position.distance_to(destination)>.02:
			hale.position=hale.position.move_toward(destination,dt*3.0)
		else:
			var delta:=walker.position-hale.position
			if delta.length()>1.05:hale.rotation.y=lerp_angle(hale.rotation.y,atan2(delta.x,delta.z),1.-exp(-8.*dt))
		return
	if hale_gate_attempt:
		if released or walker.position.x<31. or absf(walker.position.z)>2.:
			hale_gate_attempt=false;hale.rotation.x=0.
		else:
			if hale.position.distance_to(hale_gate_target)>.025:
				hale.position=hale.position.move_toward(hale_gate_target,dt*3.8)
			else:
				hale.rotation.y=lerp_angle(hale.rotation.y,PI*.5,1.-exp(-15.*dt))
				if hale_gate_effort==.82:sound_at("gate",hale_gate_target+Vector3(.64,1.22,0),-5.)
				hale_gate_effort-=dt
				hale.rotation.x=.045*sin(TAU*clampf(hale_gate_effort/.82,0.,1.))
				if hale_gate_effort<=0.:
					hale_gate_attempt=false;hale.rotation.x=0.;confirm_gate_locked()
					show_line("hale_gate","纹丝不动。绕右边的档案侧门，去找总闸。")
			return
	if tutorial_room and not learned and not holding:
		var station:=Vector3(21.1,0,9.6);hale.position=hale.position.move_toward(station,dt*3.8)
		if hale.position.distance_to(station)<.15:hale.rotation.y=lerp_angle(hale.rotation.y,-PI/2 if backed_off else .78,1.-exp(-8*dt))
		trail.clear();return
	if posting:
		if command_path.is_empty():
			posting=false;holding=true;hale.rotation.y=0.
			show_line("north_ready","我到北窗了，桥面已经锁稳。快过桥！")
			return
		var budget:=8.7*dt
		while budget>0. and not command_path.is_empty():
			var distance:=hale.position.distance_to(command_path[0])
			hale.position=hale.position.move_toward(command_path[0],budget);budget-=distance
			if budget>=0.:command_path.remove_at(0)
	elif not holding:
		if released and walker.position.x>50.:return
		if last_pos.distance_to(walker.position)>.23:trail.append(walker.position);last_pos=walker.position
		if trail.size()>9:
			var next:=hale.position.move_toward(trail[0],4.7*dt)
			var gap:=Vector2(hale.position.x-walker.position.x,hale.position.z-walker.position.z)
			var next_gap:=Vector2(next.x-walker.position.x,next.z-walker.position.z)
			if next_gap.length()<1.82 and next_gap.length()<gap.length():
				# A reversing player may meet Hale. Yield sideways when clear.
				var ray:=PhysicsRayQueryParameters3D.create(hale.position+Vector3.UP*.72,hale.position+Vector3.UP*.72+hale.basis.x*.8,2)
				if gap.length()<1.42 and get_world_3d().direct_space_state.intersect_ray(ray).is_empty():hale.position+=hale.basis.x*dt*2.
				if trail.size()>18:trail.remove_at(0)
			else:
				hale.position=next
				if hale.position.distance_to(trail[0])<.055:trail.remove_at(0)
func in_archive_without_proof(p:Vector3)->bool:
	return not learned and p.distance_to(Vector3(27.4,0,14.1))<1.1
func rules(dt:float)->void:
	var p:=walker.position
	update_demo(p,dt)
	if phase>=2 and not cues.has("start"):
		kit.airlock.position.y=2.4;polish.kick(.55);polish.punch(4.);sound_at("airlock",Vector3(.2,1,0),-7.);sound_at("bell",Vector3(25,2,0),2);line_once("start","稳压室撑不到天亮。前班撤离时，把备用源核留在了深井对岸。")
	if not released and not tutorial_room and p.x>30. and p.x<36. and absf(p.z)<2.3:
		halo.light_energy=2.3
	oil=maxf(0.,oil-dt*.11)
	if p.x>44 and not released:walker.position=Vector3(39,0,10);say("先拉开黄铜总闸。")
	if in_archive_without_proof(p) and not practice_note:
		practice_note=true;say("门闩上刻着一块板。刚才的通行记录还是空白。")
	if p.x<0 and not exit_open:walker.position.x=.05
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
		paint_bridge(Color("bf4335") if watchers==2 else Color("765337") if watchers==0 else Color("94b7be"),.30 if watchers else .13,dt)
		if hazard>=(40 if watchers==2 else 60):fail("桥面过载")
	else:
		hazard=0;paint_bridge(Color("94b7be") if holding else Color("a9824f"),.30 if holding else .19,dt)
	if released:
		var grate:=posting and hale_speed>.35 and hale.position.y>1.
		metal_beat-=dt
		if grate and metal_beat<=0:metal_foot.play();metal_beat=.55
		var loud:=walker.is_on_floor() and Vector2(walker.velocity.x,walker.velocity.z).length()>2.35
		if hunter.step(dt,p,loud,grate,distraction,collected,sounds):fail("听觉猎手扑到了你身上")
		if hunter.bait_answered and distraction>0. and not cues.has("bait_answer"):
			cues["bait_answer"]=true;polish.signal_bait()
		if collected:
			emergency.light_energy=.38+.34*(.5+.5*sin(phase*5.))
			if not siren.playing:siren.play()
# Glass transmits gaze; the plate never occludes its own samples.
func paint_bridge(tint:Color,glow:float,dt:float)->void:
	var m:=kit.bridge.material_override as StandardMaterial3D
	m.albedo_color=m.albedo_color.lerp(tint,1.-exp(-8.*dt));m.emission=m.albedo_color
	m.emission_energy_multiplier=glow
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
	elif p.z<8.95 and board_seen(eye.global_position,-eye.global_basis.z):line_once("window","站住！那是凝视异常板。学院守则严禁直视，别过去！")
	var self_sees:=board_seen(eye.global_position,-eye.global_basis.z)
	var count:=int(self_sees)+int(board_seen(hale.position+Vector3.UP*1.57,hale.basis.z))
	var was_locked:=demo_locked
	var active_single:=count==1 and self_sees and in_b3
	if active_single:
		if demo_single_time==0. and not learned:
			backed_off=true;line_once("red","转红了！快移开视线——守则不会骗人的！")
			board_audio.stream=sounds.hum;board_audio.play()
		demo_single_time+=dt
	else:demo_single_time=0.
	demo_locked=demo_single_time>=GAZE_LOCK_TIME
	if demo_locked and not was_locked and not learned:sound_at("set",board_audio.position,-7.)
	if not learned and in_b3:
		if p.z<10.45 or p.y<-.10 or (p.z<13.4 and not active_single):
			crossing=false;crossing_locked=false
		if absf(p.x-23.85)<.92 and p.z>10.48 and p.z<12.8 and p.y>=0 and active_single:crossing=true
		if crossing and demo_locked:crossing_locked=true
		if crossing_locked and p.z>=13.65 and p.y>=0 and count<2:
			learned=true;kit.evidence_gate.position.y=4.
			line_once("evidence","等等……你一直盯着它，它反而稳住了？守则明明写着严禁直视。")
			evidence_thought_delay=.68;sound_at("ink",p+Vector3.UP,-11.)
			toast("随身手册已新增批注  [1]")
	var changed:=count!=observers;observers=count
	demo_grace=1. if count else maxf(0.,demo_grace-dt)
	var faded:=count==0 and demo_grace<=0.
	var board:=kit.test_board as MeshInstance3D;var body:=board.get_child(0) as StaticBody3D
	body.collision_layer=0 if faded else 3
	var gather:=smoothstep(.38,GAZE_LOCK_TIME,demo_single_time)
	sight_blend=move_toward(sight_blend,gather if active_single else .24 if count==1 else 0.,dt*2.8)
	overload_blend=move_toward(overload_blend,1. if count==2 else 1.-gather if active_single else 0.,dt*4.8)
	plate_presence=move_toward(plate_presence,.20 if faded else 1.,dt*2.)
	plate_finish.set_shader_parameter("sight",sight_blend)
	plate_finish.set_shader_parameter("overload",overload_blend)
	plate_finish.set_shader_parameter("presence",plate_presence)
	board.position.y=move_toward(board.position.y,-.55 if faded else .045,dt*1.8)
	board.position.x=23.85+.014*overload_blend*sin(phase*42.)
	if changed and count==2:
		sound_at("spring",board_audio.position,-9.)
		if in_b3:
			backed_off=true;line_once("double","两道目光交在一起了！移开视线！")
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
	shortcut_open=false;shortcut_used=false;shortcut_time=0.;exit_requested=false;exit_open=false;reunited=false;evidence_thought_delay=-1.;cues.erase("bait_answer")
	kit.leave_pivot.rotation.y=0.;kit.airlock.position.y=2.4;hale_return_path.clear()
	hale_gate_attempt=false;hale.rotation.x=0.
	crossing=false;crossing_locked=false;distraction=0.;running=false;collected=false;kit.core.show();siren.stop();emergency.hide();cues.erase("core");cues.erase("post");captions.clear()
	if released:hunter.wake();oil=checkpoint_oil;equipped=checkpoint_item
	walker.position=Vector3(38.6,.15,10) if released else Vector3(1,.1,0);walker.velocity=Vector3.ZERO;hale.position=walker.position+Vector3(.1,0,.7);polish.reset_beat();hazard=0;holding=false;posting=false;trail.clear();command_path.clear()
func observation()->Dictionary:return {"phase":"first_expedition","section":mode,"position":str(walker.position),"checkpoint":released,"learned":learned,"core":collected,"hale_posted":holding}

func review_props()->void:
	var ground:=PlaneMesh.new();ground.size=Vector2(400,400);plinth.mesh=ground;var g:=StandardMaterial3D.new();g.albedo_color=Color("a0998e");plinth.material_override=g;add_child(plinth);plinth.hide()
	add_child(review_witness);review_witness.position=kit.polar(12.45,PI*1.5,4.8);Cast.attach(review_witness,1);review_witness.rotation.y=PI
	var cone:=MeshInstance3D.new();var mesh:=CylinderMesh.new();var target:=Vector3(61,.05,10.1);var top:=review_witness.position+Vector3.UP*1.6;mesh.height=top.distance_to(target);mesh.top_radius=.025;mesh.bottom_radius=1.45;cone.mesh=mesh;var m:=StandardMaterial3D.new();m.transparency=BaseMaterial3D.TRANSPARENCY_ALPHA;m.shading_mode=BaseMaterial3D.SHADING_MODE_UNSHADED;m.albedo_color=Color(.18,.75,.77,.27);cone.material_override=m;review_witness.add_child(cone);cone.global_position=(target+top)*.5;cone.global_basis=Basis(Quaternion(Vector3.UP,(top-target).normalized()));review_witness.hide()
	warning.stream=Sound.SPRING;warning.volume_db=-9.;warning.position=Vector3(61,1,10.1);add_child(warning)
