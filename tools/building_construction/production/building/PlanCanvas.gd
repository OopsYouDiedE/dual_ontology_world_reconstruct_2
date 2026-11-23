extends Control
const S=preload("BuildingSolver.gd")
signal stroke(a:Vector2i,b:Vector2i)
const PALETTE=[Color("b99671"),Color("b6a989"),Color("789c92"),Color("ab9aae"),Color("7c92b0"),Color("9e916e")]
var plan:Dictionary;var level:=0;var brush:=0;var tool:=0;var show_grid:=true;var hover=Vector2i(-1,-1);var drag=Vector2i(-1,-1)
func pitch()->float:return maxf(1,minf((size.x-28)/S.GRID,(size.y-28)/S.GRID))
func offset()->Vector2:return (size-Vector2.ONE*S.GRID*pitch())*.5
func _draw()->void:
	draw_rect(Rect2(Vector2.ZERO,size),Color("182229"));var h=pitch();var o=offset()
	for z in S.GRID:
		for x in S.GRID:
			var k=S.key(x,z,level);var r=Rect2(o+Vector2(x,z)*h,Vector2.ONE*h)
			if plan.get("cells",{}).has(k):draw_rect(r,PALETTE[int(plan.cells[k])]);draw_rect(r,Color("464747"),false,1)
			elif level>0 and plan.cells.has(S.key(x,z,level-1)):draw_rect(r,Color("3a4950"))
			if plan.get("cores",{}).has(k):draw_circle(r.get_center(),h*.22,Color("25323d"));draw_circle(r.get_center(),h*.11,Color("f4d997"))
	if show_grid:
		for i in S.GRID+1:
			draw_line(o+Vector2(i*h,0),o+Vector2(i*h,S.GRID*h),Color("62716e"));draw_line(o+Vector2(0,i*h),o+Vector2(S.GRID*h,i*h),Color("62716e"))
	for k in plan.get("cells",{}):
		var c=S.address(k);if c.z!=level:continue
		for d in [Vector2i.RIGHT,Vector2i.DOWN,Vector2i.LEFT,Vector2i.UP]:
			var nb=S.key(c.x+d.x,c.y+d.y,level)
			if plan.cells.has(nb) and S.room_tag(plan,k)==S.room_tag(plan,nb):continue
			var a=o+Vector2(c.x+int(d.x>0),c.y+int(d.y>0))*h;var axis=Vector2.RIGHT if d.y!=0 else Vector2.DOWN
			draw_line(a,a+axis*h*.35,Color("1c2428"),3);draw_line(a+axis*h*.65,a+axis*h,Color("1c2428"),3)
			if not plan.cells.has(nb):draw_line(a+axis*h*.35,a+axis*h*.65,Color("1c2428"),3)
	if hover.x>=0:
		var a=hover if drag.x<0 else drag;var lo=a.min(hover);var hi=a.max(hover);draw_rect(Rect2(o+Vector2(lo)*h,Vector2(hi-lo+Vector2i.ONE)*h),Color("f7da98"),false,3)
func cell(p:Vector2)->Vector2i:return Vector2i(((p-offset())/pitch()).floor())
func _gui_input(e:InputEvent)->void:
	if e is InputEventMouse:
		var c=cell(e.position);var inside=Rect2i(0,0,S.GRID,S.GRID).has_point(c);hover=c if inside else Vector2i(-1,-1);queue_redraw()
		if e is InputEventMouseButton and e.button_index==MOUSE_BUTTON_LEFT:
			if e.pressed and inside:drag=c
			elif not e.pressed and drag.x>=0:
				if inside:stroke.emit(drag,c)
				drag=Vector2i(-1,-1)
			accept_event()
