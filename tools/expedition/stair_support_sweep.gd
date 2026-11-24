extends SceneTree
## Geometric screening, not a player controller: sweep the real player capsule down
## onto the east escape spiral along each polygonal route. No hunter or elapsed ticks.
const Expedition = preload("res://scenes/expedition_01/Expedition.tscn")
const Fixture = preload("res://tools/expedition/collision_fixture.gd")
const BASE = "res://.runtime/stair-support/"
const ORIGIN := Vector3(73.35, 0, 8.1)
var walker: CharacterBody3D
var hit := KinematicCollision3D.new()
var witnesses := {}

func _initialize() -> void:
	run.call_deferred()

func check_point(p: Vector3) -> bool:
	var tr := walker.global_transform
	tr.origin = p + Vector3.UP * 0.42
	if not walker.test_move(tr, Vector3.DOWN * 0.84, hit, walker.safe_margin, false, 4): return false
	for i in hit.get_collision_count():
		if hit.get_normal(i).y >= cos(walker.floor_max_angle): return true
	return false

func locate(f: float, bottom: float, top: float, bias: float) -> Vector3:
	var a := PI * 0.5 + TAU * f
	var r := lerpf(bottom, top, f) + bias * sin(PI * f)
	return ORIGIN + Vector3(cos(a) * r, 4.8 * f, sin(a) * r)

func traverse(bottom: float, top: float, bias: float, segments: int) -> Dictionary:
	var prev := locate(0, bottom, top, bias)
	var tested := 0
	for j in range(segments + 1):
		var dest := locate(float(j) / segments, bottom, top, bias)
		var n := maxi(1, ceili(prev.distance_to(dest) / 0.12))
		for k in range(1, n + 1):
			var p := prev.lerp(dest, float(k) / n)
			tested += 1
			if not check_point(p): return {"ok":false,"probes":tested,"point":[p.x,p.y,p.z]}
		prev = dest
	return {"ok":true,"probes":tested,"point":[prev.x,prev.y,prev.z]}

func run() -> void:
	var lv = Expedition.instantiate(); root.add_child(lv); lv.set_physics_process(false)
	Fixture.apply_lightweight(lv)
	for _i in 3: await physics_frame
	walker = lv.walker
	if not check_point(locate(0,1.02,1.02,0)) or check_point(Vector3(73, 25, 8)):
		printerr("Floor / free-air control failed"); quit(1); return
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(BASE))
	var file := FileAccess.open(BASE+"cases.csv", FileAccess.WRITE)
	if not file: quit(2); return
	file.store_csv_line(["start_radius_cm","end_radius_cm","mid_bow_cm","segments","supported","capsule_queries","last_x","last_y","last_z"])
	var passed := 0; var cases := 0; var probes := 0; var start := Time.get_ticks_msec()
	for low in range(40, 221, 20):
		for high in range(40, 221, 20):
			for bend in range(-45, 46, 10):
				for segments in range(12,36):
					var r := traverse(low*.01, high*.01, bend*.01, segments)
					cases += 1; probes += int(r.probes); passed += int(r.ok)
					file.store_csv_line(PackedStringArray([low,high,bend,segments,int(r.ok),r.probes,r.point[0],r.point[1],r.point[2]]))
					if not witnesses.has(r.ok): witnesses[r.ok] = [low,high,bend,segments,r]
	file.close()
	var report := {"cases":cases,"supported":passed,"no_support":cases-passed,"capsule_queries":probes,"elapsed_ms":Time.get_ticks_msec()-start,"examples":witnesses.values()}
	var summary := FileAccess.open(BASE+"summary.json",FileAccess.WRITE)
	if not summary: quit(2); return
	summary.store_string(JSON.stringify(report,"  ")); summary.close(); print(JSON.stringify(report)); quit(0 if cases==24000 else 1)
