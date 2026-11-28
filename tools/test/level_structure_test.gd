extends SceneTree
## Level structures: every room lot converts into editable Godot nodes (LevelStructure3D +
## SmartFloorZone3D/SmartWall3D/LevelAnchor3D) and round-trips to the identical gameplay lot,
## also after saving to .tscn and loading again.
## Write the converted scenes:  -s res://tools/test/level_structure_test.gd -- --write

const Blueprint := preload("res://scenes/rogue_view/NativeBlueprint.gd")
const Converter := preload("res://tools/building_construction/LotToStructure.gd")
const OUT := "res://scenes/levels/structures"
const TEMPLATES := ["public_nave", "foyer", "living_hall", "lecture", "clinic", "dining", "valve_gallery", "service_stair"]

var failed := 0

func check(ok: bool, label: String) -> void:
	print(("PASS " if ok else "FAIL ") + label)
	if not ok:
		failed += 1

func _initialize() -> void:
	run.call_deferred()

static func as_set(items: Array) -> Array:
	var out: Array = items.map(func(v): return var_to_str(v))
	out.sort()
	return out

func same_lot(a: Dictionary, b: Dictionary, label: String) -> void:
	check(as_set(a.floors) == as_set(b.floors), "%s: walkable floor cells identical (%d)" % [label, a.floors.size()])
	check(a.patterns == b.patterns, "%s: floor patterns identical" % label)
	check(as_set(a.segments) == as_set(b.segments), "%s: wall edges identical (%d)" % [label, a.segments.size()])
	check(as_set(a.windows.keys()) == as_set(b.windows.keys()), "%s: window edges identical (%d)" % [label, a.windows.size()])
	check(as_set(a.objects) == as_set(b.objects), "%s: lot objects identical (%d)" % [label, a.objects.size()])

func run() -> void:
	var write := "--write" in OS.get_cmdline_user_args()
	for template: String in TEMPLATES:
		var source: Dictionary = Blueprint.read("res://content/academy_lots/%s.xml" % template).get("lot", {})
		check(not source.is_empty(), "%s: source lot reads" % template)
		if source.is_empty():
			continue
		var upper: Dictionary = Blueprint.read("res://content/academy_lots/%s.xml" % template, 2).get("lot", {})
		var structure: Node3D = Converter.build(source, template, template.capitalize(), upper)
		same_lot(source, structure.derive_lot(), template + " (converted)")
		var path := ("%s/%s.tscn" % [OUT, template]) if write else ("res://.runtime/structure_test/%s.tscn" % template)
		# Scenes that were edited past the XML (the Public Hall's components) are never overwritten.
		if write and ResourceLoader.exists(path) and FileAccess.get_file_as_string(path).contains("PublicHallGothic"):
			path = "res://.runtime/structure_test/%s.tscn" % template
		check(Converter.save(structure, path) == OK, "%s: saved %s" % [template, path])
		structure.free()
		var loaded := (ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_IGNORE) as PackedScene).instantiate()
		check(loaded is LevelStructure3D, "%s: loads as LevelStructure3D" % template)
		same_lot(source, loaded.derive_lot(), template + " (saved .tscn)")
		root.add_child(loaded)
		await process_frame
		await process_frame
		var bodies := loaded.find_children("CollisionRoot", "StaticBody3D", true, false)
		check(bodies.size() >= loaded.walls().size() + loaded.floors().size(), "%s: walls and floors generate collision (%d)" % [template, bodies.size()])
		loaded.queue_free()
		await process_frame
	print("LEVEL_STRUCTURE_SUMMARY failed=%d" % failed)
	quit(0 if failed == 0 else 1)
