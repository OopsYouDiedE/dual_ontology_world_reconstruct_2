extends Node3D
## Spectator only. All scoring and observations belong to the fixed-step judge.
const Plans = preload("../room_review/RoomPlans.gd")
const Block = preload("../room_review/RoomBlockout.gd")
const Figure = preload("../TestPlayer.tscn")
const Inputs = preload("../WhiteboxInput.gd")
const FLOOR = preload("../BlueRubber.tres")
const WALL = preload("../RedRubber.tres")
const LOOK = preload("../YardLook.tres")
const TITLES = preload("res://scenes/rogue_crossing/Rooms.gd")
const CREAM := Color("e7d9b9")
const TEAL := Color("71d2be")
const AMBER := Color("f0b469")
const INK := Color("273843")
var tape := {}
var chamber: Node3D
var camera: Camera3D
var rack_nodes := []
var figures := []
var tick := 0
var frame := 0
var stage := -1
var heading: Label
var optics: Label
var readout: Label
var speed := 1
var paused := false
var view_path: String
var pid := -1
var stage_spec := {}
var gate: Node3D
var dial: MeshInstance3D
var show_plan := false
var frame_ms: Array[float] = []
var previous_render_us := 0

func _ready() -> void:
	Inputs.install({&"arena_pause":KEY_SPACE, &"arena_speed":KEY_X, &"arena_room":KEY_N, &"arena_plan":KEY_TAB, &"arena_optics":KEY_V})
	var world := WorldEnvironment.new()
	world.environment = LOOK.duplicate()
	add_child(world)
	var key := DirectionalLight3D.new()
	key.rotation_degrees = Vector3(-64,-26,0)
	key.light_color = Color("fff1d8")
	key.light_energy = 1.14
	key.shadow_enabled = true
	add_child(key)
	camera = Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	add_child(camera)
	camera.make_current()
	var hud := CanvasLayer.new()
	add_child(hud)
	heading = _panel_label(hud, true)
	readout = _panel_label(hud, false)
	optics = _panel_label(hud,true)
	optics.get_parent().offset_top=63; optics.get_parent().hide()
	var mono:=SystemFont.new();mono.font_names=PackedStringArray(["Consolas","Monospace"]);optics.add_theme_font_override("font",mono)
	heading.text = "NIGHT WATCH   /   LOCKSTEP ARENA"
	readout.text = "Adjudicating the submitted program…"
	var dir := ProjectSettings.globalize_path("res://.runtime/rule-arena/view-%d" % OS.get_process_id())
	DirAccess.make_dir_recursive_absolute(dir)
	view_path = dir.path_join("view.json")
	if FileAccess.file_exists(view_path): DirAccess.remove_absolute(view_path)
	var args := PackedStringArray([ProjectSettings.globalize_path("res://tools/rule_arena/arena.mjs"),"run","--out",dir.path_join("run.json"),"--view",view_path])
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--run-seed="): args.append_array(["--seed",a.trim_prefix("--run-seed=")])
		if a.begins_with("--arena-replay="):
			args = PackedStringArray([args[0],"replay","--in",a.trim_prefix("--arena-replay="),"--view",view_path]); break
	pid = OS.create_process("node",args,false)

func _panel_label(hud: CanvasLayer, top: bool) -> Label:
	var panel := PanelContainer.new()
	hud.add_child(panel)
	panel.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT if top else Control.PRESET_BOTTOM_LEFT)
	panel.offset_left = 16
	panel.offset_top = 13 if top else -50
	var style := StyleBoxFlat.new()
	style.bg_color = Color("1a2934ee"); style.border_color = TEAL; style.border_width_left = 3
	style.content_margin_left = 13; style.content_margin_right = 13; style.content_margin_top = 6; style.content_margin_bottom = 6
	panel.add_theme_stylebox_override("panel",style)
	var label := Label.new(); panel.add_child(label)
	label.add_theme_font_size_override("font_size",18 if top else 14)
	return label

func _process(_delta: float) -> void:
	if not tape.is_empty():
		var now := Time.get_ticks_usec()
		if previous_render_us > 0 and frame_ms.size() < 3600: frame_ms.append((now-previous_render_us)/1000.)
		previous_render_us = now
		return
	if FileAccess.file_exists(view_path):
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(view_path))
		if parsed is Dictionary and parsed.has("frames"):
			tape = parsed; _show_tick(0)
	elif pid < 0 or not OS.is_process_running(pid):
		readout.text = "Judge unavailable. Install Node and run npm ci in tools/rule_arena."

func _physics_process(_delta: float) -> void:
	if tape.is_empty(): return
	if Input.is_action_just_pressed("arena_optics"):
		optics.get_parent().visible = not optics.get_parent().visible; _show_tick(tick)
	if Input.is_action_just_pressed("arena_pause"): paused = not paused
	if Input.is_action_just_pressed("arena_speed"): speed = 1 if speed == 8 else speed*2
	if Input.is_action_just_pressed("arena_plan"): show_plan = not show_plan; _frame_room()
	if Input.is_action_just_pressed("arena_room"):
		var next := int(tape.end) if stage >= tape.rooms.size()-1 else int(tape.rooms[stage+1].begin)
		_show_tick(next); return
	if not paused and tick < int(tape.end): _show_tick(mini(tick+speed,int(tape.end)))

func _show_tick(value: int) -> void:
	tick = value
	while frame+1 < tape.frames.size() and tape.frames[frame+1][0] <= tick: frame += 1
	var state: Array = tape.frames[frame]
	var index := 10 if tick == tape.end and tape.result == "camp" else int(state[1])
	if stage != index: _build(index)
	if stage == 10:
		optics.get_parent().hide()
		readout.text = "All crew accounted for   /   %d physical steps   /   MAIN CAMP" % tick
		return
	if optics.get_parent().visible:
		var scan_index:=mini(floori(tick/20.),tape.scans.size()-1)
		var lines:=PackedStringArray(["CAPTAIN / LOCAL SCAN %05d" % (scan_index*20)])
		for row in 3:
			var line:String=["LOW ","EYE ","HIGH"][row]
			for col in 9: line += "%4s" % str(tape.scans[scan_index][row*9+col])
			lines.append(line)
		optics.text="\n".join(lines)
	var crew: Array = state[4]
	for i in figures.size():
		var start: Vector3 = [Vector3.ZERO,Vector3(-1.4,0,1.8),Vector3(1.4,0,1.8)][i]
		var id := int(crew[i][0]); var pos := start
		if state[3]>=0 and id>=0:
			var points: Array = stage_spec.tracks[i]
			var elapsed: float = tick - state[3]
			var last: Array = points.back()[1]; pos = Vector3(last[0],0,last[1])
			for j in range(1,points.size()):
				if elapsed > points[j][0]: continue
				var a: Array = points[j-1]; var b: Array = points[j]
				pos = Vector3(a[1][0],0,a[1][1]).lerp(Vector3(b[1][0],0,b[1][1]),(elapsed-a[0])/maxf(1,b[0]-a[0])); break
		figures[i].position = pos
		figures[i].rotation.y = -deg_to_rad(state[2]) if i==0 else 0.0
	gate.visible = state[3] < 0
	if not show_plan and state[3]>=0:
		var target := Vector3(0,0,minf(0,figures[0].position.z))
		camera.position=target+Vector3(6,22,17);camera.look_at(target)
	for i in rack_nodes.size():
		var p: Dictionary = stage_spec.pads[i]
		var phase := posmod(floori(tick/20.)+int(p.offset),int(p.period))
		var mat: StandardMaterial3D = rack_nodes[i][0].material_override
		mat.albedo_color = INK if phase==p.period-1 else TEAL if phase<p.width else AMBER
		var h := 2.0 if phase<p.width else 1.2
		rack_nodes[i][0].position.y = h-.20
		rack_nodes[i][1].position.y = (.85+h)*.5
		rack_nodes[i][1].scale.y = (h-.85)/1.15
		rack_nodes[i][2].visible = phase!=p.period-1
	var gear: Dictionary = stage_spec.gear
	dial.rotation.y = TAU * posmod(floori(tick/20.)+int(gear.offset),int(gear.period))/float(gear.period)
	readout.text = "%s   /   T %05d   /   Crew %d   /   %d×      Space pause · X speed · N next · Tab overview · V optics" % ["Transfer" if state[3]>=0 else ("Dispatch" if tick<tape.end else str(tape.result)),tick,crew.size(),speed]

func _build(index: int) -> void:
	if chamber: remove_child(chamber); chamber.queue_free()
	stage = index; chamber = Node3D.new(); add_child(chamber); figures.clear(); rack_nodes.clear()
	var block := Block.new(); chamber.add_child(block)
	if index == 10:
		block.build(Plans.plan("hall")); heading.text = "NIGHT WATCH     /     MAIN CAMP HALL"
		for i in 3: _actor(Vector3(i-1,0,4))
	else:
		stage_spec=tape.rooms[index];var q:=stage_spec
		var plan: Dictionary = Plans.plan(q.name)
		block.build(plan); block.get_node("ReviewAprons/EntryApron").visible=false;
		_box(Vector3(0,-.12,-float(q.depth)-.25),Vector3(2.55,.24,.5),INK); block.position.z=-float(q.depth)-plan.size.y*.5-0.5
		for spec: Dictionary in q.boxes:
			var at := Vector3(spec.at[0],spec.at[1],spec.at[2]); var size := Vector3(spec.size[0],spec.size[1],spec.size[2])
			if spec.kind=="floor":
				var mesh:=Block.Geometry.prism([[-q.span,-q.depth],[q.span,-q.depth],[q.span,q.depth],[-q.span,q.depth]],-.2,0,"grout")
				mesh.material_override=FLOOR; chamber.add_child(mesh)
			else:
				if at.z == -float(q.depth) and size.x > size.z:
					gate = _box(at,Vector3(2.55,size.y,.2),INK)
					var w := (size.x-2.55)*.5
					for side in [-1,1]: _wall(block,Vector2(side*(1.275+w*.5),at.z),Vector2(w,0),size.y)
					continue
				var line := Vector2(size.x,0) if size.x>size.z else Vector2(0,size.z)
				_wall(block,Vector2(at.x,at.z),line,size.y)
		for p: Dictionary in q.pads:
			var center:=Vector3(p.at[0],0,p.at[2]);_box(center+Vector3.UP*.42,Vector3(1,.84,1),INK)
			var piston:=_box(center+Vector3.UP*1.43,Vector3(.96,1.15,.96),CREAM)
			var lamp:=_box(center+Vector3.UP*1.80,Vector3(1,.4,1),TEAL)
			var tag:=_tag(center+Vector3.UP*2.35,"%02d  /  %s" % [p.id+1,char(65+int(p.bank))]);rack_nodes.append([lamp,piston,tag])
		_box(Vector3(0,1,4),Vector3(1.3,2,1),CREAM);dial=_box(Vector3(0,2.02,4),Vector3(.96,.06,.16),INK)
		_tag(Vector3(0,2.42,4),"GOVERNOR")
		for i in (1+int(index>=2)+int(index>=6)): _actor(Vector3.ZERO)
		heading.text="NIGHT WATCH     /     %02d—10     %s" % [index+1,str(TITLES.TITLES[q.name]).to_upper()]
	_frame_room()

func _frame_room() -> void:
	var target:=Vector3.ZERO if stage==10 or not show_plan else Vector3(0,0,-7)
	camera.position=target+Vector3(6,22,17);camera.look_at(target); camera.size=31 if show_plan else 19

func _box(at:Vector3,size:Vector3,color:Color)->MeshInstance3D:
	var m:=BoxMesh.new();m.size=size;var node:=MeshInstance3D.new();node.mesh=m
	var mat:=StandardMaterial3D.new();mat.albedo_color=color;mat.roughness=.76;node.material_override=mat;node.position=at;chamber.add_child(node);return node

func _wall(block:Node3D,pt:Vector2,line:Vector2,h:float)->void:
	var spec:Dictionary=block._wall("Bulkhead",pt-line*.5,pt+line*.5,h,[]);spec.thickness=.2
	var wall:=Block.WallPath.build(spec);chamber.add_child(wall)
	for m in wall.find_children("*","MeshInstance3D",true,false): m.material_override=WALL

func _tag(at:Vector3,text:String)->Label3D:
	var label:=Label3D.new();label.text=text;label.position=at;label.billboard=BaseMaterial3D.BILLBOARD_ENABLED;label.font_size=32;label.pixel_size=.0085;chamber.add_child(label);return label

func _actor(at:Vector3)->void:
	var dummy:=Figure.instantiate();var model:=dummy.get_node("Figure") as Node3D;dummy.remove_child(model);dummy.free();chamber.add_child(model);model.position=at;figures.append(model)

func mcp_observe()->Dictionary:
	var sorted:=frame_ms.duplicate();sorted.sort()
	return {"stage":stage,"tick":tick,"loaded":not tape.is_empty(),"title":heading.text,"sample_frames":sorted.size(),"median_frame_ms":0.0 if sorted.is_empty() else sorted[sorted.size()/2],"p95_frame_ms":0.0 if sorted.is_empty() else sorted[floori((sorted.size()-1)*.95)]}
