extends "Masonry.gd"
const CX:=61.0
const CZ:=10.1
var gate:Node3D
var leaf:Node3D
var bridge:Node3D
var panel:Node3D
var core:Node3D
var supplies:Node3D
var stair_path:=PackedVector3Array()
func build()->void:
	arcade();arcade_details();archive();archive_details();shaft();shaft_details()
func arcade()->void:
	group("A1_ImmersionArcade");slab(18,0,36,4.4);lid(18,0,36,4.4,5.2)
	var lights:=[]
	for i in 6:lights.append([i*6+1,i*6+5,3.6,4.85])
	wall(true,-2.2,0,36,5.2,lights);wall(true,2.2,0,36,5.2,[[30.1,31.9,0,2.6]],true)
	for i in 6:
		var x:=3.+6*i;arch(Vector3(x,1.72,-1.97),1.67,.19,.27,false,"trim")
		for dx in [-1.77,1.77]:rect("NicheJamb",x+dx,.86,-1.98,.2,1.72,.26,"trim")
		for dx in [-1,0,1]:rect("ClerestoryMullion",x+dx,4.22,-2.2,.055,1.25,.1,"joint",false)
	for i in 7:
		var x:=i*6.;var end_wall:=i==0 or i==6
		for layer in [[1.79,.29,.60,"chalk"],[1.76,.08,.66,"trim"]]:
			var spring:=Vector3(x,3.1,0)
			if end_wall:arch(spring,layer[0],layer[1],layer[2],true,layer[3])
			else:
				arch(spring,layer[0],layer[1],layer[2],true,layer[3],2.13,PI)
				cut.append(arch(spring,layer[0],layer[1],layer[2],true,layer[3],0.,2.13))
		if end_wall:arch(Vector3(x,3.1,0),1.81,2.1,.45,true,"chalk",0.,PI,true)
		for z in [-1.98,1.98]:
			var parts:=[rect("Pier",x,1.55,z,.6,3.1,.38),rect("Plinth",x,.13,z,.71,.26,.46,"joint"),rect("Capital",x,3.03,z,.72,.16,.52,"trim")]
			if z>0 and not end_wall:cut.append_array(parts)
	gate=Node3D.new();section.add_child(gate);section=gate
	for i in 21:
		var z:float=(i-10)*.174;var h:=3.1+sqrt(1.76*1.76-z*z);rect("Picket",36,h*.5,z,.085,h,.036,"iron",false)
	for y in [.18,1.25,2.68,3.12]:rect("Strap",36,y,0,.10,.075,2.8,"iron",false)
	invisible_block(Vector3(36,1.6,0),Vector3(.15,3.2,2.8));section=root_group
	for x in range(1,36,2):rect("PavingJoint",x,.002,0,.013,.004,4.16,"joint",false)
func invisible_block(p:Vector3,s:Vector3)->void:
	var n:=rect("Barrier",p.x,p.y,p.z,s.x,s.y,s.z,"iron");n.hide()
func archive()->void:
	group("B1_B5_Archive");slab(31,4.85,6,5.3);slab(23.85,5.55,8.3,6.7);slab(23.9,12,7.7,6.2,-.6);slab(34.75,14.1,14,2);slab(38.5,10.1,6.5,5.8)
	wall(false,27.9,2.3,8.9,3.8,[[4.1,5.7,0,2.4]]);wall(false,34.1,2.3,7.5,3.8);wall(true,7.5,28,34,3.8);wall(false,19.7,2.3,8.9,3.8,[[3.2,4.4,1,3.2],[6,7.2,1,3.2]]);wall(true,2.2,19.7,28,3.8,[],true)
	wall(true,8.95,19.8,27.9,4,[[20.15,21.75,0,2.4],[22.25,27.05,1,2.5]])
	rect("ObservationGlass",24.65,1.75,8.95,4.8,1.5,.055,"glass");for x in [22.25,23.85,25.45,27.05]:rect("Mullion",x,1.75,8.95,.045,1.5,.09,"iron",false)
	wall(false,20,9.05,15.05,4);wall(true,15.15,20,27.75,4,[],true);wall(false,27.8,9.05,15.05,4,[[13.3,14.9,0,2.4]])
	# Narrow rim at grade around a genuine sunken test pit, with a walkable ramp.
	slab(23.9,9.7,7.7,1.5);slab(23.9,14.3,7.7,1.6);slab(20.8,12,1.6,3.2);slab(27,12,1.6,3.2);slab(23.85,12,3.2,1.8)
	slab(23.85,10.73,1.15,.80);slab(23.85,13.2,1.15,1.10);rect("AmberTestPlate",23.85,.012,12,3.2,.024,1.8,"amber");var ramp:=rect("PitRamp",21.95,-.32,12,1.6,.12,1.1,"floor");ramp.rotation.z=-.40
	wall(true,13,27.8,41.8,2.4,[[38.1,39.7,0,2.4]],false,"dark");wall(true,15.2,27.8,41.8,2.4,[],true,"dark");wall(false,41.85,13,15.2,2.4,[],false,"dark");lid(34.75,14.1,14,2,2.4)
	wall(true,7.2,35.25,41.75,3.8,[[37.9,39.5,0,2.4]]);wall(false,35.15,7.2,13,3.8);wall(false,41.85,7.2,13,3.8,[[8.9,11.3,0,2.8]])
	for v in [[31,4.85,6,5],[23.85,5.6,8,6.5],[23.9,12,7.5,6],[38.5,10.1,6.5,5.5]]:lid(v[0],v[1],v[2],v[3],4 if v[0]==23.9 else 3.8)
	for z in [4.0,6.9]:shelf(23.65,z)
	# Rubble in the blind opening beyond B1, visible across a broken barricade.
	for i in 17:
		var n:=rect("FallenStone",28.6+fmod(i*1.73,4.7),.18+(.22 if i%3==0 else 0.),7.15-fmod(i*.37,.85),.52,.35,.44,"joint");n.rotation.y=i*.81
	label_at("←  ARCHIVE",Vector3(31,2.3,7.35),PI)
	panel=rect("BrassIsolator",36.3,1.08,7.45,.77,.95,.23,"brass");beam(Vector3(36.3,.96,7.62),Vector3(36.3,1.49,7.94),.065,"iron")
	for pair in [[Vector3(36.3,1.45,7.52),Vector3(36.3,3.2,7.52)],[Vector3(36.3,3.2,7.52),Vector3(36.3,3.2,0)]]:beam(pair[0],pair[1],.075,"brass")
	supplies=Node3D.new();section.add_child(supplies);section=supplies;rect("OilTin",34,.26,14.85,.3,.52,.30,"brass");rect("ClockworkMetronome",34.45,.2,14.85,.22,.4,.23,"book");section=root_group;label_at("B5  /  MASTER RELEASE",Vector3(36.8,2.35,7.34))
	slab(38.7,3.1,4.9,8.3);wall(false,41.25,-2,7.2,3.6);wall(true,-2.05,36,41.25,3.6,[],true);wall(true,7.2,36,37.9,2.4);slab(44,10.1,4.6,2.6);wall(true,8.7,41.85,46.1,3.2);wall(true,11.5,41.85,46.1,3.2,[],true)
func shelf(x:float,z:float)->void:
	var bookcase:=preload("res://tools/building_construction/BuildingConstruction/Cabinets/RecipeBookshelf.gd").new()
	bookcase.recipe_parameters.merge({"width":3.2,"height":1.0,"depth":.48,"shelves":2,"bays":2},true)
	section.add_child(bookcase);bookcase.position=Vector3(x,0,z)
	for item in bookcase.find_children("*","MeshInstance3D",true,false):item.material_override=mat("book")
func polar(rad:float,a:float,y:float)->Vector3:return Vector3(CX+rad*cos(a),y,CZ+rad*sin(a))
func band(id:String,r0:float,r1:float,y0:float,y1:float,a:float,b:float,k:String,solid:=true)->Node3D:
	var st:=SurfaceTool.new();st.begin(Mesh.PRIMITIVE_TRIANGLES);st.set_smooth_group(-1);var v:=PackedVector3Array()
	for ang in [a,b]:
		for y in [y0,y1]:
			for r in [r0,r1]:v.append(polar(r,ang,y))
	for face in [[0,4,6,2],[1,3,7,5],[0,1,5,4],[2,6,7,3],[0,2,3,1],[4,5,7,6]]:
		for j in [2,1,0,3,2,0]:st.add_vertex(v[face[j]])
	st.generate_normals();var n:=MeshInstance3D.new();n.name=id;n.mesh=st.commit();n.material_override=mat(k);section.add_child(n)
	if solid:
		var body:=StaticBody3D.new();body.collision_layer=5 if k=="glass" else 3;var col:=CollisionShape3D.new();var shape:=ConvexPolygonShape3D.new();shape.points=v;col.shape=shape;body.add_child(col);n.add_child(body)
	return n
func shaft()->void:
	group("C1_C4_SourceCaisson");platform(-1,2.5);platform(1,3.);slab(CX-14.45,CZ,1.2,2.65);bridge=rect("SingleGazeSpan",CX,-.11,CZ,18,.22,3.6,"amber")
	for side in [-1,1]:
		rect("BridgeAbutment",CX+side*10.0,-5,CZ+.8,1.9,10,2.8,"joint")
	var roof:=MeshInstance3D.new();var cap:=CylinderMesh.new();cap.top_radius=14.45;cap.bottom_radius=14.45;cap.height=.32;cap.radial_segments=56;roof.mesh=cap;roof.material_override=mat("chalk");section.add_child(roof);roof.position=Vector3(CX,10.16,CZ);cut.append(roof)
	var bottom:=MeshInstance3D.new();var disc:=CylinderMesh.new();disc.top_radius=14;disc.bottom_radius=14;disc.height=.2;bottom.mesh=disc;bottom.material_override=mat("dark");section.add_child(bottom);bottom.position=Vector3(CX,-10.1,CZ)
	for i in 56:
		var a:=TAU*i/56.;var b:=TAU*(i+1)/56.;var mid:=(a+b)*.5;var entrance:=absf(mid-PI)<.115;var reveal:=cos(mid-1.03)>.52
		var lower:=band("LowerCaisson",14,14.45,-10,0,a,b,"joint");if reveal:cut.append(lower)
		if not entrance:
			var upper:=band("UpperCaisson",14,14.45,0,10,a,b,"chalk");if reveal:cut.append(upper)
		if sin(mid)<-.24:
			band("LowerServiceGallery",12.1,13.99,-.25,0,a,b,"joint")
			band("ServiceHandrail",12.12,12.18,.83,.9,a,b,"iron",false)
			beam(polar(12.15,a,0),polar(12.15,a,.84),.025,"iron")
			if i%6==0:box("GallerySupport",polar(13.4,mid,2.32),Vector3(1.1,4.65,.72),"joint",true,-mid)
		if entrance:band("PortalHead",14,14.45,2.8,10,a,b,"chalk")
		var corn:=band("Coping",13.85,14.54,9.68,10,a,b,"trim",false);if reveal:cut.append(corn)
		if i%4==1:
			var rib:=box("BrickPilaster",polar(13.87,mid,0),Vector3(.34,20,.48),"joint",false,-mid);if reveal:cut.append(rib)
		if sin(mid)>0:
			var service:=band("ServiceWalk",11.95,13.95,-.22,0,a,b,"joint");cut.append(service)
		var stair_gap:=absf(sin(mid))<.35
		if stair_gap:continue
		var floor_ring:=band("ObservationRing",11.55,13.95,4.54,4.8,a,b,"floor");if reveal:cut.append(floor_ring)
		for tier in [[4.8,5.8,"chalk"],[5.8,6.94,"glass"],[6.94,7.02,"trim"]]:
			var rail:=band("GalleryScreen",11.55,11.63,tier[0],tier[1],a,b,tier[2]);if reveal:cut.append(rail)
		var post:=box("GlazingBar",polar(11.6,a,6.38),Vector3(.07,1.16,.07),"joint",false);if reveal:cut.append(post)
	for deg in [218,322,90]:
		var pier:=box("SightBreak",polar(11.95,deg_to_rad(deg),6.3),Vector3(1.2,3,1.6),"joint",true,-deg_to_rad(deg))
		if deg==90:cut.append(pier)
	for side in [-1,1]:
		var origin:=Vector3(CX+side*12.35,0,CZ-2.0);beam(origin+Vector3.DOWN*.2,origin+Vector3.UP*5.6,.10,"iron")
		if side==-1:beam(origin+Vector3.DOWN*10,origin,.10,"iron")
		for i in range(-85 if side==-1 else 0,42):
			var a:=PI*.5+TAU*i/41.;var p:=origin+Vector3(1.02*cos(a),4.8*i/41.,1.02*sin(a));box("HelicalTread",p-Vector3.UP*.09,Vector3(1.84,.18,.37),"trim",false,-a)
			for strip in 5:stair_wedge(origin,i,.13+strip*.356,.486+strip*.356)
			if side==-1 and i>=0:stair_path.append(p)
			if i%3==0:beam(p+Vector3(.87*cos(a),0,.87*sin(a)),p+Vector3(.87*cos(a),.85,.87*sin(a)),.027,"iron")
	# Upper landing connects the last spiral tread to the gallery. Shortcut opens from the core side.
	leaf=rect("EmeraldReturnLeaf",CX+13.54,6.1,CZ+2.35,.16,2.6,1.8,"green");core=rect("SourceCore",CX+10.8,1,CZ,.42,.68,.42,"amber");rect("CorePlinth",CX+10.8,.31,CZ,.85,.62,.85,"joint")
	label_at("01   /   SOURCE CAISSON",Vector3(46.1,2.9,CZ),-PI/2)

func arcade_details()->void:
	# In a section drawing the far spring stays, while the cut side keeps a low plinth.
	for x in [0.,36.]:
		for z in [-1.96,1.96]:rect("PortalReturn",x,2.5,z,.38,5,.35)
		rect("LintelCornice",x,5.06,0,.48,.3,4.42,"trim")
	for t in [[0,30.1],[31.9,36.]]:
		var n:=rect("CutSill",(t[0]+t[1])*.5,.24,2.2,t[1]-t[0],.48,.2,"chalk",false);plates.append(n);n.hide()
	for end in [0.,36.]:
		for j in 3:
			var stair:=rect("SectionStepping",end,.24*(3-j),2.44+j*.32,.48,.48*(3-j),.33,"chalk",false);plates.append(stair);stair.hide()
	for x in [29.98,32.02]:rect("SidePortal",x,1.38,2.18,.22,2.76,.34,"trim",false)
	rect("PortalHead",31,2.74,2.18,2.27,.28,.34,"trim",false)
func archive_details()->void:
	# The A/B party wall belongs to A. Only duplicate its sliced silhouette in a B plate.
	for interval in [[28.,30.1],[31.9,34.1]]:
		var edge:=rect("SectionReturn",(interval[0]+interval[1])*.5,.6,2.2,interval[1]-interval[0],1.2,.24,"chalk",false);plates.append(edge);edge.hide()
	for x in [30.02,31.98]:rect("ArchiveEntryJamb",x,1.27,2.34,.18,2.54,.24,"trim",false)
	rect("ArchiveEntryHead",31,2.6,2.34,2.13,.16,.24,"trim",false)
	for x in [30.,32.,34.]:
		beam(Vector3(x,.12,14.94),Vector3(x,1.99,14.94),.09,"iron")
	for z in [3.5,5.4,7.4]:rect("LibraryDado",19.84,.49,z,.10,.09,1.8,"trim",false)
	for data in [[27.9,4.9,PI/2],[20.95,8.95,0.],[27.8,14.1,PI/2],[38.9,13.,0.],[38.7,7.2,0.]]:
		var center:=Vector3(data[0],0,data[1]);var yaw:float=data[2];var along:=Vector3(cos(yaw),0,sin(yaw))
		for sign_ in [-1,1]:box("DoorCasing",center+along*sign_*.88+Vector3.UP*1.24,Vector3(.16,2.48,.31),"trim",false,-yaw)
		box("DoorLintel",center+Vector3.UP*2.49,Vector3(1.94,.18,.31),"trim",false,-yaw)
	for x in [35.65,36.32,37.0]:
		beam(Vector3(x,1.92,7.39),Vector3(x,1.92,7.51),.19,"brass");beam(Vector3(x,1.92,7.515),Vector3(x,1.92,7.53),.15,"trim");beam(Vector3(x,1.92,7.55),Vector3(x+.08,2.01,7.55),.012,"iron")
	for x in [37.,34.8]:beam(Vector3(x,.12,14.94),Vector3(x,2.2,14.94),.09,"iron")
	for z in [3.2,4.4,6.,7.2]:rect("WindowCasing",19.74,2.1,z,.31,2.32,.095,"trim",false)
	for z in [3.8,6.6]:
		for y in [1.,2.,3.2]:rect("ArchiveSash",19.74,y,z,.22,.07,1.26,"trim",false)
	rect("FieldNote",23.6,1.018,4.,.29,.015,.2,"trim",false)
func shaft_details()->void:
	for i in 56:
		var a:=TAU*i/56.;var b:=TAU*(i+1)/56.;band("FoundationRing",13.9,14.52,-10.1,-9.18,a,b,"joint",false)
		if sin((a+b)*.5)<0:
			band("GalleryFascia",11.49,11.68,4.46,4.60,a,b,"trim",false)
			if absf(sin((a+b)*.5))>.35:band("SillCap",11.49,11.68,5.75,5.83,a,b,"trim",false)
	# Tangential landings, beyond the final riser, bridge the stair opening to the gallery.
	for side in [-1,1]:
		slab(CX+side*12.35,CZ+1.94,2.,5.16,4.8)
	for z in [CZ-1.84,CZ+1.84]:
		beam(Vector3(CX-9,.45,z),Vector3(CX+9,.45,z),.030,"brass")
		for i in 10:beam(Vector3(CX-9+i*2,0,z),Vector3(CX-9+i*2,.45,z),.029,"iron")

# Continuous walk surface follows the nosings. A capsule need not step over box corners.
func stair_wedge(origin:Vector3,index:int,inner:float,outer:float)->void:
	var pts:=PackedVector3Array()
	for j in [index,index+1]:
		var angle:float=PI*.5+TAU*j/41.
		for radius in [inner,outer]:
			for h in [-.16,.015]:pts.append(Vector3(radius*cos(angle),4.8*j/41.+h,radius*sin(angle)))
	var shape:=ConvexPolygonShape3D.new();shape.points=pts
	var col:=CollisionShape3D.new();col.shape=shape
	var body:=StaticBody3D.new();body.position=origin;body.add_child(col);section.add_child(body)

# Clip each rectangular landing against the inner shaft radius, leaving the portal throat separate.
func platform(side:int,half_width:float)->void:
	var outline:=PackedVector2Array([Vector2(CX+side*9,CZ-half_width)])
	for j in 13:
		var z:=lerpf(-half_width,half_width,j/12.)
		outline.append(Vector2(CX+side*sqrt(14.*14.-z*z),CZ+z))
	outline.append(Vector2(CX+side*9,CZ+half_width))
	var mesh:=CSGPolygon3D.new();mesh.name="ClippedLanding";mesh.polygon=outline;mesh.depth=.24;mesh.rotation.x=PI/2;mesh.position.y=-.24;mesh.material=mat("floor");mesh.use_collision=true;section.add_child(mesh)
