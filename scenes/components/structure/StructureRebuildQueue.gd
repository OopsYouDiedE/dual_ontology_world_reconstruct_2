extends RefCounted
## Rebuild scheduler for StructurePiece3D: coalesces change requests, rebuilds every piece
## at most once per flush, skips pieces whose inputs did not change, and stops runaway
## chains (MAX_ROUNDS rounds, MAX_REBUILDS rebuilds per flush) with a warning instead of
## freezing the editor. Also owns a per-scope grid index for neighbour lookup.

const CELL := 4.0
const MAX_ROUNDS := 3
const MAX_REBUILDS := 4000

static var _shape := {}      # instance id -> piece whose shape changed
static var _mesh := {}       # instance id -> {node, force}
static var _scheduled := false
static var _batch := 0
static var _index := {}      # scope instance id -> {Vector2i cell: Array[piece]}
static var _old_bounds := {} # instance id -> Rect2 at last build (finds former neighbours)
static var _removed: Array = [] # [scope, Rect2] of pieces that left the tree
## Tests switch the editor-only rules (neighbour propagation) on outside the editor.
static var force_editor_rules := false
## Counters for tests and the editor dock.
static var stats := {"flushes": 0, "rebuilds": 0, "skipped": 0, "dropped": 0, "capped": 0, "last_rounds": 0, "last_rebuilds": 0}

static func _bump(key: String, by: int) -> void:
	stats[key] = int(stats.get(key, 0)) + by

static func editor_rules() -> bool:
	return Engine.is_editor_hint() or force_editor_rules

static func request(piece: Node, shape: bool, force: bool) -> void:
	var id := piece.get_instance_id()
	if shape:
		_shape[id] = piece
	var entry: Dictionary = _mesh.get(id, {"node": piece, "force": false})
	entry.force = entry.force or force
	_mesh[id] = entry
	_schedule()

## Group many edits (scene load, a drag, an undo step) into one flush at end_batch().
static func begin_batch() -> void:
	_batch += 1

static func end_batch() -> void:
	_batch = maxi(0, _batch - 1)
	if _batch == 0 and not (_shape.is_empty() and _mesh.is_empty()):
		flush()

## A piece left the tree: its former neighbours re-check at the next flush, if its scope
## is still live then (a closing or hidden scene costs nothing).
static func removed(scope: Node, piece: Node) -> void:
	var id := piece.get_instance_id()
	_removed.append([scope, _old_bounds.get(id, Rect2())])
	_old_bounds.erase(id)
	_schedule()

static func pending() -> int:
	return _mesh.size()

static func remember(piece: Node) -> void:
	_old_bounds[piece.get_instance_id()] = piece.plan_bounds()

static func _schedule() -> void:
	if _scheduled or _batch > 0:
		return
	_scheduled = true
	(func(): flush()).call_deferred()

static func _live(p) -> bool:
	return is_instance_valid(p) and p.is_inside_tree() and not p.is_queued_for_deletion()

static func flush() -> void:
	_scheduled = false
	var gone := _removed
	_removed = []
	for item in gone:
		var sc = item[0]
		if is_instance_valid(sc) and sc.is_inside_tree() and not sc.is_queued_for_deletion():
			invalidate(sc)
			for n in query(sc, item[1]):
				_mesh[n.get_instance_id()] = {"node": n, "force": true}
	if _shape.is_empty() and _mesh.is_empty():
		return
	_bump("flushes", 1)
	var built := {}
	var rounds := 0
	var count := 0
	var dropped: Array = []
	while not (_shape.is_empty() and _mesh.is_empty()) and rounds < MAX_ROUNDS:
		rounds += 1
		var shapes := _shape
		var meshes := _mesh
		_shape = {}
		_mesh = {}
		for id in shapes:
			if _live(shapes[id]):
				invalidate(shapes[id].scope())
		# Editor only: a changed shape reaches the pieces around its old and new place.
		if editor_rules():
			for id in shapes:
				var p = shapes[id]
				if not _live(p):
					continue
				var areas: Array = [p.plan_bounds()]
				if _old_bounds.has(id):
					areas.append(_old_bounds[id])
				for area: Rect2 in areas:
					for n in query(p.scope(), area, p):
						var nid: int = n.get_instance_id()
						if not meshes.has(nid):
							meshes[nid] = {"node": n, "force": false}
		for id in meshes:
			var entry: Dictionary = meshes[id]
			var p = entry.node
			if not _live(p):
				continue
			if built.has(id):
				_bump("dropped", 1)  # already rebuilt this flush: never twice
				dropped.append(p)
				continue
			if not entry.force and p.input_hash() == p._built_inputs:
				_bump("skipped", 1)
				continue
			if count >= MAX_REBUILDS:
				_shape[id] = p
				break
			var before: String = p._shape_signature()
			p.rebuild()
			p._built_inputs = p.input_hash()
			built[id] = true
			count += 1
			_old_bounds[id] = p.plan_bounds()
			# A build that moved its own shape (self-adjusting piece) tells its neighbours next round.
			if p._shape_signature() != before:
				_shape[id] = p
	_bump("rebuilds", count)
	stats["last_rounds"] = rounds
	stats["last_rebuilds"] = count
	if not (_shape.is_empty() and _mesh.is_empty()) or not dropped.is_empty():
		_bump("capped", 1)
		var names: Array = []
		for id in _shape:
			if is_instance_valid(_shape[id]):
				names.append(str(_shape[id].get_path()))
		for p in dropped:
			if is_instance_valid(p):
				names.append(str(p.get_path()))
		push_warning("StructureRebuildQueue: stopped a rebuild chain after %d rounds / %d rebuilds; still changing: %s" % [rounds, count, ", ".join(names.slice(0, 8))])
		_shape.clear()
		_mesh.clear()

# ── neighbour index ───────────────────────────────────────────────────────────

static func invalidate(scope: Node) -> void:
	if scope != null:
		_index.erase(scope.get_instance_id())

static func query(scope: Node, rect: Rect2, exclude: Node = null) -> Array:
	if scope == null or not is_instance_valid(scope):
		return []
	var sid := scope.get_instance_id()
	if not _index.has(sid):
		_index[sid] = _build_index(scope)
	var cells: Dictionary = _index[sid]
	var out: Array = []
	var seen := {}
	for cx in range(floori(rect.position.x / CELL), floori(rect.end.x / CELL) + 1):
		for cy in range(floori(rect.position.y / CELL), floori(rect.end.y / CELL) + 1):
			for p in cells.get(Vector2i(cx, cy), []):
				if p == exclude or seen.has(p) or not is_instance_valid(p):
					continue
				seen[p] = true
				if p.plan_bounds().intersects(rect, true):
					out.append(p)
	return out

static func _build_index(scope: Node) -> Dictionary:
	var cells := {}
	for p in scope.find_children("*", "", true, false):
		# Pieces generated inside another piece (a colonnade's columns) are its own business.
		if not p.has_method("_shape_signature") or p.has_meta(&"_structure_generated") or p.scope() != scope:
			continue
		var r: Rect2 = p.plan_bounds()
		for cx in range(floori(r.position.x / CELL), floori(r.end.x / CELL) + 1):
			for cy in range(floori(r.position.y / CELL), floori(r.end.y / CELL) + 1):
				var key := Vector2i(cx, cy)
				if not cells.has(key):
					cells[key] = []
				cells[key].append(p)
	return cells
