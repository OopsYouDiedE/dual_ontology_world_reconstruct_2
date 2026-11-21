extends SceneTree
## Export the existing reviewed geometry, not a second handwritten set of routes.
const Plans = preload("../room_review/RoomPlans.gd")
func _initialize() -> void:
	var out := {}
	for id in Plans.ORDER:
		var p := Plans.plan(id)
		var item := {"size":pair(p.size),"height":p.height,"exit":p.exit_x,"terminal":p.terminal,"routes":[],"walls":[],"fixtures":[]}
		for r: Array in [p.route,p.alternative]:
			if r.is_empty(): continue
			var points := []
			for v: Vector2 in r: points.append(pair(v))
			item.routes.append(points)
		for w: Dictionary in p.walls: item.walls.append([pair(w.a),pair(w.b),w.height,w.openings])
		for f: Dictionary in p.fixtures: item.fixtures.append([f.label,triple(f.at),triple(f.size),f.shape])
		out[id]=item
	var file:=FileAccess.open("res://tools/rule_arena/blockouts.json",FileAccess.WRITE)
	if file==null: quit(1);return
	file.store_line(JSON.stringify(out));file.close();quit()
func pair(v:Vector2)->Array: return [v.x,v.y]
func triple(v:Vector3)->Array: return [v.x,v.y,v.z]
