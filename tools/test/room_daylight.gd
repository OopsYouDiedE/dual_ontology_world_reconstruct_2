extends SceneTree
const Lighting = preload("res://scenes/rogue_view/render/RoomLighting.gd")
func _initialize() -> void:
	var failed := false
	for mode in ["solid", "hatch", "exterior"]:
		var room := Lighting.new()
		var cells := [Vector2i.ZERO]
		if mode == "hatch": cells.append(Vector2i.RIGHT)
		var edges := {} if mode == "solid" else {Vector4i(1,0,1,1):true}
		room.build({"floors":cells, "windows":edges}, Vector3.ZERO)
		room.apply(12.0, "ember")
		var lamp := room.lamps[0].light_energy
		var day := 0.0
		for light in room.windows: day += light.light_energy
		room.apply(0.0,"ember")
		var night := 0.0
		for light in room.windows: night += light.light_energy
		failed = failed or lamp != room.lamps[0].light_energy or (day > night) != (mode == "exterior") or room.windows.size() != (1 if mode == "exterior" else 0)
		room.free()
	print("Room daylight contract: ", "FAIL" if failed else "PASS")
	quit(1 if failed else 0)
