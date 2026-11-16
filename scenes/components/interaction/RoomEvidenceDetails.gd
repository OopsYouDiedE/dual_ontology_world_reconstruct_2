extends Node3D
## 入场时装配现场细节，调查只移动相机；细节与房间同寿命。
const Prop := preload("res://scenes/components/interaction/InteractiveProp3D.gd")
const KINDS := {"e_b_sleeve": "sleeve", "e_b_drag": "drag", "e_b_water": "water", "e_b_cloth": "cloth", "e_b_ratchet": "ratchet", "e_b_boots": "boots", "e_b_seal": "seal"}
var host: Control
var presentations: Dictionary = {}
var _sleeve: Node3D

func install(h: Control) -> Dictionary:
	host = h
	if str(host.eng.s.room) == "R05":
		if not host._lowpoly_ok: return presentations
		var wardrobe := host.lowpoly._root.get_node_or_null("Instances/R05_wardrobe_01") as Node3D
		if wardrobe != null:
			var mechanism := preload("res://scenes/components/interaction/RoomWardrobe.gd").new()
			if mechanism.install(wardrobe): presentations["wardrobe"] = mechanism
			else: mechanism.free()
		var observations := {"bed": "R05_bed_01", "desk": "R05_residential_accessories_01", "lamp": "R05_banker_lamp_01", "wash": "R05_wash_table_01", "window": "R05_window_01"}
		for kind in observations:
			var original := host.lowpoly._root.get_node_or_null("Instances/" + str(observations[kind])) as Node3D
			if original == null: continue
			var observation := preload("res://scenes/components/interaction/RoomObservation.gd").new()
			if observation.install(original, str(kind)): presentations[kind] = observation
			else: observation.queue_free()
		return presentations
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
			# This prefab's -Z faces the room; +Z is beyond the left wall.
			"water": _attach_detail(detail, door, Transform3D(Basis.IDENTITY, Vector3(0, 0.004, -0.25)))
			"drag": _attach_detail(detail, door, Transform3D(Basis.IDENTITY, Vector3(0, 0.004, -1.0)))
			"boots": _attach_detail(detail, door, Transform3D(Basis.IDENTITY, Vector3(0.42, 0.004, -1.65)))
			"ratchet":
				var leaf := door.get_node_or_null("VisualRoot/ModelInstance/Asset/Left_hinge") as Node3D
				var mount := Transform3D(Basis(Vector3.UP, PI), Vector3(0.38, 0.6, -0.14))
				if is_instance_valid(leaf):
					_attach_detail(detail, leaf, leaf.global_transform.affine_inverse() * door.global_transform * mount)
				else: _attach_detail(detail, door, mount)
	if str(detail.kind) == "seal" and is_instance_valid(window):
		_attach_detail(detail, window, Transform3D(Basis.IDENTITY, Vector3(0, 0.45, 0.12)))
	if str(detail.kind) == "cloth" and is_instance_valid(rack):
		_attach_detail(detail, rack, Transform3D(Basis(Vector3.RIGHT, -PI * 0.5), Vector3(0.0715, 1.05, -0.025)))
		detail.set_meta("camera_offset", Vector3(0.35, 0.75, -0.55))

func _attach_detail(detail: Node3D, original: Node3D, local_transform: Transform3D) -> void:
	# Keep the detail in the original object's coordinate system across room reparenting.
	if detail.get_parent() != original: detail.reparent(original, false)
	detail.transform = local_transform

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
