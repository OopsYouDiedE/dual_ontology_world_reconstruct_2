extends Node3D
class_name AcademyLevelBase
## Non-bypassable Base Class for ALL future levels in The Sleeping Academy (Godot 4.7.2).
##
## How to build a new level (zero boilerplate, impossible to bypass unified systems):
##   1. `extends AcademyLevelBase`
##   2. Override `define_level_manifest() -> Dictionary` declaring:
##        - level_id, title, capabilities (AcademyLevelPipeline.capabilities_*())
##        - objects[]        -> auto-spawned via AcademyFurnitureCatalog (unified PBR materials)
##        - interactables[]  -> auto-wired to DualModeInteractionHud (C+ / Detroit 3-state)
##        - dialogues[]      -> auto-audited against Epistemic Firewall, played via UnifiedDialoguePresenter
##        - triggers[]       -> declarative trigger registry (E / proximity / zone / rule)
##        - ai_routes[]      -> autonomous teammate/NPC patrol & telegraph routes + 3D debug gizmos
##   3. Override `_on_level_action(action_id: String, ctx: Dictionary)` for level-specific effects.
##   4. Press F2 at runtime to toggle the live Visual Design Blueprint Overlay + 3D AI Route Gizmos.

const LevelPipeline := preload("res://scenes/components/shared/AcademyLevelPipeline.gd")
const FurnitureCatalog := preload("res://scenes/components/shared/AcademyFurnitureCatalog.gd")
const LevelAudit := preload("res://scenes/components/shared/AcademyLevelAudit.gd")
const UiStyle := preload("res://scenes/components/shared/UiTheme.gd")
const R18n := preload("res://scenes/components/shared/R18n.gd")

var level_manifest: Dictionary = {}
var audit_report: Dictionary = {}
var level_capabilities: Dictionary = {}
var spawned_objects: Dictionary = {}   # object_id -> Node3D
var unlocked_flags: Dictionary = {}    # flag_name -> bool

var ui_layer: CanvasLayer
var dual_ui
var dialogue_presenter
var teammate_wheel

var _objects_root: Node3D
var _gizmo_root: Node3D
var _inspector_panel: PanelContainer
var _inspector_text: RichTextLabel
var _inspector_visible := false

## Subclasses MUST override this method to declare their entire level design.
func define_level_manifest() -> Dictionary:
	return {}

## Subclasses override this to respond when any declared interactable/trigger fires.
func _on_level_action(_action_id: String, _ctx: Dictionary) -> void:
	pass

## Subclasses override this to provide the active Camera3D and player world position.
func get_level_camera() -> Camera3D:
	return get_viewport().get_camera_3d()

func get_player_position() -> Vector3:
	var cam := get_level_camera()
	return cam.global_position if is_instance_valid(cam) else Vector3.ZERO

## Subclasses may override to customize Q teammate wheel options.
func get_teammate_wheel_options() -> Array:
	return [
		{"id": "advise", "title": R18n.pick("听取队友观察", "Ask Partner"), "hint": R18n.pick("询问队友当前房间的异常观察", "Ask your partner what they notice")},
		{"id": "toggle_blueprint", "title": R18n.pick("开关设计检视 [F2]", "Toggle Blueprint [F2]"), "hint": R18n.pick("查看本关物体、交互、台词与 AI 路线", "Inspect objects, triggers, lines & AI routes")},
	]

func _ready() -> void:
	level_manifest = define_level_manifest()
	audit_report = LevelAudit.validate_manifest(level_manifest)
	if not audit_report.ok:
		push_error("AcademyLevelBase manifest audit FAILED for '%s': %s" % [
			str(level_manifest.get("level_id", name)), str(audit_report.errors)
		])
		assert(false, "AcademyLevelBase manifest audit FAILED")
	level_capabilities = level_manifest.get("capabilities", LevelPipeline.capabilities_expedition())

	# 1. Unified rendering viewport contract
	var world_env := find_child("WorldEnvironment", true, false) as WorldEnvironment
	if world_env == null:
		world_env = WorldEnvironment.new()
		world_env.name = "WorldEnvironment"
		add_child(world_env)
	LevelPipeline.bootstrap_viewport(get_viewport(), world_env, level_capabilities)

	# 2. Unified UI stack (DualModeInteractionHud + UnifiedDialoguePresenter + UnifiedTeammateWheel)
	ui_layer = CanvasLayer.new()
	ui_layer.name = "UnifiedLevelUiLayer"
	ui_layer.layer = 10
	add_child(ui_layer)
	var stack := LevelPipeline.bootstrap_ui_stack(self, ui_layer, level_capabilities, 18.0, -72.0)
	dual_ui = stack.dual_ui
	dialogue_presenter = stack.dialogue
	teammate_wheel = stack.teammate_wheel
	if is_instance_valid(teammate_wheel):
		teammate_wheel.order_selected.connect(func(order_id: String):
			if order_id == "toggle_blueprint":
				set_blueprint_inspector_visible(not _inspector_visible)
			else:
				_on_level_action("wheel_" + order_id, {"order_id": order_id})
		)

	# 3. Auto-spawn all declared objects via unified AcademyFurnitureCatalog
	_objects_root = Node3D.new()
	_objects_root.name = "ManifestObjects"
	add_child(_objects_root)
	_spawn_manifest_objects()

	# 4. Build live 3D AI Route & Trigger Gizmos + F2 Visual Design Inspector
	_gizmo_root = Node3D.new()
	_gizmo_root.name = "ManifestDebugGizmos"
	_gizmo_root.visible = false
	add_child(_gizmo_root)
	_build_3d_route_gizmos()
	_build_blueprint_inspector()

	_on_level_ready()

## Optional hook for subclasses after unified bootstrap completes.
func _on_level_ready() -> void:
	pass

func _spawn_manifest_objects() -> void:
	for obj in level_manifest.get("objects", []):
		var oid := str(obj.get("id", ""))
		var kind := str(obj.get("kind", "glb"))
		var cid := str(obj.get("catalog_id", ""))
		var pos: Vector3 = obj.get("pos", Vector3.ZERO)
		var yaw := float(obj.get("yaw", 0.0))
		var preset := str(obj.get("material_preset", ""))
		var node: Node3D = null
		if kind == "glb":
			var sc := float(obj.get("scale", 1.0))
			node = FurnitureCatalog.spawn_glb(_objects_root, cid, pos, yaw, sc, preset)
		elif kind == "recipe":
			var params: Dictionary = obj.get("params", {})
			node = FurnitureCatalog.spawn_recipe(_objects_root, cid, pos, yaw, params, preset)
		if node != null:
			node.name = oid
			spawned_objects[oid] = node

func play_dialogue(dialogue_id: String) -> bool:
	for dlg in level_manifest.get("dialogues", []):
		if str(dlg.get("id", "")) == dialogue_id:
			var speaker := str(dlg.get("speaker", ""))
			var text := R18n.pick(str(dlg.get("text_zh", "")), str(dlg.get("text_en", "")))
			var vprof := str(dlg.get("voice_profile", "resident"))
			if is_instance_valid(dialogue_presenter):
				if speaker.is_empty():
					dialogue_presenter.thought(dialogue_id, text)
				else:
					dialogue_presenter.say(dialogue_id, speaker, text, vprof)
				return true
	return false

func _build_live_interaction_groups() -> Array[Dictionary]:
	var groups: Array[Dictionary] = []
	for grp in level_manifest.get("interactables", []):
		var active_hs: Array[Dictionary] = []
		for h in grp.get("hotspots", []):
			var req := str(h.get("unlock_when", ""))
			if not req.is_empty() and not bool(unlocked_flags.get(req, false)):
				continue
			var action_id := str(h.get("action_id", ""))
			var dlg_id := str(h.get("dialogue_id", ""))
			var h_copy: Dictionary = h.duplicate(true)
			h_copy["callback"] = func():
				if not dlg_id.is_empty():
					play_dialogue(dlg_id)
				_on_level_action(action_id, {"group_id": str(grp.get("id", "")), "hotspot_id": str(h.get("id", ""))})
			active_hs.append(h_copy)
		if not active_hs.is_empty():
			var g_copy: Dictionary = grp.duplicate(true)
			g_copy["hotspots"] = active_hs
			groups.append(g_copy)
	return groups

func _process(_dt: float) -> void:
	if is_instance_valid(dual_ui):
		var cam := get_level_camera()
		var vp_rect := get_viewport().get_visible_rect()
		var can_show: bool = not (is_instance_valid(teammate_wheel) and teammate_wheel.is_open())
		dual_ui.sync_groups(cam, vp_rect, vp_rect.size, get_player_position(), _build_live_interaction_groups(), can_show)

func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if (event as InputEventKey).physical_keycode == KEY_F2:
			set_blueprint_inspector_visible(not _inspector_visible)
			get_viewport().set_input_as_handled()
			return
	if is_instance_valid(teammate_wheel) and bool(level_capabilities.get("allow_command_wheel", true)):
		if teammate_wheel.handle_input(event, get_teammate_wheel_options):
			get_viewport().set_input_as_handled()
			return
	if is_instance_valid(dual_ui):
		if dual_ui.handle_input(event, true):
			get_viewport().set_input_as_handled()

func set_blueprint_inspector_visible(visible_flag: bool) -> void:
	_inspector_visible = visible_flag
	if is_instance_valid(_gizmo_root):
		_gizmo_root.visible = _inspector_visible
	if is_instance_valid(_inspector_panel):
		_inspector_panel.visible = _inspector_visible

func _build_3d_route_gizmos() -> void:
	# Render 3D AI route segments + waypoint spheres + 3D floating action tags
	var route_mat := StandardMaterial3D.new()
	route_mat.albedo_color = Color("5ec8e8")
	route_mat.emission_enabled = true
	route_mat.emission = Color("5ec8e8")
	route_mat.emission_energy_multiplier = 1.4

	var warn_mat := StandardMaterial3D.new()
	warn_mat.albedo_color = Color("f08a4b")
	warn_mat.emission_enabled = true
	warn_mat.emission = Color("f08a4b")
	warn_mat.emission_energy_multiplier = 1.8

	for route in level_manifest.get("ai_routes", []):
		var wps: Array = route.get("waypoints", [])
		var im := ImmediateMesh.new()
		if wps.size() >= 2:
			im.surface_begin(Mesh.PRIMITIVE_LINE_STRIP, route_mat)
			for wp in wps:
				var p: Vector3 = wp.get("pos", Vector3.ZERO) + Vector3.UP * 0.25
				im.surface_add_vertex(p)
			im.surface_end()
			var line_mi := MeshInstance3D.new()
			line_mi.mesh = im
			_gizmo_root.add_child(line_mi)
		for wi in wps.size():
			var wp: Dictionary = wps[wi]
			var p: Vector3 = wp.get("pos", Vector3.ZERO) + Vector3.UP * 0.25
			var sph := MeshInstance3D.new()
			var sm := SphereMesh.new(); sm.radius = 0.14; sm.height = 0.28
			sph.mesh = sm
			sph.material_override = warn_mat if bool(wp.get("is_rule_mistake", false)) else route_mat
			sph.position = p
			_gizmo_root.add_child(sph)
			var tag := Label3D.new()
			tag.billboard = BaseMaterial3D.BILLBOARD_ENABLED
			tag.pixel_size = 0.0028
			tag.position = p + Vector3.UP * 0.35
			tag.modulate = Color("ffd38a") if bool(wp.get("is_rule_mistake", false)) else Color("a8e6ff")
			tag.text = "#%d %s · %s" % [wi + 1, str(route.get("actor_name", "")), str(wp.get("action", ""))]
			_gizmo_root.add_child(tag)

func _build_blueprint_inspector() -> void:
	var font := UiStyle.make_font()
	_inspector_panel = PanelContainer.new()
	_inspector_panel.name = "LevelBlueprintInspector"
	_inspector_panel.set_anchors_and_offsets_preset(Control.PRESET_LEFT_WIDE)
	_inspector_panel.offset_left = 18.0
	_inspector_panel.offset_top = 18.0
	_inspector_panel.offset_bottom = -18.0
	_inspector_panel.offset_right = 510.0
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.05, 0.062, 0.088, 0.92)
	sb.border_color = Color("cfa04c")
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(4)
	sb.content_margin_left = 16; sb.content_margin_right = 16
	sb.content_margin_top = 14; sb.content_margin_bottom = 14
	_inspector_panel.add_theme_stylebox_override("panel", sb)
	ui_layer.add_child(_inspector_panel)

	_inspector_text = RichTextLabel.new()
	_inspector_text.bbcode_enabled = true
	_inspector_text.fit_content = false
	_inspector_text.add_theme_font_override("normal_font", font)
	_inspector_text.add_theme_font_size_override("normal_font_size", 13)
	_inspector_text.add_theme_color_override("default_color", Color("e9e5dc"))
	_inspector_panel.add_child(_inspector_text)
	_inspector_text.text = _format_inspector_bbcode()
	_inspector_panel.visible = false

func _format_inspector_bbcode() -> String:
	var b: PackedStringArray = []
	b.append("[color=#f0d394][b]关卡设计蓝图检视器 [F2][/b][/color]  ·  %s (`%s`)" % [str(level_manifest.get("title", "")), str(level_manifest.get("level_id", ""))])
	b.append("[color=#7ce0a3]✓ 认知防火墙 & 家具库 & AI 前摇校验：PASS[/color]" if bool(audit_report.get("ok", false)) else "[color=#ff6b6b]✗ 校验失败：%s[/color]" % str(audit_report.get("errors", [])))
	b.append("能力开关：跳=%s  灯=%s  跺=%s  轮盘=%s" % [
		str(level_capabilities.get("allow_jump", false)),
		str(level_capabilities.get("allow_lamp", false)),
		str(level_capabilities.get("allow_stomp", false)),
		str(level_capabilities.get("allow_command_wheel", true)),
	])
	b.append("\n[color=#f0d394][b]1. 场景物体 (%d)[/b][/color]" % level_manifest.get("objects", []).size())
	for obj in level_manifest.get("objects", []):
		var p: Vector3 = obj.get("pos", Vector3.ZERO)
		b.append("  • %s  [%s:%s]  @(%.1f, %.1f, %.1f)" % [str(obj.id), str(obj.kind), str(obj.catalog_id), p.x, p.y, p.z])
	b.append("\n[color=#f0d394][b]2. 可交互点 (%d 组)[/b][/color]" % level_manifest.get("interactables", []).size())
	for grp in level_manifest.get("interactables", []):
		for h in grp.get("hotspots", []):
			b.append("  • %s / %s → [E] %s  (条件:%s)" % [str(grp.title), str(h.part_name), str(h.verb), str(h.get("unlock_when", "默认"))])
	b.append("\n[color=#f0d394][b]3. 触发方式 (%d)[/b][/color]" % level_manifest.get("triggers", []).size())
	for trg in level_manifest.get("triggers", []):
		b.append("  • [%s] %s → %s" % [str(trg.how), str(trg.source_id), str(trg.get("effect", trg.get("dialogue_id", "-")))])
	b.append("\n[color=#f0d394][b]4. 台词清单 (%d)[/b][/color]" % level_manifest.get("dialogues", []).size())
	for dlg in level_manifest.get("dialogues", []):
		b.append("  • %s：%s" % [str(dlg.get("speaker", "独白")), str(dlg.get("text_zh", ""))])
	b.append("\n[color=#9bc4e6][b]5. AI 动作路线 (%d 条)[/b][/color]" % level_manifest.get("ai_routes", []).size())
	for route in level_manifest.get("ai_routes", []):
		b.append("  [b]%s[/b] (%s):" % [str(route.actor_name), str(route.get("role", "partner"))])
		var wps: Array = route.get("waypoints", [])
		for wi in wps.size():
			var wp: Dictionary = wps[wi]
			var p: Vector3 = wp.get("pos", Vector3.ZERO)
			var warn := " [color=#f08a4b][误踩前摇 %.1fs][/color]" % float(wp.get("foreshadow_sec", 0.0)) if bool(wp.get("is_rule_mistake", false)) else ""
			b.append("    %d) (%.1f,%.1f) %s [%s]%s" % [wi + 1, p.x, p.z, str(wp.action), str(wp.get("rule_tag", "-")), warn])
	return "\n".join(b)
