extends Control
## High-contrast native overhead mode. Coordinates and IDs come from the lot.
var lot: Dictionary = {}
var _scale := 1.0
var _origin := Vector2.ZERO

func set_lot(value: Dictionary) -> void:
	lot = value
	queue_redraw()

func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), Color("111b22"))
	if lot.is_empty() or lot.floors.is_empty():
		return
	var bounds := Rect2i(lot.floors[0], Vector2i.ONE)
	for cell: Vector2i in lot.floors:
		bounds = bounds.merge(Rect2i(cell, Vector2i.ONE))
	for edge: Vector4i in lot.segments:
		bounds = bounds.expand(Vector2i(edge.x, edge.y)).expand(Vector2i(edge.z, edge.w))
	for item: Dictionary in lot.objects:
		bounds = bounds.expand(Vector2i(item.position.floor()))
	var extent := Vector2(bounds.size) + Vector2(2, 2)
	_scale = maxf(1.0, minf((size.x - 54) / extent.x, (size.y - 150) / extent.y))
	_origin = Vector2(size.x * 0.5, (size.y - 16) * 0.5) - (Vector2(bounds.position) + Vector2(bounds.size) * 0.5) * _scale
	var font := ThemeDB.fallback_font
	draw_string(font, Vector2(20, 72), "N ↑    Native tile grid   |   pale: walls   ·   blue: glazing", HORIZONTAL_ALIGNMENT_LEFT, -1, 15, Color("bcd6de"))
	for cell: Vector2i in lot.floors:
		var rect := Rect2(_point(Vector2(cell)), Vector2.ONE * _scale)
		draw_rect(rect, floor_color(int(lot.patterns.get(cell, 0))))
		draw_rect(rect, Color(0.09, 0.16, 0.20, 0.35), false, 1.0)
	for edge: Vector4i in lot.segments:
		var a := _point(Vector2(edge.x, edge.y))
		var b := _point(Vector2(edge.z, edge.w))
		draw_line(a, b, Color("101921"), 6.0, true)
		draw_line(a, b, Color("77d1f5") if lot.get("windows", {}).has(edge) else Color("f4edce"), 2.5, true)
	var callouts: Array[Dictionary] = []
	for item: Dictionary in lot.objects:
		var point := _point(item.position)
		var role: String = item.role
		if role == "window": continue
		var accent := Color("b0f2cf") if role == "entry" else Color("f4ca84") if role == "exit" else Color("a2e1ff")
		var labeled: bool = not String(item.label).is_empty() or role in ["entry", "exit", "focal"]
		draw_circle(point, 7 if labeled else 3.5, Color("111b22"))
		draw_circle(point, 5 if labeled else 2.5, accent)
		if labeled:
			var caption := String(item.label)
			if role in ["entry", "exit"] and not caption.to_lower().begins_with(role):
				caption = role.capitalize() if caption.is_empty() else role.capitalize() + " · " + caption
			if caption.is_empty(): caption = "Inspect"
			callouts.append({"point": point, "label": caption.left(45), "color": accent})
	var occupied: Array[Rect2] = []
	for note in callouts:
		var label_size := font.get_string_size(note.label, HORIZONTAL_ALIGNMENT_LEFT, -1, 15)
		var box_size := Vector2(label_size.x + 14, 24)
		var p: Vector2 = note.point
		for delta in [Vector2(10, -12), Vector2(-box_size.x - 10, -12), Vector2(2, -35), Vector2(2, 12), Vector2(2, 36), Vector2(2, -59)]:
			var rect := Rect2((p + delta).clamp(Vector2(12, 84), size - box_size - Vector2(12, 54)), box_size)
			if occupied.any(func(other: Rect2): return other.intersects(rect.grow(2))):
				continue
			occupied.append(rect)
			draw_line(p, p.clamp(rect.position, rect.end), note.color, 1.0, true)
			draw_rect(rect, Color("15242e"))
			draw_rect(rect, note.color, false, 1.0)
			draw_string(font, rect.position + Vector2(7, 17), note.label, HORIZONTAL_ALIGNMENT_LEFT, -1, 15, note.color)
			break

func _point(tile: Vector2) -> Vector2:
	return _origin + tile * _scale

static func floor_color(pattern: int) -> Color:
	# Render stable, high-contrast swatches by native pattern ID, not guessed textures.
	if pattern == 65535:
		return Color("407f96")
	var swatches := [Color("8b9b85"), Color("bda47e"), Color("8dacc0"), Color("bca7af"), Color("9cb4a5"), Color("c7bd9f"), Color("a8a1bc")]
	return swatches[posmod(pattern, swatches.size())]
