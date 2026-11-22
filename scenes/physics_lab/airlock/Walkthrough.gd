extends RefCounted
## Opt-in camera/input score. It produces the same move, relative look,
## crouch and talk commands used by a human; only the controller moves bodies.
const Room = preload("res://scenes/physics_lab/airlock/Room.gd")
var phase := 0
var since := 0
var failed := false
var variant := "clear"
var withdrew := false
var panic_recovered := false
var false_turn_at := -1
var left_cover := false
var public_signal := -1
var rejected_at := 0
var agreement_at := 0
var dark_at := 0
var panic_retry := false


func _init() -> void:
	var audit_case := OS.get_environment("DUAL_AIRLOCK_AUDIT_CASE")
	if not audit_case.is_empty(): variant = audit_case
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--airlock-case="): variant = arg.trim_prefix("--airlock-case=")


func command(game: Node3D) -> Dictionary:
	var age: int = game.tick - since
	if failed or phase >= 17: return {}
	if age > 590:
		failed = true
		game.film_failed = "WALKTHROUGH STUCK step %d: %s" % [phase, JSON.stringify(game.mcp_observe())]
		printerr(game.film_failed)
		if _cli(): game.get_tree().quit(2)
		return {}
	var p: Vector3 = game.lead.position
	var near_aim := Vector3(-.02,0,-2.18)
	var hale_face: Vector3 = game.hale.position+Vector3.UP*1.55
	var landing := Room.FAR_SECOND if variant == "alternate" else Room.FAR_WATCH
	var concealed := variant in ["early","blocked"] and not left_cover
	if concealed: landing = Room.FAR_HIDDEN
	var back := landing + Vector3(0,1.56,2.0)
	var side := p + Vector3(-.51,0,.86)*3.0 + Vector3.UP*1.58
	match phase:
		0:
			if age >= 105: _next(game)
			var cmd := _input(game,Vector3(-.16,0,2.34),Room.A_AIM,.041)
			cmd.book = age >= 45 and age < 96
			return cmd
		1:
			if game.role == "WAIT_B": _next(game)
			return _input(game,Vector3(.39,0,.51),near_aim,.043)
		2:
			var pos := Vector3(.04,0,-2.91)
			if _arrived(p,pos): _next(game)
			return _input(game,pos,near_aim if p.z > -1.72 else Vector3(.04,0,-3.35))
		3:
			var pos := Vector3(.82,0,Room.B_LANE)
			if dark_at == 0 and game.attempted_tread: dark_at = game.tick
			if _arrived(p,pos) and dark_at > 0 and game.tick-dark_at > 19: _next(game)
			return _input(game,pos,Vector3(1.8,.02,Room.B_LANE),.063)
		4:
			if game.role == "TRIAL_WAIT": _next(game)
			var out := _input(game,Room.ISLAND_TRIAL,hale_face,.055)
			out["talk"] = _arrived(p,Room.ISLAND_TRIAL) and age % 14 == 0
			return out
		5:
			if game.rule.counterexample and not game.rule.distorted: _next(game)
			if variant == "death" and game.failed == "DOUBLE_GAZE":
				if age > 180: _finish(game)
				return {}
			if variant == "panic" and not panic_retry and game.role == "WAIT_B" and game.rule.distorted:
				panic_retry = true
				withdrew = false
				phase = 4
				since = game.tick
			var aim := Room.B_AIM
			var trial_age: int = game.tick-game.trial_at
			if variant == "panic" and not panic_retry:
				if trial_age in range(65,83) or (game.rule.distorted and trial_age in range(110,139)): aim = hale_face
				if game.red_after_panic and (game.spans[1].red >= 13 or withdrew):
					withdrew = true
					aim = hale_face
			elif variant == "solo": aim = hale_face
			elif variant != "death":
				if game.spans[1].red >= 16: withdrew = true
				if withdrew or trial_age > 82: aim = hale_face
			return _input(game,Room.ISLAND_TRIAL,aim,.18)
		6:
			if game.rule.revised and game.role == "WATCH_B" and game.deck[1]: _next(game)
			var out := _input(game,Room.ISLAND_TRIAL,hale_face,.085)
			if not game.rule.revised and not game.offer_open: out.talk = age > 24 and age % 12 == 0
			if game.offer_open:
				if agreement_at == 0: agreement_at = game.tick
				if rejected_at == 0 and game.tick-agreement_at > 18:
					out.offer = 2
					rejected_at = game.tick
				elif rejected_at > 0 and game.tick-rejected_at > 32: out.offer = 1
			return out
		7:
			var pos := Vector3(.74,0,Room.B_LANE)
			if _arrived(p,pos): _next(game)
			return _input(game,pos,Vector3(5.25,.31,Room.B_LANE),.068)
		8:
			var pos := Vector3(1.95,0,Room.B_LANE)
			if _arrived(p,pos): _next(game)
			return _input(game,pos,Vector3(5.25,.35,Room.B_LANE),.041,true)
		9:
			var pos := Vector3(6.16,0,Room.B_LANE)
			if _arrived(p,pos): _next(game)
			var aim := Vector3(7.41,1.02,-3.95)
			if p.x > 4.55:
				if variant in ["early","recoil"]: aim = Vector3(6.0,1.4,-8.0)
				elif variant == "blocked": aim = side
			return _input(game,pos,aim,.066)
		10:
			if _arrived(p,landing): _next(game)
			return _input(game,landing,Room.B_AIM if variant in ["early","recoil"] else (side if variant == "blocked" else back),.078)
		11:
			if variant == "blocked" and not left_cover:
				if age >= 91: left_cover = true
				return _input(game,p,back)
			if variant == "recoil" and not left_cover:
				if game.role == "RETRY_B": left_cover = true
				return _input(game,p,Room.B_AIM,.067)
			if variant == "early":
				if game.failed == "DOUBLE_GAZE" and age > 108: _finish(game)
				return _input(game,p,Room.B_AIM,.068)
			if variant == "late":
				if game.failed == "FALL" and age > 200: _finish(game)
				return _input(game,p,Room.B_AIM if game.failed == "FALL" else back,.083)
			if variant == "public":
				if public_signal < 0 and game.subtitle.text == "[A knock.]": public_signal = game.tick
				if public_signal >= 0 and game.tick-public_signal >= 13: _next(game)
			elif game.spans[1].dark >= 7 and game.role in ["B_LINE","CROSS_B"]: _next(game)
			return _input(game,landing,back)
		12:
			if game.role == "FAR": _next(game)
			return _input(game,p,Room.B_AIM,game.KEY_LOOK_SPEED*game.STEP if variant == "public" else .118)
		13:
			var pos := Vector3(7.13,0,-3.95)
			if _arrived(p,pos): _next(game)
			return _input(game,pos,Vector3(7.9,1.33,-3.95),.047)
		14:
			if game.cleared: _next(game)
			return _input(game,Vector3(7.86,0,-3.95),Vector3(8.04,1.35,-3.95))
		15:
			if age > 142: _finish(game)
			return _input(game,p,hale_face,.058)
	return {}


func _finish(game: Node3D) -> void:
	phase = 17
	print("OBSERVER_AIRLOCK_RESULT ",JSON.stringify(game.mcp_observe()))
	if _cli(): game.get_tree().quit()


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
