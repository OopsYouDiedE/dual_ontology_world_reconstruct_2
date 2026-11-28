extends RefCounted
## Fit a recessed floor instrument into a contiguous, unfurnished part of a native lot.
## In Public Hall (flush_display = true), builds an authentic Panthéon-style Foucault
## pendulum compass dial (dark slate basin, engraved degree ring, inlaid meridian
## crosshairs, center brass sighting pin, and perimeter knock-down pegs) instead of a
## clockwork tourbillon.
const Watch = preload("res://scenes/components/props/meridian/Meridian.gd")
const HallFinish = preload("res://scenes/components/rendering/surfaces/HallFinish.gdshader")

static func _hall_mat(hex: String, roughness: float, grain: float) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = HallFinish
	m.set_shader_parameter("pigment", Color(hex))
	m.set_shader_parameter("surface_roughness", roughness)
	m.set_shader_parameter("grain", grain)
	m.set_shader_parameter("toon_on", true)
	m.set_shader_parameter("toon_strength", 0.86)
	return m

static func plan(lot: Dictionary) -> Rect2i:
	var allowed := {}
	var center := Vector2.ZERO
	for c: Vector2i in lot.floors:
		if lot.patterns.get(c, 0) != 65535:
			allowed[c] = true
			center += Vector2(c)
	center /= maxi(1, allowed.size())
	for o: Dictionary in lot.objects:
		if not o.get("annotation_only", false):
			allowed.erase(Vector2i(Vector2(o.position).floor()))
	var pick := Rect2i()
	for width: int in [6, 5, 4, 3, 2]:
		var best := INF
		for p: Vector2i in allowed:
			var dist := (Vector2(p) + Vector2.ONE * (width - 1) * 0.5).distance_squared_to(center)
			if dist >= best:
				continue
			var fits := true
			for i in width:
				for j in width:
					if not allowed.has(p + Vector2i(i, j)):
						fits = false
						break
				if not fits:
					break
			if not fits:
				continue
			var inset := Rect2(Vector2(p) + Vector2.ONE * 0.02, Vector2.ONE * (width - 0.04))
			for e: Vector4i in lot.segments:
				if inset.has_point(Vector2(e.x + e.z, e.y + e.w) * 0.5):
					fits = false
					break
			if fits:
				pick = Rect2i(p, Vector2i.ONE * width)
				best = dist
		if pick.has_area():
			break
	return pick

static func install(parent: Node3D, area: Rect2i, flush_display := false) -> void:
	var root := Node3D.new()
	root.name = "FloorMeridian"
	parent.add_child(root)
	var width := float(area.size.x)
	root.position = Vector3(area.position.x + width * 0.5, 0.0, area.position.y + width * 0.5)

	if flush_display:
		_build_foucault_dial(root, width)
		return

	# Non-Hall Observatory fallback keeps the original recessed Meridian watch mechanism.
	var watch := Watch.new()
	var s := width * 0.30
	watch.scale = Vector3.ONE * s
	watch.position.y = -0.89 * s
	root.add_child(watch)
	var bronze := _hall_mat("807159", 0.42, 0.05)
	var well := _hall_mat("283037", 0.88, 0.05)
	var glass: Material = ShaderMaterial.new()
	(glass as ShaderMaterial).shader = preload("res://scenes/components/props/meridian/Sapphire.gdshader")
	_box(root, Vector3(0, -1.83 * s, 0), Vector3(width, 0.10, width), well)
	for side: float in [-1.0, 1.0]:
		for lateral in [false, true]:
			var rail := Vector3(side * width * 0.49, 0, 0) if lateral else Vector3(0, 0, side * width * 0.49)
			var dims := Vector3(width * 0.025, 0.024, width) if lateral else Vector3(width, 0.024, width * 0.025)
			_box(root, rail, dims, bronze)
			dims.y = 1.84 * s
			_box(root, rail + Vector3.DOWN * dims.y * 0.5, dims, well)
	_box(root, Vector3(0, -0.01, 0), Vector3(width, 0.008, width), glass)
	var lamp := OmniLight3D.new()
	lamp.position = Vector3(0, -0.12 * s, s * 0.55)
	lamp.light_color = Color("fff1cd")
	lamp.omni_range = width * 0.85
	lamp.light_energy = 1.3
	root.add_child(lamp)

static func _build_foucault_dial(root: Node3D, width: float) -> void:
	## Authentic Panthéon-style Foucault pendulum floor structure:
	## shallow dark-slate marble basin, limestone degree ring, inlaid brass meridian
	## crosshairs, central brass sighting pin + 0.25m reference ring, and perimeter
	## standing knock-down pegs.
	var slate := _hall_mat("262d36", 0.86, 0.04)
	var slate_inner := _hall_mat("1e242c", 0.82, 0.03)
	var stone := _hall_mat("576572", 0.88, 0.04)
	var ivory := _hall_mat("dfd1b4", 0.84, 0.045)
	var brass := _hall_mat("d6a856", 0.26, 0.04)
	var bronze := _hall_mat("7e6d52", 0.44, 0.05)
	var peg_wood := _hall_mat("5d3f2a", 0.72, 0.06)

	var dial_r := minf(1.60, width * 0.40)  # Ø 3.20m optimal clear-aisle Panthéon dial
	# Flush limestone apron bridging 4x4m well opening to the Ø3.20m dial
	_box(root, Vector3(0.0, -0.065, 0.0), Vector3(width, 0.04, width), stone)

	# 1. Solid square sub-floor so there is no bottomless glowing pit
	_box(root, Vector3(0.0, -0.11, 0.0), Vector3(width, 0.10, width), slate)

	# 2. Shallow circular dark-slate pendulum floor basin (flush at y = -0.05m)
	_cyl(root, Vector3(0.0, -0.018, 0.0), dial_r, 0.03, slate_inner, 48)
	# Subtle recessed sand/marble inner disc (where the pointer sweeps)
	_cyl(root, Vector3(0.0, 0.000, 0.0), dial_r * 0.76, 0.010, slate, 48)

	# 3. Outer ivory limestone azimuth degree ring + raised bronze curb
	_torus(root, Vector3(0.0, 0.002, 0.0), dial_r * 0.84, dial_r * 0.96, 0.26, ivory)
	_torus(root, Vector3(0.0, 0.005, 0.0), dial_r * 0.955, dial_r * 1.005, 0.65, bronze)

	# 4. 360-degree brass azimuth ticks (60 fine ticks, 12 major hour-angle bars)
	for i in 60:
		var ang := TAU * float(i) / 60.0
		var is_cardinal := (i % 15 == 0)
		var is_major := (i % 5 == 0)
		var tick_len := 0.22 if is_cardinal else (0.14 if is_major else 0.065)
		var tick_w := 0.036 if is_cardinal else (0.024 if is_major else 0.012)
		var holder := Node3D.new()
		holder.rotation.y = ang
		root.add_child(holder)
		_box(holder, Vector3(0.0, 0.012, dial_r * 0.90), Vector3(tick_w, 0.010, tick_len), brass)

	# 5. Inlaid orthogonal N-S and E-W brass meridian crosshairs + 45-deg diagonals
	_box(root, Vector3(0.0, 0.007, 0.0), Vector3(0.024, 0.006, dial_r * 1.66), brass)
	_box(root, Vector3(0.0, 0.007, 0.0), Vector3(dial_r * 1.66, 0.006, 0.024), brass)
	for diag_ang: float in [PI * 0.25, -PI * 0.25]:
		var dnode := Node3D.new()
		dnode.rotation.y = diag_ang
		root.add_child(dnode)
		_box(dnode, Vector3(0.0, 0.006, 0.0), Vector3(0.012, 0.005, dial_r * 1.50), bronze)

	# 6. Center brass sighting pin (Ø 0.14m) + r=0.25m inner calibration ring (Rule 02 + H1)
	_cyl(root, Vector3(0.0, 0.012, 0.0), 0.07, 0.032, brass, 24)
	_cyl(root, Vector3(0.0, 0.032, 0.0), 0.022, 0.036, brass, 16)
	_torus(root, Vector3(0.0, 0.009, 0.0), 0.235, 0.265, 0.45, brass)

	# 7. Classic Panthéon knock-down pegs ring (24 small vertical pegs @ r = 1.38m; 2 tipped)
	var peg_r := dial_r * 0.74
	for k in 24:
		var ang := TAU * float(k) / 24.0
		var p_pos := Vector3(sin(ang) * peg_r, 0.006, cos(ang) * peg_r)
		var peg := Node3D.new()
		peg.position = p_pos
		peg.rotation.y = ang
		root.add_child(peg)
		if k in [1, 13]:
			# Tipped peg resting flat on the slate disc to show real precession
			peg.rotation.x = PI * 0.5
			peg.position.y = 0.018
		_cyl(peg, Vector3(0.0, 0.055, 0.0), 0.016, 0.11, peg_wood, 10)
		_cyl(peg, Vector3(0.0, 0.115, 0.0), 0.018, 0.014, brass, 10)

	# 8. Four stone corner spandrels trimming the 4x4m square floor opening to a brass-edged octagon
	for corner in 4:
		var quadrant := Node3D.new()
		quadrant.rotation.y = corner * PI * 0.5
		root.add_child(quadrant)
		var r := width * 0.5
		var cut := width * 0.27
		var st := SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		for pt in [Vector3(r, 0.012, r), Vector3(r - cut, 0.012, r), Vector3(r, 0.012, r - cut)]:
			st.set_normal(Vector3.UP)
			st.add_vertex(pt)
		var face := MeshInstance3D.new()
		face.mesh = st.commit()
		face.material_override = stone
		quadrant.add_child(face)
		var edging := Node3D.new()
		edging.position = Vector3(r - cut * 0.5, 0.018, r - cut * 0.5)
		edging.rotation.y = PI * 0.25
		quadrant.add_child(edging)
		_box(edging, Vector3.ZERO, Vector3(cut * sqrt(2.0), 0.026, 0.065), bronze)

	# 9. Square perimeter bronze trim strips flush with floor
	for side: float in [-1.0, 1.0]:
		for lateral in [false, true]:
			var rail := Vector3(side * width * 0.49, 0.008, 0.0) if lateral else Vector3(0.0, 0.008, side * width * 0.49)
			var dims := Vector3(width * 0.025, 0.022, width) if lateral else Vector3(width, 0.022, width * 0.025)
			_box(root, rail, dims, bronze)

static func _box(root: Node3D, p: Vector3, sz: Vector3, mat: Material) -> void:
	var mesh := BoxMesh.new()
	mesh.size = sz
	var inst := MeshInstance3D.new()
	inst.mesh = mesh
	inst.material_override = mat
	inst.position = p
	inst.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(inst)

static func _cyl(root: Node3D, p: Vector3, radius: float, height: float, mat: Material, segs := 24) -> void:
	var mesh := CylinderMesh.new()
	mesh.top_radius = radius
	mesh.bottom_radius = radius
	mesh.height = height
	mesh.radial_segments = segs
	var inst := MeshInstance3D.new()
	inst.mesh = mesh
	inst.material_override = mat
	inst.position = p
	inst.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(inst)

static func _torus(root: Node3D, p: Vector3, r_in: float, r_out: float, sy: float, mat: Material) -> void:
	var mesh := TorusMesh.new()
	mesh.inner_radius = r_in
	mesh.outer_radius = r_out
	var inst := MeshInstance3D.new()
	inst.mesh = mesh
	inst.material_override = mat
	inst.position = p
	inst.scale.y = sy
	inst.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(inst)
