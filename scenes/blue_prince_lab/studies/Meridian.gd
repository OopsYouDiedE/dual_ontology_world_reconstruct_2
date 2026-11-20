extends Node3D
## Enlarged Deep Space reference model. The fixed dial surrounds three independent pivots.
const TRIANGLE_BUDGET := 8500
const SURFACE_BUDGET := 16
const SPEEDS := Vector3(TAU / 1800.0, -TAU / 360.0, TAU / 40.0)
const ASSETS := "res://scenes/blue_prince_lab/reference/meshes/"
var angles := Vector3(-.13, -.26, .11)
var running := false
var yaw := Node3D.new()
var pitch := Node3D.new()
var roll := Node3D.new()
var _mesh_stats := {"triangles":0, "surfaces":0, "moving_triangles":0}

func _ready() -> void:
	rotation_degrees = Vector3(-39,-20,12)
	_piece("Case", self)
	add_child(yaw)
	yaw.add_child(pitch)
	pitch.add_child(roll)
	_piece("BlueSwing", yaw)
	_piece("SilverCarrier", pitch)
	_piece("ForkBridge", pitch)
	_piece("Balance", roll)
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

func _piece(key: String, parent: Node3D) -> void:
	parent.add_child((load(ASSETS + key + ".glb") as PackedScene).instantiate())

func interact() -> void:
	running = not running

func _process(delta: float) -> void:
	if running:
		angles += SPEEDS * delta * 10.0 # tenfold exhibit playback
		_apply_pose()

func _apply_pose() -> void:
	yaw.rotation.y = angles.x
	pitch.rotation.x = angles.y
	roll.rotation.z = angles.z

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
			if yaw.is_ancestor_of(node): _mesh_stats.moving_triangles += count / 3
	for child in node.get_children(): _count_surfaces(child)
