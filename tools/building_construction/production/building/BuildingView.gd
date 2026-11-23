extends Node3D
## Material batches and physical meshes are compiled from the same triangles.
const Geo=preload("../../BuildingConstruction/Shared/ArchitectGeometry.gd")
const Factory=preload("../../BuildingConstruction/Shared/ComponentFactory.gd")
const S=preload("BuildingSolver.gd")
var batches={};var physics={};var doors={};var valves={};var panels={};var regions={}
var hide_roof:=false
var slice:=-1
var model
# View-local materials: keep the component library and its cached originals intact.
const PIGMENTS={"wall":"c8b99f","stone":"b4afa5","stone_dark":"757988","wood":"916e58","wood_dark":"635052","wood_light":"ab8970","cream":"e1d6ba","tile_dark":"48515e","tile_light":"d9d4c5","grout":"797b82"}
var paints:Dictionary={}
func finish(key:String)->Material:
	if paints.has(key):return paints[key]
	var mat:Material=Geo.material(key).duplicate()
	if mat is ShaderMaterial:
		if PIGMENTS.has(key):mat.set_shader_parameter("pigment",Color(PIGMENTS[key]))
		mat.set_shader_parameter("clearline",true)
		mat.set_shader_parameter("roughness",.93)
		mat.set_shader_parameter("specular_amount",.06)
		if key=="wall":mat.set_shader_parameter("wall_lift",.07)
	elif key in ["gold","glass"]:
		mat.roughness=.32 if key=="gold" else .20
		mat.metallic_specular=.32
	elif mat is StandardMaterial3D:mat.roughness=.93
	paints[key]=mat
	return mat
const NORMALS=[Vector3.RIGHT,Vector3.LEFT,Vector3.UP,Vector3.DOWN,Vector3.BACK,Vector3.FORWARD]
func tri(tag:String,mat:String,a:Vector3,b:Vector3,c:Vector3,n:Vector3,mask:int,visual:=true,smooth:Array=[])->void:
	if visual:
		var id=tag+"|"+mat
		if not batches.has(id):
			var st=SurfaceTool.new();st.begin(Mesh.PRIMITIVE_TRIANGLES);st.set_material(finish(mat));batches[id]=st
		var st:SurfaceTool=batches[id];var u=Vector3.RIGHT if absf(n.y)>.9 else Vector3.UP.cross(n).normalized();var v=n.cross(u)
		var i=0
		for p in [a,b,c]:
			st.set_normal(n if smooth.is_empty() else smooth[i]);st.set_uv(Vector2(p.dot(u),p.dot(v)));st.add_vertex(p);i+=1
	if mask:
		var id=tag+"|"+str(mask);if not physics.has(id):physics[id]=[]
		physics[id].append_array([a,b,c])
func block(r:Dictionary)->void:
	var rot=Basis(Vector3.UP,r.yaw);var extent:Vector3=r.size*.5
	for n in NORMALS:
		var u=Vector3.RIGHT if absf(n.y)>.9 else Vector3.UP.cross(n);var v=n.cross(u);var pts=[]
		for uv in [Vector2(-1,-1),Vector2(-1,1),Vector2(1,1),Vector2(1,-1)]:pts.append(r.p+rot*((n+u*uv.x+v*uv.y)*extent))
		for ix in [[0,1,2],[0,2,3]]:tri(r.owner,r.mat,pts[ix[0]],pts[ix[1]],pts[ix[2]],rot*n,r.mask)
# Cumulative construction preview. Stages use the very same solved geometry as Full.
static func block_stage(id:String)->int:
	if "/slab" in id:return 1
	if id.begins_with("column/") or id.begins_with("plinth/") or id.begins_with("capital/") or id.begins_with("beam/"):return 2
	if "/wall" in id or "/finish" in id or "/niche" in id:return 3
	return 4
func render(s,level:int,cutaway:bool,stage:=5)->void:
	model=s;hide_roof=cutaway;slice=level
	for n in get_children():remove_child(n);n.queue_free()
	batches.clear();physics.clear();doors.clear();panels.clear();valves.clear();regions.clear()
	for r in s.pieces:
		if cutaway and "/coffer-soffit" in r.id and S.address(r.owner).z==level:continue
		if visible_owner(r.owner) and block_stage(r.id)<=stage:block(r)
	for f in s.facets:
		if stage<4 or not visible_owner(f[0]) or ((stage<5 or cutaway) and str(f[1])=="book_blue"):continue
		var normal:Vector3=(f[4]-f[2]).cross(f[3]-f[2]).normalized();tri(f[0],f[1],f[2],f[3],f[4],normal,f[5],f[1]!="walk_proxy",f[6])
	for r in s.roofs:
		if stage<5 or not visible_owner(r[0]) or cutaway:continue
		var n:Vector3=(r[3]-r[1]).cross(r[2]-r[1]).normalized();tri(r[0],"book_blue",r[1],r[2],r[3],n,3);tri(r[0],"cream",r[1],r[3],r[2],-n,0)
	for item in batches:
		var st:SurfaceTool=batches[item];st.index();var mesh=MeshInstance3D.new();var baked=st.commit();mesh.mesh=baked;
		if baked.surface_get_array_len(0)>200:
			var imp=ImporterMesh.new();imp.add_surface(Mesh.PRIMITIVE_TRIANGLES,baked.surface_get_arrays(0),[],{},baked.surface_get_material(0));imp.generate_lods(45,65,[]);mesh.mesh=imp.get_mesh()
		mesh.visibility_range_end=140.;mesh.visibility_range_end_margin=12.;add_child(mesh)
	for item in physics:
		var faces=PackedVector3Array(physics[item]);var mask=int(item.get_slice("|",1));var body=StaticBody3D.new();body.collision_layer=mask|(16 if mask&S.MOVE else 0);add_child(body);var col=CollisionShape3D.new();var shape=ConcavePolygonShape3D.new();shape.backface_collision=true;shape.set_faces(faces);col.shape=shape;body.add_child(col)
		if mask&S.SIGHT:
			var occ=ArrayOccluder3D.new();var inds=PackedInt32Array();inds.resize(faces.size());for i in inds.size():inds[i]=i
			occ.set_arrays(faces,inds);var node=OccluderInstance3D.new();node.occluder=occ;add_child(node)
	for item in s.sockets:
		if stage==5 and visible_owner(item.owner):emit_socket(item)
	make_zones();batches.clear();physics.clear()
func visible_owner(k:String)->bool:return slice<0 or S.address(k).z<=slice
func solid(parent:Node3D,sz:Vector3,p:Vector3,mat:String,mask:int)->Node3D:
	var m=Geo.box(sz,mat,p);m.material_override=finish(mat);parent.add_child(m)
	if mask:
		var body=StaticBody3D.new();body.collision_layer=mask;m.add_child(body);var col=CollisionShape3D.new();var shape=BoxShape3D.new();shape.size=sz;col.shape=shape;body.add_child(col)
	return m
func trigger(parent:Node3D,id:String,sz:Vector3,mask:int)->Area3D:
	var a=Area3D.new();a.set_meta("socket_id",id);a.collision_layer=mask;a.collision_mask=0;parent.add_child(a);var col=CollisionShape3D.new();var shape=BoxShape3D.new();shape.size=sz;col.shape=shape;a.add_child(col);return a
func mount_scene(parent:Node3D,path:String,contract:Dictionary)->void:
	var prefab=load(path).instantiate()
	if not prefab is Node3D:prefab.free();push_error("Slot prefab needs a Node3D root: "+path);return
	parent.add_child(prefab)
	if prefab.has_method("configure_slot"):prefab.configure_slot(contract)
func emit_socket(o:Dictionary)->void:
	if o.kind=="zone" or (o.kind=="valley" and hide_roof):return
	var root=Node3D.new();root.position=o.p;root.rotation.y=o.get("yaw",0.);root.set_meta("structure_id",o.id);add_child(root)
	match o.kind:
		"custom":mount_scene(root,o.scene,o.get("slot",o))
		"light":
			solid(root,Vector3(.34,.05,.34) if o.get("flush",false) else Vector3(.28,.14,.28),Vector3.ZERO,"emission",0);var lamp=OmniLight3D.new();lamp.position.y=-.30;lamp.light_color=Color("ffd29a");lamp.omni_range=4.2;lamp.omni_attenuation=1.6;lamp.light_energy=.60;lamp.distance_fade_enabled=true;lamp.distance_fade_begin=22;root.add_child(lamp)
		"door":
			var pivot=Node3D.new();pivot.position.x=-o.width/2;root.add_child(pivot);var iron=o.style=="iron"
			if o.get("scene","")!="":
				var leaf=Node3D.new();leaf.position.x=o.width*.5;pivot.add_child(leaf);mount_scene(leaf,o.scene,model.slots[o.id])
				var body=StaticBody3D.new();body.collision_layer=3;leaf.add_child(body);var col=CollisionShape3D.new();var sh=BoxShape3D.new();sh.size=Vector3(o.width,o.height,.09);col.shape=sh;col.position.y=o.height*.5;body.add_child(col)
			elif o.style in ["steel","sliding"]:
				solid(pivot,Vector3(o.width,o.height,.09),Vector3(o.width*.5,o.height*.5,0),"stone_dark",3)
				for h in [.28,o.height-.28]:solid(pivot,Vector3(o.width,.065,.12),Vector3(o.width*.5,h,0),"grout",0)
			elif iron:
				for i in 8:solid(pivot,Vector3(.035,o.height,.06),Vector3(.03+i*(o.width-.06)/7,o.height/2,0),"gold",0)
				for h in [.12,o.height-.12]:solid(pivot,Vector3(o.width,.09,.07),Vector3(o.width/2,h,0),"wood_dark",0)
				var b=StaticBody3D.new();b.collision_layer=S.MOVE;pivot.add_child(b);var c=CollisionShape3D.new();var sh=BoxShape3D.new();sh.size=Vector3(o.width,o.height,.06);c.shape=sh;c.position=Vector3(o.width/2,o.height/2,0);b.add_child(c)
			else:
				solid(pivot,Vector3(o.width,o.height,.09),Vector3(o.width/2,o.height/2,0),"wood",3)
				for face in [-1,1]:
					for section in [[.23,.31],[.68,.47]]:
						var h:float=o.height*section[1];var cy:float=o.height*section[0]
						solid(pivot,Vector3(o.width-.24,h,.025),Vector3(o.width*.5,cy,face*.056),"wood_light",0)
						solid(pivot,Vector3(o.width-.32,h-.08,.02),Vector3(o.width*.5,cy,face*.078),"wood",0)
					solid(pivot,Vector3(.05,.17,.055),Vector3(o.width-.085,1.01,face*.069),"gold",0)
					solid(pivot,Vector3(.12,.032,.07),Vector3(o.width-.115,1.01,face*.119),"gold",0)
			for face in [-1,1]:
				var z:float=face*(o.wall_depth*.5+.03)
				for side in [-1,1]:solid(root,Vector3(.105,o.height,.064),Vector3(side*(o.width*.5+.0525),o.height*.5,z),"wood_dark",0)
				solid(root,Vector3(o.width+.21,.09,.064),Vector3(0,o.height+.045,z),"wood_light",0)
			var port=trigger(root,o.id,Vector3(o.width,o.height,.22),S.SOUND);port.position.y=o.height/2
			var nav=NavigationLink3D.new();nav.start_position=Vector3(0,.02,-.42);nav.end_position=Vector3(0,.02,.42);nav.enabled=false;root.add_child(nav)
			doors[o.id]={"slide":o.style=="sliding","width":o.width,"pivot":pivot,"open":false,"group":o.interlock,"port":port,"link":nav,"closed_db":6 if iron else 24};port.set_meta("loss_db",doors[o.id].closed_db)
		"panel","valve":
			solid(root,Vector3(.26,.2,.075),Vector3.ZERO,"gold",0);var area=trigger(root,o.id,Vector3(.32,.28,.16),S.USE);area.set_meta("target",o.get("target",o.get("network","")))
			if o.kind=="panel":
				panels[o.id]=o.target;var label=Label3D.new();label.text=o.caption;label.pixel_size=.0012;label.font_size=28;label.position.z=.045;label.double_sided=true;root.add_child(label)
			else:valves[o.network]=true
		"link":
			var link=NavigationLink3D.new();link.end_position=o.end-o.p;root.add_child(link)
		"fixture":
			var paths=["Props/RecipeStorageRack","Props/RecipeCrockeryShelf","Tables/RecipeInstrumentTable","Tables/RecipeTable","Tables/RecipeSlateTable","Props/RecipeValveStation"]
			var obj=Factory.create(Factory.COMPONENT_ROOT+paths[int(o.type)]+".gd")
			if obj:
				obj.scale=Vector3.ONE*.48;root.add_child(obj)
				for mesh in obj.find_children("*","MeshInstance3D",true,false):
					var key=Geo.materials.find_key(mesh.material_override)
					if key!=null:mesh.material_override=finish(key)
		"valley":
			var dir:Vector3=o.end-o.p;var rail=Geo.box(Vector3(.09,.05,dir.length()),"gold",dir*.5+Vector3.UP*.03);rail.material_override=finish("gold");root.add_child(rail);rail.look_at(to_global(o.end+Vector3.UP*.03),Vector3.UP)
func switch_door(id:String)->bool:
	if not doors.has(id):return false
	var d=doors[id];if not d.open and d.group!="":
		for other in doors.values():
			if other.group==d.group and other.open:return false
	d.open=not d.open
	if d.slide:d.pivot.position.x=d.width*(.52 if d.open else -.5)
	else:d.pivot.rotation.y=PI*.5 if d.open else 0.
	d.link.enabled=d.open;d.port.set_meta("loss_db",2 if d.open else d.closed_db);return true
func use_socket(id:String)->bool:
	if panels.has(id):return switch_door(panels[id])
	for o in model.sockets:
		if o.id==id and o.kind=="valve" and valves.has(o.network):valves[o.network]=not valves[o.network];return true
	return false
func make_zones()->void:
	var seen={}
	for k in model.layout.cells:
		if seen.has(k) or not visible_owner(k):continue
		var queue=[k];seen[k]=true;var area=Area3D.new();area.collision_layer=S.SOUND;area.collision_mask=S.MOVE;add_child(area);var bounds=AABB();var first=true
		while not queue.is_empty():
			var at=queue.pop_back();var c=S.address(at);var p=Vector3(c.x*S.BAY,model.datum(c.z),c.y*S.BAY);var sz=Vector3(S.BAY,model.room_height(at),S.BAY);var cell=AABB(p,sz);bounds=cell if first else bounds.merge(cell);first=false
			var col=CollisionShape3D.new();var box=BoxShape3D.new();box.size=sz;col.shape=box;col.position=p+sz/2;area.add_child(col)
			for dir in [Vector2i.UP,Vector2i.DOWN,Vector2i.LEFT,Vector2i.RIGHT]:
				var nb=S.key(c.x+dir.x,c.y+dir.y,c.z);if not seen.has(nb) and model.layout.cells.has(nb) and S.room_tag(model.layout,nb)==S.room_tag(model.layout,k):seen[nb]=true;queue.append(nb)
		var bus="ArchRoomVerb";if AudioServer.get_bus_index(bus)<0:
			AudioServer.add_bus();var idx=AudioServer.bus_count-1;AudioServer.set_bus_name(idx,bus);AudioServer.add_bus_effect(idx,AudioEffectReverb.new())
		area.reverb_bus_enabled=true;area.reverb_bus_name=bus;area.reverb_bus_amount=.25
		var probe=ReflectionProbe.new();probe.size=bounds.size;probe.position=bounds.get_center();probe.intensity=.22;probe.box_projection=true;add_child(probe)
func audit_sockets()->String:
	var ok=0;var failed=[];var space=get_world_3d().direct_space_state
	for o in model.sockets:
		if o.kind!="panel" or not visible_owner(o.owner):continue
		var point:Vector3=to_global(o.p);var q=PhysicsRayQueryParameters3D.create(point+o.normal*.7,point-o.normal*.12,S.USE|S.SIGHT);q.collide_with_areas=true;var hit=space.intersect_ray(q)
		if hit and hit.collider.get_meta("socket_id","")==o.id:ok+=1
		else:failed.append(o.id)
	return "Eye-height rays (1.60 m): %d visible, %d blocked. %s"%[ok,failed.size(),", ".join(failed)]
func bake_routes()->String:
	var prior=get_node_or_null("WalkRegion");if prior:remove_child(prior);prior.free()
	var region=NavigationRegion3D.new();region.name="WalkRegion";add_child(region);var nav=NavigationMesh.new();nav.agent_radius=.24;nav.agent_height=1.68;nav.agent_max_climb=.24;nav.cell_size=.12;nav.cell_height=.08;nav.geometry_parsed_geometry_type=NavigationMesh.PARSED_GEOMETRY_STATIC_COLLIDERS;nav.geometry_collision_mask=16
	var map=get_world_3d().navigation_map;NavigationServer3D.map_set_cell_size(map,nav.cell_size);NavigationServer3D.map_set_cell_height(map,nav.cell_height);var src=NavigationMeshSourceGeometryData3D.new();NavigationServer3D.parse_source_geometry_data(nav,src,self)
	# Isolate thresholds on the ground mesh: dynamic navigation links alone convey door state.
	for o in model.sockets:
		if o.kind!="door" or not visible_owner(o.owner):continue
		var basis=Basis(Vector3.UP,o.yaw);var poly=PackedVector3Array();for uv in [Vector2(-.5,-.14),Vector2(.5,-.14),Vector2(.5,.14),Vector2(-.5,.14)]:poly.append(o.p+basis*Vector3(uv.x*o.width,0,uv.y))
		src.add_projected_obstruction(poly,o.p.y-.2,1.9,false)
	NavigationServer3D.bake_from_source_geometry_data(nav,src);region.navigation_mesh=nav;return "Navigation baked: %d polygons · door links follow live state."%nav.get_polygon_count()
func sound_loss(from:String,to:String)->float:
	# Shortest attenuation path through room cells and door/vertical ports (dB).
	var costs={from:0.};var pending=[from];var graph={}
	for o in model.sockets:
		if o.kind=="door" and doors.has(o.id):
			var a=o.rooms[0];var b=o.rooms[1];if not graph.has(a):graph[a]=[]
			if not graph.has(b):graph[b]=[]
			var loss=doors[o.id].port.get_meta("loss_db");graph[a].append([b,loss]);graph[b].append([a,loss])
	for k in model.active_cores:
		var c=S.address(k);var b=S.key(c.x,c.y,c.z+1);for pair in [[k,b],[b,k]]:
			if not graph.has(pair[0]):graph[pair[0]]=[]
			graph[pair[0]].append([pair[1],4.])
	while not pending.is_empty():
		var k=pending.pop_front();var edges=graph.get(k,[]).duplicate();var c=S.address(k)
		for d in [Vector2i.UP,Vector2i.DOWN,Vector2i.LEFT,Vector2i.RIGHT]:
			var b=S.key(c.x+d.x,c.y+d.y,c.z);if model.layout.cells.has(b) and S.room_tag(model.layout,k)==S.room_tag(model.layout,b):edges.append([b,.5])
		for edge in edges:
			var loss=float(costs[k])+float(edge[1]);if loss<costs.get(edge[0],INF):costs[edge[0]]=loss;pending.append(edge[0])
	return costs.get(to,INF)
