@tool
extends RefCounted

const Sem = preload("res://tools/building_construction/BuildingConstruction/Shared/RecipeSemantics.gd")
const Geo = preload("res://tools/building_construction/BuildingConstruction/Shared/RecipeGeometry.gd")

static func gen_courtyard_gate(v_name, v_mats, v_width = 2.2, v_height = 2.7, v_rise = 0.65, v_parent = null):
	var v_obj = null
	var v_root = null
	var v_sign = null
	v_root = load("res://tools/building_construction/BuildingConstruction/Doors/VariantRecipes.gd").gen_arched_closed_door(v_name, v_mats, v_width, v_height, v_rise, true, 12, 0.14, v_parent)
	for tmp_4 in Geo.descendants(v_root):
		v_obj = tmp_4
		if Sem.truth(((v_obj.type != "MESH"))):
			continue
		if Sem.truth(Sem.either_lazy((("_Arch_jamb" in v_obj.name)), func(): return Sem.either_lazy((("_Arch_moulding" in v_obj.name)), func(): return (("_Arch_inner_bead" in v_obj.name))))):
			v_obj.data.materials.clear()
			v_obj.data.materials.append((v_mats["stone"] if Sem.truth((("_jamb" in v_obj.name))) else v_mats["cream"]))
	for tmp_5 in [Sem.neg(1), 1]:
		v_sign = tmp_5
		Geo.gen_box(Sem.add(Sem.add(v_name, "_Stone_Pier_"), str(v_sign)), [Sem.mul(v_sign, Sem.add(Sem.div(v_width, 2), 0.3)), 0.04, Sem.div(v_height, 2)], [0.44, 0.48, v_height], v_mats["stone"], 0.015, v_root)
		Geo.gen_box(Sem.add(Sem.add(v_name, "_Stone_Cap_"), str(v_sign)), [Sem.mul(v_sign, Sem.add(Sem.div(v_width, 2), 0.3)), 0.04, Sem.add(v_height, 0.08)], [0.6, 0.62, 0.18], v_mats["cream"], 0.015, v_root)
	v_root["transition_mode"] = "teleport"
	return v_root
