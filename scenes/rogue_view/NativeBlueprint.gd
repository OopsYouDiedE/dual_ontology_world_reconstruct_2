extends RefCounted
## Reads the authored native XmlHouse geometry without adding any layout.

const Edges = preload("res://scenes/rogue_view/FreeSoSnapshot.gd").EDGES

static func read(path: String, level: int = 1) -> Dictionary:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return {"error": FileAccess.get_open_error()}
	if file.get_length() > 8 * 1024 * 1024:
		return {"error": ERR_FILE_CORRUPT}
	var xml := XMLParser.new()
	if xml.open_buffer(file.get_buffer(file.get_length())) != OK:
		return {"error": ERR_PARSE_ERROR}
	var stack: PackedStringArray = []
	var side := 0
	var floors: Dictionary = {}
	var edges: Dictionary = {}
	var objects: Array[Dictionary] = []
	var has_world := false
	var closed := false
	var status := xml.read()
	while status == OK:
		match xml.get_node_type():
			XMLParser.NODE_ELEMENT:
				var tag := xml.get_node_name()
				var parent := stack[-1] if not stack.is_empty() else ""
				if stack.is_empty() and (closed or tag != "house" or xml.is_empty()):
					return {"error": ERR_FILE_UNRECOGNIZED}
				if parent == "house" and tag == "world":
					has_world = true
				var attributes := {}
				for i in xml.get_attribute_count():
					attributes[xml.get_attribute_name(i)] = xml.get_attribute_value(i)
				var cell := Vector2i(_int(attributes, "x", -1), _int(attributes, "y", -1))
				if cell.x >= 0 and cell.y >= 0:
					if tag == "floor" and parent == "floors" and _int(attributes, "level", 0) == level - 1:
						var pattern := _int(attributes, "value", 0)
						if pattern > 0:
							floors[cell] = pattern
					elif tag == "pool" and parent == "pools" and level == 1:
						floors[cell] = 65535
					elif tag == "wall" and parent == "walls" and _int(attributes, "level", 0) == level - 1:
						var mask := _int(attributes, "segments", 0)
						for bit: int in Edges:
							if mask & bit:
								var edge: Vector4i = Edges[bit] + Vector4i(cell.x, cell.y, cell.x, cell.y)
								edges[edge] = true
					elif tag == "object" and parent == "objects" and _int(attributes, "level", 0) == level:
						var guid: String = attributes.get("guid", "")
						if not guid.is_valid_hex_number(true) or guid.hex_to_int() <= 0 or guid.hex_to_int() > 0xffffffff:
							return {"error": ERR_INVALID_DATA}
						objects.append({"position": Vector2(cell) + Vector2(0.5, 0.5), "guid": guid.hex_to_int(),
							"yaw": -_int(attributes, "dir", 0) * PI / 4.0, "label": attributes.get("plan_label", ""),
							"role": attributes.get("plan_role", ""), "dir": _int(attributes, "dir", 0), "cell": cell})
				if not xml.is_empty():
					stack.append(tag)
			XMLParser.NODE_ELEMENT_END:
				if stack.is_empty() or stack[-1] != xml.get_node_name():
					return {"error": ERR_PARSE_ERROR}
				stack.resize(stack.size() - 1)
				closed = stack.is_empty()
			XMLParser.NODE_TEXT:
				if stack == PackedStringArray(["house", "size"]):
					var value := xml.get_node_data().strip_edges()
					if value.is_valid_int():
						side = value.to_int()
		status = xml.read()
	if status != ERR_FILE_EOF or not closed or not has_world or side < 1 or side > 128 or floors.is_empty():
		return {"error": ERR_INVALID_DATA}
	var bounds := Rect2i(0, 0, side, side)
	for cell: Vector2i in floors:
		if not bounds.has_point(cell):
			return {"error": ERR_INVALID_DATA}
	for edge: Vector4i in edges:
		if edge.x > side or edge.y > side or edge.z > side or edge.w > side:
			return {"error": ERR_INVALID_DATA}
	for item in objects:
		if not bounds.has_point(item.cell):
			return {"error": ERR_INVALID_DATA}
	_add_landmarks(path, level, objects, floors, edges)
	var windows := {}
	for item in objects:
		if item.role == "window":
			var edge: Vector4i = item.get("window_edge", _window_edge(item.cell, item.dir, edges))
			if edge != Vector4i.ZERO: windows[edge] = true
	return {"error": OK, "lot": {"width": side, "height": side, "segments": edges.keys(),
		"windows": windows, "floors": floors.keys(), "patterns": floors, "objects": objects, "avatars": PackedVector2Array()}}

static func _add_landmarks(path: String, level: int, objects: Array[Dictionary], floors: Dictionary, edges: Dictionary) -> void:
	var metadata := FileAccess.open(path.get_base_dir().path_join("plan_landmarks.json"), FileAccess.READ)
	if metadata == null or metadata.get_length() > 1024 * 1024: return
	var index: Variant = JSON.parse_string(metadata.get_as_text())
	if not index is Dictionary: return
	var rows: Variant = index.get(path.get_file().get_basename(), [])
	if not rows is Array: return
	for row: Variant in rows:
		if not row is Dictionary or row.get("level") != level - 1: continue
		var role: Variant = row.get("role")
		var label: Variant = row.get("label")
		if role not in ["entry", "exit", "focal", "inspect", "landmark", "window"] or not label is String: continue
		if not (row.get("x") is int or row.get("x") is float) or not (row.get("y") is int or row.get("y") is float): continue
		var cell := Vector2i(int(row.x), int(row.y))
		var position := Vector2(cell) + Vector2(0.5, 0.5)
		if role == "window":
			var guid: Variant = row.get("guid")
			var edge := _edge_at(cell, row.get("edge", ""))
			if not guid is String or not guid.is_valid_hex_number(true) or not edges.has(edge): continue
			for item in objects:
				if item.cell == cell and item.guid == guid.hex_to_int() and item.dir == row.get("dir"):
					item.role = "window"
					item.label = label
					item.window_edge = edge
					break
			continue
		if role in ["entry", "exit"]:
			match row.get("edge", ""):
				"TopLeft": position.x -= 0.5
				"TopRight": position.y -= 0.5
				"BottomLeft": position.y += 0.5
				"BottomRight": position.x += 0.5
			# A threshold annotation denotes an existing authored opening, not a new object.
			if edges.has(_edge_at(cell, row.get("edge", ""))): continue
			objects.append({"position": position, "label": label, "role": role, "guid": 0, "yaw": 0.0, "annotation_only": true, "interior": Vector2(cell) + Vector2(0.5, 0.5)})
			continue
		var matched := false
		for item in objects:
			if item.get("cell") == cell and item.role.is_empty():
				item.label = label
				item.role = role
				matched = true
				break
		if not matched and floors.has(cell):
			objects.append({"position": position, "label": label, "role": role, "guid": 0, "yaw": 0.0, "annotation_only": true})


static func _int(attributes: Dictionary, key: String, fallback: int) -> int:
	var value: String = attributes.get(key, "")
	return value.to_int() if value.is_valid_int() else fallback


static func _window_edge(cell: Vector2i, direction: int, edges: Dictionary) -> Vector4i:
	# Prefer the facing edge; some wall-mounted objects face into the room.
	# Only accept an existing segment on that axis; never cut a perpendicular wall.
	var direction_edges := {0: [2, 8], 2: [4, 1], 4: [8, 2], 6: [1, 4]}
	for bit: int in direction_edges.get(direction, []):
		var edge: Vector4i = Edges[bit] + Vector4i(cell.x, cell.y, cell.x, cell.y)
		if edges.has(edge): return edge
	return Vector4i.ZERO


static func _edge_at(cell: Vector2i, name: String) -> Vector4i:
	var bit: int = {"TopLeft": 1, "TopRight": 2, "BottomRight": 4, "BottomLeft": 8}.get(name, 0)
	if bit == 0: return Vector4i.ZERO
	return Edges[bit] + Vector4i(cell.x, cell.y, cell.x, cell.y)
