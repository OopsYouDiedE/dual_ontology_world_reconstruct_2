extends RefCounted
## Optional movie director; consumes the very same worker step path as live play.

var rows: Array
var policy: String
var output: String
var index := 0
var frame := 0
var left := 44
var span := 44
var row := {}
var stills := {}
var actor := -1
var anchor := Vector3.ZERO
var camera := Vector3.ZERO
var shot_key := ""

func _init(path: String, receipt: String) -> void:
	var data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(path))
	rows = data.rows
	policy = str(data.policy).to_upper()
	output = receipt

func advance(scene: Node3D) -> void:
	if left == 0:
		if index == rows.size():
			var file := FileAccess.open(output, FileAccess.WRITE)
			file.store_string(JSON.stringify({"renderer":RenderingServer.get_current_rendering_method(),
				"packets":index,"state_sha256":scene._packet.get("film_state_sha256", ""),"status":scene._obs.status,"tick":scene._render.tick,"frames":frame,"stills":stills}, "\t"))
			scene.get_tree().quit()
			return
		row = rows[index]
		var previous: int = scene._level
		scene._send({"op":"step", "action":scene._as_integer_values(row.action)})
		if int(scene._render.tick) != int(row.tick):
			push_error("Movie replay tick mismatch at decision %d" % index)
			scene.get_tree().quit(2)
			return
		index += 1
		left = int(row.frames)
		span = left
		if scene._level != previous or int(row.actor) == 0 or 0 in row.moved:
			actor = -1
			shot_key = ""
		elif int(row.actor) > 0:
			actor = int(row.actor)
			if not str(row.target).is_empty():
				_compose(scene)
			elif shot_key.is_empty() or not shot_key.begins_with(str(actor) + ":"):
				_compose(scene)
		if int(row.actor) <= 0 and not str(row.caption).is_empty() and str(row.caption).contains(" · "):
			actor = -1
		scene._subhead.text = "%s REPLAY  /  SEED %s     |     TICK %04d     |     DECISION %03d/%03d" % [
			policy, str(scene._film_seed), int(scene._render.tick), index, rows.size()]
	if row.is_empty():
		scene._footer.text = "FIELD RECORD  /  VERIFIED EXPEDITION REPLAY"
	else:
		var source := "COMPANION CAMERA" if actor > 0 else "LEAD CAMERA"
		var caption := str(row.caption)
		scene._footer.text = "FIELD RECORD  /  %s" % source if caption.is_empty() else "%s     |     %s" % [source, caption]
	if actor > 0 and scene._actors.has(actor):
		var member: Node3D = scene._actors[actor].root
		member.show()
		scene._view.fov = 63.0
		scene._view.position = camera
		if not camera.is_equal_approx(anchor): scene._view.look_at(anchor)
	else:
		scene._view.fov = 72.0
		if row.get("proof", "") == "09-console-read" and scene._target_objects.has("reticle"):
			# Keep the actual crouched eye and include the lateral receiver and desk in one frame.
			var reticle: Vector3 = scene._target_objects.reticle
			scene._view.fov = 84.0
			scene._view.look_at(scene._view.position + Vector3(signf(reticle.x - scene._view.position.x) * 0.28, -0.07, 1.3))
	scene._focus_panel.hide()
	var elapsed := span - left
	if not row.is_empty() and not str(row.proof).is_empty():
		if elapsed == 2 and actor > 0:
			stills[str(row.proof) + "-motion-start"] = frame
		elif elapsed == 11:
			stills[str(row.proof)] = frame
	if elapsed == 22 and not stills.has("chamber-%02d" % scene._level):
		stills["chamber-%02d" % scene._level] = frame
	left -= 1
	frame += 1

func _compose(scene: Node3D) -> void:
	var person: Vector3 = scene._actor_targets[actor]
	var machine: Vector3 = scene._target_objects.get(row.target, person)
	var interesting := machine
	var best := INF
	for id: String in row.changes:
		if id == row.target: continue
		var position: Vector3 = scene._target_objects.get(id, machine)
		var distance := position.distance_to(machine)
		if distance < best:
			best = distance
			interesting = position
	var key := "%d:%s" % [actor, row.target]
	var focus := person.lerp(machine, 0.49).lerp(interesting, 0.42)
	focus.y = maxf(1.01, focus.y + 0.78)
	var side := signf(person.x) if absf(person.x) > 0.40 else 1.0
	var width := float(scene._render.size[0]) * 0.0005
	var depth := float(scene._render.size[1]) * 0.001
	var distance := clampf(maxf(person.distance_to(machine), person.distance_to(interesting)) * 0.36 + 1.85, 2.45, 3.65)
	var best_score := -1
	for shoulder: float in [side, -side]:
		var eye := focus + Vector3(shoulder * 1.78, 0.65, -distance)
		if person.z > 3.8: eye.z = maxf(2.32, eye.z)
		eye.x = clampf(eye.x, -width + 0.43, width - 0.43)
		eye.z = clampf(eye.z, 0.4, depth - 0.4)
		var score := _sightline_score(scene, eye, person + Vector3.UP * 1.18, machine, interesting)
		if score > best_score:
			best_score = score
			camera = eye
	anchor = focus
	shot_key = key

func _sightline_score(scene: Node3D, eye: Vector3, person: Vector3, machine: Vector3, load: Vector3) -> int:
	var control_height := 1.15
	for e: Dictionary in scene._render.get("entities", []):
		if e.entity_id == row.target:
			control_height = float(e.primitive_geometry.size[1]) * 0.00081
			break
	var probes := [person, machine + Vector3.UP * control_height, load + Vector3.UP * 0.4,
		machine + Vector3.UP * control_height * 0.67]
	var weights := [4, 4, 2, 2]
	for e: Dictionary in scene._render.get("entities", []):
		if e.entity_id == row.target or e.entity_class not in ["counterweight", "carriage", "shutter", "divider", "frame"]:
			continue
		var dims: Vector3 = scene._point(e.primitive_geometry.size)
		var origin: Vector3 = scene._point(e.primitive_geometry.position) - Vector3(dims.x / 2.0, 0.0, dims.z / 2.0)
		var bounds := AABB(origin, dims)
		# An endpoint inside its own load is visible when its nearest face is visible.
		for i in range(probes.size()):
			if not bounds.has_point(probes[i]) and bounds.intersects_segment(eye, probes[i]) != null:
				weights[i] = 0
	return weights[0] + weights[1] + weights[2] + weights[3]
