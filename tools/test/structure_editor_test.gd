extends SceneTree
## Editable level pieces beyond walls and floors (phases B–E), headless logic checks:
## columns, arches, colonnades, assemblies with exposed parameters, stairs and stations on
## the shared plan interface, triggers with ordered actions, movers, the level manifest,
## click-selection adoption of generated meshes, and the cheap scene-exit path.
## The plan tab and 3D handles are checked in a real editor window (tools-guide §8).

const Structure := preload("res://scenes/components/structure/LevelStructure3D.gd")
const Queue := preload("res://scenes/components/structure/StructureRebuildQueue.gd")
const Piece := preload("res://scenes/components/structure/StructurePiece3D.gd")
const Wall := preload("res://tools/building_construction/BuildingConstruction/Walls/SmartWall3D.gd")
const FloorZone := preload("res://tools/building_construction/BuildingConstruction/Floors/SmartFloorZone3D.gd")
const Stair := preload("res://tools/building_construction/BuildingConstruction/Stairs/SmartStair3D.gd")
const Station := preload("res://scenes/components/structure/LevelStation3D.gd")
const Column := preload("res://scenes/components/structure/StructureColumn3D.gd")
const Arch := preload("res://scenes/components/structure/StructureArch3D.gd")
const Colonnade := preload("res://scenes/components/structure/Colonnade3D.gd")
const Assembly := preload("res://scenes/components/structure/StructureAssembly3D.gd")
const Trigger := preload("res://scenes/components/structure/LevelTrigger3D.gd")
const Mover := preload("res://scenes/components/structure/LevelMover3D.gd")
const Adopt := preload("res://addons/archbuilder/structure_adopt.gd")
const Audit := preload("res://scenes/components/shared/AcademyLevelAudit.gd")

var failed := 0

func check(ok: bool, label: String) -> void:
	print(("PASS " if ok else "FAIL ") + label)
	if not ok:
		failed += 1

func _initialize() -> void:
	run.call_deferred()

func meshes(n: Node) -> Array:
	return n.find_children("*", "MeshInstance3D", true, false)

func tris(n: Node) -> int:
	var t := 0
	for mi: MeshInstance3D in meshes(n):
		if mi.mesh:
			for s in mi.mesh.get_surface_count():
				t += mi.mesh.surface_get_arrays(s)[Mesh.ARRAY_VERTEX].size() / 3 if mi.mesh is ArrayMesh else 1
	return t

## Stand-in level: answers _on_level_action / play_dialogue like AcademyLevelBase.
class FakeLevel extends Node3D:
	var actions: Array = []
	var lines: Array = []
	var unlocked_flags := {}
	func _on_level_action(action_id: String, _ctx: Dictionary) -> void: actions.append(action_id)
	func play_dialogue(id: String) -> bool: lines.append(id); return true

func run() -> void:
	var level := FakeLevel.new()
	level.name = "Level"
	root.add_child(level)
	var s: Node3D = Structure.new()
	s.name = "Structure"
	level.add_child(s)
	s.owner = level

	# ── columns ────────────────────────────────────────────────────────────────
	var col: Node3D = Column.new()
	col.position = Vector3(2, 0, 2)
	s.add_child(col)
	col.owner = level
	await process_frame
	check(meshes(col).size() >= 3 and col.find_child("Collision", true, false) != null, "column builds base, shaft, capital and a collider")
	check(col.snap_targets()[0].is_equal_approx(Vector2(2, 2)), "column centre is a snap point")
	col.set_plan_handle(&"radius", Vector2(2.6, 2))
	check(is_equal_approx(col.radius, 0.6), "radius handle sets the radius (%.2f)" % col.radius)
	for style in Column.Style.values():
		col.style = style
		col.rebuild()
		check(meshes(col).size() >= 3, "column style %d builds" % style)

	# ── arches ─────────────────────────────────────────────────────────────────
	var arch: Node3D = Arch.new()
	arch.position = Vector3(4, 0, 2)
	arch.end_point = Vector3(3, 0, 0)
	s.add_child(arch)
	await process_frame
	for profile in Arch.Profile.values():
		arch.profile = profile
		arch.rebuild()
		var mi: MeshInstance3D = arch.find_child("Arch", true, false)
		var aabb := mi.get_aabb() if mi else AABB()
		var crown: float = arch.spring_height + (0.0 if profile == Arch.Profile.FLAT else arch.rise) + arch.band
		check(mi != null and absf(aabb.end.y - crown) < 0.05 and aabb.position.y <= 0.01, "arch profile %d: jambs from the floor, crown at %.2f m (mesh top %.2f)" % [profile, crown, aabb.end.y])
	arch.fill_to = 5.0
	arch.rebuild()
	check(absf((arch.find_child("Arch", true, false) as MeshInstance3D).get_aabb().end.y - 5.0) < 0.01, "spandrel fill reaches fill_to")
	check(arch.find_child("Collision", true, false) != null, "arch has a collider")
	arch.set_plan_handle(&"end", Vector2(9, 2))
	check(arch.end_point.is_equal_approx(Vector3(5, 0, 0)), "arch end handle moves the end point")
	arch.profile = Arch.Profile.POINTED
	check(absf(arch.curve_y(0.0, 2.0) - arch.rise) < 0.001 and arch.curve_y(1.0, 2.0) < 0.001, "arch curve: crown at rise, zero at the springing")

	# ── colonnade (several structures as one node with exported parameters) ───
	var row: Node3D = Colonnade.new()
	row.position = Vector3(0, 0, 8)
	row.end_point = Vector3(10, 0, 0)
	row.bays = 4
	s.add_child(row)
	row.owner = level
	await process_frame
	await process_frame
	var cols := row.get_children().filter(func(n): return n is Column)
	var arches := row.get_children().filter(func(n): return n is Arch)
	check(cols.size() == 5 and arches.size() == 4, "colonnade builds bays+1 columns and bays arches (%d, %d)" % [cols.size(), arches.size()])
	check(cols.all(func(n): return n.has_meta(Piece.GENERATED_META)), "colonnade members are generated (never saved)")
	var before_capped: int = Queue.stats.capped
	row.bays = 2
	row.column_height = 3.2
	await process_frame
	await process_frame
	cols = row.get_children().filter(func(n): return n is Column and not n.is_queued_for_deletion())
	check(cols.size() == 3 and is_equal_approx(cols[0].height, 3.2), "changing the colonnade's parameters rebuilds its members")
	check(Queue.stats.capped == before_capped, "no runaway rebuild chain")
	check(Queue.query(s, Rect2(0, 7, 11, 2)).all(func(n): return not n.has_meta(Piece.GENERATED_META)), "generated members stay out of the neighbour index")

	# ── assembly with exposed parameters ───────────────────────────────────────
	var asm: Node3D = Assembly.new()
	asm.name = "Gate"
	asm.position = Vector3(14, 0, 2)
	s.add_child(asm)
	asm.owner = level
	var left: Node3D = Column.new(); left.name = "Left"; asm.add_child(left); left.owner = level
	var right: Node3D = Column.new(); right.name = "Right"; right.position = Vector3(3, 0, 0); asm.add_child(right); right.owner = level
	var top: Node3D = Arch.new(); top.name = "Top"; top.end_point = Vector3(3, 0, 0); top.jambs = false; asm.add_child(top); top.owner = level
	await process_frame
	asm.expose("height", "Left", "height")
	asm.expose("height", "Right", "height")
	asm.expose("height", "Top", "spring_height")
	asm.set("参数/height", 4.5)
	check(is_equal_approx(left.height, 4.5) and is_equal_approx(right.height, 4.5) and is_equal_approx(top.spring_height, 4.5), "one exposed parameter drives every bound member")
	check(asm.get_property_list().any(func(p): return p.name == "参数/height" and p.type == TYPE_FLOAT), "the parameter shows in the Inspector as 参数/height (float)")
	check(is_equal_approx(float(asm.get("参数/height")), 4.5), "reading the parameter returns its value")
	var packed: PackedScene = asm.to_packed_scene()
	check(packed != null and packed.get_state().get_node_count() == 4, "assembly packs as a reusable scene (root + 3 members, no generated meshes)")
	var again: Node3D = packed.instantiate()
	again.name = "Gate2"
	again.position = Vector3(20, 0, 2)
	s.add_child(again)
	await process_frame
	check(is_equal_approx(again.get_node("Left").height, 4.5), "an instance applies its saved parameter values on load")
	again.set("参数/height", 2.0)
	check(is_equal_approx(again.get_node("Top").spring_height, 2.0) and is_equal_approx(left.height, 4.5), "instances keep their own parameter values")
	check(asm.plan_outline().size() == 4 and Geometry2D.is_point_in_polygon(Vector2(15.5, 2), asm.plan_outline()), "assembly outline covers its members")

	# ── stairs and stations on the shared plan interface ───────────────────────
	var stair: Node3D = Stair.new()
	stair.position = Vector3(2, 0, 14)
	stair.end_point = Vector3(4, 2, 0)
	s.add_child(stair)
	await process_frame
	check(stair is Piece and stair.plan_handles().size() == 2 and stair.plan_kind() == "stair", "stairs use the plan interface (start / end handles)")
	stair.set_plan_handle(&"end", Vector2(8, 14))
	check(stair.end_point.is_equal_approx(Vector3(6, 2, 0)), "stair end handle keeps the rise (%s)" % str(stair.end_point))
	var st: Node3D = Station.new()
	st.position = Vector3(10, 0, 14)
	s.add_child(st)
	st.owner = level
	await process_frame
	st.set_plan_handle(&"corner", Vector2(11.5, 15))
	check(st.footprint.is_equal_approx(Vector2(2, 1.5)) and st.position.is_equal_approx(Vector3(10.5, 0, 14.25)), "station corner handle resizes with the opposite corner fixed (%s at %s)" % [str(st.footprint), str(st.position)])
	check(s.station_bounds().any(func(r): return r.is_equal_approx(Rect2(9.5, 13.5, 2, 1.5))), "resized station feeds station_bounds")

	# ── walls: doors and windows from the plan ─────────────────────────────────
	var w: Node3D = Wall.new()
	w.grid_snap = 0.0
	w.end_point = Vector3(6, 0, 0)
	w.position = Vector3(0, 0, 20)
	s.add_child(w)
	await process_frame
	w.add_opening_at(Vector2(2, 20), 0.9, 0.0, 2.1)
	w.add_opening_at(Vector2(4.5, 20.1), 1.2, 0.9, 2.1)
	check(w.openings.size() == 2 and is_equal_approx(float(w.openings[0].from), 1.55), "door and window placed where clicked")
	check(w.plan_handles().size() == 4, "each opening gets a plan handle")
	w.set_plan_handle(&"op0", Vector2(3, 20))
	check(is_equal_approx(float(w.openings[0].from), 2.55) and is_equal_approx(float(w.openings[0].to), 3.45), "opening handle slides the door along the wall")
	w.plan_remove_handle(&"op1")
	check(w.openings.size() == 1, "an opening can be removed")
	var f: Node3D = FloorZone.new()
	s.add_child(f)
	await process_frame
	check(f.plan_insert_handle(Vector2(0, -3.05)) and f.polygon.size() == 5, "a floor vertex is inserted on the nearest edge")
	check(f.plan_remove_handle(&"v1") and f.polygon.size() == 4, "a floor vertex is removed")

	# ── movers ─────────────────────────────────────────────────────────────────
	var mover: Node3D = Mover.new()
	mover.name = "Portcullis"
	mover.position = Vector3(8, 0, 24)
	mover.duration = 0.2
	s.add_child(mover)
	mover.owner = level
	var bars := MeshInstance3D.new()
	bars.name = "Bars"
	bars.mesh = BoxMesh.new()
	mover.add_child(bars)
	bars.owner = level
	await process_frame
	check(mover.plan_open_outline().size() == 4, "mover shows its open pose on the plan")

	# ── triggers and actions ───────────────────────────────────────────────────
	var lamp := OmniLight3D.new()
	lamp.name = "Lamp"
	s.add_child(lamp)
	lamp.owner = level
	var trig: Node3D = Trigger.new()
	trig.name = "GateTrigger"
	trig.trigger_id = "trg_gate"
	trig.position = Vector3(8, 0, 22)
	trig.action_id = "gate_opened"
	trig.dialogue_id = "dlg_gate"
	trig.condition = "首次走到闸门前"
	var a1 := SetPropertyAction.new(); a1.target = NodePath("../Lamp"); a1.property = "light_energy"; a1.value = "3.5"
	var a2 := MoverAction.new(); a2.mover = NodePath("../Portcullis"); a2.command = MoverAction.Command.OPEN; a2.wait = true
	var a3 := TweenPropertyAction.new(); a3.target = NodePath("../Lamp"); a3.property = "position:y"; a3.to = "2.0"; a3.duration = 0.1
	var a4 := LevelEventAction.new(); a4.action_id = "second_beat"; a4.set_flag = "gate_seen"
	var acts: Array[LevelAction] = [a1, a2, a3, a4]
	trig.actions = acts
	s.add_child(trig)
	trig.owner = level
	await process_frame
	check(trig.find_child("Zone", true, false) is Area3D, "zone trigger builds its Area3D")
	var heard := []
	s.trigger_fired.connect(func(id, act, _ctx): heard.append([id, act]))
	var stranger := Node3D.new()
	trig._on_body(stranger, true)
	check(trig.fire_count == 0, "bodies outside body_group do not fire it")
	var player := Node3D.new()
	player.add_to_group("player")
	trig._on_body(player, true)
	await create_timer(1.5).timeout
	check(is_equal_approx(lamp.light_energy, 3.5), "SetPropertyAction set the lamp energy")
	check(mover.is_open and bars.position.is_equal_approx(Vector3(0, 2.5, 0)), "MoverAction opened the portcullis (bars at %s)" % str(bars.position))
	check(is_equal_approx(lamp.position.y, 2.0), "TweenPropertyAction animated the lamp")
	check(level.actions == ["gate_opened", "second_beat"] and level.lines == ["dlg_gate"] and level.unlocked_flags.get("gate_seen", false), "level heard the action ids, dialogue and flag (%s)" % str(level.actions))
	check(heard == [["trg_gate", "gate_opened"]], "structure emitted trigger_fired")
	trig._on_body(player, true)
	await process_frame
	check(trig.fire_count == 1, "once = fires a single time")
	mover.close()
	await create_timer(0.6).timeout
	check(bars.position.is_equal_approx(Vector3.ZERO), "mover closes back to rest")
	var manifest := {"level_id": "t", "title": "t", "objects": [], "interactables": [], "dialogues": [{"id": "dlg_gate", "speaker": "hale", "text_zh": "门开了。", "text_en": "The gate is open."}],
		"triggers": s.trigger_manifest(), "ai_routes": []}
	var report: Dictionary = Audit.validate_manifest(manifest)
	check(s.trigger_manifest().size() == 1 and s.trigger_manifest()[0].how != "", "trigger appears in the manifest with its mechanism")
	check(not report.errors.any(func(e): return "Trigger" in str(e) or "trigger" in str(e)), "trigger manifest entry passes the level audit (%s)" % str(report.errors))

	# ── click selection: generated meshes are adopted by their piece ───────────
	var adopted := Adopt.sweep(level)
	var col_mesh: MeshInstance3D = meshes(col)[0]
	check(adopted > 0 and col_mesh.owner == col and col_mesh.has_meta(Adopt.META), "generated meshes are adopted by their piece (%d)" % adopted)
	check(bars.owner == level, "authored meshes keep their scene owner")
	var shaft_owner := (meshes(row)[0] as Node).owner
	check(shaft_owner == row, "meshes of generated members select the colonnade itself")
	col.rebuild()
	check(not meshes(col).any(func(m): return m == col_mesh and not m.is_queued_for_deletion()), "adopted meshes are still cleared on rebuild")
	var packed_level := PackedScene.new()
	packed_level.pack(level)
	var state := packed_level.get_state()
	var saved_names: Array = []
	for i in state.get_node_count():
		saved_names.append(str(state.get_node_name(i)))
	check(not ("Shaft" in saved_names) and "Bars" in saved_names, "adopted meshes are never saved; authored ones are")

	# ── leaving the tree is cheap (tab switch / close) ─────────────────────────
	Queue.force_editor_rules = true
	var big: Node3D = Structure.new()
	root.add_child(big)
	for i in 150:
		var piece: Node3D = Wall.new()
		piece.grid_snap = 0.0
		piece.start_point = Vector3(i * 0.5, 0, 0)
		piece.end_point = Vector3(i * 0.5, 0, 3)
		big.add_child(piece)
	await process_frame
	var t := Time.get_ticks_usec()
	root.remove_child(big)
	var exit_ms := (Time.get_ticks_usec() - t) / 1000.0
	await process_frame
	check(exit_ms < 60.0, "removing 150 pieces from the tree takes %.1f ms (no per-piece index rebuild)" % exit_ms)
	root.add_child(big)
	await process_frame
	big.get_child(0).queue_free()
	await process_frame
	await process_frame
	check(Queue.stats.last_rebuilds >= 1, "deleting one piece still updates its neighbours")
	Queue.force_editor_rules = false
	big.queue_free()

	print("STRUCTURE_EDITOR_SUMMARY failed=%d" % failed)
	quit(0 if failed == 0 else 1)
