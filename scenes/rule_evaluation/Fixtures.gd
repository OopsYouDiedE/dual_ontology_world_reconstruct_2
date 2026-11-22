extends RefCounted
## Whitebox finish: rubber registration, anodized machine shells, ceramic labels.

const RUBBER := preload("res://scenes/rubber_whitebox/RubberTile.gdshader")
const INK := Color("1e2829")
const PAPER := Color("ede5c9")
const STEEL := Color("52636a")
const BRASS := Color("a47b4d")
const GREEN := Color("a3e4b9")
const AMBER := Color("f0b16d")
const FIELD_PLATES := preload("res://scenes/blue_prince_lab/reference/plates.jpg")
const ESCAPEMENT_BALANCE := preload("res://scenes/blue_prince_lab/reference/meshes/Balance.glb")
const INDEX_CAGE_DRIVE := preload("res://scenes/blue_prince_lab/reference/meshes/CageDrive.glb")


static func matte(color: Color, metal := 0.0) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.metallic = metal
	mat.roughness = 0.69
	return mat

static func light_mat(color: Color) -> StandardMaterial3D:
	var mat := matte(color)
	mat.emission_enabled = true
	mat.emission = color
	mat.emission_energy_multiplier = 0.65
	return mat

static func box(parent: Node3D, center: Vector3, size: Vector3, material: Material) -> MeshInstance3D:
	var inst := MeshInstance3D.new()
	var shape := BoxMesh.new()
	shape.size = size
	inst.mesh = shape
	inst.material_override = material
	inst.position = center
	parent.add_child(inst)
	return inst

static func disk(parent: Node3D, center: Vector3, radius: float, thickness: float, material: Material) -> MeshInstance3D:
	var inst := MeshInstance3D.new()
	var shape := CylinderMesh.new()
	shape.top_radius = radius
	shape.bottom_radius = radius
	shape.height = thickness
	shape.radial_segments = 20
	shape.rings = 0
	inst.mesh = shape
	inst.material_override = material
	inst.position = center
	inst.rotation_degrees.x = 90
	parent.add_child(inst)
	return inst

static func print_on(parent: Node3D, title: String, center: Vector3, color: Color, scale_factor := 0.0034) -> Label3D:
	var text := Label3D.new()
	text.text = title
	text.font_size = 30
	text.outline_size = 0
	text.pixel_size = scale_factor
	text.modulate = color
	text.position = center
	text.rotation_degrees.y = 180
	parent.add_child(text)
	return text

static func archive_plate(parent: Node3D, center: Vector3, region: Rect2i, caption: String) -> void:
	var frame := matte(Color("49362a"), 0.08)
	box(parent, center, Vector3(2.13, 1.42, 0.10), frame)
	box(parent, center + Vector3(0, 0.04, -0.07), Vector3(2.01, 1.20, 0.05), matte(PAPER))
	var print_material := matte(Color.WHITE)
	print_material.albedo_texture = ImageTexture.create_from_image(FIELD_PLATES.get_image().get_region(region))
	var plate := MeshInstance3D.new()
	var quad := QuadMesh.new()
	quad.size = Vector2(1.87, 1.052)
	plate.mesh = quad
	plate.material_override = print_material
	plate.rotation.y = PI
	plate.position = center + Vector3(0, 0.045, -0.101)
	parent.add_child(plate)
	print_on(parent, caption, center + Vector3(0, -0.61, -0.070), PAPER, 0.0025)

static func mount_authored_rotor(parent: Node3D, asset: PackedScene, radius: float, finish: Material) -> void:
	# The installed model is a visual child of the integer phase-driven rotor.
	# Fit the authored mesh to the face envelope; never add imported collision.
	var mounted := asset.instantiate() as Node3D
	parent.add_child(mounted)
	var mesh_node: MeshInstance3D = mounted as MeshInstance3D
	if mesh_node == null:
		var meshes := mounted.find_children("*", "MeshInstance3D", true, false)
		if not meshes.is_empty(): mesh_node = meshes[0] as MeshInstance3D
	if mesh_node == null:
		mounted.queue_free()
		return
	var envelope: AABB = (mounted.global_transform.affine_inverse() * mesh_node.global_transform) * mesh_node.get_aabb()
	var xy := radius * 1.55 / maxf(0.001, maxf(envelope.size.x, envelope.size.y))
	var fit := Vector3(xy, xy, minf(xy, 0.047 / maxf(envelope.size.z, 0.001)))
	mounted.scale = fit
	mounted.position = Vector3(0, 0, -0.074) - envelope.get_center() * fit
	mesh_node.material_override = finish

static func encasement(parent: Node3D, width: float, depth: float, level: int, title: String,
		portal := Vector3.INF, span := 1.7) -> void:
	var furnace := level >= 7
	var tint := Color("446271") if level <= 2 else (Color("425c56") if level <= 6 else Color("6d5449"))
	var floor := ShaderMaterial.new()
	floor.shader = RUBBER
	floor.set_shader_parameter("sheet_color", tint)
	floor.set_shader_parameter("registration_ink", Color("a4b5a5"))
	floor.set_shader_parameter("molded_tread", true)
	floor.set_shader_parameter("floor_grid_ink", 0.17)
	box(parent, Vector3(0, -0.12, depth * 0.5), Vector3(width + 0.23, 0.24, depth + 0.24), floor)
	var chalk := matte(Color("b8b19c"))
	var band := matte(tint.lightened(0.16))
	var rib := matte(Color("787d75"), 0.12)
	var seam := matte(Color("d7c8a6"))
	var light := light_mat(Color("fff0cb"))
	const H := 4.4
	for s: float in [-1.0, 1.0]:
		box(parent, Vector3(s * (width * 0.5 + 0.14), H * 0.5, depth * 0.5), Vector3(0.28, H, depth), chalk)
		box(parent, Vector3(s * width * 0.5, 0.53, depth * 0.5), Vector3(0.035, 1.06, depth), band)
		box(parent, Vector3(s * (width * 0.5 - 0.035), 1.08, depth * 0.5), Vector3(0.055, 0.06, depth), seam)
		box(parent, Vector3(s * (width * 0.5 - 0.34), 0.005, depth * 0.5), Vector3(0.018, 0.012, depth * 0.90), seam)
		for index in range(1, ceili(depth / 2.6)):
			var z := float(index) * 2.55
			if z > depth - 0.45: continue
			box(parent, Vector3(s * (width * 0.5 - 0.12), 2.24, z), Vector3(0.23, 4.40, 0.11), rib)
			if index % 2 == 1:
				box(parent, Vector3(s * (width * 0.5 - 0.095), 2.91, z+0.60), Vector3(0.18, 0.13, 1.12), rib)
				box(parent, Vector3(s * (width * 0.5 - 0.192), 2.91, z+0.60), Vector3(0.036, 0.066, 0.91), light)
	for z: float in [-0.14, depth + 0.14]:
		if z > 0 and portal != Vector3.INF:
			var left := portal.x - span*0.49
			var right := portal.x + span*0.49
			var wall_edges := [-width*0.5-0.28, left, right, width*0.5+0.28]
			for i in [0,2]:
				var a: float = wall_edges[i]
				var b: float = wall_edges[i+1]
				box(parent,Vector3((a+b)*0.5,H*0.5,z),Vector3(b-a,H,0.28),chalk)
			box(parent,Vector3(portal.x,(H+2.35)*0.5,z),Vector3(span,H-2.35,0.28),chalk)
			var passage := matte(Color("718586"))
			var length := depth - portal.z + 2.24
			var mid := portal.z + length*0.5
			for x: float in [left-0.08,right+0.08]:
				box(parent,Vector3(x,1.28,mid),Vector3(0.18,2.56,length),passage)
			box(parent,Vector3(portal.x,-0.07,mid),Vector3(span,0.14,length),floor)
			box(parent,Vector3(portal.x,2.44,mid),Vector3(span,0.16,length),rib)
			box(parent,Vector3(portal.x,1.20,depth+2.22),Vector3(span,2.45,0.15),matte(Color("435854")))
			box(parent,Vector3(portal.x,2.34,depth+0.71),Vector3(span*0.54,0.08,0.22),light)
			var foot_lamp := OmniLight3D.new()
			foot_lamp.position = Vector3(portal.x,1.81,depth+0.67)
			foot_lamp.omni_range = 3.6
			foot_lamp.light_energy = 0.78
			foot_lamp.light_color = Color("c1e3d9")
			parent.add_child(foot_lamp)
		else:
			box(parent, Vector3(0, H * 0.5, z), Vector3(width + 0.56, H, 0.28), chalk)
		var sign_z := z + (-0.165 if z > 0 else 0.165)
		box(parent, Vector3(0, 3.61, sign_z), Vector3(minf(width - 0.8, 5.8), 0.44, 0.05), matte(INK))
		if z > 0:
			print_on(parent, title.to_upper(), Vector3(0, 3.62, sign_z - 0.031), PAPER, 0.0040)
	box(parent, Vector3(0, H+0.07, depth * 0.5), Vector3(width + 0.22, 0.19, depth), matte(Color("707e7d")))
	for fraction: float in [0.16, 0.47, 0.76]:
		var z := depth * fraction
		box(parent, Vector3(0, 4.22, z), Vector3(width, 0.27, 0.27), rib)
		box(parent, Vector3(0, 4.02, z), Vector3(width * 0.57, 0.11, 0.22), light)
		var lamp := OmniLight3D.new()
		lamp.position = Vector3(0, 3.85, z)
		lamp.omni_range = 8.8
		lamp.omni_attenuation = 0.95
		lamp.light_energy = 1.18 if furnace else 1.27
		lamp.light_color = Color("f8dab1") if furnace else Color("ecf0e1")
		lamp.shadow_enabled = (fraction == 0.47)
		parent.add_child(lamp)

static func make(parent: Node3D, e: Dictionary, separate_exit_leaf := false) -> Dictionary:
	var root := Node3D.new()
	root.name = e.entity_id
	parent.add_child(root)
	var sz: Array = e.primitive_geometry.size
	var s := Vector3(float(sz[0]), float(sz[1]), float(sz[2])) * 0.001
	var kind := str(e.entity_class)
	var color := Color(str(e.color))
	var body := matte(color, 0.19)
	var dark := matte(INK, 0.13)
	var metal := matte(STEEL, 0.30)
	var ivory := matte(PAPER)
	var signal_material := light_mat(AMBER)
	var signal_mesh: MeshInstance3D
	var mobile: Node3D
	var slide: Node3D
	var pointer: Node3D
	var flag: Node3D
	var gauge: Node3D
	var lever: Node3D
	if kind == "shadow_zone":
		return {"root": root, "mark": null, "rotor": null}
	if e.entity_id == "exit":
		for sign_x: float in [-1.0, 1.0]:
			box(root, Vector3(sign_x*s.x*0.49, s.y*0.49, 0), Vector3(0.16, s.y*0.98, s.z+0.09), body)
			box(root, Vector3(sign_x*s.x*0.41, s.y*0.49, -s.z*0.46), Vector3(0.026,s.y*0.95,0.037), ivory)
		box(root, Vector3(0, s.y*0.97, 0), Vector3(s.x+0.16, 0.28, s.z+0.12), body)
		box(root, Vector3(0, 0.028, 0), Vector3(s.x, 0.054, s.z + 0.14), dark)

		signal_mesh = box(root, Vector3(s.x*0.39, s.y*0.96, -s.z*0.72), Vector3(0.13, 0.077, 0.035), signal_material)
		print_on(root, "E G R E S S", Vector3(0, s.y*0.97, -s.z*0.56-0.06), PAPER)
		if not separate_exit_leaf:
			slide = Node3D.new()
			root.add_child(slide)
			box(slide, Vector3(0, s.y*0.47, 0), Vector3(s.x*0.91, s.y*0.91, s.z*0.75), dark)
			box(slide, Vector3(0, s.y*0.47, -s.z*0.41), Vector3(0.034, s.y*0.89, 0.025), metal)
			for x: float in [-0.23, 0.23]:
				box(slide, Vector3(s.x*x, s.y*0.46, -s.z*0.49), Vector3(0.22, 0.050, 0.081), ivory)
	elif kind in ["clock", "phase-cam", "flywheel"]:
		box(root, Vector3(0, s.y*0.5, s.z*0.09), Vector3(s.x, s.y, s.z*0.82), dark)
		var r := minf(s.x, s.y) * 0.408
		pointer = Node3D.new()
		root.add_child(pointer)
		var mark_plate := box(pointer, Vector3(0, s.y * 0.92, -s.z*0.59), Vector3(r*0.14, r*0.31, 0.055), ivory)
		mark_plate.rotation.z = 0.785
		for n in range(12):
			var a := TAU * float(n) / 12.0
			var rim := box(root, Vector3(cos(a)*r*0.98, s.y*0.50 + sin(a)*r*0.98, -s.z*0.50), Vector3(r*0.11, 0.016, 0.026), metal)
			rim.rotation.z = a
		disk(root, Vector3(0, s.y*0.50, -s.z*0.31), r, s.z*0.24, metal)
		mobile = Node3D.new()
		mobile.position = Vector3(0, s.y*0.50, -s.z*0.45)
		root.add_child(mobile)
		disk(mobile, Vector3.ZERO, r*0.90, 0.08, body)
		if kind == "flywheel" or kind == "clock":
			var model: PackedScene = INDEX_CAGE_DRIVE if kind == "flywheel" else ESCAPEMENT_BALANCE
			mount_authored_rotor(mobile, model, r, matte(Color("d1b585"), 0.24))
		else:
			for index in range(6):
				var angle := float(index) * PI / 3.0
				var spoke := box(mobile, Vector3(cos(angle)*r*0.53, sin(angle)*r*0.53, -0.06), Vector3(r * 0.70, r * 0.085, 0.03), ivory)
				spoke.rotation.z = angle
			disk(mobile, Vector3(0, 0, -0.047), r*0.23, 0.073, dark)
		box(mobile, Vector3(0, r*0.73, -0.071), Vector3(r*0.13, r*0.21, 0.022), light_mat(AMBER))
		signal_mesh = disk(root, Vector3(s.x*0.42, s.y*0.91, -s.z*0.59), 0.061, 0.045, signal_material)
	elif kind in ["plate", "pressure_plate"]:
		box(root, Vector3(0, s.y*0.48, 0), s, dark)
		box(root, Vector3(0, s.y*0.86, 0), Vector3(s.x*0.89, maxf(s.y*0.25,0.020), s.z*0.9), body)
		for x: float in [-0.36, 0.36]:
			box(root, Vector3(s.x*x, s.y*1.02, 0), Vector3(0.035, 0.018, s.z*0.80), ivory)
		for x: float in [-0.465,0.465]:
			box(root, Vector3(s.x*x, 0.52, s.z*0.5-0.055), Vector3(0.065,1.04,0.11), metal)
		box(root, Vector3(0, 0.94, s.z*0.5-0.055), Vector3(s.x,0.32,0.11), dark)
		signal_mesh = box(root, Vector3(0, 0.91, s.z*0.5-0.119), Vector3(s.x*0.82, 0.064, 0.025), signal_material)
	elif kind in ["alarm"] or (e.entity_id == "alarm" and kind == "index_marker"):
		box(root, Vector3(0,s.y*0.50,0), s, dark)
		box(root, Vector3(0,s.y*0.50,-s.z*0.47), Vector3(s.x*0.88,s.y*0.82,0.052), metal)
		signal_mesh = box(root, Vector3(0,s.y*0.59,-s.z*0.55), Vector3(s.x*0.75,s.y*0.42,0.057), signal_material)
	elif kind in ["lamp", "reticle"]:
		box(root, Vector3(0,s.y*0.50,0), s, dark)
		box(root, Vector3(0,s.y*0.50,-s.z*0.50), Vector3(s.x*0.89,s.y*0.87,0.031), metal)
		if kind == "lamp":
			signal_mesh = disk(root,Vector3(0,s.y*0.50,-s.z*0.58),s.y*0.32,0.10,signal_material)
		else:
			signal_mesh = box(root, Vector3(0,s.y*0.50,-s.z*0.58), Vector3(s.x*0.79,s.y*0.52,0.05), signal_material)
			box(root, Vector3(0,s.y*0.50,-s.z*0.67), Vector3(s.x*0.15,0.028,0.018), dark)
			box(root, Vector3(0,s.y*0.50,-s.z*0.67), Vector3(0.023,s.y*0.54,0.018), dark)
	elif kind == "divider":
		box(root, Vector3(0, s.y*0.5, 0), s, body)
		for h: float in [0.24, 1.08, 2.22]:
			box(root, Vector3(0, h, 0), Vector3(s.x + 0.03, 0.044, s.z + 0.03), dark)
	elif kind in ["inspection-datum", "inspection-arm", "sign", "index_marker", "sliding_shutter", "shutter", "barrier", "bridge", "screen", "load", "reticle", "carriage", "counterweight", "frame"]:
		box(root, Vector3(0, s.y*0.5, 0), s, body)
		box(root, Vector3(0, s.y*0.14, -s.z*0.51), Vector3(s.x*0.92, minf(0.07,s.y*0.18), 0.016), dark)
		if kind in ["shutter", "sliding_shutter", "screen", "barrier"]:
			for i in range(1,5):
				var x := float(i) / 5.0 - 0.5
				box(root, Vector3(s.x*x, s.y*0.5, -s.z*0.52), Vector3(0.031, s.y*0.83, 0.025), metal)
	elif kind == "floor_channel":
		box(root, Vector3(0,s.y*0.50,0), s, metal)
	else:
		box(root, Vector3(0, s.y*0.5, s.z*0.07), Vector3(s.x,s.y,s.z*0.86), body)
		box(root, Vector3(0, s.y*0.15, -s.z*0.47), Vector3(s.x*0.94, s.y*0.30, s.z*0.11), dark)
		box(root, Vector3(0, s.y*0.73, -s.z*0.41), Vector3(s.x*0.77, s.y*0.34, s.z*0.18), metal)
		for x: float in [-0.23, 0.23]:
			box(root, Vector3(s.x*x, s.y*0.77, -s.z*0.58), Vector3(s.x*0.080, s.y*0.17, s.z*0.24), dark)
		var handle_center := Vector3(0, s.y*0.81, -s.z*0.68)
		if e.entity_id in ["copper", "cobalt", "capstan", "bolt", "release"]:
			lever = Node3D.new()
			root.add_child(lever)
			lever.position = handle_center
			box(lever, Vector3.ZERO, Vector3(s.x*0.61, 0.068, 0.089), ivory)
			disk(lever, Vector3(0, 0, 0.01), 0.07, 0.12, metal)
		else:
			box(root, handle_center, Vector3(s.x*0.61, 0.068, 0.089), ivory)
		signal_mesh = disk(root, Vector3(s.x*0.43, s.y*0.90, -s.z*0.49), 0.047, 0.05, signal_material)
		if e.whitebox_state.has("pressure_kpa"):
			var center := Vector3(0,s.y*0.66,-s.z*0.52)
			var radius := s.x*0.22
			disk(root,center,radius,0.070,dark)
			disk(root,center+Vector3(0,0,-0.046),radius*0.82,0.035,ivory)
			for n in range(8):
				var angle := deg_to_rad(-50.0+40.0*float(n))
				var tick := box(root,center+Vector3(sin(angle)*radius*0.64,cos(angle)*radius*0.64,-0.074),
					Vector3(0.012,radius*0.17,0.013),matte(Color("bd4f42")) if n>5 else dark)
				tick.rotation.z = -angle
			gauge = Node3D.new()
			gauge.position = center+Vector3(0,0,-0.087)
			root.add_child(gauge)
			box(gauge,Vector3(0,radius*0.32,0),Vector3(0.021,radius*0.70,0.015),matte(Color("a64635")))
		if e.whitebox_state.has("selected"):
			flag = Node3D.new()
			root.add_child(flag)
			box(flag, Vector3(0, s.y+0.17,0), Vector3(0.038,0.38,0.047), metal)
			box(flag, Vector3(0, s.y+0.38,0), Vector3(s.x*0.86,0.27,0.067), matte(Color("d96040")))
			print_on(flag,"REJECTED",Vector3(0,s.y+0.37,-0.049),PAPER,0.0032)
	if e.entity_id != "exit" and not str(e.label).is_empty() and e.entity_id != "index" and kind not in ["divider", "plate", "pressure_plate", "inspection-arm"] and s.y >= 0.24:
		var caption := str(e.label).to_upper()
		var first_line := caption.split(" | ")[0].split(" • ")[0]
		var bottom := s.y*0.23 if kind in ["clock","phase-cam","flywheel"] else s.y*0.52
		if kind == "inspection-datum": bottom = s.y*0.91
		if kind == "reticle": bottom = s.y*0.15
		# Nameplates stay outside the swept silhouette of the bolt and drive links.
		var plate_width := s.x * 0.94
		var plate_x := 0.0
		if kind == "reticle":
			first_line = "REGISTER"
			plate_width = s.x * 0.62
			plate_x = signf(float(e.primitive_geometry.position[0])) * s.x * 0.165
		if first_line == "READER": bottom = s.y*0.69
		if e.entity_id == "bolt" or kind in ["clock", "flywheel"]:
			bottom = s.y*0.915
			plate_width = s.x * 0.66
			plate_x = -s.x * 0.082
		var glyph := minf(0.0032, plate_width / maxf(15.0 * float(first_line.length()), 240.0))
		box(root, Vector3(plate_x, bottom, -s.z*0.545), Vector3(plate_width, 0.154, 0.026), dark)
		print_on(root, first_line, Vector3(plate_x, bottom, -s.z*0.56-0.016), PAPER, glyph)
		if kind == "flywheel":
			box(root, Vector3(0, s.y*0.11, -s.z*0.545), Vector3(s.x*0.66, 0.154, 0.026), dark)
			print_on(root, "DOG UP = WORKING SECTOR", Vector3(0, s.y*0.11, -s.z*0.56-0.016), PAPER, 0.0025)
	return {"root":root, "mark":signal_mesh, "indicator":signal_material, "rotor":mobile, "pointer":pointer, "slide":slide, "flag":flag, "gauge":gauge, "lever":lever, "span":s.x}
