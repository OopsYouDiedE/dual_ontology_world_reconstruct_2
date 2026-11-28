extends SceneTree
## Single-pipeline + decoupling gate.
##  1. Source audit: no formal-runtime file bypasses the shared runtime / render stage / item catalog.
##  2. Scene selectables (AcademyInteractable) reach the UI only through descriptors, and UI
##     activation reaches the scene only through signals — neither side references the other.
##  3. Items: catalog `interaction` blocks become selectables; optional missing items are filtered.
##  4. Tools: ArchBuilder (BuildingSimulator) and the Component Library item-property inspector
##     load the shared catalog, place items and edit interaction properties.
##
## & .runtime/godot/4.7.2/Godot_v4.7.2-stable_mono_win64_console.exe --headless --path . -s res://tools/test/architecture_unity_test.gd

const Audit := preload("res://scenes/components/shared/AcademyArchitectureAudit.gd")
const Runtime := preload("res://scenes/components/shared/AcademyLevelRuntime.gd")
const Pipeline := preload("res://scenes/components/shared/AcademyLevelPipeline.gd")
const Schema := preload("res://scenes/components/interaction/AcademyInteractionSchema.gd")
const Interactable := preload("res://scenes/components/interaction/AcademyInteractable.gd")
const Hotspot := preload("res://scenes/components/interaction/AcademyHotspot.gd")
const Factory := preload("res://tools/building_construction/BuildingConstruction/Shared/ComponentFactory.gd")
const FurnitureCatalog := preload("res://scenes/components/shared/AcademyFurnitureCatalog.gd")
const Library := preload("res://tools/building_construction/ComponentLibrary.tscn")
const Simulator := preload("res://tools/building_construction/BuildingSimulator.tscn")
const R01Level := preload("res://scenes/levels/Chapter1R01Level.gd")

var failed := 0

func _initialize() -> void:
	run.call_deferred()

func check(ok: bool, msg: String) -> void:
	print(("PASS " if ok else "FAIL ") + msg)
	if not ok:
		failed += 1

func frames(n: int) -> void:
	for i in n:
		await process_frame

func key(code: Key) -> InputEventKey:
	var e := InputEventKey.new()
	e.physical_keycode = code
	e.keycode = code
	e.pressed = true
	return e

func run() -> void:
	# 1. Source audit
	var report := Audit.scan()
	print(Audit.format_report(report))
	check(report.ok and int(report.scanned) > 50, "No formal-runtime file bypasses the unified pipeline (%d files scanned)" % int(report.scanned))
	# Negative control: a level that builds its own HUD, syncs it and attaches a post pass is caught.
	DirAccess.make_dir_recursive_absolute("user://arch_audit_probe")
	var probe := FileAccess.open("user://arch_audit_probe/BypassLevel.gd", FileAccess.WRITE)
	probe.store_string("extends Node3D
func _ready():
	var hud := DualModeInteractionHud.new()
	hud.sync_groups(null, Rect2(), Vector2.ONE, Vector3.ZERO, [], false)
	add_child(preload(\"res://scenes/components/rendering/post/InkPass.gd\").create())
	var e := Stage.environment()
")
	probe.close()
	var bypass := Audit.scan(["user://arch_audit_probe"])
	var hit_rules: Array = bypass.violations.map(func(v): return v.rule)
	check(not bypass.ok and "ui.hud_instance" in hit_rules and "ui.direct_sync" in hit_rules and "render.post_pass" in hit_rules and "render.stage_env" in hit_rules,
		"Audit catches a bypassing level (%s)" % str(hit_rules))
	for path in ["res://scenes/components/interaction/AcademyInteractable.gd", "res://scenes/components/interaction/AcademyHotspot.gd"]:
		var src := FileAccess.get_file_as_string(path)
		check(not src.contains("DualModeInteractionHud") and not src.contains("sync_groups") and not src.contains("Control"),
			"%s holds scene data only (no UI references)" % path.get_file())
	var hud_src := FileAccess.get_file_as_string("res://scenes/components/shared/DualModeInteractionHud.gd")
	check(not hud_src.contains("AcademyInteractable") and not hud_src.contains("get_nodes_in_group"),
		"DualModeInteractionHud never reaches into scene nodes")

	# 2. Schema contract
	var bad := Schema.validate_groups([{"id": "", "anchor_world": 3, "hotspots": []}, {"id": "a", "anchor_world": Vector3.ZERO, "hotspots": [{"id": "h", "world_pos": Vector3.ZERO}]}])
	check(bad.size() >= 3, "Schema rejects empty ids, bad anchors and callback-less hotspots (%d errors)" % bad.size())
	var good := Schema.single("x", "X", Vector3.ZERO, "E · Open", func(): pass)
	check(Schema.validate_groups([good]).is_empty() and good.hotspots[0].verb == "Open", "Schema.single builds a valid group and strips key-cap prefixes")
	var caps := Pipeline.capabilities_for("hall", {"allow_jump": false})
	check(caps.level_kind == "hall" and not caps.allow_jump, "capabilities_for() derives explicit overrides from a standard profile")

	# 3. Decoupled scene selectable -> runtime -> presenter -> signal back
	var host := Node3D.new()
	host.name = "DecoupleHost"
	root.add_child(host)
	var cam := Camera3D.new()
	host.add_child(cam)
	cam.look_at_from_position(Vector3(0, 1.57, 2.0), Vector3(0, 0.9, 0), Vector3.UP)
	cam.current = true
	var crate := Node3D.new()
	crate.name = "Crate"
	host.add_child(crate)
	var it := Interactable.attach_to(crate, {"id": "crate", "title_en": "Crate", "title_zh": "木箱", "verb_en": "Open", "verb_zh": "打开",
		"action_id": "open_crate", "anchor_offset": [0, 0.9, 0],
		"hotspots": [{"id": "crate_lid", "part_en": "Lid", "verb_en": "Lift", "action_id": "lift_lid", "offset": [0, 0.9, 0]},
			{"id": "crate_seal", "part_en": "Seal", "verb_en": "Break", "action_id": "break_seal", "unlock_flag": "seal_known", "offset": [0.2, 0.9, 0]}]})
	var layer := CanvasLayer.new()
	host.add_child(layer)
	var rt := Runtime.install(host, layer, Pipeline.capabilities_campaign_room(), {"auto_refresh": false})
	check(Runtime.install(host, layer, Pipeline.capabilities_campaign_room()) == rt, "Runtime.install is idempotent per host")
	check(is_instance_valid(rt.dual_ui) and is_instance_valid(rt.dialogue) and is_instance_valid(rt.teammate_wheel), "Runtime owns HUD + dialogue + wheel")
	rt.set_view_provider(func(): return {"camera": cam, "rect": Rect2(0, 0, 1280, 720), "vp_size": Vector2(1280, 720), "player_pos": cam.global_position, "can_show": true})
	var signals := []
	it.activated.connect(func(hid: String, act: String): signals.append("node:%s:%s" % [hid, act]))
	rt.interactions.action_requested.connect(func(act: String, ctx: Dictionary): signals.append("dir:%s:%s" % [act, ctx.hotspot_id]))
	await frames(2)
	rt.refresh_interactions()
	var groups := rt.interactions.last_groups()
	check(groups.size() == 1 and groups[0].hotspots.size() == 1, "Locked hotspot stays hidden until its flag is set (%s)" % str(groups.map(func(g): return g.hotspots.size())))
	rt.interactions.set_flag("seal_known")
	rt.refresh_interactions()
	groups = rt.interactions.last_groups()
	check(groups[0].hotspots.size() == 2, "Setting a flag unlocks the hotspot without touching the UI")
	var snap: Dictionary = rt.interaction_snapshot()
	check(snap.get("cplus_state", "") == "selected" and snap.get("cplus_focus_group", "") == "crate", "Presenter selects the scene interactable it only knows as a descriptor (%s)" % str(snap))
	var consumed := rt.handle_input(key(KEY_E))
	check(consumed and "node:crate_lid:lift_lid" in signals and "dir:lift_lid:crate_lid" in signals,
		"Pressing E reaches the scene via signals only (%s)" % str(signals))
	it.enabled = false
	rt.refresh_interactions()
	check(rt.interactions.last_groups().is_empty(), "Disabling the scene node removes its prompt")
	host.queue_free()
	await frames(2)

	# 4. Items: catalog interaction + optional filtering
	var catalog := Factory.load_catalog()
	var ids := (catalog.get("items", []) as Array).map(func(e): return str(e.id))
	check(ids.size() > 100 and not ("PhysicalButton" in ids), "Shared catalog loader drops optional items missing from this checkout (%d items)" % ids.size())
	var chest_entry: Dictionary = {}
	for e in catalog.items:
		if e.id == "RecipeChest":
			chest_entry = e
	var chest := Factory.create_entry(chest_entry)
	var chest_it := chest.get_node_or_null("Interactable") if chest else null
	check(chest_it is Interactable and chest_it.action_id == "search_container", "Catalog item with an interaction block becomes a scene selectable")
	if chest: chest.free()
	check(FurnitureCatalog.default_interaction("manor_chest").get("action_id", "") == "search_container", "Furniture catalog exposes default item interactions")

	# 5. Level built on AcademyLevelBase: manifest interactables are scene nodes
	var lvl := R01Level.new()
	root.add_child(lvl)
	await frames(3)
	check(lvl.audit_report.ok, "R-01 manifest (incl. object interaction) passes the audit (%s)" % str(lvl.audit_report.errors))
	check(lvl.interactable_nodes.has("r01_logbook") and lvl.interactable_nodes.has("r01_supply_chest"), "Manifest interactables + catalog item spawn as AcademyInteractable nodes (%s)" % str(lvl.interactable_nodes.keys()))
	check(lvl.interactable_nodes.get("r01_supply_chest") is Interactable and lvl.interactable_nodes.r01_supply_chest.get_parent() == lvl.spawned_objects.get("r01_supply_chest"), "Item interaction lives on the item node")
	var before := lvl.runtime.interactions.collect().map(func(g): return g.hotspots.size())
	lvl.unlocked_flags["letter_inspected"] = true
	var after := lvl.runtime.interactions.collect().map(func(g): return g.hotspots.size())
	check(before != after, "Level flags unlock manifest hotspots through the director (%s -> %s)" % [str(before), str(after)])
	lvl.queue_free()
	await frames(2)

	# 6. Tools: Component Library (item property tool) and ArchBuilder (BuildingSimulator)
	var library := Library.instantiate()
	root.add_child(library)
	await frames(3)
	check(not library.catalog.is_empty() and library.catalog.items.size() == ids.size(), "Component Library loads the shared catalog")
	var lib_chest: Node3D = library._make_part(chest_entry)
	library.candidates.add_child(lib_chest)
	library._own_interaction(lib_chest)
	library._select(lib_chest)
	var labels: Array = library.inspector.get_children().filter(func(c): return c is Label).map(func(c): return c.text)
	check("Interaction" in labels and "action_id" in labels and "title_en" in labels, "Inspector shows the item's interaction properties")
	var lib_it: Interactable = lib_chest.get_node("Interactable")
	library._change("action_id", "loot_chest", lib_it)
	check(lib_it.action_id == "loot_chest" and lib_it.owner == library.candidates, "Inspector edits interaction data and it is saved with the candidate")
	var shelf_entry: Dictionary = {}
	for e in catalog.items:
		if e.id == "RecipeBookshelf":
			shelf_entry = e
	var shelf: Node3D = library._make_part(shelf_entry)
	library.candidates.add_child(shelf)
	library._select(shelf)
	var make_btn = library.inspector.get_children().filter(func(c): return c is Button and c.text == "Make selectable")
	check(make_btn.size() == 1, "Non-selectable items offer 'Make selectable'")
	if make_btn.size() == 1:
		make_btn[0].pressed.emit()
		await frames(1)
		check(shelf.get_node_or_null("Interactable") is Interactable, "'Make selectable' attaches an AcademyInteractable to the item")
	library.queue_free()
	await frames(2)

	var sim := Simulator.instantiate()
	root.add_child(sim)
	await frames(4)
	check(sim.catalog is Dictionary and (sim.catalog.get("items", []) as Array).size() == ids.size(), "ArchBuilder (BuildingSimulator) loads the shared catalog")
	sim.queue_free()
	await frames(2)

	print("ARCHITECTURE_UNITY_SUMMARY failed=%d" % failed)
	quit(0 if failed == 0 else 1)
