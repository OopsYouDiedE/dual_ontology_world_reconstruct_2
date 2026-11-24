extends Node3D
## Indoor lamps use only mood. Only exterior apertures receive the clock profile.
const RenderProfile := preload("res://scenes/components/rendering/AcademyRenderProfile.gd")
var lamps: Array[OmniLight3D] = []
var hearths: Array[OmniLight3D] = []
var windows: Array[OmniLight3D] = []
var _hearth_base := 0.4
var _flicker_phase := 0.0

func build(lot: Dictionary, center: Vector3) -> void:
	var cells := {}
	for cell in lot.floors: cells[cell] = true
	var lamp := OmniLight3D.new()
	add_child(lamp)
	lamp.position = center + Vector3(0,2.30,0)
	lamp.omni_range = 14.0
	lamp.shadow_enabled = true
	RenderProfile.tune_omni_light(lamp, "lamp")
	lamps.append(lamp)
	for item in lot.get("objects", []):
		if str(item.get("label", "")).to_lower() != "stove": continue
		var fire := OmniLight3D.new()
		add_child(fire)
		fire.position = Vector3(item.position.x,0.96,item.position.y)
		fire.light_color = Color("ff953e")
		fire.omni_range = 4.8
		fire.shadow_enabled = true
		RenderProfile.tune_omni_light(fire, "hearth")
		hearths.append(fire)
	for edge: Vector4i in lot.get("windows", {}):
		var mid := Vector2(edge.x+edge.z,edge.y+edge.w)*0.5
		var axis := Vector2.RIGHT if edge.x == edge.z else Vector2.DOWN
		var front := cells.has(Vector2i((mid+axis*0.25).floor()))
		var back := cells.has(Vector2i((mid-axis*0.25).floor()))
		if front == back: continue # Interior serving hatches receive no daylight.
		var inside := mid+axis*(0.28 if front else -0.28)
		var light := OmniLight3D.new()
		add_child(light)
		light.position = Vector3(inside.x,1.55,inside.y)
		light.omni_range = 5.0
		light.shadow_enabled = true
		RenderProfile.tune_omni_light(light, "window")
		windows.append(light)

func apply(hour: float, mood: String) -> void:
	for lamp in lamps:
		lamp.light_color = Color("ffb77a") if mood == "ember" else Color("f7f2e9")
		lamp.light_energy = 1.0 if mood == "ember" else 3.2
		match mood:
			"shelter":
				lamp.light_color = Color("ffc68d")
				lamp.light_energy = 3.6
			"rain":
				lamp.light_color = Color("a7c7c4")
				lamp.light_energy = 1.55
			"rewrite":
				lamp.light_color = Color("e49581")
				lamp.light_energy = 1.65
			"echo":
				lamp.light_color = Color("aec2e4")
				lamp.light_energy = 1.9
	_hearth_base = 2.2 if mood == "ember" else 0.4
	for fire in hearths:
		fire.light_energy = _hearth_base
	var daylight := smoothstep(0.0,1.0,maxf(0.0,cos((fposmod(hour,24.0)-12.0)*PI/12.0)))
	for light in windows:
		light.light_energy = lerpf(0.08,2.8,daylight)
		light.light_color = Color("7598cb").lerp(Color("ffebbf"),daylight)

func _process(delta: float) -> void:
	if hearths.is_empty():
		return
	_flicker_phase += delta
	var wave := 1.0 + 0.055 * sin(_flicker_phase * 11.3) + 0.032 * sin(_flicker_phase * 23.7)
	for fire in hearths:
		fire.light_energy = _hearth_base * wave
