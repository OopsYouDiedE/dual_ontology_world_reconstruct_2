extends Control

const Space = preload("res://scenes/components/life/BuildingSpace.gd")
const Components = preload("res://tools/building_construction/BuildingConstruction/Shared/ComponentFactory.gd")
const Wall = preload("res://tools/building_construction/BuildingConstruction/Walls/WallPathGeometry.gd")
const Floor = preload("res://tools/building_construction/BuildingConstruction/Floors/ArchitectFloor.gd")
const Props = preload("res://tools/building_construction/BuildingConstruction/Props/ArchitectProps.gd")
const DEFAULT_CONTENT := "res://assets/data/scenarios/life_simulation.dv"

var bridge: Node
var menu: Control
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

func _ready() -> void:
	bridge = load("res://scenes/main/LifeBridge.cs").new()
	add_child(bridge)
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--dv-content="): content_path = argument.trim_prefix("--dv-content=")
		elif argument.begins_with("--dv-seed="): seed_value = int(argument.trim_prefix("--dv-seed="))
	_make_menu()

func _button(parent: Node, text: String, callback: Callable) -> Button:
	var button := Button.new()
	button.text = text
	button.pressed.connect(callback)
	parent.add_child(button)
	return button

func _make_menu() -> void:
	menu = VBoxContainer.new()
	menu.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	menu.position = Vector2(-210, -100)
	menu.custom_minimum_size = Vector2(420, 240)
	add_child(menu)
	var title := Label.new()
	title.text = "五人生活推演 · Reconstruct 2"
	title.add_theme_font_size_override("font_size", 28)
	menu.add_child(title)
	_button(menu, "开始生活新局", func(): open_life())
	_button(menu, "打开建筑设计工具", open_building)
	var note := Label.new()
	note.text = "侦探 · 雀儿 · 卢西安 · 阮清月 · 沈鼐"
	menu.add_child(note)

func open_building() -> void:
	menu.hide()
	if not is_instance_valid(builder):
		builder = preload("res://tools/building_construction/BuildingSimulator.tscn").instantiate()
		add_child(builder)
	builder.show()

func open_life(building: Dictionary = {}) -> void:
	if active: return
	initial_building = building.duplicate(true)
	var result: Dictionary = JSON.parse_string(bridge.Open(content_path, JSON.stringify(building) if not building.is_empty() else "", seed_value))
	if not result.get("ok", false):
		status_text = str(result.get("error", "无法开局"))
		push_error(status_text)
		return
	rules = result.definition
	selected = rules.agents[0].id
	speed = 20.0
	space = Space.new()
	var layer_index := 0
	for index in range(rules.building.layers.size()):
		if not rules.building.layers[index].get("roomFaces", []).is_empty(): layer_index = index; break
	space.setup(rules.building, layer_index, rules.capacities)
	menu.hide()
	if is_instance_valid(builder): builder.hide()
	paths.clear()
	figures.clear()
	captions.clear()
	props.clear()
	walls.clear()
	_make_life_ui()
	_build_view()
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
		var position: Vector2 = space.nearest_free(Vector2(actor.placement.X, actor.placement.Z))
		if position == Vector2.INF: push_error("人物没有可用出生位置"); continue
		bridge.Place(actor.id, position.x, space.layer_y, position.y, 0.0)
		figures[actor.id].position = Vector3(position.x, space.layer_y, position.y)
	active = true
	paused = false
	status_text = ""
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
	_button(header, "保存进度", func(): status_text = bridge.Save("user://life-save.json"))
	_button(header, "读取进度", _load_save)
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
			paths.erase(actor)
			continue
		var model: Node3D = figures[actor]
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
				budget = 0
		model.position = Vector3(position.x, space.layer_y, position.y)
		bridge.Progress(movement.execution, position.x, space.layer_y, position.y, space.path_length(position, movement.route))
		if movement.route.is_empty():
			if not bridge.Arrive(movement.execution, position.x, space.layer_y, position.y): bridge.Fail(movement.execution, "arrival_rejected")
			paths.erase(actor)

func _process(delta: float) -> void:
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
			snapshot = JSON.parse_string(bridge.Observe())
			remaining -= seconds
	for actor in snapshot.get("actors", []):
		if not figures.has(actor.id): continue
		var placement: Dictionary = actor.placement
		figures[actor.id].position = Vector3(placement.X, placement.Y, placement.Z)
		var text: String = actor.name
		if actor.activity != null:
			text += "\n" + actor.activity.Phase
		captions[actor.id].text = text
		captions[actor.id].position = figures[actor.id].position + Vector3(0, 1.65, 0)
	var hour := fmod(float(snapshot.get("time", 420)), 1440.0) / 60.0
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
	var log_text := "事件与实际兑现\n"
	for event in snapshot.get("mechanics", []):
		if event.Kind == "life_response":
			var response: Dictionary = event.Details
			log_text += "%s → %s · %s\n%s · %s\n\n" % [response.requester, response.responder, rules.social.categories[response.category].label, rules.social.mode_labels[response.mode], "已兑现" if response.delivered else "尚未兑现"]
		elif event.Kind == "life_seating":
			log_text += "%s · 座位约定%s\n\n" % [event.Details.requester, "已实际履行" if event.Success else "已到期"]
	for receipt in snapshot.get("receipts", []).slice(-8): log_text += "%s · %s\n" % [receipt.Actor, receipt.Reason]
	events.text = log_text
	if not status_text.is_empty(): status_label.text = status_text
	elif not audit.is_empty(): status_label.text = "库存 %.0f · 携带 %.0f · 已消耗 %.0f · 总供给 %.0f　|　原模型姿态显示，坐卧骨骼动作未接入" % [audit.stock, audit.carried, audit.consumed, audit.supplied]

func _load_save() -> void:
	paused = true
	status_text = bridge.Load("user://life-save.json")
	if status_text.is_empty():
		paths.clear()
		snapshot = JSON.parse_string(bridge.Observe())
		for actor in snapshot.actors:
			figures[actor.id].position = Vector3(actor.placement.X, actor.placement.Y, actor.placement.Z)
		var navigation: Array = JSON.parse_string(bridge.Navigation())
		for action in navigation: _dispatch(action)
		status_text = "已恢复；保持暂停。"
	_refresh()

func close_life() -> void:
	active = false
	bridge.Close()
	paths.clear()
	if is_instance_valid(life_ui): life_ui.queue_free()
	if is_instance_valid(builder): builder.show()
	else: menu.show()

func mcp_observe() -> Dictionary:
	var result := {"started": active, "state": snapshot if active else {"active": true, "campaign_completed": false}, "faulted": not str(snapshot.get("error", "")).is_empty(), "host_errors": [], "ui": {"paused": paused, "speed": speed, "status": status_text}}
	if is_instance_valid(builder):
		result["authored_scene"] = builder.state.data.duplicate(true)
		result["selection"] = builder.state.selected.duplicate(true)
		result["blueprint"] = {"pan": builder.blueprint.pan, "zoom": builder.blueprint.zoom}
	return result
