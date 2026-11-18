extends SceneTree

const Kitchen = preload("res://scenes/rogue_view/render/HotKitchen.gd")
const Shell = preload("res://scenes/rogue_view/render/OrthogonalShell.gd")
const Masks = preload("res://scenes/rogue_view/render/KitchenSurfaceMasks.gd")
var failures := 0

func _initialize() -> void:
	var mask := Masks.bake(Masks.KITCHEN_SEED)
	check(mask.has_mipmaps(), "weathering mask includes mipmaps")
	check(mask.get_data() == Masks.bake(Masks.KITCHEN_SEED).get_data(), "weathering mask deterministic")
	check(mask.get_data() != Masks.bake(Masks.KITCHEN_SEED+1).get_data(), "weathering mask responds to seed")
	var plan := Kitchen.read_plan()
	check(not plan.is_empty(), "ArchBuilder restore and placement search")
	if plan.is_empty():
		quit(1)
		return
	var prep: Dictionary = plan.props.filter(func(p): return p.id == "prep")[0]
	check(is_equal_approx(prep.x,3.975) and is_equal_approx(prep.z,2.75), "minimum-displacement worktable placement")
	check(plan == Kitchen.read_plan(), "placement deterministic")
	var impossible := plan.duplicate(true)
	impossible.props.filter(func(p): return p.id == "prep")[0].x = 20
	check(Kitchen.fit_prep(impossible).is_empty(), "infeasible placement reported")
	var layout := Kitchen.layout(plan)
	check(layout.floors.size() == 84, "all three floor zones")
	var solids := Kitchen.shell_prisms(plan,layout.floors)
	var compiled := Shell.compile(solids)
	var edges := {}
	var face_ids := {}
	for face in compiled.faces:
		var corners: Array = face.corners
		var a := Vector3(corners[1]-corners[0])
		var b := Vector3(corners[2]-corners[0])
		check(a.cross(b).dot(Vector3(face.normal)) < 0, "nondegenerate, outward-wound face")
		var key: Array = corners.duplicate()
		key.sort()
		check(not face_ids.has(key), "no duplicate face")
		face_ids[key] = true
		for i in 4:
			var edge := [corners[i],corners[(i+1)%4]]
			edge.sort()
			edges[edge] = edges.get(edge,0)+1
	check(edges.values().all(func(count): return count == 2), "every shell edge shared by exactly two faces")
	for point in [Vector3(3.4,1.6,0),Vector3(6.35,1,0),Vector3(6.4,1,-2),Vector3(4,1,7)]:
		check(not contains(solids,point), "clear opening at %s" % point)
	for point in [Vector3(3.4,0.8,0),Vector3(4.9,1.6,0),Vector3(0.05,1,0.05),Vector3(6.2,-0.08,-2.01),Vector3(6.2,3.25,-2.01)]:
		check(contains(solids,point), "solid wall/floor/ceiling at %s" % point)
	print("Hot kitchen: %d boundary quads, %d shared edges, %d failures" % [compiled.faces.size(),edges.size(),failures])
	quit(0 if failures == 0 else 1)

func contains(solids: Array, at: Vector3) -> bool:
	var p := Vector3i((at*Shell.SCALE).round())
	for solid in solids:
		var low: Vector3i = solid[0]
		var high: Vector3i = solid[1]
		if p.x >= low.x and p.x < high.x and p.y >= low.y and p.y < high.y and p.z >= low.z and p.z < high.z: return true
	return false

func check(ok: bool, label: String) -> void:
	if not ok:
		failures += 1
		push_error(label)
