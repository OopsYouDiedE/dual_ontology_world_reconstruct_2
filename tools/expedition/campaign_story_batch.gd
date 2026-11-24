extends SceneTree
## Post-first-return solo campaigns. Real travel/inspect/act handlers; omit room drawing.
class Receiver extends RefCounted:
	var line := ""
	func set_modal(_open): pass
	func set_instance_id(_id): pass
	func show_crossing_action(_group, _id, receipt): line = receipt.line

class Watch extends "res://scenes/rogue_crossing/FirstWatch.gd":
	func _refresh():
		destinations = _routes() if cleared.has(current) and phase not in ["lost", "won"] else PackedStringArray()
	func _open(kind: String, _title: String, _folio: String): modal = kind
	func _label(_text: String, _size := 16, _gold := false): pass
	func _button(_parent: Container, label: String, callback: Callable) -> Button:
		var b := Button.new()
		b.text = label
		b.pressed.connect(callback)
		add_child(b)
		return b
	func _close():
		modal = ""
		_acting = -1
		for child in get_children(): child.free()

func trial(seed_value: int) -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value ^ 73451
	var w := Watch.new()
	w.room_view = Receiver.new()
	w.first_returned = true
	w.new_run(seed_value)
	var path := [w.current]
	var actions := []
	var attempts := {}
	for step in 160:
		if w.phase in ["lost", "won"]: break
		if not w.destinations.is_empty():
			w.travel(rng.randi_range(0, w.destinations.size()-1))
			path.append(w.current)
			attempts.clear()
			continue
		# Inspect each station and consider only enabled apparatus buttons. Prefer
		# the least-tried options; RNG breaks ties independently of the house deck.
		var options := []
		var least := 999
		for group in 3:
			w._inspect(group)
			for b: Button in w.get_children():
				if b.disabled or b.text.begins_with("Put it down"): continue
				var n := int(attempts.get(b.text, 0))
				if n < least:
					options.clear()
					least = n
				if n == least: options.append([group, b.text])
			w._close()
		if options.is_empty(): break
		var pick: Array = options[rng.randi_range(0, options.size()-1)]
		w._inspect(pick[0])
		for b: Button in w.get_children():
			if b.text == pick[1]:
				# Invoke the exact bound gameplay callback outside signal dispatch.
				var cb: Callable = b.pressed.get_connections()[0].callable
				cb.call()
				break
		attempts[pick[1]] = int(attempts.get(pick[1], 0)) + 1
		actions.append([w.current, w._stage(), pick[1], w.room_view.line])
	var row := {"seed":seed_value,"route":path,"outcome":w.phase,"actions":actions}
	w.free()
	return row

func _initialize():
	var rows := []
	for n in range(1, 257): rows.append(trial(n))
	print("CAMPAIGN_AUDIT " + JSON.stringify(rows))
	quit()
