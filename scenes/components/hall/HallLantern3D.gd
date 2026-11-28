@tool
class_name HallLantern3D
extends GothicHallPiece3D
## Hanging oil lantern (the project's Lamp component), lit by the hall's night factor.

const OilLamp := preload("res://scenes/components/props/lamp/Lamp.tscn")

@export var hang_length := 0.68:
	set(v): hang_length = v; changed()
@export var light_energy := 2.85:
	set(v): light_energy = v; changed()
@export var lamp_scale := 1.32:
	set(v): lamp_scale = v; changed()

func _build() -> void:
	var lamp := OilLamp.instantiate()
	lamp.hang_length = hang_length
	lamp.light_energy = light_energy
	lamp.shadow_enabled = false
	lamp.scale = Vector3.ONE * lamp_scale
	add_child(lamp)
	_lanterns.append(lamp)
