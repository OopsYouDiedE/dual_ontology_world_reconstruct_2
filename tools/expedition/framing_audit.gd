extends SceneTree
## First-person, fixed approach poses (never look_at the thing being measured).
## Run with --rendering-method forward_plus --fixed-fps 60 --script <this script>.
## Pixel IDs are two successive unlit colours on the actual mesh; props, Hale,
## transparent glazing, non-colliding mullions and the ordinary HUD stay drawn.
const OUT := "res://.runtime/expedition-framing/"
var lv
var rows: Array[Dictionary] = []
var errors := 0

func _initialize() -> void:
	run.call_deferred()

func settle(frames: int) -> void:
	for i in frames: await process_frame
	await RenderingServer.frame_post_draw

func capture() -> Image:
	await settle(4)
	return root.get_texture().get_image()

func marker(color: Color) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = color
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	return mat

func audit(id: String, subject: Node3D, feet: Vector3, yaw: float, pitch: float, min_fraction: float) -> void:
	lv.walker.position = feet
	lv.walker.rotation.y = yaw
	lv.eye.rotation = Vector3(pitch, 0, 0)
	var meshes: Array[Node] = subject.find_children("*", "MeshInstance3D", true, false)
	if subject is MeshInstance3D: meshes.append(subject)
	var rendered: Array[MeshInstance3D] = []
	var materials: Array[Material] = []
	var bounds := Rect2()
	var started := false
	for m: MeshInstance3D in meshes:
		if not m.is_visible_in_tree(): continue
		rendered.append(m)
		materials.append(m.material_override)
		var box := m.get_aabb()
		for j in 8:
			var point := m.to_global(box.get_endpoint(j))
			if lv.eye.is_position_behind(point): continue
			var screen: Vector2 = lv.eye.unproject_position(point)
			bounds = bounds.expand(screen) if started else Rect2(screen, Vector2.ZERO)
			started = true
	await settle(12)
	var real := await capture()
	real.save_png(OUT + id + ".png")
	var green := marker(Color.GREEN)
	var red := marker(Color.RED)
	for m in rendered: m.material_override = green
	var a := await capture()
	for m in rendered: m.material_override = red
	var b := await capture()
	for i in rendered.size(): rendered[i].material_override = materials[i]
	var points := 0
	var brightness := 0.
	var contrast := 0.
	var edge_samples := 0
	var center := Vector2.ZERO
	var size := real.get_size()
	# Scan in the projected AABB only; two-colour differential rejects red art,
	# screen-space effects, shadows and most bloom outside the mesh silhouette.
	for y in range(maxi(0,floori(bounds.position.y)), mini(size.y,ceili(bounds.end.y)),2):
		for x in range(maxi(0,floori(bounds.position.x)), mini(size.x,ceili(bounds.end.x)),2):
			var g := a.get_pixel(x,y)
			var r := b.get_pixel(x,y)
			if g.g-r.g < .25 or r.r-g.r < .25: continue
			points += 1
			center += Vector2(x,y)
			brightness += real.get_pixel(x,y).get_luminance()
			for dx in [-8,8]:
				var nx: int = x+dx
				if nx < 0 or nx >= size.x: continue
				if a.get_pixel(nx,y).g-b.get_pixel(nx,y).g > .20: continue
				contrast += absf(real.get_pixel(x,y).get_luminance()-real.get_pixel(nx,y).get_luminance())
				edge_samples += 1
	var fraction := 4.*points/(size.x*size.y)
	center = center/maxi(1,points)/Vector2(size)
	brightness /= maxi(1,points)
	contrast /= maxi(1,edge_samples)
	var sight_point: Vector3 = subject.global_position
	if subject == lv.kit.gate: sight_point = Vector3(36.,1.55,0.)
	var query := PhysicsRayQueryParameters3D.create(lv.eye.global_position,sight_point,2,[lv.walker.get_rid()])
	var hit := lv.get_world_3d().direct_space_state.intersect_ray(query) as Dictionary
	var clear := hit.is_empty() or subject.is_ancestor_of(hit.collider)
	var ok := clear and Rect2(.18,.12,.64,.73).has_point(center) and fraction >= min_fraction and brightness > .08 and contrast > .035
	var row := {"beat":id,"visible_frame_fraction":fraction,"projected_bounds_px":str(bounds),"visible_center_uv":str(center),"mean_luma":brightness,"edge_contrast":contrast,"ray_clear":clear,"ok":ok}
	rows.append(row)
	print(JSON.stringify(row))
	if not ok: errors += 1

func run() -> void:
	if DisplayServer.get_name() == "headless":
		push_error("Framing needs real pixels; use Forward+."); quit(2); return
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	root.size = Vector2i(1280,720)
	lv = preload("res://scenes/expedition_01/Expedition.tscn").instantiate()
	root.add_child(lv)
	# Let the player's opening fade finish, then freeze the live scene while
	# sampling each controlled arrival pose, so ID frames share one silhouette.
	await settle(540)
	paused = true
	await audit("entry", lv.kit.gate, Vector3(1,.03,0), -PI/2, 0., .001)
	lv.hale.position = lv.archive.WINDOW
	await audit("window", lv.kit.test_board, Vector3(24.65,.03,7.75), PI, -.15, .008)
	lv.hale.position = Vector3(47.,0.,9.)
	await audit("shaft", lv.kit.bridge, Vector3(49.4,.03,10.1), -PI/2, -.10, .01)
	var f := FileAccess.open(OUT + "report.json",FileAccess.WRITE)
	f.store_string(JSON.stringify(rows,"\t")); f.close()
	quit(1 if errors else 0)
