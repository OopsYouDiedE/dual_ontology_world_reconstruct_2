extends Node3D
## 书房舞台：窗外夜海保持冷色，仅远处火山口照亮局部灰云。
## 只负责模型、灯光、镜头与动态效果。书页内容的纹理与输入换算由 BookUI 通过下方公开接口完成。

const DETAIL := preload("res://scenes/components/world/BookSurfaceDetail3D.gd")
const LEAF_SCENE := preload("res://scenes/components/world/BookLeafTurn3D.tscn")
const SPREAD_SHADER := preload("res://assets/materials/book_spread_page.gdshader")
const SKY_SHADER := preload("res://assets/materials/night_volcano_sky.gdshader")
const SEA_SHADER := preload("res://assets/materials/night_sea.gdshader")
const CURTAIN_SHADER := preload("res://assets/materials/study_curtain.gdshader")
const BEAM_SHADER := preload("res://assets/materials/lighthouse_beam.gdshader")
const FLAME_SHADER := preload("res://assets/materials/desk_flame.gdshader")
const GLASS_SHADER := preload("res://assets/materials/desk_glass.gdshader")
const COVER_FONT := preload("res://assets/external/yujisyuku/YujiSyuku-Regular.ttf")

## 单页尺寸（米）。对开页为 2 × PAGE_SIZE.x 宽。
const PAGE_SIZE := Vector2(0.30, 0.40)
const STACK := 0.016
const COVER := 0.006
const BOOK_ORIGIN := Vector3(-0.02, 0.004, 0.06)
const BOOK_YAW := -0.06
const SEA_Y := -6.0
const VOLCANO := Vector3(-30.0, SEA_Y, -105.0)
const VOLCANO_HEIGHT := 14.0
const PAPER := Color(0.87, 0.81, 0.69)
const TITLE_CAMERA := {"position": Vector3(0.66, 0.60, 1.06), "target": Vector3(-0.06, 0.18, -0.50), "fov": 44.0, "h_offset": 0.20}
const READ_FOV := 40.0

var camera: Camera3D
var opened := 0.0: set = _set_opened
var focus := 0.0
var ink := 0.0: set = _set_ink
var reduce_motion := false
var flash_enabled := true
# BookUI 与 MCP 观察读取的书本状态。
var turn_lift := 0.0
var title_spread := true
var casebook_spread := false

var _book: Node3D
var _hinge: Node3D
var _spine: MeshInstance3D
var _spread: MeshInstance3D
var _spread_material: ShaderMaterial
var _leaf: Node3D
var _cover_material: StandardMaterial3D
var _lamp_light: OmniLight3D
var _flame_material: ShaderMaterial
var _window_light: SpotLight3D
var _sky_material: ShaderMaterial
var _sea_material: ShaderMaterial
var _crater_material: StandardMaterial3D
var _embers: GPUParticles3D
var _beam_pivot: Node3D
var _curtains: Array[ShaderMaterial] = []
var _watch_hands: Array[Node3D] = []
var _hover := 0.0
var _hover_target := false
var _pointer := Vector2.ZERO
var _pointer_smooth := Vector2.ZERO
var _time := 0.0
var _flash := 0.0
var _next_flash := 4.0
var _sequence: Tween

func _ready() -> void:
	_build_environment()
	_build_room()
	_build_outside()
	_build_desk()
	_build_tools()
	_build_book()
	_build_particles()
	var settings := get_node_or_null("/root/GameSettings")
	if settings != null:
		reduce_motion = bool(settings.get_value("accessibility", "reduce_motion"))
		flash_enabled = bool(settings.get_value("accessibility", "screen_flash"))
		settings.setting_changed.connect(_on_setting_changed)
	_set_opened(0.0)
	_set_ink(0.0)
	_update_camera(0.0)

# ================================================================ public API ===

## 显示或隐藏整个舞台。隐藏时停止处理，现场模式下不占用帧时间。
func set_active(active: bool) -> void:
	visible = active
	process_mode = Node.PROCESS_MODE_INHERIT if active else Node.PROCESS_MODE_DISABLED
	if active: camera.make_current()

## 鼠标在屏幕中的归一化位置（-1..1），用于标题镜头的轻微视差。
func set_pointer(value: Vector2) -> void:
	_pointer = value.clamp(-Vector2.ONE, Vector2.ONE)

func set_hover(active: bool) -> void:
	_hover_target = active

## 书页的实时界面纹理（BookUI 的 SubViewport）。
func set_spread_texture(texture: Texture2D) -> void:
	_spread_material.set_shader_parameter("live_texture", texture)

## 翻页期间，左右半页可改为显示旧页面的快照。传 null 恢复实时显示。
func freeze_spread(snapshot: Texture2D, left: bool, right: bool) -> void:
	_spread_material.set_shader_parameter("snapshot_texture", snapshot)
	_spread_material.set_shader_parameter("left_snapshot", snapshot != null and left)
	_spread_material.set_shader_parameter("right_snapshot", snapshot != null and right)

## 镜头推向书本并翻开封面，然后显出书页墨迹。
func open_sequence() -> void:
	var speed := 0.35 if reduce_motion else 1.0
	_restart_sequence()
	_sequence.tween_property(self, "focus", 1.0, 1.15 * speed).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN_OUT)
	_sequence.parallel().tween_property(self, "opened", 1.0, 0.95 * speed).set_delay(0.40 * speed).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	_sequence.tween_property(self, "ink", 1.0, 0.35 * speed)
	await _sequence.finished

## 墨迹淡去、合上封面并把镜头拉回标题构图。
func close_sequence() -> void:
	var speed := 0.35 if reduce_motion else 1.0
	_restart_sequence()
	_sequence.tween_property(self, "ink", 0.0, 0.22 * speed)
	_sequence.tween_property(self, "opened", 0.0, 0.80 * speed).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	_sequence.parallel().tween_property(self, "focus", 0.0, 1.05 * speed).set_delay(0.25 * speed).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN_OUT)
	await _sequence.finished

## 不播放动画，直接回到合上的标题构图。
func snap_closed() -> void:
	if _sequence != null: _sequence.kill()
	_leaf.visible = false
	freeze_spread(null, false, false)
	ink = 0.0
	opened = 0.0
	focus = 0.0
	_update_camera(0.0)

## 准备一张翻动的书叶。forward=true 时书叶从右翻到左。
## 纹理矩形取 UV 空间：左半页 Rect2(0, 0, 0.5, 1)，右半页 Rect2(0.5, 0, 0.5, 1)。
func prepare_leaf(forward: bool, front: Texture2D, front_rect: Rect2, back: Texture2D, back_rect: Rect2) -> void:
	_leaf.configure(front, back, PAGE_SIZE, not forward)
	_leaf.set_uv_rects(front_rect, back_rect)
	_leaf.set_blank_paper(PAPER)
	_leaf.set_tint(Color(0.96, 0.94, 0.92))
	_leaf.visible = true

func play_leaf() -> void:
	var tween := create_tween()
	tween.tween_method(_set_leaf_progress, 0.0, 1.0, 0.28 if reduce_motion else 0.72).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	await tween.finished
	_leaf.visible = false
	turn_lift = 0.0

## 屏幕坐标 → 对开页 UV（0..1）；未落在书页上时返回 (-1, -1)。
func screen_to_page_uv(point: Vector2) -> Vector2:
	if camera == null or not _spread.visible: return Vector2(-1.0, -1.0)
	var plane := Plane(_spread.global_basis.y.normalized(), _spread.global_position)
	var hit: Variant = plane.intersects_ray(camera.project_ray_origin(point), camera.project_ray_normal(point))
	if hit == null: return Vector2(-1.0, -1.0)
	var local: Vector3 = _spread.global_transform.affine_inverse() * (hit as Vector3)
	var uv := Vector2((local.x + PAGE_SIZE.x) / (PAGE_SIZE.x * 2.0), (local.z + PAGE_SIZE.y * 0.5) / PAGE_SIZE.y)
	return uv if Rect2(0.0, 0.0, 1.0, 1.0).has_point(uv) else Vector2(-1.0, -1.0)

func page_uv_to_screen(uv: Vector2) -> Vector2:
	var local := Vector3((uv.x * 2.0 - 1.0) * PAGE_SIZE.x, 0.0, (uv.y - 0.5) * PAGE_SIZE.y)
	return camera.unproject_position(_spread.global_transform * local)

## 屏幕点是否落在桌上的书本上（按当前开合状态的包围盒判断）。
func pick_book(point: Vector2) -> bool:
	if camera == null or not visible: return false
	var left := lerpf(0.0, -PAGE_SIZE.x - 0.012, opened)
	var half_z := PAGE_SIZE.y * 0.5 + 0.012
	var top := 2.0 * (STACK + COVER)
	var bounds := Rect2()
	var first := true
	for corner in 8:
		var local := Vector3(left if corner & 1 == 0 else PAGE_SIZE.x + 0.012, 0.0 if corner & 2 == 0 else top, -half_z if corner & 4 == 0 else half_z)
		var world := _book.global_transform * local
		if camera.is_position_behind(world): return false
		var screen := camera.unproject_position(world)
		if first: bounds = Rect2(screen, Vector2.ZERO); first = false
		else: bounds = bounds.expand(screen)
	return bounds.has_point(point)

# ================================================================== frame ===

func _process(delta: float) -> void:
	_time += delta
	var motion := 0.0 if reduce_motion else 1.0
	_hover = move_toward(_hover, 1.0 if _hover_target and opened < 0.01 else 0.0, delta * 5.0)
	_cover_material.emission_energy_multiplier = _hover * 0.35
	_pointer_smooth = _pointer_smooth.lerp(_pointer * motion, 1.0 - exp(-delta * 3.0))
	_update_book_pose()
	_update_camera(motion)
	# 灯焰与灯光的不规则闪烁。
	var flicker := 0.5 * sin(_time * 7.3) + 0.3 * sin(_time * 13.1 + 1.7) + 0.2 * sin(_time * 23.7 + 0.4)
	_lamp_light.light_energy = 1.25 + 0.10 * flicker * motion
	_flame_material.set_shader_parameter("wind", (0.10 * sin(_time * 1.9) + 0.05 * flicker) * motion)
	_flame_material.set_shader_parameter("intensity", 1.0 + 0.08 * flicker * motion)
	for material in _curtains: material.set_shader_parameter("sway", 0.25 if reduce_motion else 1.0)
	_beam_pivot.rotation.y = _time * 0.55
	_update_watch()
	_update_eruption(delta)

func _update_book_pose() -> void:
	var basis := Basis(Vector3.UP, BOOK_YAW)
	_book.transform = Transform3D(basis, BOOK_ORIGIN + basis.x * (-(1.0 - opened) * PAGE_SIZE.x * 0.5) + Vector3.UP * _hover * 0.012)

func _update_camera(motion: float) -> void:
	if camera == null: return
	var eased := smoothstep(0.0, 1.0, focus)
	var book_basis := Basis(Vector3.UP, BOOK_YAW)
	var spine := BOOK_ORIGIN + Vector3.UP * (COVER + STACK)
	var read_target := spine
	var read_position := spine + book_basis.y * 0.62 + book_basis.z * 0.105
	var sway := Vector3(sin(_time * 0.21) * 0.014, sin(_time * 0.17) * 0.009, sin(_time * 0.13) * 0.010) * motion
	var parallax := Vector3(_pointer_smooth.x * 0.05, -_pointer_smooth.y * 0.025, 0.0)
	var title_position: Vector3 = TITLE_CAMERA.position + sway + parallax
	var position := title_position.lerp(read_position, eased) + Vector3.UP * sin(eased * PI) * 0.06
	var target: Vector3 = (TITLE_CAMERA.target as Vector3).lerp(read_target, eased)
	position += Vector3(_pointer_smooth.x, 0.0, _pointer_smooth.y) * 0.004 * eased
	camera.fov = lerpf(TITLE_CAMERA.fov, READ_FOV, eased)
	camera.h_offset = lerpf(TITLE_CAMERA.h_offset, 0.0, eased)
	camera.look_at_from_position(position, target, Vector3.UP)
	title_spread = focus < 0.5
	casebook_spread = opened > 0.99

func _update_watch() -> void:
	var now := Time.get_time_dict_from_system()
	var seconds := float(now.second)
	var minutes := float(now.minute) + seconds / 60.0
	var hours := fmod(float(now.hour), 12.0) + minutes / 60.0
	_watch_hands[0].rotation.y = -hours / 12.0 * TAU
	_watch_hands[1].rotation.y = -minutes / 60.0 * TAU
	_watch_hands[2].rotation.y = -seconds / 60.0 * TAU

## 火山不定期喷发闪光：映亮天空、海面和透过窗户落在桌上的红光。
func _update_eruption(delta: float) -> void:
	if _time >= _next_flash:
		_next_flash = _time + randf_range(6.0, 15.0)
		if flash_enabled: _flash = 1.0
	_flash = maxf(0.0, _flash - delta * 0.7)
	var glow := _flash * _flash
	var pulse := 0.85 + 0.15 * sin(_time * 0.83)
	_sky_material.set_shader_parameter("flash", glow * 0.6)
	_sea_material.set_shader_parameter("flash", glow * 0.5)
	_crater_material.emission_energy_multiplier = 5.0 * pulse + glow * 8.0
	_window_light.light_energy = 0.15 * pulse + glow * 0.65
	_embers.amount_ratio = 0.45 + glow * 0.55

func _set_opened(value: float) -> void:
	opened = clampf(value, 0.0, 1.0)
	if _hinge == null: return
	_hinge.rotation.z = opened * PI
	_spine.scale.y = maxf(0.02, 1.0 - opened)
	_spread.visible = opened > 0.995
	_update_book_pose()

func _set_ink(value: float) -> void:
	ink = clampf(value, 0.0, 1.0)
	if _spread_material != null: _spread_material.set_shader_parameter("page_fade", ink)

func _set_leaf_progress(value: float) -> void:
	_leaf.set_progress(value)
	turn_lift = sin(value * PI)

func _restart_sequence() -> void:
	if _sequence != null: _sequence.kill()
	_sequence = create_tween()

func _on_setting_changed(section: String, key: String, value: Variant) -> void:
	if section != "accessibility": return
	if key == "reduce_motion": reduce_motion = bool(value)
	elif key == "screen_flash": flash_enabled = bool(value)

# ================================================================== build ===

func _build_environment() -> void:
	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color(0.012, 0.014, 0.02)
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color(0.11, 0.14, 0.21)
	environment.ambient_light_energy = 0.30
	environment.tonemap_mode = Environment.TONE_MAPPER_ACES
	environment.tonemap_exposure = 0.95
	environment.glow_enabled = true
	environment.glow_intensity = 0.75
	environment.glow_bloom = 0.04
	environment.glow_hdr_threshold = 1.1
	environment.ssao_enabled = true
	environment.ssao_radius = 0.25
	environment.ssao_intensity = 1.4
	camera = Camera3D.new()
	camera.name = "StageCamera"
	camera.near = 0.02
	camera.far = 400.0
	camera.environment = environment
	add_child(camera)
	add_to_group("book_camera_stages")

func _build_room() -> void:
	var plaster := _mat(Color(0.11, 0.13, 0.14), 0.95)
	var panel := _mat(Color(0.17, 0.10, 0.07), 0.7)
	var frame := _mat(Color(0.23, 0.14, 0.09), 0.6)
	var room := _node("Room", self)
	# 后墙在窗洞四周围合；窗洞 x ∈ [-0.85, 0.85]，y ∈ [0.18, 1.55]。
	_box(room, Vector3(1.65, 3.6, 0.12), Vector3(-1.675, 0.8, -0.68), plaster)
	_box(room, Vector3(1.65, 3.6, 0.12), Vector3(1.675, 0.8, -0.68), plaster)
	_box(room, Vector3(1.7, 1.05, 0.12), Vector3(0.0, 2.075, -0.68), plaster)
	_box(room, Vector3(1.7, 1.2, 0.12), Vector3(0.0, -0.42, -0.68), panel)
	_box(room, Vector3(5.0, 0.9, 0.03), Vector3(0.0, -0.40, -0.605), panel)
	_box(room, Vector3(5.0, 0.04, 0.05), Vector3(0.0, 0.06, -0.60), frame)
	# 窗框、中梃与窗台。
	_box(room, Vector3(1.84, 0.07, 0.14), Vector3(0.0, 1.585, -0.66), frame)
	_box(room, Vector3(0.07, 1.44, 0.14), Vector3(-0.885, 0.865, -0.66), frame)
	_box(room, Vector3(0.07, 1.44, 0.14), Vector3(0.885, 0.865, -0.66), frame)
	_box(room, Vector3(0.04, 1.37, 0.06), Vector3(0.0, 0.865, -0.68), frame)
	_box(room, Vector3(1.7, 0.04, 0.06), Vector3(0.0, 1.10, -0.68), frame)
	for x in [-0.425, 0.425]:
		_box(room, Vector3(0.022, 0.45, 0.04), Vector3(x, 1.325, -0.69), frame)
	_box(room, Vector3(1.96, 0.05, 0.22), Vector3(0.0, 0.155, -0.60), frame)
	var glass := ShaderMaterial.new()
	glass.shader = GLASS_SHADER
	var pane := QuadMesh.new()
	pane.size = Vector2(1.7, 1.37)
	_mesh(room, pane, Vector3(0.0, 0.865, -0.70), glass, Vector3.ZERO, false)
	# 窗帘与帘杆。
	var rod := _mat(Color(0.62, 0.46, 0.22), 0.35, 0.85)
	_cylinder(room, 0.012, 0.012, 2.9, Vector3(0.0, 1.78, -0.56), rod, 10, Vector3(0.0, 0.0, PI * 0.5))
	for side in [-1.0, 1.0]:
		var cloth := ShaderMaterial.new()
		cloth.shader = CURTAIN_SHADER
		var curtain := QuadMesh.new()
		curtain.size = Vector2(0.62, 2.05)
		curtain.subdivide_width = 48
		curtain.subdivide_depth = 24
		var node := _mesh(room, curtain, Vector3(side * 1.08, 0.76, -0.55), cloth)
		cloth.set_shader_parameter("fold_frequency", 44.0 + side * 3.0)
		_curtains.append(cloth)
		node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	# 透过窗户映入的火山红光，投下窗棂阴影。
	_window_light = SpotLight3D.new()
	_window_light.light_color = Color(1.0, 0.50, 0.30)
	_window_light.spot_range = 5.0
	_window_light.spot_angle = 28.0
	_window_light.shadow_enabled = true
	add_child(_window_light)
	_window_light.look_at_from_position(Vector3(-0.55, 1.45, -1.9), Vector3(0.05, 0.0, 0.1), Vector3.UP)
	var fill := OmniLight3D.new()
	fill.light_color = Color(0.36, 0.42, 0.62)
	fill.light_energy = 0.18
	fill.omni_range = 4.0
	fill.position = Vector3(0.9, 1.3, 1.5)
	add_child(fill)

func _build_outside() -> void:
	var outside := _node("Outside", self)
	_sky_material = ShaderMaterial.new()
	_sky_material.shader = SKY_SHADER
	_sky_material.set_shader_parameter("volcano_uv", Vector2(0.42, 0.585))
	var sky := QuadMesh.new()
	sky.size = Vector2(500.0, 200.0)
	_mesh(outside, sky, Vector3(0.0, 26.0, -140.0), _sky_material, Vector3.ZERO, false)
	_sea_material = ShaderMaterial.new()
	_sea_material.shader = SEA_SHADER
	_sea_material.set_shader_parameter("volcano_world", VOLCANO + Vector3.UP * VOLCANO_HEIGHT)
	var sea := PlaneMesh.new()
	sea.size = Vector2(320.0, 132.0)
	sea.subdivide_width = 64
	sea.subdivide_depth = 30
	_mesh(outside, sea, Vector3(0.0, SEA_Y, -73.0), _sea_material, Vector3.ZERO, false)
	# 平顶火山、火口辉光与熔岩流。
	var rock := _mat(Color(0.05, 0.035, 0.035), 0.9)
	_cylinder(outside, 2.8, 24.0, VOLCANO_HEIGHT, VOLCANO + Vector3.UP * VOLCANO_HEIGHT * 0.5, rock, 9)
	_cylinder(outside, 9.0, 16.0, 4.0, VOLCANO + Vector3(13.0, 2.0, 6.0), rock, 7)
	_crater_material = _mat(Color(0.3, 0.06, 0.02), 1.0)
	_crater_material.emission_enabled = true
	_crater_material.emission = Color(1.0, 0.38, 0.1)
	_crater_material.emission_energy_multiplier = 5.0
	_cylinder(outside, 2.4, 2.8, 0.6, VOLCANO + Vector3.UP * (VOLCANO_HEIGHT + 0.05), _crater_material, 9)
	var lava := _mat(Color(0.25, 0.05, 0.02), 1.0)
	lava.emission_enabled = true
	lava.emission = Color(1.0, 0.30, 0.08)
	lava.emission_energy_multiplier = 1.6
	var slope := atan(VOLCANO_HEIGHT / (24.0 - 2.8))
	for angle in [-0.42, -0.05, 0.31]:
		var arm := _node("Lava", outside)
		arm.position = VOLCANO + Vector3.UP * VOLCANO_HEIGHT * 0.5
		arm.rotation.y = angle
		var radius := 7.5
		var height := VOLCANO_HEIGHT * 0.5 - (radius - 2.8) * tan(slope)
		_box(arm, Vector3(0.35, 0.08, 6.0 + angle * 3.0), Vector3(0.0, height + 0.15, radius + 0.4), lava, Vector3(slope, 0.0, 0.0))
	# 远处灯塔与旋转光柱。
	var island := _mat(Color(0.04, 0.035, 0.04), 0.9)
	var tower := _mat(Color(0.35, 0.33, 0.30), 0.8)
	tower.emission_enabled = true
	tower.emission = Color(0.25, 0.12, 0.10)
	var lamp := _mat(Color(1.0, 0.9, 0.7), 1.0)
	lamp.emission_enabled = true
	lamp.emission = Color(1.0, 0.86, 0.6)
	lamp.emission_energy_multiplier = 6.0
	var lighthouse := Vector3(42.0, SEA_Y, -72.0)
	_cylinder(outside, 2.0, 5.0, 3.0, lighthouse + Vector3.UP * 1.5, island, 7)
	_cylinder(outside, 0.55, 0.85, 6.5, lighthouse + Vector3.UP * 6.25, tower, 8)
	_cylinder(outside, 0.5, 0.5, 0.8, lighthouse + Vector3.UP * 9.9, lamp, 8)
	_beam_pivot = _node("Beam", outside)
	_beam_pivot.position = lighthouse + Vector3.UP * 9.9
	var beam_material := ShaderMaterial.new()
	beam_material.shader = BEAM_SHADER
	var beam := CylinderMesh.new()
	beam.top_radius = 0.3
	beam.bottom_radius = 4.5
	beam.height = 60.0
	beam.radial_segments = 12
	beam.rings = 1
	_mesh(_beam_pivot, beam, Vector3(0.0, 0.0, 30.0), beam_material, Vector3(-PI * 0.5, 0.0, 0.0), false)

func _build_desk() -> void:
	var walnut := _mat(Color(0.25, 0.14, 0.08), 0.5)
	var dark := _mat(Color(0.14, 0.08, 0.05), 0.6)
	var desk := _node("Desk", self)
	_mesh(desk, DETAIL.beveled_box(Vector3(2.3, 0.05, 1.12), 0.012, 2), Vector3(0.0, -0.025, -0.02), walnut)
	_box(desk, Vector3(2.24, 0.09, 0.03), Vector3(0.0, -0.095, 0.52), dark)
	var felt := _mat(Color(0.12, 0.20, 0.15), 0.95)
	_box(desk, Vector3(0.86, 0.004, 0.62), BOOK_ORIGIN - Vector3(0.0, 0.002, 0.0), felt, Vector3(0.0, BOOK_YAW, 0.0))

func _build_tools() -> void:
	var tools := _node("Tools", self)
	var brass := _mat(Color(0.66, 0.48, 0.22), 0.35, 0.9)
	var paper := _mat(Color(0.82, 0.77, 0.66), 0.95)
	var ink_black := _mat(Color(0.03, 0.03, 0.05), 0.3)
	var briar := _mat(Color(0.24, 0.11, 0.05), 0.45)
	var porcelain := _mat(Color(0.86, 0.84, 0.80), 0.25)
	var wax := _mat(Color(0.48, 0.06, 0.05), 0.5)
	# 黄铜煤油灯：底座、灯身、玻璃罩、火焰与暖光。
	var lamp := _node("OilLamp", tools)
	lamp.position = Vector3(-0.66, 0.0, -0.26)
	_cylinder(lamp, 0.06, 0.075, 0.022, Vector3(0.0, 0.011, 0.0), brass, 12)
	_cylinder(lamp, 0.012, 0.018, 0.12, Vector3(0.0, 0.08, 0.0), brass, 8)
	_cylinder(lamp, 0.05, 0.06, 0.07, Vector3(0.0, 0.17, 0.0), brass, 12)
	_cylinder(lamp, 0.032, 0.034, 0.02, Vector3(0.0, 0.215, 0.0), brass, 10)
	var chimney := ShaderMaterial.new()
	chimney.shader = GLASS_SHADER
	chimney.set_shader_parameter("edge_opacity", 0.22)
	_cylinder(lamp, 0.026, 0.038, 0.17, Vector3(0.0, 0.31, 0.0), chimney, 14, Vector3.ZERO, false)
	_flame_material = ShaderMaterial.new()
	_flame_material.shader = FLAME_SHADER
	var flame := CylinderMesh.new()
	flame.top_radius = 0.17
	flame.bottom_radius = 0.17
	flame.height = 1.15
	flame.radial_segments = 12
	flame.rings = 10
	var flame_node := _mesh(lamp, flame, Vector3(0.0, 0.258, 0.0), _flame_material, Vector3.ZERO, false)
	flame_node.scale = Vector3.ONE * 0.04
	_lamp_light = OmniLight3D.new()
	_lamp_light.light_color = Color(1.0, 0.66, 0.36)
	_lamp_light.omni_range = 2.8
	_lamp_light.omni_attenuation = 1.3
	_lamp_light.shadow_enabled = true
	_lamp_light.position = Vector3(0.0, 0.27, 0.0)
	lamp.add_child(_lamp_light)
	# 放大镜。
	var magnifier := _node("Magnifier", tools)
	magnifier.position = Vector3(0.47, 0.008, 0.20)
	magnifier.rotation = Vector3(0.05, 0.6, 0.0)
	var ring := TorusMesh.new()
	ring.inner_radius = 0.046
	ring.outer_radius = 0.056
	ring.rings = 18
	ring.ring_segments = 6
	_mesh(magnifier, _faceted(ring), Vector3.ZERO, brass)
	var lens := ShaderMaterial.new()
	lens.shader = GLASS_SHADER
	lens.set_shader_parameter("edge_opacity", 0.5)
	_cylinder(magnifier, 0.047, 0.047, 0.003, Vector3.ZERO, lens, 18, Vector3.ZERO, false)
	_cylinder(magnifier, 0.009, 0.007, 0.11, Vector3(0.11, 0.0, 0.0), briar, 8, Vector3(0.0, 0.0, PI * 0.5))
	_cylinder(magnifier, 0.011, 0.011, 0.012, Vector3(0.058, 0.0, 0.0), brass, 8, Vector3(0.0, 0.0, PI * 0.5))
	# 烟斗。
	var pipe := _node("Pipe", tools)
	pipe.position = Vector3(0.66, 0.0, -0.16)
	pipe.rotation.y = -0.5
	_cylinder(pipe, 0.019, 0.015, 0.042, Vector3(0.0, 0.021, 0.0), briar, 9)
	_cylinder(pipe, 0.013, 0.013, 0.002, Vector3(0.0, 0.0425, 0.0), ink_black, 9)
	_cylinder(pipe, 0.0045, 0.0055, 0.12, Vector3(0.07, 0.012, 0.0), briar, 6, Vector3(0.0, 0.0, PI * 0.5 - 0.08))
	_cylinder(pipe, 0.004, 0.0045, 0.03, Vector3(0.145, 0.018, 0.0), ink_black, 6, Vector3(0.0, 0.0, PI * 0.5 - 0.08))
	# 怀表：真实时刻驱动的指针，链条盘在桌面。
	var watch := _node("PocketWatch", tools)
	watch.position = Vector3(-0.43, 0.0, 0.24)
	watch.rotation.y = 0.3
	_cylinder(watch, 0.036, 0.038, 0.012, Vector3(0.0, 0.006, 0.0), brass, 16)
	var face := _mat(Color(0.92, 0.89, 0.80), 0.4)
	_cylinder(watch, 0.031, 0.031, 0.002, Vector3(0.0, 0.0125, 0.0), face, 16)
	var bow := TorusMesh.new()
	bow.inner_radius = 0.008
	bow.outer_radius = 0.0115
	bow.rings = 10
	bow.ring_segments = 4
	_mesh(watch, _faceted(bow), Vector3(0.0, 0.006, -0.048), brass)
	for hand in [[0.016, 0.0022], [0.024, 0.0016], [0.027, 0.0008]]:
		var pivot := _node("Hand", watch)
		pivot.position = Vector3(0.0, 0.0138 + _watch_hands.size() * 0.0004, 0.0)
		_box(pivot, Vector3(hand[1], 0.0004, hand[0]), Vector3(0.0, 0.0, -hand[0] * 0.4), ink_black if _watch_hands.size() < 2 else wax)
		_watch_hands.append(pivot)
	for link in 14:
		var t := float(link) / 13.0
		var point := Vector3(0.012 + sin(t * 3.4) * 0.07, 0.002, -0.055 - t * 0.09)
		_box(watch, Vector3(0.006, 0.003, 0.009), point, brass, Vector3(0.0, cos(t * 3.4), 0.0))
	# 墨水瓶与羽毛笔。
	var inkwell := _node("Inkwell", tools)
	inkwell.position = Vector3(0.40, 0.0, -0.32)
	var bottle := _mat(Color(0.06, 0.09, 0.16), 0.15)
	_cylinder(inkwell, 0.024, 0.034, 0.05, Vector3(0.0, 0.025, 0.0), bottle, 8)
	_cylinder(inkwell, 0.014, 0.014, 0.012, Vector3(0.0, 0.056, 0.0), brass, 8)
	var feather := _mat(Color(0.85, 0.83, 0.78), 0.9)
	var quill := _cylinder(inkwell, 0.0015, 0.016, 0.24, Vector3(0.035, 0.15, 0.025), feather, 6, Vector3(0.35, 0.0, -0.32))
	quill.scale = Vector3(1.0, 1.0, 0.18)
	# 信件、照片与封蜡。
	var letters := _node("Letters", tools)
	letters.position = Vector3(-0.40, 0.0, -0.26)
	for sheet in 4:
		_box(letters, Vector3(0.21, 0.0012, 0.28), Vector3(sheet * 0.012, 0.0006 + sheet * 0.0013, sheet * 0.006), paper, Vector3(0.0, 0.25 - sheet * 0.17, 0.0))
	var envelope := _mat(Color(0.74, 0.66, 0.52), 0.95)
	_box(letters, Vector3(0.17, 0.0016, 0.10), Vector3(0.05, 0.0065, 0.10), envelope, Vector3(0.0, -0.35, 0.0))
	_cylinder(letters, 0.012, 0.013, 0.003, Vector3(0.05, 0.0085, 0.10), wax, 9)
	var photo := _mat(Color(0.30, 0.24, 0.17), 0.6)
	_box(letters, Vector3(0.08, 0.0012, 0.105), Vector3(0.12, 0.0072, -0.06), _mat(Color(0.9, 0.87, 0.80), 0.8), Vector3(0.0, 0.5, 0.0))
	_box(letters, Vector3(0.068, 0.0012, 0.08), Vector3(0.12, 0.0080, -0.064), photo, Vector3(0.0, 0.5, 0.0))
	# 茶杯（蒸汽在粒子里）。
	var cup := _node("Teacup", tools)
	cup.position = Vector3(0.74, 0.0, 0.16)
	_cylinder(cup, 0.066, 0.06, 0.006, Vector3(0.0, 0.003, 0.0), porcelain, 14)
	_cylinder(cup, 0.042, 0.028, 0.052, Vector3(0.0, 0.032, 0.0), porcelain, 12)
	_cylinder(cup, 0.038, 0.038, 0.002, Vector3(0.0, 0.052, 0.0), _mat(Color(0.25, 0.12, 0.05), 0.15), 12)
	var handle := TorusMesh.new()
	handle.inner_radius = 0.010
	handle.outer_radius = 0.016
	handle.rings = 8
	handle.ring_segments = 4
	_mesh(cup, _faceted(handle), Vector3(0.045, 0.034, 0.0), porcelain, Vector3(PI * 0.5, 0.0, 0.0))
	# 卷起的岛图。
	_cylinder(tools, 0.018, 0.018, 0.32, Vector3(0.12, 0.018, -0.42), _mat(Color(0.70, 0.62, 0.46), 0.9), 8, Vector3(0.0, 0.2, PI * 0.5))

func _build_book() -> void:
	_book = _node("Casebook", self)
	var leather := _mat(Color(0.10, 0.20, 0.15), 0.62)
	leather.emission_enabled = true
	leather.emission = Color(0.85, 0.62, 0.25)
	leather.emission_energy_multiplier = 0.0
	_cover_material = leather
	var gold := _mat(Color(0.74, 0.56, 0.24), 0.32, 0.9)
	var pages := _mat(Color(0.86, 0.80, 0.66), 0.9)
	var board := Vector3(PAGE_SIZE.x + 0.012, COVER, PAGE_SIZE.y + 0.02)
	var block := Vector3(PAGE_SIZE.x - 0.004, STACK, PAGE_SIZE.y - 0.006)
	var pivot_y := COVER + STACK
	# 右侧：封底与书页块固定。
	_mesh(_book, DETAIL.beveled_box(board, 0.002, 1), Vector3(board.x * 0.5, COVER * 0.5, 0.0), leather)
	_box(_book, block, Vector3(block.x * 0.5, COVER + STACK * 0.5, 0.0), pages)
	# 左侧：封面连同前半书页块绕书脊翻开；合上时盖在右侧书页上。
	_hinge = _node("CoverHinge", _book)
	_hinge.position = Vector3(0.0, pivot_y, 0.0)
	_box(_hinge, block, Vector3(block.x * 0.5, STACK * 0.5, 0.0), pages)
	_mesh(_hinge, DETAIL.beveled_box(board, 0.002, 1), Vector3(board.x * 0.5, STACK + COVER * 0.5, 0.0), leather)
	var face_y := STACK + COVER + 0.0006
	var inset := Vector2(board.x - 0.04, board.z - 0.04)
	for edge in [[Vector3(inset.x, 0.001, 0.004), Vector3(board.x * 0.5, face_y, -inset.y * 0.5)],
			[Vector3(inset.x, 0.001, 0.004), Vector3(board.x * 0.5, face_y, inset.y * 0.5)],
			[Vector3(0.004, 0.001, inset.y), Vector3(0.02, face_y, 0.0)],
			[Vector3(0.004, 0.001, inset.y), Vector3(board.x - 0.02, face_y, 0.0)]]:
		_box(_hinge, edge[0], edge[1], gold)
	for corner in [-1.0, 1.0]:
		_box(_hinge, Vector3(0.024, COVER + 0.001, 0.024), Vector3(board.x - 0.011, STACK + COVER * 0.5, corner * (board.z * 0.5 - 0.011)), gold)
		_box(_book, Vector3(0.024, COVER + 0.001, 0.024), Vector3(board.x - 0.011, COVER * 0.5, corner * (board.z * 0.5 - 0.011)), gold)
	var title := Label3D.new()
	title.text = "案 卷"
	title.font = COVER_FONT
	title.font_size = 96
	title.pixel_size = 0.0005
	title.modulate = Color(0.86, 0.68, 0.34)
	title.outline_size = 0
	title.shaded = true
	title.double_sided = false
	title.position = Vector3(board.x * 0.5, face_y + 0.0004, 0.07)
	title.rotation = Vector3(-PI * 0.5, 0.0, 0.0)
	_hinge.add_child(title)
	_spine = _box(_book, Vector3(0.010, 2.0 * pivot_y, board.z), Vector3(-0.004, pivot_y, 0.0), leather)
	# 红色丝带书签从书页底部垂出。
	_box(_book, Vector3(0.009, 0.0008, 0.07), Vector3(0.006, pivot_y + 0.002, PAGE_SIZE.y * 0.5 + 0.012), _mat(Color(0.55, 0.06, 0.06), 0.6))
	# 对开页：显示 BookUI 渲染的界面。
	_spread_material = ShaderMaterial.new()
	_spread_material.shader = SPREAD_SHADER
	_spread_material.set_shader_parameter("paper_color", PAPER)
	var plane := PlaneMesh.new()
	plane.size = Vector2(PAGE_SIZE.x * 2.0, PAGE_SIZE.y)
	_spread = _mesh(_book, plane, Vector3(0.0, pivot_y + 0.0012, 0.0), _spread_material, Vector3.ZERO, false)
	_leaf = LEAF_SCENE.instantiate()
	_leaf.position = Vector3(0.0, pivot_y + 0.0028, 0.0)
	_leaf.visible = false
	_book.add_child(_leaf)

func _build_particles() -> void:
	var soft := GradientTexture2D.new()
	soft.fill = GradientTexture2D.FILL_RADIAL
	soft.fill_from = Vector2(0.5, 0.5)
	soft.fill_to = Vector2(1.0, 0.5)
	var fade := Gradient.new()
	fade.set_color(0, Color(1, 1, 1, 1))
	fade.set_color(1, Color(1, 1, 1, 0))
	soft.gradient = fade
	# 火口迸出的火星。
	var ember_ramp := Gradient.new()
	ember_ramp.set_color(0, Color(1.0, 0.85, 0.45, 1.0))
	ember_ramp.add_point(0.4, Color(1.0, 0.35, 0.08, 0.9))
	ember_ramp.set_color(ember_ramp.get_point_count() - 1, Color(0.3, 0.03, 0.02, 0.0))
	_embers = _particles("Embers", VOLCANO + Vector3.UP * (VOLCANO_HEIGHT + 0.5), 140, 3.2, 0.45, soft, true)
	var ember_process: ParticleProcessMaterial = _embers.process_material
	ember_process.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	ember_process.emission_sphere_radius = 1.6
	ember_process.direction = Vector3.UP
	ember_process.spread = 28.0
	ember_process.initial_velocity_min = 5.0
	ember_process.initial_velocity_max = 11.0
	ember_process.gravity = Vector3(0.6, -5.0, 0.0)
	ember_process.scale_min = 0.5
	ember_process.scale_max = 1.0
	ember_process.color_ramp = _ramp_texture(ember_ramp)
	_embers.visibility_aabb = AABB(Vector3(-25, -5, -25), Vector3(50, 40, 50))
	# 火山烟柱，被火口从下方映红。
	var smoke_ramp := Gradient.new()
	smoke_ramp.set_color(0, Color(0.45, 0.12, 0.06, 0.0))
	smoke_ramp.add_point(0.15, Color(0.30, 0.08, 0.06, 0.55))
	smoke_ramp.set_color(smoke_ramp.get_point_count() - 1, Color(0.05, 0.03, 0.04, 0.0))
	var smoke := _particles("Smoke", VOLCANO + Vector3.UP * (VOLCANO_HEIGHT + 1.0), 46, 16.0, 7.0, soft, false)
	var smoke_process: ParticleProcessMaterial = smoke.process_material
	smoke_process.direction = Vector3.UP
	smoke_process.spread = 12.0
	smoke_process.initial_velocity_min = 1.6
	smoke_process.initial_velocity_max = 2.6
	smoke_process.gravity = Vector3(0.35, 0.12, 0.0)
	smoke_process.scale_min = 0.6
	smoke_process.scale_max = 1.2
	smoke_process.scale_curve = _curve_texture([Vector2(0.0, 0.4), Vector2(1.0, 2.6)])
	smoke_process.color_ramp = _ramp_texture(smoke_ramp)
	smoke.visibility_aabb = AABB(Vector3(-40, -5, -40), Vector3(80, 70, 80))
	smoke.preprocess = 16.0
	# 茶杯蒸汽。
	var steam_ramp := Gradient.new()
	steam_ramp.set_color(0, Color(1, 1, 1, 0.0))
	steam_ramp.add_point(0.25, Color(1, 0.95, 0.9, 0.16))
	steam_ramp.set_color(steam_ramp.get_point_count() - 1, Color(1, 1, 1, 0.0))
	var steam := _particles("Steam", Vector3(0.74, 0.058, 0.16), 22, 2.8, 0.035, soft, false)
	var steam_process: ParticleProcessMaterial = steam.process_material
	steam_process.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	steam_process.emission_sphere_radius = 0.015
	steam_process.direction = Vector3.UP
	steam_process.spread = 10.0
	steam_process.initial_velocity_min = 0.025
	steam_process.initial_velocity_max = 0.045
	steam_process.gravity = Vector3(0.0, 0.012, 0.0)
	steam_process.turbulence_enabled = true
	steam_process.turbulence_noise_strength = 0.4
	steam_process.turbulence_noise_scale = 1.2
	steam_process.scale_curve = _curve_texture([Vector2(0.0, 0.5), Vector2(1.0, 2.2)])
	steam_process.color_ramp = _ramp_texture(steam_ramp)
	steam.preprocess = 3.0
	# 灯光中缓缓浮动的尘埃。
	var dust_ramp := Gradient.new()
	dust_ramp.set_color(0, Color(1.0, 0.85, 0.6, 0.0))
	dust_ramp.add_point(0.5, Color(1.0, 0.85, 0.6, 0.55))
	dust_ramp.set_color(dust_ramp.get_point_count() - 1, Color(1.0, 0.85, 0.6, 0.0))
	var dust := _particles("Dust", Vector3(-0.25, 0.42, -0.1), 70, 9.0, 0.0035, soft, true)
	var dust_process: ParticleProcessMaterial = dust.process_material
	dust_process.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	dust_process.emission_box_extents = Vector3(0.75, 0.35, 0.45)
	dust_process.spread = 180.0
	dust_process.initial_velocity_min = 0.004
	dust_process.initial_velocity_max = 0.016
	dust_process.gravity = Vector3(0.0, 0.0015, 0.0)
	dust_process.turbulence_enabled = true
	dust_process.turbulence_noise_strength = 0.2
	dust_process.color_ramp = _ramp_texture(dust_ramp)
	dust.preprocess = 9.0

# ================================================================= helpers ===

func _particles(label: String, position: Vector3, amount: int, lifetime: float, size: float, texture: Texture2D, additive: bool) -> GPUParticles3D:
	var particles := GPUParticles3D.new()
	particles.name = label
	particles.position = position
	particles.amount = amount
	particles.lifetime = lifetime
	particles.process_material = ParticleProcessMaterial.new()
	var quad := QuadMesh.new()
	quad.size = Vector2.ONE * size
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.blend_mode = BaseMaterial3D.BLEND_MODE_ADD if additive else BaseMaterial3D.BLEND_MODE_MIX
	material.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	material.vertex_color_use_as_albedo = true
	material.albedo_texture = texture
	material.disable_receive_shadows = true
	quad.material = material
	particles.draw_pass_1 = quad
	particles.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(particles)
	return particles

static func _ramp_texture(gradient: Gradient) -> GradientTexture1D:
	var texture := GradientTexture1D.new()
	texture.gradient = gradient
	return texture

static func _curve_texture(points: Array) -> CurveTexture:
	var curve := Curve.new()
	curve.max_value = 3.0
	for point: Vector2 in points: curve.add_point(point)
	var texture := CurveTexture.new()
	texture.curve = curve
	return texture

func _node(label: String, parent: Node) -> Node3D:
	var node := Node3D.new()
	node.name = label
	parent.add_child(node)
	return node

func _mat(color: Color, roughness := 0.8, metallic := 0.0) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = roughness
	material.metallic = metallic
	return material

func _mesh(parent: Node3D, mesh: Mesh, position: Vector3, material: Material, rotation := Vector3.ZERO, shadow := true) -> MeshInstance3D:
	var node := MeshInstance3D.new()
	node.mesh = mesh
	node.position = position
	node.rotation = rotation
	node.material_override = material
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if shadow else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(node)
	return node

func _box(parent: Node3D, size: Vector3, position: Vector3, material: Material, rotation := Vector3.ZERO) -> MeshInstance3D:
	var mesh := BoxMesh.new()
	mesh.size = size
	return _mesh(parent, mesh, position, material, rotation)

func _cylinder(parent: Node3D, top: float, bottom: float, height: float, position: Vector3, material: Material, segments := 10, rotation := Vector3.ZERO, shadow := true) -> MeshInstance3D:
	var mesh := CylinderMesh.new()
	mesh.top_radius = top
	mesh.bottom_radius = bottom
	mesh.height = height
	mesh.radial_segments = segments
	mesh.rings = 1
	return _mesh(parent, _faceted(mesh), position, material, rotation, shadow)

## 低模分面：每个三角形使用自己的面法线。
static func _faceted(source: PrimitiveMesh) -> ArrayMesh:
	var arrays := source.get_mesh_arrays()
	var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
	var uvs: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV]
	var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
	var out_vertices := PackedVector3Array()
	var out_normals := PackedVector3Array()
	var out_uvs := PackedVector2Array()
	for i in range(0, indices.size(), 3):
		var a := vertices[indices[i]]
		var b := vertices[indices[i + 1]]
		var c := vertices[indices[i + 2]]
		var normal := (b - a).cross(c - a)
		if normal.length_squared() < 1e-14: continue
		normal = normal.normalized()
		if normal.dot(normals[indices[i]] + normals[indices[i + 1]] + normals[indices[i + 2]]) < 0.0: normal = -normal
		for corner in 3:
			out_vertices.append(vertices[indices[i + corner]])
			out_normals.append(normal)
			out_uvs.append(uvs[indices[i + corner]] if uvs.size() > 0 else Vector2.ZERO)
	var result_arrays: Array = []
	result_arrays.resize(Mesh.ARRAY_MAX)
	result_arrays[Mesh.ARRAY_VERTEX] = out_vertices
	result_arrays[Mesh.ARRAY_NORMAL] = out_normals
	result_arrays[Mesh.ARRAY_TEX_UV] = out_uvs
	var result := ArrayMesh.new()
	result.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, result_arrays)
	return result
