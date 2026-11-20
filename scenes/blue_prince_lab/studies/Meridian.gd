extends Node3D
## Enlarged Deep Space reference model. The fixed dial surrounds three geared carriages.
const TRIANGLE_BUDGET := 11500
const MOVING_BUDGET := 7200
const SURFACE_BUDGET := 22
const ESCAPE_TEETH := 15
const ASSETS := "res://scenes/blue_prince_lab/reference/meshes/"
const REST := Vector3(-.13, 0, 0)
var angles := REST
var running := true
var elapsed := 0.0
var hour := Node3D.new()
var minute := Node3D.new()
var beat := 0.0
var transfer := Node3D.new()
var planet := Node3D.new()
var escape := Node3D.new()
var lever := Node3D.new()
var spring := preload("res://scenes/blue_prince_lab/studies/Hairspring.gd").new()
var oscillator := Node3D.new()
var yaw := Node3D.new()
var pitch := Node3D.new()
var roll := Node3D.new()
var _mesh_stats := {"triangles":0, "surfaces":0, "moving_triangles":0}

func _ready() -> void:
	rotation_degrees.x = -72.0
	_piece("Case", self)
	add_child(hour)
	add_child(minute)
	_piece("HourHand", hour)
	_piece("MinuteHand", minute)
	add_child(yaw)
	yaw.add_child(pitch)
	pitch.position = Vector3(0,.031,-.06) # axis of the two blue trunnion bearings
	pitch.add_child(roll)
	_piece("BlueSwing", yaw)
	var bevel := _piece("FixedBevel", yaw)
	bevel.position = pitch.position + Vector3(.524,0,0)
	bevel.rotation.y = PI/2 # bevel is fixed to the blue cradle
	_piece("SilverCarrier", pitch)
	_piece("FixedSun", pitch)
	_mount(transfer, "TransferArbor", pitch, Vector3(.5,0,0))
	_piece("CageDrive", roll)
	_mount(planet, "PlanetArbor", roll, Vector3(.30,0,0))
	_mount(escape, "EscapeArbor", roll, Vector3(.30,.18,0))
	_mount(lever, "PalletLever", roll, Vector3(.15,.075,0))
	roll.add_child(spring)
	_piece("ForkBridge", roll)
	roll.add_child(oscillator)
	_piece("Balance", oscillator)
	var ink := Sprite3D.new()
	ink.texture = preload("res://scenes/blue_prince_lab/reference/ChapterInk.png")
	ink.pixel_size = 2.72 / 1024.
	ink.position.z = -.059
	ink.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(ink)
	var cover := MeshInstance3D.new()
	var dome := SphereMesh.new()
	dome.is_hemisphere = true
	dome.radial_segments = 32
	dome.rings = 5
	dome.radius = 1.262
	dome.height = .542
	cover.mesh = dome
	cover.rotation.x = PI/2
	cover.position.z = -.075
	var glass := ShaderMaterial.new()
	glass.shader = preload("res://scenes/blue_prince_lab/reference/Sapphire.gdshader")
	glass.render_priority = 2
	cover.material_override = glass
	cover.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	cover.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
	add_child(cover)
	_count_surfaces(self)
	_mesh_stats.triangles += 2 # chapter-ring lettering quad
	_mesh_stats.surfaces += 1
	_apply_pose()

func _piece(key: String, parent: Node3D) -> Node3D:
	var part := (load(ASSETS + key + ".glb") as PackedScene).instantiate() as Node3D
	part.name = key
	parent.add_child(part)
	return part

func _mount(arbor: Node3D, key: String, parent: Node3D, center: Vector3) -> void:
	arbor.name = key + "Pivot"
	parent.add_child(arbor)
	arbor.position = center
	_piece(key, arbor)

func interact() -> void:
	running = not running

func step_inspection() -> void:
	running = false
	elapsed = fmod(elapsed + 1./48., 43200.)
	_apply_pose()

func _process(delta: float) -> void:
	if running:
		elapsed = fmod(elapsed + delta, 43200.0)
		_apply_pose()

func _apply_pose() -> void:
	# Sample one clock. Drop occurs around each balance centre crossing; both banks
	# hold the train still for the rest of the swing (including on skipped frames).
	var beats := elapsed * 6.0
	var tick := floori(beats)
	var unlock := smoothstep(.455, .545, fposmod(beats, 1.0))
	# Count escape teeth, then solve the four gear meshes backwards. These angles
	# are shaft-relative; the fixed sun has relative angle -cage in its orbit.
	var escape_turns := -(tick + unlock) / (2.0 * ESCAPE_TEETH)
	var planet_turns := -escape_turns * 8./16.
	var cage_turns := planet_turns * 8./32.
	var transfer_turns := -cage_turns * 16./24.
	var middle_turns := transfer_turns * 9./54.
	beat = fposmod(PI * (beats - .5), TAU)
	angles = REST + Vector3(fmod(-middle_turns/5.,1.), fmod(middle_turns,1.), fmod(cage_turns,1.)) * TAU
	hour.rotation.z = -elapsed * TAU / 43200.0
	minute.rotation.z = -TAU * fmod(elapsed,3600.) / 3600.0
	yaw.rotation.z = angles.x
	pitch.rotation.x = angles.y
	roll.rotation.z = angles.z # the balance staff is also the inner cage axis
	transfer.rotation.z = TAU * fmod(transfer_turns,1.)
	planet.rotation.z = TAU * fmod(planet_turns,1.)
	escape.rotation.z = TAU * fmod(escape_turns,1.)
	lever.rotation.z = lerpf(.11, -.11, unlock if tick % 2 == 0 else 1.0-unlock)
	oscillator.rotation.z = 2.7 * sin(beat)
	spring.finish.set_shader_parameter("balance_angle", oscillator.rotation.z)

func mesh_stats() -> Dictionary:
	return _mesh_stats.duplicate()

func _count_surfaces(node: Node) -> void:
	if node is MeshInstance3D:
		for i in node.mesh.get_surface_count():
			var arrays: Array = node.mesh.surface_get_arrays(i)
			var indices: Variant = arrays[Mesh.ARRAY_INDEX]
			var count: int = arrays[Mesh.ARRAY_VERTEX].size() if indices == null or indices.is_empty() else indices.size()
			_mesh_stats.triangles += count / 3
			_mesh_stats.surfaces += 1
			if yaw.is_ancestor_of(node) or hour.is_ancestor_of(node) or minute.is_ancestor_of(node): _mesh_stats.moving_triangles += count / 3
	for child in node.get_children(): _count_surfaces(child)
