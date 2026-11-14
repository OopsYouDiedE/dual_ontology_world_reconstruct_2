extends RefCounted
## 房间变体：room_art.zip 里的 B-P（乙区小厨房）与 C-P（丙区备餐间）是同一份户型 + 同一套家具，
## 玩家分不清自己在哪一区，也与 C-P 的房间描述（茶水台、高处观察气窗、梳妆镜架）不符。
## 这里在 Lowpoly 房间实例化之后、量取包围盒之前，对指定房间做数据化改造：
##   · 移除不属于该房间的家具（炉灶、抽油烟机、炒锅）
##   · 补上与描述一致的家具（茶水台、高处气窗、梳妆镜架）
##   · 调整建筑材质色调（冷灰蓝），一眼就能与暖橙色的 B-P 区分
## 改造发生在 zip 之外，不需要改动二进制资源，补丁可读、可回退。

const COOL_TINT := Color(0.80, 1.0, 1.35)   # >1 的蓝通道：把暖橙护墙板拉向冷灰蓝，同时不压暗


static func apply(identity: String, inst: Node3D) -> void:
	match identity:
		"C-P": _variant_cp(inst)


static func _variant_cp(inst: Node3D) -> void:
	var inst_root := inst.get_node_or_null("Instances")
	if inst_root == null: return
	for nm in ["C_P_stove_01", "C_P_cooker_hood_01", "C_P_cooking_pot_01", "C_P_cooking_pot_02", "C_P_sink_01"]:
		var n := inst_root.get_node_or_null(nm)
		if n != null:
			inst_root.remove_child(n)
			n.queue_free()
	_tint_architecture(inst_root.get_node_or_null("C_P_architecture"), COOL_TINT)
	_tea_station(inst, Vector3(-2.25, 0.0, -5.0))
	_vent_window(inst, Vector3(-2.25, 2.3, -5.42))
	_mirror_stand(inst, Vector3(-3.0, 0.0, -4.55))
	_vent_window(inst, Vector3(2.1, 2.3, -5.42))


## 把架构 prefab 的 ShaderMaterial 复制一份再改 base_color（不污染 B-P 共用的资源）。
static func _tint_architecture(node: Node, tint: Color) -> void:
	if node == null: return
	for mi in node.find_children("*", "MeshInstance3D", true, false):
		var m := mi as MeshInstance3D
		var mat: Material = m.material_override
		if mat is ShaderMaterial:
			var dup := (mat as ShaderMaterial).duplicate() as ShaderMaterial
			var base: Variant = dup.get_shader_parameter("base_color")
			var c: Color = base if base is Color else Color(0.82, 0.78, 0.72)
			dup.set_shader_parameter("base_color", Color(c.r * tint.r, c.g * tint.g, c.b * tint.b, 1.0))
			m.material_override = dup
		elif mat is StandardMaterial3D:
			var sm := (mat as StandardMaterial3D).duplicate() as StandardMaterial3D
			sm.albedo_color = sm.albedo_color * tint
			m.material_override = sm
		else:
			# 导入网格自带材质：逐表面复制后染色
			if m.mesh == null: continue
			for i in m.mesh.get_surface_count():
				var sm0 := m.get_active_material(i)
				if sm0 is StandardMaterial3D:
					var d := (sm0 as StandardMaterial3D).duplicate() as StandardMaterial3D
					d.albedo_color = d.albedo_color * tint
					m.set_surface_override_material(i, d)


static func _mat(color: Color, rough := 0.7, metal := 0.0, emit := 0.0) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.roughness = rough
	m.metallic = metal
	if emit > 0.0:
		m.emission_enabled = true
		m.emission = color
		m.emission_energy_multiplier = emit
	return m


static func _box(parent: Node3D, size: Vector3, pos: Vector3, mat: Material, nm := "") -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.material_override = mat
	mi.position = pos
	if nm != "": mi.name = nm
	parent.add_child(mi)
	return mi


static func _cyl(parent: Node3D, r: float, h: float, pos: Vector3, mat: Material, rot := Vector3.ZERO) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = r
	cm.bottom_radius = r
	cm.height = h
	cm.radial_segments = 16
	mi.mesh = cm
	mi.material_override = mat
	mi.position = pos
	mi.rotation = rot
	parent.add_child(mi)
	return mi


## 茶水台：深木矮柜 + 铜壶 + 三只茶杯 + 托盘。
static func _tea_station(inst: Node3D, at: Vector3) -> void:
	var root := Node3D.new()
	root.name = "TeaStation"
	root.position = at
	inst.add_child(root)
	var wood := _mat(Color("#4a3426"), 0.75)
	var top := _mat(Color("#7b5a3c"), 0.55)
	var brass := _mat(Color("#c8963c"), 0.3, 0.8)
	var cup := _mat(Color("#f1ece0"), 0.4)
	_box(root, Vector3(1.25, 0.82, 0.56), Vector3(0, 0.41, 0), wood, "TeaCabinetBody")
	_box(root, Vector3(1.32, 0.06, 0.62), Vector3(0, 0.85, 0), top, "TeaTop")
	_box(root, Vector3(0.5, 0.025, 0.34), Vector3(0.28, 0.905, 0), _mat(Color("#2c211a"), 0.6))
	_cyl(root, 0.11, 0.2, Vector3(-0.3, 0.98, 0.0), brass)
	_cyl(root, 0.045, 0.06, Vector3(-0.3, 1.11, 0.0), brass)
	for i in 3:
		_cyl(root, 0.04, 0.05, Vector3(0.12 + i * 0.16, 0.945, 0.04 * (i % 2)), cup)
	# 台面小夜灯：暖色，提示这是「茶水台」
	var lamp := OmniLight3D.new()
	lamp.light_color = Color("#ffd9a0")
	lamp.light_energy = 0.5
	lamp.omni_range = 2.2
	lamp.position = Vector3(0, 1.3, 0.2)
	root.add_child(lamp)


## 高处观察气窗：深色窗框 + 横向百叶 + 冷色天光玻璃。贴墙，位于 2.3 m 高处。
static func _vent_window(inst: Node3D, at: Vector3) -> void:
	var root := Node3D.new()
	root.name = "VentWindow_%d" % int(at.x * 10.0)
	root.position = at
	inst.add_child(root)
	var frame := _mat(Color("#2b2a30"), 0.6, 0.2)
	var glass := _mat(Color("#bcd8ee"), 0.15, 0.0, 0.9)
	_box(root, Vector3(1.18, 0.5, 0.05), Vector3.ZERO, frame, "VentFrame")
	_box(root, Vector3(1.04, 0.36, 0.03), Vector3(0, 0, 0.03), glass, "VentGlass")
	for i in 4:
		_box(root, Vector3(1.06, 0.022, 0.05), Vector3(0, -0.14 + i * 0.093, 0.06), frame)


## 梳妆镜架：落地木架 + 椭圆镜面（冷色金属反光）+ 搭着的织巾。
static func _mirror_stand(inst: Node3D, at: Vector3) -> void:
	var root := Node3D.new()
	root.name = "MirrorStand"
	root.position = at
	inst.add_child(root)
	var wood := _mat(Color("#3f2d22"), 0.7)
	var mirror := _mat(Color("#cfe2f0"), 0.05, 0.9)
	for sx in [-1, 1]:
		_box(root, Vector3(0.06, 1.75, 0.06), Vector3(sx * 0.42, 0.875, 0), wood)
		_box(root, Vector3(0.08, 0.05, 0.5), Vector3(sx * 0.42, 0.025, 0), wood)
	_box(root, Vector3(0.9, 0.06, 0.06), Vector3(0, 1.72, 0), wood)
	_box(root, Vector3(0.9, 0.06, 0.06), Vector3(0, 0.3, 0), wood)
	var glass := _cyl(root, 0.4, 0.03, Vector3(0, 1.05, 0.02), mirror, Vector3(PI / 2.0, 0, 0))
	glass.scale = Vector3(0.95, 1.0, 1.55)
	_box(root, Vector3(0.7, 0.28, 0.04), Vector3(0.0, 0.6, 0.12), _mat(Color("#8a4a54"), 0.9))
