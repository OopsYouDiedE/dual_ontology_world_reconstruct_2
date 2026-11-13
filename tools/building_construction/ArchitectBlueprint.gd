extends Control
var editor: Node
var pan = Vector2(140,140)
var zoom = 42.0
var hover = Vector2.ZERO
var panning = false
var dragging = false
var drag_start = Vector2.ZERO
var snapshot: Dictionary = {}

func _ready() -> void:
	clip_contents = true
	mouse_filter = Control.MOUSE_FILTER_STOP
func world(point: Vector2) -> Vector2: return (point-pan)/zoom
func screen(point: Vector2) -> Vector2: return point*zoom+pan
func p2(point: Array) -> Vector2: return Vector2(point[0],point[2])
func _process(_dt: float) -> void:
	if is_visible_in_tree(): queue_redraw()

const Footprint = preload("BuildingConstruction/Props/PropFootprint.gd")
const SANS_FONT := preload("res://assets/external/NotoSansSC/NotoSansSC[wght].ttf")
const PROP_COLORS = {"floor":Color("8cbd9f"),"wall":Color("9fb4d9"),"top":Color("e0c27a"),"ceiling":Color("c8a2d8"),"flat":Color("6f8f7a")}
var magnet_hit: Dictionary = {}

func label_at(text: String, at: Vector2, color := Color("c9d1da"), size := 14) -> void:
	var font: Font = SANS_FONT
	var extent = font.get_string_size(text,HORIZONTAL_ALIGNMENT_LEFT,-1,size)
	draw_rect(Rect2(at-Vector2(extent.x*0.5+3,extent.y*0.5+1),extent+Vector2(6,2)),Color(0.06,0.07,0.09,0.78))
	draw_string(font,at+Vector2(-extent.x*0.5,extent.y*0.5-3),text,HORIZONTAL_ALIGNMENT_LEFT,-1,size,color)

func segment_label(a: Vector2, b: Vector2, thickness: float, color := Color("9aa6b4")) -> void:
	var length = a.distance_to(b)
	if length<0.05 or length*zoom<46: return
	var mid = screen((a+b)*0.5)
	var normal = (b-a).normalized().orthogonal()
	label_at("%.2f m" % length,mid+normal*(thickness*zoom*0.5+11),color,13)

func draw_prop(prop: Dictionary, selected: bool, conflict: String) -> void:
	var f = Footprint.info(prop)
	var color = PROP_COLORS.get(f.mount,Color("8cbd9f"))
	if conflict!="": color = Color("e5675b")
	var points = PackedVector2Array()
	for p in Footprint.corners(prop): points.append(screen(p))
	if f.mount in ["wall","top","ceiling"] and points.size()==4 and (f.w*zoom<10 or f.d*zoom<6):
		# Thin or tiny pieces: draw a marker so they stay selectable.
		var c = screen(Vector2(prop.x,prop.z))
		draw_circle(c,5 if f.mount!="wall" else 4,color)
		var facing = Vector2(sin(deg_to_rad(prop.get("yaw",0))),cos(deg_to_rad(prop.get("yaw",0))))
		draw_line(c,c+facing*11,color,2)
		if selected: draw_arc(c,9,0,TAU,20,Color.WHITE,2)
		return
	var fill = Color(color.r,color.g,color.b,0.14 if f.mount==Footprint.FLAT else 0.34)
	draw_colored_polygon(points,fill)
	var outline = points.duplicate()
	outline.append(points[0])
	draw_polyline(outline,Color.WHITE if selected else color,3 if selected else 1.5)
	# Front edge (local +z) is thick, so orientation is readable at a glance.
	var front_a = screen(Footprint.to_world(prop,Vector2(local_x(prop,-1),local_z(prop,1))))
	var front_b = screen(Footprint.to_world(prop,Vector2(local_x(prop,1),local_z(prop,1))))
	draw_line(front_a,front_b,color.lightened(0.35),3)
	if f.w*zoom>38 and f.d*zoom>16:
		label_at(short_name(prop),screen(Vector2(prop.x,prop.z)),Color("dbe3ea"),13)

func local_x(prop: Dictionary, sign: float) -> float:
	var r = Footprint.local_rect(prop)
	return r.position.x if sign<0 else r.end.x
func local_z(prop: Dictionary, sign: float) -> float:
	var r = Footprint.local_rect(prop)
	return r.position.y if sign<0 else r.end.y
func short_name(prop: Dictionary) -> String:
	var names = editor.prop_presets.get(str(prop.get("kind","")),{}) if editor!=null else {}
	return str(names.get("name",prop.get("name","")))


func _input(event: InputEvent) -> void:
	# Match the source editor's window-level mouseup, including release outside the canvas.
	if event is InputEventMouseButton and not event.pressed:
		if event.button_index==MOUSE_BUTTON_LEFT and dragging:
			dragging = false
			editor.state.remember()
		if event.button_index in [MOUSE_BUTTON_RIGHT,MOUSE_BUTTON_MIDDLE]: panning = false

func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO,size),Color("101318"))
	if editor==null: return
	var state = editor.state
	var step = maxf(state.grid_snap,0.2)
	while step*zoom<16: step *= 2
	var top = world(Vector2.ZERO)
	var bottom = world(size)
	var gx = floor(top.x/step)*step
	while gx<bottom.x:
		draw_line(screen(Vector2(gx,top.y)),screen(Vector2(gx,bottom.y)),Color("252932"))
		gx += step
	var gz = floor(top.y/step)*step
	while gz<bottom.y:
		draw_line(screen(Vector2(top.x,gz)),screen(Vector2(bottom.x,gz)),Color("252932"))
		gz += step
	for li in range(state.data.layers.size()):
		var layer = state.data.layers[li]
		for pi in range(layer.polygons.size()):
			var poly = layer.polygons[pi]
			var points = PackedVector2Array()
			for p in poly: points.append(screen(Vector2(p[0],p[1])))
			if points.size()<3: continue
			draw_colored_polygon(points,Color(0.5,0.32,0.2,0.25))
			points.append(points[0])
			draw_polyline(points,Color("8f6b48"),2)
			var nodes = layer.roomFaces[pi].nodes if layer.has("roomFaces") else poly
			for p in nodes: draw_circle(screen(Vector2(p[0],p[1])),4,Color("b89365"))
	for wi in range(state.data.walls.size()):
		var wall = state.data.walls[wi]
		var color = Color("d4a373")
		if absf(float(wall.get("baseY",0))-float(state.layer().get("y",0)))>0.3: color = Color(0.83,0.64,0.45,0.28)
		if state.selected.get("wallIndex",-1)==wi: color = Color("f7d27e")
		for si in range(wall.points.size()-1):
			draw_line(screen(p2(wall.points[si])),screen(p2(wall.points[si+1])),color,maxf(3,wall.thickness*zoom))
		for p in wall.points: draw_circle(screen(p2(p)),5,Color("f2c17b"))
		for oi in range(wall.openings.size()):
			var op = wall.openings[oi]
			if op.segment>=wall.points.size()-1: continue
			var a = p2(wall.points[op.segment])
			var delta = (p2(wall.points[op.segment+1])-a).normalized()
			var center = a+delta*op.center
			draw_line(screen(center-delta*op.width*0.5),screen(center+delta*op.width*0.5),Color("72c4d1"),maxf(5,wall.thickness*zoom+2))
			draw_circle(screen(center),4,Color.WHITE)
	for rail in state.data.railings:
		for i in range(rail.points.size()-1): draw_line(screen(p2(rail.points[i])),screen(p2(rail.points[i+1])),Color("89b995"),3)
		for p in rail.points: draw_circle(screen(p2(p)),4,Color("89b995"))
	for stair in state.data.stairs:
		var center = screen(Vector2(stair.x,stair.z))
		draw_circle(center,8,Color("bd9fca"))
		draw_line(center,center+Vector2(cos(deg_to_rad(-stair.yaw)),sin(deg_to_rad(-stair.yaw)))*stair.run*zoom,Color("bd9fca"),stair.width*zoom)
	var conflicts = editor.conflicts
	for pi in range(state.data.props.size()):
		var prop = state.data.props[pi]
		draw_prop(prop,state.selected.get("kind","")=="prop" and state.selected.get("index",-1)==pi,str(conflicts.get(pi,"")))
	# Room names and areas on the active layer.
	var active = state.layer()
	if active.has("roomFaces"):
		for ri in range(active.roomFaces.size()):
			var face = active.roomFaces[ri]
			label_at("房间 %d · %.1f m²" % [ri+1,face.get("area",0.0)],screen(Vector2(face.centroid[0],face.centroid[1]))+Vector2(0,-14),Color("e9d8b4"),12)
	# Dimensions of the selected wall and of the segment being drawn.
	if state.selected.get("kind","") in ["wall","wallNode"]:
		var sel = state.data.walls[state.selected.wallIndex]
		for si in range(sel.points.size()-1): segment_label(p2(sel.points[si]),p2(sel.points[si+1]),sel.thickness)
	if not magnet_hit.is_empty() and editor.tool in ["wall","floor","railing"]:
		draw_arc(screen(magnet_hit.point),9,0,TAU,24,Color("70e1e8") if magnet_hit.kind=="node" else Color("f7d27e"),2)
	if not editor.drawing.is_empty():
		var points = PackedVector2Array()
		for p in editor.drawing:
			points.append(screen(Vector2(p[0],p[1])))
			draw_circle(points[-1],5,Color("f7d27e"))
		points.append(screen(hover))
		if points.size()>1: draw_polyline(points,Color("f7d27e"),2)
		var last = Vector2(editor.drawing[-1][0],editor.drawing[-1][1])
		if last.distance_to(hover)>0.05:
			var delta = hover-last
			label_at("%.2f m · %d°" % [delta.length(),int(round(fposmod(rad_to_deg(atan2(-delta.y,delta.x)),360)))],screen((last+hover)*0.5)+Vector2(0,-14),Color("f7d27e"),12)
	if editor.tool=="opening":
		var hit = state.nearest_wall(hover,0.9)
		if not hit.is_empty(): draw_circle(screen(hit.point),8,Color("70e1e8"),false,2)
	var selected = state.selected
	if selected.get("kind","") in ["wallNode","floorNode","railingNode"]:
		var point: Vector2
		match selected.kind:
			"wallNode": point = p2(state.data.walls[selected.wallIndex].points[selected.ptIndex])
			"floorNode":
				var layer = state.data.layers[selected.layerIndex]
				var p = layer.roomFaces[selected.polyIndex].nodes[selected.ptIndex] if layer.has("roomFaces") else layer.polygons[selected.polyIndex][selected.ptIndex]
				point = Vector2(p[0],p[1])
			"railingNode": point = p2(state.data.railings[selected.railIndex].points[selected.ptIndex])
		draw_circle(screen(point),8,Color.WHITE,false,2)

func hit_test(point: Vector2) -> Dictionary:
	var state = editor.state
	var tol = 9/zoom
	for wi in range(state.data.walls.size()):
		var wall = state.data.walls[wi]
		var count = wall.points.size()-(1 if wall.closed else 0)
		for i in range(count):
			if point.distance_to(p2(wall.points[i]))<=tol: return {"kind":"wallNode","wallIndex":wi,"ptIndex":i}
	for li in range(state.data.layers.size()):
		for pi in range(state.data.layers[li].polygons.size()):
			var layer = state.data.layers[li]
			var poly = layer.roomFaces[pi].nodes if layer.has("roomFaces") else layer.polygons[pi]
			for i in range(poly.size()):
				if point.distance_to(Vector2(poly[i][0],poly[i][1]))<=tol: return {"kind":"floorNode","layerIndex":li,"polyIndex":pi,"ptIndex":i}
	for ri in range(state.data.railings.size()):
		for i in range(state.data.railings[ri].points.size()):
			if point.distance_to(p2(state.data.railings[ri].points[i]))<=tol: return {"kind":"railingNode","railIndex":ri,"ptIndex":i}
	for wi in range(state.data.walls.size()):
		var wall = state.data.walls[wi]
		for oi in range(wall.openings.size()):
			var op = wall.openings[oi]
			if op.segment>=wall.points.size()-1: continue
			var a = p2(wall.points[op.segment])
			var b = p2(wall.points[op.segment+1])
			var length = (b-a).length()
			var center = a+(b-a)/(length if length>0 else 1.0)*op.center
			if point.distance_to(center)<=maxf(op.width*0.45,tol*1.4): return {"kind":"opening","wallIndex":wi,"opIndex":oi}
	# Small hanging / tabletop pieces win over the big piece they sit on; rugs come last.
	for pass_index in range(3):
		for i in range(state.data.props.size()-1,-1,-1):
			var p = state.data.props[i]
			var mount = Footprint.info(p).mount
			var rank = 0 if mount in ["wall","top","ceiling"] else (2 if mount=="flat" else 1)
			if rank!=pass_index: continue
			if Footprint.contains(p,point,0.06) or (rank==0 and point.distance_to(Vector2(p.x,p.z))<=0.3): return {"kind":"prop","index":i}
	for i in range(state.data.stairs.size()-1,-1,-1):
		var p = state.data.stairs[i]
		var rad = deg_to_rad(p.get("yaw",0))
		var delta = point-Vector2(p.x,p.z)
		var lx = delta.x*cos(-rad)-delta.y*sin(-rad)
		var lz = delta.x*sin(-rad)+delta.y*cos(-rad)
		if lx>=-0.2 and lx<=p.run+0.2 and abs(lz)<=p.width*0.55: return {"kind":"stair","index":i}
	for wi in range(state.data.walls.size()):
		var wall = state.data.walls[wi]
		for i in range(wall.points.size()-1):
			if state.project(point,p2(wall.points[i]),p2(wall.points[i+1])).dist<=maxf(wall.thickness*0.6,tol): return {"kind":"wall","wallIndex":wi}
	for ri in range(state.data.railings.size()):
		var rail = state.data.railings[ri]
		for i in range(rail.points.size()-1):
			if state.project(point,p2(rail.points[i]),p2(rail.points[i+1])).dist<=tol: return {"kind":"railing","railIndex":ri}
	for li in range(state.data.layers.size()-1,-1,-1):
		for pi in range(state.data.layers[li].polygons.size()-1,-1,-1):
			if Geometry2D.is_point_in_polygon(point,editor.Geo.points2(state.data.layers[li].polygons[pi])): return {"kind":"floorPoly","layerIndex":li,"polyIndex":pi}
	return {}

func _gui_input(event: InputEvent) -> void:
	if editor==null: return
	var state = editor.state
	if event is InputEventMouseButton:
		var point = world(event.position)
		if event.button_index in [MOUSE_BUTTON_WHEEL_UP,MOUSE_BUTTON_WHEEL_DOWN] and event.pressed:
			zoom = clampf(zoom*(1.12 if event.button_index==MOUSE_BUTTON_WHEEL_UP else 0.89),12,180)
			pan = event.position-point*zoom
		elif event.button_index in [MOUSE_BUTTON_RIGHT,MOUSE_BUTTON_MIDDLE]: panning = event.pressed
		elif event.button_index==MOUSE_BUTTON_LEFT:
			if not event.pressed:
				if dragging: state.remember()
				dragging = false
				return
			if event.double_click:
				if editor.tool!="select": editor.finish_path(editor.tool!="railing")
				else:
					var hit = hit_test(point)
					if hit.get("kind","") in ["wallNode","floorNode","opening","prop","stair"]:
						state.selected = hit
						editor.show_parameters()
					elif state.insert_wall_node(point,10/zoom): editor.refresh()
					else: editor.insert_floor_node(point,10/zoom)
				return
			match editor.tool:
				"wall","floor","railing":
					var sx = state.snap(point.x)
					var sz = state.snap(point.y)
					var p = Vector2(sx,sz)
					var pull = state.magnet(point,14/zoom,editor.wall_params.baseY if editor.tool=="wall" else state.layer().get("y",0.0)) if editor.tool!="railing" else {}
					if not pull.is_empty():
						sx = snappedf(pull.point.x,0.01); sz = snappedf(pull.point.y,0.01)
						p = Vector2(sx,sz)
					if editor.drawing.size()>=3 and p.distance_to(Vector2(editor.drawing[0][0],editor.drawing[0][1]))<=12/zoom: editor.finish_path(true)
					else:
						var y = editor.wall_params.baseY if editor.tool=="wall" else state.layer().get("y",0)
						editor.drawing.append([sx,sz,y])
						editor.update_status()
				"opening":
					if state.add_opening(point,editor.opening_params): editor.refresh()
					else: editor.status.text = state.message
				"prop": editor.place_prop(point)
				_:
					state.selected = hit_test(point)
					editor.refresh_inspector()
					if not state.selected.is_empty():
						dragging = true
						drag_start = point
						snapshot = state.data.duplicate(true)
	elif event is InputEventMouseMotion:
		var point = world(event.position)
		hover = Vector2(state.snap(point.x),state.snap(point.y))
		magnet_hit = {}
		if editor.tool in ["wall","floor"]:
			magnet_hit = state.magnet(point,14/zoom,editor.wall_params.baseY if editor.tool=="wall" else state.layer().get("y",0.0))
			if not magnet_hit.is_empty(): hover = Vector2(snappedf(magnet_hit.point.x,0.01),snappedf(magnet_hit.point.y,0.01))
		editor.update_cursor(hover)
		if panning: pan += event.relative
		elif dragging and not state.selected.is_empty():
			var s = state.selected
			var delta = Vector2(state.snap(point.x-drag_start.x),state.snap(point.y-drag_start.y))
			match s.kind:
				"wallNode":
					var wall = state.data.walls[s.wallIndex]
					state.set_node(wall,s.ptIndex,0,state.snap(point.x))
					state.set_node(wall,s.ptIndex,2,state.snap(point.y))
				"wall":
					state.translate_wall(s.wallIndex,snapshot,delta.x,delta.y)
				"opening":
					var wall = state.data.walls[s.wallIndex]
					var op = wall.openings[s.opIndex]
					var hit = state.project(point,p2(wall.points[op.segment]),p2(wall.points[op.segment+1]))
					op.center = max(op.width*0.5+0.05,min(hit.len-op.width*0.5-0.05,state.snap(hit.t*hit.len)))
				"floorNode":
					state.move_room_node(s.layerIndex,s.polyIndex,s.ptIndex,state.snap(point.x),state.snap(point.y))
				"floorPoly":
					state.translate_room(s.layerIndex,s.polyIndex,snapshot,delta.x,delta.y)
				"railingNode":
					state.data.railings[s.railIndex].points[s.ptIndex][0] = state.snap(point.x)
					state.data.railings[s.railIndex].points[s.ptIndex][2] = state.snap(point.y)
				"railing":
					var rail = state.data.railings[s.railIndex]
					for i in range(rail.points.size()):
						rail.points[i][0] = editor.Geo.js_round((snapshot.railings[s.railIndex].points[i][0]+delta.x)*100)/100
						rail.points[i][2] = editor.Geo.js_round((snapshot.railings[s.railIndex].points[i][2]+delta.y)*100)/100
				"prop":
					state.data.props[s.index].x = state.snap(point.x)
					state.data.props[s.index].z = state.snap(point.y)
					if not Input.is_key_pressed(KEY_ALT): editor.snap_prop(state.data.props[s.index],point)
				"stair":
					state.data.stairs[s.index].x = editor.Geo.js_round((snapshot.stairs[s.index].x+delta.x)*100)/100
					state.data.stairs[s.index].z = editor.Geo.js_round((snapshot.stairs[s.index].z+delta.y)*100)/100
			editor.request_rebuild()
			editor.refresh_inspector()
