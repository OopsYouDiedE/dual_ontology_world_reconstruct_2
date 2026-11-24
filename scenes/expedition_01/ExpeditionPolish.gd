extends Node
## Presentation layer for the first expedition: camera rig and cinematic beats,
## HUD, vignette / letterbox / fade overlays, and viewport render parameters.
## Gameplay logic stays in Expedition.gd; this node only reads its state and
## drives eye *position*, *roll*, *fov* and frustum offsets. Yaw/pitch stay owned
## by the player (and by WalkTest / HearingTest), so tests are unaffected.

const UiStyle = preload("res://scenes/components/shared/UiTheme.gd")
const R18n = preload("res://scenes/components/shared/R18n.gd")
const Feel = preload("res://scenes/components/shared/FeelProfile.gd")

const BASE_FOV:=73.
const EYE_HEIGHT:=1.57
const LETTERBOX_PX:=46.
const ACCENT:=UiStyle.ACCENT
const CINEMATIC_LINES:=["start","release","core","evidence","double","reunion"]
const VIGNETTE:="""shader_type canvas_item;
uniform float strength=.36;
uniform float dread=.0;
uniform float pulse=.0;
void fragment(){
	vec2 uv=UV-.5;uv.x*=1.12;
	float d=smoothstep(.16,.82,dot(uv,uv)*2.2);
	vec3 col=mix(vec3(.018,.014,.01),vec3(.42,.0,.018),clamp(dread+pulse,.0,1.));
	COLOR=vec4(col,d*clamp(strength+dread*.5+pulse*.3,.0,.92));
}
"""

var lv                      # Expedition.gd root (untyped: avoids a preload cycle)
var focus_id:=""
var look_sens:=.0022
var t:=0.
var trauma:=0.
var fov_off:=0.
var step_offset:=0.
var land_dip:=0.
var threshold_dip:=0.
var bob_amp:=0.
var roll:=0.
var intro:=0.
var dread:=0.
var parity:=1.
var last_stride:=0.
var last_y:=0.
var prev_hunter:=""
var bait_time:=0.
var was_captured:=false
var fade_a:=1.
var end_fade:=false
var fade_target:=0.
var fade_rate:=.7
var bars:=0.
var bars_timer:=0.
var ring:=0.
var noise:=FastNoiseLite.new()
var saved:={}
var ui_root:CanvasLayer
var shade:ColorRect
var fade:ColorRect
var bar_top:ColorRect
var bar_bottom:ColorRect
var dim:ColorRect
var cross:Control
var panel:PanelContainer
var debug_layer:=CanvasLayer.new()
var debug_enabled:=false
var debug_panel:PanelContainer
var oil_bar:ProgressBar
var oil_fill:StyleBoxFlat
var oil_label:Label
var objective_label:Label
var hale_brief:Label
var lang_badge:Label
var state_label:Label
var end_card:Label
var rule_tick:Label
var time_label:Label
var hale_label:Label
var quiet_eye:=0.
var was_demo:=false
var was_shaft:=false
var card_title:Label
var card_rule:Label
var card_note:Label
var card_time:=0.
var fail_title:Label
var fail_body:Label
var fail_time:=0.
var beads:Array[Control]=[]
var bead_row:HBoxContainer
var trust_row:HBoxContainer
var plate_line:Label
var bead_lit:=0
var card_holder:Control
var fail_holder_ctl:Control

static func make_font()->Font:
	return UiStyle.make_font()

static func box(color:Color,radius:=3,margin:=Vector2(14,9))->StyleBoxFlat:
	return UiStyle.panel_box(color,radius,margin)

func setup(level:Node,canvas:CanvasLayer)->void:
	lv=level;noise.seed=7;noise.frequency=.9
	_tune_viewport();_tune_camera()
	last_y=lv.walker.position.y
	ui_root=CanvasLayer.new();ui_root.layer=7;add_child(ui_root)
	var top:=CanvasLayer.new();top.layer=20;add_child(top)
	shade=_rect(ui_root,Color.WHITE);var sh:=Shader.new();sh.code=VIGNETTE;var mat:=ShaderMaterial.new();mat.shader=sh;shade.material=mat
	dim=_rect(canvas,Color(0,0,0,0))
	canvas.move_child(dim,lv.manual.get_index())
	bar_top=_rect(ui_root,Color.BLACK);bar_bottom=_rect(ui_root,Color.BLACK)
	bar_top.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE);bar_bottom.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	bar_top.offset_bottom=0;bar_bottom.offset_top=0
	fade=_rect(top,Color.BLACK)
	end_card=Label.new();top.add_child(end_card);end_card.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT);end_card.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER;end_card.vertical_alignment=VERTICAL_ALIGNMENT_CENTER
	end_card.add_theme_font_override("font",make_font());end_card.add_theme_font_size_override("font_size",30);end_card.add_theme_constant_override("outline_size",8);end_card.mouse_filter=Control.MOUSE_FILTER_IGNORE;end_card.modulate.a=0.
	debug_layer.name="ExpeditionDebug";debug_layer.layer=9;add_child(debug_layer);debug_layer.hide()
	_build_hud(canvas);oil_bar.value=lv.oil
	fade_a=1.;fade_target=0.;fade_rate=.7;letterbox(3.2)

func _rect(parent:Node,color:Color)->ColorRect:
	var r:=ColorRect.new();parent.add_child(r);r.color=color;r.mouse_filter=Control.MOUSE_FILTER_IGNORE;r.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT);return r

func _build_hud(canvas:CanvasLayer)->void:
	var font:=make_font()
	panel=PanelContainer.new();canvas.add_child(panel);panel.position=Vector2(22,18);panel.mouse_filter=Control.MOUSE_FILTER_IGNORE
	var back:=UiStyle.panel_box(UiStyle.PANEL_BG,3,Vector2(16,11),3,0,ACCENT)
	panel.add_theme_stylebox_override("panel",back)
	var col:=VBoxContainer.new();panel.add_child(col);col.add_theme_constant_override("separation",5);col.mouse_filter=Control.MOUSE_FILTER_IGNORE
	var top_row:=HBoxContainer.new();col.add_child(top_row);top_row.add_theme_constant_override("separation",14);top_row.mouse_filter=Control.MOUSE_FILTER_IGNORE
	oil_label=Label.new();top_row.add_child(oil_label)
	lang_badge=Label.new();top_row.add_child(lang_badge)
	oil_bar=ProgressBar.new();col.add_child(oil_bar);oil_bar.custom_minimum_size=Vector2(146,4);oil_bar.show_percentage=false;oil_bar.max_value=100
	oil_fill=box(ACCENT,2,Vector2.ZERO);oil_bar.add_theme_stylebox_override("fill",oil_fill);oil_bar.add_theme_stylebox_override("background",box(Color(1,1,1,.12),2,Vector2.ZERO))
	objective_label=Label.new();objective_label.text=R18n.t("hud.obj.fetch");col.add_child(objective_label)
	hale_brief=Label.new();col.add_child(hale_brief)
	debug_panel=PanelContainer.new();debug_layer.add_child(debug_panel)
	debug_panel.position=Vector2(22,146);debug_panel.mouse_filter=Control.MOUSE_FILTER_IGNORE
	debug_panel.add_theme_stylebox_override("panel",back)
	var diagnostics:=VBoxContainer.new();debug_panel.add_child(diagnostics);diagnostics.mouse_filter=Control.MOUSE_FILTER_IGNORE
	lv.hud.reparent(diagnostics,false);lv.hud.custom_minimum_size=Vector2(250,0);lv.hud.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART;lv.hud.add_theme_font_size_override("font_size",16)
	state_label=Label.new();diagnostics.add_child(state_label)
	time_label=Label.new();diagnostics.add_child(time_label)
	hale_label=Label.new();diagnostics.add_child(hale_label)
	for l in [oil_label,objective_label,hale_brief,state_label,time_label,hale_label]:
		UiStyle.style_label(l,font,15,UiStyle.TEXT_MAIN,4)
	UiStyle.style_label(lang_badge,font,13,UiStyle.TEXT_MUTED,3)
	hale_brief.add_theme_font_size_override("font_size",13)
	hale_brief.add_theme_color_override("font_color",UiStyle.ACCENT_SOFT)
	# Centre reticle: a quiet dot that opens over usable objects and tightens during steady aim.
	cross=Control.new();canvas.add_child(cross);cross.set_anchors_and_offsets_preset(Control.PRESET_CENTER);cross.mouse_filter=Control.MOUSE_FILTER_IGNORE
	cross.draw.connect(func()->void:
		var aim_val:float=clampf(lv.aim,0.,1.) if lv!=null else 0.
		var dot_r:=lerpf(2.0,1.45,aim_val)
		cross.draw_circle(Vector2.ZERO,dot_r,Color(1,1,1,.58+.34*maxf(ring,aim_val)))
		if aim_val>.05:
			cross.draw_arc(Vector2.ZERO,lerpf(11.5,5.2,aim_val),0,TAU,32,Color(UiStyle.ACCENT_SOFT,aim_val*.72),1.2,true)
		if ring>.02:
			cross.draw_arc(Vector2.ZERO,6.+7.*ring,0,TAU,40,Color(ACCENT,ring*.9),1.8,true))
	# Interaction prompt sits just under the reticle, subtitle gets a backing plate.
	var p:Label=lv.prompt;p.offset_top=27;p.offset_bottom=65;p.add_theme_font_size_override("font_size",19)
	# 中央下方的规则违例 ticker：同声律／独灯律触发时亮红字。
	rule_tick=Label.new();canvas.add_child(rule_tick)
	rule_tick.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	rule_tick.offset_left=-340;rule_tick.offset_right=340;rule_tick.offset_top=140;rule_tick.offset_bottom=168
	rule_tick.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER
	UiStyle.style_label(rule_tick,font,17,UiStyle.DANGER,7)
	rule_tick.add_theme_color_override("font_outline_color",UiStyle.DANGER_OUTLINE)
	rule_tick.text="";rule_tick.modulate.a=0.
	_build_rule_hud(canvas,font)

## Contract readouts: three iron beads (contract B), live clause line (contract A),
## region card, and fail clause live on the gameplay HUD canvas so players can read
## rules without opening F3 diagnostics.
func _build_rule_hud(canvas:CanvasLayer,font:Font)->void:
	plate_line=Label.new();canvas.add_child(plate_line)
	plate_line.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	plate_line.offset_left=-280;plate_line.offset_right=280;plate_line.offset_top=84;plate_line.offset_bottom=110
	plate_line.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER
	UiStyle.style_label(plate_line,font,16,UiStyle.ACCENT_SOFT,6)
	bead_lit=0
	bead_row=HBoxContainer.new();canvas.add_child(bead_row)
	bead_row.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	bead_row.offset_left=-36;bead_row.offset_right=36;bead_row.offset_top=114;bead_row.offset_bottom=130
	bead_row.add_theme_constant_override("separation",6);bead_row.alignment=BoxContainer.ALIGNMENT_CENTER
	bead_row.mouse_filter=Control.MOUSE_FILTER_IGNORE
	for i in 3:
		var bead:=Panel.new();bead.custom_minimum_size=Vector2(10,10);bead_row.add_child(bead)
		var s:=box(Color(1,1,1,.13),5,Vector2.ZERO);bead.add_theme_stylebox_override("panel",s);beads.append(bead)
	# Region card, top right.
	var holder:=PanelContainer.new();canvas.add_child(holder)
	holder.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	holder.offset_left=-382;holder.offset_right=-24;holder.offset_top=22;holder.offset_bottom=132
	var back:=UiStyle.panel_box(UiStyle.PANEL_BG_DEEP,4,Vector2(16,12),0,3,ACCENT)
	holder.add_theme_stylebox_override("panel",back);holder.mouse_filter=Control.MOUSE_FILTER_IGNORE
	var col:=VBoxContainer.new();holder.add_child(col);col.add_theme_constant_override("separation",3)
	col.mouse_filter=Control.MOUSE_FILTER_IGNORE
	card_title=Label.new();card_rule=Label.new();card_note=Label.new()
	for l in [card_title,card_rule,card_note]:
		col.add_child(l);l.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
		l.add_theme_font_override("font",font);l.mouse_filter=Control.MOUSE_FILTER_IGNORE
	card_title.add_theme_font_size_override("font_size",17);card_title.add_theme_color_override("font_color",ACCENT)
	card_rule.add_theme_font_size_override("font_size",15);card_rule.add_theme_color_override("font_color",UiStyle.TEXT_MAIN)
	card_note.add_theme_font_size_override("font_size",14);card_note.add_theme_color_override("font_color",UiStyle.TEXT_MUTED)
	holder.modulate.a=0.;card_time=0.;card_holder=holder
	# Fail card, centred under the letterbox.
	var fail_holder:=VBoxContainer.new();canvas.add_child(fail_holder)
	fail_holder.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	fail_holder.offset_left=-330;fail_holder.offset_right=330;fail_holder.offset_top=-56;fail_holder.offset_bottom=56
	fail_holder.alignment=BoxContainer.ALIGNMENT_CENTER;fail_holder.add_theme_constant_override("separation",6)
	fail_holder.mouse_filter=Control.MOUSE_FILTER_IGNORE
	fail_title=Label.new();fail_body=Label.new()
	for l in [fail_title,fail_body]:
		fail_holder.add_child(l);l.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER
		l.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART;l.add_theme_font_override("font",font)
		l.mouse_filter=Control.MOUSE_FILTER_IGNORE
	fail_title.add_theme_font_size_override("font_size",25);fail_title.add_theme_constant_override("outline_size",8)
	fail_body.add_theme_font_size_override("font_size",17);fail_body.add_theme_constant_override("outline_size",7)
	fail_body.add_theme_color_override("font_color",UiStyle.WARN)
	fail_holder.modulate.a=0.;fail_time=0.;fail_holder_ctl=fail_holder
	_keep(holder);_keep(fail_holder);fail_holder.name="FailCard";holder.name="RuleCard"

func _keep(n:Node)->void:
	n.set_meta("polish_hud",true)

func card(title:String,rule:String,note:String)->void:
	card_title.text=title;card_rule.text=rule;card_note.text=note;card_time=3.4

func fail_card(reason:String,clause:String)->void:
	fail_title.text=reason;fail_body.text=clause;fail_time=3.0

func _tune_camera()->void:
	var eye:Camera3D=lv.eye;eye.fov=BASE_FOV;eye.near=.05;eye.far=180.

# Render parameters that belong to the viewport rather than the Environment.
func _tune_viewport()->void:
	var vp:Viewport=lv.get_viewport()
	saved={"msaa":vp.msaa_3d,"deband":vp.use_debanding}
	vp.msaa_3d=Viewport.MSAA_4X;vp.use_debanding=true;vp.screen_space_aa=Viewport.SCREEN_SPACE_AA_DISABLED
	vp.positional_shadow_atlas_size=4096;vp.positional_shadow_atlas_quad_0=Viewport.SHADOW_ATLAS_QUADRANT_SUBDIV_16;vp.positional_shadow_atlas_quad_1=Viewport.SHADOW_ATLAS_QUADRANT_SUBDIV_16

func _exit_tree()->void:
	if saved.is_empty() or not is_instance_valid(lv):return
	var vp:Viewport=lv.get_viewport()
	if vp==null:return
	vp.msaa_3d=saved.msaa;vp.use_debanding=saved.deband

# ---- events (called from Expedition.gd) -------------------------------------
func kick(amount:float)->void:trauma=minf(1.,trauma+amount)
func punch(deg:float)->void:fov_off+=deg
func letterbox(seconds:float)->void:bars_timer=maxf(bars_timer,seconds)
func fade_to(alpha:float,seconds:float)->void:fade_target=alpha;fade_rate=1./maxf(.05,seconds)
func fail_beat()->void:kick(.9);punch(9.);fade_to(1.,1.9)
func on_land(impact_vy:float)->void:
	var dip:=Feel.landing_dip(impact_vy)
	if dip<=0.:return
	land_dip=maxf(land_dip,dip)
	kick(Feel.landing_trauma(impact_vy))
func reset_beat()->void:
	intro=.55;step_offset=0.;land_dip=0.;threshold_dip=0.;trauma=0.;fov_off=0.;last_y=lv.walker.position.y;fade_a=1.;fade_to(0.,.9)
func on_book(open:bool)->void:
	if open:was_captured=Input.mouse_mode==Input.MOUSE_MODE_CAPTURED;Input.mouse_mode=Input.MOUSE_MODE_VISIBLE
	elif was_captured:Input.mouse_mode=Input.MOUSE_MODE_CAPTURED
func finish(title:String,sub:String)->Tween:
	end_card.text=title+"\n\n"+sub;bars_timer=0.;end_fade=true
	var sequence:=create_tween().set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	sequence.tween_property(self,"fade_a",1.,1.55)
	sequence.tween_interval(.18)
	sequence.tween_property(end_card,"modulate:a",1.,1.15)
	sequence.tween_interval(2.8)
	return sequence

# ---- per-frame --------------------------------------------------------------
func _process(dt:float)->void:
	if lv==null or not is_instance_valid(lv):return
	t+=dt;dt=minf(dt,.1)
	_overlay(dt)
	var playing:bool=lv.mode<0 and not lv.manual.visible and not lv.finished
	if playing:
		_look_stick(dt);_dread(dt);_rig(dt);_hud(dt)

func toggle_debug()->void:
	debug_enabled=not debug_enabled
	sync_debug_visibility()

func sync_debug_visibility()->void:
	debug_layer.visible=debug_enabled and lv.mode<0 and not lv.manual.visible and not lv.finished and not lv.wheel_open

func _overlay(dt:float)->void:
	if not end_fade:fade_a=move_toward(fade_a,fade_target,dt*fade_rate)
	fade.color.a=fade_a
	bars_timer=maxf(0.,bars_timer-dt);bars=move_toward(bars,1. if bars_timer>0. else 0.,dt*1.6)
	var bar_h:=LETTERBOX_PX*smoothstep(0.,1.,bars)
	bar_top.offset_bottom=bar_h;bar_bottom.offset_top=-bar_h
	var book:bool=lv.manual.visible;dim.color.a=lerpf(dim.color.a,.5 if book else 0.,Feel.exp_damp(10.,dt))
	var live:bool=lv.mode<0 and not book
	var hud_live:bool=live and not lv.finished and not lv.wheel_open
	cross.visible=hud_live;panel.visible=hud_live
	rule_tick.visible=hud_live;fail_holder_ctl.visible=hud_live
	plate_line.visible=hud_live and plate_line.text!=""
	if card_holder:card_holder.visible=hud_live and card_time>0.
	fail_body.visible=fail_body.text!=""
	sync_debug_visibility()
	var m:ShaderMaterial=shade.material
	var low:float=clampf(1.-lv.oil/22.,0.,1.)
	var strength:float=.34+.22*low
	if not lv.lamp_on and lv.walker.position.x>46.:strength+=.22
	m.set_shader_parameter("strength",strength);m.set_shader_parameter("dread",dread)
	var in_shaft:bool=lv.released and lv.walker.position.x>46.
	var pressure:float=clampf(lv.hunter.exposure/1.45,0.,1.) if in_shaft and not lv.collected else 0.
	m.set_shader_parameter("pulse",pressure*(.24+.18*sin(lv.phase*7.)));shade.visible=lv.mode<0
	var want:float=1. if (focus_id!="" and live) else 0.
	ring=lerpf(ring,want,Feel.exp_damp(14.,dt));cross.queue_redraw()

func _look_stick(dt:float)->void:
	var s:=Vector2(Input.get_joy_axis(0,JOY_AXIS_RIGHT_X),Input.get_joy_axis(0,JOY_AXIS_RIGHT_Y))
	if s.length()<.2:return
	s=s.normalized()*pow((s.length()-.2)/.8,1.7)*Feel.aim_gain_scale(lv.aim)
	lv.walker.rotate_y(-s.x*3.1*dt);lv.eye.rotation.x=clampf(lv.eye.rotation.x-s.y*2.4*dt,-1.48,1.48)

func _dread(dt:float)->void:
	var target:=0.
	var h=lv.hunter;var p:Vector3=lv.walker.position
	if lv.released and h.visible and p.x>46. and not lv.in_return_gallery(p) and lv.retry<=0.:
		var d:=Vector2(p.x-h.position.x,p.z-h.position.z).length()
		var mood:float=1. if h.state=="hunt" else .6 if h.state in ["investigate","lure"] else .3
		target=clampf(1.-d/20.,0.,1.)*mood
	if lv.both_lamp and lv.released and p.x>46. and not lv.in_return_gallery(p):target=maxf(target,.34)
	if lv.collected and p.x>46. and not lv.in_return_gallery(p):target=minf(.36,maxf(target,.12+.09*sin(lv.phase*5.)))
	dread=lerpf(dread,target,Feel.exp_damp(3.,dt))
	if h.state!=prev_hunter:
		if h.state=="hunt":kick(.55);punch(7.)
		prev_hunter=h.state
	if dread>.35:trauma=maxf(trauma,dread*dread*.22)

func _rig(dt:float)->void:
	var w:CharacterBody3D=lv.walker;var eye:Camera3D=lv.eye
	var vel:=Vector3(w.velocity.x,0,w.velocity.z);var sp:=vel.length();var grounded:=w.is_on_floor()
	# Absorb grounded tread risers and 0.12 m thresholds so the lens glides smoothly.
	var dy:=w.position.y-last_y;last_y=w.position.y
	if grounded and absf(dy)>Feel.STEP_ABSORB_MIN and absf(dy)<Feel.STEP_ABSORB_MAX:step_offset-=dy
	step_offset=lerpf(step_offset,0.,Feel.exp_damp(13.,dt))
	var moving:bool=grounded and sp>.4 and lv.retry<=0.
	bob_amp=lerpf(bob_amp,clampf(sp/3.8,0.,1.45) if moving else 0.,Feel.exp_damp(9.,dt))
	if lv.stride<last_stride-.5:parity=-parity
	last_stride=lv.stride
	var bob:=-cos(TAU*lv.stride)*.014*bob_amp
	var sway:=sin(PI*(lv.stride+(0. if parity>0. else 1.)))*.010*bob_amp
	land_dip=lerpf(land_dip,0.,Feel.exp_damp(11.,dt))
	threshold_dip=lerpf(threshold_dip,0.,Feel.exp_damp(10.,dt))
	var lean:=(w.basis.inverse()*vel).x/5.8*.02
	roll=lerpf(roll,-lean-sway*.2,Feel.exp_damp(8.,dt))
	trauma=maxf(0.,trauma-dt*1.4);var shake:=trauma*trauma
	var n:=Vector3(noise.get_noise_2d(t*55.,0.),noise.get_noise_2d(t*55.,100.),noise.get_noise_2d(t*55.,200.))
	var breath:=.0035*sin(t*1.6)*(1.-clampf(bob_amp,0.,1.))*lerpf(1.,Feel.AIM_BREATH_SCALE,lv.aim)
	# 静步压身：视高 1.57 → 1.34 平滑下蹲，潜行有重量感。
	var quiet_posture:=Input.is_physical_key_pressed(KEY_CTRL) or Input.is_action_pressed("expedition_quiet")
	quiet_eye=lerpf(quiet_eye,1. if quiet_posture else 0.,Feel.exp_damp(8.,dt))
	intro=minf(1.,intro+dt/3.4);var k:=1.-smoothstep(0.,1.,intro)
	eye.position=Vector3(sway+n.x*shake*.03,lerpf(EYE_HEIGHT,1.34,quiet_eye)+bob+breath-land_dip+step_offset-.38*k*k+n.y*shake*.03,0)
	eye.rotation.z=roll+n.z*shake*.05+.05*k
	eye.h_offset=n.x*shake*.05;eye.v_offset=n.y*shake*.05-threshold_dip
	var f:=BASE_FOV
	if moving:f+=clampf((sp-3.8)/2.,-1.,1.)*(4. if sp>3.8 else 1.5)
	else:f-=1.2
	if focus_id!="":f-=2.5
	f-=6.*lv.aim
	f+=dread*5.+9.*k
	fov_off=lerpf(fov_off,0.,Feel.exp_damp(4.5,dt))
	eye.fov=lerpf(eye.fov,f+fov_off,Feel.exp_damp(6.,dt))
	# 运镜节拍：凝视锁定瞬间 zoom punch；首次进源井 letterbox + 收束。
	if lv.demo_locked and not was_demo:punch(-2.2);kick(.12)
	was_demo=lv.demo_locked
	var in_shaft:bool=lv.released and lv.walker.position.x>46. and not lv.in_return_gallery(lv.walker.position)
	if in_shaft and not was_shaft:letterbox(1.1);punch(-2.)
	was_shaft=in_shaft

func signal_bait()->void:bait_time=3.2

## A rising portcullis: a rattle, then the leaf travels. The camera answers the
## first rattle with a short low hit and the second with a lift, so the player
## feels the gate leave the floor without losing control.
func gate_lift(gate:Node)->void:
	if gate==null:return
	var base:float=gate.position.y
	var tw:=create_tween()
	tw.tween_interval(.14)
	tw.tween_callback(func()->void:
		shake_once(.22,3.)
		punch(-2.)
		if lv!=null and lv.has_method("sound_at"):
			lv.sound_at("iron",Vector3(36.,1.5,-1.35),-14.,18.)
			lv.sound_at("iron",Vector3(36.,1.5,1.35),-14.,18.))
	tw.tween_property(gate,"position:y",base+.02,.15).set_trans(Tween.TRANS_SINE)
	tw.tween_property(gate,"position:y",base+4.0,.72).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tw.tween_callback(func()->void:
		punch(2.4)
		kick(.30))

## A short door/hush beat used when the player crosses a threshold.
func threshold()->void:
	punch(-2.);kick(.10);threshold_dip=.018

func shake_once(amount:float,deg:float)->void:
	kick(amount);punch(deg)

func _hud(dt:float)->void:
	bait_time=maxf(0.,bait_time-dt)
	var oil:float=lv.oil
	oil_bar.value=lerpf(oil_bar.value,oil,Feel.exp_damp(8.,dt))
	var low:=oil<22.
	oil_fill.bg_color=UiStyle.DANGER if low else ACCENT
	if low and sin(lv.phase*6.)>0.:oil_fill.bg_color=Color("ffd2a0")
	oil_label.text=R18n.t("hud.oil",[ceili(oil)]);oil_label.modulate=Color("ff9a80") if low else UiStyle.TEXT_MAIN
	lang_badge.text=R18n.t("hud.lang_badge")
	objective_label.text=R18n.t("hud.obj.return") if lv.collected else R18n.t("hud.obj.fetch")
	var hale_text:=R18n.t("hud.hale_prefix",[lv.hale_order_text()])
	hale_brief.text=hale_text
	var quiet:bool=Input.is_physical_key_pressed(KEY_CTRL) or Input.is_action_pressed("expedition_quiet")
	var well:bool=lv.released and lv.walker.position.x>46.
	var mode_name:=R18n.t("hud.mode.quiet") if quiet else R18n.t("hud.mode.run") if lv.running else R18n.t("hud.mode.walk")
	var tint:=UiStyle.QUIET if quiet else Color("ff9a80") if lv.running else UiStyle.TEXT_MAIN
	var note:=""
	if well:note=R18n.t("hud.note.quiet_well") if quiet else (R18n.t("hud.note.hunt") if lv.hunter.state=="hunt" else R18n.t("hud.note.iron_watch"))
	if well and not quiet:tint=ACCENT
	if well and bait_time>0. and not lv.collected:note=R18n.t("hud.note.bait");tint=Color("ffda91")
	if lv.pair_loud:note=R18n.t("hud.note.pair_loud");tint=UiStyle.DANGER
	elif lv.both_lamp and well:note=R18n.t("hud.note.both_lamp");tint=UiStyle.DANGER
	state_label.text="▸ %s%s"%[mode_name,note];state_label.modulate=tint
	var secs:=int(lv.run_time)
	time_label.text=R18n.t("hud.time",[secs/60,secs%60])
	hale_label.text=hale_text
	var tick:=""
	if lv.pair_loud:tick=R18n.t("hud.tick.pair_loud")
	elif lv.both_lamp and well:tick=R18n.t("hud.tick.both_lamp")
	rule_tick.text=tick
	rule_tick.modulate.a=lerpf(rule_tick.modulate.a,1. if tick!="" else 0.,Feel.exp_damp(8.,dt))
	_rules(dt)

## Live contract readout. Contract A speaks only while two lines overlap;
## contract B keeps a three-bead tally while iron is underfoot or remembered.
func _rules(dt:float)->void:
	var c=lv.contracts
	var clause:String=c.a_hint()
	if clause=="":
		clause=c.b_hint()
	plate_line.text=clause
	plate_line.modulate=Color("ff9a80") if lv.fail_reason!="" and c.a_state=="blackout" else UiStyle.ACCENT_SOFT
	var filled:int=c.b_beads()
	var in_shaft:bool=lv.released and lv.walker.position.x>46. and not lv.in_return_gallery(lv.walker.position)
	var hud_live:bool=lv.mode<0 and not lv.manual.visible and not lv.finished and not lv.wheel_open
	if bead_row:
		bead_row.visible=hud_live and (in_shaft or filled>0 or c.b_remembered)
	for i in beads.size():
		var on:bool=i<filled
		var style:StyleBoxFlat=beads[i].get_theme_stylebox("panel")
		style.bg_color=Color("ff8a63") if on else (Color("ffb070") if c.b_remembered else Color(1,1,1,.13))
		style.border_color=Color(1,1,1,.22);style.set_border_width_all(1)
	card_time=maxf(0.,card_time-dt)
	if card_holder:
		card_holder.modulate.a=clampf(card_time/.55,0.,1.)
	fail_time=maxf(0.,fail_time-dt)
	if fail_holder_ctl:
		fail_holder_ctl.modulate.a=clampf(fail_time/.45,0.,1.)
