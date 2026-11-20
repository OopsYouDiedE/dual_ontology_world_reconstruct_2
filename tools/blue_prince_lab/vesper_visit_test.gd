extends "res://tools/test/night_expedition.gd"

func _click(at: Vector2) -> void:
	for down: bool in [true,false]:
		var e:=InputEventMouseButton.new()
		e.button_index=MOUSE_BUTTON_LEFT
		e.position=at
		e.global_position=at
		e.pressed=down
		e.button_mask=MOUSE_BUTTON_MASK_LEFT if down else 0
		root.push_input(e,true)
		await process_frame

func _main() -> void:
	var game := Run.instantiate()
	root.add_child(game)
	if not await _approach(game, 2):
		quit(1)
		return
	var funds: int=game.crew.supplies
	var doors: Array=Array(game.destinations)
	game._open_vesper()
	await process_frame
	var pt: Array=game.vesper.puzzle.snapshot().props.leaf
	await _click(Vector2(pt[0],pt[1]))
	check(game.vesper.puzzle.rules.cinder,"real click did not reach the folio in the embedded viewport")
	var back: Button=game.vesper.puzzle.keys.get_child(-1)
	await _click(back.get_global_rect().get_center())
	if not check(game.vesper==null,"return button did not dismiss the embedded viewport"):
		quit(1)
		return
	game._open_vesper()
	var room=game.vesper.puzzle
	check(room.rules.cinder, "case progress lost on return to hall")
	for id in [&"lamp", &"wind", &"leaf", &"lamp", &"cross"]: room.use(id)
	check(room.rules.crossed and game.vesper_recovered and game.crew.supplies==funds+1,"evidence not filed")
	room.restart()
	for id in [&"leaf", &"lamp", &"wind", &"leaf", &"lamp", &"cross"]: room.use(id)
	game._leave_vesper()
	check(game.crew.supplies==funds+1 and doors==Array(game.destinations), "replay or optional room changed economy/topology")
	game.new_run(3)
	check(not game.vesper_recovered and game.vesper_progress==null,"file leaked across runs")
	print("Vesper camp visit: ", "PASS" if failure.is_empty() else failure)
	game.queue_free()
	await process_frame
	quit(0 if failure.is_empty() else 1)
