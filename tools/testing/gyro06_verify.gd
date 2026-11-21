extends SceneTree
## Native headless check for the real architecture, rotor and directional light ray.
const SCENE := preload("res://scenes/rubber_whitebox/gyro06/Gyro06.tscn")
const G := preload("res://scenes/rubber_whitebox/gyro06/FoundryMesh.gd")
var room: Node3D
var failures := PackedStringArray()

func _initialize() -> void:
	verify.call_deferred()

func check(ok: bool, label: String) -> void:
	if not ok:
		failures.append(label)
		push_error(label)

func hit(from: Vector3, to: Vector3, mask: int) -> Dictionary:
	return room.get_world_3d().direct_space_state.intersect_ray(PhysicsRayQueryParameters3D.create(from,to,mask,[room.player.get_rid()]))

func verify() -> void:
	room = SCENE.instantiate()
	root.add_child(room)
	room.running = false
	var apertures := {}
	for seed in range(1,13):
		room.build_06_art(seed)
		apertures[room.hole_count] = true
		check(room.rotor_shapes.size()>100,"seed %d has native rotor faces" % seed)
		var first: Basis = room.rotor_basis(0)
		var last: Basis = room.rotor_basis(600)
		check(is_equal_approx(first.y.y,last.y.y) and Vector2(first.y.x+last.y.x,first.y.z+last.y.z).length()<0.0001,
			"seed %d half-cycle reverses axis" % seed)
		var tilt := rad_to_deg(first.y.angle_to(Vector3.UP))
		check(is_equal_approx(tilt,24.0),"seed %d tilt" % seed)
		var min_y := INF
		var max_y := -INF
		var max_radius := 0.0
		# Every rendered bronze/iron triangle has an equal native triangle surface on the spinner.
		for child in room.wheel.get_children():
			if child is MeshInstance3D:
				for face in child.mesh.get_faces():
					if Vector2(face.x,face.z).length() > 9.50:
						max_radius = maxf(max_radius,Vector2(face.x,face.z).length())
						var height: float = (first*face).y + room.PIVOT_Y
						min_y = minf(min_y,height)
						max_y = maxf(max_y,height)
		if seed == 6:
			print("Seed 6: rotor %.2f m; measured rim extrema %.3f m and %.3f m" % [max_radius*2.0,min_y,max_y])
		check(absf(max_radius-9.92)<0.002 and min_y > 0.48 and min_y < 0.90 and max_y > 8.50,
			"seed %d measures diameter and rim heights: %f / %f / %f" % [seed,max_radius*2,min_y,max_y])
	check(apertures.size() == 3,"seeds cover 2, 3 and 4 actual openings")
	room.build_06_art(6)
	room.set_step(0)
	await physics_frame
	await physics_frame
	var high := G.radial(room.phase+PI)
	var low := -high
	var low_path := hit(low*11.63+Vector3.UP*1.04, low*8.6+Vector3.UP*1.04, 2)
	check(not low_path.is_empty(),"floor capsule is blocked on low side")
	check(hit(high*11.38+Vector3.UP*1.65,high*6.38+Vector3.UP*1.65,3).is_empty(),"B has five clear metres")
	check(not hit(high*6.89+Vector3.UP*7.45,high*6.89+Vector3.UP*9.52,2).is_empty(),"raised rotor enters upper approach volume")
	check(hit(low*6.89+Vector3.UP*7.45,low*6.89+Vector3.UP*9.52,2).is_empty(),"low side upper approach is open")
	var initial_bridge := [room.bridges[0].position,room.bridges[1].position]
	var spots: Array[Vector3] = []
	for i in 48:
		var p := G.radial(TAU*i/48.0)*5.4
		if not room.top_light_reaches(p):
			spots.append(p)
	check(spots.size() > 5 and spots.size() < 38,"floor contains direct light and real blocked shadow")
	room.set_step(600)
	await physics_frame
	await physics_frame
	var lit_after := 0
	for p in spots:
		if room.top_light_reaches(p):
			lit_after += 1
	check(lit_after >= 3,"actual hard shadow moves at half-cycle")
	check(hit(low*11.63+Vector3.UP*1.04,low*8.6+Vector3.UP*1.04,2).is_empty(),"previous low approach clears")
	check(not hit(high*11.63+Vector3.UP*1.04,high*8.6+Vector3.UP*1.04,2).is_empty(),"previous high approach is blocked")
	check(initial_bridge[0].length() > room.bridges[0].position.length() and initial_bridge[1].length() < room.bridges[1].position.length(),"upper approaches swap")
	room.set_step(0)
	room.hide_gyro(true)
	await physics_frame
	await physics_frame
	check(hit(low*11.63+Vector3.UP*1.04,low*8.6+Vector3.UP*1.04,2).is_empty(),"hide removes native rotor collision")
	for p in spots:
		check(room.top_light_reaches(p),"hide removes rotor's light occlusion at %s" % p)
	await walk_stair()
	await walk_bridge()
	await check_external_glb()
	if failures.is_empty():
		print("PASS Gyro06: seeds 1–12, native collisions and light rays, half-cycle reversal, walkable stair and bridge, external GLB roundtrip")
	quit(0 if failures.is_empty() else 1)

func walk_toward(target: Vector3) -> void:
	var direction := target - (room.player.position as Vector3)
	room.player.rotation.y = atan2(-direction.x,-direction.z)

func walk_stair() -> void:
	# Start at the lower aisle and climb the full flight using controller input and gravity.
	var a: float = room.stair_angle
	const LANE := 12.38
	room.player.position = G.radial(a-0.045)*LANE+Vector3.UP*0.015
	room.player.velocity = Vector3.ZERO
	await physics_frame
	Input.action_press("gyro_forward")
	for i in 335:
		var p: Vector3 = room.player.position
		var theta := atan2(p.z,p.x)
		if wrapf(theta-a,-PI,PI) >= room.stair_span+0.085:
			break
		walk_toward(G.radial(theta+0.047)*LANE)
		await physics_frame
	check(room.player.position.y > 6.96,"native 1.75m actor climbs 7m: %s" % room.player.position)
	var theta := atan2(room.player.position.z,room.player.position.x)
	for i in 46:
		if Vector2(room.player.position.x,room.player.position.z).length() < 11.15:
			break
		walk_toward(G.radial(theta)*10.94)
		await physics_frame
	Input.action_release("gyro_forward")
	check(room.player.position.y > 6.96 and Vector2(room.player.position.x,room.player.position.z).length()<11.25,
		"landing connects to elevated inner ring: %s" % room.player.position)

func walk_bridge() -> void:
	var bridge: float = room.bridge_angles[1]
	Input.action_press("gyro_forward")
	for i in 390:
		var p: Vector3 = room.player.position
		var here := atan2(p.z,p.x)
		var remaining := wrapf(bridge-here,-PI,PI)
		if absf(remaining)<0.005:
			break
		walk_toward(G.radial(here+clampf(remaining,-0.045,0.045))*11.02)
		await physics_frame
	for i in 75:
		if Vector2(room.player.position.x,room.player.position.z).length() <= 7.85:
			break
		walk_toward(G.radial(bridge)*7.45)
		await physics_frame
	Input.action_release("gyro_forward")
	check(absf(room.player.position.y-7.011)<0.035 and Vector2(room.player.position.x,room.player.position.z).length()<7.90,
		"actor can step onto the deployable bridge: %s" % room.player.position)
func check_external_glb() -> void:
	const FOLDER := "res://.runtime/gyro06"
	var target := ProjectSettings.globalize_path(FOLDER.path_join("geometry-fixture.glb"))
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(FOLDER))
	var fixture := Node3D.new()
	var translated := Node3D.new()
	fixture.add_child(translated)
	translated.position.x = 0.25
	for child in room.wheel.get_children():
		if child is MeshInstance3D:
			var instance := MeshInstance3D.new()
			instance.mesh = child.mesh
			translated.add_child(instance)
			instance.position.x = -0.25
	var state := GLTFState.new()
	var doc := GLTFDocument.new()
	var exported := doc.append_from_scene(fixture,state)==OK and doc.write_to_filesystem(state,target)==OK
	fixture.free()
	check(exported,"temporary GLB fixture writes")
	if not exported:
		return
	room.gyro_model_path = target
	room.gyro_model_source = "Procedural verification fixture (repository)"
	room.gyro_model_license = "Same terms as the repository"
	room.build_06_art(6)
	await physics_frame
	await physics_frame
	check(room.external_active and room.wheel.get_meta("model_source","")==room.gyro_model_source,
		"GLB geometry is loaded with provenance")
	var low := G.radial(room.phase)
	check(not hit(low*11.63+Vector3.UP*1.04,low*8.6+Vector3.UP*1.04,2).is_empty(),"imported triangles retain native rim contact")