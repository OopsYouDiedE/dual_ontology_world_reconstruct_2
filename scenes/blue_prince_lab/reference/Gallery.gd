extends Node3D
## Fixed reference cameras. Only the selected set is resident in the world.
const NAMES := ["Chapel", "Garden Gate", "Forest Camp", "Attic", "Draft", "Security", "Inspect"]
const SCENES := ["Chapel", "GardenGate", "ForestCamp", "Attic", "DraftLobby", "Security", "Darkroom"]
const EYES := [Vector3(3.40,3.35,4.70),Vector3(0,1.50,8.9),Vector3(-0.46,1.57,8.6),Vector3(1.04,1.57,3.85),Vector3(0,1.48,3.02),Vector3(.10,1.83,4.14),Vector3(.24,1.62,3.25)]
const AIM := [Vector3(-0.12,2.29,-3.20),Vector3(0.05,1.96,-6),Vector3(0.02,2.03,-3.1),Vector3(0.39,1.29,-4.7),Vector3(0,1.48,-1.0),Vector3(0,1.40,0),Vector3(0,1.67,-.4)]
const FOV := [65.,46.,47.,46.,52.,50.,58.]
const LAYER := 4
var set_root: Node3D
var previous := -1
var meadow: Node3D
var interface_layer: CanvasLayer
var desk: Control
var sky := Sky.new()
var paint := ShaderMaterial.new()

func _ready() -> void:
	position = Vector3(0,0,140)
	paint.shader = preload("res://scenes/blue_prince_lab/reference/Pigment.gdshader")
	var mat := ShaderMaterial.new()
	mat.shader = preload("res://scenes/blue_prince_lab/reference/Overcast.gdshader")
	sky.sky_material = mat

func clear_set(env: Environment) -> void:
	if previous < 0: return
	if interface_layer:
		remove_child(interface_layer)
		interface_layer.queue_free()
		interface_layer=null
	desk=null
	meadow=null
	remove_child(set_root)
	set_root.queue_free()
	previous = -1
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color("8f9ba6")
	env.ambient_light_color = Color("c5d2de")
	env.ambient_light_energy = 0.42
	env.fog_enabled = false
	env.sky = null

func show_set(index: int, camera: Camera3D, env: Environment) -> void:
	clear_set(env)
	var path := "res://scenes/blue_prince_lab/reference/%s.tscn" % SCENES[index]
	set_root = (load(path) as PackedScene).instantiate()
	add_child(set_root)
	previous = index
	for n in set_root.find_children("*", "MeshInstance3D", true, false):
		for i in n.mesh.get_surface_count():
			var finish: Material = n.mesh.surface_get_material(i)
			if finish.resource_name == "paint": n.set_surface_override_material(i, paint)
		n.layers = LAYER
		n.gi_mode = GeometryInstance3D.GI_MODE_STATIC
	camera.fov = FOV[index]
	camera.global_position = to_global(EYES[index])
	camera.look_at(to_global(AIM[index]))
	if index in [1,2]:
		env.sky = sky
		env.background_mode = Environment.BG_SKY
		env.fog_enabled = true
		env.fog_mode = Environment.FOG_MODE_DEPTH
		env.fog_depth_begin = 9.0
		env.fog_depth_end = 102.0
		env.fog_depth_curve = 0.82
		env.fog_light_color = Color("537c99")
		env.fog_sky_affect = 0.0
		env.ambient_light_color = Color("98b9d1")
		env.ambient_light_energy = 0.82
		_sun(Vector3(-.6,-.82,-.22),"c0d7e8",0.60)
		meadow = preload("Meadow.gd").new()
		set_root.add_child(meadow)
		meadow.build(index==2)
	elif index == 0:
		env.ambient_light_color = Color("d3c4d0")
		env.ambient_light_energy = 0.77
		_bulb(Vector3(-2.8,3,-2),"ffc3a9",1.36,7.0)
		_bulb(Vector3(3.4,3.6,1.0),"d9d5ff",1.2,6.)
	elif index == 3:
		env.ambient_light_color = Color("8caed0")
		env.ambient_light_energy = .76
		_bulb(Vector3(-.5,2.8,-.9),"98bcdf",1.12,10.0)
		# A warm exterior source projects the real eight-spoke window onto the floor.
		env.background_color = Color("ffd29f")
		var daylight := SpotLight3D.new()
		daylight.light_color = Color("ffc59e")
		daylight.light_energy = 7.0
		daylight.spot_attenuation = 0.25
		daylight.spot_range = 18.0
		daylight.spot_angle = 32.0
		daylight.shadow_enabled = true
		daylight.light_cull_mask = LAYER
		set_root.add_child(daylight)
		daylight.position = Vector3(-2.22,5.60,-7.23)
		daylight.look_at(set_root.to_global(Vector3(-1.02,2.96,-4.95)))

	else:
		env.ambient_light_color = Color(["abb4c2","8caaa1","b97e8d"][index-4])
		env.ambient_light_energy = [.50,.62,.65][index-4]
		if index==5:
			_screens()
			_bulb(Vector3(0,1.65,1.15),"83dca8",1.05,5.)
			_bulb(Vector3(-1.2,3.2,2.0),"afc3c6",.83,7.)
		else:
			_bulb(Vector3(-2,2.45,1.0),"ff3152" if index==6 else "a6bed7",2.4 if index==6 else .80,7.)
			_bulb(Vector3(2.5,1.87,1.7),"fa3449" if index==6 else "9aadc2",1.7 if index==6 else .65,5.)
			interface_layer=CanvasLayer.new()
			interface_layer.layer=1
			add_child(interface_layer)
			desk=preload("interface/PaperDesk.gd").new()
			interface_layer.add_child(desk)
			desk.setup(NAMES[index])

func _screens() -> void:
	var cabinets: Array = JSON.parse_string(FileAccess.get_file_as_string("res://scenes/blue_prince_lab/reference/interface/cabinets.json"))
	for i in cabinets.size():
		var b: Array = cabinets[i]
		var face := QuadMesh.new()
		face.size=Vector2(b[2]*.875,b[3]*.757)
		var crt := ShaderMaterial.new()
		crt.shader=preload("interface/CRT.gdshader")
		crt.set_shader_parameter("feed",preload("interface/Feeds.jpg"))
		var ch := (i*3+i/8)%8
		crt.set_shader_parameter("tile",Vector2(ch%4,ch/4))
		crt.set_shader_parameter("channel",i*.163)
		var tube := MeshInstance3D.new()
		tube.mesh=face
		tube.layers=LAYER
		tube.material_override=crt
		tube.position=Vector3(b[0],b[1]+b[3]*.547,.054)
		tube.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		set_root.add_child(tube)

func _sun(direction: Vector3, hue: String, power: float) -> void:
	var sun := DirectionalLight3D.new()
	sun.light_color = Color(hue)
	sun.light_energy = power
	sun.light_cull_mask = LAYER
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 48
	set_root.add_child(sun)
	sun.look_at(sun.global_position + direction)

func _bulb(where: Vector3, hue: String, power: float, radius: float) -> void:
	var light := OmniLight3D.new()
	light.position = where
	light.light_color = Color(hue)
	light.light_energy = power
	light.omni_range = radius
	light.omni_attenuation = 0.75
	light.light_cull_mask = LAYER
	set_root.add_child(light)
