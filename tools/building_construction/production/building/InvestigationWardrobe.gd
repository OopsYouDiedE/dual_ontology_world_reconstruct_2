extends RefCounted
## A role-specific fitting for the Structure Lab. Coordinates are MPFB bind metres.
const INK=preload("res://scenes/components/rendering/actors/InvestigationPigment.gdshader")
const CONTACT=preload("res://scenes/components/rendering/actors/ShoeContact.gdshader")
static func dye(color:String,part:=0)->ShaderMaterial:
	var m:=ShaderMaterial.new();m.shader=INK;m.set_shader_parameter("pigment",Color(color));m.set_shader_parameter("part",part);return m

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
		elif id.contains("Eyes"):mat=dye("ffffff",4)
		else:continue
		mat.set_shader_parameter("textile",old.get_shader_parameter("base_texture"));n.set_surface_override_material(0,mat)
	var hat=socket(rig,"head");var waist=socket(rig,"spine_01")
	if tech:
		ring(hat,Vector3(0,1.713,.049),.112,.144,.014,.91,"635547");ring(hat,Vector3(0,1.741,.035),.111,.125,.065,.66,"767365")
		ring(waist,Vector3(0,1.005,.045),.175,.163,.055,1.,"70503c");var pouch=BoxMesh.new();pouch.size=Vector3(.105,.15,.06);piece(waist,pouch,Vector3(-.118,.954,.157),"885d3e")
	else:
		ring(hat,Vector3(0,1.713,.041),.145,.162,.014,.98,"78664f");ring(hat,Vector3(0,1.765,.042),.101,.120,.102,.81,"a18a68");ring(hat,Vector3(0,1.733,.042),.102,.122,.026,.97,"514942")
		var skirt=ring(waist,Vector3(0,.912,.045),.232,.194,.40,.76,"ad9778");skirt.material_override.set_shader_parameter("part",6)
		for y in [.85,.97,1.075]:
			var button:=SphereMesh.new();button.radius=.013;button.height=.026;piece(waist,button,Vector3(.026,y,.045+.194*lerpf(1.,.76,(y-.712)/.40)),"625749")
		var collar=socket(rig,"spine_03");ring(collar,Vector3(0,1.477,.065),.098,.099,.059,.93,"874f42")
	for bone in ["foot_l","foot_r"]:
		var sh:=MeshInstance3D.new();var plane:=PlaneMesh.new();plane.size=Vector2(.29,.43);sh.mesh=plane;sh.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF;var sm:=ShaderMaterial.new();sm.shader=CONTACT;sh.material_override=sm;person.add_child(sh);sh.set_script(preload("res://tools/building_construction/production/building/ShoeContact.gd"));sh.bind(rig,bone)

static func socket(rig:Skeleton3D,bone:String)->Node3D:
	var a:=BoneAttachment3D.new();rig.add_child(a);a.bone_name=bone;var rest:=Node3D.new();a.add_child(rest);rest.transform=rig.get_bone_global_rest(rig.find_bone(bone)).affine_inverse();return rest
static func ring(parent:Node3D,pos:Vector3,rx:float,rz:float,h:float,top:float,color:String)->MeshInstance3D:
	var m:=CylinderMesh.new();m.radial_segments=24;m.rings=1;m.bottom_radius=rx;m.top_radius=rx*top;m.height=h;var n=piece(parent,m,pos,color);n.scale.z=rz/rx;return n
static func piece(parent:Node3D,mesh:Mesh,pos:Vector3,color:String)->MeshInstance3D:
	var n:=MeshInstance3D.new();parent.add_child(n);n.mesh=mesh;n.position=pos;n.material_override=dye(color);return n
