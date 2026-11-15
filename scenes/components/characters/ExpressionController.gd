extends Node
## Facial features are shaded on the imported head surface, following its real skinning.
const SURFACE := preload("res://scenes/components/rendering/ExpressionFigurineSurface.gdshader")
const EXPRESSIONS := {
	"neutral":{"frown":0.0,"brow_lift":0.0,"mouth_open":0.0,"mouth_curve":0.0,"eye_squeeze":0.0},
	"concern":{"frown":-0.35,"brow_lift":0.70,"mouth_open":0.12,"mouth_curve":-0.65,"eye_squeeze":0.1},
	"resolve":{"frown":0.85,"brow_lift":0.0,"mouth_open":0.0,"mouth_curve":0.0,"eye_squeeze":0.42},
	"fear":{"frown":-0.25,"brow_lift":1.0,"mouth_open":0.85,"mouth_curve":-0.35,"eye_squeeze":0.0},
	"relief":{"frown":0.0,"brow_lift":0.1,"mouth_open":0.1,"mouth_curve":0.85,"eye_squeeze":0.55}
}
var frown := 0.0
var brow_lift := 0.0
var mouth_open := 0.0
var mouth_curve := 0.0
var eye_squeeze := 0.0
var expression := "neutral"
var materials: Array[ShaderMaterial] = []
var _tween: Tween
var _clock := 0.0

func install(model: Node3D, profile: Dictionary = {}) -> void:
	var converted: Dictionary = {}
	for mesh in model.find_children("*","MeshInstance3D",true,false):
		for surface in mesh.mesh.get_surface_count():
			var original := mesh.get_active_material(surface) as ShaderMaterial
			if original == null: continue
			var material: ShaderMaterial
			if converted.has(original): material = converted[original]
			else:
				material = ShaderMaterial.new()
				material.shader = SURFACE
				for key in ["albedo_texture","albedo_tint","surface_roughness","surface_specular","shadow_warm_tint","rim_warm_color","rim_strength","ambient_lift"]:
					material.set_shader_parameter(key,original.get_shader_parameter(key))
				for key in profile: material.set_shader_parameter(key,profile[key])
				converted[original] = material
				materials.append(material)
			mesh.set_surface_override_material(surface,material)

func set_expression(value: String,duration := 0.3) -> bool:
	if not EXPRESSIONS.has(value): return false
	expression = value
	if _tween != null: _tween.kill()
	_tween = create_tween().set_parallel(true).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	for key in EXPRESSIONS[value]: _tween.tween_property(self,key,EXPRESSIONS[value][key],duration)
	return true

func _process(delta: float) -> void:
	_clock += delta
	var phase := fmod(_clock,4.7)
	var blink := sin(clampf((phase-4.45)/0.18,0.0,1.0)*PI) if phase>4.45 and phase<4.63 else 0.0
	for material in materials:
		for key in ["frown","brow_lift","mouth_open","mouth_curve","eye_squeeze"]: material.set_shader_parameter(key,get(key))
		material.set_shader_parameter("blink",blink)

func test_snapshot() -> Dictionary:
	return {"expression":expression,"frown":frown,"brow_lift":brow_lift,"mouth_open":mouth_open,"mouth_curve":mouth_curve,"eye_squeeze":eye_squeeze,"materials":materials.size(),"reference_alignment":"pending_astra_reference_and_independent_review"}
