@tool
class_name LevelStructure3D
extends Node3D
## Root of a level's editable structure. Everything under it is an ordinary Godot node that
## can be moved and tuned in the editor and Inspector:
##   SmartFloorZone3D  floors (polygon, pattern, collision)
##   SmartWall3D       walls (start/end, height, thickness, openings, collision)
##   SmartStair3D / SmartRailing3D
##   catalog components (RecipeComponent and other @tool items)
##   LevelAnchor3D     named gameplay points and lot objects
##   LevelStation3D    reserved footprints (blocked cells + collider)
##   StructureColumn3D / StructureArch3D / Colonnade3D / StructureAssembly3D
##   LevelTrigger3D    zones and E-key triggers with ordered actions (LevelAction resources)
##   LevelMover3D      gates, lifts, doors: children moved between rest and open poses
## Gameplay never hand-builds a shell: it instances this scene and reads derive_lot()/anchor().

## A LevelTrigger3D under this structure fired (also sent to AcademyLevelBase._on_level_action).
signal trigger_fired(trigger_id: String, action_id: String, ctx: Dictionary)

@export var template_id: String = ""
@export var room_label: String = ""
## Side of the square lot grid (cells), as in the former FreeSO XML lots.
@export var lot_size: int = 32
## Optional upper-floor plan data for the overhead map (lot dictionary), carried over from the
## original lots. Data only: no geometry is built from it.
@export var upper_plan: Dictionary = {}
@export_group("Editor")
## Grid of the 2D plan tab and of 3D handle drags (metres; 0 = off).
@export var editor_grid: float = 0.25
## Moving a piece in 3D pulls its snap points onto a neighbour's within this distance (0 = off).
@export var editor_magnet: float = 0.2
@export_group("")
@export_tool_button("Rebuild structure", "Reload") var rebuild_action := rebuild_all
@export_multiline var summary: String = ""

func _ready() -> void:
	if Engine.is_editor_hint():
		refresh_summary()

# ── node queries (work both in and out of the scene tree) ─────────────────────

static func is_wall(node: Node) -> bool:
	return "start_point" in node and "end_point" in node and "openings" in node and "wall_height" in node

static func is_floor(node: Node) -> bool:
	return "polygon" in node and "floor_thickness" in node

func walls() -> Array:
	return _collect(is_wall)

func floors() -> Array:
	return _collect(is_floor)

func anchors() -> Array:
	return _collect(func(n): return n is LevelAnchor3D)

func stations_nodes() -> Array:
	return _collect(func(n): return n is LevelStation3D)

func triggers() -> Array:
	return _collect(func(n): return n is LevelTrigger3D)

func movers() -> Array:
	return _collect(func(n): return n is LevelMover3D)

## Trigger entries for the level manifest (AcademyLevelAudit schema).
func trigger_manifest() -> Array:
	return triggers().map(func(t): return t.manifest_entry())

func trigger(id: String) -> Node:
	for t in triggers():
		if t.resolved_id() == id:
			return t
	return null

func _collect(test: Callable) -> Array:
	var out: Array = []
	var stack: Array = get_children()
	while not stack.is_empty():
		var node: Node = stack.pop_front()
		if node.has_meta(&"_structure_generated") or (node.owner == null and node.get_parent() != self and Engine.is_editor_hint()):
			continue  # skip generated helpers
		if test.call(node):
			out.append(node)
		stack.append_array(node.get_children())
	return out

## Transform of `node` relative to this structure, computed without needing the tree.
func relative(node: Node3D) -> Transform3D:
	var xform := node.transform
	var parent := node.get_parent()
	while parent != null and parent != self:
		if parent is Node3D:
			xform = (parent as Node3D).transform * xform
		parent = parent.get_parent()
	return xform

func anchor(id: String, fallback := Vector3.ZERO) -> Vector3:
	for node: LevelAnchor3D in anchors():
		if node.anchor_id == id:
			return relative(node).origin
	return fallback

func has_anchor(id: String) -> bool:
	return anchors().any(func(n): return n.anchor_id == id)

func station_bounds() -> Array[Rect2]:
	var out: Array[Rect2] = []
	for node: LevelStation3D in stations_nodes():
		out.append(node.bounds_in(relative(node).origin))
	# Components that reserve their own footprints (furniture, lamps, arch cheeks…).
	for node in _collect(func(n): return n.has_method("reserved_stations")):
		out.append_array(node.reserved_stations())
	return out

## All named anchors: {anchor_id: position in structure space}.
func anchor_points() -> Dictionary:
	var out := {}
	for node: LevelAnchor3D in anchors():
		if node.anchor_id != "":
			out[node.anchor_id] = relative(node).origin
	return out

# ── gameplay lot (same shape as NativeBlueprint.read().lot) ────────────────────

static func edge(a: Vector2i, b: Vector2i) -> Vector4i:
	if a.x > b.x or a.y > b.y:
		var swap := a
		a = b
		b = swap
	return Vector4i(a.x, a.y, b.x, b.y)

func derive_lot() -> Dictionary:
	var patterns := {}
	var floors_list: Array = []
	for zone: Node3D in floors():
		var xform := relative(zone)
		var polygon := PackedVector2Array()
		for p: Vector2 in zone.polygon:
			var world := xform * Vector3(p.x, 0, p.y)
			polygon.append(Vector2(world.x, world.z))
		if polygon.size() < 3:
			continue
		var box := Rect2(polygon[0], Vector2.ZERO)
		for p in polygon:
			box = box.expand(p)
		for z in range(floori(box.position.y), ceili(box.end.y)):
			for x in range(floori(box.position.x), ceili(box.end.x)):
				var cell := Vector2i(x, z)
				if patterns.has(cell):
					continue
				if Geometry2D.is_point_in_polygon(Vector2(cell) + Vector2(0.5, 0.5), polygon):
					patterns[cell] = int(zone.pattern)
					floors_list.append(cell)
	var segments: Array = []
	var windows := {}
	for wall: Node3D in walls():
		var xform := relative(wall)
		var a3: Vector3 = xform * wall.start_point
		var b3: Vector3 = xform * wall.end_point
		var a := Vector2(a3.x, a3.z)
		var b := Vector2(b3.x, b3.z)
		var steps := roundi(a.distance_to(b))
		if steps < 1:
			continue
		var unit := (b - a) / float(steps)
		var length := a.distance_to(b)
		for step in steps:
			var along := (float(step) + 0.5) * length / float(steps)
			var door := false
			var window := false
			for op: Dictionary in wall.openings:
				if float(op.get("from", 0)) <= along and along <= float(op.get("to", 0)):
					if float(op.get("bottom", 0)) <= 0.01:
						door = true
					else:
						window = true
			if door:
				continue
			var e := edge(Vector2i((a + unit * step).round()), Vector2i((a + unit * (step + 1)).round()))
			segments.append(e)
			if window:
				windows[e] = true
	var objects: Array = []
	for node: LevelAnchor3D in anchors():
		if node.role != "":
			objects.append(node.lot_object(relative(node).origin))
	return {"width": lot_size, "height": lot_size, "segments": segments, "windows": windows,
		"floors": floors_list, "patterns": patterns, "objects": objects, "avatars": PackedVector2Array(),
		"template": template_id, "anchors": anchor_points()}

# ── editor helpers ────────────────────────────────────────────────────────────

func rebuild_all() -> void:
	for node in _collect(func(n): return n.has_method("rebuild") and n != self):
		node.rebuild()
	refresh_summary()

func refresh_summary() -> void:
	var lot := derive_lot()
	summary = "%d floors · %d walls · %d anchors · %d stations · %d triggers · %d movers
%d walkable cells · %d wall edges · %d lot objects" % [
		floors().size(), walls().size(), anchors().size(), stations_nodes().size(), triggers().size(), movers().size(),
		lot.floors.size(), lot.segments.size(), lot.objects.size()]
	notify_property_list_changed()
