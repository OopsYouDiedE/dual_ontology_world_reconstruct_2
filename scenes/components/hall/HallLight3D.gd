@tool
class_name HallLight3D
extends GothicHallPiece3D
## A hall light that follows the time of day.
##   pool     — warm interior pool: `energy` at night, `day_energy` by day
##   daylight — skylight bounce: 0 at night, `day_energy` at noon
##   static   — constant `energy`

@export_enum("pool", "daylight", "static") var mode := "pool":
	set(v): mode = v; changed()
@export var color := Color("ffc27a"):
	set(v): color = v; changed()
@export var energy := 1.3:
	set(v): energy = v; changed()
## Pool: energy by day (-1 = 14% of `energy`). Daylight: energy at noon.
@export var day_energy := -1.0:
	set(v): day_energy = v; changed()
@export var reach := 3.2:
	set(v): reach = v; changed()
@export var attenuation := 1.0:
	set(v): attenuation = v; changed()
@export var specular := 0.5:
	set(v): specular = v; changed()

func _build() -> void:
	var light := OmniLight3D.new()
	light.name = name + "_Light"
	light.light_color = color
	light.omni_range = reach
	light.omni_attenuation = attenuation
	light.light_specular = specular
	add_child(light)
	match mode:
		"pool":
			light.light_energy = energy
			_pools.append({"light": light, "night": energy, "day": energy * 0.14 if day_energy < 0.0 else day_energy})
		"daylight":
			light.light_energy = 0.0
			light.shadow_enabled = false
			_daylight_fills.append({"light": light, "day": day_energy})
		_:
			light.light_energy = energy
