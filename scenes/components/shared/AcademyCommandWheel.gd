extends Node
## Industry-standard radial command wheel for Hale (angular pie-slice selection with center
## deadzone, directional pointer, spring-pop open, plus full keyboard 1-5 / scroll / E support).
## The caller filters options, so the wheel never offers an order that cannot be executed.

signal chosen(id:String)
signal cancelled

const UiStyle = preload("res://scenes/components/shared/UiTheme.gd")
const R18n = preload("res://scenes/components/shared/R18n.gd")
const ACCENT := UiStyle.ACCENT
const INK := UiStyle.INK
const NODE_RADIUS := 44.0
const DEADZONE := 34.0
const OUTER_RADIUS := 235.0
var options:Array=[]          # [{id,title,hint,cost?}]
var index:=0
var open:=false
var t:=0.
var cursor:=Vector2.ZERO
var wheel:Control
var font:Font
var closing:=0.
var _in_deadzone:=false

func setup(parent:Node,typeface:Font)->void:
	font=typeface
	wheel=Control.new()
	parent.add_child(wheel)
	wheel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	wheel.mouse_filter=Control.MOUSE_FILTER_IGNORE
	wheel.visible=false
	wheel.draw.connect(_draw)
	wheel.gui_input.connect(_on_gui_input)
	set_process(false)

func bind(items:Array)->void:
	options=items
	index=0  # a fresh wheel never pre-selects an order from the last time it opened
	_in_deadzone=false

func reveal()->void:
	if options.is_empty():return
	open=true;closing=0.;wheel.modulate.a=1.;wheel.visible=true;set_process(true)
	wheel.mouse_filter=Control.MOUSE_FILTER_STOP
	t=0.
	_in_deadzone=false

func dismiss()->void:
	if not open:return
	open=false;closing=.16
	wheel.mouse_filter=Control.MOUSE_FILTER_IGNORE

func confirm()->String:
	if not open or options.is_empty():return ""
	var id:String=options[clampi(index,0,options.size()-1)].id
	dismiss()
	chosen.emit(id)
	return id

func move(step:int)->void:
	if options.is_empty():return
	index=posmod(index+step,options.size())
	_in_deadzone=false

## Industry-standard angular sector hit-test with a safe center deadzone.
func _hit_option(local_pos:Vector2)->int:
	if options.is_empty():return -1
	var center:=wheel.size*.5
	var rel:=local_pos-center
	var dist:=rel.length()
	if dist<DEADZONE:
		return -2 # inside center cancel deadzone
	if dist>OUTER_RADIUS:
		return -1 # background outside the radial ring
	var count:=options.size()
	var span:=TAU/float(maxi(count,1))
	# Shift angle so sector 0 is centered at -PI/2 (12 o'clock)
	var ang:=fposmod(atan2(rel.y,rel.x)+PI*.5+span*.5,TAU)
	return clampi(int(floor(ang/span)),0,count-1)

func _on_gui_input(ev:InputEvent)->void:
	if not open or options.is_empty():return
	if ev is InputEventMouseMotion:
		cursor=ev.position
		var hit:=_hit_option(ev.position)
		if hit==-2:
			_in_deadzone=true
		elif hit>=0:
			_in_deadzone=false
			index=hit
	elif ev is InputEventMouseButton and ev.pressed and ev.button_index==MOUSE_BUTTON_LEFT:
		var hit:=_hit_option(ev.position)
		if hit==-2:
			dismiss()
			cancelled.emit()
		elif hit>=0:
			index=hit
			confirm()
		wheel.accept_event()
	elif ev is InputEventMouseButton and ev.pressed and ev.button_index==MOUSE_BUTTON_RIGHT:
		dismiss()
		cancelled.emit()
		wheel.accept_event()

func _process(dt:float)->void:
	t+=dt
	if not open:
		closing=maxf(0.,closing-dt)
		wheel.modulate.a=closing/.16
		wheel.visible=closing>0.
		if not wheel.visible:set_process(false)
	wheel.queue_redraw()

func _point_for(i:int,count:int,radius:float)->Vector2:
	var span:=TAU/float(maxi(count,1))
	var angle:=-PI*.5+span*i
	return Vector2(cos(angle),sin(angle))*radius

func _draw_wedge(inner_r:float,outer_r:float,a0:float,a1:float,col:Color)->void:
	var segs:=18
	var pts:=PackedVector2Array()
	for s in range(segs+1):
		var a:=lerpf(a0,a1,float(s)/float(segs))
		pts.append(Vector2(cos(a),sin(a))*outer_r)
	for s in range(segs,-1,-1):
		var a:=lerpf(a0,a1,float(s)/float(segs))
		pts.append(Vector2(cos(a),sin(a))*inner_r)
	wheel.draw_colored_polygon(pts,col)

func _draw()->void:
	if options.is_empty():return
	wheel.draw_set_transform(wheel.size*.5)
	# Spring-pop ease out
	var u:=clampf(t/.14,0.,1.)
	var ease:=1.0-pow(1.0-u,3.0)
	var controls:=R18n.t("wheel.controls")
	var controls_width:=font.get_string_size(controls,HORIZONTAL_ALIGNMENT_LEFT,-1,15).x
	wheel.draw_rect(Rect2(Vector2(-controls_width*.5-10,248),Vector2(controls_width+20,27)),Color(INK,.9))
	wheel.draw_string(font,Vector2(-controls_width*.5,267),controls,HORIZONTAL_ALIGNMENT_LEFT,-1,15,UiStyle.TEXT_MAIN)

	var radius:=150.*(.88+.12*ease)
	var outer_ring:=radius+28.
	var inner_ring:=54.
	wheel.draw_circle(Vector2.ZERO,outer_ring,Color(INK,.46*ease))

	# Highlight active radial pie-slice wedge
	var count:=options.size()
	var span:=TAU/float(maxi(count,1))
	if not _in_deadzone:
		var a_mid:=-PI*.5+span*index
		_draw_wedge(inner_ring,outer_ring,a_mid-span*.48,a_mid+span*.48,Color(ACCENT,.18*ease))
		wheel.draw_arc(Vector2.ZERO,outer_ring,a_mid-span*.48,a_mid+span*.48,24,Color(ACCENT,.95*ease),3.0,true)
		var dir:=Vector2(cos(a_mid),sin(a_mid))
		wheel.draw_line(dir*(inner_ring+4.),dir*(radius-NODE_RADIUS-6.),Color(ACCENT,.75*ease),2.0,true)

	# Center hub / cancel deadzone indicator
	wheel.draw_circle(Vector2.ZERO,inner_ring,Color(INK,.76 if _in_deadzone else .54))
	wheel.draw_arc(Vector2.ZERO,inner_ring,0,TAU,40,Color(ACCENT,.85 if _in_deadzone else .38),1.8,true)
	var hub_text:=R18n.pick("取消","Cancel") if _in_deadzone else "Hale"
	var htw:=font.get_string_size(hub_text,HORIZONTAL_ALIGNMENT_LEFT,-1,14).x
	wheel.draw_string(font,Vector2(-htw*.5,5),hub_text,HORIZONTAL_ALIGNMENT_LEFT,-1,14,UiStyle.WARN if _in_deadzone else UiStyle.ACCENT_SOFT)
	wheel.draw_arc(Vector2.ZERO,outer_ring,0,TAU,64,Color(ACCENT,.42*ease),1.4,true)

	for i in count:
		var opt:Dictionary=options[i]
		var c:=_point_for(i,count,radius)
		var picked:=(i==index) and not _in_deadzone
		var nr:=NODE_RADIUS*(1.08 if picked else 1.0)
		wheel.draw_circle(c,nr,Color(INK,.96) if picked else Color(INK,.66))
		wheel.draw_arc(c,nr,0,TAU,40,Color(ACCENT,1. if picked else .35),2.6 if picked else 1.2,true)
		wheel.draw_string(font,c+Vector2(-6,7),str(i+1),HORIZONTAL_ALIGNMENT_LEFT,-1,20,Color(ACCENT,1. if picked else .6))
		var outward:=c.normalized()
		var title:String=opt.title
		var tw:=font.get_string_size(title,HORIZONTAL_ALIGNMENT_LEFT,-1,17).x
		var tp:=c+outward*68.-Vector2(tw*.5,0)
		wheel.draw_string(font,tp,title,HORIZONTAL_ALIGNMENT_LEFT,-1,17,UiStyle.TEXT_MAIN if picked else UiStyle.ACCENT_SOFT)
		if picked:
			var hint:String=String(opt.get("hint",""))
			var cost:String=String(opt.get("cost",""))
			var y_top:=-radius-(142. if cost!="" else 120.)
			if hint!="":
				var hw:=font.get_string_size(hint,HORIZONTAL_ALIGNMENT_LEFT,-1,15).x
				var cw:=font.get_string_size(cost,HORIZONTAL_ALIGNMENT_LEFT,-1,14).x if cost!="" else 0.
				var box_w:=maxf(hw,cw)+24.
				var box_h:=48. if cost!="" else 26.
				wheel.draw_rect(Rect2(Vector2(-box_w*.5,y_top),Vector2(box_w,box_h)),Color(INK,.90))
				wheel.draw_string(font,Vector2(-hw*.5,y_top+18.),hint,HORIZONTAL_ALIGNMENT_LEFT,-1,15,UiStyle.ACCENT_SOFT)
				if cost!="":
					wheel.draw_string(font,Vector2(-cw*.5,y_top+39.),cost,HORIZONTAL_ALIGNMENT_LEFT,-1,14,UiStyle.WARN)
