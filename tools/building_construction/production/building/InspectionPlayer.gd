extends "res://scenes/rogue_player/RoguePlayer.gd"
## Same feet-origin capsule and locomotion as the expedition; calibrated inspection eye.
func _update_camera(_delta:float)->void:
	_camera.global_position=global_position+Vector3.UP*1.60
	_camera.rotation=Vector3(_pitch,_yaw,0)

func enter(feet:Vector3,yaw:float)->void:
	_pitch=.045
	spawn_at(feet,yaw)
