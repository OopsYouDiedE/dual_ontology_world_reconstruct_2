extends SceneTree

const Factory = preload("../BuildingConstruction/Shared/ComponentFactory.gd")
const Assembly = preload("../production/assembly/ComponentAssembly.gd")
const Solver = preload("../production/building/BuildingSolver.gd")
const View = preload("../production/building/BuildingView.gd")

var failed := 0

func _initialize() -> void:
	run.call_deferred()

func check(ok: bool, msg: String) -> void:
	print(("PASS " if ok else "FAIL ") + msg)
	if not ok:
		failed += 1

func run() -> void:
	var data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://tools/building_construction/catalog.json"))
	var entries := {}
	for entry in data.items:
		entries[entry.id] = entry

	# 1. Verify all 5 Gothic ArchBuilder recipes generate mesh + collision and respond to parameter edits.
	for id in ["RecipeGothicPointedRib", "RecipeGothicVaultBay", "RecipeGothicLancetBay", "RecipeGothicRoseWindow", "RecipeGothicButtress"]:
		check(entries.has(id), "catalog contains " + id)
		var node := Factory.create_entry(entries[id])
		root.add_child(node)
		var gen := node.get_node_or_null("Generated")
		var meshes := node.find_children("*", "MeshInstance3D", true, false)
		var cols := node.find_children("*", "CollisionShape3D", true, false)
		check(gen != null and not meshes.is_empty() and not cols.is_empty(), "%s generates visible meshes (%d) and collisions (%d)" % [id, meshes.size(), cols.size()])
		node.free()

	# Parameter responsiveness check on RecipeGothicVaultBay
	var small_vault := Factory.create_entry(entries.RecipeGothicVaultBay, {"span_x": 3.4, "crown_rise": 1.2})
	var large_vault := Factory.create_entry(entries.RecipeGothicVaultBay, {"span_x": 5.6, "crown_rise": 2.4})
	root.add_child(small_vault)
	root.add_child(large_vault)
	check(Assembly.bounds(large_vault).size.x > Assembly.bounds(small_vault).size.x + 1.5, "RecipeGothicVaultBay span_x expands geometry bounds")
	small_vault.free()
	large_vault.free()

	# 2. Verify BuildingSolver 4-pass sequence with GothicHallKit.tres
	var plan := {
		"version": 1,
		"seed": 42,
		"mode": "repair",
		"cells": {
			"0:0:0": 0, "1:0:0": 0,
			"0:1:0": 0, "1:1:0": 0,
		},
		"cores": {},
		"overrides": {},
		"profiles": {
			"0": {
				"room_height": 4.6,
				"allow_windows": true,
				"kit": "res://tools/building_construction/production/building/kits/GothicHallKit.tres"
			}
		},
		"reservations": [],
		"mounts": []
	}
	check(Solver.valid(plan), "GothicHallKit plan passes BuildingSolver schema validation")
	var s := Solver.new()
	s.build(plan)
	check(s.notes.is_empty(), "GothicHallKit build produces zero solver notes: " + str(s.notes))
	check(s.pass_order == ["ReservationPass", "StructurePass", "EnvelopePass", "FinishPass"], "GothicHallKit preserves 4-pass generator sequence")
	check(s.facets.size() > 200, "GothicHallKit emits procedural curved ribs, groin vault webs, and lancet/blind-arcade facets (%d)" % s.facets.size())
	check(s.pieces.any(func(p): return "/colonnette" in p.id), "GothicHallKit emits clustered gothic columns")
	check(s.pieces.any(func(p): return "/vault-boss" in p.id), "GothicHallKit emits gothic vault keystone bosses")

	var view := View.new()
	root.add_child(view)
	view.render(s, -1, false)
	var rendered_meshes := view.find_children("*", "MeshInstance3D", true, false)
	check(rendered_meshes.size() >= 3, "BuildingView compiles GothicHallKit into batched meshes (%d)" % rendered_meshes.size())
	view.free()

	await process_frame
	print("Gothic integration test: %d failures" % failed)
	quit(failed)
