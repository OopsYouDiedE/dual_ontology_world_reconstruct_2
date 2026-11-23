extends PanelContainer
const S=preload("BuildingSolver.gd")
const V=preload("BuildingView.gd")
const Grid=preload("PlanCanvas.gd")
const SAVE="user://academy-structure-v1.json"
var detective=preload("DetectivePreview.gd").new()
var detective_focus:=false
var dx_input=SpinBox.new();var dz_input=SpinBox.new();var radius=SpinBox.new();var room_number=1;var plan=S.example();var solver=S.new();var view=V.new();var grid=Grid.new();var level=0;var brush=0;var tool=0;var cut=true;var history=[];var redo=[]
var list=OptionButton.new();var report=RichTextLabel.new();var cam=Camera3D.new();var section=SubViewportContainer.new();var viewport=SubViewport.new();var az=.64;var el=.64;var stage=5;var zoom=.70;var summary="";var filter=0;var repairs=CheckButton.new();var seed_input=SpinBox.new()
func btn(parent:Control,title:String,action:Callable)->void:
	var b=Button.new();b.text=title;b.pressed.connect(action);parent.add_child(b)
func opt(parent:Control,names:Array,cb:Callable)->OptionButton:
	var o=OptionButton.new();for n in names:o.add_item(n)
	o.item_selected.connect(cb);parent.add_child(o);return o
func caption(parent:Control,t:String)->void:
	var l=Label.new();l.text=t;parent.add_child(l)
func example_menu(bar:Control)->void:
	var menu=MenuButton.new();menu.text="Example";bar.add_child(menu);menu.get_popup().add_item("Inspection hall",0);menu.get_popup().add_item("Room kit study",1)
	menu.tooltip_text="Inspection hall / room kit study (K)";menu.get_popup().id_pressed.connect(load_example)
func load_example(id:int)->void:
	var next=S.example() if id==0 else JSON.parse_string(FileAccess.get_file_as_string("res://tools/building_construction/production/building/kits/room-kit-study.json"))
	if S.valid(next):remember();plan=next;rebuild()
func _ready()->void:
	var style=StyleBoxFlat.new();style.bg_color=Color("202a32");add_theme_stylebox_override("panel",style);add_theme_constant_override("separation",6)
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT);var col=VBoxContainer.new();add_child(col);var bar=HBoxContainer.new();col.add_child(bar);caption(bar,"  ARCHBUILDER  /  STRUCTURE LAB     ")
	btn(bar,"Undo",func():travel(history,redo));btn(bar,"Redo",func():travel(redo,history));btn(bar,"Save",save_plan);btn(bar,"Load",load_plan);example_menu(bar);btn(bar,"New from seed",func():remember();plan=S.generate(int(seed_input.value));rebuild());btn(bar,"Close",func():
		if get_parent() is Control:queue_free()
		else:get_tree().quit())
	var edit=HBoxContainer.new();col.add_child(edit);opt(edit,["Ground","Level 2","Level 3","Level 4"],func(i):level=i;rebuild());opt(edit,S.TYPES,func(i):brush=i;grid.brush=i);opt(edit,["Paint room","Erase bay","U stair up","Spiral up","Service shaft up","Remove core"],func(i):tool=i);var show=CheckButton.new();show.text="Grid";show.button_pressed=true;edit.add_child(show);show.toggled.connect(func(v):grid.show_grid=v;grid.queue_redraw());var slice=CheckButton.new();slice.text="Cutaway";slice.button_pressed=true;edit.add_child(slice);slice.toggled.connect(func(v):cut=v;rebuild());repairs.text="Auto repair";repairs.button_pressed=true;edit.add_child(repairs);repairs.toggled.connect(func(v):remember();plan.mode="repair" if v else "strict";rebuild())
	caption(edit,"Seed");seed_input.min_value=0;seed_input.max_value=999999;seed_input.value=plan.seed;edit.add_child(seed_input);btn(edit,"Apply",func():remember();plan.seed=int(seed_input.value);rebuild())
	var params=HBoxContainer.new();col.add_child(params);caption(params,"  Room group");var group=SpinBox.new();group.min_value=1;group.max_value=99;params.add_child(group);group.value_changed.connect(func(v):room_number=int(v));caption(params,"Spiral clearance");radius.min_value=1.0;radius.max_value=1.7;radius.step=.1;radius.value=1.6;params.add_child(radius);radius.value_changed.connect(func(v):remember();plan.spiral_radius=v;rebuild());btn(params,"Bake navigation",func():report.text=view.bake_routes());btn(params,"Audit panels",func():report.text=view.audit_sockets());
	caption(params,"Pin ΔX / ΔZ");for spin in [dx_input,dz_input]:spin.min_value=-.65;spin.max_value=.65;spin.step=.05;params.add_child(spin)
	dx_input.value=.35
	var split=HSplitContainer.new();split.size_flags_vertical=SIZE_EXPAND_FILL;col.add_child(split);grid.size_flags_horizontal=SIZE_EXPAND_FILL;grid.custom_minimum_size.x=220;split.add_child(grid);grid.stroke.connect(paint);section.size_flags_horizontal=SIZE_EXPAND_FILL;section.custom_minimum_size.x=320;section.stretch=true;split.add_child(section);split.split_offset=-170;viewport.own_world_3d=true;viewport.use_occlusion_culling=true;section.add_child(viewport);viewport.add_child(view);viewport.add_child(cam);cam.current=true
	configure_indoor_light()
	viewport.add_child(detective)
	section.gui_input.connect(orbit)
	var row=HBoxContainer.new();col.add_child(row);opt(row,["Columns","Doors","Lights","Valves","Prefab slots"],func(i):filter=i;fill_list());list.custom_minimum_size.x=175;row.add_child(list);btn(row,"Pin / update",override_part);btn(row,"Clear override",clear_part);btn(row,"Operate",operate);btn(row,"Diagnostics",diagnostics)
	var seq=opt(row,["1 · Slabs","2 · Frame","3 · Walls","4 · Detail","5 · Full"],func(i):stage=i+1;rebuild());seq.select(4)
	report.custom_minimum_size.y=60;report.fit_content=false;col.add_child(report);rebuild()
func configure_indoor_light()->void:
	viewport.msaa_3d=Viewport.MSAA_2X
	var env=WorldEnvironment.new()
	var e:Environment=preload("res://scenes/components/rendering/post/Hall04.tres").duplicate()
	e.background_mode=Environment.BG_COLOR
	e.background_color=Color("495766")
	e.ambient_light_source=Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color=Color("abbcda")
	e.ambient_light_energy=.74
	e.ssao_enabled=true
	e.ssao_radius=.24
	e.ssao_intensity=.50
	e.ssao_power=1.1
	e.tonemap_mode=Environment.TONE_MAPPER_FILMIC
	e.glow_enabled=false
	e.sdfgi_enabled=false
	e.adjustment_enabled=false
	e.fog_enabled=true
	e.fog_density=.0025
	e.fog_light_color=Color("91a4b9")
	e.fog_sky_affect=0
	e.fog_sun_scatter=0
	env.environment=e
	viewport.add_child(env)
	var sun=DirectionalLight3D.new()
	sun.rotation_degrees=Vector3(-42,-32,0)
	sun.light_color=Color("fff0d8")
	sun.light_energy=1.28
	sun.shadow_enabled=true
	viewport.add_child(sun)
	var ink=preload("res://scenes/components/rendering/post/InkPass.gd").create()
	ink.material_override.set_shader_parameter("opacity",.68)
	ink.material_override.set_shader_parameter("ink_radius",.90)
	viewport.add_child(ink)

func remember()->void:
	history.append(plan.duplicate(true));if history.size()>40:history.pop_front()
	redo.clear()
func travel(src:Array,dst:Array)->void:
	if src.is_empty():return
	dst.append(plan);plan=src.pop_back();rebuild()
func paint(a:Vector2i,b:Vector2i)->void:
	remember();var lo=a.min(b);var hi=a.max(b)
	for x in range(lo.x,hi.x+1):
		for z in range(lo.y,hi.y+1):
			var k=S.key(x,z,level)
			match tool:
				0:
					plan.cells[k]=brush;if not plan.has("rooms"):plan.rooms={}
					plan.rooms[k]=str(brush) if room_number==1 else "%d#%d"%[brush,room_number]
				1:plan.cells.erase(k);plan.cores.erase(k);plan.get("rooms",{}).erase(k)
				2,3,4:plan.cores[k]=["stair","spiral","service"][tool-2]
				5:plan.cores.erase(k)
	rebuild()
func rebuild()->void:
	solver.build(plan);view.render(solver,level if cut else -1,cut,stage);detective.place(solver,level,stage);grid.plan=plan;grid.level=level;grid.queue_redraw();seed_input.value=plan.seed;radius.set_value_no_signal(plan.get("spiral_radius",1.6));repairs.set_pressed_no_signal(plan.mode=="repair");fill_list();camera_fit();summary="%d bays   ·   %d wall segments   ·   %d portals/vertical links   ·   %d overrides   ·   %d diagnostics"%[plan.cells.size(),solver.wall_hosts.size(),solver.links.size(),plan.overrides.size(),solver.notes.size()];report.text=summary+"\nDrag grid to paint · RMB orbit · wheel zoom · F: walk at 1.60 m · P: detective actions."
func fill_list()->void:
	var old=list.get_item_text(list.selected) if list.selected>=0 else "";list.clear()
	if filter==4:
		var all=solver.slots.keys();all.sort()
		for id in all:
			if view.visible_owner(solver.slots[id].owner):list.add_item(id);if id==old:list.select(list.item_count-1)
		return
	var prefix=["column/","door/","light/","valve/"][filter];var ids=solver.choices.keys() if filter!=3 else view.valves.keys();if filter==3:ids=[];for o in solver.sockets:if o.kind=="valve" and view.visible_owner(o.owner):ids.append(o.id)
	ids.sort();for id in ids:
		if id.begins_with(prefix) and (not solver.choices.has(id) or view.visible_owner(solver.choices[id].owner)):list.add_item(id);if id==old:list.select(list.item_count-1)
func selection()->String:return list.get_item_text(list.selected) if list.selected>=0 else ""
func override_part()->void:
	var id=selection();if id=="" or filter==3:return
	if filter==4:
		var dialog=FileDialog.new();dialog.file_mode=FileDialog.FILE_MODE_OPEN_FILE;dialog.access=FileDialog.ACCESS_RESOURCES;dialog.filters=PackedStringArray(["*.tscn ; Slot prefabs"]);add_child(dialog)
		dialog.file_selected.connect(func(path):
			remember();var o=plan.overrides.get(id,{});o.scene=path;plan.overrides[id]=o;rebuild();dialog.queue_free())
		dialog.canceled.connect(dialog.queue_free);dialog.popup_centered_ratio(.7);return
	if filter==0:
		var c=S.address(id.trim_prefix("column/"));id="column/"+S.key(c.x,c.y,0)
	remember();var o=plan.overrides.get(id,{});match filter:
		0:o.shift=[dx_input.value,dz_input.value]
		1:o.style="oak" if o.get("style","oak")=="iron" else "iron"
		2:o.hidden=not o.get("hidden",false)
	plan.overrides[id]=o;rebuild()
func clear_part()->void:
	var id=selection();if filter==0 and id!="":
		var c=S.address(id.trim_prefix("column/"));id="column/"+S.key(c.x,c.y,0)
	if not plan.overrides.has(id):return
	remember();var o:Dictionary=plan.overrides[id]
	o.erase(["shift","style","hidden","", "scene"][filter])
	if o.is_empty():plan.overrides.erase(id)
	rebuild()
func operate()->void:
	var id=selection();var ok=view.switch_door(id) if filter==1 else view.use_socket(id);report.text=("Operated " if ok else "Blocked or not operable: ")+id
	if ok and view.doors.has(id):
		var door=view.doors[id];report.text="%s · %s · %s dB · nav link %s"%[id,"open" if door.open else "closed",door.port.get_meta("loss_db"),door.link.enabled]
func diagnostics()->void:report.text=summary+"\n"+"\n".join(solver.notes)
func camera_fit()->void:
	if detective_focus and detective.visible:
		cam.position=detective.base+Vector3(.10,1.35,2.28);cam.look_at(detective.base+Vector3.UP*.98);return
	var bounds=AABB();var first=true;for k in plan.cells:
		var c=S.address(k);if cut and c.z>level:continue
		var b=AABB(Vector3(c.x*S.BAY,solver.datum(c.z),c.y*S.BAY),Vector3(S.BAY,solver.room_height(k),S.BAY));bounds=b if first else bounds.merge(b);first=false
	var target=bounds.get_center();var dist=maxf(6,bounds.size.length()*1.16)*zoom;cam.position=target+Vector3(cos(az)*cos(el),sin(el),sin(az)*cos(el))*dist;cam.look_at(target)
func orbit(e:InputEvent)->void:
	if is_instance_valid(walker):return
	if e is InputEventMouseMotion and e.button_mask&MOUSE_BUTTON_MASK_RIGHT:az-=e.relative.x*.008;el=clampf(el+e.relative.y*.006,.12,1.5);camera_fit()
	if e is InputEventMouseButton and e.pressed:
		if e.button_index in [MOUSE_BUTTON_WHEEL_UP,MOUSE_BUTTON_WHEEL_DOWN]:zoom=clampf(zoom*(.88 if e.button_index==MOUSE_BUTTON_WHEEL_UP else 1.14),.25,3);camera_fit()
		elif e.button_index==MOUSE_BUTTON_LEFT:
			var a=cam.project_ray_origin(e.position);var q=PhysicsRayQueryParameters3D.create(a,a+cam.project_ray_normal(e.position)*180,S.USE|S.SIGHT);q.collide_with_areas=true;var hit=view.get_world_3d().direct_space_state.intersect_ray(q);if hit and hit.collider.has_meta("socket_id"):report.text="Interaction: "+str(view.use_socket(hit.collider.get_meta("socket_id")))
func save_plan()->void:
	var f=FileAccess.open(SAVE,FileAccess.WRITE);if f:f.store_string(JSON.stringify(plan,"  "));report.text="Saved: "+ProjectSettings.globalize_path(SAVE)
func load_plan()->void:
	var p=JSON.parse_string(FileAccess.get_file_as_string(SAVE)) if FileAccess.file_exists(SAVE) else null
	if not S.valid(p):report.text="No valid saved plan. Current drawing retained.";return
	remember();plan=p;rebuild()

# F enters a full-building inspection using the actual expedition capsule.
var walker:CharacterBody3D
var hidden_walk_controls:Array[Control]=[]
var capture_settle_frame:=0
func walk_toggle()->void:
	if is_instance_valid(walker):
		Input.mouse_mode=Input.MOUSE_MODE_VISIBLE
		viewport.remove_child(walker);walker.queue_free();walker=null
		for control in hidden_walk_controls:control.show()
		hidden_walk_controls.clear();cam.make_current();rebuild();return
	var cells=plan.cells.keys();cells.sort();var spawn_key=""
	for k in cells:
		var c=S.address(k)
		if c.z!=0 or solver.active_cores.has(k):continue
		if spawn_key=="" or (int(plan.cells[k])==0 and c.y>S.address(spawn_key).y):spawn_key=k
	if spawn_key=="":report.text="Paint a ground-floor bay without a shaft to enter.";return
	var c=S.address(spawn_key);var feet=Vector3((c.x+.55)*S.BAY,.035,(c.y+.65)*S.BAY)
	view.render(solver,-1,false);walker=preload("res://scenes/rogue_player/RoguePlayer.tscn").instantiate();walker.set_script(preload("InspectionPlayer.gd"));walker.first_person=true;walker.collision_layer=0;viewport.add_child(walker);walker.enter(feet,-.40);walker.camera().fov=70
	var split=section.get_parent();var col=split.get_parent()
	for control in col.get_children():
		if control!=split and control!=report and control.visible:hidden_walk_controls.append(control);control.hide()
	hidden_walk_controls.append(grid);grid.hide();capture_settle_frame=Engine.get_process_frames()+2;Input.mouse_mode=Input.MOUSE_MODE_CAPTURED
	report.text="SPACE INSPECTION   ·   1.60 m eye   |   WASD move   ·   mouse look   ·   E operate ahead   ·   F / Esc return"

func _input(e:InputEvent)->void:
	if e is InputEventKey and e.pressed and not e.echo:
		if not is_instance_valid(walker) and not get_viewport().gui_get_focus_owner() is LineEdit:
			if e.keycode==KEY_P:
				if not detective.visible:report.text="No clear bay for the detective on this level.";return
				detective_focus=not detective_focus;detective.choose(0,true)
				view.render(solver,level if cut and not detective_focus else -1,cut and not detective_focus,stage);camera_fit()
				report.text="DETECTIVE + VALE  ·  1–4 Basics   5 Signal   6 Examine   7 Listen   0 Cycle   N Next bay   P Return" if detective_focus else summary
				get_viewport().set_input_as_handled();return
			if detective_focus and e.keycode==KEY_N:
				detective.show_room(1);camera_fit();get_viewport().set_input_as_handled();return
			if detective_focus and e.keycode>=KEY_0 and e.keycode<=KEY_7:
				var number=e.keycode-KEY_0;detective.choose(maxi(0,number-1),number==0);get_viewport().set_input_as_handled();return
		if e.keycode==KEY_K and not is_instance_valid(walker) and not get_viewport().gui_get_focus_owner() is LineEdit:load_example(1);get_viewport().set_input_as_handled();return
		if e.keycode==KEY_F or (e.keycode==KEY_ESCAPE and is_instance_valid(walker)):
			walk_toggle();get_viewport().set_input_as_handled();return
		if is_instance_valid(walker) and e.keycode==KEY_E:
			var eye=walker.camera().global_position;var ray=PhysicsRayQueryParameters3D.create(eye,eye-walker.camera().global_basis.z*3,S.USE|S.SIGHT);ray.collide_with_areas=true
			var hit=view.get_world_3d().direct_space_state.intersect_ray(ray)
			if hit and hit.collider.has_meta("socket_id"):view.use_socket(hit.collider.get_meta("socket_id"))
	if is_instance_valid(walker) and e is InputEventMouseMotion:
		# Ignore pointer recentering on capture; each review starts at the authored yaw.
		if Engine.get_process_frames()>capture_settle_frame:walker.orbit_by(e.relative)
		get_viewport().set_input_as_handled()

func _exit_tree()->void:
	if is_instance_valid(walker):Input.mouse_mode=Input.MOUSE_MODE_VISIBLE
