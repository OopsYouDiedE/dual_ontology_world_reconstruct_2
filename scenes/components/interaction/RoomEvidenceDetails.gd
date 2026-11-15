extends Node3D
## 入场时装配现场细节，调查只移动相机；细节与房间同寿命。
const Prop := preload("res://scenes/components/interaction/InteractiveProp3D.gd")
const KINDS := {"e_b_sleeve": "sleeve", "e_b_drag": "drag", "e_b_water": "water", "e_b_cloth": "cloth", "e_b_ratchet": "ratchet", "e_b_boots": "boots", "e_b_seal": "seal"}
var host: Control
var presentations: Dictionary = {}
var _sleeve: Node3D

func install(h: Control) -> Dictionary:
	host = h
	if str(host.eng.s.room) != "B-P": return presentations
	for evidence_id in KINDS:
		var marker: Node3D = host.room_mesh.evidence_nodes.get(evidence_id)
		if marker == null: continue
		var detail := Prop.new()
		detail.kind = KINDS[evidence_id]
		add_child(detail)
		detail.set_meta("evidence_id", evidence_id)
		detail.global_position = marker.global_position
		detail.position.y = 0.015
		if detail.kind in ["ratchet", "seal"]: detail.position.y = 0.75
		if detail.kind == "cloth": detail.position.y = 0.65
		_anchor_to_room(detail)
		if detail.kind == "sleeve": _sleeve = detail
		if is_instance_valid(detail.tool): detail.tool.visible = false
		if is_instance_valid(detail.hand): detail.hand.visible = false
		presentations[str(detail.kind)] = detail
	sync_body_anchor()
	sync_markers()
	return presentations

func _anchor_to_room(detail: Node3D) -> void:
	if not host._lowpoly_ok: return
	var scene: Node3D = host.lowpoly._root
	var door := scene.get_node_or_null("Instances/B_P_Door_00") as Node3D
	var window := scene.get_node_or_null("Instances/B_P_window_01") as Node3D
	var rack := scene.get_node_or_null("Instances/B_P_cloth_rack_01") as Node3D
	if is_instance_valid(door):
		match str(detail.kind):
			"water": detail.global_transform = door.global_transform * Transform3D(Basis.IDENTITY, Vector3(0, -0.16, 0.12))
			"drag": detail.global_transform = door.global_transform * Transform3D(Basis.IDENTITY, Vector3(0, -0.035, 1.0))
			"boots": detail.global_transform = door.global_transform * Transform3D(Basis.IDENTITY, Vector3(0.95, -0.035, 0.65))
			"ratchet": detail.global_transform = door.global_transform * Transform3D(Basis.IDENTITY, Vector3(0.65, 0.6, 0.16))
	if str(detail.kind) == "seal" and is_instance_valid(window):
		detail.global_transform = window.global_transform * Transform3D(Basis.IDENTITY, Vector3(0, 0.45, 0.12))
	if str(detail.kind) == "cloth" and is_instance_valid(rack):
		detail.global_transform = rack.global_transform * Transform3D(Basis(Vector3.RIGHT, PI * 0.5), Vector3(0, 1.3, 0.16))
		detail.set_meta("camera_offset", Vector3(0.35, 0.75, -0.55))

func sync_markers() -> void:
	for kind in presentations:
		var detail: Node3D = presentations[kind]
		var marker: Node3D = host.room_mesh.evidence_nodes.get(str(detail.get_meta("evidence_id", "")))
		if is_instance_valid(marker):
			marker.global_position = Vector3(detail.global_position.x, 0.0, detail.global_position.z)

func sync_body_anchor() -> void:
	if not is_instance_valid(_sleeve) or not is_instance_valid(host): return
	var figure: Node3D = host.figures.get("su")
	var body: Node3D = figure.get("_body") if is_instance_valid(figure) else null
	var wrist: Node3D = body.get_meta("slot_right_hand", null) if is_instance_valid(body) else null
	_sleeve.visible = is_instance_valid(wrist)
	if is_instance_valid(wrist):
		_sleeve.global_position = wrist.global_position - _sleeve.sleeve.position
