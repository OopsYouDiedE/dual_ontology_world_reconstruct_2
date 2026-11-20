extends Node3D
## The Vesper Index: an inspection camera until the player commits to crossing the well.
signal recovered
signal return_requested

const Rules := preload("VesperRules.gd")
const Finish := preload("Exposure.gdshader")
const Shell := preload("VesperShell.gd")
const LAYER := 4
const GOLD := "b78e55"
const BRONZE := "70563e"
const IRON := "34404c"
const VELLUM := "e6d3a0"
const EYE := Vector3(0,2.28,5.9)
const FOCUS := Vector3(0,1.86,-3.8)
const BOOK := Vector3(-1.00,1.01,2.28)
const ANCHORS := {&"leaf": BOOK, &"lamp": Rules.SOURCE, &"wind": Rules.WHEEL, &"cross": Vector3(0,1.8,-9)}
const NAMES := {&"leaf":"Turn folio", &"lamp":"Train lens", &"wind":"Wind ratchet", &"cross":"Cross to archive"}
var rules := Rules.new()
var finishes: Array[ShaderMaterial] = []
var materials := {}
var camera: Camera3D
var door: Node3D
var plate := CollisionShape3D.new()
var yoke := Node3D.new()
var wheel := Node3D.new()
var weight := Node3D.new()
var bolt := Node3D.new()
var turning_leaf := Node3D.new()
var beam := SpotLight3D.new()
var hud := CanvasLayer.new()
var caption := Label.new()
var dial := Label.new()
var keys := HBoxContainer.new()
var story := "A page in the night register survived the fire. Recover it across the well."
var travel: Tween
var sweep: Tween
var standalone := false

func _ready() -> void:
	var shell := Shell.new()
	add_child(shell)
	for n in shell.get_children():
		if n is MeshInstance3D:
			n.layers = LAYER
			var mat: ShaderMaterial = n.material_override
			mat.set_shader_parameter("two_editions",true)
			finishes.append(mat)
	_build_crossing()
	_build_winding_post()
	_build_desk()
	_build_register()
	for side: float in [-1.,1.]:
		var p:=Vector3(side*2.84,3.75,-4.6)
		_disc(self,p+Vector3.UP*1.1,.018,.018,2.1,_mat(BRONZE))
		_disc(self,p+Vector3.UP*.10,.25,.09,.15,_mat(BRONZE))
		_disc(self,p-Vector3.UP*.095,.105,.19,.23,_mat("ffdb92",-1,1.4))
		_disc(self,p-Vector3.UP*.23,.038,.12,.07,_mat(GOLD))
		_interior_light(p-Vector3.UP*.32,"ffcf92",.82,5.)
	_interior_light(Vector3(0,3.3,-14.),"b4c3d2",1.05,10.)
	_interior_light(Vector3(-1.8,4.4,2.4),"d9e6ff",1.1,11)
	_interior_light(Vector3(2.1,4,-5.9),"c8daee",.91,10)
	_interior_light(Vector3(-2,2,-.6),"ffc888",.52,5)
	_interior_light(Vector3(0,.8,-10.5),"e4b67f",1.1,5)
	_make_folio_strip()

func begin(cam: Camera3D) -> void:
	camera=cam
	camera.fov=62
	camera.global_position=to_global(EYE)
	camera.look_at(to_global(FOCUS))
	_refresh()

func _mat(color: String, edition := -1, glow := 0.) -> ShaderMaterial:
	var key := "%s/%d/%s" % [color,edition,glow]
	if not materials.has(key):
		var m := ShaderMaterial.new()
		m.shader=Finish
		m.set_shader_parameter("edition",edition)
		m.set_shader_parameter("pigment",Color(color))
		m.set_shader_parameter("glow",glow)
		materials[key]=m
		finishes.append(m)
	return materials[key]

func _part(parent: Node3D, mesh: Mesh, p: Vector3, m: Material) -> MeshInstance3D:
	var n := MeshInstance3D.new()
	n.mesh=mesh
	n.material_override=m
	n.layers=LAYER
	n.position=p
	parent.add_child(n)
	return n

func _box(parent: Node3D, p: Vector3, size: Vector3, m: Material) -> MeshInstance3D:
	var mesh := BoxMesh.new()
	mesh.size=size
	return _part(parent,mesh,p,m)

func _disc(parent: Node3D, p: Vector3, base: float, top: float, h: float, m: Material) -> MeshInstance3D:
	var mesh := CylinderMesh.new()
	mesh.radial_segments=20
	mesh.rings=0
	mesh.bottom_radius=base
	mesh.top_radius=top
	mesh.height=h
	return _part(parent,mesh,p,m)

func _ring(parent: Node3D,p: Vector3,r: float,t: float,m: Material) -> MeshInstance3D:
	var mesh := TorusMesh.new()
	mesh.inner_radius=r-t
	mesh.outer_radius=r+t
	mesh.rings=32
	mesh.ring_segments=6
	var n := _part(parent,mesh,p,m)
	n.rotation.x=PI/2
	return n

func _build_crossing() -> void:
	door=preload("res://scenes/blue_prince_lab/doors/Door.tscn").instantiate()
	door.position=Vector3(0,.01,-9.13)
	door.scale=Vector3.ONE*1.48
	door.hall_finish=true
	add_child(door)
	for n in door.find_children("*","MeshInstance3D",true,false): n.layers=LAYER
	# Masonry seals the portal in the fire year. Opposite geometry is cut per fragment.
	add_child(bolt)
	bolt.position=Vector3(0,1.35,-8.54)
	_box(bolt,Vector3.ZERO,Vector3(2.46,.12,.12),_mat(BRONZE))
	for x: float in [-1.14,1.14]:
		_box(self,Vector3(x,1.35,-8.48),Vector3(.16,.22,.13),_mat(GOLD))
	for row in 10:
		for col in 4:
			var x := (col-1.5)*.56 + (.10 if row%2 else -.10)
			_box(self,Vector3(x,.21+row*.39,-8.78),Vector3(.55,.38,.25),_mat("764b49" if (col+row)%3 else "494350",1))
	for i in 12:
		var z := -1.125 - i*.25
		_box(self,Vector3(0,-.09,z),Vector3(1.37,.18,.245),_mat("bca987" if i%3 else "988678",1))
		for side: float in [-1.,1.]:
			_box(self,Vector3(side*.61,.013,z),Vector3(.045,.018,.242),_mat(GOLD,1,.34))
	for side: float in [-1.,1.]:
		_box(self,Vector3(side*.53,-.22,-2.5),Vector3(.15,.25,3.03),_mat(IRON,1))
	var body:= StaticBody3D.new()
	add_child(body)
	var shape:=BoxShape3D.new()
	shape.size=Vector3(.86,.18,3.)
	plate.shape=shape
	plate.position=Vector3(0,-.09,-2.5)
	body.add_child(plate)
	for x: float in [-.86,.86]:
		for z: float in [-.86,-4.14]:
			_disc(self,Vector3(x,.25,z),.075,.045,.50,_mat(BRONZE))
			_disc(self,Vector3(x,.52,z),.083,.045,.07,_mat(GOLD))

func _build_winding_post() -> void:
	var pivot := Rules.WHEEL
	_disc(self,pivot+Vector3(0,-1.16,-.27),.42,.38,.15,_mat(IRON))
	_disc(self,pivot+Vector3(0,-.55,-.27),.26,.18,1.08,_mat(BRONZE))
	add_child(wheel)
	wheel.position=pivot
	var brass := _mat(GOLD,0)
	_ring(wheel,Vector3.ZERO,.41,.035,brass)
	_ring(wheel,Vector3.ZERO,.12,.022,brass)
	for i in 6:
		var a:=TAU*i/6.
		_box(wheel,Vector3(sin(a)*.23,cos(a)*.23,0),Vector3(.032,.32,.043),brass).rotation.z=-a
	_disc(wheel,Vector3(.28,.23,.08),.05,.041,.15,brass).rotation.x=PI/2
	add_child(weight)
	weight.position=Rules.WEIGHT
	_disc(weight,Vector3.ZERO,.20,.24,.62,_mat("72524a",1))
	for h: float in [-.25,.25]: _disc(weight,Vector3.UP*h,.245,.245,.06,_mat(GOLD,1))
	_box(self,Rules.WEIGHT+Vector3.UP*1.48,Vector3(.032,2.80,.032),_mat(GOLD,1))
	_ring(self,Rules.WEIGHT+Vector3.UP*2.89,.19,.03,_mat(GOLD,1))
	_box(self,Vector3(.12,4.90,-2.45),Vector3(5.03,.030,.032),_mat(GOLD,1))

func _build_desk() -> void:
	# A reading stand and a trunnion-mounted optical lantern, both on the near bank.
	var wood := _mat("58483e")
	_disc(self,BOOK-Vector3.UP*.92,.36,.29,.14,wood)
	_disc(self,BOOK-Vector3.UP*.49,.16,.12,.81,wood)
	var desk := Node3D.new()
	add_child(desk)
	desk.position=BOOK
	desk.rotation.x=.25
	_box(desk,Vector3(0,-.10,0),Vector3(1.17,.13,.82),wood)
	for side: float in [-1.,1.]:
		var page:=Node3D.new()
		desk.add_child(page)
		page.rotation.z=-side*.08
		_box(page,Vector3(side*.25,-.015,0),Vector3(.51,.055,.68),_mat("593b37"))
		_box(page,Vector3(side*.25,.025,0),Vector3(.48,.055,.63),_mat(VELLUM))
		for i in 7:
			_box(page,Vector3(side*.25,.056,-.18+i*.057),Vector3(.21 if i%3==0 else .32,.004,.009),_mat(BRONZE))
	desk.add_child(turning_leaf)
	_box(turning_leaf,Vector3(.23,.062,0),Vector3(.46,.006,.62),_mat(VELLUM))
	for i in 6:
		_box(turning_leaf,Vector3(.23,.067,-.16+i*.058),Vector3(.27 if i!=5 else .15,.004,.011),_mat(BRONZE))
	var s := Rules.SOURCE
	_disc(self,Vector3(s.x,.12,s.z),.39,.32,.22,_mat(IRON))
	_disc(self,Vector3(s.x,.65,s.z),.20,.12,.93,_mat(BRONZE))
	_disc(self,s-Vector3.UP*.36,.28,.28,.10,_mat(GOLD))
	add_child(yoke)
	yoke.position=s
	for sign_x: float in [-1.,1.]:
		_box(yoke,Vector3(sign_x*.22,-.13,0),Vector3(.044,.37,.08),_mat(GOLD))
	_disc(yoke,Vector3.ZERO,.17,.25,.50,_mat(BRONZE)).rotation.x=-PI/2
	_ring(yoke,Vector3(0,0,-.25),.235,.025,_mat(GOLD))
	_disc(yoke,Vector3(0,0,-.25),.208,.208,.01,_mat("ffe5a1",-1,1.3)).rotation.x=PI/2
	for i in 3:
		_ring(yoke,Vector3(0,0,.12-i*.12),.19+i*.018,.016,_mat(GOLD))
	# Oil reservoir, chimney and pierced shoulder keep the projector readable in silhouette.
	_disc(yoke,Vector3(0,.22,.12),.105,.085,.10,_mat(GOLD))
	_disc(yoke,Vector3(0,.34,.12),.075,.066,.18,_mat("ffbe72",-1,1.5))
	_disc(yoke,Vector3(0,.45,.12),.10,.062,.055,_mat(BRONZE))
	for x: float in [-.080,.080]:
		_box(yoke,Vector3(x,.33,.12),Vector3(.012,.21,.018),_mat(GOLD))
	add_child(beam)
	beam.position=s
	beam.light_color=Color("ffdc9b")
	beam.light_energy=2.4
	beam.light_cull_mask=LAYER
	beam.spot_angle=Rules.HALF_ANGLE
	beam.spot_range=Rules.REACH
	beam.spot_attenuation=.32

func _interior_light(p:Vector3,hue:String,power:float,radius:float) -> void:
	var l:=OmniLight3D.new()
	l.position=p
	l.light_color=Color(hue)
	l.light_energy=power
	l.light_cull_mask=LAYER
	l.omni_range=radius
	l.omni_attenuation=.78
	add_child(l)

func set_toon(enabled: bool) -> void:
	for m in finishes: m.set_shader_parameter("toon_on",enabled)

func _make_folio_strip() -> void:
	hud.layer=2
	add_child(hud)
	var bar:=PanelContainer.new()
	hud.add_child(bar)
	bar.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	bar.grow_vertical=Control.GROW_DIRECTION_BEGIN
	var skin:=StyleBoxFlat.new()
	skin.bg_color=Color("1c2530f4")
	skin.border_color=Color("b39865")
	skin.border_width_top=2
	skin.content_margin_left=22
	skin.content_margin_right=22
	skin.content_margin_top=8
	skin.content_margin_bottom=8
	bar.add_theme_stylebox_override("panel",skin)
	var rows:=VBoxContainer.new()
	bar.add_child(rows)
	var top:=HBoxContainer.new()
	rows.add_child(top)
	dial.add_theme_color_override("font_color",Color("e5c58b"))
	dial.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	top.add_child(dial)
	top.add_child(keys)
	for id: StringName in Rules.ACTIONS:
		var b:=Button.new()
		b.text=NAMES[id]
		b.focus_mode=Control.FOCUS_NONE
		b.flat=true
		b.mouse_default_cursor_shape=Control.CURSOR_POINTING_HAND
		b.pressed.connect(use.bind(id))
		keys.add_child(b)
	var reset:=Button.new()
	reset.text="Reopen case"
	reset.flat=true
	reset.pressed.connect(restart)
	keys.add_child(reset)
	if standalone:
		var back:=Button.new()
		back.text="Return to hall"
		back.pressed.connect(func(): return_requested.emit())
		keys.add_child(back)
	caption.add_theme_color_override("font_color",Color("e3e1d6"))
	caption.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
	rows.add_child(caption)

func _refresh() -> void:
	var dir:=rules.direction()
	_expose(dir)
	door.set_open(rules.released and not rules.cinder)
	weight.position.y=Rules.WEIGHT.y + (.66 if rules.released else 0.)
	bolt.position.x=1.53 if rules.released else 0.
	wheel.rotation.z=PI*.5 if rules.released else 0.
	dial.text="VESPER  /  %s     ·     %s" % ["FIRE, 1903" if rules.cinder else "INQUIRY, 1907", ["Shutter closed","Lens I · Ratchet","Lens II · Span"][rules.aim]]
	caption.text=story
	for i in Rules.ACTIONS.size(): keys.get_child(i).disabled=rules.crossed

func _expose(dir: Vector3) -> void:
	for m in finishes:
		m.set_shader_parameter("source",to_global(Rules.SOURCE))
		m.set_shader_parameter("axis",global_basis*dir)
		m.set_shader_parameter("cone_cos",cos(deg_to_rad(Rules.HALF_ANGLE)))
		m.set_shader_parameter("reach",Rules.REACH)
		m.set_shader_parameter("shutter_open",rules.aim!=0)
		m.set_shader_parameter("cinder",rules.cinder)
	yoke.look_at(to_global(Rules.SOURCE+dir))
	beam.global_basis=yoke.global_basis
	beam.visible=rules.aim!=0
	plate.disabled=not rules.bridge_whole(dir)

func use(id: StringName) -> void:
	if rules.crossed: return
	if sweep: sweep.kill()
	var old_dir := rules.direction()
	story=rules.act(id)
	_refresh()
	if id==&"lamp" and rules.aim != 0:
		var final_dir:=rules.direction()
		sweep=create_tween().set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
		sweep.tween_method(func(t: float): _expose(old_dir.slerp(final_dir,t)),0.,1.,.40)
	if id==&"leaf":
		if travel: travel.kill()
		travel=create_tween().set_trans(Tween.TRANS_SINE)
		travel.tween_property(turning_leaf,"rotation:z",PI-.14 if rules.cinder else 0.,.36)
	if rules.crossed:
		recovered.emit()
		if travel: travel.kill()
		travel=create_tween().set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
		travel.tween_property(camera,"global_position",to_global(Vector3(0,1.65,-10.15)),2.15)

func restart() -> void:
	if travel: travel.kill()
	if sweep: sweep.kill()
	rules=Rules.new()
	turning_leaf.rotation.z=0.
	story="A page in the night register survived the fire. Recover it across the well."
	begin(camera)

func click_prop(point: Vector2) -> void:
	if rules.crossed: return
	var best: StringName=&""
	var closest:=1.0
	for id: StringName in ANCHORS:
		var p:=to_global(ANCHORS[id])
		var radius:=camera.unproject_position(p+Vector3.RIGHT*(.67 if id!=&"cross" else 1.)).distance_to(camera.unproject_position(p))
		var d:=camera.unproject_position(p).distance_to(point)/maxf(16.,radius)
		if d<closest:
			best=id
			closest=d
	if best!=&"": use(best)

func snapshot() -> Dictionary:
	var props:={}
	for id: StringName in ANCHORS:
		var pixel:=camera.unproject_position(to_global(ANCHORS[id]))
		props[id]=[pixel.x,pixel.y]
	return {"cinder":rules.cinder,"aim":rules.aim,"released":rules.released,"crossed":rules.crossed,"bridge":not plate.disabled,"story":story,"props":props}

func _unhandled_input(event: InputEvent) -> void:
	if standalone and event is InputEventMouseButton and event.pressed and event.button_index==MOUSE_BUTTON_LEFT:
		click_prop(event.position)

func _exit_tree() -> void:
	if sweep: sweep.kill()
	if travel: travel.kill()

func _build_register() -> void:
	# Real evidence waits beyond the threshold, large enough to read after the dolly.
	var stand := Node3D.new()
	stand.position=Vector3(0,1.38,-11.95)
	add_child(stand)
	_disc(stand,Vector3(0,-.7,0),.34,.16,1.3,_mat(BRONZE))
	var slope:=Node3D.new()
	slope.rotation.x=.84
	stand.add_child(slope)
	_box(slope,Vector3.ZERO,Vector3(1.38,.10,.93),_mat("4b3631"))
	for side: float in [-1.,1.]:
		_box(slope,Vector3(.33*side,.08,0),Vector3(.63,.07,.85),_mat(VELLUM))
		var text:=Label3D.new()
		text.text="NIGHT REGISTER\n_______________\n\n11 NOV. 1903\nAdmit one bearer.\n\nE. Vale" if side<0 else "ARCHIVE COPY\n_______________\n\n11 NOV. 1907\nThe key returned.\n\nE. Vale"
		text.font_size=32
		text.pixel_size=.0019
		text.modulate=Color("392e29")
		text.outline_size=0
		text.rotation.x=-PI/2
		text.position=Vector3(.33*side,.118,0)
		slope.add_child(text)
