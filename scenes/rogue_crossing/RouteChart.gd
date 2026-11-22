extends Control
## Coordinates are authored once; only connections, room labels and state change.
const POS := {"camp":Vector2(38,79),"west_1":Vector2(147,36),"east_1":Vector2(147,122),"west_2":Vector2(251,36),"east_2":Vector2(251,122),"turntable":Vector2(348,79),"west_3":Vector2(447,36),"east_3":Vector2(447,122),"observatory":Vector2(561,79)}
var chart: RefCounted
var here: String
var visited: Dictionary
func _draw() -> void:
	if not chart: return
	var ink := Color("cdc7b6")
	var accent := Color("e8c282")
	var font := ThemeDB.fallback_font
	for id in POS:
		for dest in chart.forward(id):
			var bright: bool = id == here or (id in visited and dest in visited)
			draw_dashed_line(POS[id], POS[dest], accent if bright else Color("706f63"), 2, 5, true, true)
	for id: String in POS:
		var p: Vector2 = POS[id]
		var color := accent if id == here else ink
		draw_circle(p,12,Color("222923"))
		if id.begins_with("west"):
			draw_arc(p,8,0,TAU,24,color,2,true)
		elif id.begins_with("east"):
			draw_rect(Rect2(p-Vector2(7,7),Vector2(14,14)),color,false,2)
		else:
			var ring := PackedVector2Array([p+Vector2.UP*11,p+Vector2.RIGHT*10,p+Vector2.DOWN*11,p+Vector2.LEFT*10,p+Vector2.UP*11]);draw_polyline(ring,color,2,true)
		if id == here: draw_circle(p,3,accent)
		var label := "Hall" if id == "camp" else ("Junction" if id == "turntable" else ("Bell" if id == "observatory" else ("Felt" if id.begins_with("west") else "Ratchet")))
		draw_string(font,p+Vector2(-36,26),label,HORIZONTAL_ALIGNMENT_CENTER,72,13,color)
