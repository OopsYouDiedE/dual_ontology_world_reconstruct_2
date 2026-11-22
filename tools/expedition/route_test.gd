extends SceneTree
## Seed invariants and inventory rules. The viewport runner covers movement and the tram.
const House = preload("res://scenes/rogue/HouseMap.cs")
const Rules = preload("res://scenes/rogue_crossing/Crossing.gd")
const SLOTS := ["camp","west_1","east_1","west_2","east_2","turntable","west_3","east_3","observatory"]
var errors: Array[String] = []

func check(ok: bool, why: String) -> void:
	if not ok and errors.size() < 20: errors.append(why)

func _initialize() -> void:
	var h := House.new()
	var signatures := {}
	var edges := {}
	for seed in range(-128,128):
		var prev := ""
		for repeat in 2:
			if not h.generate_expedition(seed):
				check(false,"solver %d" % seed)
				continue
			check(h.start_room()=="camp" and h.goal_room()=="observatory", "anchors")
			var seen := {"camp":true}
			var cards := []
			var links := []
			for id: String in SLOTS:
				var dest: PackedStringArray = h.forward(id)
				check(id in seen,"unreachable %s/%d" % [id,seed])
				check(id == "observatory" or not dest.is_empty(),"dead end at %s/%d" % [id,seed])
				for n in dest:
					seen[n] = true
					check(h.column(n)==h.column(id)+1,"back edge")
				links.append(Array(dest))
				if id not in ["camp","turntable","observatory"]: cards.append(h.room_stage(id))
			check(h.room_stage("turntable")=="shutter" and h.template_id("turntable")=="dining" and h.template_id("camp")=="living_hall" and h.template_id("observatory")=="valve_gallery" and h.room_stage("observatory")=="meridian", "fixed rooms")
			check(cards.size()==6 and cards.all(func(c): return cards.count(c)==1),"deck duplicates")
			var stamp := JSON.stringify([links,cards])
			if repeat: check(stamp==prev,"unstable seed %d" % seed)
			prev = stamp
			signatures[JSON.stringify(cards)] = true
			edges[JSON.stringify(links)] = true
	check(signatures.size()>1 and edges.size()>1,"seed must vary cards and links")
	var crew := ["Ivory"]
	for mode in ["free","felt","ratchet"]:
		var boss := Rules.new("meridian",false)
		var pack := {"felt":0,"ratchet":0}
		check(boss.use_tool(1,"felt",pack).is_empty(),"empty bag")
		if mode != "free":
			pack[mode] = 2
			var g := boss.tool_group(mode)
			check(boss.use_tool(3-g,mode,pack).is_empty(),"wrong station")
			check(not boss.use_tool(g,mode,pack).is_empty() and pack[mode]==1,"single debit")
			check(boss.use_tool(g,mode,pack).is_empty() and pack[mode]==1,"repeat debit")
		var result := {}
		if mode == "felt": result = boss.act(1,"seal",crew)
		else:
			boss.act(0,"docket",crew)
			if mode=="free": boss.act(2,"brake",crew)
			result = boss.act(2,"wind",crew)
		check(result.get("clear",false) and result.bonus==(2 if mode=="felt" else 0) and result.minutes==(18 if mode=="free" else 3),"boss receipt: "+mode)
	for e in errors: push_error(e)
	if errors.is_empty(): print("PASS: 256 seeds x2; distinct hands %d, edge sets %d; 3 boss receipts" % [signatures.size(), edges.size()])
	quit(int(not errors.is_empty()))
