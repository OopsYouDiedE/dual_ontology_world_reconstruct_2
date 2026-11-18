extends Node3D
## Dressing and kinetic fixtures for an ArchBuilder-authored kitchen cluster.
const State = preload("res://tools/building_construction/ArchitectState.gd")
const Shell = preload("res://scenes/rogue_view/render/OrthogonalShell.gd")
const Masks = preload("res://scenes/rogue_view/render/KitchenSurfaceMasks.gd")
const Finish = preload("res://scenes/rogue_view/render/KitchenFinish.gdshader")
const Tile = preload("res://scenes/rogue_view/render/AcademyTile.gdshader")
# Shared dimensions for authored geometry and the finite placement search.
const PREP_HALF := Vector2(1350, 525) # millimetres
const OVEN_SWEEP_HALF := Vector2(740, 655)
const OVEN_HINGE_X := 860
const SPAWN := Vector3(4.32,0,3.88)
const BLUEPRINT = "res://content/archbuilder/hot-kitchen.json"
var plan: Dictionary
var openings := {}
var anchors := {}
var cells: Array[Vector2i] = []
var shutter: AnimatableBody3D
var cold_door: AnimatableBody3D
var oven_door: AnimatableBody3D
var cold_light: SpotLight3D
var appliances := {}
var closed := {"hatch": false,"cold-door": false,"oven": false}
var moving := {}
var wall_mat := ShaderMaterial.new()
var floor_mat := ShaderMaterial.new()
var wood := ShaderMaterial.new()
var metal := ShaderMaterial.new()
var paper := StandardMaterial3D.new()
var brass := StandardMaterial3D.new()

static func read_plan() -> Dictionary:
	var state := State.new()
	if not state.restore(FileAccess.get_file_as_string(BLUEPRINT)): return {}
	return fit_prep(state.data)

## Search ±0.75 m on a 0.125 m lattice; minimize squared movement then x/z.
## The stove and passage are fixed. Keep a 0.68 m walking margin and reserve
## the full conservative sweep of the drop-down oven door.
static func fit_prep(document: Dictionary) -> Dictionary:
	var prep := {}
	var stove := {}
	for prop in document.props:
		if prop.id == "prep": prep = prop
		if prop.id == "range": stove = prop
	if prep.is_empty() or stove.is_empty(): return {}
	var stove_center := Vector2(stove.x,stove.z)*1000.0
	var stove_box := Rect2(stove_center-Vector2(800,1170),Vector2(1600,2340))
	var oven_sweep := Rect2(stove_center+Vector2(OVEN_HINGE_X-50,-OVEN_SWEEP_HALF.y), Vector2(OVEN_SWEEP_HALF.x+50,OVEN_SWEEP_HALF.y*2))
	var original := (Vector2(prep.x,prep.z)*1000.0).round()
	var best := Vector2.INF
	var best_cost := INF
	for x in range(-6,7):
		for z in range(-6,7):
			var point := original+Vector2(x,z)*125.0
			var occupied := Rect2(point-PREP_HALF,PREP_HALF*2)
			if not Rect2(90,90,7820,6820).encloses(occupied.grow(680)): continue
			if occupied.grow(680).intersects(stove_box): continue
			if occupied.grow(30).intersects(oven_sweep): continue
			if occupied.end.x > 5450: continue # preserve the right-hand approach to the passage
			if occupied.grow(340).has_point(Vector2(SPAWN.x,SPAWN.z)*1000.0): continue
			var cost := point.distance_squared_to(original)
			if cost < best_cost:
				best = point
				best_cost = cost
	if not best.is_finite(): return {}
	var fitted := document.duplicate(true)
	for prop in fitted.props:
		if prop.id != "prep": continue
		prop.x = best.x/1000.0
		prop.z = best.y/1000.0
	return fitted

static func layout(document: Dictionary) -> Dictionary:
	var floors: Array[Vector2i] = []
	var patterns := {}
	for layer in document.layers:
		if layer.id != document.activeLayerId: continue
		for coords in layer.polygons:
			var polygon := PackedVector2Array()
			for p in coords: polygon.append(Vector2(p[0],p[1]))
			if polygon.size() < 3: continue
			var bounds := Rect2(polygon[0],Vector2.ZERO)
			for p in polygon: bounds = bounds.expand(p)
			for x in range(floori(bounds.position.x),ceili(bounds.end.x)):
				for z in range(floori(bounds.position.y),ceili(bounds.end.y)):
					var p := Vector2i(x,z)
					if not patterns.has(p) and Geometry2D.is_point_in_polygon(Vector2(p)+Vector2(0.5,0.5),polygon):
						patterns[p] = 11
						floors.append(p)
	var prep := Vector2.ZERO
	for prop in document.props:
		if prop.id == "prep": prep = Vector2(prop.x,prop.z)
	var segments: Array[Vector4i] = []
	for wall in document.walls:
		for i in wall.points.size()-1:
			var a := Vector2(wall.points[i][0],wall.points[i][2])
			var b := Vector2(wall.points[i+1][0],wall.points[i+1][2])
			var axis := a.direction_to(b)
			for step in roundi(a.distance_to(b)):
				var passable := false
				for op in wall.openings:
					if op.segment == i and op.bottom == 0.0 and absf(step+0.5-op.center) <= op.width*0.5: passable = true
				if passable: continue
				var start := Vector2i((a+axis*step).round())
				var end := Vector2i((a+axis*(step+1)).round())
				if start.x > end.x or start.y > end.y:
					var swap := start
					start = end
					end = swap
				segments.append(Vector4i(start.x,start.y,end.x,end.y))
	return {"floors":floors,"patterns":patterns,"segments":segments,"windows":{},"avatars":PackedVector2Array(),"objects":[
		{"role":"entry","position":Vector2(4,6.85),"interior":Vector2(4,6.35),"label":"Entry","guid":0,"yaw":0.0,"layout_only":true},
		{"role":"exit","position":Vector2(6.3,-4.25),"interior":Vector2(6.3,-4.25),"label":"Cold store crossing","guid":0,"yaw":0.0,"layout_only":true},
		{"role":"inspect","position":prep+Vector2(0,0.88),"label":"Cook's notebook","guid":0,"yaw":0.0,"layout_only":true}]}

func build(document: Dictionary, floor_cells: Array) -> void:
	plan = document
	cells.assign(floor_cells)
	floor_mat.shader = Tile
	floor_mat.set_shader_parameter("glaze", Color("574d44"))
	wall_mat.shader = Tile
	wall_mat.set_shader_parameter("glaze", Color("aa9378"))
	wall_mat.set_shader_parameter("wall",true)
	for material in [floor_mat,wall_mat]:
		material.set_shader_parameter("kitchen_weathering",true)
		material.set_shader_parameter("wear_masks",Masks.kitchen_texture())
	_set_finish(wood,Color("77513a"),true)
	_set_finish(metal,Color("494644"),false)
	paper.albedo_color = Color("cbb38a")
	brass.albedo_color = Color("977248")
	brass.metallic = 0.58
	var solids := shell_prisms(document, cells)
	_add_solid("JoinedShell", solids, [floor_mat, wall_mat, metal])
	for wall in plan.walls: _build_frames(wall)
	for prop in plan.props: anchors[prop.id] = Vector3(prop.x,prop.y,prop.z)
	_build_furniture()
	_build_openings()
	_lighting()

static func shell_prisms(document: Dictionary, floor_cells: Array) -> Array:
	var solids := []
	for cell: Vector2i in floor_cells:
		solids.append(Shell.prism(Vector3(cell.x,-0.16,cell.y),Vector3(cell.x+1,0,cell.y+1),0))
		solids.append(Shell.prism(Vector3(cell.x,3.15,cell.y),Vector3(cell.x+1,3.33,cell.y+1),2))
	for wall in document.walls:
		for i in wall.points.size()-1:
			var a := Vector3(wall.points[i][0],wall.baseY,wall.points[i][2])
			var b := Vector3(wall.points[i+1][0],wall.baseY,wall.points[i+1][2])
			var axis := a.direction_to(b)
			var length := a.distance_to(b)
			var holes := []
			for op in wall.openings:
				if op.segment == i: holes.append(op)
			holes.sort_custom(func(l,r): return l.center < r.center)
			var cursor := 0.0
			for op in holes:
				var left: float = op.center-op.width*0.5
				var right: float = op.center+op.width*0.5
				_wall_prism(solids,a,axis,wall.thickness,cursor,left,0,wall.height)
				_wall_prism(solids,a,axis,wall.thickness,left,right,0,op.bottom)
				_wall_prism(solids,a,axis,wall.thickness,left,right,op.bottom+op.height,wall.height)
				cursor = right
			_wall_prism(solids,a,axis,wall.thickness,cursor,length,0,wall.height)
	return solids

static func _wall_prism(solids: Array, origin: Vector3, axis: Vector3, depth: float, a: float, b: float, bottom: float, top: float) -> void:
	if b-a < 0.001 or top-bottom < 0.001: return
	var side := axis.cross(Vector3.UP).abs()*depth*0.5
	var start := origin+axis*a
	var finish := origin+axis*b
	solids.append(Shell.prism(start.min(finish)-side+Vector3.UP*bottom, start.max(finish)+side+Vector3.UP*top, 1))

func _build_frames(wall: Dictionary) -> void:
	for op in wall.openings:
		var a := Vector3(wall.points[op.segment][0],wall.baseY,wall.points[op.segment][2])
		var b := Vector3(wall.points[op.segment+1][0],wall.baseY,wall.points[op.segment+1][2])
		var axis := a.direction_to(b)
		var frame := Node3D.new()
		add_child(frame)
		frame.position = a+axis*float(op.center)+Vector3.UP*float(op.bottom)
		frame.rotation.y = atan2(-axis.z,axis.x)
		openings[op.id] = {"root":frame,"w":op.width,"h":op.height}
		const TRIM := 0.04
		for sign_x in [-1,1]:
			box(frame,Vector3(sign_x*(op.width-TRIM)*0.5,(op.height-TRIM)*0.5,0),Vector3(TRIM,op.height-TRIM,wall.thickness),metal)
		box(frame,Vector3(0,op.height-TRIM*0.5,0),Vector3(op.width,TRIM,wall.thickness),metal)

func _build_furniture() -> void:
	var prep: Vector3 = anchors.prep
	var worktop := [Shell.prism(prep+Vector3(-PREP_HALF.x*0.001,0.90,-PREP_HALF.y*0.001),prep+Vector3(PREP_HALF.x*0.001,1.04,PREP_HALF.y*0.001),0)]
	for x in [-1.16,1.16]:
		for z in [-0.37,0.37]:
			var foot := prep+Vector3(x,0,z)
			worktop.append(Shell.prism(foot+Vector3(-0.075,0,-0.075),foot+Vector3(0.075,0.90,0.075),0))
	_add_solid("Worktable",worktop,[wood])
	for i in [-1,1]:
		var page := box(self,prep+Vector3(i*0.145,1.054,0.14),Vector3(0.29,0.026,0.38),paper)
		page.rotation.z = i*0.085
		for line in 5: box(page,Vector3(0,0.014,0.09-line*0.043),Vector3(0.19-float(line%2)*0.04,0.001,0.006),wood)
	var range_pos: Vector3 = anchors.range
	var carcass := [
		Shell.prism(range_pos+Vector3(-0.80,0,-1.17),range_pos+Vector3(0.80,0.27,1.17),0),
		Shell.prism(range_pos+Vector3(-0.80,0.97,-1.17),range_pos+Vector3(0.80,1.15,1.17),0),
		Shell.prism(range_pos+Vector3(-0.80,0.27,-1.17),range_pos+Vector3(-0.02,0.97,1.17),0),
		Shell.prism(range_pos+Vector3(-0.02,0.27,-1.17),range_pos+Vector3(0.80,0.97,-0.625),0),
		Shell.prism(range_pos+Vector3(-0.02,0.27,0.625),range_pos+Vector3(0.80,0.97,1.17),0),
	]
	_add_solid("RangeCarcass",carcass,[metal])
	var ember := StandardMaterial3D.new()
	ember.albedo_color = Color("ab3310")
	ember.emission_enabled = true
	ember.emission = Color("ff631b")
	ember.emission_energy_multiplier = 2.0
	for i in 7: box(self,range_pos+Vector3(0.59,0.31+0.027*(i%3),-0.56+i*0.17),Vector3(0.24,0.095,0.14),ember)
	oven_door = _moving_body(self)
	oven_door.position = range_pos+Vector3(OVEN_HINGE_X*0.001,0.33,0)
	box(oven_door,Vector3(0,0.27,0),Vector3(0.09,0.55,1.25),metal,true)
	box(oven_door,Vector3(0.12,0.47,0),Vector3(0.15,0.07,0.48),brass)
	oven_door.rotation.z = -1.0
	appliances.oven = (range_pos+Vector3(1.10,0,1.02))
	var hood := CylinderMesh.new()
	hood.top_radius = 0.62
	hood.bottom_radius = 1.02
	hood.height = 0.45
	hood.radial_segments = 4
	var hood_node := MeshInstance3D.new()
	hood_node.mesh = hood
	hood_node.material_override = metal
	add_child(hood_node)
	hood_node.position = range_pos+Vector3(0,2.27,0)
	hood_node.scale = Vector3(1.3,1.0,1.65)
	hood_node.rotation.y = PI*0.25
	box(self,range_pos+Vector3(0,2.83,0),Vector3(0.53,0.74,0.61),metal)
	for z in [-0.72,0.3]:
		var pot := CylinderMesh.new()
		pot.top_radius = 0.29
		pot.bottom_radius = 0.24
		pot.height = 0.35
		pot.radial_segments = 10
		var part := MeshInstance3D.new()
		part.mesh = pot
		part.material_override = metal
		add_child(part)
		part.position = range_pos+Vector3(0.38,1.33,z)
		box(self,part.position+Vector3(0,0.19,0),Vector3(0.16,0.09,0.06),brass)
	var store: Vector3 = anchors.storage
	for y in [0.12,0.9,1.65]: box(self,store+Vector3(0,y,0),Vector3(1.7,0.10,0.57),metal,true)
	for x in [-0.8,0.8]: box(self,store+Vector3(x,0.9,0),Vector3(0.07,1.8,0.06),metal,true)

func _build_openings() -> void:
	var hatch: Dictionary = openings.hatch
	var travel: float = hatch.h*0.61
	for sign_x in [-1,1]:
		box(hatch.root,Vector3(sign_x*(hatch.w*0.5-0.025),(hatch.h+travel)*0.5,0.15),Vector3(0.042,hatch.h+travel,0.12),metal)
	box(hatch.root,Vector3(0,-0.045,0.235),Vector3(hatch.w-0.08,0.09,0.29),wood)
	shutter = _moving_body(hatch.root)
	shutter.position = Vector3(0,travel,0.15)
	box(shutter,Vector3(0,hatch.h*0.5,0),Vector3(hatch.w-0.12,hatch.h-0.02,0.085),metal,true)
	box(shutter,Vector3(0,0.12,0.12),Vector3(0.37,0.065,0.12),brass)
	appliances.hatch = hatch.root.global_position+Vector3(0,-1,0.47)
	var door: Dictionary = openings["cold-door"]
	cold_door = _moving_body(door.root)
	cold_door.position.x = -door.w*0.5+0.14
	box(cold_door,Vector3(door.w*0.5-0.14,door.h*0.5,0),Vector3(door.w-0.28,door.h-0.06,0.13),metal,true)
	box(cold_door,Vector3(door.w-0.43,1.03,0.13),Vector3(0.12,0.31,0.14),brass)
	cold_door.rotation.y = 0.88
	appliances["cold-door"] = door.root.global_position+Vector3(0,0,0.60)

func _moving_body(root: Node3D) -> AnimatableBody3D:
	var part := AnimatableBody3D.new()
	part.sync_to_physics = false
	root.add_child(part)
	return part

func targets() -> Array[Dictionary]:
	return [{"kind":"fixture","id":"hatch","position":appliances.hatch,"label":"Serving shutter"},
		{"kind":"fixture","id":"cold-door","position":appliances["cold-door"],"label":"Cold store door"},
		{"kind":"fixture","id":"oven","position":appliances.oven,"label":"Oven door"}]

func toggle(id: String, actor_position: Vector3) -> bool:
	if not closed.has(id) or moving.has(id): return false
	var local := to_local(actor_position)
	var displacement := Vector2(local.x,local.z)
	# Decline operations from inside a conservative fixture sweep plus capsule radius.
	if id == "cold-door":
		var pivot: Vector3 = to_local(cold_door.global_position)
		var width: float = openings[id].w-0.28
		if Rect2(pivot.x-0.08,pivot.z-width-0.12,width+0.23,width+0.27).grow(0.29).has_point(displacement): return false
	if id == "oven":
		var pivot: Vector3 = to_local(oven_door.global_position)
		if Rect2(pivot.x-0.05,pivot.z-OVEN_SWEEP_HALF.y*0.001, (OVEN_SWEEP_HALF.x+50)*0.001,OVEN_SWEEP_HALF.y*0.002).grow(0.29).has_point(displacement): return false
	closed[id] = not closed[id]
	moving[id] = true
	var shut: bool = closed[id]
	var tween := create_tween().set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN_OUT)
	match id:
		"hatch": tween.tween_property(shutter,"position:y",0.0 if shut else float(openings.hatch.h)*0.61,0.64)
		"cold-door":
			tween.tween_property(cold_door,"rotation:y",0.0 if shut else 0.88,0.76)
			tween.parallel().tween_property(cold_light,"light_energy",0.0 if shut else 3.1,0.76)
		"oven": tween.tween_property(oven_door,"rotation:z",0.0 if shut else -1.0,0.55)
	tween.tween_callback(func(): moving.erase(id))
	return true

func _lighting() -> void:
	var fill := OmniLight3D.new()
	add_child(fill)
	fill.position = Vector3(3.7,2.7,3.4)
	fill.light_color = Color("e3c5a0")
	fill.light_energy = 1.05
	fill.omni_range = 6.2
	fill.shadow_enabled = true
	var hearth := OmniLight3D.new()
	add_child(hearth)
	hearth.position = anchors.range+Vector3(0.99,0.53,0.0)
	hearth.light_color = Color("ff9a50")
	hearth.light_energy = 3.5
	hearth.omni_range = 6.0
	hearth.shadow_enabled = true
	var cold := OmniLight3D.new()
	add_child(cold)
	cold.position = Vector3(6.8,2.64,-3.55)
	cold.light_color = Color("86f1f2")
	cold.light_energy = 1.55
	cold.omni_range = 3.6
	cold.shadow_enabled = true
	cold_light = SpotLight3D.new()
	add_child(cold_light)
	cold_light.position = Vector3(6.85,2.18,-2.18)
	cold_light.look_at(Vector3(6.52,0.0,1.1))
	cold_light.light_color = Color("84edf3")
	cold_light.light_energy = 3.1
	cold_light.spot_range = 5.2
	cold_light.spot_angle = 20
	cold_light.shadow_enabled = true

func _set_finish(material: ShaderMaterial, color: Color, timber: bool) -> void:
	material.shader = Finish
	material.set_shader_parameter("wear_masks",Masks.kitchen_texture())
	material.set_shader_parameter("base",color)
	material.set_shader_parameter("timber",timber)

func _add_solid(name_hint: String, solids: Array, materials: Array[Material]) -> void:
	var instance := MeshInstance3D.new()
	instance.name = name_hint
	instance.mesh = Shell.mesh_of(Shell.compile(solids).faces, materials)
	instance.gi_mode = GeometryInstance3D.GI_MODE_STATIC
	add_child(instance)
	instance.create_trimesh_collision()

func box(root: Node3D, pos: Vector3, size: Vector3, mat: Material, collision := false) -> MeshInstance3D:
	var item := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = size
	item.mesh = mesh
	item.material_override = mat
	item.position = pos
	root.add_child(item)
	if collision:
		var body := root as PhysicsBody3D
		if body == null:
			body = StaticBody3D.new()
			item.add_child(body)
		var hit := CollisionShape3D.new()
		var bounds := BoxShape3D.new()
		bounds.size = size
		hit.shape = bounds
		if body == root: hit.position = pos
		body.add_child(hit)
	return item
