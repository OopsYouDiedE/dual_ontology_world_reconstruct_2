extends SceneTree
## Verify the resources actually mounted in a new production room.
func _initialize() -> void:
	var room := preload("res://scenes/rogue_view/RogueRoomView.tscn").instantiate()
	var env: Environment = room.get_node("RoomViewport/WorldEnvironment").environment
	var geo := preload("res://tools/building_construction/BuildingConstruction/Shared/ArchitectGeometry.gd")
	var wood := geo.material("wood") as ShaderMaterial
	var ok := env == preload("res://scenes/components/rendering/post/Hall04.tres") and env.sdfgi_enabled and not env.glow_enabled
	ok = ok and env.adjustment_enabled and is_equal_approx(env.adjustment_saturation, 0.76)
	ok = ok and wood != null and wood.shader == preload("res://scenes/components/rendering/surfaces/PaintedSurface.gdshader")
	ok = ok and (geo.material("glass") as StandardMaterial3D).transparency == BaseMaterial3D.TRANSPARENCY_ALPHA
	var main := str(ProjectSettings.get_setting("application/run/main_scene"))
	ok = ok and (load(main) == preload("res://scenes/rogue/Run.tscn"))
	var kit := preload("res://assets/architecture/night_crossing/shutter.glb").instantiate()
	ok = ok and preload("res://scenes/components/rendering/surfaces/PaintedSurface.gd").finish_kit(kit) > 0
	kit.free()
	room.free()
	if ok: print("PASS: Hall 04 environment, architectural finishes and expedition entry")
	else: push_error("Hall 04 production contract failed")
	quit(0 if ok else 1)
