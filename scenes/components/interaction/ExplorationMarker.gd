extends RefCounted
## 三个自由探索场景共用的宝石与名牌组合。

static func create(parent: Node3D, label: String, options: Dictionary = {}) -> Dictionary:
	var gem := MeshInstance3D.new()
	var mesh := SphereMesh.new()
	mesh.radius = float(options.get("radius", 0.15))
	mesh.height = float(options.get("height", 0.34))
	mesh.radial_segments = int(options.get("radial_segments", 4))
	mesh.rings = int(options.get("rings", 2))
	gem.mesh = mesh
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = options.get("albedo_color", Color("#ffa51f"))
	material.emission_enabled = true
	material.emission = options.get("emission_color", Color("#ff8a00"))
	material.emission_energy_multiplier = float(options.get("emission_energy_multiplier", 1.6))
	gem.material_override = material
	gem.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(gem)

	var tag := Label3D.new()
	tag.text = label
	var font: Font = options.get("font", null)
	if font != null: tag.font = font
	tag.font_size = int(options.get("font_size", 40))
	tag.pixel_size = float(options.get("pixel_size", 0.0055))
	tag.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	tag.position = options.get("tag_position", Vector3(0.0, 0.26, 0.0))
	tag.modulate = options.get("tag_color", Color("#ffe3a3"))
	tag.outline_size = int(options.get("outline_size", 12))
	tag.no_depth_test = bool(options.get("no_depth_test", true))
	tag.visible = bool(options.get("tag_visible", false))
	parent.add_child(tag)
	return {"gem": gem, "mat": material, "tag": tag}
