extends SceneTree
const Rules := preload("res://scenes/blue_prince_lab/vesper/VesperRules.gd")

func _initialize() -> void:
	var root := Rules.new()
	var queue := [root]
	var graph := {}
	var winning := {}
	var shortest := -1
	var depths := {root.code():0}
	while not queue.is_empty():
		var state: Rules = queue.pop_front()
		var code := state.code()
		graph[code]=[]
		if state.crossed:
			winning[code]=true
			if shortest<0: shortest=depths[code]
		for action in Rules.ACTIONS:
			var next:=Rules.new()
			next.cinder=state.cinder
			next.aim=state.aim
			next.released=state.released
			next.crossed=state.crossed
			next.act(action)
			var dest:=next.code()
			graph[code].append(dest)
			if not depths.has(dest):
				depths[dest]=depths[code]+1
				queue.append(next)
	var changed:=true
	while changed:
		changed=false
		for code in graph:
			if winning.has(code): continue
			for dest in graph[code]:
				if winning.has(dest):
					winning[code]=true
					changed=true
					break
	var ok:= shortest==6 and winning.size()==graph.size() and graph.size()==13
	print("Vesper: %d reachable, %d can finish, shortest %d actions" % [graph.size(),winning.size(),shortest])
	quit(0 if ok else 1)
