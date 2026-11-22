extends RefCounted
## Opt-in camera/input score. It produces the same move, relative look,
## crouch and talk commands used by a human; only the controller moves bodies.
const Room = preload("res://scenes/physics_lab/airlock/Room.gd")
var phase := 0
var since := 0
var failed := false


func command(game: Node3D) -> Dictionary:
	var age: int = game.tick - since
	if failed or phase >= 18: return {}
	if age > 600:
		failed = true
		game.film_failed = "WALKTHROUGH STUCK step %d: %s" % [phase, JSON.stringify(game.mcp_observe())]
		printerr(game.film_failed)
		if _cli(): game.get_tree().quit(2)
		return {}
	var p: Vector3 = game.lead.position
	var near_aim := Vector3(-.02,0,-2.18)
	match phase:
		0: # Let the player see the entrance and the materialized deck.
			if age >= 132: _next(game)
			return _input(game,p,Vector3(-.18,1.66,-3.84) if age < 27 else Room.A_AIM,.025)
		1: # An ordinary look toward Hale breaks the light, in full view.
			if age >= 145: _next(game)
			return _input(game,p,game.hale.position+Vector3.UP*1.73,.029)
		2:
			if _arrived(p,Vector3(-.15,0,.49)): _next(game)
			return _input(game,Vector3(-.15,0,.49), near_aim)
		3:
			if _arrived(p,Vector3(-.15,0,-1.22)): _next(game)
			return _input(game,Vector3(-.15,0,-1.22), near_aim)
		4:
			if age >= 34: _next(game)
			return _input(game,p,near_aim)
		5:
			if _arrived(p,Vector3(-.15,0,.62)) and game.rule.counterexample: _next(game)
			return _input(game,Vector3(-.15,0,.62), near_aim)
		6:
			var pos := Vector3(.13,0,1.52)
			if _arrived(p,pos): _next(game)
			return _input(game,pos,game.hale.position+Vector3.UP*1.49)
		7:
			if game.rule.revised: _next(game)
			var out := _input(game,p,game.hale.position+Vector3.UP*1.49)
			out["talk"] = age >= 58 and age % 9 == 0
			return out
		8:
			if game.role == "WATCH_B" and game.deck[1] and age > 130: _next(game)
			return _input(game,Vector3(.39,0,.50),near_aim,.032)
		9:
			var pos := Vector3(-.19,0,-2.91)
			if _arrived(p,pos): _next(game)
			return _input(game,pos,near_aim if p.z > -1.72 else Vector3(.20,0,-3.30))
		10:
			var pos := Vector3(.53,0,Room.B_LANE)
			if _arrived(p,pos): _next(game)
			return _input(game,pos,Vector3(2.18,1.02,-3.87),.039)
		11:
			var pos := Vector3(1.90,0,Room.B_LANE)
			if _arrived(p,pos): _next(game)
			return _input(game,pos,Vector3(5.25,.35,Room.B_LANE),.035,true)
		12:
			var pos := Vector3(6.16,0,Room.B_LANE)
			if _arrived(p,pos): _next(game)
			return _input(game,pos,Vector3(7.41,1.02,-3.95),.035)
		13:
			if _arrived(p,Room.FAR_WATCH): _next(game)
			return _input(game,Room.FAR_WATCH,Room.B_AIM,.042)
		14:
			if game.role == "FAR": _next(game)
			return _input(game,p,Room.B_AIM,.03)
		15:
			var pos := Vector3(7.13,0,-3.95)
			if _arrived(p,pos): _next(game)
			return _input(game,pos,Vector3(7.9,1.33,-3.95),.038)
		16:
			if game.cleared: _next(game)
			return _input(game,Vector3(7.86,0,-3.95),Vector3(8.04,1.35,-3.95))
		17:
			if age > 168:
				_next(game)
				print("OBSERVER_AIRLOCK_CLEAR ",JSON.stringify(game.mcp_observe()))
				if _cli(): game.get_tree().quit()
	return {}


func _next(game: Node3D) -> void:
	phase += 1
	since = game.tick


func _cli() -> bool:
	return OS.get_cmdline_user_args().has("--airlock-film") or OS.get_cmdline_user_args().has("--airlock-film-test")


func _arrived(from: Vector3,to: Vector3) -> bool:
	return (from-to).slide(Vector3.UP).length() < .09


func _input(g: Node3D, goal: Vector3, aim: Vector3, turn := .047, low := false) -> Dictionary:
	var offset: Vector3 = goal-g.lead.position
	var gaze: Vector3 = aim-g.camera.global_position
	var yaw_goal := atan2(-gaze.x,-gaze.z)
	var pitch_goal := atan2(gaze.y,Vector2(gaze.x,gaze.z).length())
	var yaw_delta := clampf(wrapf(yaw_goal-g.yaw,-PI,PI),-turn,turn)
	var pitch_delta := clampf(pitch_goal-g.pitch,-turn,turn)
	var delta := offset.slide(Vector3.UP)
	var walk := delta.normalized() * minf(1.0,delta.length()*12.0) if delta.length() > .024 else Vector3.ZERO
	walk = walk.rotated(Vector3.UP,-(g.yaw+yaw_delta))
	return {"walk":Vector2(walk.x,walk.z),"look":Vector2(yaw_delta,pitch_delta),"low":low}
