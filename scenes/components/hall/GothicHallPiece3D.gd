@tool
class_name GothicHallPiece3D
extends "res://scenes/components/structure/StructurePiece3D.gd"
## Shared base of the Public Hall's editable Gothic components (vault, piers, lancet bays,
## gables, oculi, arcades, paving, lamps, furniture…). Each component builds its own
## geometry from its exported parameters, in its own local space, with the helper code
## and the locked Hall 04 palette below; move it with the gizmo, tune it in the Inspector.
##
## Time of day: every piece keeps its own glass / beam / glow materials and lights and
## answers apply_hour(); PublicHallGothic forwards set_hour() to all of them.
## Reserved stations (furniture footprints) become collision boxes and station_bounds.

const RenderProfile := preload("res://scenes/components/rendering/AcademyRenderProfile.gd")
const StainedGlassShader := preload("res://scenes/rogue_view/render/StainedGlass.gdshader")
const StainedGlassBeamShader := preload("res://scenes/rogue_view/render/StainedGlassBeam.gdshader")
const StainedGlassGlowShader := preload("res://scenes/rogue_view/render/StainedGlassGlow.gdshader")
const FurnitureCatalog := preload("res://scenes/components/shared/AcademyFurnitureCatalog.gd")

const LANCET_TEX := "res://tools/research/french_gothic_nodes/lancet_register.png"
const ROSE_NORTH_TEX := "res://tools/research/french_gothic_nodes/rose_register.png"
const ROSE_SOUTH_TEX := "res://tools/research/french_gothic_nodes/rose_botanical.png"

const SPRING_H := 6.00
const ARCADE_INSET := 0.30
const PIER_INSET := 0.29
const CROWN_RISE := 6.60
const CROWN_H := SPRING_H + CROWN_RISE
const ARCADE_SPRING := 2.85
const ARCADE_RISE := 1.80
const WING_SPRING := 2.58
const WING_ROOF := 5.20

## Hour used to preview glass and lamps in the editor (the game sets its own).
static var preview_hour := 4.0
static var _materials := {}

var _glass_mats: Array[ShaderMaterial] = []
var _beam_mats: Array[ShaderMaterial] = []
var _glow_mats: Array[ShaderMaterial] = []
var _window_lights: Array[Dictionary] = []
var _daylight_fills: Array[Dictionary] = []
var _lanterns: Array[Node3D] = []
var _pools: Array[Dictionary] = []
var _stations: Array[Rect2] = []

func _enter_tree() -> void:
	add_to_group(&"gothic_hall_piece")

# ── build cycle ───────────────────────────────────────────────────────────────

func rebuild() -> void:
	_clear_generated()
	_build()
	apply_hour(preview_hour)

## Subclasses build here, in local space, adding generated children to self.
func _build() -> void:
	pass

func _clear_generated() -> void:
	for child in get_children():
		if is_generated(child):  # generated (never saved); authored children are owned by the scene
			remove_child(child)
			child.queue_free()
	_glass_mats.clear(); _beam_mats.clear(); _glow_mats.clear()
	_window_lights.clear(); _daylight_fills.clear(); _lanterns.clear(); _pools.clear()
	_stations.clear()

func reserved_stations() -> Array[Rect2]:
	return _stations

## Mesh-only parameter changed (most component parameters).
func changed() -> void:
	mesh_changed()

# ── materials (locked Hall 04 palette, shared by all pieces) ──────────────────

static func mat(key: String) -> Material:
	if _materials.has(key):
		return _materials[key]
	var m: Material
	match key:
		"wall": m = _finish("4b5868", 0.88, 0.032, false, false, 0.03, {"pale_wash": 0.09})
		"rib": m = _finish("8a96a6", 0.80, 0.025, false, false, 0.04, {"pale_wash": 0.13})
		"vault": m = _finish("3a4554", 0.92, 0.035, false, false, 0.06, {"pale_wash": 0.10})
		"plinth": m = _finish("333b46", 0.86, 0.03, false, false, 0.02)
		"wood": m = _finish("3f2b1f", 0.76, 0.06, true, false, 0.0)
		"runner": m = _finish("ca9857", 0.92, 0.05, false, true, 0.0, {"emission_gain": 0.18})
		"lead": m = _finish("1f242b", 0.70, 0.03, false, false, 0.0)
		"brass": m = RenderProfile.make_hall_finish(Color("cfa04c"), 0.28, 0.045)
		"canvas": m = RenderProfile.make_hall_finish(Color("74765b"), 0.95, 0.09, false, false, 0.0)
		"embers":
			var e := StandardMaterial3D.new()
			e.albedo_color = Color("ff862d"); e.emission_enabled = true
			e.emission = Color("ff7022"); e.emission_energy_multiplier = 3.4
			m = e
		_:
			push_warning("GothicHallPiece3D: unknown material '%s'" % key)
			m = _finish("4b5868", 0.88, 0.032, false, false, 0.03)
	_materials[key] = m
	return m

static func _finish(hex: String, roughness: float, grain: float, is_wood: bool, is_runner: bool, vault_fill: float, params := {}) -> ShaderMaterial:
	var m := RenderProfile.make_hall_finish(Color(hex), roughness, grain, is_wood, is_runner, vault_fill)
	for k in params:
		m.set_shader_parameter(k, params[k])
	return m

static func load_texture(path: String) -> Texture2D:
	if path != "" and ResourceLoader.exists(path):
		return load(path) as Texture2D
	return null

# ── time of day ───────────────────────────────────────────────────────────────

func apply_hour(hour: float) -> void:
	var daylight := smoothstep(0.0, 1.0, maxf(0.0, cos((fposmod(hour, 24.0) - 12.0) * PI / 12.0)))
	var night_mix := 1.0 - daylight
	var sky_tint := Color("1f3154").lerp(Color("fff4d6"), daylight)
	for m in _glass_mats:
		m.set_shader_parameter("daylight", daylight)
		m.set_shader_parameter("exterior_tint", sky_tint)
	var beam_scale := lerpf(0.0, 1.05, pow(daylight, 0.85))
	var beam_tint := Color("7fa8de").lerp(Color("fff1cc"), daylight)
	for m in _beam_mats:
		m.set_shader_parameter("beam_tint", beam_tint)
		m.set_shader_parameter("beam_intensity", float(m.get_meta("base_intensity", 0.35)) * beam_scale)
	var glow_scale := pow(daylight, 0.85)
	for m in _glow_mats:
		m.set_shader_parameter("glow_tint", beam_tint)
		m.set_shader_parameter("glow_strength", float(m.get_meta("base_strength", 0.30)) * glow_scale)
	for entry in _window_lights:
		var light := entry.get("light") as Light3D
		if not is_instance_valid(light):
			continue
		var tint: Color = entry.get("tint", beam_tint)
		light.light_color = tint.lerp(beam_tint, 0.45)
		var energy := lerpf(float(entry.get("night", 0.0)), float(entry.get("day", 4.8)), daylight)
		light.light_energy = energy
		light.visible = energy > 0.02
	for entry in _daylight_fills:
		var light := entry.get("light") as Light3D
		if not is_instance_valid(light):
			continue
		var energy := lerpf(0.0, float(entry.get("day", 2.8)), daylight)
		light.light_energy = energy
		light.visible = energy > 0.02
	var lamp_factor := lerpf(0.04, 1.0, pow(night_mix, 0.72))
	for lamp in _lanterns:
		if is_instance_valid(lamp) and lamp.has_method("set_lit_factor"):
			lamp.set_lit_factor(lamp_factor, 2.9, 8.5)
	for entry in _pools:
		var light := entry.get("light") as OmniLight3D
		if is_instance_valid(light):
			light.light_energy = lerpf(float(entry.get("day", 0.15)), float(entry.get("night", 1.5)), night_mix)

# ── helpers (shared geometry code, local space) ───────────────────────────────

func _reserve_station(pos: Vector3, footprint: Vector2, height: float) -> void:
	var c := to_plan(pos)
	_stations.append(Rect2(c - footprint * 0.5, footprint))
	var body := StaticBody3D.new()
	# Footprints are authored in structure axes: undo this piece's own rotation.
	body.transform = Transform3D(to_scope().basis.orthonormalized().inverse(), pos + Vector3.UP * height * 0.5)
	var shape := BoxShape3D.new(); shape.size = Vector3(footprint.x, height, footprint.y)
	var col := CollisionShape3D.new(); col.shape = shape; body.add_child(col); add_child(body)

func _pool(pos: Vector3, tint: Color, energy: float, reach: float) -> OmniLight3D:
	var lamp := OmniLight3D.new()
	lamp.position = pos
	lamp.light_color = tint
	lamp.light_energy = energy
	lamp.omni_range = reach
	add_child(lamp)
	_pools.append({"light": lamp, "night": energy, "day": energy * 0.14})
	return lamp

func _glb_prop(parent: Node3D, path: String, pos: Vector3, yaw := 0.0, uniform_scale := 1.0, brass := false) -> Node3D:
	var preset := "brass_antique" if (brass or "candle" in path) else ("oak_aged" if ("stool" in path or "crate" in path or "chest" in path) else "walnut_varnish")
	return FurnitureCatalog.spawn_glb(parent, path, pos, yaw, uniform_scale, preset)

static func recipe_preset(recipe: String) -> String:
	if recipe in ["Cabinets/Bookshelf", "Cabinets/LinenCabinet", "Tables/ReceptionDesk", "Props/Screen"]:
		return "walnut_varnish"
	if recipe in ["Props/Stove", "Props/KitchenHood"]:
		return "iron_wrought"
	if recipe == "Props/Chalkboard":
		return "slate_honed"
	if recipe.begins_with("Lighting/"):
		return "brass_antique"
	if recipe == "Props/Schematic":
		return "linen_cream"
	return "oak_aged"

func _prop(parent: Node3D, recipe: String, pos: Vector3, yaw := 0.0, params := {}) -> Node3D:
	return FurnitureCatalog.spawn_recipe(parent, recipe, pos, yaw, params, recipe_preset(recipe))

static func pointed_arch_y(x_norm: float) -> float:
	var u := clampf(absf(x_norm), 0, 1)
	return CROWN_RISE * sqrt(maxf(0, 4.0 - pow(u + 1.0, 2)) / 3.0)

static func vault_height(nx: float, nz: float) -> float:
	var transverse := pointed_arch_y(nx)
	return SPRING_H + transverse + 0.42 * maxf(0, pointed_arch_y(nz) - transverse)

func _make_stained_glass_mat(tex: Texture2D, fallback: Color, emit_gain: float) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = StainedGlassShader
	m.set_shader_parameter("glass_tex", tex)
	m.set_shader_parameter("has_tex", tex != null)
	m.set_shader_parameter("fallback_color", fallback)
	m.set_shader_parameter("emit_gain", maxf(emit_gain, 0.45))
	_glass_mats.append(m)
	return m

func _build_glass_glow_quad(parent: Node3D, center: Vector3, u_vec: Vector3, v_vec: Vector3, normal: Vector3, tex: Texture2D, fallback: Color, uv_rect: Vector4, base_strength: float, is_circular: float, quad_name: String) -> void:
	var m := ShaderMaterial.new()
	m.shader = StainedGlassGlowShader
	m.render_priority = 104
	m.set_shader_parameter("glass_tex", tex)
	m.set_shader_parameter("has_tex", tex != null)
	m.set_shader_parameter("fallback_color", fallback)
	m.set_shader_parameter("uv_rect", uv_rect)
	m.set_shader_parameter("glow_strength", 0.0)
	m.set_shader_parameter("is_circular", is_circular)
	m.set_meta("base_strength", base_strength)
	_glow_mats.append(m)
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var hu := u_vec * 0.5
	var hv := v_vec * 0.5
	_add_uv_quad(st, center - hu - hv, center + hu - hv, center + hu + hv, center - hu + hv, Vector2(0.0, 1.0), Vector2(1.0, 1.0), Vector2(1.0, 0.0), Vector2(0.0, 0.0), normal)
	var inst := MeshInstance3D.new()
	inst.name = quad_name
	inst.mesh = st.commit()
	inst.material_override = m
	inst.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	inst.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
	parent.add_child(inst)

func _build_tyndall_beam(parent: Node3D, origin: Vector3, dir: Vector3, start_r: float, end_r: float, length: float, tex: Texture2D, fallback: Color, uv_rect: Vector4, base_intensity: float, beam_name: String) -> void:
	var n_dir := dir.normalized()
	var ref_up := Vector3.UP if absf(n_dir.y) < 0.92 else Vector3.RIGHT
	var side := n_dir.cross(ref_up).normalized()
	var up := side.cross(n_dir).normalized()
	var cone_mat := ShaderMaterial.new()
	cone_mat.shader = StainedGlassBeamShader
	cone_mat.render_priority = 105
	cone_mat.set_shader_parameter("stained_tex", tex)
	cone_mat.set_shader_parameter("has_tex", tex != null)
	cone_mat.set_shader_parameter("fallback_color", fallback)
	cone_mat.set_shader_parameter("uv_rect", uv_rect)
	cone_mat.set_shader_parameter("beam_intensity", base_intensity)
	cone_mat.set_shader_parameter("radial_wrap", 1.0)
	cone_mat.set_meta("base_intensity", base_intensity)
	_beam_mats.append(cone_mat)
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var segs := 12
	for i in segs:
		var u0 := float(i) / float(segs)
		var u1 := float(i + 1) / float(segs)
		var d0 := side * cos(TAU * u0) + up * sin(TAU * u0)
		var d1 := side * cos(TAU * u1) + up * sin(TAU * u1)
		_add_uv_quad(st, origin + d0 * start_r, origin + d1 * start_r, origin + n_dir * length + d1 * end_r, origin + n_dir * length + d0 * end_r,
			Vector2(u0, 0.0), Vector2(u1, 0.0), Vector2(u1, 1.0), Vector2(u0, 1.0), (d0 + d1).normalized())
	var cone := MeshInstance3D.new()
	cone.name = beam_name
	cone.mesh = st.commit()
	cone.material_override = cone_mat
	cone.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	cone.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
	parent.add_child(cone)
	var rib_mat := cone_mat.duplicate() as ShaderMaterial
	rib_mat.set_shader_parameter("radial_wrap", 0.0)
	rib_mat.set_shader_parameter("beam_intensity", base_intensity * 0.65)
	rib_mat.set_meta("base_intensity", base_intensity * 0.65)
	_beam_mats.append(rib_mat)
	var rst := SurfaceTool.new()
	rst.begin(Mesh.PRIMITIVE_TRIANGLES)
	for axis: Vector3 in [side, up]:
		var n := axis.cross(n_dir).normalized()
		_add_uv_quad(rst, origin - axis * start_r * 0.9, origin + axis * start_r * 0.9, origin + n_dir * length + axis * end_r * 0.9, origin + n_dir * length - axis * end_r * 0.9,
			Vector2(0.0, 0.0), Vector2(1.0, 0.0), Vector2(1.0, 1.0), Vector2(0.0, 1.0), n)
	var ribs := MeshInstance3D.new()
	ribs.name = beam_name + "_Core"
	ribs.mesh = rst.commit()
	ribs.material_override = rib_mat
	ribs.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	ribs.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
	parent.add_child(ribs)

## A spot light aimed along dir (works before the piece is in the tree).
func _aimed_spot(parent: Node3D, pos: Vector3, dir: Vector3) -> SpotLight3D:
	var spot := SpotLight3D.new()
	spot.transform = Transform3D(Basis.looking_at(dir, Vector3.UP), pos)
	parent.add_child(spot)
	return spot

func _commit_mesh(st: SurfaceTool, m: Material, mesh_name: String, parent: Node3D = null) -> MeshInstance3D:
	var inst := MeshInstance3D.new()
	inst.name = mesh_name
	inst.mesh = st.commit()
	inst.material_override = m
	inst.gi_mode = GeometryInstance3D.GI_MODE_STATIC
	(self if parent == null else parent).add_child(inst)
	return inst

static func _add_quad(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3) -> void:
	st.add_vertex(a); st.add_vertex(b); st.add_vertex(c)
	st.add_vertex(a); st.add_vertex(c); st.add_vertex(d)

static func _add_uv_quad(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3, uva: Vector2, uvb: Vector2, uvc: Vector2, uvd: Vector2, n: Vector3) -> void:
	_add_uv_tri(st, a, b, c, uva, uvb, uvc, n)
	_add_uv_tri(st, a, c, d, uva, uvc, uvd, n)

static func _add_uv_tri(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, uva: Vector2, uvb: Vector2, uvc: Vector2, n: Vector3) -> void:
	st.set_normal(n); st.set_uv(uva); st.add_vertex(a)
	st.set_normal(n); st.set_uv(uvb); st.add_vertex(b)
	st.set_normal(n); st.set_uv(uvc); st.add_vertex(c)

static func _sweep_rib(st: SurfaceTool, path: PackedVector3Array, r: float) -> void:
	if path.size() < 2:
		return
	var sides := 6
	var rings: Array = []
	var prev_side := Vector3.ZERO
	for i in path.size():
		var p_prev := path[maxi(i - 1, 0)]
		var p_next := path[mini(i + 1, path.size() - 1)]
		var t := (p_next - p_prev).normalized()
		if t.length_squared() < 1e-6:
			t = Vector3.UP
		var ref := Vector3.UP if absf(t.y) < 0.92 else Vector3.RIGHT
		var side := t.cross(ref).normalized()
		if prev_side.length_squared() > 0.01 and prev_side.dot(side) < 0.0:
			side = -side
		prev_side = side
		var up := side.cross(t).normalized()
		var ring: Array = []
		for k in sides:
			var ang := TAU * float(k) / float(sides)
			ring.append(path[i] + (side * cos(ang) + up * sin(ang)) * r)
		rings.append(ring)
	for i in path.size() - 1:
		for k in sides:
			var kn := (k + 1) % sides
			_add_quad(st, rings[i][k], rings[i][kn], rings[i + 1][kn], rings[i + 1][k])

static func _box(parent: Node3D, p: Vector3, sz: Vector3, m: Material) -> MeshInstance3D:
	var inst := MeshInstance3D.new()
	var b := BoxMesh.new()
	b.size = sz
	inst.mesh = b
	inst.position = p
	inst.material_override = m
	inst.gi_mode = GeometryInstance3D.GI_MODE_STATIC
	parent.add_child(inst)
	return inst

## Axis-aligned plan rectangle (local XZ) → plan-space outline.
func _rect_outline(local: Rect2) -> PackedVector2Array:
	return PackedVector2Array([
		to_plan(Vector3(local.position.x, 0, local.position.y)), to_plan(Vector3(local.end.x, 0, local.position.y)),
		to_plan(Vector3(local.end.x, 0, local.end.y)), to_plan(Vector3(local.position.x, 0, local.end.y))])
