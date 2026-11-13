extends Control

const TITLE_UI_SCENE := preload("res://scenes/UIpanel/TitleUI/TitleUI.tscn")
const BOOK_UI_SCENE := preload("res://scenes/UIpanel/BookUI/BookUI.tscn")
const STUDY_STAGE_SCENE := preload("res://scenes/components/world/StudyDeskStage3D.tscn")
const Sound := preload("res://scenes/components/shared/Sound.gd")

const Space = preload("res://scenes/components/life/BuildingSpace.gd")
const Components = preload("res://tools/building_construction/BuildingConstruction/Shared/ComponentFactory.gd")
const Wall = preload("res://tools/building_construction/BuildingConstruction/Walls/WallPathGeometry.gd")
const Floor = preload("res://tools/building_construction/BuildingConstruction/Floors/ArchitectFloor.gd")
const Props = preload("res://tools/building_construction/BuildingConstruction/Props/ArchitectProps.gd")
const DEFAULT_CONTENT := "res://assets/data/scenarios/life_simulation.dv"
const CAMPAIGN_PANEL := preload("res://scenes/main/CampaignPanel.gd")
const DUAL_WORLD_SCENE := preload("res://scenes/dual_world/DualWorldMain.tscn")
const DUAL_WORLD_SAVES := ["user://dual_world/auto.json", "user://dual_world/save_1.json"]

var bridge: Node
var builder: Control
var life_ui: Control
var space: RefCounted
var rules: Dictionary = {}
var snapshot: Dictionary = {}
var paths: Dictionary = {}
var figures: Dictionary = {}
var captions: Dictionary = {}
var props: Dictionary = {}
var walls: Array = []
var camera: Camera3D
var sun: DirectionalLight3D
var environment: Environment
var clock_label: Label
var status_label: Label
var detail: RichTextLabel
var events: RichTextLabel
var actor_pick: OptionButton
var choice_pick: OptionButton
var selected := "detective"
var speed := 20.0
var paused := false
var active := false
var ui_elapsed := 0.0
var orbit := Vector2(0.4, 0.95)
var distance := 24.0
var camera_target := Vector3.ZERO
var seed_value := 7
var content_path := DEFAULT_CONTENT
var initial_building: Dictionary = {}
var status_text := ""
var title_ui: Control
var book_ui: Control
var stage: Node3D
var book_paused := false
var campaign_panel: Control
var dual_world: Control
var shutting_down := false

var _events_key := ""

func _ready() -> void:
	add_to_group("lifecycle_hosts")
	bridge = load("res://scenes/main/LifeBridge.cs").new()
	add_child(bridge)
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--dv-content="): content_path = argument.trim_prefix("--dv-content=")
		elif argument.begins_with("--dv-seed="): seed_value = int(argument.trim_prefix("--dv-seed="))
	_title_setup()
	Sound.music("main_theme", 2.0)

func _title_setup() -> void:
	stage = STUDY_STAGE_SCENE.instantiate()
	add_child(stage)
	book_ui = BOOK_UI_SCENE.instantiate()
	add_child(book_ui)
	book_ui.configure(stage, self)
	book_ui.closed.connect(_book_closed)
	title_ui = TITLE_UI_SCENE.instantiate()
	add_child(title_ui)
	title_ui.new_game_requested.connect(func(): open_life())
	title_ui.continue_requested.connect(_continue_game)
	title_ui.book_requested.connect(_open_book_page)
	title_ui.quit_requested.connect(_quit)
	title_ui.builder_requested.connect(open_building)
	title_ui.campaign_requested.connect(open_campaign)
	title_ui.dual_world_requested.connect(func(): open_dual_world())
	title_ui.show_title(has_progress(), true)
	GameSettings.settings_requested.connect(_settings_requested)
	campaign_panel = CAMPAIGN_PANEL.new()
	add_child(campaign_panel)
	campaign_panel.closed.connect(func(): title_ui.show_title(has_progress()))

func _open_book_page(page_id: String) -> void:
	if is_instance_valid(campaign_panel) and campaign_panel.visible:
		campaign_panel.hide()
		title_ui.show_title(has_progress())
		return
	if book_ui.is_open:
		book_ui.goto_page(page_id)
		return
	if book_ui.busy(): return
	book_paused = paused
	paused = true
	if is_instance_valid(life_ui): life_ui.hide()
	if is_instance_valid(builder): builder.hide()
	title_ui.hide_title()
	stage.set_active(true)
	book_ui.open(page_id, active)

func _book_closed() -> void:
	paused = book_paused
	if active:
		stage.set_active(false)
		life_ui.show()
	elif is_instance_valid(builder):
		stage.set_active(false)
		builder.show()
	else:
		title_ui.show_title(has_progress())

func _settings_requested() -> void:
	if is_instance_valid(campaign_panel) and campaign_panel.visible:
		campaign_panel.hide()
		title_ui.show_title(has_progress())
		return
	if book_ui.is_open and book_ui.page_id() == "settings": book_ui.close()
	else: _open_book_page("settings")

func _quit() -> void:
	if is_instance_valid(campaign_panel) and campaign_panel.visible: campaign_panel.begin_shutdown()
	var audio := get_node_or_null("/root/GameAudio")
	if audio != null: audio.quit_cleanly()
	else: get_tree().quit()

func _input(event: InputEvent) -> void:
	if book_ui != null and book_ui.route_input(event): get_viewport().set_input_as_handled()

func _unhandled_input(event: InputEvent) -> void:
	if not active and title_ui.interactive and event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT and stage.pick_book(event.position):
		_open_book_page("journal")

func begin_shutdown() -> void:
	shutting_down = true
	paused = true
	if active: status_text = bridge.Save(_slot_path("auto"))
	if is_instance_valid(campaign_panel) and campaign_panel.visible: campaign_panel.begin_shutdown()
	bridge.Close()
	GameSettings.flush()

func wait_for_shutdown() -> void:
	await get_tree().process_frame

func _continue_game() -> void:
	var candidates := [_auto_path()]
	for index in range(1, 7): candidates.append(_slot_path(str(index)))
	var selected_path := ""
	var latest := -1
	for path in candidates:
		if FileAccess.file_exists(path):
			var modified := FileAccess.get_modified_time(path)
			if modified > latest:
				latest = modified
				selected_path = path
	# 正式游戏（双本体）存档：自动存档与手动槽位，取最新的一份。
	var dual_path := ""
	var dual_latest := -1
	for path in DUAL_WORLD_SAVES:
		if FileAccess.file_exists(path):
			var modified := FileAccess.get_modified_time(path)
			if modified > dual_latest:
				dual_latest = modified
				dual_path = path
	if not dual_path.is_empty() and dual_latest >= latest:
		open_dual_world(dual_path)
		return
	if selected_path.is_empty(): return
	_load_save(selected_path)

func _button(parent: Node, text: String, callback: Callable) -> Button:
	var button := Button.new()
	button.text = text
	button.pressed.connect(callback)
	parent.add_child(button)
	return button

func open_building() -> void:
	if is_instance_valid(campaign_panel): campaign_panel.hide()
	book_ui.close_immediately()
	title_ui.hide_title(0.0)
	stage.set_active(false)
	if not is_instance_valid(builder):
		builder = preload("res://tools/building_construction/BuildingSimulator.tscn").instantiate()
		add_child(builder)
	builder.show()

func open_campaign() -> void:
	if active or is_instance_valid(builder) and builder.visible: return
	book_ui.close_immediately()
	title_ui.hide_title(0.0)
	if is_instance_valid(campaign_panel):
		campaign_panel.open_campaign()

## 双本体整合入口：2D 完整地图 / 3D 单房间 / 2D 蓝图编辑器，规则核心为纯 GDScript 的 DualEngine。
func open_dual_world(resume_path := "") -> void:
	if active or is_instance_valid(builder) and builder.visible or is_instance_valid(dual_world): return
	book_ui.close_immediately()
	title_ui.hide_title(0.0)
	stage.set_active(false)
	var audio := get_node_or_null("/root/GameAudio")
	if audio != null: audio.stop_music(0.4)
	dual_world = DUAL_WORLD_SCENE.instantiate()
	dual_world.resume_path = resume_path
	add_child(dual_world)
	dual_world.closed.connect(close_dual_world)

func close_dual_world() -> void:
	if is_instance_valid(dual_world):
		remove_child(dual_world)
		dual_world.queue_free()
	dual_world = null
	stage.set_active(true)
	title_ui.show_title(has_progress())
	Sound.music("main_theme", 1.5)

func open_life(building: Dictionary = {}) -> void:
	if active: return
	initial_building = building.duplicate(true)
	var result: Dictionary = JSON.parse_string(bridge.Open(content_path, JSON.stringify(building) if not building.is_empty() else "", seed_value))
	if not result.get("ok", false):
		status_text = str(result.get("error", "无法开局"))
		push_error(status_text)
		return
	rules = result.definition
	_present_life(false)

func _present_life(restored: bool) -> void:
	if is_instance_valid(life_ui):
		remove_child(life_ui)
		life_ui.queue_free()
	selected = rules.agents[0].id
	speed = 20.0
	space = Space.new()
	var layer_index := 0
	for index in range(rules.building.layers.size()):
		if not rules.building.layers[index].get("roomFaces", []).is_empty(): layer_index = index; break
	space.setup(rules.building, layer_index, rules.capacities)
	if is_instance_valid(title_ui): title_ui.hide_title()
	book_ui.close_immediately()
	stage.set_active(false)
	if is_instance_valid(builder): builder.hide()
	paths.clear()
	figures.clear()
	captions.clear()
	props.clear()
	walls.clear()
	_make_life_ui()
	_build_view()
	_events_key = ""
	snapshot = JSON.parse_string(bridge.Observe())
	var roster: Array = load("res://scenes/components/characters/ModelCatalog.cs").new().ReadRoster()
	for profile in rules.agents:
		var declaration: Dictionary = {}
		for entry in roster:
			if entry.character_id == profile.id: declaration = entry; break
		if declaration.is_empty(): push_error("缺少人物模型：" + profile.id); continue
		var model := preload("res://scenes/components/characters/CharacterModel.tscn").instantiate()
		camera.get_parent().add_child(model)
		model.configure(declaration)
		figures[profile.id] = model
		var caption := Label3D.new()
		caption.font_size = 36
		caption.pixel_size = 0.005
		caption.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		camera.get_parent().add_child(caption)
		captions[profile.id] = caption
	for actor in snapshot.actors:
		var position := Vector2(actor.placement.X, actor.placement.Z)
		if not restored: position = space.nearest_free(position)
		if position == Vector2.INF: push_error("人物没有可用出生位置"); continue
		if not restored: bridge.Place(actor.id, position.x, space.layer_y, position.y, 0.0)
		figures[actor.id].position = Vector3(position.x, space.layer_y, position.y)
	active = true
	paused = restored
	status_text = ""
	if restored:
		var navigation: Array = JSON.parse_string(bridge.Navigation())
		for action in navigation: _dispatch(action)
	_refresh()

func _make_life_ui() -> void:
	life_ui = PanelContainer.new()
	life_ui.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(life_ui)
	var column := VBoxContainer.new()
	life_ui.add_child(column)
	var header := HFlowContainer.new()
	column.add_child(header)
	_button(header, "返回建筑器" if is_instance_valid(builder) else "返回主菜单", close_life)
	_button(header, "暂停／继续", func():
		paused = not paused
		status_text = "已暂停。" if paused else "")
	var speeds := OptionButton.new()
	for value in [1, 5, 20, 60, 240]: speeds.add_item(str(value) + "×", value)
	speeds.select(2)
	speeds.item_selected.connect(func(index): speed = speeds.get_item_id(index))
	header.add_child(speeds)
	_button(header, "保存进度", func(): status_text = bridge.Save(_slot_path("auto")))
	_button(header, "读取进度", func(): _load_save(_auto_path()))
	_button(header, "手记", func(): _open_book_page("journal"))
	_button(header, "存档", func(): _open_book_page("save"))
	_button(header, "设置", func(): _open_book_page("settings"))
	_button(header, "重载内容", func():
		status_text = bridge.Reload(content_path)
		if status_text.is_empty(): status_text = "内容已重载，运行状态与证据保留。")
	_button(header, "切换墙体", func():
		for wall in walls: wall.visible = not wall.visible)
	clock_label = Label.new()
	header.add_child(clock_label)
	var body := HBoxContainer.new()
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.add_child(body)
	var sidebar := VBoxContainer.new()
	sidebar.custom_minimum_size.x = 300
	body.add_child(sidebar)
	actor_pick = OptionButton.new()
	for profile in rules.agents: actor_pick.add_item(profile.name)
	actor_pick.item_selected.connect(func(index): selected = rules.agents[index].id; _refresh())
	sidebar.add_child(actor_pick)
	detail = RichTextLabel.new()
	detail.size_flags_vertical = Control.SIZE_EXPAND_FILL
	sidebar.add_child(detail)
	choice_pick = OptionButton.new()
	choice_pick.custom_minimum_size.x = 280
	choice_pick.clip_text = true
	sidebar.add_child(choice_pick)
	_button(sidebar, "提交当前可用行动", func():
		if choice_pick.selected >= 0:
			status_text = bridge.Submit(selected, str(choice_pick.get_item_metadata(choice_pick.selected))))
	var viewport_box := SubViewportContainer.new()
	viewport_box.stretch = true
	viewport_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.add_child(viewport_box)
	viewport_box.gui_input.connect(_view_input)
	var viewport := SubViewport.new()
	viewport.own_world_3d = true
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	viewport_box.add_child(viewport)
	var world := Node3D.new()
	viewport.add_child(world)
	camera = Camera3D.new()
	world.add_child(camera)
	var world_environment := WorldEnvironment.new()
	environment = Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color("cdd4df")
	world_environment.environment = environment
	world.add_child(world_environment)
	sun = DirectionalLight3D.new()
	sun.shadow_enabled = true
	world.add_child(sun)
	events = RichTextLabel.new()
	events.custom_minimum_size.x = 320
	events.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_child(events)
	status_label = Label.new()
	status_label.text = "原模型姿态显示；坐卧骨骼动作尚未接入。右键旋转，滚轮缩放。"
	column.add_child(status_label)

func _build_view() -> void:
	var world := camera.get_parent()
	for layer in rules.building.layers: world.add_child(Floor.build(layer))
	for data in rules.building.walls:
		var wall = Wall.build(data)
		if wall != null: world.add_child(wall); walls.append(wall)
	for data in rules.building.props:
		var prop: Node3D
		if str(data.get("path", "")) != "":
			prop = Components.create(data.path)
			if prop != null:
				for parameter in data.get("params", {}): prop.set(parameter, data.params[parameter])
				prop.position = Vector3(data.x, data.get("y", 0), data.z)
				prop.rotation_degrees.y = data.get("yaw", 0)
		else: prop = Props.build(data)
		if prop != null: world.add_child(prop); props[str(data.id)] = prop
	for wall in walls: wall.scale.y = 0.32
	camera_target = Vector3(space.bounds.get_center().x, space.layer_y + 0.4, space.bounds.get_center().y)
	distance = maxf(space.bounds.size.x, space.bounds.size.y) * 1.25
	_update_camera()

func _update_camera() -> void:
	camera.position = camera_target + Vector3(sin(orbit.x) * cos(orbit.y), sin(orbit.y), cos(orbit.x) * cos(orbit.y)) * distance
	camera.look_at(camera_target)

func _view_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and event.button_mask & MOUSE_BUTTON_MASK_RIGHT:
		orbit.x -= event.relative.x * 0.006
		orbit.y = clampf(orbit.y + event.relative.y * 0.006, 0.15, 1.5)
		_update_camera()
	elif event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP: distance = maxf(5, distance * 0.9)
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN: distance = minf(100, distance * 1.1)
		_update_camera()

func _dispatch(action: Dictionary) -> void:
	var position: Vector3 = figures[action.actor].position
	var plan: Dictionary = {}
	var meta: Dictionary = action.meta
	if meta.get("target", "") != "":
		var other: Vector3 = figures[meta.target].position
		var approach: Vector2 = space.nearest_free(Vector2(other.x, other.z) + Vector2(0.8, 0.0), 4)
		var route: Array = space.find_path(Vector2(position.x, position.z), approach)
		if approach != Vector2.INF and (not route.is_empty() or Vector2(position.x, position.z).distance_to(approach) < 0.4):
			plan = {"point": {"approach": approach}, "path": route, "length": space.path_length(Vector2(position.x, position.z), route)}
	else:
		var object = space.object_by_id.get(str(meta.get("obj", "")))
		if object != null: plan = space.plan_use(Vector2(position.x, position.z), object, rules.actions[meta.action], int(meta.get("slot", 0)))
	if plan.is_empty(): bridge.Fail(int(action.execution), "navigation_unreachable"); return
	var endpoint: Vector2 = plan.point.approach
	if not bridge.SetTarget(int(action.execution), endpoint.x, space.layer_y, endpoint.y, float(plan.length), 2.4):
		bridge.Fail(int(action.execution), "navigation_target_rejected")
		return
	paths[action.actor] = {"execution": int(action.execution), "route": plan.path, "target": endpoint, "meta": meta, "label": action.label}

func _move(seconds: float) -> void:
	for actor in paths.keys():
		var movement: Dictionary = paths[actor]
		var current := false
		for profile in snapshot.get("actors", []):
			if profile.id == actor and profile.activity != null:
				current = profile.activity.Execution == movement.execution and profile.activity.Phase == "approaching"
		if not current:
			figures[actor].set_motion(false)
			paths.erase(actor)
			continue
		var model: Node3D = figures[actor]
		model.set_motion(true)
		var position := Vector2(model.position.x, model.position.z)
		var budget := seconds * 2.4
		while budget > 0.0 and not movement.route.is_empty():
			var waypoint: Vector2 = movement.route[0]
			var gap := position.distance_to(waypoint)
			if gap <= budget: position = waypoint; budget -= gap; movement.route.pop_front()
			else:
				var direction := position.direction_to(waypoint)
				position += direction * budget
				model.rotation.y = atan2(direction.x, direction.y)
				if model.has_method("set_motion"): model.set_motion(true, false)
				budget = 0
		model.position = Vector3(position.x, space.layer_y, position.y)
		if model.has_method("set_motion") and movement.route.is_empty(): model.set_motion(false)
		bridge.Progress(movement.execution, position.x, space.layer_y, position.y, space.path_length(position, movement.route))
		if movement.route.is_empty():
			if not bridge.Arrive(movement.execution, position.x, space.layer_y, position.y): bridge.Fail(movement.execution, "arrival_rejected")
			paths.erase(actor)

func _process(delta: float) -> void:
	if shutting_down: return
	if is_instance_valid(campaign_panel) and campaign_panel.visible: return
	if stage != null and stage.visible:
		var pointer := get_viewport().get_mouse_position()
		stage.set_pointer(pointer / get_viewport_rect().size.max(Vector2.ONE) * 2.0 - Vector2.ONE)
		stage.set_hover(title_ui.interactive and stage.pick_book(pointer))
	if not active: return
	if not paused and snapshot.get("active", true):
		var remaining := minf(delta, 0.2) * speed
		while remaining > 0:
			var seconds := minf(remaining, 5.0)
			var result: Dictionary = JSON.parse_string(bridge.Step(seconds))
			if result.has("error"): status_text = result.error; paused = true; break
			snapshot = result.snapshot
			_move(float(result.elapsed_seconds))
			for action in result.dispatch: _dispatch(action)
			# F4：Step 返回值里已带 snapshot，不再额外 Observe()（每次多序列化 + 解析一整份历史快照）
			remaining -= seconds
	for actor in snapshot.get("actors", []):
		if not figures.has(actor.id): continue
		figures[actor.id].pause_animation(paused)
		var placement: Dictionary = actor.placement
		figures[actor.id].position = Vector3(placement.X, placement.Y, placement.Z)
		var text: String = actor.name
		if actor.activity != null:
			text += "\n" + actor.activity.Phase
		captions[actor.id].text = text
		captions[actor.id].position = figures[actor.id].position + Vector3(0, 1.65, 0)
	var hour := fmod(float(snapshot.get("time", 420)), 1440.0) / 60.0
	get_node("/root/GameAudio").apply_music_scene(snapshot)
	var daylight := clampf(sin((hour - 6) / 12 * PI), 0, 1)
	sun.light_energy = 0.12 + daylight
	sun.rotation_degrees = Vector3(-15 - daylight * 55, 35 + (hour - 12) * 6, 0)
	environment.ambient_light_energy = 0.25 + daylight * 0.5
	environment.background_color = Color("101b30").lerp(Color("8cb3e5"), daylight)
	for item in snapshot.get("objects", []):
		if props.has(item.id):
			for light in props[item.id].find_children("*", "Light3D", true, false): light.visible = bool(item.lamp)
	ui_elapsed += delta
	if ui_elapsed >= 0.3: ui_elapsed = 0; _refresh()

func _refresh() -> void:
	if not active: return
	var minute := int(snapshot.get("time", 420))
	clock_label.text = "第%d日 %02d:%02d%s" % [minute / 1440 + 1, minute % 1440 / 60, minute % 60, " · 暂停" if paused else ""]
	var text := "作者检查器\n"
	var refresh_choices := not choice_pick.get_popup().visible
	var previous_choice := str(choice_pick.get_item_metadata(choice_pick.selected)) if choice_pick.selected >= 0 else ""
	if refresh_choices: choice_pick.clear()
	for actor in snapshot.get("actors", []):
		if actor.id != selected: continue
		text += str(actor.purpose) + "\n\n"
		for need in actor.needs: text += "%s: %.0f\n" % [str(rules.needs[need].label), float(actor.needs[need])]
		text += "口粮 %s · 证据 %s\n" % [actor.food, actor.evidence_count]
		text += "\n人物主观认知（观察片段与推论）\n"
		var cognition: Dictionary = actor.get("cognition", {})
		var status_labels := {"proved":"有依据", "refuted":"有反证", "conflicted":"证据冲突", "unknown":"未知", "pending":"整理中"}
		for query in cognition.get("queries", []):
			text += "%s：%s\n" % [query.label, status_labels.get(query.status, query.status)]
		if refresh_choices:
			for choice in actor.choices:
				choice_pick.add_item(choice.label)
				choice_pick.set_item_metadata(choice_pick.item_count - 1, choice.id)
				if choice.id == previous_choice: choice_pick.select(choice_pick.item_count - 1)
	text += "\n有向关系（好感／信任／积怨）\n"
	var audit: Dictionary = snapshot.get("audit", {})
	for relation in audit.get("relations", []):
		if relation.from == selected: text += "%s: %.1f / %.1f / %.1f %s\n" % [relation.to, relation.affinity, relation.trust, relation.tension, relation.stage]
	detail.text = text
	# F4：事件文本只在 mechanics / receipts 数量变化时重建，不再每 0.3 秒遍历全部历史
	var mech: Array = snapshot.get("mechanics", [])
	var rcpt: Array = snapshot.get("receipts", [])
	var events_key := "%d|%d" % [mech.size(), rcpt.size()]
	if events_key != _events_key:
		_events_key = events_key
		var log_text := "事件与实际兑现\n"
		for event in mech:
			if event.Kind == "life_response":
				var response: Dictionary = event.Details
				log_text += "%s → %s · %s\n%s · %s\n\n" % [response.requester, response.responder, rules.social.categories[response.category].label, rules.social.mode_labels[response.mode], "已兑现" if response.delivered else "尚未兑现"]
			elif event.Kind == "life_seating":
				log_text += "%s · 座位约定%s\n\n" % [event.Details.requester, "已实际履行" if event.Success else "已到期"]
		for receipt in rcpt.slice(-8): log_text += "%s · %s\n" % [receipt.Actor, receipt.Reason]
		events.text = log_text
	if not status_text.is_empty(): status_label.text = status_text
	elif not audit.is_empty(): status_label.text = "库存 %.0f · 携带 %.0f · 已消耗 %.0f · 总供给 %.0f　|　原模型姿态显示，坐卧骨骼动作未接入" % [audit.stock, audit.carried, audit.consumed, audit.supplied]

func _load_save(path: String) -> void:
	status_text = bridge.Load(path)
	if status_text.is_empty():
		rules = JSON.parse_string(bridge.Definition())
		_present_life(true)
		book_paused = true
		status_text = "已恢复；保持暂停。"
	_refresh()

func close_life() -> void:
	if active: status_text = bridge.Save(_slot_path("auto"))
	active = false
	bridge.Close()
	paths.clear()
	if is_instance_valid(life_ui):
		remove_child(life_ui)
		life_ui.queue_free()
	life_ui = null
	if is_instance_valid(builder): builder.show()
	else:
		stage.set_active(true)
		title_ui.show_title(has_progress())
		Sound.music("main_theme")

func has_progress() -> bool:
	for path in DUAL_WORLD_SAVES:
		if FileAccess.file_exists(path): return true
	if FileAccess.file_exists(_auto_path()): return true
	for index in range(1, 7):
		if FileAccess.file_exists(_slot_path(str(index))): return true
	return false

func can_save() -> bool:
	return active

func journal() -> Dictionary:
	return JSON.parse_string(bridge.Journal(selected))

func journal_actions() -> Array:
	for actor in snapshot.get("actors", []):
		if actor.id == selected: return actor.choices
	return []

func journal_submit(action: String) -> void:
	status_text = bridge.Submit(selected, action)

func journal_save_note(title: String, text: String, related: String, judgement: String, identity: String) -> String:
	return bridge.SaveNote(selected, title, text, related, judgement, identity)

func save_slots() -> Array:
	var slots: Array = []
	var auto_path := _auto_path()
	slots.append(_slot_summary("auto", "自动记录", auto_path))
	for index in range(1, 7):
		var path := _slot_path(str(index))
		slots.append(_slot_summary(str(index), "手记 " + ["一", "二", "三", "四", "五", "六"][index - 1], path))
	return slots

func _slot_summary(id: String, label: String, path: String) -> Dictionary:
	var exists := FileAccess.file_exists(path)
	var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(path)) if exists else null
	var minute := float(data.get("game_time", 0.0)) if data is Dictionary else 0.0
	return {"id":id, "label":label, "kind":"auto" if id == "auto" else "manual", "exists":exists, "saved_at":FileAccess.get_modified_time(path) if exists else 0, "place":"生活宅邸" if exists else "—", "game_time":"第%d日 %02d:%02d" % [int(minute / 1440) + 1, int(minute) % 1440 / 60, int(minute) % 60] if exists else "—"}

func save_to_slot(id: String) -> String:
	if id == "auto": return "自动记录由生活进程写入。"
	if not id.is_valid_int() or int(id) < 1 or int(id) > 6: return "无效的手记页。"
	return bridge.Save(_slot_path(id))

func load_slot(id: String) -> String:
	if id != "auto" and (not id.is_valid_int() or int(id) < 1 or int(id) > 6): return "无效的手记页。"
	var path := _auto_path() if id == "auto" else _slot_path(id)
	if not FileAccess.file_exists(path): return "这一页的记录无法读取。"
	_load_save(path)
	return "" if status_text == "已恢复；保持暂停。" else status_text

func delete_slot(id: String) -> String:
	if id == "auto": return "自动记录不能撕去。"
	if not id.is_valid_int() or int(id) < 1 or int(id) > 6: return "无效的手记页。"
	var path := _slot_path(id)
	if FileAccess.file_exists(path):
		var error := DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
		return "" if error == OK else error_string(error)
	return ""

func _slot_path(id: String) -> String:
	return _slot_directory().path_join("slot-%s.json" % id)

func _auto_path() -> String:
	var path := _slot_path("auto")
	return "user://life-save.json" if _slot_directory() == "user://life-slots" and not FileAccess.file_exists(path) else path

func _slot_directory() -> String:
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--dv-save-slot="): return "user://sessions/%s/life-slots" % argument.trim_prefix("--dv-save-slot=")
	return "user://life-slots"

func mcp_observe() -> Dictionary:
	if is_instance_valid(campaign_panel) and campaign_panel.visible: return campaign_panel.observation()
	var result := {"started": active, "state": snapshot if active else {"active": true, "campaign_completed": false}, "faulted": not str(snapshot.get("error", "")).is_empty(), "host_errors": [], "ui": {"paused": paused, "speed": speed, "status": status_text}}
	if is_instance_valid(builder):
		result["authored_scene"] = builder.state.data.duplicate(true)
		result["selection"] = builder.state.selected.duplicate(true)
		result["blueprint"] = {"pan": builder.blueprint.pan, "zoom": builder.blueprint.zoom}
	return result
