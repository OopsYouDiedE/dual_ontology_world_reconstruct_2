extends SubViewportContainer
## A separate world keeps the ArchBuilder camp and its residents alive behind the exhibit.
const Room := preload("VesperRoom.gd")
const Look := preload("res://scenes/blue_prince_lab/HallLook.gd")
var puzzle := Room.new()

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	stretch=true
	var vp:=SubViewport.new()
	vp.own_world_3d=true
	vp.msaa_3d=get_viewport().msaa_3d
	add_child(vp)
	var world:=WorldEnvironment.new()
	world.environment=Look.environment(true)
	world.environment.ambient_light_color=Color("bdcbdc")
	world.environment.ambient_light_energy=.47
	vp.add_child(world)
	vp.add_child(Look.ink_pass())
	puzzle.standalone=true
	vp.add_child(puzzle)
	var cam:=Camera3D.new()
	cam.near=.06
	vp.add_child(cam)
	puzzle.begin(cam)
