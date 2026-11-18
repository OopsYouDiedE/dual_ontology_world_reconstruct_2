extends SceneTree
## Geometry contracts for the late-game paths that feed story gates.
const Main := preload("res://scenes/dual_world/DualWorldMain.tscn")
const Approach := preload("res://scenes/components/interaction/InteractionApproach.gd")
var failures := 0

func _initialize() -> void:
	call_deferred("run")

func check(ok: bool, detail: String) -> void:
	if not ok:
		failures += 1
		printerr("FAIL: " + detail)

func stage(host, room: String, next_beat: String, at: float) -> void:
	host.eng.s.chapter = 2
	host.eng.s.room = room
	host.eng.s.t = at
	host.eng.s.beat_cursor = host.data.beat_index_by_id[next_beat]
	host.eng.s.playing = false
	host._build_room(room)
	host._det_to_home()

func run() -> void:
	var host = Main.instantiate()
	root.add_child(host)
	stage(host, "B2-valve", "d4_deduce_valve", 5375.0)
	check(host.figures.size() == 4, "all witnesses are visible in the valve gallery")
	for a: Node3D in host.figures.values():
		for b: Node3D in host.figures.values():
			if a == b: continue
			check(a.position.distance_to(b.position) >= host.ACTOR_MIN_DISTANCE - 0.001, "valve gallery witnesses have clearance")
	var valve: Node3D = host.room_mesh.evidence_nodes["e_v_valve"]
	var valve_point := Vector2(valve.global_position.x, valve.global_position.z)
	check(Approach.plan(host, valve_point, "", host.det_pos).ok, "player can approach the valve evidence with all witnesses in the room")
	stage(host, "N01", "d5_final", 6510.0)
	var door: Dictionary = host._door_for(host.room_mesh.design, host._room_dir("N01", "2F-cross-M"))
	check(not door.is_empty() and host._det_can_occupy(door.inner), "archive doorway approach clears the moved column")
	host.queue_free()
	await process_frame
	print("RESULT story_navigation failures=%d" % failures)
	quit(0 if failures == 0 else 1)
