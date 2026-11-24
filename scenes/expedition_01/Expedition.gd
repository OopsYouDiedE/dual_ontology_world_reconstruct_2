extends Node3D
signal returned
# Read-only test observer; no listeners during ordinary play.
signal audit_action(kind:String, detail:String)
const Kit=preload("ExpeditionKit.gd")
const Relay=preload("ServiceSignal.gd")
const OIL_PICKUP:=35.
const Cast=preload("res://scenes/rogue_crossing/ProductionCast.gd")
const R18n=preload("res://scenes/components/shared/R18n.gd")
const Feel=preload("res://scenes/components/shared/FeelProfile.gd")
const RenderProfile=preload("res://scenes/components/rendering/AcademyRenderProfile.gd")
var kit:=Kit.new()
var walker:=CharacterBody3D.new()
var eye:=Camera3D.new()
var survey:=Camera3D.new()
var hale:=Node3D.new()
var trail:=PackedVector3Array()
var hud:=Label.new() # Route diagnostics only (F3).
var review_hud:=Label.new()
var book_controls:=Label.new()
var plinth:=MeshInstance3D.new()
var review_witness:=Node3D.new()
var warning:=AudioStreamPlayer3D.new()
var hunter:=preload("AuditoryStalker.gd").new()
var manual:=PanelContainer.new()
var page:=RichTextLabel.new()
var book_page:=0
var caption_toast:=Label.new()
var toast_time:=0.
var lantern:=OmniLight3D.new()
var hale_lantern:=OmniLight3D.new()
var hale_prop:Node3D
var hale_rig:Skeleton3D
var hale_hand:=-1
var north_beacon:=OmniLight3D.new()
const NORTH_READY_NOTICE:="北窗的灯亮了。"
var north_ready_signaled:=false
var ambient_bed:=AudioStreamPlayer.new()
var player_lamp:Node3D
var darkroom_mix:=0.
var evidence_thought_delay:=-1.
var demo_single_time:=0.
var demo_locked:=false
var archive:=preload("ArchiveWitness.gd").new()
const GAZE_LOCK_TIME:=2.35
# --- movement feel ---------------------------------------------------------
enum { ST_QUIET, ST_WALK, ST_RUN }
const SPEEDS := [1.55, 3.8, 6.4]
const ACCEL_GROUND:=26.
const ACCEL_TURN:=52.
const ACCEL_STOP:=34.
const ACCEL_QUIET:=44.
const AIR_CONTROL:=.20
const STEP_HEIGHT:=.19
const JUMP_SPEED:=4.35
const COYOTE:=.12
const GRAVITY_RISE:=15.5
const GRAVITY_FALL:=19.5
var stance:=ST_WALK
var stance_blend:=1.
var jump_buffer:=0.
var coyote:=0.
var aim:=0.
var aiming:=false
var land_dip:=0.
var last_vy:=0.
var air_peak:=0.
var _lamp_sway:=Vector2.ZERO
var _lamp_prev_yaw:=0.
var _lamp_prev_pitch:=0.
var catwalk_oil_grace:=0.
var trust_line_cd:=0.
var wheel:Node=preload("CommandWheel.gd").new()
var wheel_open:=false
var mouse_lifecycle:=preload("ExpeditionMouse.gd").new()
const Contracts=preload("ExpeditionContracts.gd")
var contracts:=Contracts.new()
var region:=""
var niche_taken:=false
var region_card_time:=0.
var fail_reason:=""
var prior_seer:=Contracts.Seer.NONE
var hale_stuck:=0.
const HALE_TURN_RATE:=TAU # radians per second
const HALE_FACE_SPEED:=.35
var hale_chasing:=false
var hale_yielded:=false
var hale_yield_left:=0.
var hale_yield_dir:=Vector3.ZERO
var hale_yaw_before_step:=0.
var hale_face_motion:=true
var hale_last:=Vector3.ZERO
var rule_breach_flash:=0.
const HALE_WAIT:=Vector3(1.12,0.,1.19)
const HALE_ENTER:=Vector3(-2.87,0.,.87)
var plate_finish:=ShaderMaterial.new()
var sight_blend:=0.
var overload_blend:=0.
var plate_presence:=1.
var plate_spill:=OmniLight3D.new()
var prompt:=Label.new()
var prompt_notice:=Label.new()
var read_book:=false
var running:=false
var subtitle_id:=""
var crossing:=false
var crossing_locked:=false
var trial_near_bank:=false
var crossing_in_hale_view:=false
var checkpoint_oil:=65.
var checkpoint_item:=false
var metal_foot:=AudioStreamPlayer3D.new()
var metal_beat:=0.
var emergency:=OmniLight3D.new()
var siren:=AudioStreamPlayer3D.new()
var gallery_bell:=AudioStreamPlayer.new()
var gallery_impact:=AudioStreamPlayer.new()
var gallery_tail:=0.
var north_pause:=0.
var left_north_window:=false
var halo:=OmniLight3D.new()
var finished:=false
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
const HALE_GATE_DURATION:=1.14
var hale_gate_effort:=0.
# Stand east of the green doorway, clear of both its mouth and the hall center.
const HALE_ARCHIVE_LOOKOUT:=Vector3(32.65,0.,1.28)
var hale_gate_guide:=0
var hale_gate_guide_wait:=0.
var hale_speed:=0.
var hale_loco:AnimationNodeStateMachinePlayback
var hale_clip:=&""
var watch_route:=PackedVector3Array()
var hale_return_path:=PackedVector3Array()
var shortcut_open:=false
var return_started:=false
var return_gate_open:=false
var shaft_mix:=0.
var shaft_bed:=AudioStreamPlayer.new()
var score:=AudioStreamPlayer.new()
var shortcut_used:=false
var exit_open:=false
var reunited:=false
var exit_requested:=false
var learned:=false
var released:=false
var collected:=false
var equipped:=false
var taken:=false
var clock_taken:=false
var service_signal:=Relay.new()
var relay_focus:=-1
var mcp_controls:=false
var posting:=false
var holding:=false
var command_path:=PackedVector3Array()
var oil:=65.0
var distraction:=0.
var hazard:=0
var lamp_on:=true
var run_time:=0.
var pair_loud:=false
var both_lamp:=false
var stomp_cool:=0.
var hale_hold:=false
var solo_escape:=false
const SOLO_HATCH:=Vector3(-2.6,1.4,1.34)
const STELE_A:=Vector3(31.5,1.5,17.40)
const STELE_B:=Vector3(52.3,2.04,22.47)
const STELE_TEXT:={
	"sound":"其一 · 同声律　井底只数声音，不数人头。两个人的脚步叠在一起，它会当成一顿饭——一个人走，另一个站着听。",
	"light":"其二 · 独灯律　井里只许点一盏灯。两盏灯芯一起爆响，井底会听成两个人的脚步。熄掉自己那盏，借同伴的光走。"}
const HALE_TALK:={
	"talk_rules":"手册别离手。这地方的规矩，比墙还厚。",
	"talk_b4":"这些是前班的字。我认得抄表人的笔迹。",
	"talk_well":"慢一点。你那边脚下稳吗？",
	"talk_exit":"你先走，我跟在后头。",
	"talk_idle":"……你还好吗？我们得赶在天亮前出去。"}
var retry:=0.
var notice:=""
var msg_time:=0.
var last_pos:=Vector3.ZERO
func _ready()->void:
	add_child(kit);kit.build();light_stage();review_props()
	var c:=CollisionShape3D.new();var shape:=CapsuleShape3D.new();shape.radius=.32;shape.height=1.75;c.shape=shape;c.position.y=.875;walker.add_child(c);walker.floor_max_angle=deg_to_rad(60);walker.floor_constant_speed=true;walker.floor_snap_length=.28;add_child(walker);walker.position=Vector3(1,.03,0);walker.rotation.y=-PI/2;walker.add_child(eye);eye.position.y=1.57;eye.fov=73;eye.current=true
	add_child(hale);Cast.attach(hale,1,true);setup_hale_animation();hale.position=Vector3(3.15,0,1.22);hale.rotation.y=PI*.5;add_child(survey);survey.far=600;survey.projection=Camera3D.PROJECTION_ORTHOGONAL
	var canvas:=CanvasLayer.new();canvas.layer=8;add_child(canvas);canvas.add_child(hud);hud.position=Vector2(22,17);hud.add_theme_font_size_override("font_size",17);hud.add_theme_constant_override("outline_size",6)
	for a in ["expedition_quiet","expedition_use","expedition_section","expedition_watch","expedition_shell","expedition_detail","expedition_hop","expedition_lamp","expedition_stomp"]:
		if not InputMap.has_action(a):InputMap.add_action(a)
	mouse_lifecycle.release()
	mouse_lifecycle.set_focused(get_window().has_focus())
	get_window().focus_entered.connect(_on_focus_entered)
	get_window().focus_exited.connect(_release_focus)
	var font:=Polish.make_font()
	hud.add_theme_font_override("font",font);hud.mouse_filter=Control.MOUSE_FILTER_IGNORE
	canvas.add_child(review_hud);review_hud.position=hud.position;review_hud.hide()
	review_hud.add_theme_font_override("font",font);review_hud.add_theme_constant_override("outline_size",6)
	review_hud.mouse_filter=Control.MOUSE_FILTER_IGNORE
	canvas.add_child(captions);captions.setup(font)
	canvas.add_child(caption_toast);caption_toast.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT)
	caption_toast.offset_left=-460.;caption_toast.offset_top=-176.;caption_toast.offset_right=-28.;caption_toast.offset_bottom=-140.
	caption_toast.horizontal_alignment=HORIZONTAL_ALIGNMENT_RIGHT
	caption_toast.mouse_filter=Control.MOUSE_FILTER_IGNORE
	caption_toast.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
	caption_toast.add_theme_font_override("font",font);caption_toast.add_theme_font_size_override("font_size",17)
	caption_toast.add_theme_constant_override("outline_size",6);caption_toast.hide()
	plate_finish.shader=preload("GazePlate.gdshader");kit.test_board.material_override=plate_finish
	add_child(plate_spill);plate_spill.position=Vector3(23.85,1.2,11.75)
	plate_spill.light_color=Color("ec512e");plate_spill.omni_range=4.4;plate_spill.omni_attenuation=2.1;plate_spill.light_energy=0.
	player_lamp=Node3D.new();eye.add_child(player_lamp);player_lamp.position=Vector3(.34,-.42,-.25)
	player_lamp.add_child(lantern);lantern.position=Vector3(0,.065,-.08)
	lantern.light_color=Color("ffd09b");lantern.shadow_enabled=true
	RenderProfile.tune_omni_light(lantern,"lantern")
	_lamp_prev_yaw=walker.rotation.y;_lamp_prev_pitch=eye.rotation.x
	hale_prop=build_lantern(Vector3(-.27,1.06,.27));hale_prop.hide()
	hale_rig=hale.get_meta("skeleton");hale_hand=hale_rig.find_bone("hand_l")
	hale_prop.add_child(hale_lantern);hale_lantern.position=Vector3(0,.08,.13)
	hale_lantern.light_color=Color("f6c184");hale_lantern.omni_range=3.6;hale_lantern.light_energy=.42
	add_child(north_beacon);north_beacon.position=kit.north_spot.global_position+Vector3(.38,1.8,-.9)
	north_beacon.light_color=Color("ffca80");north_beacon.omni_range=3.5;north_beacon.light_energy=.85;north_beacon.hide()
	kit.section=kit.get_child(0);kit.plaque("锚定厅 · 稳压区",Vector3(.25,2.94,0),1.62,PI*.5)
	kit.section=kit.get_child(2);kit.plaque("北窗",kit.polar(10.9,1.5*PI,6.82),.68)
	sounds=Sound.clips()
	add_child(ambient_bed);ambient_bed.stream=sounds.ambience;ambient_bed.volume_db=-26.;ambient_bed.play()
	add_child(shaft_bed);shaft_bed.stream=sounds.shaft;shaft_bed.volume_db=-70.;shaft_bed.play()
	add_child(score);score.stream=sounds.cello;score.volume_db=-70.
	sound_at("opening_tail",Vector3(-.58,1.15,0),-24.,9.)
	add_child(gallery_bell);gallery_bell.stream=sounds.gallery_bell
	add_child(gallery_impact);gallery_impact.stream=sounds.gallery_impact
	add_child(foot);add_child(chime);add_child(board_audio);foot.volume_db=-21;chime.volume_db=-14;board_audio.position=Vector3(23.85,.4,12.02);board_audio.max_distance=12;board_audio.volume_db=-9
	for pos in [Vector3(23.6,2.1,4.),Vector3(24.65,2.7,8.1),Vector3(20.95,2.25,9.05),Vector3(23.85,2.4,12),Vector3(36.3,2.4,8.2),Vector3(.8,2.55,0)]:
		var lamp:=OmniLight3D.new();lamp.position=pos;lamp.omni_range=4.;lamp.light_energy=.62;lamp.light_color=Color("ffebc5");lamp.omni_attenuation=1.3;lamp.shadow_enabled=true;lamp.shadow_bias=.035;lamp.shadow_normal_bias=.42;add_child(lamp)
	var annex:=OmniLight3D.new();add_child(annex);annex.position=Vector3(-3.4,2.22,0)
	annex.omni_range=6.2;annex.light_energy=2.4;annex.light_color=Color("ffc475");annex.shadow_enabled=true
	for marker in kit.find_children("GalleryLamp*","Marker3D",true,false):
		var service_light:=OmniLight3D.new();add_child(service_light);service_light.position=marker.global_position
		service_light.omni_range=6.;service_light.light_energy=.81;service_light.light_color=Color("ffd99d");service_light.shadow_enabled=true
		service_light.shadow_bias=.06;service_light.shadow_normal_bias=.5
	add_child(hunter);hale.add_child(metal_foot);metal_foot.stream=sounds.iron;metal_foot.volume_db=-12;add_child(siren);siren.position=Vector3(73.15,5.25,9.25);siren.max_distance=24.;siren.volume_db=-17.
	add_child(halo);halo.position=Vector3(31,2.1,2.9);halo.light_color=Color("ffbd70");halo.omni_range=6;halo.light_energy=1.4;halo.shadow_enabled=true
	add_child(emergency);emergency.position=Vector3(73.15,5.25,9.25);emergency.light_color=Color("ff5234");emergency.omni_range=5.6;emergency.omni_attenuation=1.7;emergency.hide()
	canvas.add_child(prompt);prompt.set_anchors_and_offsets_preset(Control.PRESET_CENTER);prompt.offset_left=-320;prompt.offset_right=320;prompt.offset_top=23;prompt.offset_bottom=68;prompt.vertical_alignment=VERTICAL_ALIGNMENT_TOP;prompt.add_theme_font_size_override("font_size",19);prompt.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER;prompt.add_theme_font_override("font",font);prompt.add_theme_constant_override("outline_size",6);prompt.mouse_filter=Control.MOUSE_FILTER_IGNORE
	canvas.add_child(prompt_notice);prompt_notice.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	prompt_notice.offset_left=-340;prompt_notice.offset_right=340;prompt_notice.offset_top=52;prompt_notice.offset_bottom=80
	prompt_notice.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER
	prompt_notice.add_theme_font_override("font",font);prompt_notice.add_theme_font_size_override("font_size",16)
	prompt_notice.add_theme_constant_override("outline_size",6)
	prompt_notice.add_theme_color_override("font_color",Color("ffcf9a"))
	prompt_notice.mouse_filter=Control.MOUSE_FILTER_IGNORE;prompt_notice.hide()
	canvas.add_child(manual);manual.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	manual.offset_left=-305;manual.offset_right=305;manual.offset_top=-194;manual.offset_bottom=194
	var paper:=StyleBoxFlat.new();paper.bg_color=Color("e3cda2");paper.border_color=Color("63472b");paper.set_border_width_all(3)
	paper.set_corner_radius_all(4);paper.shadow_color=Color(0,0,0,.7);paper.shadow_size=20
	paper.content_margin_left=34;paper.content_margin_right=34;paper.content_margin_top=28;paper.content_margin_bottom=22
	manual.add_theme_stylebox_override("panel",paper);manual.add_child(page);page.bbcode_enabled=true;page.scroll_active=false
	page.add_theme_font_override("normal_font",font);page.add_theme_font_override("bold_font",font)
	page.add_theme_color_override("default_color",Color("31241a"));page.add_theme_font_size_override("normal_font_size",18)
	page.add_theme_font_size_override("bold_font_size",22);manual.hide()
	canvas.add_child(book_controls);book_controls.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	book_controls.offset_left=-380.;book_controls.offset_right=380.;book_controls.offset_top=201.;book_controls.offset_bottom=282.
	book_controls.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER
	book_controls.mouse_filter=Control.MOUSE_FILTER_IGNORE
	book_controls.add_theme_font_override("font",font);book_controls.add_theme_font_size_override("font_size",15)
	book_controls.add_theme_constant_override("outline_size",6);book_controls.hide()
	add_child(polish);polish.setup(self,canvas)
	add_child(wheel);wheel.setup(canvas,font)
	wheel.chosen.connect(pick_order)
	contracts.reset()
	update_target()
	toast(R18n.t("hud.start_toast"))
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--rogue-mcp-dir="):mcp_controls=true
	if mcp_controls:
		for action in ["expedition_look_left","expedition_look_right","expedition_look_up","expedition_look_down"]:
			if not InputMap.has_action(action):InputMap.add_action(action)
		if OS.get_cmdline_user_args().has("--expedition-b4-review"):
			read_book=true
			cues["start"]=true;cues["gate"]=true
			walker.position=Vector3(28.40,.03,14.06);hale.position=Vector3(26.9,0,14.06)
func toggle_book()->void:
	_release_mouse()
	if wheel_open:_close_wheel()
	manual.visible=not manual.visible;read_book=true
	if manual.visible:
		book_page=0;render_book();toast_time=0.;caption_toast.hide()
		captions.clear();evidence_thought_delay=-1.
		play_ui("page",-19.)
	else:play_ui("book_close",-19.)
	prompt.visible=not manual.visible;prompt_notice.visible=not manual.visible and prompt_notice.text!=""
	captions.visible=not manual.visible;book_controls.visible=manual.visible;polish.on_book(manual.visible)
	polish.sync_debug_visibility()
func render_book()->void:
	var pages:=contracts.manual_pages(archive.note,cues.has("stele_sound"),cues.has("stele_light"))
	page.text=str(pages[clampi(book_page,0,pages.size()-1)])
	if book_page==4 and cues.has("stele_sound") and cues.has("stele_light"):page.append_text("\n\n两处刻文均已核对。")
	book_controls.text=R18n.t("hud.book_controls")
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
	audit_action.emit("feedback",text)
	caption_toast.text=text;caption_toast.show();toast_time=captions.reading_time(text)
# Keep close-range distance gain from turning small mechanical cues into stingers.
const CLOSE_CUE_CAPS := {"opening_tail": -17., "gate": -8., "airlock": -8., "relay_tap": -16., "relay_answer": -12.}
func sound_at(kind:String,pos:Vector3,db:float,distance:=90.)->void:
	var audio:=AudioStreamPlayer3D.new();add_child(audio);audio.position=pos;audio.stream=sounds[kind]
	audio.volume_db=db;audio.max_distance=distance
	if kind.begins_with("relay_"):audio.unit_size=2.
	if CLOSE_CUE_CAPS.has(kind):audio.max_db=CLOSE_CUE_CAPS[kind]
	audio.finished.connect(audio.queue_free);audio.play()
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
func _release_mouse()->void:
	mouse_lifecycle.release()
	aiming=false

func _on_focus_entered()->void:
	mouse_lifecycle.set_focused(true)

func _release_focus()->void:
	mouse_lifecycle.set_focused(false)
	aiming=false

func _exit_tree()->void:
	get_window().focus_entered.disconnect(_on_focus_entered)
	get_window().focus_exited.disconnect(_release_focus)
	_release_focus()

func _close_wheel(confirm:=false)->void:
	wheel_open=false
	_release_mouse()
	if confirm:wheel.confirm()
	else:wheel.dismiss()

func _unhandled_input(ev:InputEvent)->void:
	if finished or manual.visible or wheel_open or mode>=0:return
	if mouse_lifecycle.capture_world_click(ev,get_viewport()):
		get_viewport().set_input_as_handled()

func _input(ev:InputEvent)->void:
	if finished:return
	var key:=0
	if ev is InputEventKey and ev.pressed and not ev.echo:key=ev.physical_keycode
	if key==KEY_F3:
		polish.toggle_debug();get_viewport().set_input_as_handled();return
	if key==KEY_F8:
		R18n.toggle_locale()
		if manual.visible:render_book()
		update_target()
		toast(R18n.t("hud.lang_switched"))
		get_viewport().set_input_as_handled();return
	var watch:=key==KEY_Q or ev.is_action_pressed("expedition_watch")
	if key==KEY_ESCAPE:
		_release_mouse()
		if manual.visible:toggle_book()
		if wheel_open:_close_wheel()
		get_viewport().set_input_as_handled()
		return
	if key==KEY_I or watch:_release_mouse()
	if ev is InputEventKey and ev.pressed and not ev.echo and mode<0:
		if key==KEY_I or (not wheel_open and key in [KEY_1,KEY_KP_1]):
			toggle_book();get_viewport().set_input_as_handled();return
		if ev.physical_keycode==KEY_SHIFT and not manual.visible:running=not running;return
	if manual.visible:
		if ev is InputEventKey and ev.pressed and not ev.echo and ev.physical_keycode in [KEY_LEFT,KEY_RIGHT]:
			book_page=posmod(book_page+(1 if ev.physical_keycode==KEY_RIGHT else -1),5);render_book();play_ui("page",-19.)
		return
	# Right mouse / LT is the steady-hand stance: half sensitivity, tighter FOV.
	if ev is InputEventMouseButton and ev.button_index==MOUSE_BUTTON_RIGHT:
		aiming=ev.pressed and mouse_lifecycle.focused and not wheel_open and mode<0;return
	if ev is InputEventJoypadButton and ev.button_index==JOY_BUTTON_LEFT_SHOULDER:
		aiming=ev.pressed;return
	if ev is InputEventMouseMotion and mode<0 and Input.mouse_mode==Input.MOUSE_MODE_CAPTURED:
		var gain:=look_sens*Feel.aim_gain_scale(aim)
		walker.rotate_y(-ev.relative.x*gain);eye.rotation.x=clampf(eye.rotation.x-ev.relative.y*gain,-1.48,1.48)
	if wheel_open and ev is InputEventMouseButton and ev.pressed and ev.button_index in [MOUSE_BUTTON_WHEEL_UP,MOUSE_BUTTON_WHEEL_DOWN]:
		wheel.move(-1 if ev.button_index==MOUSE_BUTTON_WHEEL_UP else 1)
		get_viewport().set_input_as_handled();return
	if key==KEY_F4 or ev.is_action_pressed("expedition_section"):section_view();return
	if mode>=0:
		if key==KEY_F6 or ev.is_action_pressed("expedition_detail"):detail_camera();return
		if key==KEY_F5 or ev.is_action_pressed("expedition_shell"):shell_closed=not shell_closed;show_shell()
		return
	if key==KEY_BRACKETLEFT or key==KEY_BRACKETRIGHT:
		look_sens=clampf(look_sens*(1.12 if key==KEY_BRACKETRIGHT else 1./1.12),.0008,.006);say(R18n.t("hud.sens",[roundi(look_sens/.0022*100.)]));return
	if wheel_open:
		if key in [KEY_1,KEY_2,KEY_3,KEY_4,KEY_5]:wheel.index=clampi(key-KEY_1,0,maxi(0,wheel.options.size()-1));_close_wheel(true);return
		if watch:_close_wheel();return
		if key==KEY_E or key==KEY_ENTER:_close_wheel(true)
		return
	if retry<=0 and (key==KEY_SPACE or ev.is_action_pressed("expedition_hop")):jump_buffer=.16;return
	if retry<=0 and (key==KEY_R or ev.is_action_pressed("expedition_lamp")):toggle_lamp();return
	if retry<=0 and (key==KEY_F or ev.is_action_pressed("expedition_stomp")):stomp();return
	if key==KEY_E or ev.is_action_pressed("expedition_use"):use()
	if watch:
		if focus()=="hale":order();return
		var items:=order_options()
		if items.size()>1:
			wheel.bind(items);wheel.reveal();wheel_open=true
		elif items.size()==1:pick_order(items[0].id)
		return
	if key==KEY_ALT:
		if not manual.visible:toggle_book()
		book_page=3;render_book();return
func section_view()->void:
	_release_mouse()
	if wheel_open:_close_wheel()
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
func say(t:String)->void:
	notice=t;msg_time=4.
	audit_action.emit("feedback",t)
func toggle_lamp()->void:
	lamp_on=not lamp_on
	play_ui("cue",-16.)
	say("提灯已熄。" if not lamp_on else "提灯亮了。")
	if not lamp_on and released and walker.position.x>46. and not in_return_gallery(walker.position):
		line_once("lamp_off","熄灯了？……好，我这盏够我们俩走。")
func stomp()->void:
	if stomp_cool>0.:return
	stomp_cool=6.
	audit_action.emit("confirmed","跺脚")
	foot.stream=sounds.iron;foot.pitch_scale=.88;foot.volume_db=-7.;foot.play()
	polish.kick(.14)
	if released and walker.position.x>46. and not in_return_gallery(walker.position):
		hunter.probe(walker.position)
		if hunter.state=="hunt":say("脚步声越来越近。")
		else:
			say("井底传来脚步声。")
			line_once("stomp_warn","你跺什么脚？把它招过来，我们俩都得交代在这！")
	else:say("跺脚声在拱廊里回荡。")
func read_stele(kind:String)->void:
	var id:="stele_"+kind
	if cues.has(id):say("刻板上的字你已经记下了。");return
	cues[id]=true
	play_ui("ink",-14.)
	var rule_text:String=STELE_TEXT["sound"] if kind=="sound" else STELE_TEXT["light"]
	captions.post(id,"",rule_text)
	polish.letterbox(captions.reading_time(rule_text)+.3)
	if cues.has("stele_sound") and cues.has("stele_light"):
		toast("两处刻文已誊入手册")
func talk_to_hale()->void:
	if hale.position.distance_to(walker.position)>5.5:return
	var id:="talk_idle"
	if collected:id="talk_exit"
	elif released and walker.position.x>46.:id="talk_well"
	elif in_b4(walker.position):id="talk_b4"
	elif not learned:id="talk_rules"
	if cues.has(id):id="talk_idle"
	if cues.has("talk_idle") and id=="talk_idle":
		say("Hale 朝你点了点头，没有说话。");return
	line_once(id,HALE_TALK[id])
func hale_order_text()->String:
	if posting:return R18n.t("hale.posting")
	if holding:return R18n.t("hale.holding")
	if hale_hold:return R18n.t("hale.hold")
	if hale_gate_attempt:return R18n.t("hale.gate")
	return R18n.t("hale.follow")
func thought(id:String,text:String)->void:
	subtitle_id=id;captions.post(id,"",text)
func near(p:Vector3,d:=2.1)->bool:return walker.position.distance_to(p)<d
func in_b4(p:Vector3)->bool:
	return (p.x>27.8 and p.x<41.8 and p.z>13.05 and p.z<=15.2) or (p.x>28.5 and p.x<40.5 and p.z>15.2 and p.z<17.68)
func aimed(pos:Vector3,reach:float,cone:=.96)->bool:
	var delta:=pos-eye.global_position
	if delta.length()>reach or (-eye.global_basis.z).dot(delta.normalized())<cone:return false
	var hit:=get_world_3d().direct_space_state.intersect_ray(PhysicsRayQueryParameters3D.create(eye.global_position,pos,2))
	return hit.is_empty() or Vector3(hit.position).distance_to(pos)<.65
func focus()->String:
	relay_focus=-1
	if walker.position.z>16.12 and walker.position.y>.48:
		if service_signal.open and not clock_taken and aimed(Relay.HATCH,1.85,.92):return "clock"
		if not service_signal.open:
			for i in Relay.PORTS.size():
				if aimed(Relay.PORTS[i],1.48,.94):relay_focus=i;return "relay"
			if aimed(Relay.HATCH,1.65,.94):return "clock_locked"
	if not released and walker.position.x<35.9 and aimed(Vector3(36.,1.57,0),2.,.91):return "gate"
	if not taken and walker.position.z<15.2 and aimed(Vector3(34.14,.5,14.67),2.8):return "loot"
	if aimed(Vector3(23.6,1.03,4),2.8):return "note"
	if not niche_taken and aimed(Vector3(13.9,.62,5.9),2.6,.93):return "niche_oil"
	if not released and aimed(Vector3(36.3,1.35,7.72),3.):return "lever"
	if released and not collected and aimed(kit.core.position,2.8):return "core"
	if collected and not shortcut_open and aimed(kit.leaf.global_position,3.5,.94):return "return"
	if collected and not exit_open and walker.position.x>=0. and aimed(Vector3(.37,1.5,0),3.):return "exit"
	if released and walker.position.x>47.45 and near(Vector3(49,0,10),4.5) and aimed(kit.polar(12.45,1.5*PI,6.42),24,.976):return "north"
	if equipped and walker.position.x>46:
		var landing:Variant=Plane(Vector3.UP,hunter.CENTER.y).intersects_ray(eye.global_position,-eye.global_basis.z)
		if landing!=null and landing.distance_to(hunter.CENTER)<13.:return "throw"
	if not solo_escape and exit_open and walker.position.x<0. and aimed(SOLO_HATCH,2.6,.93):return "solo_exit"
	if aimed(STELE_A,2.4,.93):return "stele1"
	if kit.vault_can.visible and aimed(kit.vault_can.global_position,2.4,.94):return "vault_oil"
	if aimed(STELE_B,2.6,.93):return "stele2"
	if mode<0:
		var maintenance_target:=kit.maintenance.target(eye,walker)
		if maintenance_target!="":return maintenance_target
	if hale.visible and mode<0:
		var hd:=hale.position+Vector3.UP*1.25-eye.global_position
		var hd_len:=hd.length()
		if hd_len<5.5 and (-eye.global_basis.z).dot(hd.normalized())>.965:
			var hale_hit:=get_world_3d().direct_space_state.intersect_ray(PhysicsRayQueryParameters3D.create(eye.global_position,hale.position+Vector3.UP*1.25,2))
			# 命中点若在 Hale 身前（有墙隔开）则不给指令；穿过或打在他身上都算看得见。
			if hale_hit.is_empty() or Vector3(hale_hit["position"]).distance_to(eye.global_position)>=hd_len-.35:return "hale"
	return ""
func use()->void:
	if retry>0 or manual.visible:return
	var target:=focus()
	audit_action.emit("use",target)
	if target!="":polish.kick(.07)
	match target:
		"maintenance_lift","maintenance_oil":kit.maintenance.operate(target,self)
		"gate":
			polish.kick(.22)
			sound_at("gate",Vector3(36.,1.46,0),-14.,12.)
			thought("gate_test","闸门一点都推不动。")
			confirm_gate_locked()
		"note":captions.post("archive_note","残页","观察窗一直关着。抄表时我抬了下头，玻璃外那块板忽然起了波纹。")
		"niche_oil":
			if Vector2(walker.velocity.x,walker.velocity.z).length()>.85:
				say("先站稳，再把油壶提起来。")
				return
			niche_taken=true;oil=minf(100.,oil+24.);kit.niche_oil.hide()
			play_ui("cue",-16.);toast("已补充灯油。")
			contracts.award("niche_quiet")
			show_line("niche","还有油？给我看看壶底漏不漏。")
		"loot":
			taken=true;oil=minf(100.,oil+OIL_PICKUP);kit.oil_tin.hide()
			if released:checkpoint_oil=minf(100.,checkpoint_oil+OIL_PICKUP)
			play_ui("cue",-16.);toast("已收起灯油。")
		"clock":
			clock_taken=true;equipped=true;kit.clock_cache.hide();play_ui("cue",-16.)
			if released:checkpoint_item=true
			toast("已收起节拍器。")
		"relay":use_relay(relay_focus)
		"lever":
			if released or focus()!="lever":return
			archive.facts.decide("master_release",true,"player operated the B5 lever")
			hale_gate_attempt=false
			create_tween().tween_property(kit.shaft_shutter,"position:y",4.66,.90)
			released=true;polish.gate_lift(kit.gate);checkpoint_oil=oil;checkpoint_item=equipped;hunter.wake();polish.kick(.5);polish.punch(-5.);sound_at("lever",kit.panel.position,-4.);sound_at("chain",Vector3(36.,2.,0.),-3.);thought("release","主闸那边传来链条声。")
		"core":
			left_north_window=holding
			collected=true;begin_hale_return();polish.kick(.32);polish.punch(-4.);kit.core.hide();emergency.show();siren.stream=sounds.alarm;siren.play()
			thought("core","警报响了。得找条路回主廊。")
		"return":
			shortcut_open=true;polish.kick(.38);sound_at("escape",kit.leaf.global_position,-5.)
			create_tween().set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT).tween_property(kit.leave_pivot,"rotation:y",1.43,.42)
		"exit":
			exit_open=true;create_tween().tween_property(kit.airlock,"position:y",5.4,.45)
			sound_at("airlock",Vector3(.1,1.45,0),-6.)
		"solo_exit":
			solo_escape=true;polish.kick(.3);polish.punch(-4.)
			sound_at("airlock",SOLO_HATCH,-6.)
			if kit.solo_hatch:create_tween().tween_property(kit.solo_hatch,"position:y",kit.solo_hatch.position.y+2.05,.40)
			var solo_tw:=create_tween()
			solo_tw.tween_interval(.5)
			solo_tw.tween_callback(func()->void:finish_expedition(true))
		"vault_oil":
			oil=minf(100.,oil+20.);kit.vault_can.hide();say("已收起备用灯油")
		"stele1":read_stele("sound")
		"stele2":read_stele("light")
		"hale":talk_to_hale()
		"throw":
			equipped=false;polish.kick(.14);polish.punch(-2.);distraction=12.
			hunter.throw_from(eye.global_position,-eye.global_basis.z)
			if contracts.b_pardon():
				toast("井底的脚步声远了。")
				show_line("pardon","脚步声远了。趁现在，轻点走。")
	update_target()
func use_relay(port:int)->void:
	if service_signal.pending():return
	if service_signal.heard and port==service_signal.target():
		service_signal.open=true
		create_tween().tween_property(kit.clock_shutter,"position:y",Relay.HATCH.y+.54,.40)
		sound_at("lever",Relay.HATCH,-16.,6.)
		set_relay_lamp(2,true)
		toast("中央柜门已打开。")
		return
	if not service_signal.on_felt(walker.position,port):
		toast("毡垫能压住脚音。")
		return
	set_relay_lamp(0,false);set_relay_lamp(1,false)
	service_signal.strike(port)
	sound_at("relay_tap",Relay.PORTS[port],-14.,6.)
	toast("等一等，听回声……")
func set_relay_lamp(id:int,active:bool)->void:
	var finish:=kit.relay_lamps[id].material_override as StandardMaterial3D
	finish.emission=Color("94ffd0") if active else Color("ffd580")
	finish.emission_energy_multiplier=1.65 if active else .18
func update_service_signal(dt:float)->void:
	var speed:=Vector2(walker.velocity.x,walker.velocity.z).length()
	var event:=service_signal.advance(dt,walker.position,speed)
	if event.is_empty():return
	var target:=service_signal.target()
	var clear:=event in ["pulse","answer"]
	sound_at("relay_answer",Relay.PORTS[target],-8. if clear else -34.,8.)
	if event=="answer":
		set_relay_lamp(target,true)
		toast("%s传来两声敲击。"%("西侧" if target==0 else "东侧"))
	elif event=="masked":toast("敲击的回声被脚步盖住了。")
func relay_hint()->String:
	if service_signal.pending():return "聆听回声……"
	if service_signal.heard and relay_focus==service_signal.target():return "[E] 扳动柜闩"
	if service_signal.on_felt(walker.position,relay_focus):return "[E] 敲击"
	return "站上毡垫聆听"
func finish_expedition(solo:=false)->void:
	finished=true;_release_mouse()
	if solo:
		var solo_ending:Tween=polish.finish("撤 离 成 功","独自撤出 · 提灯留在了气密前室 · Hale 仍守在井区")
		solo_ending.finished.connect(func():returned.emit())
	else:
		var ending:Tween=polish.finish("撤 离 成 功","备用源核已送回稳压室 · 远征记录已归档")
		# The host removes this scene on return. Give the fade and title time to play first.
		ending.finished.connect(func():returned.emit())
	captions.hide();caption_toast.hide();prompt.hide();siren.stop();hunter.stop_audio()
func begin_hale_return()->void:
	if not (holding or posting):
		# The south bypass also rejoins the evacuation route: Hale waits by the west entrance.
		if archive.beat in [archive.Beat.WINDOW,archive.Beat.WITHDRAW,archive.Beat.DOOR,archive.Beat.WAIT,archive.Beat.PEEK]:
			archive.facts.decide("hale_recall",true,"return via the B2 bank and B1")
			# Rejoin from the B2 bank via B1, rather than cutting through archive walls.
			hale_return_path=PackedVector3Array([Vector3(26.28,0.,8.5),Vector3(26.28,0.,4.93),Vector3(31.,0.,4.93),Vector3(31.,0.,0.),Vector3(2.4,0.,0.),HALE_WAIT])
		elif hale.position.x>46.:
			hale_return_path=PackedVector3Array([Vector3(48.3,0.,10.1),Vector3(38.7,0.,10.1),Vector3(38.7,0.,0.),Vector3(2.4,0.,0.),HALE_WAIT])
		return
	var traversed:=watch_route.size() if holding else watch_route.size()-command_path.size()
	hale_return_path.clear()
	for i in range(traversed-1,-1,-1):hale_return_path.append(watch_route[i])
	for point in [Vector3(48.3,0.,10.1),Vector3(38.7,0.,10.1),Vector3(38.7,0.,0.),Vector3(34.,0.,0.),Vector3(2.4,0.,0.),HALE_WAIT]:hale_return_path.append(point)
	holding=false;posting=false;command_path.clear();trail.clear()
## The wheel shows only orders that can actually be executed right now. Each
## option carries its cost in the same vocabulary the contracts use, so the
## player is choosing a clause, not a button.
func order_options()->Array:
	var target:=focus()
	var items:Array=[]
	if target=="gate":
		items.append({"id":"try_gate","title":"让 Hale 试闸","hint":"请他试着拉开铁闸。"})
	if target=="north" or holding or posting:
		items.append({"id":"north","title":"去北窗盯桥" if not (holding or posting) else "召回 Hale","hint":"请他从北窗看着桥面。" if not (holding or posting) else "请他回来。"})
	if hale_hold or released and walker.position.x>46. and near(Vector3(61,0,10.1),26.):
		items.append({"id":"trail","title":"跟紧我","hint":"让他跟在你身后。"})
	items.append({"id":"hold","title":"原地待命","hint":"请他在这里等你。"})
	if contracts.trust>=2:
		items.append({"id":"advise","title":"听他的建议","hint":"问他有没有听见或看见什么。"})
	return items

func pick_order(id:String)->void:
	audit_action.emit("order",id)
	if id in ["try_gate","north","trail","hold"]:hale_gate_guide=0
	if id in ["north","trail","hold"]:hale_gate_attempt=false
	match id:
		"try_gate":
			if hale_gate_attempt:return
			hale_gate_attempt=true;hale_gate_effort=HALE_GATE_DURATION
			hale_gate_target=kit.gate_spots[0 if walker.position.z>=0. else 1].global_position
			trail.clear()
		"north":
			if posting or holding:
				posting=false;holding=false;north_pause=0.;command_path.clear();trail.clear()
				say("已发出召回指令。")
				return
			var hale_available:=archive.beat==archive.Beat.DONE and hale.position.distance_to(walker.position)<=6.
			if not archive.facts.decide("north_order",hale_available,"Hale reached the shaft" if hale_available else "Hale has not reached the shaft"):
				say("Hale 还没到桥头。");return
			hale_hold=false;posting=true;north_pause=maxf(.25,.55-.12*contracts.trust);command_path=kit.stair_path.duplicate()
			command_path.insert(0,kit.west_stair_entry())
			for i in 19:command_path.append(kit.polar(12.45,PI+(PI*.5)*i/19.,4.8))
			command_path.append(kit.north_spot.global_position)
			watch_route=command_path.duplicate()
			captions.post("north_order","我","你看见我走过那块板了。去北窗替我盯着桥，我看前面。"
				if archive.facts.evaluate("hale_comparison") else "去北窗替我盯着桥。我过桥时只看前面。")
		"trail":
			holding=false;posting=false;command_path.clear()
			hale_hold=false;say("已下达跟随指令。")
		"hold":
			hale_hold=true;holding=false;posting=false;trail.clear();command_path.clear();say("已下达留守指令。")
		"advise":
			if not hale_in_earshot():
				say("离 Hale 太远，听不清。");return
			var reply:=hale_hears_well()
			if contracts.a_state=="overlap" and archive.gaze!=Vector3.ZERO:reply="我还盯着那块板。你那边怎么样？"
			show_line("advise",reply if not reply.is_empty() else "等一下，让我听听。")
## Keyboard/legacy path: Q acts immediately on the most specific order; the
## wheel is only raised when there is a genuine choice to make.
func order()->void:
	if focus()=="hale":
		pick_order("trail" if hale_hold else "hold");return
	var items:=order_options()
	if items.is_empty():return
	for want in ["north","try_gate","trail","hold"]:
		for it in items:
			if it.id==want:pick_order(want);return
	pick_order(items[0].id)

## A stored hunt state is not an audible cue. The escape gallery has a separate mix.
func hale_hears_well()->String:
	if not released or not hale_in_earshot() or not hunter.voice.playing:return ""
	for pos:Vector3 in [walker.global_position,hale.global_position]:
		if pos.x<=46. or in_return_gallery(pos) or pos.distance_to(hunter.voice.global_position)>=hunter.voice.max_distance:return ""
	if hunter.voice.stream==sounds.scream:return "听见那一声了吗？就在井里。先别动。"
	if hunter.voice.stream==sounds.rumble:return "嘘，下面响了一声。"
	return ""

func hale_report()->void:
	if trust_line_cd>0. or manual.visible or finished:return
	var line:=hale_hears_well()
	if line.is_empty():return
	trust_line_cd=5.2
	show_line("hale_read",line)

func stance_speed()->float:
	return SPEEDS[stance]

## Quiet beats everything: holding Ctrl at a sprint drops to 1.55 m/s in one
## tick, which is what makes the contract-B tally a real decision.
func update_stance(dt:float)->void:
	var quiet:=Input.is_physical_key_pressed(KEY_CTRL) or Input.is_action_pressed("expedition_quiet")
	stance=ST_QUIET if quiet else ST_RUN if running else ST_WALK
	stance_blend=lerpf(stance_blend,float(stance),1.-exp(-9.*dt))
	aim=lerpf(aim,1. if aiming else 0.,1.-exp(-11.*dt))

## Landings absorb into the lens and stop the stride, so a drop never plays a
## footstep on the same frame it touches down.
func _surface_underfoot()->String:
	for i in walker.get_slide_collision_count():
		var contact:=walker.get_slide_collision(i)
		if contact.get_normal().y<.7:continue
		var surface:=str(contact.get_collider().get_parent().name)
		if "SouthServiceWalk" in surface or "Span" in surface or "InspectionDeck" in surface or "ServiceIncline" in surface or contact.get_collider().is_in_group("expedition_iron_tread"):return "iron"
		elif "Plate" in surface:return "wood"
	return "stone"

func landing_check(was_grounded:bool)->void:
	var grounded:=walker.is_on_floor()
	if was_grounded and not grounded:air_peak=walker.velocity.y
	if grounded:
		if not was_grounded and last_vy<-Feel.LAND_MIN_SPEED:
			land_dip=Feel.landing_dip(last_vy)
			stride=0.
			polish.on_land(last_vy)
			var kind:=_surface_underfoot()
			var muffled:=service_signal.on_felt(walker.position,0) or service_signal.on_felt(walker.position,1)
			foot.stream=sounds.quiet if speed_quiet() or muffled else sounds[kind]
			foot.pitch_scale=randf_range(.84,.94)
			foot.volume_db=-32. if muffled else (-25. if speed_quiet() else clampf(-20.+(-last_vy-3.)*1.2,-20.,-13.))
			foot.play()
		air_peak=0.
	last_vy=walker.velocity.y

func _physics_process(dt:float)->void:
	if finished:
		for track in [ambient_bed,shaft_bed,score]:
			track.volume_db=move_toward(track.volume_db,-72.,46.*dt)
			if track.volume_db<=-72. and track.playing:track.stop()
		return
	if manual.visible:return
	prompt.visible=mode<0 and not wheel_open;captions.visible=mode<0
	if wheel_open:prompt_notice.visible=false
	review_hud.visible=mode>=0
	if mode>=0 and detail_view>=0:review_hud.text="EYE HEIGHT   /   %s     F6  next sightline    F4  leave"%["B2 · OBSERVATION WINDOW","B5 · MASTER RELEASE","C1 · GAZE SPAN"][detail_view];return
	if mode>=0:review_hud.text="SECTION PLATE  %s    /    F4  next view   /   F5  shell or cutaway   /   F6  eye height"%["A · IMMERSION ARCADE","B · ARCHIVE WING","C · SOURCE CAISSON"][mode];return
	if mcp_controls:
		var turn:=Input.get_vector("expedition_look_left","expedition_look_right","expedition_look_up","expedition_look_down")
		walker.rotate_y(-turn.x*dt*1.8);eye.rotation.x=clampf(eye.rotation.x-turn.y*dt*1.8,-1.48,1.48)
	run_time+=dt
	stomp_cool=maxf(0.,stomp_cool-dt)
	var axis:=Input.get_vector("move_left","move_right","move_up","move_down");var dir:=walker.basis*Vector3(axis.x,0,axis.y)
	update_stance(dt)
	var speed:=stance_speed()
	if retry>0:
		retry-=dt;if retry<=0:reset_at_checkpoint()
	else:
		var current:=Vector2(walker.velocity.x,walker.velocity.z);var wish:=Vector2(dir.x,dir.z)*speed
		# Three gear steps with a soft start, a hard reversal and a short glide-to-stop.
		# Air control keeps a fifth of the ground authority so jumps commit to their arc.
		var grounded:=walker.is_on_floor()
		var planar:=Feel.step_planar_velocity(current,wish,dt,grounded,ACCEL_GROUND,ACCEL_TURN,ACCEL_STOP,AIR_CONTROL,stance==ST_QUIET)
		walker.velocity.x=planar.x;walker.velocity.z=planar.y
		# Jump: one buffered press, a 120 ms coyote window and a short apex hang.
		jump_buffer=maxf(0.,jump_buffer-dt);coyote=maxf(0.,coyote-dt)
		if grounded:coyote=COYOTE
		if jump_buffer>0. and (grounded or coyote>0.):
			audit_action.emit("confirmed","起跳")
			walker.velocity.y=JUMP_SPEED;jump_buffer=0.;coyote=0.
			polish.kick(.10);sound_at("quiet",walker.position,-30.,8.)
		# Rising gravity is lighter than the fall so a short hop clears a 0.19 m riser and lands fast.
		walker.velocity.y-=GRAVITY_RISE*dt if walker.velocity.y>0. else GRAVITY_FALL*dt
		# Low tread risers: lift only on a grounded horizontal obstruction and verify clearance.
		var step:=dir*speed*dt
		if grounded and step.length_squared()>.00001 and walker.test_move(walker.transform,step) and not walker.test_move(walker.transform,Vector3.UP*STEP_HEIGHT):
			var up:=walker.transform;up.origin.y+=STEP_HEIGHT
			if not walker.test_move(up,step):walker.position.y+=STEP_HEIGHT
		walker.move_and_slide()
		landing_check(grounded)
		walking_feedback(dt);update_service_signal(dt)
		update_return_route(walker.position)
		if exit_open and walker.position.x<kit.AIRLOCK_DEPTH:exit_requested=true
		if not solo_escape and exit_requested and walker.position.x<kit.AIRLOCK_DEPTH and hale.position.x< -1.85 and hale_return_path.is_empty() and not captions.entries.has("Hale"):
			finish_expedition();return
		var prior:=hale.position;advance_hale(dt);animate_hale(prior,dt);rules(dt)
	msg_time-=dt;distraction=maxf(0,distraction-dt)
	captions.advance(dt)
	toast_time-=dt;caption_toast.visible=toast_time>0. and mode<0
	update_north_signal()
	update_lantern(dt)
	update_soundscape(dt)
	if evidence_thought_delay>0.:
		evidence_thought_delay-=dt
		if evidence_thought_delay<=0.:thought("thought","隔着窗，两个人一看就起了红光。刚才只剩我在看，波纹倒平了。得记下来。")
	update_target()
	hud.modulate=Color.WHITE
	var hints:={"gate":R18n.t("prompt.gate_busy") if hale_gate_attempt else R18n.t("prompt.gate"),"note":R18n.t("prompt.note"),"loot":R18n.t("prompt.loot"),"clock":R18n.t("prompt.clock"),"clock_locked":R18n.t("prompt.clock_locked"),"lever":R18n.t("prompt.lever"),"core":R18n.t("prompt.core"),"return":R18n.t("prompt.return"),"exit":R18n.t("prompt.exit"),"north":R18n.t("prompt.north_recall") if holding or posting else R18n.t("prompt.north_post"),"throw":R18n.t("prompt.throw"),"hale":R18n.t("prompt.hale",[R18n.t("prompt.hale_hold") if not hale_hold else R18n.t("prompt.hale_follow")]),"solo_exit":R18n.t("prompt.solo_exit"),"stele1":R18n.t("prompt.stele1"),"stele2":R18n.t("prompt.stele2")}
	hints["maintenance_lift"]=R18n.t("prompt.maint_lift")
	hints["maintenance_oil"]=R18n.t("prompt.maint_oil")
	hints["vault_oil"]=R18n.t("prompt.vault_oil")
	hints["niche_oil"]=R18n.t("prompt.niche_oil")
	var seen:=focus();polish.focus_id=seen
	var hint:=relay_hint() if seen=="relay" else str(hints.get(seen,""))
	# Two lines, never one replacing the other: the action line stays pinned to
	# the reticle while the notice line reports state changes underneath it.
	prompt.text=hint
	prompt_notice.visible=mode<0 and not manual.visible and not wheel_open
	prompt_notice.text=notice if msg_time>0. else ""
	prompt.offset_top=23 if hint!="" or msg_time>0. else 10
func in_return_gallery(p:Vector3)->bool:
	return return_started and (p.x>75.55 or p.z>25.15 or (absf(p.x-kit.RETURN_WEST)<1.45 and p.z>=kit.RETURN_GATE_Z-.2))

func update_return_route(p:Vector3)->void:
	if shortcut_open and p.x>75.60 and p.y>4.48 and absf(p.z-12.45)<1.0:
		if not return_started:
			hunter.stop_audio();siren.stop();gallery_tail=0.
			gallery_bell.volume_db=-22.;gallery_bell.play()
			gallery_impact.volume_db=-22.;gallery_impact.play()
		return_started=true
	if not return_started or absf(p.x-kit.RETURN_WEST)>1.18 or p.y>.60:return
	if not return_gate_open and p.z>kit.RETURN_GATE_Z and p.z<14.5:
		return_gate_open=true
		var gate:Node3D=kit.return_exit_gate
		create_tween().tween_property(gate,"position:y",2.74,.62).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
		sound_at("chain",gate.position+Vector3.UP*1.6,-17.,12.)
	if return_gate_open and p.z<kit.RETURN_GATE_Z-.12:shortcut_used=true

func update_soundscape(dt:float)->void:
	if return_started:
		gallery_tail+=dt
		var fadeout:=1. if shortcut_used else smoothstep(.55,6.4,gallery_tail)
		var tail_gain:=linear_to_db(maxf(.002,pow(1.-fadeout,1.55)))
		gallery_bell.volume_db=-19.+tail_gain
		gallery_impact.volume_db=-20.+tail_gain
		if fadeout>=1.:
			gallery_bell.stop();gallery_impact.stop()
	var p:=walker.position
	var shaft:=released and p.x>46.2 and not in_return_gallery(p)
	shaft_mix=move_toward(shaft_mix,1. if shaft else 0.,dt*.72)
	ambient_bed.volume_db=linear_to_db(lerpf(.056,.029,shaft_mix))
	shaft_bed.volume_db=linear_to_db(maxf(.00032,shaft_mix*.080))
	if shaft and not score.playing:score.play()
	elif not shaft and shaft_mix<=0. and score.playing:score.stop()
	score.volume_db=linear_to_db(maxf(.00032,shaft_mix*(.041 if collected else .025)))

func update_lantern(dt:float)->void:
	var p:=walker.position
	var dark:=in_b4(p)
	darkroom_mix=move_toward(darkroom_mix,1. if dark else 0.,dt*4.)
	var env:Environment=get_world_3d().environment
	var atmo:=RenderProfile.atmosphere_for(region if region!="" else "arcade",darkroom_mix)
	var grade_k:=Feel.exp_damp(3.2,dt)
	env.ambient_light_energy=lerpf(env.ambient_light_energy,float(atmo.ambient),grade_k)
	env.fog_light_color=env.fog_light_color.lerp(atmo.fog_color,grade_k)
	env.fog_density=lerpf(env.fog_density,float(atmo.fog_density),grade_k)
	env.sdfgi_energy=lerpf(.90,.48,darkroom_mix)
	var fuel:=sqrt(oil/100.)
	var low_oil:=clampf(1.-oil/28.,0.,1.)
	var flicker:=1.+(.045+.055*low_oil)*sin(phase*15.7)+(.026+.034*low_oil)*sin(phase*27.3)
	lantern.light_color=Color("ffd09b").lerp(Color("ff7e3d"),low_oil*.75)
	if not lamp_on:lantern.light_energy=0.
	else:lantern.light_energy=(1.18+.54*darkroom_mix)*fuel*flicker
	lantern.omni_range=lerpf(1.45,6.9,fuel)
	var dyaw:=wrapf(walker.rotation.y-_lamp_prev_yaw,-PI,PI)
	var dpitch:=eye.rotation.x-_lamp_prev_pitch
	_lamp_prev_yaw=walker.rotation.y;_lamp_prev_pitch=eye.rotation.x
	var local_v:=walker.basis.inverse()*Vector3(walker.velocity.x,0.,walker.velocity.z)
	var target_sway:=Vector2(clampf(-dyaw*.28-local_v.x*.008,-.055,.055),clampf(-dpitch*.22-walker.velocity.y*.006,-.045,.045))
	_lamp_sway=_lamp_sway.lerp(target_sway,Feel.exp_damp(10.,dt))
	var aim_tuck:=Vector3(-.055,.028,.04)*aim
	player_lamp.position=Vector3(.34+.020*sin(TAU*stride)+_lamp_sway.x,-.42+.019*cos(TAU*stride)+_lamp_sway.y-polish.land_dip*.45,-.25)+aim_tuck
	player_lamp.rotation=Vector3(_lamp_sway.y*1.4,0.,-_lamp_sway.x*2.0)
	hale_prop.visible=released
	if released and hale_hand>=0:
		var grip:=hale.to_local(hale_rig.to_global(hale_rig.get_bone_global_pose(hale_hand).origin))
		hale_prop.position=grip+Vector3(0,-.14,.032)
	hale_lantern.light_energy=(1.22 if posting else .48)*flicker
func update_target()->void:
	var goal:=R18n.t("goal.arcade")
	if exit_requested:goal=R18n.t("goal.enter_hall")
	elif shortcut_used:goal=R18n.t("goal.return_hall")
	elif return_started:goal=R18n.t("goal.return_gallery")
	elif collected:goal=R18n.t("goal.evacuate")
	elif holding:goal=R18n.t("goal.bridge_go")
	elif posting:goal=R18n.t("goal.hale_think") if north_pause>0. else R18n.t("goal.hale_north")
	elif released:goal=R18n.t("goal.enter_shaft")
	elif archive.in_trial(walker.position) and walker.position.z<13.65:
		goal=R18n.t("goal.trial_cross") if demo_locked else R18n.t("goal.trial_lock")
	elif learned or equipped or walker.position.x>27.8 and walker.position.z>9.:
		goal=R18n.t("goal.control_room")
	elif archive.in_window(walker.position) and not archive.paired:
		goal=R18n.t("goal.window_opt")
	elif tutorial_room or archive.paired:goal=R18n.t("goal.through_b3")
	elif cues.has("gate"):goal=R18n.t("goal.archive_door")
	hud.text=R18n.t("hud.step_prefix",[goal])
var iron_footfall:=false
func walking_feedback(dt:float)->void:
	iron_footfall=false
	var distance:=Vector2(walker.get_position_delta().x,walker.get_position_delta().z).length()
	if walker.is_on_floor() and distance>.001:
		stride+=distance/Feel.stride_for_stance(stance)
		if stride>=1.:
			stride=fmod(stride,1.);var kind:=_surface_underfoot()
			iron_footfall=kind=="iron"
			var muffled:=service_signal.on_felt(walker.position,0) or service_signal.on_felt(walker.position,1)
			var quiet_now:=speed_quiet()
			foot.stream=sounds.quiet if quiet_now or muffled else sounds[kind]
			var pitch_bias:=-.05 if quiet_now else (.04 if running else 0.)
			foot.pitch_scale=randf_range(.94,1.06)+pitch_bias
			var iron_boost:=1.8 if (kind=="iron" and not quiet_now and not muffled) else 0.
			foot.volume_db=(-34. if muffled else -27. if quiet_now else (-17. if running else -21.))+iron_boost;foot.play()

func speed_quiet()->bool:return Input.is_physical_key_pressed(KEY_CTRL) or Input.is_action_pressed("expedition_quiet")
func setup_hale_animation()->void:
	var anim:AnimationPlayer=hale.get_meta("animation_player")
	var tree:=AnimationTree.new();var machine:=AnimationNodeStateMachine.new()
	var states: Array[StringName]=[&"idle",&"walk",&"run",&"gate_effort",&"watch_plate",&"ward",&"peek"]
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
	var d:=hale.position-prior;d.y=0;var speed:=d.length()/maxf(dt,.00001)
	hale_speed=lerpf(hale_speed,speed,1.-exp(-10.*dt))
	var pushing:=hale_gate_attempt and hale.position.distance_to(hale_gate_target)<.025
	var clip:=&"gate_effort" if pushing else archive.pose if archive.pose!=&"" else &"run" if hale_speed>4.8 else &"walk" if hale_speed>.18 else &"idle"
	if hale_clip!=clip:hale_loco.travel(clip);hale_clip=clip
	var target_yaw:=hale.rotation.y
	if hale_face_motion and speed>HALE_FACE_SPEED and hale_speed>HALE_FACE_SPEED and not pushing and archive.pose==&"" and archive.gaze==Vector3.ZERO:
		target_yaw=atan2(d.x,d.z)
	hale.rotation.y=rotate_toward(hale_yaw_before_step,target_yaw,HALE_TURN_RATE*dt)
func line_once(id:String,text:String)->void:
	if cues.has(id):return
	cues[id]=true
	show_line(id,text)
func hale_in_earshot()->bool:
	return hale.global_position.distance_squared_to(walker.global_position)<=64.

func show_line(id:String,text:String)->void:
	# Caption and voice cue share a local hearing range. Story cues still record normally.
	if not hale_in_earshot():return
	if id in Polish.CINEMATIC_LINES:polish.letterbox(captions.reading_time(text)+.4)
	subtitle_id=id;captions.post(id,"Hale",text.trim_prefix("Hale："));play_ui("cue",-23.)
func announce_north_ready()->void:
	if hale_in_earshot():
		show_line("north_ready","我到窗边了！桥面不晃了。")
		north_ready_signaled=true

func update_north_signal()->void:
	north_beacon.visible=holding
	if not holding:
		north_ready_signaled=false
		if caption_toast.text==NORTH_READY_NOTICE:
			toast_time=0.;caption_toast.hide()
		return
	if north_ready_signaled:return
	var lamp:Vector3=north_beacon.global_position
	if not eye.is_position_in_frustum(lamp):return
	# Stone can hide the light; the north window's glazing transmits it.
	var ray:=PhysicsRayQueryParameters3D.create(eye.global_position,lamp,2)
	if not get_world_3d().direct_space_state.intersect_ray(ray).is_empty():return
	north_ready_signaled=true
	toast(NORTH_READY_NOTICE)

func confirm_gate_locked()->void:
	cues["gate"]=true
func advance_hale(dt:float)->void:
	hale_yaw_before_step=hale.rotation.y
	hale_face_motion=true
	var separation:=hale.position-walker.position
	separation.y=0.
	var gap:=separation.length()
	if gap>1.6:hale_yielded=false
	if not hale_return_path.is_empty() or shortcut_used or hale_gate_attempt or posting or holding or hale_hold or (released and walker.position.x>50.):
		reset_hale_pursuit()
	if shortcut_used or not hale_return_path.is_empty():hale_gate_guide=0
	if not hale_return_path.is_empty():
		var next:=hale_return_path[0]
		hale.position=hale.position.move_toward(next,dt*5.8)
		if hale.position.distance_to(next)<.03:hale_return_path.remove_at(0)
		return
	if shortcut_used and not reunited and walker.position.x<9. and hale.position.distance_to(walker.position)<7.:
		reunited=true;sound_at("hale_breath",hale.position+Vector3.UP*1.46,-29.,8.)
		show_line("reunion","呼……我从二层北廊绕下来的。差一点就回不来了。走，进锚定厅。" if left_north_window else "呼……我沿原路撤回来的。差一点就回不来了。走，进锚定厅。")
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
			hale_gate_attempt=false
		else:
			if hale.position.distance_to(hale_gate_target)>.025:
				hale.position=hale.position.move_toward(hale_gate_target,dt*3.8)
			else:
				hale.rotation.y=lerp_angle(hale.rotation.y,PI*.5,1.-exp(-15.*dt))
				var before:=HALE_GATE_DURATION-hale_gate_effort
				hale_gate_effort-=dt
				for hit in [.36,.69]:
					if before<hit and before+dt>=hit:sound_at("gate",Vector3(35.97,1.24,hale_gate_target.z),-13.,12.)

				if hale_gate_effort<=0.:
					hale_gate_attempt=false;confirm_gate_locked()
					if walker.position.x>=33.2 and not hale_hold and not posting and not holding:
						show_line("hale_gate","纹丝不动。刚才经过那扇绿门通档案翼，走，回去看看。")
						hale_gate_guide=1
						cues["sealed_well"]=true
			return
	if archive.step(self,dt):
		hale_gate_guide=0
		reset_hale_pursuit()
		return
	if hale_gate_guide>0 and step_hale_gate_guide(dt):return
	if posting:
		if north_pause>0.:
			north_pause=maxf(0.,north_pause-dt)
			if north_pause==0.:show_line("post","好。我去北窗。等窗边的灯亮了，你再过桥。")
			return
		if command_path.is_empty():
			posting=false;holding=true;hale.rotation.y=0.
			announce_north_ready()
			return
		var budget:=9.6*dt
		while budget>0. and not command_path.is_empty():
			var distance:=hale.position.distance_to(command_path[0])
			hale.position=hale.position.move_toward(command_path[0],budget);budget-=distance
			if budget>=0.:command_path.remove_at(0)
	elif holding:
		hale.rotation.y=0.
	else:
		# Q 的留守令：Hale 原地驻守并面向玩家；离得太远会自己归队。
		if hale_hold:
			if hale.position.distance_to(walker.position)>26.:
				hale_hold=false;show_line("hale_catchup","等等我！——你走得太远了！")
			else:
				var hold_face:=walker.position-hale.position
				if Vector2(hold_face.x,hold_face.z).length()>.45:
					hale.rotation.y=lerp_angle(hale.rotation.y,atan2(hold_face.x,hold_face.z),1.-exp(-6.*dt))
			return
		if released and walker.position.x>50.:return
		if gap>2.6:hale_chasing=true
		elif gap<1.6:hale_chasing=false
		# Keep the sampled route through doors and around corners, even when stopped.
		if last_pos.distance_to(walker.position)>.23:trail.append(walker.position);last_pos=walker.position
		if gap<.9 and not hale_yielded:
			hale_yielded=true
			var side:=Vector3(-separation.z,0.,separation.x).normalized() if gap>.001 else walker.basis.x
			for direction in [side,-side]:
				if hale_can_yield(direction):
					hale_yield_dir=direction;hale_yield_left=.65
					break
		if hale_yield_left>0.:
			var stride:=minf(hale_yield_left,dt*2.)
			hale.position+=hale_yield_dir*stride;hale_yield_left-=stride
			hale_face_motion=false
			return
		if not hale_chasing:return
		# Preserve the existing long-distance recovery and suppress facing on its teleport frame.
		if hale.position.distance_to(walker.position)>13.:
			hale_stuck+=dt
			if hale_stuck>6. and not trail.is_empty():
				hale.position=trail[0]+Vector3(0,0,.9);hale_stuck=0.
				hale_face_motion=false
				show_line("stuck","……这儿有点窄，我绕了一下。")
				return
		else:hale_stuck=0.
		if not trail.is_empty():
			hale.position=hale.position.move_toward(trail[0],4.7*dt)
			if hale.position.distance_to(trail[0])<.055:trail.remove_at(0)
func step_hale_gate_guide(dt:float)->bool:
	var p:=walker.position
	# Entering the archive, continuing down the hall, and explicit orders all
	# hand movement straight back to the existing follower.
	if released or posting or holding or hale_hold or p.x<32.05 or absf(p.z)>2.:
		hale_gate_guide=0
		return false
	reset_hale_pursuit()
	if last_pos.distance_to(p)>.23:trail.append(p);last_pos=p
	if hale_gate_guide<3:
		var target:=Vector3(33.2,0.,hale_gate_target.z) if hale_gate_guide==1 else HALE_ARCHIVE_LOOKOUT
		var step:=target-hale.position
		if step.length()>.03:
			# Plant the turn after the shove, then walk along the flank of the hall.
			var heading:=atan2(step.x,step.z)
			if absf(angle_difference(hale.rotation.y,heading))>.55:
				hale_face_motion=false;hale.rotation.y=heading
			else:hale.position=hale.position.move_toward(target,dt*2.55)
		else:
			hale_gate_guide+=1
			if hale_gate_guide==3:hale_gate_guide_wait=2.2
	else:
		var look:=p-hale.position
		if Vector2(look.x,look.z).length()>.45:hale.rotation.y=atan2(look.x,look.z)
		hale_gate_guide_wait-=dt
		if hale_gate_guide_wait<=0.:hale_gate_guide=0
	return true
func reset_hale_pursuit()->void:
	hale_chasing=false;hale_yield_left=0.;hale_stuck=0.
func hale_can_yield(direction:Vector3)->bool:
	var space:=get_world_3d().direct_space_state
	var chest:=hale.position+Vector3.UP*.72
	var clear:=PhysicsRayQueryParameters3D.create(chest,chest+direction*.90,5,[walker.get_rid()])
	if not space.intersect_ray(clear).is_empty():return false
	var foot:=hale.position+direction*.65
	var floor_ray:=PhysicsRayQueryParameters3D.create(foot+Vector3.UP*.35,foot-Vector3.UP*.45,5,[walker.get_rid()])
	return not space.intersect_ray(floor_ray).is_empty()
func rules(dt:float)->void:
	var p:=walker.position
	pair_loud=false;both_lamp=false
	update_demo(p,dt)
	contract_hooks(p,dt)
	var hale_near:=hale.visible and p.distance_to(hale.position)<5.5
	var at_entry:=not released and not tutorial_room and p.x>=.3 and p.x<7. and absf(p.z)<1.9
	var at_gate:=not released and p.x>30. and p.x<36. and absf(p.z)<2.3
	var at_detour:=not released and p.x>28.2 and p.x<33.8 and p.z>4.4 and p.z<7.1
	var active_hale: String = captions.entries.get("Hale", {}).get("id", "")
	match active_hale:
		"start":
			if not (at_entry and hale_near):captions.remove_speaker("Hale")
		"sealed_well":
			if not (at_gate and hale_near):captions.remove_speaker("Hale")
		"collapse":
			if not (at_detour and hale_near):captions.remove_speaker("Hale")
		"rule_sound", "rule_light":
			if not hale_near:captions.remove_speaker("Hale")
	if hale_near and not captions.entries.has("Hale"):
		if at_entry and not cues.has("gate"):
			line_once("start","咱们先沿主廊走，看看隔离闸还能不能推开。")
		elif at_gate and cues.has("gate"):
			line_once("sealed_well","闸门推不开。看看旁边有没有路。")
		elif at_detour:
			line_once("collapse","直路被碎石堵住了。试试档案翼。")
	if not released and not tutorial_room and p.x>30. and p.x<36. and absf(p.z)<2.3:
		halo.light_energy=2.3
	oil=maxf(0.,oil-dt*.11)



	var radial:=Vector2(p.x-kit.CX,p.z-kit.CZ)
	# Give the caisson bed and west spiral a chance to catch a falling player.
	var fall_limit:float=kit.SHAFT_FLOOR_Y-.55 if radial.length_squared()<=kit.SHAFT_RECOVERY_RADIUS*kit.SHAFT_RECOVERY_RADIUS else -1.8
	if p.y<fall_limit:fail("坠入源井");return
	var service:=radial.y>2.65 and radial.length()>12.35 and radial.length()<14.25 and absf(p.y)<.35
	if service or in_b4(p):oil=maxf(0,oil-dt*(1.70 if service else 1.))
	if service and oil<=0:
		catwalk_oil_grace+=dt
		if lamp_on:lamp_on=false;polish.kick(.18)
		notice=R18n.t("warn.catwalk_oil",[maxf(0.,3.5-catwalk_oil_grace)]);msg_time=.25
		if catwalk_oil_grace>=3.5:fail("检修栈桥：灯油耗尽");return
	else:
		catwalk_oil_grace=0.
	if released and not collected and not cues.has("shaft_doubt") and p.x>47.2 and p.x<51.9 and aimed(Vector3(53.5,.08,10.1),8.,.90):
		cues["shaft_doubt"]=true
		thought("shaft_doubt","前面是桥面。先看看脚下。")
	var on_bridge:=absf(p.x-61)<9 and absf(p.z-10.1)<1.8 and absf(p.y)<.5
	if on_bridge:
		var aim:=-eye.global_basis.z
		var hit:Variant=Plane(Vector3.UP,0).intersects_ray(eye.global_position,aim)
		var looking:=hit!=null and absf(hit.x-61)<9 and absf(hit.z-10.1)<1.8
		var eye_h:=hale.position+Vector3.UP*1.62
		var watching:=(holding or (posting and hale.position.y>=4.7)) and sees_span(eye_h)
		var watchers:=int(watching)+int(looking);hazard=hazard+1 if watchers!=1 else 0
		if hazard==1 or hazard==25:warning.play()
		if hazard>0:notice="桥面泛红，开始摇晃" if watchers==2 else "桥面在下沉";msg_time=.2
		paint_bridge(Color("bf4335") if watchers==2 else Color("765337") if watchers==0 else Color("94b7be"),.30 if watchers else .13,dt)
		if hazard>=(40 if watchers==2 else 60):fail("桥面过载")
	else:
		hazard=0;paint_bridge(Color("94b7be") if holding else Color("a9824f"),.30 if holding else .19,dt)
	if released and not in_return_gallery(p):
		var grate:=posting and hale_speed>.35 and hale.position.y>1.
		metal_beat-=dt
		if grate and metal_beat<=0:metal_foot.play();metal_beat=.55
		var loud:=walker.is_on_floor() and Vector2(walker.velocity.x,walker.velocity.z).length()>2.35
		# 规则怪谈判定：同声律（两人同声 exposure×2）／独灯律（双灯 exposure×1.5 + 额外耗油）。
		if p.x>46.:
			var hale_noisy:=grate or (hale_speed>4.2 and hale.position.x>46. and hale.position.y<1.6)
			pair_loud=loud and hale_noisy
			both_lamp=lamp_on and hale_prop.visible and hale.position.x>46. and not in_return_gallery(hale.position)
		var heat:=1.
		if pair_loud:
			heat*=2.
			if hale_near and not captions.entries.has("Hale"):line_once("rule_sound","停一下。刚才咱俩的脚步叠在一块儿了。")
		if both_lamp:
			heat*=1.5
			oil=maxf(0.,oil-dt*.25)
			if hale_near and not captions.entries.has("Hale"):line_once("rule_light","两盏灯都亮着。我这盏够照了。")
		var rage:=collected or contracts.b_remembered
		if hunter.step(dt,p,loud,grate,distraction,rage,sounds,heat):
			if contracts.b_remembered:fail("违反契约B：它的呼唤已经记住了你的脚步")
			else:fail("听觉猎手扑到了你身上")
		if hunter.bait_answered and distraction>0. and p.distance_to(hunter.voice.global_position)<hunter.voice.max_distance and not cues.has("bait_answer"):
			cues["bait_answer"]=true;polish.signal_bait()
		if collected:
			emergency.light_energy=.38+.34*(.5+.5*sin(phase*5.))
			if p.x>46. and not siren.playing:siren.play()
# Glass transmits gaze; the plate never occludes its own samples.
func current_region(p:Vector3)->String:
	if in_return_gallery(p) or p.x>75.:return "return"
	if p.x>46.2:return "underdeck" if (absf(p.z-10.1)>1.9 and p.y<-.3) else "shaft"
	if p.x>27.8 and p.z>13.05 and p.z<17.68:return "release"
	if p.x<-.4:return "arcade"
	if p.x<19.9 and p.z>2.2 and p.z<7.4:return "niche"
	if p.x<9.2:return "arcade"
	if p.x<41.8 and p.z>9.:return "trial"
	if p.x<41.8:return "archive"
	return "arcade"

func announce_region(id:String)->void:
	if id==region:return
	region=id
	var card:=Contracts.region_card(id)
	if card.is_empty():return
	if contracts.trust<3:contracts.award("visit_"+id)
	polish.card(card.title,card.rule,card.note)
	polish.threshold()

## Overlap can extinguish the board; loud iron footsteps can draw the hunter.
func contract_hooks(p:Vector3,dt:float)->void:
	announce_region(current_region(p))
	# The B2/B3 plate only: elsewhere nobody is looking at the same board.
	var board_zone:=p.x>19.6 and p.x<28.2 and p.z>7.0 and p.z<15.4
	var self_sees:=board_zone and board_seen(eye.global_position,-eye.global_basis.z)
	var hale_sees:=board_zone and archive.gaze!=Vector3.ZERO and board_seen(hale.position+Vector3.UP*1.57,archive.gaze.normalized())
	var count:=int(self_sees)+int(hale_sees)
	var hale_present:=hale.visible and p.distance_to(hale.position)<5.5
	if not board_zone:contracts.a_abandon()
	var first:int=prior_seer if prior_seer!=0 else contracts.Seer.PLAYER
	if count<2:prior_seer=contracts.Seer.PLAYER if self_sees else contracts.Seer.HALE if hale_sees else contracts.Seer.NONE
	if board_zone or contracts.a_state=="blackout":
		var ev:=contracts.a_step(dt,count,first,self_sees,hale_sees)
		if ev=="breach":
			rule_breach_flash=1.
			board_audio.stop();kit.test_board.hide();kit.test_board.get_child(0).collision_layer=0;plate_spill.light_energy=0.
			sound_at("glass_breakout",board_audio.position,-8.,18.)
			polish.kick(.55);polish.punch(6.)
			if hale_present:
				# Only the plate footprint loses support; the observation bank is stone.
				var over_plate:=absf(p.x-23.85)<.90 and absf(p.z-12.02)<1.60 and p.y>=-.10
				if over_plate:
					cues["breach_a"]=true
					show_line("breach_a","板子熄了！快退回石台！" if hale_sees else "脚下！快退回石台！")
				else:
					line_once("breach_a","刚才那声碎响，你听见了吗？")
			return
		elif ev=="release":
			archive.handoff(self)
			contracts.award("contract_a")
			if hale_present:show_line("pass_a","看，波纹平了。" if hale_sees else "我背过身了。你那边怎么样？")
	trust_line_cd=maxf(0.,trust_line_cd-dt)
	if count==0:hale_report()
	# Contract B: only iron tread makes a call, and only while the hunter can hear.
	if released and p.x>46. and not in_return_gallery(p) and walker.is_on_floor():
		var loud:=Vector2(walker.velocity.x,walker.velocity.z).length()>4.6
		if loud and iron_footfall:
			var ev:=contracts.b_loud_step()
			if ev=="remembered":
				hunter.wake();polish.kick(.5);rule_breach_flash=1.
				show_line("remember_b","那声音又近了。先停一下。")
				sound_at("rumble",Vector3(54.4,-9.4,9.4),-4.,40.)
			elif ev=="call":
				polish.kick(.2);sound_at("iron",p,-14.,18.)
				show_line("call_b",contracts.b_line(self))
		elif not loud:
			contracts.b_quiet(dt)
	rule_breach_flash=maxf(0.,rule_breach_flash-dt*1.4)

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
	var board:=kit.test_board as MeshInstance3D
	var body:=board.get_child(0) as StaticBody3D
	# contract_hooks owns the timer. No gaze, lock, or fade writes while the
	# plate is dead, including the tick on which the timer reaches zero.
	if contracts.a_state=="blackout":
		board.hide();body.collision_layer=0
		demo_single_time=0.;demo_locked=false;observers=0
		trial_near_bank=false;crossing=false;crossing_locked=false;crossing_in_hale_view=false
		plate_spill.light_energy=0.;overload_blend=0.
		return
	if not board.visible:
		board.position=Vector3(23.85,.045,12.02)
		demo_grace=1.
		board.show()
	var in_b3:=archive.in_trial(p)
	if in_b3:tutorial_room=true
	var self_sees:=board_seen(eye.global_position,-eye.global_basis.z)
	var hale_sees:=archive.gaze!=Vector3.ZERO and board_seen(hale.position+Vector3.UP*1.57,archive.gaze.normalized())
	var count:=int(self_sees)+int(hale_sees)
	archive.compare(self,count if hale.visible and p.distance_to(hale.position)<5.5 else 0,dt)
	var was_locked:=demo_locked
	var active_single:=count==1 and self_sees and in_b3 and p.y>=-.10
	if active_single:
		if demo_single_time==0. and not archive.facts.has_fact("solo_lock_b3"):
			if not cues.has("settling"):
				cues["settling"]=true
				thought("settling","琥珀色的波纹在往里收。再盯一会儿，看看能不能稳住。")
			board_audio.stream=sounds.hum;board_audio.play()
		demo_single_time+=dt
	else:
		demo_single_time=0.
		if board_audio.playing:board_audio.stop()
	demo_locked=demo_single_time>=GAZE_LOCK_TIME
	if demo_locked and not was_locked:
		board_audio.stop();sound_at("set",board_audio.position,-7.)
		archive.record_lock(self)
	if not in_b3 or p.y<-.10:trial_near_bank=false
	elif p.z<10.45:trial_near_bank=true
	if not trial_near_bank or p.z<10.45 or (p.z<13.4 and not active_single):
		crossing=false;crossing_locked=false;crossing_in_hale_view=false
	if trial_near_bank and absf(p.x-23.85)<.92 and p.z>10.48 and p.z<12.8 and p.y>=0. and active_single:crossing=true
	if crossing and demo_locked:
		crossing_locked=true
		if active_single and archive.sees_crossing(self):crossing_in_hale_view=true
	if crossing_locked and p.z>=13.65 and p.y>=0. and count<2:
		learned=true
		archive.record_crossing(self,crossing_in_hale_view)
		trial_near_bank=false;crossing=false;crossing_locked=false;crossing_in_hale_view=false
	var changed:=count!=observers;observers=count
	demo_grace=1. if count else maxf(0.,demo_grace-dt)
	var faded:=count==0 and demo_grace<=0.
	body.collision_layer=0 if faded else 3
	var gather:=smoothstep(.48,GAZE_LOCK_TIME,demo_single_time)
	sight_blend=move_toward(sight_blend,gather if active_single else .68 if count==1 else .33,dt*3.)
	var red:=1. if count==2 else 0.
	overload_blend=move_toward(overload_blend,red,dt*(8. if count==2 else 5.5))
	plate_presence=move_toward(plate_presence,.27 if faded else 1.,dt*2.)
	plate_finish.set_shader_parameter("sight",sight_blend)
	plate_finish.set_shader_parameter("overload",overload_blend)
	plate_spill.light_energy=overload_blend*(.33+.30*sin(phase*23.)+.71*smoothstep(.73,.96,overload_blend))
	plate_finish.set_shader_parameter("presence",plate_presence)
	plate_finish.set_shader_parameter("settling",gather if active_single else 0.)
	board.position.y=move_toward(board.position.y,-.55 if faded else .045,dt*1.8)
	board.position.x=23.85+.018*overload_blend*sin(phase*42.)
	if changed and count==2:
		sound_at("glass_breakout",board_audio.position,-10.,16.)
	elif changed and count==1 and not in_b3:
		board_audio.stop()
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
func fail(reason:String)->void:
	retry=3.;polish.fail_beat();fail_reason=reason
	var clause:=rule_clause_for(reason)
	notice="";msg_time=0.
	var title:=reason
	if reason.begins_with("违反契约A"):title="板面熄灭了"
	elif "过载" in reason:title="桥面塌了"
	elif reason.begins_with("违反契约B") or "扑到" in reason:title="井底的东西追上来了"
	polish.fail_card(title,clause)

## Every death is answered with the exact clause that was broken, so a retry
## teaches the rule instead of only restoring position.
func rule_clause_for(reason:String)->String:
	if "契约A" in reason:return "契约A 第二码：先看见者一秒内移开，后看见者继续注视。"
	if "契约B" in reason:return "契约B 第二码：连续三声呼唤，井底记住你。"
	if "过载" in reason:return "契约A 第一码：同一块板面，每次只容一人注视。"
	if "扑到" in reason:return "契约B 第一码：铁网上的每一步都被听成一次呼唤。"
	if "灯油" in reason:return "灯油读数归零。"
	if "源井" in reason:return "离开可站立的桥面。"
	return ""
func reset_at_checkpoint()->void:
	hale_gate_guide=0
	shortcut_open=false;shortcut_used=false;return_started=false;return_gate_open=false;north_pause=0.;gallery_bell.stop();gallery_impact.stop();kit.return_exit_gate.position.y=0.;siren.volume_db=-17.;exit_requested=false;exit_open=false;reunited=false;evidence_thought_delay=-1.;cues.erase("bait_answer")
	kit.leave_pivot.rotation.y=0.;kit.airlock.position.y=2.4;hale_return_path.clear()
	hale_gate_attempt=false
	crossing=false;crossing_locked=false;distraction=0.;running=false;collected=false;kit.core.show();siren.stop();emergency.hide();cues.erase("core");cues.erase("post");captions.clear()
	if released:hunter.wake();oil=checkpoint_oil;equipped=checkpoint_item
	else:
		taken=false;clock_taken=false;equipped=false;oil=65.;kit.oil_tin.show();kit.clock_cache.show()
		niche_taken=false;kit.niche_oil.show()
		service_signal=Relay.new();kit.clock_shutter.position.y=Relay.HATCH.y
		for i in 3:set_relay_lamp(i,false)
	kit.test_board.show();kit.vault_can.show();contracts.soft_reset();prior_seer=0
	archive.reset_motion(released)
	trial_near_bank=false;crossing_in_hale_view=false;demo_single_time=0.;demo_locked=false
	region=""
	walker.position=Vector3(38.6,.15,10) if released else Vector3(1,.1,0);walker.velocity=Vector3.ZERO;hale.position=walker.position+Vector3(.1,0,.7);polish.reset_beat();hazard=0;holding=false;posting=false;trail.clear();command_path.clear()
	reset_hale_pursuit();hale_yielded=false;last_pos=walker.position;hale_speed=0.
	lamp_on=true;stomp_cool=0.;hale_hold=false;pair_loud=false;both_lamp=false;catwalk_oil_grace=0.
	if released:show_line("checkpoint","……我在这儿。缓口气，我看看你有没有伤着。")
func observation()->Dictionary:return {"phase":"first_expedition","section":mode,"position":str(walker.position),"checkpoint":released,"learned":learned,"paired_gaze":archive.paired,"annotated":archive.note,"plate_observers":observers,"core":collected,"hale_posted":holding}

func mcp_observe()->Dictionary:
	var state:=observation()
	state["archive_evidence"]=archive.facts.snapshot()
	var point:=walker.position
	state.merge({"feet":[point.x,point.y,point.z],"yaw":walker.rotation.y,"pitch":eye.rotation.x,
		"b4":in_b4(point),"oil":snappedf(oil,.01),"oil_taken":taken,"metronome":equipped,"clock_taken":clock_taken,
		"relay_source":service_signal.source,"relay_target":service_signal.target(),
		"relay_heard":service_signal.heard,"locker_open":service_signal.open,
		"focus":focus(),"relay_focus":relay_focus,"prompt":prompt.text,
		"service_caption":caption_toast.text if caption_toast.visible else "",
		"lamp_on":lamp_on,"run_time":snappedf(run_time,.01),"hale_hold":hale_hold,
		"pair_loud":pair_loud,"both_lamp":both_lamp,"hale_order":hale_order_text()},true)
	return state

func review_props()->void:
	var ground:=PlaneMesh.new();ground.size=Vector2(400,400);plinth.mesh=ground;var g:=StandardMaterial3D.new();g.albedo_color=Color("a0998e");plinth.material_override=g;add_child(plinth);plinth.hide()
	add_child(review_witness);review_witness.position=kit.polar(12.45,PI*1.5,4.8);Cast.attach(review_witness,1);review_witness.rotation.y=PI
	var cone:=MeshInstance3D.new();var mesh:=CylinderMesh.new();var target:=Vector3(61,.05,10.1);var top:=review_witness.position+Vector3.UP*1.6;mesh.height=top.distance_to(target);mesh.top_radius=.025;mesh.bottom_radius=1.45;cone.mesh=mesh;var m:=StandardMaterial3D.new();m.transparency=BaseMaterial3D.TRANSPARENCY_ALPHA;m.shading_mode=BaseMaterial3D.SHADING_MODE_UNSHADED;m.albedo_color=Color(.18,.75,.77,.27);cone.material_override=m;review_witness.add_child(cone);cone.global_position=(target+top)*.5;cone.global_basis=Basis(Quaternion(Vector3.UP,(top-target).normalized()));review_witness.hide()
	warning.stream=Sound.SPRING;warning.volume_db=-9.;warning.position=Vector3(61,1,10.1);add_child(warning)
