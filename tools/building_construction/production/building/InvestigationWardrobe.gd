extends RefCounted
## A role-specific fitting for the Structure Lab. Coordinates are MPFB bind metres.
const INK=preload("res://scenes/components/rendering/actors/InvestigationPigment.gdshader")
const CONTACT=preload("res://scenes/components/rendering/actors/ShoeContact.gdshader")
static func dye(color:String,part:=0)->ShaderMaterial:
	var m:=ShaderMaterial.new();m.shader=INK;m.set_shader_parameter("pigment",Color(color));m.set_shader_parameter("part",part)
	if part in [0,1,2,5,6]:
		var edge:=ShaderMaterial.new();edge.shader=preload("res://scenes/components/rendering/actors/InvestigationEdge.gdshader");m.next_pass=edge
	return m

static func dress(person:Node3D,tech:bool)->void:
	var rig:Skeleton3D=person.get_meta("skeleton")
	for n:MeshInstance3D in person.find_children("*","MeshInstance3D",true,false):
		var old=n.get_surface_override_material(0) as ShaderMaterial
		if not old:continue
		var mat:ShaderMaterial
		var id=String(n.name)
		if id.contains("Outfit"):
			var arr=n.mesh.surface_get_arrays(0);var verts:PackedVector3Array=arr[Mesh.ARRAY_VERTEX];var mask:=PackedColorArray();mask.resize(verts.size())
			for i in verts.size():
				var v=verts[i];var w=smoothstep(.90,.97,v.y)
				if tech:w*=1.-smoothstep(.14,.21,absf(v.x))
				mask[i]=Color(w,smoothstep(.91,.97,v.y),w,1)
			arr[Mesh.ARRAY_COLOR]=mask;var copy:=ArrayMesh.new();copy.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arr,[],{},n.mesh.surface_get_format(0)&Mesh.ARRAY_FLAG_USE_8_BONE_WEIGHTS);n.mesh=copy
			mat=dye("52716f" if tech else "b39c78",2 if tech else 1);mat.set_shader_parameter("secondary",Color("b7ad95" if tech else "64606a"))
		elif id.contains("Hair"):mat=dye("514335" if tech else "604939",5);n.visible=not id.contains("Locks")
		elif id.contains("HeadBody"):
			mat=dye("ffffff",3);mat.set_shader_parameter("pigment",old.get_shader_parameter("base_color"))
		elif id.contains("Eyes"):mat=dye("ffffff",4)
		else:continue
		mat.set_shader_parameter("textile",old.get_shader_parameter("base_texture"));n.set_surface_override_material(0,mat)
	var hat=socket(rig,"head");var waist=socket(rig,"spine_01")
	for side in [-1.,1.]:
		var lock:=SphereMesh.new();lock.radius=1.;lock.height=2.;var strand=piece(hat,lock,Vector3(side*.078,1.664,.051),"544537" if tech else "61483a");strand.scale=Vector3(.019,.057,.036)
	var nape:=SphereMesh.new();nape.radius=1.;nape.height=2.;piece(hat,nape,Vector3(0,1.663,-.024),"514234").scale=Vector3(.085,.068,.061)
	if tech:
		ring(hat,Vector3(0,1.713,.049),.112,.144,.014,.91,"635547");ring(hat,Vector3(0,1.741,.035),.111,.125,.065,.66,"767365")
		ring(waist,Vector3(0,1.005,.045),.175,.163,.055,1.,"70503c");var pouch=BoxMesh.new();pouch.size=Vector3(.105,.15,.06);piece(waist,pouch,Vector3(-.118,.954,.157),"885d3e")
	else:
		ring(hat,Vector3(0,1.713,.041),.145,.162,.014,.98,"78664f");ring(hat,Vector3(0,1.765,.042),.101,.120,.102,.81,"a18a68");ring(hat,Vector3(0,1.733,.042),.102,.122,.026,.97,"514942")
		coat(rig,person.find_child("Wardrobe_Outfit",true,false))
		var collar=socket(rig,"spine_03");ring(collar,Vector3(0,1.477,.065),.098,.099,.059,.93,"874f42")
	for bone in ["foot_l","foot_r"]:
		var sh:=MeshInstance3D.new();var plane:=PlaneMesh.new();plane.size=Vector2(.29,.43);sh.mesh=plane;sh.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF;var sm:=ShaderMaterial.new();sm.shader=CONTACT;sh.material_override=sm;person.add_child(sh);sh.set_script(preload("res://tools/building_construction/production/building/ShoeContact.gd"));sh.bind(rig,bone)

static func socket(rig:Skeleton3D,bone:String)->Node3D:
	var a:=BoneAttachment3D.new();rig.add_child(a);a.bone_name=bone;var rest:=Node3D.new();a.add_child(rest);rest.transform=rig.get_bone_global_rest(rig.find_bone(bone)).affine_inverse();return rest
static func ring(parent:Node3D,pos:Vector3,rx:float,rz:float,h:float,top:float,color:String)->MeshInstance3D:
	var m:=CylinderMesh.new();m.radial_segments=24;m.rings=1;m.bottom_radius=rx;m.top_radius=rx*top;m.height=h;var n=piece(parent,m,pos,color);n.scale.z=rz/rx;return n
static func piece(parent:Node3D,mesh:Mesh,pos:Vector3,color:String)->MeshInstance3D:
	var n:=MeshInstance3D.new();parent.add_child(n);n.mesh=mesh;n.position=pos;n.material_override=dye(color);return n

## Skin the hem in the same bind space as the trousers. Side vertices follow their own thigh.
static func coat(rig:Skeleton3D,outfit:MeshInstance3D)->void:
	var st:=SurfaceTool.new();st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var binding={};var skin=outfit.skin
	for i in skin.get_bind_count():
		var id=skin.get_bind_bone(i);var name=skin.get_bind_name(i) if id<0 else rig.get_bone_name(id);binding[String(name)]=i
	for row in 5:
		for j in 40:
			for corner in [[0,0],[0,1],[1,1],[0,0],[1,1],[1,0]]:
				var u=(j+corner[0])/40.;var v=(row+corner[1])/5.;var a=u*TAU;var x=sin(a);var z=cos(a);var legs=.92*(1.-smoothstep(.08,.8,v));var side=smoothstep(-.4,.4,x);var spine=.68*smoothstep(.48,1.,v)
				st.set_bones(PackedInt32Array([binding.pelvis,binding.thigh_l,binding.thigh_r,binding.spine_01]));st.set_weights(PackedFloat32Array([1.-legs-spine,legs*side,legs*(1.-side),spine]));st.set_uv(Vector2(u,v));st.set_normal(Vector3(x,.14,z).normalized());st.add_vertex(Vector3(x*lerpf(.254,.19,v),lerpf(.73,1.115,v),.035+z*lerpf(.209,.168,v)))
	var n:=MeshInstance3D.new();outfit.get_parent().add_child(n);n.transform=outfit.transform;n.mesh=st.commit();n.skin=skin;n.skeleton=n.get_path_to(rig);n.material_override=dye("ab967a",6)
