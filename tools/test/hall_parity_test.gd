extends SceneTree
## Public Hall parity: the editable component scene must reproduce the original
## procedural hall mesh-for-mesh, light-for-light, station-for-station.
##   Record the reference (once, from the legacy builder):  -- --dump-legacy
##   Check the structure scene against it:                   (no args)
## The reference lives in tools/test/fixtures/public_hall_legacy.json.

const FP := preload("res://tools/test/HallFingerprint.gd")
const FIXTURE := "res://tools/test/fixtures/public_hall_legacy.json"
const Blueprint := preload("res://scenes/rogue_view/NativeBlueprint.gd")

var failed := 0

func check(ok: bool, label: String) -> void:
	print(("PASS " if ok else "FAIL ") + label)
	if not ok:
		failed += 1

func _initialize() -> void:
	run.call_deferred()

static func rects(list: Array) -> Array:
	var out: Array = []
	for r: Rect2 in list:
		out.append([snappedf(r.position.x, 0.001), snappedf(r.position.y, 0.001), snappedf(r.size.x, 0.001), snappedf(r.size.y, 0.001)])
	out.sort()
	return out

static func vec(v: Vector3) -> Array:
	return [snappedf(v.x, 0.001), snappedf(v.y, 0.001), snappedf(v.z, 0.001)]

func run() -> void:
	if "--dump-legacy" in OS.get_cmdline_user_args():
		await dump_legacy()
	else:
		await check_scene()
	print("HALL_PARITY_SUMMARY failed=%d" % failed)
	quit(0 if failed == 0 else 1)

func dump_legacy() -> void:
	var Legacy = load("res://scenes/rogue_view/render/PublicHallGothic.gd")
	var Well = load("res://scenes/rogue_view/render/MeridianWell.gd")
	var lot: Dictionary = Blueprint.read("res://content/academy_lots/public_nave.xml").lot
	var geo := Node3D.new()
	root.add_child(geo)
	var well := Rect2i(14, 15, 4, 4)
	Well.install(geo, well, true)
	var hall: Node3D = Legacy.install(geo, lot, Rect2i(11, 5, 10, 20), well, true)
	for i in 4:
		await process_frame
	hall.set_hour(4.0)
	hall.set_process(false)
	hall.pendulum_pivot.rotation = Vector3.ZERO  # the swing is animation, not geometry
	var entries := FP.collect([hall, geo.get_node("FloorMeridian")])
	var extra := {
		"stations": rects(hall.station_bounds),
		"pendulum": vec(hall.pendulum_world_pos),
		"cot": vec(hall.watch_cot_pos),
		"gate": vec(hall.north_gate_pos),
		"period": hall.get_pendulum_period_sec(),
	}
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(FIXTURE.get_base_dir()))
	var f := FileAccess.open(FIXTURE, FileAccess.WRITE)
	f.store_string(FP.to_json(entries, extra))
	f.close()
	check(entries.size() > 500, "legacy hall recorded: %d meshes/shapes/lights, %d stations" % [entries.size(), extra.stations.size()])

func check_scene() -> void:
	var ref: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(FIXTURE))
	check(ref != null and not ref.entries.is_empty(), "legacy reference loads (%d entries)" % (ref.entries.size() if ref else 0))
	var structure: Node3D = (load("res://scenes/levels/structures/public_nave.tscn") as PackedScene).instantiate()
	root.add_child(structure)
	for i in 4:
		await process_frame
	var hall: Node3D = structure.get_node_or_null("PublicHallGothic")
	check(hall != null, "public_nave.tscn contains the PublicHallGothic component root")
	if hall == null:
		return
	hall.refresh()
	hall.set_hour(4.0)
	hall.pendulum().set_process(false)
	hall.pendulum_pivot.rotation = Vector3.ZERO
	var pieces: Array = hall.pieces()
	check(pieces.size() > 100, "hall is made of editable component nodes (%d)" % pieces.size())
	check(pieces.all(func(p): return p.owner == structure), "every component is saved in the scene (owned), not generated at runtime")
	var now: Array = JSON.parse_string(FP.to_json(FP.collect([hall]), {})).entries
	# The three nave fill lights used to be added by LotGeometryBuilder; they now live in the scene.
	for i in 3:
		ref.entries.append({"kind": "OmniLight3D", "tag": "ffe9cb", "v": [16.0, 4.1, lerpf(7.5, 22.5, i / 2.0), 0.0, 0.0, -1.0, 12.0, 0.52]})
	var d := FP.diff(ref.entries, now)
	var groups := {}
	for e in d.missing: groups["missing " + e.tag] = int(groups.get("missing " + e.tag, 0)) + 1
	for e in d.extra: groups["extra " + e.tag] = int(groups.get("extra " + e.tag, 0)) + 1
	if not groups.is_empty(): print("  diff by material: ", groups)
	var kinds := {}
	for e: Dictionary in ref.entries:
		kinds[e.kind] = int(kinds.get(e.kind, 0)) + 1
	# Book spines cycle through the catalog's four book materials in an order that depended on
	# the engine's runtime node id of the legacy shelf (@RecipeBookshelf@<n>); geometry must
	# still match exactly, only the cycle may differ.
	const BOOK_TAGS := ["std:5a3b28", "std:5e2620", "std:2a4d3e", "std:1f242b"]
	var recolor := FP.diff(d.missing.map(func(e): return {"kind": e.kind, "tag": "book" if e.tag in BOOK_TAGS else e.tag, "v": e.v}),
		d.extra.map(func(e): return {"kind": e.kind, "tag": "book" if e.tag in BOOK_TAGS else e.tag, "v": e.v}))
	print("  book spines recoloured (same geometry): %d" % (d.missing.size() - recolor.missing.size()))
	d = recolor
	check(d.missing.is_empty() and d.extra.is_empty(), "meshes, collision shapes and lights match the legacy hall one-to-one (%s; missing %d, extra %d)" % [str(kinds), d.missing.size(), d.extra.size()])
	for e in d.missing.slice(0, 6):
		print("  missing ", e)
	for e in d.extra.slice(0, 6):
		print("  extra   ", e)
	check(str(rects(hall.station_bounds)) == str(ref.extra.stations), "station footprints identical (%d)" % hall.station_bounds.size())
	if str(rects(hall.station_bounds)) != str(ref.extra.stations):
		print("  now ", rects(hall.station_bounds))
		print("  ref ", ref.extra.stations)
	check(vec(hall.pendulum_world_pos) == ref.extra.pendulum, "pendulum position identical %s" % str(hall.pendulum_world_pos))
	check(vec(hall.watch_cot_pos) == ref.extra.cot, "wake cot anchor identical %s" % str(hall.watch_cot_pos))
	check(vec(hall.north_gate_pos) == ref.extra.gate, "north gate anchor identical %s" % str(hall.north_gate_pos))
	check(is_equal_approx(hall.get_pendulum_period_sec(), float(ref.extra.period)), "pendulum period identical (%.1f s)" % hall.get_pendulum_period_sec())
	check(hall.well_rect() == Rect2i(14, 15, 4, 4), "meridian dial cells come from the pendulum component %s" % str(hall.well_rect()))
	var lot: Dictionary = structure.derive_lot()
	check(lot.anchors.get("spawn") == Vector3(16, 0, 24.4), "spawn comes from the scene's spawn anchor")
	# Editing in the editor = changing exported parameters: one bay moves, the rest stays.
	var bay: Node3D = hall.find_child("LancetW0", true, false)
	var before := bay.get_child_count()
	bay.variant = 3
	bay.rebuild()
	check(bay.get_child_count() == before and bay.find_child("LancetGlass_3_0", true, false) != null, "changing a bay's parameter rebuilds just that bay")
