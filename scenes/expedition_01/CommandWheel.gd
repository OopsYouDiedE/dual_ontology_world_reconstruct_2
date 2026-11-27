extends Node
## Command wheel for Hale. Q opens it (Q on Hale, the gate or the north window acts
## directly instead); hover/click a sector, 1-5, scroll wheel, or E confirms. The
## caller filters options, so the wheel never offers an order that cannot be executed.

signal chosen(id:String)
signal cancelled

const UiStyle = preload("res://scenes/components/shared/UiTheme.gd")
const R18n = preload("res://scenes/components/shared/R18n.gd")
const ACCENT := UiStyle.ACCENT
const INK := UiStyle.INK
const NODE_RADIUS := 44.0
var options:Array=[]          # [{id,title,hint,cost?}]
var index:=0
var open:=false
var t:=0.
var cursor:=Vector2.ZERO
var wheel:Control
var font:Font
var closing:=0.

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

func reveal()->void:
	if options.is_empty():return
	open=true;closing=0.;wheel.modulate.a=1.;wheel.visible=true;set_process(true)
	wheel.mouse_filter=Control.MOUSE_FILTER_STOP
	t=0.

func dismiss()->void:
	if not open:return
	open=false;closing=.18
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

func _hit_option(local_pos:Vector2)->int:
	if options.is_empty():return -1
	var center:=wheel.size*.5
	var rel:=local_pos-center
	var radius:=150.
	for i in options.size():
		if rel.distance_to(_point_for(i,options.size(),radius))<=NODE_RADIUS+4.:
			return i
	return -1

func _on_gui_input(ev:InputEvent)->void:
	if not open or options.is_empty():return
	if ev is InputEventMouseMotion:
		cursor=ev.position
		var hovered:=_hit_option(ev.position)
		if hovered>=0:
			index=hovered
	elif ev is InputEventMouseButton and ev.pressed and ev.button_index==MOUSE_BUTTON_LEFT:
		var clicked:=_hit_option(ev.position)
		if clicked>=0:
			index=clicked
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
		wheel.modulate.a=closing/.18
		wheel.visible=closing>0.
		if not wheel.visible:set_process(false)
	wheel.queue_redraw()

func _point_for(i:int,count:int,radius:float)->Vector2:
	var span:=TAU/float(maxi(count,1))
	var angle:=-PI*.5+span*i
	return Vector2(cos(angle),sin(angle))*radius

func _draw()->void:
	if options.is_empty():return
	# The wheel is a full-rect overlay; everything is drawn around its centre.
	wheel.draw_set_transform(wheel.size*.5)
	var ease:=smoothstep(0.,1.,clampf(t/.14,0.,1.))
	var controls:=R18n.t("wheel.controls")
	var controls_width:=font.get_string_size(controls,HORIZONTAL_ALIGNMENT_LEFT,-1,15).x
	wheel.draw_rect(Rect2(Vector2(-controls_width*.5-10,248),Vector2(controls_width+20,27)),Color(INK,.9))
	wheel.draw_string(font,Vector2(-controls_width*.5,267),controls,HORIZONTAL_ALIGNMENT_LEFT,-1,15,UiStyle.TEXT_MAIN)
	var radius:=150.*(.86+.14*ease)
	wheel.draw_circle(Vector2.ZERO,radius+26.,Color(INK, .44*ease))
	wheel.draw_circle(Vector2.ZERO,58.,Color(INK, .32*ease))
	wheel.draw_arc(Vector2.ZERO,radius+26.,0,TAU,64,Color(ACCENT,.55*ease),1.6,true)
	for i in options.size():
		var opt:Dictionary=options[i]
		var c:=_point_for(i,options.size(),radius)
		var picked:=i==index
		wheel.draw_circle(c,NODE_RADIUS,Color(INK,.94) if picked else Color(INK,.64))
		wheel.draw_arc(c,NODE_RADIUS,0,TAU,40,Color(ACCENT,1. if picked else .35),2.4 if picked else 1.2,true)
		wheel.draw_string(font,c+Vector2(-6,-8),str(i+1),HORIZONTAL_ALIGNMENT_LEFT,-1,20,Color(ACCENT,1. if picked else .6))
		# Labels sit away from the centre so arcs never overlap each other.
		var outward:=c.normalized()
		var title:String=opt.title
		var tw:=font.get_string_size(title,HORIZONTAL_ALIGNMENT_LEFT,-1,17).x
		var tp:=c+outward*66.-Vector2(tw*.5,0)
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
				wheel.draw_rect(Rect2(Vector2(-box_w*.5,y_top),Vector2(box_w,box_h)),Color(INK,.88))
				wheel.draw_string(font,Vector2(-hw*.5,y_top+18.),hint,HORIZONTAL_ALIGNMENT_LEFT,-1,15,UiStyle.ACCENT_SOFT)
				if cost!="":
					wheel.draw_string(font,Vector2(-cw*.5,y_top+39.),cost,HORIZONTAL_ALIGNMENT_LEFT,-1,14,UiStyle.WARN)
