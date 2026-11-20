extends SceneTree
## Exercise the actual pivots, imported tooth tips and banked pallet faces in cage space.
const Watch = preload("res://scenes/blue_prince_lab/studies/Meridian.gd")
var errors := 0

func _initialize() -> void: call_deferred("run")

func check(ok: bool, message: String) -> void:
	if not ok:
		push_error(message)
		errors += 1

func sampled(w: Watch, time: float) -> void:
	w.elapsed = 0
	w._process(time)

func pose(w: Watch) -> Array:
	var result := []
	for n: Node3D in [w.hour,w.minute,w.yaw,w.pitch,w.roll,w.transfer,w.planet,w.escape,w.lever,w.oscillator]:
		result.append(n.global_transform)
	result.append(w.spring.finish.get_shader_parameter("balance_angle"))
	return result

func check_contact(w: Watch, degrees: float) -> void:
	var contact := Vector2(.30,.18) + Vector2.RIGHT.rotated(deg_to_rad(degrees))*(.126+.48*.252/15.)
	for part: Node3D in [w.escape,w.lever]:
		var nearest := INF
		for inst: MeshInstance3D in part.find_children("*","MeshInstance3D",true,false):
			for i in inst.mesh.get_surface_count():
				var vertices: PackedVector3Array = inst.mesh.surface_get_arrays(i)[Mesh.ARRAY_VERTEX]
				for v in vertices:
					var p := w.roll.to_local(inst.to_global(v))
					if p.z > .044 and p.z < .066:
						nearest = minf(nearest,contact.distance_to(Vector2(p.x,p.y)))
		# Pallet's two locking-face corners are ±.007 from the contact midpoint.
		check(nearest < (.0005 if part == w.escape else .0075), "%s misses banked tooth (%s)" % [part.name,nearest])

func run() -> void:
	var w := Watch.new()
	root.add_child(w)
	w.set_process(false)
	check(w.roll.get_parent()==w.pitch and w.pitch.get_parent()==w.yaw, "cage nesting")
	check(w.roll.is_ancestor_of(w.escape) and w.roll.is_ancestor_of(w.lever) and w.spring.get_parent()==w.roll, "escapement frame")
	check(w.transfer.get_parent()==w.pitch and w.pitch.has_node("FixedSun") and w.yaw.has_node("FixedBevel"), "stationary gear frames")
	check(is_equal_approx(w.planet.position.length(),.24+.06) and is_equal_approx(w.planet.position.distance_to(w.escape.position),.12+.06), "pitch circles")
	var case_pose := (w.get_node("Case") as Node3D).global_transform
	sampled(w,0)
	check_contact(w,240)
	var bank := w.lever.rotation.z
	sampled(w,.07)
	check(is_zero_approx(w.escape.rotation.z) and is_equal_approx(w.lever.rotation.z,bank), "entry lock")
	sampled(w,1./12.)
	check(absf(w.oscillator.rotation.z)<.0001 and absf(w.lever.rotation.z)<.0001, "fork changes bank at balance neutral")
	sampled(w,1./6.)
	check_contact(w,156)
	check(is_equal_approx(w.escape.rotation.z,-TAU/30.) and is_equal_approx(w.lever.rotation.z,-bank), "half tooth, exit lock")
	sampled(w,1./3.)
	check_contact(w,240)
	check(is_equal_approx(w.escape.rotation.z,-TAU/15.) and is_equal_approx(w.lever.rotation.z,bank), "one tooth per oscillation")
	check(is_equal_approx(w.spring.finish.get_shader_parameter("balance_angle"), w.oscillator.rotation.z), "spring collet follows balance")
	check(is_equal_approx(w.escape.rotation.z,-2*w.planet.rotation.z) and is_equal_approx(w.planet.rotation.z,4*w.roll.rotation.z), "sun/planet and escape mesh")
	check(is_equal_approx(w.transfer.rotation.z,6*w.pitch.rotation.x) and is_equal_approx(w.roll.rotation.z,-1.5*w.transfer.rotation.z), "bevel and transfer mesh")
	check((w.get_node("Case") as Node3D).global_transform == case_pose, "case moved")
	var stats := w.mesh_stats()
	check(stats.triangles <= w.TRIANGLE_BUDGET and stats.moving_triangles <= w.MOVING_BUDGET and stats.surfaces <= w.SURFACE_BUDGET, "watch budget")
	var p := pose(w)
	w.interact(); w._process(30.)
	check(pose(w)==p, "paused movement drifted")
	w.interact()
	sampled(w,43201.125)
	var one := pose(w)
	sampled(w,43199.875)
	for i in 60: w._process(1.0/48.)
	var many := pose(w)
	for i in one.size()-1: check(one[i].is_equal_approx(many[i]), "chunk / wrap mismatch at %s" % i)
	check(is_equal_approx(one.back(),many.back()), "spring wrap")
	print("Measured watch: ", stats, "; movement errors: ", errors)
	w.free()
	quit(1 if errors else 0)
