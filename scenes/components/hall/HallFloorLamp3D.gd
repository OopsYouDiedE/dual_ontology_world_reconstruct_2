@tool
class_name HallFloorLamp3D
extends GothicHallPiece3D
## 1900s standing brass kerosene floor lamp with a glowing globe; lit at night.
## Reserves its footprint.

@export var night_energy := 2.8:
	set(v): night_energy = v; changed()
@export var reach := 9.5:
	set(v): reach = v; changed()

func plan_outline() -> PackedVector2Array: return _rect_outline(Rect2(-0.29, -0.29, 0.58, 0.58))

func _build() -> void:
	for seg in [[0.22, 0.28, 0.10, 0.05], [0.045, 0.06, 1.48, 0.84], [0.16, 0.08, 0.12, 1.62]]:
		var cm := CylinderMesh.new(); cm.top_radius = seg[0]; cm.bottom_radius = seg[1]; cm.height = seg[2]
		var mi := MeshInstance3D.new(); mi.mesh = cm; mi.material_override = mat("brass"); mi.position.y = seg[3]; add_child(mi)
	var shade_mat := StandardMaterial3D.new()
	shade_mat.albedo_color = Color("fff0cf"); shade_mat.emission_enabled = true
	shade_mat.emission = Color("ffba62"); shade_mat.emission_energy_multiplier = 2.6; shade_mat.roughness = 0.25
	var globe := SphereMesh.new(); globe.radius = 0.14; globe.height = 0.30
	var gmi := MeshInstance3D.new(); gmi.mesh = globe; gmi.material_override = shade_mat; gmi.position.y = 1.80; add_child(gmi)
	var cap := CylinderMesh.new(); cap.top_radius = 0.08; cap.bottom_radius = 0.17; cap.height = 0.07
	var cmi := MeshInstance3D.new(); cmi.mesh = cap; cmi.material_override = mat("brass"); cmi.position.y = 1.98; add_child(cmi)
	var l := OmniLight3D.new(); l.name = name + "_Light"; l.position = Vector3(0.0, 1.82, 0.0)
	l.light_color = Color("ffb86c"); l.light_energy = night_energy; l.omni_range = reach; l.omni_attenuation = 1.15; l.shadow_enabled = false
	add_child(l)
	_pools.append({"light": l, "night": night_energy, "day": 0.08})
	_reserve_station(Vector3.ZERO, Vector2(0.58, 0.58), 2.0)
