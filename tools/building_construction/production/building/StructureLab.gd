extends PanelContainer
const S=preload("BuildingSolver.gd")
const V=preload("BuildingView.gd")
const Grid=preload("PlanCanvas.gd")
const SAVE="user://academy-structure-v1.json"
var dx_input=SpinBox.new();var dz_input=SpinBox.new();var radius=SpinBox.new();var room_number=1;var plan=S.example();var solver=S.new();var view=V.new();var grid=Grid.new();var level=0;var brush=0;var tool=0;var cut=true;var history=[];var redo=[]
var list=OptionButton.new();var report=RichTextLabel.new();var cam=Camera3D.new();var section=SubViewportContainer.new();var viewport=SubViewport.new();var az=.64;var el=.64;var stage=5;var zoom=.70;var summary="";var filter=0;var repairs=CheckButton.new();var seed_input=SpinBox.new()
func btn(parent:Control,title:String,action:Callable)->void:
	var b=Button.new();b.text=title;b.pressed.connect(action);parent.add_child(b)
func opt(parent:Control,names:Array,cb:Callable)->OptionButton:
	var o=OptionButton.new();for n in names:o.add_item(n)
	o.item_selected.connect(cb);parent.add_child(o);return o
func caption(parent:Control,t:String)->void:
	var l=Label.new();l.text=t;parent.add_child(l)
func _ready()->void:
	var style=StyleBoxFlat.new();style.bg_color=Color("202a32");add_theme_stylebox_override("panel",style);add_theme_constant_override("separation",6)
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT);var col=VBoxContainer.new();add_child(col);var bar=HBoxContainer.new();col.add_child(bar);caption(bar,"  ARCHBUILDER  /  STRUCTURE LAB     ")
	btn(bar,"Undo",func():travel(history,redo));btn(bar,"Redo",func():travel(redo,history));btn(bar,"Save",save_plan);btn(bar,"Load",load_plan);btn(bar,"Example",func():remember();plan=S.example();rebuild());btn(bar,"New from seed",func():remember();plan=S.generate(int(seed_input.value));rebuild());btn(bar,"Close",func():
		if get_parent() is Control:queue_free()
		else:get_tree().quit())
	var edit=HBoxContainer.new();col.add_child(edit);opt(edit,["Ground","Level 2","Level 3","Level 4"],func(i):level=i;rebuild());opt(edit,S.TYPES,func(i):brush=i;grid.brush=i);opt(edit,["Paint room","Erase bay","U stair up","Spiral up","Service shaft up","Remove core"],func(i):tool=i);var show=CheckButton.new();show.text="Grid";show.button_pressed=true;edit.add_child(show);show.toggled.connect(func(v):grid.show_grid=v;grid.queue_redraw());var slice=CheckButton.new();slice.text="Cutaway";slice.button_pressed=true;edit.add_child(slice);slice.toggled.connect(func(v):cut=v;rebuild());repairs.text="Auto repair";repairs.button_pressed=true;edit.add_child(repairs);repairs.toggled.connect(func(v):remember();plan.mode="repair" if v else "strict";rebuild())
	caption(edit,"Seed");seed_input.min_value=0;seed_input.max_value=999999;seed_input.value=plan.seed;edit.add_child(seed_input);btn(edit,"Apply",func():remember();plan.seed=int(seed_input.value);rebuild())
	var params=HBoxContainer.new();col.add_child(params);caption(params,"  Room group");var group=SpinBox.new();group.min_value=1;group.max_value=99;params.add_child(group);group.value_changed.connect(func(v):room_number=int(v));caption(params,"Spiral clearance");radius.min_value=1.0;radius.max_value=1.7;radius.step=.1;radius.value=1.6;params.add_child(radius);radius.value_changed.connect(func(v):remember();plan.spiral_radius=v;rebuild());btn(params,"Bake navigation",func():report.text=view.bake_routes());btn(params,"Audit panels",func():report.text=view.audit_sockets());
	caption(params,"Pin ΔX / ΔZ");for spin in [dx_input,dz_input]:spin.min_value=-.65;spin.max_value=.65;spin.step=.05;params.add_child(spin)
	dx_input.value=.35
	var split=HSplitContainer.new();split.size_flags_vertical=SIZE_EXPAND_FILL;col.add_child(split);grid.size_flags_horizontal=SIZE_EXPAND_FILL;grid.custom_minimum_size.x=220;split.add_child(grid);grid.stroke.connect(paint);section.size_flags_horizontal=SIZE_EXPAND_FILL;section.custom_minimum_size.x=320;section.stretch=true;split.add_child(section);split.split_offset=-170;viewport.own_world_3d=true;viewport.use_occlusion_culling=true;section.add_child(viewport);viewport.add_child(view);viewport.add_child(cam);cam.current=true
	var env=WorldEnvironment.new();var e=preload("res://scenes/components/rendering/post/Hall04.tres").duplicate();e.background_mode=Environment.BG_COLOR;e.background_color=Color("303c47");e.ambient_light_source=Environment.AMBIENT_SOURCE_COLOR;e.ambient_light_color=Color("e9ddc6");e.ambient_light_energy=.85;env.environment=e;viewport.add_child(env);var sun=DirectionalLight3D.new();sun.rotation_degrees=Vector3(-54,-32,0);sun.shadow_enabled=true;viewport.add_child(sun);section.gui_input.connect(orbit)
	var row=HBoxContainer.new();col.add_child(row);opt(row,["Columns","Doors","Lights","Valves"],func(i):filter=i;fill_list());list.custom_minimum_size.x=175;row.add_child(list);btn(row,"Pin / update",override_part);btn(row,"Clear override",clear_part);btn(row,"Operate",operate);btn(row,"Diagnostics",diagnostics)
	var seq=opt(row,["1 · Slabs","2 · Frame","3 · Walls","4 · Detail","5 · Full"],func(i):stage=i+1;rebuild());seq.select(4)
	report.custom_minimum_size.y=60;report.fit_content=false;col.add_child(report);rebuild()
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
	solver.build(plan);view.render(solver,level if cut else -1,cut,stage);grid.plan=plan;grid.level=level;grid.queue_redraw();seed_input.value=plan.seed;radius.set_value_no_signal(plan.get("spiral_radius",1.6));repairs.set_pressed_no_signal(plan.mode=="repair");fill_list();camera_fit();summary="%d bays   ·   %d wall segments   ·   %d portals/vertical links   ·   %d overrides   ·   %d diagnostics"%[plan.cells.size(),solver.wall_hosts.size(),solver.links.size(),plan.overrides.size(),solver.notes.size()];report.text=summary+"\nDrag grid to paint (4.2 m snap). RMB orbit · wheel zoom. Pin saves column shift / door finish / lamp suppression."
func fill_list()->void:
	var old=list.get_item_text(list.selected) if list.selected>=0 else "";list.clear();var prefix=["column/","door/","light/","valve/"][filter];var ids=solver.choices.keys() if filter!=3 else view.valves.keys();if filter==3:ids=[];for o in solver.sockets:if o.kind=="valve" and view.visible_owner(o.owner):ids.append(o.id)
	ids.sort();for id in ids:
		if id.begins_with(prefix) and (not solver.choices.has(id) or view.visible_owner(solver.choices[id].owner)):list.add_item(id);if id==old:list.select(list.item_count-1)
func selection()->String:return list.get_item_text(list.selected) if list.selected>=0 else ""
func override_part()->void:
	var id=selection();if id=="" or filter==3:return
	if filter==0:
		var c=S.address(id.trim_prefix("column/"));id="column/"+S.key(c.x,c.y,0)
	remember();var o=plan.overrides.get(id,{});match filter:
		0:o={"shift":[dx_input.value,dz_input.value]}
		1:o={"style":"oak" if o.get("style","oak")=="iron" else "iron"}
		2:o={"hidden":not o.get("hidden",false)}
	plan.overrides[id]=o;rebuild()
func clear_part()->void:
	var id=selection();if filter==0 and id!="":
		var c=S.address(id.trim_prefix("column/"));id="column/"+S.key(c.x,c.y,0)
	if not plan.overrides.has(id):return
	remember();plan.overrides.erase(id);rebuild()
func operate()->void:
	var id=selection();var ok=view.switch_door(id) if filter==1 else view.use_socket(id);report.text=("Operated " if ok else "Blocked or not operable: ")+id
	if ok and view.doors.has(id):
		var door=view.doors[id];report.text="%s · %s · %s dB · nav link %s"%[id,"open" if door.open else "closed",door.port.get_meta("loss_db"),door.link.enabled]
func diagnostics()->void:report.text=summary+"\n"+"\n".join(solver.notes)
func camera_fit()->void:
	var bounds=AABB();var first=true;for k in plan.cells:
		var c=S.address(k);if cut and c.z>level:continue
		var b=AABB(Vector3(c.x*S.BAY,c.z*S.RISE,c.y*S.BAY),Vector3(S.BAY,S.RISE,S.BAY));bounds=b if first else bounds.merge(b);first=false
	var target=bounds.get_center();var dist=maxf(6,bounds.size.length()*1.16)*zoom;cam.position=target+Vector3(cos(az)*cos(el),sin(el),sin(az)*cos(el))*dist;cam.look_at(target)
func orbit(e:InputEvent)->void:
	if e is InputEventMouseMotion and e.button_mask&MOUSE_BUTTON_MASK_RIGHT:az-=e.relative.x*.008;el=clampf(el+e.relative.y*.006,.12,1.5);camera_fit()
	if e is InputEventMouseButton and e.pressed:
		if e.button_index in [MOUSE_BUTTON_WHEEL_UP,MOUSE_BUTTON_WHEEL_DOWN]:zoom=clampf(zoom*(.88 if e.button_index==MOUSE_BUTTON_WHEEL_UP else 1.14),.25,3);camera_fit()
		elif e.button_index==MOUSE_BUTTON_LEFT:
			var a=cam.project_ray_origin(e.position);var q=PhysicsRayQueryParameters3D.create(a,a+cam.project_ray_normal(e.position)*180,S.USE|S.SIGHT);q.collide_with_areas=true;var hit=viewport.world_3d.direct_space_state.intersect_ray(q);if hit and hit.collider.has_meta("socket_id"):report.text="Interaction: "+str(view.use_socket(hit.collider.get_meta("socket_id")))
func save_plan()->void:
	var f=FileAccess.open(SAVE,FileAccess.WRITE);if f:f.store_string(JSON.stringify(plan,"  "));report.text="Saved: "+ProjectSettings.globalize_path(SAVE)
func load_plan()->void:
	var p=JSON.parse_string(FileAccess.get_file_as_string(SAVE)) if FileAccess.file_exists(SAVE) else null
	if not S.valid(p):report.text="No valid saved plan. Current drawing retained.";return
	remember();plan=p;rebuild()
