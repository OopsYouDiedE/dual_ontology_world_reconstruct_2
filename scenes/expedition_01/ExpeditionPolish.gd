extends Node
## Presentation layer for the first expedition: camera rig and cinematic beats,
## HUD, vignette / letterbox / fade overlays, and viewport render parameters.
## Gameplay logic stays in Expedition.gd; this node only reads its state and
## drives eye *position*, *roll*, *fov* and frustum offsets. Yaw/pitch stay owned
## by the player (and by WalkTest / HearingTest), so tests are unaffected.

const BASE_FOV:=73.
const EYE_HEIGHT:=1.57
const LETTERBOX_PX:=46.
const ACCENT:=Color("ffbf75")
const CINEMATIC_LINES:=["start","release","core","evidence","double"]
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
var bob_amp:=0.
var roll:=0.
var intro:=0.
var dread:=0.
var parity:=1.
var last_stride:=0.
var last_y:=0.
var last_vy:=0.
var was_floor:=true
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
var oil_bar:ProgressBar
var oil_fill:StyleBoxFlat
var oil_label:Label
var state_label:Label
var end_card:Label

static func make_font()->Font:
	var font:=SystemFont.new()
	font.font_names=PackedStringArray(["Microsoft YaHei UI","PingFang SC","Noto Sans CJK SC"])
	if Engine.has_meta("review_font"):font.fallbacks=[Engine.get_meta("review_font")]
	return font

static func box(color:Color,radius:=3,margin:=Vector2(14,9))->StyleBoxFlat:
	var s:=StyleBoxFlat.new();s.bg_color=color;s.set_corner_radius_all(radius)
	s.content_margin_left=margin.x;s.content_margin_right=margin.x;s.content_margin_top=margin.y;s.content_margin_bottom=margin.y
	return s

func setup(level:Node,canvas:CanvasLayer)->void:
	lv=level;noise.seed=7;noise.frequency=.9
	_tune_viewport();_tune_camera()
	last_y=lv.walker.position.y
	ui_root=CanvasLayer.new();ui_root.layer=7;add_child(ui_root)
	var top:=CanvasLayer.new();top.layer=20;add_child(top)
	shade=_rect(ui_root,Color.WHITE);var sh:=Shader.new();sh.code=VIGNETTE;var mat:=ShaderMaterial.new();mat.shader=sh;shade.material=mat
	dim=_rect(canvas,Color(0,0,0,0))
	bar_top=_rect(ui_root,Color.BLACK);bar_bottom=_rect(ui_root,Color.BLACK)
	bar_top.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE);bar_bottom.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	bar_top.offset_bottom=0;bar_bottom.offset_top=0
	fade=_rect(top,Color.BLACK)
	end_card=Label.new();top.add_child(end_card);end_card.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT);end_card.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER;end_card.vertical_alignment=VERTICAL_ALIGNMENT_CENTER
	end_card.add_theme_font_override("font",make_font());end_card.add_theme_font_size_override("font_size",30);end_card.add_theme_constant_override("outline_size",8);end_card.mouse_filter=Control.MOUSE_FILTER_IGNORE;end_card.modulate.a=0.
	_build_hud(canvas);oil_bar.value=lv.oil
	fade_a=1.;fade_target=0.;fade_rate=.7;letterbox(3.2)

func _rect(parent:Node,color:Color)->ColorRect:
	var r:=ColorRect.new();parent.add_child(r);r.color=color;r.mouse_filter=Control.MOUSE_FILTER_IGNORE;r.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT);return r

func _build_hud(canvas:CanvasLayer)->void:
	var font:=make_font()
	panel=PanelContainer.new();canvas.add_child(panel);panel.position=Vector2(22,18);panel.mouse_filter=Control.MOUSE_FILTER_IGNORE
	var back:=box(Color(.045,.04,.035,.66),3,Vector2(16,11));back.border_color=ACCENT;back.border_width_left=3;back.shadow_color=Color(0,0,0,.35);back.shadow_size=8
	panel.add_theme_stylebox_override("panel",back)
	var col:=VBoxContainer.new();panel.add_child(col);col.add_theme_constant_override("separation",5);col.mouse_filter=Control.MOUSE_FILTER_IGNORE
	oil_label=Label.new();col.add_child(oil_label)
	oil_bar=ProgressBar.new();col.add_child(oil_bar);oil_bar.custom_minimum_size=Vector2(250,7);oil_bar.show_percentage=false;oil_bar.max_value=100
	oil_fill=box(ACCENT,2,Vector2.ZERO);oil_bar.add_theme_stylebox_override("fill",oil_fill);oil_bar.add_theme_stylebox_override("background",box(Color(1,1,1,.12),2,Vector2.ZERO))
	lv.hud.reparent(col,false);lv.hud.custom_minimum_size=Vector2(250,0);lv.hud.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART;lv.hud.add_theme_font_size_override("font_size",16)
	state_label=Label.new();col.add_child(state_label)
	for l in [oil_label,state_label]:
		l.add_theme_font_override("font",font);l.add_theme_font_size_override("font_size",15);l.add_theme_constant_override("outline_size",4);l.mouse_filter=Control.MOUSE_FILTER_IGNORE
	# Centre reticle: a quiet dot that opens into a ring over anything usable.
	cross=Control.new();canvas.add_child(cross);cross.set_anchors_and_offsets_preset(Control.PRESET_CENTER);cross.mouse_filter=Control.MOUSE_FILTER_IGNORE
	cross.draw.connect(func()->void:
		cross.draw_circle(Vector2.ZERO,2.,Color(1,1,1,.55+.35*ring))
		if ring>.02:cross.draw_arc(Vector2.ZERO,6.+7.*ring,0,TAU,40,Color(ACCENT,ring*.9),1.8,true))
	# Interaction prompt sits just under the reticle, subtitle gets a backing plate.
	var p:Label=lv.prompt;p.offset_top=27;p.offset_bottom=65;p.add_theme_font_size_override("font_size",19)

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
func reset_beat()->void:
	intro=.55;step_offset=0.;land_dip=0.;trauma=0.;fov_off=0.;last_y=lv.walker.position.y;fade_a=1.;fade_to(0.,.9)
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

func _overlay(dt:float)->void:
	if not end_fade:fade_a=move_toward(fade_a,fade_target,dt*fade_rate)
	fade.color.a=fade_a
	bars_timer=maxf(0.,bars_timer-dt);bars=move_toward(bars,1. if bars_timer>0. else 0.,dt*1.6)
	var bar_h:=LETTERBOX_PX*smoothstep(0.,1.,bars)
	bar_top.offset_bottom=bar_h;bar_bottom.offset_top=-bar_h
	var book:bool=lv.manual.visible;dim.color.a=lerpf(dim.color.a,.5 if book else 0.,1.-exp(-10.*dt))
	var live:bool=lv.mode<0 and not book
	cross.visible=live and not lv.finished;panel.visible=not lv.finished
	var m:ShaderMaterial=shade.material
	var low:float=clampf(1.-lv.oil/22.,0.,1.)
	m.set_shader_parameter("strength",.34+.22*low);m.set_shader_parameter("dread",dread)
	var in_shaft:bool=lv.released and lv.walker.position.x>46.
	var pressure:float=clampf(lv.hunter.exposure/1.45,0.,1.) if in_shaft and not lv.collected else 0.
	m.set_shader_parameter("pulse",pressure*(.24+.18*sin(lv.phase*7.)));shade.visible=lv.mode<0
	var want:float=1. if (focus_id!="" and live) else 0.
	ring=lerpf(ring,want,1.-exp(-14.*dt));cross.queue_redraw()

func _look_stick(dt:float)->void:
	var s:=Vector2(Input.get_joy_axis(0,JOY_AXIS_RIGHT_X),Input.get_joy_axis(0,JOY_AXIS_RIGHT_Y))
	if s.length()<.2:return
	s=s.normalized()*pow((s.length()-.2)/.8,1.7)
	lv.walker.rotate_y(-s.x*3.1*dt);lv.eye.rotation.x=clampf(lv.eye.rotation.x-s.y*2.4*dt,-1.48,1.48)

func _dread(dt:float)->void:
	var target:=0.
	var h=lv.hunter;var p:Vector3=lv.walker.position
	if lv.released and h.visible and p.x>46. and not lv.in_return_gallery(p) and lv.retry<=0.:
		var d:=Vector2(p.x-h.position.x,p.z-h.position.z).length()
		var mood:float=1. if h.state=="hunt" else .6 if h.state in ["investigate","lure"] else .3
		target=clampf(1.-d/20.,0.,1.)*mood
	if lv.collected and p.x>46. and not lv.in_return_gallery(p):target=minf(.36,maxf(target,.12+.09*sin(lv.phase*5.)))
	dread=lerpf(dread,target,1.-exp(-3.*dt))
	if h.state!=prev_hunter:
		if h.state=="hunt":kick(.55);punch(7.)
		prev_hunter=h.state
	if dread>.35:trauma=maxf(trauma,dread*dread*.22)

func _rig(dt:float)->void:
	var w:CharacterBody3D=lv.walker;var eye:Camera3D=lv.eye
	var vel:=Vector3(w.velocity.x,0,w.velocity.z);var sp:=vel.length();var grounded:=w.is_on_floor()
	# A tread riser or floor snap moves the body in one physics tick; absorb it so the lens glides.
	var dy:=w.position.y-last_y;last_y=w.position.y
	if absf(dy)>.12 and absf(dy)<.6:step_offset-=dy
	step_offset=lerpf(step_offset,0.,1.-exp(-13.*dt))
	var moving:bool=grounded and sp>.4 and lv.retry<=0.
	bob_amp=lerpf(bob_amp,clampf(sp/3.8,0.,1.6) if moving else 0.,1.-exp(-9.*dt))
	if lv.stride<last_stride-.5:parity=-parity
	last_stride=lv.stride
	var bob:=-cos(TAU*lv.stride)*.016*bob_amp
	var sway:=sin(PI*(lv.stride+(0. if parity>0. else 1.)))*.011*bob_amp
	if grounded and not was_floor and last_vy<-3.:land_dip=minf(.11,-last_vy*.012);kick(.06)
	was_floor=grounded;last_vy=w.velocity.y
	land_dip=lerpf(land_dip,0.,1.-exp(-9.*dt))
	var lean:=(w.basis.inverse()*vel).x/5.8*.02
	roll=lerpf(roll,-lean-sway*.2,1.-exp(-8.*dt))
	trauma=maxf(0.,trauma-dt*1.4);var shake:=trauma*trauma
	var n:=Vector3(noise.get_noise_2d(t*55.,0.),noise.get_noise_2d(t*55.,100.),noise.get_noise_2d(t*55.,200.))
	var breath:=.0035*sin(t*1.6)*(1.-clampf(bob_amp,0.,1.))
	intro=minf(1.,intro+dt/3.4);var k:=1.-smoothstep(0.,1.,intro)
	eye.position=Vector3(sway+n.x*shake*.03,EYE_HEIGHT+bob+breath-land_dip+step_offset-.38*k*k+n.y*shake*.03,0)
	eye.rotation.z=roll+n.z*shake*.05+.05*k
	eye.h_offset=n.x*shake*.05;eye.v_offset=n.y*shake*.05
	var f:=BASE_FOV
	if moving:f+=clampf((sp-3.8)/2.,-1.,1.)*(4. if sp>3.8 else 1.5)
	else:f-=1.2
	if focus_id!="":f-=2.5
	f+=dread*5.+9.*k
	fov_off=lerpf(fov_off,0.,1.-exp(-4.5*dt))
	eye.fov=lerpf(eye.fov,f+fov_off,1.-exp(-6.*dt))

func signal_bait()->void:bait_time=3.2

func _hud(dt:float)->void:
	bait_time=maxf(0.,bait_time-dt)
	var oil:float=lv.oil
	oil_bar.value=lerpf(oil_bar.value,oil,1.-exp(-8.*dt))
	var low:=oil<22.
	oil_fill.bg_color=Color("ff6b4a") if low else ACCENT
	if low and sin(lv.phase*6.)>0.:oil_fill.bg_color=Color("ffd2a0")
	oil_label.text="灯油　%d%%"%ceili(oil);oil_label.modulate=Color("ff9a80") if low else Color("f4ead8")
	var quiet:bool=Input.is_physical_key_pressed(KEY_CTRL) or Input.is_action_pressed("expedition_quiet")
	var well:bool=lv.released and lv.walker.position.x>46.
	var mode_name:="静步" if quiet else "奔跑" if lv.running else "步行"
	var tint:=Color("9fd6e8") if quiet else Color("ff9a80") if lv.running else Color("f4ead8")
	var note:=""
	if well:note="　· 静步压住了脚音" if quiet else ("　· 井底已闻声" if lv.hunter.state=="hunt" else "　· 留意铁网上的脚音")
	if well and not quiet:tint=Color("ffbf75")
	if well and bait_time>0. and not lv.collected:note="　· 井底的动静被引开了";tint=Color("ffda91")
	state_label.text="▸ %s%s\n[Shift] 走跑　[Ctrl] 静步　[1] 手册"%[mode_name,note];state_label.modulate=tint
