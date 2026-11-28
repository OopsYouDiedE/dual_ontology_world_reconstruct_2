extends SceneTree
## Headless one-shot level diagnostic inspector used by `tools/inspect_level.py`.
## Dumps loaded level metadata, door/route topology, room objects, and all live
## DualModeInteractionHud interactable candidates as clean JSON.

const RunScene := preload("res://scenes/rogue/Run.tscn")
const SortieScene := preload("res://scenes/expedition_01/Sortie.tscn")
const R01Level := preload("res://scenes/levels/Chapter1R01Level.gd")

func _initialize() -> void:
	run.call_deferred()

func frames(n: int) -> void:
	for i in n:
		await process_frame

func _vec_arr(v: Vector3) -> Array:
	return [snappedf(v.x, 0.01), snappedf(v.y, 0.01), snappedf(v.z, 0.01)]

func _extract_candidates(dual_ui) -> Array:
	var out := []
	if not is_instance_valid(dual_ui):
		return out
	var snap: Dictionary = dual_ui.get_state_snapshot()
	var d_states: Dictionary = snap.get("detroit_states", {})
	for g in dual_ui.groups:
		var gid := str(g.get("id", ""))
		var hs_out := []
		for h in g.get("hotspots", []):
			var hid := str(h.get("id", ""))
			hs_out.append({
				"id": hid,
				"part_name": str(h.get("part_name", "")),
				"verb": str(h.get("verb", "")),
				"world_pos": _vec_arr(h.get("world_pos", g.get("anchor_world", Vector3.ZERO))),
				"state": str(d_states.get(hid, "none")),
				"unlock_when": str(h.get("unlock_when", "default")),
			})
		out.append({
			"group_id": gid,
			"title": str(g.get("title", "")),
			"anchor_world": _vec_arr(g.get("anchor_world", Vector3.ZERO)),
			"hotspots": hs_out,
		})
	return out

func run() -> void:
	var scene_key := "hall"
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--scene="):
			scene_key = arg.get_slice("=", 1).to_lower()

	var report := {
		"main_scene_config": str(ProjectSettings.get_setting("application/run/main_scene", "")),
		"scene_key": scene_key,
		"loaded_level": {},
		"door_topology": {},
		"room_objects": [],
		"interactable_candidates": [],
		"ai_routes": [],
		"architecture_audit": {},
	}
	var audit := preload("res://scenes/components/shared/AcademyArchitectureAudit.gd").scan()
	report.architecture_audit = {"ok": audit.ok, "scanned": audit.scanned, "violations": audit.violations}

	if scene_key == "r01":
		var lvl := R01Level.new()
		root.add_child(lvl)
		await frames(4)
		var m: Dictionary = lvl.level_manifest
		report.loaded_level = {
			"level_id": str(m.get("level_id", "")),
			"title": str(m.get("title", "")),
			"pipeline": "AcademyLevelBase → AcademyLevelRuntime",
			"audit_ok": bool(lvl.audit_report.get("ok", false)),
			"capabilities": lvl.level_capabilities,
			"ui_mode": lvl.dual_ui.get_mode_name() if is_instance_valid(lvl.dual_ui) else "none",
		}
		report.door_topology = {
			"note": "R-01 North Wing Porch -> connects H-00 Public Hall <-> R-02 Sunken Archive",
			"triggers": m.get("triggers", []),
		}
		for oid in lvl.spawned_objects:
			var n: Node3D = lvl.spawned_objects[oid]
			report.room_objects.append({"id": oid, "pos": _vec_arr(n.position)})
		report.interactable_candidates = _extract_candidates(lvl.dual_ui)
		report.ai_routes = m.get("ai_routes", [])
		lvl.queue_free()
	elif scene_key == "expedition":
		var exp := SortieScene.instantiate()
		root.add_child(exp)
		await frames(5)
		report.loaded_level = {
			"level_id": "expedition_01_north_wing",
			"title": "Expedition-01 (Sortie.tscn)",
			"pipeline": "AcademyLevelRuntime (director → DualModeInteractionHud)",
			"capabilities": exp.level_capabilities,
			"ui_mode": exp.dual_ui.get_mode_name() if is_instance_valid(exp.dual_ui) else "none",
		}
		report.door_topology = {
			"zones": ["A1_ImmersionArcade", "A2_QuietNiche", "B1_B5_Archive", "B6_CounterweightPumpRoom", "C1_C4_SourceCaisson", "C5_SouthReturnGallery"],
			"gate_released": bool(exp.released),
			"shortcut_open": bool(exp.shortcut_open),
			"exit_open": bool(exp.exit_open),
		}
		report.interactable_candidates = _extract_candidates(exp.dual_ui)
		exp.queue_free()
	else:
		var game := RunScene.instantiate()
		root.add_child(game)
		await frames(5)
		var obs: Dictionary = game.mcp_observe()
		report.loaded_level = {
			"level_id": str(obs.get("room", "camp")),
			"title": "Public Hall (Run.tscn / FirstWatch)",
			"phase": str(obs.get("phase", "")),
			"stage": str(obs.get("stage", "")),
			"pipeline": "AcademyLevelRuntime (director → DualModeInteractionHud)",
			"capabilities": game.level_capabilities,
			"ui_mode": game.dual_ui.get_mode_name() if is_instance_valid(game.dual_ui) else "none",
		}
		# Door & HouseMap topology
		var graph := {}
		if game.house != null:
			for rid in [game.house.camp_room(), "west_1", "east_1", "west_2", "east_2", "turntable", "west_3", "east_3", game.house.goal_room()]:
				var fwd := []
				for d in game.house.forward(rid):
					fwd.append(str(d))
				graph[rid] = fwd
		var exits_info := []
		for t in game.room_view._targets:
			if str(t.get("kind", "")) == "exit":
				exits_info.append({
					"label": str(t.get("label", "")),
					"index": int(t.get("index", 0)),
					"pos": _vec_arr(t.get("position", Vector3.ZERO)),
					"released": bool(game.room_view.routes_released),
				})
		report.door_topology = {
			"current_room": str(obs.get("room", "")),
			"cleared": obs.get("cleared", []),
			"active_exits": exits_info,
			"house_graph": graph,
		}
		var gothic: Node = game.find_child("PublicHallGothic", true, false)
		if gothic != null:
			for child in gothic.get_children():
				if child is Node3D and child.name in ["FoucaultPendulum", "WatchCotAlcove", "EssenceCalibrationLectern", "FloorLampNW", "FloorLampNE", "FloorLampSW", "FloorLampSE"]:
					report.room_objects.append({"id": child.name, "pos": _vec_arr(child.position)})
			report.room_objects.append({"id": "station_bounds_count", "count": gothic.station_bounds.size()})
		report.interactable_candidates = _extract_candidates(game.dual_ui)
		game.queue_free()

	print("===LEVEL_DEBUG_JSON_START===")
	print(JSON.stringify(report, "  "))
	print("===LEVEL_DEBUG_JSON_END===")
	quit(0)
