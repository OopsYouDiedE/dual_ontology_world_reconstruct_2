extends RefCounted
## A run-local camp. The host owns the world clock and the captain input controller.

## Announces the camp mode; the captain remains under player input in both modes.
signal control_changed(mode: StringName, captain_id: String)

const TICK_SECONDS := 0.25
const NEED_MAX := 100
const NEED_TRIGGER := 60
const NEEDS := ["hunger", "fatigue", "social"]
const GROWTH := [2, 1, 1]
const MAX_EVENTS := 128
const MAX_STALL := 4

var _graph: Dictionary = {}
var _residents: Dictionary = {}
var _objects: Dictionary = {}
var _stands: Dictionary = {}
var _events: Array[Dictionary] = []
var _captain := ""
var _in_camp := false
var _tick := 0


## Reconfigure only outside camp. Reject bad data without changing the existing camp.
func setup(captain_id: String, graph: Dictionary, residents: Array, objects: Array) -> bool:
	if _in_camp or captain_id.is_empty() or graph.is_empty():
		return false
	for cell in graph:
		if not cell is Vector2i or not graph[cell] is Array:
			return false
		for neighbor in graph[cell]:
			if not neighbor is Vector2i or not graph.has(neighbor) or cell.distance_squared_to(neighbor) != 1:
				return false
	var people := {}
	var occupied := {}
	for row in residents:
		if not row is Dictionary or not row.get("id") is String or row.id.is_empty() or row.id == captain_id or people.has(row.id):
			return false
		var cell: Variant = row.get("cell")
		if not graph.has(cell) or occupied.has(cell) or not row.get("needs", {}) is Dictionary:
			return false
		var needs := {}
		for need in NEEDS:
			var value: Variant = row.get("needs", {}).get(need, 0)
			if not value is int or value < 0 or value > NEED_MAX:
				return false
			needs[need] = value
		people[row.id] = {"cell": cell, "needs": needs, "job": {}, "return_to": null, "status": &"idle"}
		occupied[cell] = true
	var fixtures := {}
	var stands := {}
	for row in objects:
		if not row is Dictionary or not row.get("id") is String or row.id.is_empty() or fixtures.has(row.id):
			return false
		if not graph.has(row.get("stand")) or stands.has(row.stand) or not NEEDS.has(row.get("need")):
			return false
		if not row.get("duration") is int or row.duration < 1 or not row.get("relief") is int or row.relief < 1 or row.relief > NEED_MAX:
			return false
		var stock: Variant = row.get("stock", -1)
		if not stock is int or stock < -1:
			return false
		fixtures[row.id] = {"stand": row.stand, "need": row.need, "duration": row.duration,
			"relief": row.relief, "stock": stock, "reserved_by": ""}
		stands[row.stand] = true
	_graph = graph.duplicate(true)
	_residents = people
	_objects = fixtures
	_stands = stands
	_events.clear()
	_captain = captain_id
	_tick = 0
	return true


func enter_camp() -> bool:
	if _captain.is_empty() or _in_camp:
		return false
	_in_camp = true
	control_changed.emit(&"camp_ai", _captain)
	return true


## Release companion jobs atomically; the captain is already under player control.
func leave_camp() -> bool:
	if not _in_camp:
		return false
	for id in _sorted_ids(_residents):
		if not _residents[id].job.is_empty():
			_finish(id, &"cancelled", &"left_camp")
		_residents[id].return_to = null
		_residents[id].status = &"idle"
	_in_camp = false
	control_changed.emit(&"captain", _captain)
	return true


## One 250 ms simulation step. Outside camp all simulation is suspended.
func step() -> void:
	if not _in_camp:
		return
	_tick += 1
	var ids := _sorted_ids(_residents)
	if ids.is_empty():
		return
	var first := (_tick - 1) % ids.size()
	for id in ids:
		for i in NEEDS.size():
			var need: String = NEEDS[i]
			var needs: Dictionary = _residents[id].needs
			needs[need] = mini(NEED_MAX, needs[need] + GROWTH[i])
	# Rotate who gets first choice; a job already in progress keeps its reservation.
	for i in ids.size():
		var id := ids[(first + i) % ids.size()]
		if _residents[id].return_to != null:
			_clear_aisle(id)
		elif _residents[id].job.is_empty():
			_choose(id)
		else:
			_progress(id)


func snapshot() -> Dictionary:
	return {"tick": _tick, "mode": &"camp_ai" if _in_camp else &"captain", "captain_id": _captain,
		"residents": _residents.duplicate(true), "objects": _objects.duplicate(true), "events": _events.duplicate(true)}


func _sorted_ids(rows: Dictionary) -> Array[String]:
	var ids: Array[String] = []
	ids.assign(rows.keys())
	ids.sort()
	return ids


func _choose(id: String) -> void:
	var resident: Dictionary = _residents[id]
	resident.status = &"idle"
	var best := ""
	var best_need := -1
	var best_ticks := 0
	var saw_need := false
	for need in NEEDS:
		saw_need = saw_need or resident.needs[need] >= NEED_TRIGGER
	for fixture_id in _sorted_ids(_objects):
		var fixture: Dictionary = _objects[fixture_id]
		var urgency: int = resident.needs[fixture.need]
		if urgency < NEED_TRIGGER or fixture.stock == 0 or fixture.reserved_by != "":
			continue
		var path := _route(id, fixture.stand)
		if path.is_empty():
			continue
		var cost: int = path.size() - 1 + fixture.duration
		if urgency > best_need or (urgency == best_need and cost < best_ticks):
			best = fixture_id
			best_need = urgency
			best_ticks = cost
	if best.is_empty():
		if saw_need:
			resident.status = &"waiting_for_object"
		_yield_stand(id)
		return
	var target: Dictionary = _objects[best]
	target.reserved_by = id
	resident.job = {"object_id": best, "remaining": target.duration, "stall": 0, "origin": resident.cell}
	_record(id, best, &"reserved")
	if resident.cell == target.stand:
		_start(id, best)
	else:
		resident.status = &"walking"


## Free the interaction tile on a subsequent step, if there is a free aisle.
func _yield_stand(id: String) -> void:
	var cell: Vector2i = _residents[id].cell
	if not _stands.has(cell):
		return
	for neighbor in _graph[cell]:
		if not _stands.has(neighbor) and _route(id, neighbor).size() == 2:
			_residents[id].cell = neighbor
			return


## Backtrack towards the pre-job tile instead of idling in the approach aisle.
func _clear_aisle(id: String) -> void:
	var resident: Dictionary = _residents[id]
	var path := _route(id, resident.return_to)
	if path.size() > 1:
		resident.cell = path[1]
	else:
		_yield_stand(id)
	if path.size() <= 2:
		resident.return_to = null
		resident.status = &"idle"


func _progress(id: String) -> void:
	var resident: Dictionary = _residents[id]
	var job: Dictionary = resident.job
	var fixture_id: String = job.object_id
	var fixture: Dictionary = _objects[fixture_id]
	if resident.status == &"walking":
		var path := _route(id, fixture.stand)
		if path.size() < 2:
			job.stall += 1
			if job.stall >= MAX_STALL:
				_finish(id, &"cancelled", &"path_blocked")
			return
		resident.cell = path[1]
		job.stall = 0
		if resident.cell == fixture.stand:
			_start(id, fixture_id)
		return
	job.remaining -= 1
	if job.remaining == 0:
		var before: int = resident.needs[fixture.need]
		resident.needs[fixture.need] = maxi(0, before - fixture.relief)
		if fixture.stock > 0:
			fixture.stock -= 1
		_finish(id, &"completed", &"", before - resident.needs[fixture.need])


func _start(id: String, fixture_id: String) -> void:
	_residents[id].status = &"using_object"
	_record(id, fixture_id, &"started")


func _finish(id: String, kind: StringName, reason: StringName, relief: int = 0) -> void:
	var resident: Dictionary = _residents[id]
	var fixture_id: String = resident.job.object_id
	_objects[fixture_id].reserved_by = ""
	var origin: Vector2i = resident.job.origin
	resident.job = {}
	resident.status = &"idle"
	if kind == &"completed" and origin != resident.cell:
		resident.return_to = origin
		resident.status = &"clearing_aisle"
	_record(id, fixture_id, kind, reason, relief)


func _record(id: String, fixture_id: String, kind: StringName, reason: StringName = &"", relief: int = 0) -> void:
	_events.append({"tick": _tick, "resident_id": id, "object_id": fixture_id, "kind": kind,
		"reason": reason, "relief": relief, "need": _objects[fixture_id].need, "stock": _objects[fixture_id].stock})
	if _events.size() > MAX_EVENTS:
		_events.pop_front()


## BFS over host-supplied walkable edges, with live actor and stand occupancy.
func _route(id: String, finish: Vector2i) -> Array[Vector2i]:
	var start: Vector2i = _residents[id].cell
	var blocked := {}
	for other in _residents:
		if other != id:
			blocked[_residents[other].cell] = true
	for fixture in _objects.values():
		if fixture.reserved_by != "" and fixture.reserved_by != id:
			blocked[fixture.stand] = true
	var queue: Array[Vector2i] = [start]
	var prior := {start: start}
	var index := 0
	while index < queue.size():
		var cell := queue[index]
		index += 1
		if cell == finish:
			var path: Array[Vector2i] = [cell]
			while cell != start:
				cell = prior[cell]
				path.append(cell)
			path.reverse()
			return path
		for neighbor in _graph[cell]:
			if not blocked.has(neighbor) and not prior.has(neighbor):
				prior[neighbor] = cell
				queue.append(neighbor)
	return []
