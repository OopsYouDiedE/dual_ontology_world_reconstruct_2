extends SceneTree
func _initialize():
	var boot = load("res://scenes/main/Boot.tscn").instantiate()
	root.add_child(boot)
	await create_timer(0.5).timeout
	print("PROBE2 boot children=", boot.get_child_count(), " first=", boot.get_child(0).get_class() if boot.get_child_count() else "none")
	quit()
