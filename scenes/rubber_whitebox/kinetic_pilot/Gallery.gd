extends Node3D
## Viewer of the authoritative referee. Triangle vertices and every moving basis are supplied by replay.
const Figure = preload("../TestPlayer.tscn")
const Inputs = preload("../WhiteboxInput.gd")
const Arch = preload("res://tools/building_construction/BuildingConstruction/Shared/ArchitectGeometry.gd")
var stage := 3
var seed_value := 42
var record := {}
var motion: FileAccess
var last_motion_tick := -1
var frieze: Array = []
var rod_batch: MultiMesh
var wire_batch: MultiMesh
var eye_view := false
var moving: Array[Node3D] = []
var figures: Array[Node3D] = []
var camera := Camera3D.new()
var content: Node3D
var inspection_light: OmniLight3D
var lamp_slide: Node3D
var ray_mesh: MeshInstance3D
var info := Label.new()
var optics := Label.new()
var footer := Label.new()
var view_path := ""
var tick := 0
var pid := -1
var show_rays := false
var pause := false
var wide := false
var speed := 1
var last_scan := -1
var replay_input := ""
var rng_seeded := false
func _ready() -> void:
	Inputs.install({&"kin_home":KEY_HOME,&"kin_eye":KEY_C,&"kin_next":KEY_N,&"kin_optics":KEY_V,&"kin_pause":KEY_SPACE,&"kin_speed":KEY_X,&"kin_wide":KEY_TAB,&"kin_seek":KEY_J})
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--run-seed="): seed_value=int(arg.trim_prefix("--run-seed="));rng_seeded=true
		if arg.begins_with("--pilot-stage="): stage=int(arg.trim_prefix("--pilot-stage="))
		if arg.begins_with("--arena-replay="): replay_input=arg.trim_prefix("--arena-replay=")
	if not rng_seeded: seed_value = randi()
	var world:=WorldEnvironment.new();var env:=Environment.new();env.background_mode=Environment.BG_COLOR;env.background_color=Color("182128");env.ambient_light_source=Environment.AMBIENT_SOURCE_COLOR;env.ambient_light_color=Color("c3cece");env.ambient_light_energy=.53;env.sdfgi_enabled=true;env.tonemap_mode=Environment.TONE_MAPPER_FILMIC;world.environment=env;add_child(world)
	var sun:=DirectionalLight3D.new();sun.rotation_degrees.x=-90;sun.shadow_enabled=true;sun.light_angular_distance=0;sun.light_energy=1.64;sun.light_color=Color("fff3d8");add_child(sun);add_child(camera);camera.make_current()
	var hud:=CanvasLayer.new();add_child(hud)
	for item in [[info,Vector2(18,14),19],[optics,Vector2(18,57),15],[footer,Vector2(18,-49),15]]:
		var panel:=PanelContainer.new();hud.add_child(panel);var style:=StyleBoxFlat.new();style.bg_color=Color("172329ed");style.border_width_left=3;style.border_color=Color("c99f61");style.content_margin_left=12;style.content_margin_right=12;style.content_margin_top=6;style.content_margin_bottom=6;panel.add_theme_stylebox_override("panel",style)
		if item[0]==footer: panel.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT)
		panel.offset_left=item[1].x;panel.offset_top=item[1].y;panel.add_child(item[0]);item[0].add_theme_font_size_override("font_size",item[2]);item[0].modulate=Color("f6eddc")
	var mono:=SystemFont.new();mono.font_names=PackedStringArray(["Consolas","monospace"]);optics.add_theme_font_override("font",mono);optics.get_parent().hide();_load_room()
func _load_room() -> void:
	if content: remove_child(content);content.queue_free()
	content=Node3D.new();add_child(content);moving.clear();frieze.clear();last_motion_tick=-1;figures.clear();record={};last_scan=-1;tick=0;pause=false
	info.text="KINETIC STUDIES   /   Adjudicating…";footer.text="Loading the submitted program and compact tape";optics.get_parent().hide()
	var dir:=ProjectSettings.globalize_path("res://.runtime/kinetic/view-%d-%d"%[OS.get_process_id(),stage]);DirAccess.make_dir_recursive_absolute(dir);view_path=dir.path_join("view.json")
	if FileAccess.file_exists(view_path):DirAccess.remove_absolute(view_path)
	var js:=ProjectSettings.globalize_path("res://tools/rule_arena/kinetic/arena.mjs");var args:=PackedStringArray([js,"run","--stage",str(stage),"--seed",str(seed_value),"--out",dir.path_join("run.json"),"--view",view_path])
	if not replay_input.is_empty():args=PackedStringArray([js,"replay","--in",replay_input,"--view",view_path]);
	pid=OS.create_process("node",args,false)
func _process(_dt:float) -> void:
	if record.is_empty():
		if FileAccess.file_exists(view_path):
			record=JSON.parse_string(FileAccess.get_file_as_string(view_path));stage=int(record.stage);motion=FileAccess.open(view_path+".motion", FileAccess.READ);_build();_show(0)
		elif pid<0 or not OS.is_process_running(pid):footer.text="Judge failed to start; check Node and npm ci --prefix tools/rule_arena"
func _physics_process(_dt:float) -> void:
	if record.is_empty():return
	if Input.is_action_just_pressed("kin_next") and replay_input.is_empty():stage=6 if stage==3 else 3;_load_room();return
	if Input.is_action_just_pressed("kin_optics"):show_rays=not show_rays;last_scan=-1
	if Input.is_action_just_pressed("kin_pause"):pause=not pause
	if Input.is_action_just_pressed("kin_wide"):eye_view=false;wide=not wide;_frame()
	if Input.is_action_just_pressed("kin_eye"):eye_view=not eye_view;_frame()
	if Input.is_action_just_pressed("kin_home"):tick=0;last_scan=-1
	if Input.is_action_just_pressed("kin_speed"): speed=1 if speed==4 else speed*2
	if Input.is_action_just_pressed("kin_seek"):
		var patch_tick:int=record.audit[0].t if not record.audit.is_empty() else 0
		var operating:=patch_tick+65
		if stage==6:
			for i in record.rows.size():
				if record.rows[i][5]>=.5:operating=i;break
		var milestones:Array=[patch_tick,operating,int(record.ticks)-115,int(record.ticks)-65,int(record.ticks)]
		for v:int in milestones:
			if v>tick+2:tick=v;break
	_show(mini(int(record.ticks),tick+(0 if pause else speed)))
func _vector(a:Array) -> Vector3:return Vector3(a[0],a[1],a[2])
func _xf(a:Array) -> Transform3D:return Transform3D(Basis(Vector3(a[0],a[1],a[2]),Vector3(a[3],a[4],a[5]),Vector3(a[6],a[7],a[8])),Vector3(a[9],a[10],a[11]))
func _build() -> void:
	var meshes:={};var palette:={}
	for key in record.spec.meshes:
		var m:Dictionary=record.spec.meshes[key];var st:=SurfaceTool.new();st.begin(Mesh.PRIMITIVE_TRIANGLES)
		for f:Array in m.f:
			var a:=_vector(m.v[int(f[0])]);var b:=_vector(m.v[int(f[1])]);var c:=_vector(m.v[int(f[2])]);var normal:=(b-a).cross(c-a)
			if normal.length_squared()<.000000001:continue
			for v:Vector3 in [a,c,b]:st.set_normal(normal.normalized());st.add_vertex(v)
		meshes[key]=st.commit()
	var by_id:={};var floor_mat:=ShaderMaterial.new();floor_mat.shader=preload("Floor.gdshader")
	var wheel_mat:=ShaderMaterial.new();wheel_mat.shader=preload("Flywheel.gdshader")
	var batches := {}
	var suspended := {}
	for key:String in ["rod", "wire"]:
		var batch := MultiMesh.new()
		batch.transform_format = MultiMesh.TRANSFORM_3D
		batch.mesh = meshes[key]
		batch.instance_count = record.spec.frieze.size() * (1 if key == "rod" else 2)
		var group := MultiMeshInstance3D.new()
		group.multimesh = batch
		content.add_child(group)
		batches[key] = group
	rod_batch = batches["rod"].multimesh
	wire_batch = batches["wire"].multimesh
	for n:Dictionary in record.spec.nodes:
		if not palette.has(n.color):
			var mat:=StandardMaterial3D.new();mat.albedo_color=Color(n.color);mat.cull_mode=BaseMaterial3D.CULL_DISABLED;mat.roughness=.41 if n.kind in ["flywheel","bell","suspended rod"] else .7;mat.metallic=.38 if n.kind in ["flywheel","bell","suspended rod"] else .04;palette[n.color]=mat
		if batches.has(n.g):
			suspended[n.id] = _xf(n.m)
			batches[n.g].material_override = palette[n.color]
			continue
		var model:=MeshInstance3D.new();model.mesh=meshes[n.g];content.add_child(model);model.transform=_xf(n.m);by_id[n.id]=model
		model.material_override=floor_mat if n.kind=="floor" else (wheel_mat if n.kind=="flywheel" else palette[n.color])
	for id in record.spec.moving:moving.append(by_id[id])
	for ids:Array in record.spec.frieze:frieze.append([suspended[ids[0]],suspended[ids[1]],suspended[ids[2]]])
	var base:=Arch.prism([[-9.22,-9.22],[9.22,-9.22],[9.22,9.22],[-9.22,9.22]],-.55,-.25,"grout");content.add_child(base)
	for i in 2:
		var dummy:=Figure.instantiate();var fig:=dummy.get_node("Figure") as Node3D;dummy.remove_child(fig);dummy.free();content.add_child(fig);figures.append(fig)
		var collar:=MeshInstance3D.new();var disc:=CylinderMesh.new();disc.top_radius=.34;disc.bottom_radius=.34;disc.height=.027;collar.mesh=disc;var mat:=StandardMaterial3D.new();mat.albedo_color=Color("63d6cc") if i==0 else Color("df9947");collar.material_override=mat;fig.add_child(collar)
	lamp_slide=by_id["lampSlide"];var local:=OmniLight3D.new();inspection_light=local;local.position=Vector3(0,2.1,5.3) if stage==3 else Vector3(6.1,1,7.3);local.omni_range=5.8;local.light_color=Color("ffd5a0");local.light_energy=1.4;local.shadow_enabled=true;content.add_child(local)
	ray_mesh=MeshInstance3D.new();content.add_child(ray_mesh);ray_mesh.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF;_frame()
func _frame() -> void:
	camera.projection=Camera3D.PROJECTION_PERSPECTIVE;camera.fov=47
	var aim:=Vector3(0,2,.4) if stage==3 else Vector3(.25,2.65,.65)
	camera.position=Vector3(12,10.1,17.8) if stage==3 else Vector3(15.2,11.3,18.2)
	if wide:
		camera.position=Vector3(3.4,3.1,8.0) if stage==3 else Vector3(10.5,3.15,9.7)
		aim=Vector3(0,2.05,.55) if stage==3 else Vector3(3.1,1.25,4.2)
	camera.look_at(aim)
func _show(t:int) -> void:
	tick=t
	if t!=last_motion_tick:
		last_motion_tick=t
		var stride:=(moving.size()*12+frieze.size())*4;motion.seek(t*stride)
		var f:=motion.get_buffer(stride).to_float32_array();var i:=0
		for node in moving:
			node.transform=Transform3D(Basis(Vector3(f[i],f[i+1],f[i+2]),Vector3(f[i+3],f[i+4],f[i+5]),Vector3(f[i+6],f[i+7],f[i+8])),Vector3(f[i+9],f[i+10],f[i+11]));i+=12
		for k in frieze.size():
			var y:=f[i];i+=1
			var rod:Transform3D=frieze[k][0];rod.origin.y=y
			rod_batch.set_instance_transform(k,rod)
			for side in 2:
				var wire:Transform3D=frieze[k][side+1]
				wire.origin.y=(5.42+y)*.5;wire.basis.y=Vector3.UP*(5.42-y)
				wire_batch.set_instance_transform(2*k+side,wire)
	inspection_light.position=lamp_slide.position+Vector3.UP*.095
	var row:Array=record.rows[t]
	for i in 2:
		var p:=Vector3(row[i*2],0,row[i*2+1]);var delta:=p-figures[i].position;figures[i].position=p
		if delta.length_squared()>.00001:figures[i].rotation.y=atan2(-delta.x,-delta.z)
	figures[0].rotation.y=-deg_to_rad(float(row[4]))
	figures[0].visible=not eye_view
	if eye_view:
		camera.fov=80;camera.position=figures[0].position+Vector3.UP*1.45;camera.rotation=Vector3(0,-deg_to_rad(float(row[4])),0)
	info.text="NIGHT WATCH   /   %02d     %s"%[stage,"BELL COROLLA" if stage==3 else "PRECESSION STUDY"]
	var site:String=("Plate held" if row[8] else "Plate free") if stage==3 else ("Trolley %.2f m"%row[5]);footer.text="t %04d   /   %s   /   %s   /   %s     •     V optics   J cue   N room   Tab view   C eye   Space pause"%[t,site,"Proof accepted" if row[7] else "Native handbook",record.result if t==int(record.ticks) else "Walking score"]
	optics.get_parent().visible=show_rays;ray_mesh.visible=show_rays
	var idx:=mini(t/20,record.scans.size()-1)
	if show_rays and idx!=last_scan:_rays(record.scans[idx],idx);last_scan=idx
func _rays(scan:Dictionary,idx:int) -> void:
	var lines:PackedStringArray=["CAPTAIN  /  LOCAL SCAN  %04d"%(idx*20)];var im:=ImmediateMesh.new();var mat:=StandardMaterial3D.new();mat.shading_mode=BaseMaterial3D.SHADING_MODE_UNSHADED;mat.albedo_color=Color("75c4b8");mat.vertex_color_use_as_albedo=true;mat.albedo_color=Color.WHITE;im.surface_begin(Mesh.PRIMITIVE_LINES,mat);var origin:=Vector3(scan.at[0],1.45,scan.at[1]);var count:=0
	for i in 3:
		var line:String=["LOW ","EYE ","HIGH"][i]
		for k in 9:
			var r:Variant=scan.r[i*9+k];var name_str:="·"
			if r!=null:
				im.surface_set_color(Color("53d5b7"));name_str=str(r[0]).substr(0,2).to_upper();im.surface_add_vertex(origin);im.surface_add_vertex(_vector(r[2]));count+=1
			else:
				# Null readings have no measured range; show only an angular stub at the scanner.
				var az:=deg_to_rad(float(scan.yaw)+k*15.0-60.0);var el:=deg_to_rad((i-1)*15.0)
				var dir:=Vector3(sin(az)*cos(el),sin(el),-cos(az)*cos(el));im.surface_set_color(Color("667a82"));im.surface_add_vertex(origin+dir*.12);im.surface_add_vertex(origin+dir*.45)
			line+=" %2s"%name_str
		lines.append(line)
	if count==0:im.surface_add_vertex(origin);im.surface_add_vertex(origin)
	im.surface_end();ray_mesh.mesh=im;optics.text="\n".join(lines)
func mcp_observe()->Dictionary:return {"loaded":not record.is_empty(),"stage":stage,"tick":tick,"optics":show_rays,"fps":Engine.get_frames_per_second(),"paused":pause,"result":record.get("result",""),"view":view_path}
