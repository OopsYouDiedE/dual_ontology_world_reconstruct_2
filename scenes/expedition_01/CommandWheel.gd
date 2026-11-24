extends Node
## Command wheel for Hale. Hold or tap Q to open; 1/2/3, the wheel arcs, or
## E confirm an intent. Options are filtered by what is in front
## of the player, so the wheel never offers an order that cannot be executed.

signal chosen(id:String)

const ACCENT:=Color("ffbf75")
const INK:=Color("221c16")
var options:Array=[]          # [{id,title,hint}]
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
	set_process(false)

func bind(items:Array)->void:
	options=items
	index=clampi(index,0,maxi(0,items.size()-1))

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
	var controls:="滚轮选择　E 确认　数字键直选　Q 取消"
	var controls_width:=font.get_string_size(controls,HORIZONTAL_ALIGNMENT_LEFT,-1,15).x
	wheel.draw_rect(Rect2(Vector2(-controls_width*.5-10,218),Vector2(controls_width+20,27)),Color(INK,.9))
	wheel.draw_string(font,Vector2(-controls_width*.5,237),controls,HORIZONTAL_ALIGNMENT_LEFT,-1,15,Color("f6ead6"))
	var radius:=150.*(.86+.14*ease)
	wheel.draw_circle(Vector2.ZERO,radius+26.,Color(INK, .42*ease))
	wheel.draw_circle(Vector2.ZERO,58.,Color(INK, .30*ease))
	wheel.draw_arc(Vector2.ZERO,radius+26.,0,TAU,64,Color(ACCENT,.55*ease),1.6,true)
	for i in options.size():
		var opt:Dictionary=options[i]
		var c:=_point_for(i,options.size(),radius)
		var picked:=i==index
		wheel.draw_circle(c,44.,Color(INK,.92) if picked else Color(INK,.62))
		wheel.draw_arc(c,44.,0,TAU,40,Color(ACCENT,1. if picked else .35),2.4 if picked else 1.2,true)
		wheel.draw_string(font,c+Vector2(-6,-8),str(i+1),HORIZONTAL_ALIGNMENT_LEFT,-1,20,Color(ACCENT,1. if picked else .6))
		# Labels sit away from the centre so arcs never overlap each other.
		var outward:=c.normalized()
		var title:String=opt.title
		var tw:=font.get_string_size(title,HORIZONTAL_ALIGNMENT_LEFT,-1,17).x
		var tp:=c+outward*66.-Vector2(tw*.5,0)
		wheel.draw_string(font,tp,title,HORIZONTAL_ALIGNMENT_LEFT,-1,17,Color("f6ead6") if picked else Color("d8c9ae"))
		if picked:
			var hint:String=String(opt.get("hint",""))
			if hint!="":
				var hw:=font.get_string_size(hint,HORIZONTAL_ALIGNMENT_LEFT,-1,15).x
				wheel.draw_rect(Rect2(Vector2(-hw*.5-10,-radius-116),Vector2(hw+20,26)),Color(INK,.85))
				wheel.draw_string(font,Vector2(-hw*.5,-radius-98),hint,HORIZONTAL_ALIGNMENT_LEFT,-1,15,Color("e8d4b0"))
