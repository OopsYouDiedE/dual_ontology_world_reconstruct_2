extends SceneTree

const Reader := preload("res://tools/freeso_bridge/LotSnapshot.gd")

func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() != 1:
		printerr("Pass the exported JSON filename after --.")
		quit(2)
		return
	var result := Reader.read_file(args[0])
	if result.has("error"):
		printerr(result.error)
		quit(1)
		return
	var snapshot: Dictionary = result.snapshot
	for avatar in snapshot.avatars:
		if avatar.placed:
			print("avatar ", avatar.object_id, " position ", Reader.avatar_position(avatar),
				" membership ", avatar.get("lot_membership", "unknown"),
				" activity ", avatar.get("activity", {"status": "unavailable"}))
	print("FreeSO tick ", snapshot.tick, ": ", snapshot.lot.walls.size(), " wall cells; ", snapshot.lot.floors.size(), " floor cells; ", snapshot.avatars.size(), " avatars")
	quit(0)
