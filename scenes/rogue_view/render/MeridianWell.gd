extends RefCounted
## Fit a recessed, glazed mechanism into a contiguous, unfurnished part of a native lot.
const Watch = preload("res://scenes/blue_prince_lab/studies/Meridian.gd")
static func plan(lot: Dictionary) -> Rect2i:
	var allowed := {}
	var center := Vector2.ZERO
	for c: Vector2i in lot.floors:
		if lot.patterns.get(c,0)!=65535:
			allowed[c]=true
			center+=Vector2(c)
	center/=maxi(1,allowed.size())
	for o: Dictionary in lot.objects:
		if not o.get("annotation_only",false): allowed.erase(Vector2i(Vector2(o.position).floor()))
	var pick := Rect2i()
	for width: int in [6,5,4,3,2]:
		var best := INF
		for p: Vector2i in allowed:
			var dist := (Vector2(p)+Vector2.ONE*(width-1)*.5).distance_squared_to(center)
			if dist>=best: continue
			var fits := true
			for i in width:
				for j in width:
					if not allowed.has(p+Vector2i(i,j)): fits=false; break
				if not fits: break
			if not fits: continue
			var inset := Rect2(Vector2(p)+Vector2.ONE*.02,Vector2.ONE*(width-.04))
			for e: Vector4i in lot.segments:
				if inset.has_point(Vector2(e.x+e.z,e.y+e.w)*.5): fits=false; break
			if fits:
				pick=Rect2i(p,Vector2i.ONE*width)
				best=dist
		if pick.has_area(): break
	return pick

static func install(parent: Node3D, area: Rect2i, flush_display := false) -> void:
	var root := Node3D.new()
	root.name="FloorMeridian"
	parent.add_child(root)
	var width := float(area.size.x)
	root.position=Vector3(area.position.x+width*.5,0,area.position.y+width*.5)
	var watch := Watch.new()
	var s := width*.30
	watch.scale=Vector3.ONE*s
	watch.position.y=-.89*s
	if flush_display:
		var tray := Node3D.new()
		tray.name = "TourbillonTray"
		tray.scale.y = 0.26
		root.add_child(tray)
		tray.add_child(watch)
		watch.rotation_degrees.x = -90.0
	else:
		root.add_child(watch)
	var bronze:=StandardMaterial3D.new()
	bronze.albedo_color=Color("807159")
	var well:=StandardMaterial3D.new()
	well.albedo_color=Color("283037")
	var glass:=ShaderMaterial.new()
	glass.shader=preload("res://scenes/blue_prince_lab/reference/Sapphire.gdshader")
	_box(root,Vector3(0,-1.83*s,0),Vector3(width,.10,width),well)
	for side: float in [-1.,1.]:
		for lateral in [false,true]:
			var rail:=Vector3(side*width*.49,0,0) if lateral else Vector3(0,0,side*width*.49)
			var dims:=Vector3(width*.025,.024,width) if lateral else Vector3(width,.024,width*.025)
			_box(root,rail,dims,bronze)
			dims.y=1.84*s
			_box(root,rail+Vector3.DOWN*dims.y*.5,dims,well)
	_box(root,Vector3(0,-.01,0),Vector3(width,.008,width),glass)
	if flush_display:
		# Four stone spandrels trim the square tile opening to a brass-edged octagon.
		var stone := StandardMaterial3D.new()
		stone.albedo_color = Color("576572")
		for corner in 4:
			var quadrant := Node3D.new()
			quadrant.rotation.y = corner * PI / 2
			root.add_child(quadrant)
			var r := width * 0.5
			var cut := width * 0.27
			var st := SurfaceTool.new()
			st.begin(Mesh.PRIMITIVE_TRIANGLES)
			for pt in [Vector3(r,0.018,r), Vector3(r-cut,0.018,r), Vector3(r,0.018,r-cut)]:
				st.set_normal(Vector3.UP)
				st.add_vertex(pt)
			var face := MeshInstance3D.new()
			face.mesh = st.commit()
			face.material_override = stone
			quadrant.add_child(face)
			var edging := Node3D.new()
			edging.position = Vector3(r-cut/2,0.024,r-cut/2)
			edging.rotation.y = PI/4
			quadrant.add_child(edging)
			_box(edging,Vector3.ZERO,Vector3(cut*sqrt(2.0),0.03,0.065),bronze)
	var lamp:=OmniLight3D.new()
	lamp.position=Vector3(0,-.12*s,s*.55)
	lamp.light_color=Color("fff1cd")
	lamp.omni_range=width*.85
	lamp.light_energy=1.3
	root.add_child(lamp)

static func _box(root: Node3D,p: Vector3,sz: Vector3,mat: Material) -> void:
	var mesh := BoxMesh.new()
	mesh.size=sz
	var inst:=MeshInstance3D.new()
	inst.mesh=mesh
	inst.material_override=mat
	inst.position=p
	inst.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(inst)
