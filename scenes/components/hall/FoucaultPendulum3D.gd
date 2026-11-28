@tool
class_name FoucaultPendulum3D
extends GothicHallPiece3D
## Suspended brass Foucault pendulum over the flush meridian dial (MeridianWell), with the
## calibration bezel, perimeter railing and essence light. The node sits on the dial centre.
## `drifting` = the abnormal opening state (8.1 s, off-centre precession).

const MeridianWell := preload("res://scenes/rogue_view/render/MeridianWell.gd")
const GRAVITY_STANDARD := 9.80665
const NORMAL_PERIOD_S := 7.0196 # 2*pi*sqrt(12.24/9.80665)
const DRIFT_PERIOD_S := 8.1

## Suspension height (the vault crown).
@export var ceiling_height := CROWN_H + 0.02:
	set(v): ceiling_height = v; changed()
## Dial size in floor cells (square, centred on the node).
@export_range(2, 8) var well_cells := 4:
	set(v): well_cells = v; shape_changed()
@export var flush_dial := true:
	set(v): flush_dial = v; changed()
@export var drifting := true:
	set(v): drifting = v; _apply_drift()
## Swing in the editor viewport too.
@export var preview_swing := false

var pendulum_pivot: Node3D
var pendulum_bob: Node3D
var drift_bezel: MeshInstance3D
var essence_light: OmniLight3D
var _time := 0.0
var _drift_angle := 0.24

func shape_key() -> Array: return [well_cells]
func plan_outline() -> PackedVector2Array:
	var h := well_cells * 0.5
	return _rect_outline(Rect2(-h, -h, well_cells, well_cells))

## Dial cells in structure space (no floor tiles are laid there).
func well_rect() -> Rect2i:
	var c := to_plan(Vector3.ZERO)
	var half := well_cells / 2
	return Rect2i(Vector2i(roundi(c.x) - half, roundi(c.y) - half), Vector2i(well_cells, well_cells))

func get_pendulum_period_sec() -> float:
	return snappedf(DRIFT_PERIOD_S if drifting else NORMAL_PERIOD_S, 0.1)

func _build() -> void:
	var half := well_cells / 2
	MeridianWell.install(self, Rect2i(-half, -half, well_cells, well_cells), flush_dial)
	var ceiling_y := ceiling_height
	var cap := MeshInstance3D.new()
	var cap_mesh := CylinderMesh.new()
	cap_mesh.top_radius = 0.28; cap_mesh.bottom_radius = 0.18; cap_mesh.height = 0.22
	cap.mesh = cap_mesh
	cap.position = Vector3(0.0, ceiling_y, 0.0)
	cap.material_override = mat("brass")
	add_child(cap)
	pendulum_pivot = Node3D.new()
	pendulum_pivot.name = "PendulumPivot"
	pendulum_pivot.position = Vector3(0.0, ceiling_y - 0.08, 0.0)
	add_child(pendulum_pivot)
	var cable_len := ceiling_y - 0.38
	var cable := MeshInstance3D.new()
	var cable_mesh := CylinderMesh.new()
	cable_mesh.top_radius = 0.008; cable_mesh.bottom_radius = 0.008; cable_mesh.height = cable_len
	cable.mesh = cable_mesh
	cable.position = Vector3(0.0, -cable_len * 0.5, 0.0)
	cable.material_override = mat("lead")
	pendulum_pivot.add_child(cable)
	pendulum_bob = Node3D.new()
	pendulum_bob.name = "PendulumBob"
	pendulum_bob.position = Vector3(0.0, -cable_len, 0.0)
	pendulum_bob.scale = Vector3.ONE * 1.18
	pendulum_pivot.add_child(pendulum_bob)
	var sphere := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 0.20; sm.height = 0.40
	sphere.mesh = sm
	sphere.material_override = mat("brass")
	pendulum_bob.add_child(sphere)
	var equator := MeshInstance3D.new()
	var tm := TorusMesh.new()
	tm.inner_radius = 0.20; tm.outer_radius = 0.245
	equator.mesh = tm
	equator.material_override = mat("brass")
	pendulum_bob.add_child(equator)
	var needle := MeshInstance3D.new()
	var nm := CylinderMesh.new()
	nm.top_radius = 0.04; nm.bottom_radius = 0.004; nm.height = 0.28
	needle.mesh = nm
	needle.position = Vector3(0.0, -0.30, 0.0)
	needle.material_override = mat("brass")
	pendulum_bob.add_child(needle)
	var well_r := minf(1.60, float(well_cells) * 0.40)
	drift_bezel = MeshInstance3D.new()
	var ring_mesh := TorusMesh.new()
	ring_mesh.inner_radius = well_r - 0.028
	ring_mesh.outer_radius = well_r
	drift_bezel.mesh = ring_mesh
	drift_bezel.position = Vector3(0.0, 0.022, 0.0)
	drift_bezel.material_override = RenderProfile.make_hall_finish(Color("4d8f75"), 0.35, 0.045, false, false, 0.0, 0.0, 0.22)
	add_child(drift_bezel)
	var rail_r := well_r + 0.10
	var rail_h := 0.74
	var rail_ring := MeshInstance3D.new()
	var rail_torus := TorusMesh.new()
	rail_torus.inner_radius = rail_r - 0.018
	rail_torus.outer_radius = rail_r + 0.018
	rail_ring.mesh = rail_torus
	rail_ring.position = Vector3(0.0, rail_h, 0.0)
	rail_ring.material_override = mat("brass")
	add_child(rail_ring)
	for k in 8:
		var ang := TAU * float(k) / 8.0
		var post := MeshInstance3D.new()
		var pm := CylinderMesh.new()
		pm.top_radius = 0.022; pm.bottom_radius = 0.032; pm.height = rail_h
		post.mesh = pm
		post.position = Vector3(cos(ang) * rail_r, rail_h * 0.5, sin(ang) * rail_r)
		post.material_override = mat("brass")
		add_child(post)
	essence_light = OmniLight3D.new()
	essence_light.position = Vector3(0.0, 0.52, 0.0)
	essence_light.omni_range = 4.2
	essence_light.shadow_enabled = false
	add_child(essence_light)
	_apply_drift()

func set_drift_state(is_drifting: bool) -> void:
	drifting = is_drifting  # setter applies it

func _apply_drift() -> void:
	if is_instance_valid(drift_bezel) and drift_bezel.material_override is ShaderMaterial:
		var rm := drift_bezel.material_override as ShaderMaterial
		rm.set_shader_parameter("pigment", Color("9e3a2b") if drifting else Color("4d8f75"))
		rm.set_shader_parameter("emission_gain", 0.45 if drifting else 0.22)
	if is_instance_valid(essence_light):
		essence_light.light_color = Color("f08a62") if drifting else Color("ffe0a3")
		essence_light.light_energy = 1.25 if drifting else 0.90

func _process(delta: float) -> void:
	if not is_instance_valid(pendulum_pivot) or (Engine.is_editor_hint() and not preview_swing):
		return
	_time += delta
	if drifting:
		var base_phase := _time * TAU / DRIFT_PERIOD_S
		var swing := 0.095 * sin(base_phase)
		var lateral_off := 0.034 * cos(base_phase)
		pendulum_pivot.rotation = Vector3(swing * sin(_drift_angle) + lateral_off, _drift_angle, swing * cos(_drift_angle))
		if is_instance_valid(essence_light):
			essence_light.light_energy = 0.85 + 0.12 * sin(base_phase)
	else:
		var swing := 0.092 * sin(_time * TAU / NORMAL_PERIOD_S)
		var slow_precession := fmod(_time * 0.015, TAU)
		pendulum_pivot.rotation = Vector3(swing * sin(slow_precession), slow_precession, swing * cos(slow_precession))
		if is_instance_valid(essence_light):
			essence_light.light_energy = 0.85 + 0.06 * sin(_time * 1.2)
