extends Node3D
## Metric primitives shared by the A/B/C construction recipes. Y is feet elevation.
const COLORS = {"brick":"796a5f","abyss":"090b10","pit":"47484a","test_amber":"e99425","chalk":"c7c3b6","trim":"ded9cb","joint":"b1ad9e","floor":"cdc8bc","iron":"40474a","dark":"232735","brass":"ba914e","amber":"ffc35a","green":"65d39c","door_green":"31604b","glass":"bfdedd","book":"9f998a"}
var materials := {}
var cut: Array[Node3D] = []
var plates: Array[Node3D] = []
var section: Node3D
var stone_mesh := BoxMesh.new()
var root_group: Node3D
func group(label: String) -> void:
	section=Node3D.new(); section.name=label; add_child(section); root_group=section
func mat(k: String) -> StandardMaterial3D:
	if materials.has(k): return materials[k]
	var m:=StandardMaterial3D.new(); m.albedo_color=Color(COLORS[k]); m.roughness=.85
	if k in ["amber","green"]: m.emission_enabled=true; m.emission=m.albedo_color; m.emission_energy_multiplier=.7
	if k=="glass": m.transparency=BaseMaterial3D.TRANSPARENCY_ALPHA; m.albedo_color.a=.19; m.cull_mode=BaseMaterial3D.CULL_DISABLED
	materials[k]=m; return m
func box(id:String,p:Vector3,size:Vector3,k:String="chalk",solid:=true,yaw:=0.0)->Node3D:
	var n:=MeshInstance3D.new(); n.name=id; n.mesh=stone_mesh; n.material_override=mat(k); section.add_child(n); n.position=p; n.rotation.y=yaw; n.scale=size
	if solid:
		var b:=StaticBody3D.new();
		if k=="glass": b.collision_layer=5
		else: b.collision_layer=3
		var c:=CollisionShape3D.new(); c.shape=BoxShape3D.new(); b.add_child(c); n.add_child(b)
	return n
func rect(id:String,x:float,y:float,z:float,w:float,h:float,d:float,k:="chalk",solid:=true)->Node3D:
	return box(id,Vector3(x,y,z),Vector3(w,h,d),k,solid)
func beam(a:Vector3,b:Vector3,r:float,k:String)->Node3D:
	var n:=MeshInstance3D.new();var m:=CylinderMesh.new();m.radial_segments=12;m.rings=0;m.top_radius=r;m.bottom_radius=r;m.height=a.distance_to(b);n.mesh=m;n.material_override=mat(k);section.add_child(n);n.position=(a+b)*.5;n.quaternion=Quaternion(Vector3.UP,(b-a).normalized());return n
## Arch built from continuous extruded annular sectors (rather than stair-stepped blocks).
func arch(origin:Vector3,r:float,t:float,depth:float,axis_x:bool,k:String,start:=0.,end:=PI,spandrel:=false)->Node3D:
	var st:=SurfaceTool.new(); st.begin(Mesh.PRIMITIVE_TRIANGLES);st.set_smooth_group(-1)
	for i in 32:
		var pts:=PackedVector3Array()
		for j in 8:
			var angle:=lerpf(start,end,(i+((j>>2)&1))/32.0); var rad:=r+t*((j>>1)&1);var d:=depth*((j&1)-.5);var u:=cos(angle)*rad;var v:=sin(angle)*rad
			if spandrel and ((j>>1)&1):u=cos(angle)*r;v=t
			pts.append(Vector3(d,v,u) if axis_x else Vector3(u,v,d))
		for face in [[0,4,5,1],[2,3,7,6],[0,2,6,4],[1,5,7,3],[0,1,3,2],[4,6,7,5]]:
			for j in [0,1,2,0,2,3]: st.add_vertex(pts[face[j]])
	st.generate_normals();var n:=MeshInstance3D.new(); n.mesh=st.commit(); var m:=mat(k).duplicate() as StandardMaterial3D; m.cull_mode=BaseMaterial3D.CULL_DISABLED;n.material_override=m;section.add_child(n);n.position=origin;return n
## Wall described by two endpoints along X or Z and optional real openings [from,to,sill,head].
func wall(x_axis:bool,f:float,a:float,b:float,h:float,holes:Array=[],remove:=false,k:="chalk")->void:
	var pos:=a
	for hole in holes+[[b,b,0,h]]:
		var l:float=hole[0];var u:float=hole[1];var sill:float=hole[2];var head:float=hole[3]
		for seg in [[pos,l,0,h],[l,u,0,sill],[l,u,head,h]]:
			var w:float=seg[1]-seg[0];var ht:float=seg[3]-seg[2];if w<.001 or ht<.001:continue
			var mid:float=(seg[1]+seg[0])*.5;var y:float=(seg[3]+seg[2])*.5
			var n:=rect("Wall",mid if x_axis else f,y,f if x_axis else mid,w if x_axis else .2,ht,.2 if x_axis else w,k);if remove:cut.append(n)
		pos=u
func slab(x:float,z:float,w:float,d:float,y:=0.0)->void:rect("Slab",x,y-.12,z,w,.24,d,"floor")
func lid(x:float,z:float,w:float,d:float,y:float)->void:cut.append(rect("Ceiling",x,y+.1,z,w,.2,d))
func plaque(text:String,p:Vector3,width:float,yaw:=0.)->void:
	var facing:=Vector3.BACK.rotated(Vector3.UP,yaw)
	box("LetteredEnamelPlaque",p,Vector3(width,.27,.055),"iron",false,yaw)
	var n:=Label3D.new();n.text=text;n.font_size=38;n.pixel_size=.00285;n.modulate=Color("eddfa9");n.outline_size=0
	n.rotation.y=yaw;n.double_sided=false;section.add_child(n);n.position=p+facing*.031
func label_at(text:String,p:Vector3,yaw:=0.0)->void:
	var n:=Label3D.new();n.text=text;n.font_size=40;n.pixel_size=.004;n.modulate=Color("eddfa9");n.outline_size=5;n.double_sided=true;n.rotation.y=yaw;section.add_child(n);n.position=p
