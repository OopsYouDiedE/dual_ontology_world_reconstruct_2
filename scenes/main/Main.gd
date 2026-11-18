extends Control

const TITLE_UI_SCENE := preload("res://scenes/UIpanel/TitleUI/TitleUI.tscn")
const BOOK_UI_SCENE := preload("res://scenes/UIpanel/BookUI/BookUI.tscn")
const STUDY_STAGE_SCENE := preload("res://scenes/components/world/StudyDeskStage3D.tscn")
const Sound := preload("res://scenes/components/shared/Sound.gd")

const Routes = preload("res://scenes/components/life/BuildingRoutes.gd")
const Components = preload("res://tools/building_construction/BuildingConstruction/Shared/ComponentFactory.gd")
const Openings = preload("res://tools/building_construction/BuildingConstruction/Windows/ArchitectOpenings.gd")
const Wall = preload("res://tools/building_construction/BuildingConstruction/Walls/WallPathGeometry.gd")
const Floor = preload("res://tools/building_construction/BuildingConstruction/Floors/ArchitectFloor.gd")
const Stair = preload("res://tools/building_construction/BuildingConstruction/Stairs/ArchitectStair.gd")
const Railing = preload("res://tools/building_construction/BuildingConstruction/Railings/ArchitectRailing.gd")
const Props = preload("res://tools/building_construction/BuildingConstruction/Props/ArchitectProps.gd")
const DEFAULT_CONTENT := "res://assets/data/scenarios/life_simulation.dv"
const DUAL_WORLD_SCENE := preload("res://scenes/dual_world/DualWorldMain.tscn")
const DUAL_WORLD_SCRIPT := preload("res://scenes/dual_world/DualWorldMain.gd")

const LIFE_ENGLISH = preload("res://assets/data/life_simulation/display_en.json")
const LIFE_PROMISE_PREFIX := "履行承诺："

var bridge: Variant
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
var door_models: Dictionary = {}
var door_pick: OptionButton
var door_toggle: Button
var door_lock: Button
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

func _dual_world_saves() -> Array:
	var dir := DUAL_WORLD_SCRIPT.save_dir_path()
	return [
		dir + "/auto.json",
		dir + "/save_1.json",
		dir + "/save_2.json",
		dir + "/save_3.json",
	]

func _ready() -> void:
	add_to_group("lifecycle_hosts")
	if ClassDB.class_exists("CSharpScript"):
		var bridge_script: Script = load("res://scenes/main/LifeBridge.cs")
		if bridge_script != null and bridge_script.can_instantiate():
			bridge = bridge_script.new()
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
	title_ui.life_requested.connect(func(): open_life())
	title_ui.continue_life_requested.connect(_continue_life)
	title_ui.continue_requested.connect(_continue_game)
	title_ui.book_requested.connect(_open_book_page)
	title_ui.quit_requested.connect(_quit)
	title_ui.builder_requested.connect(open_building)
	title_ui.new_game_requested.connect(func(): open_dual_world())
	_show_title(true)
	var settings := get_node_or_null("/root/GameSettings")
	if settings != null and settings.has_signal("settings_requested"):
		settings.connect("settings_requested", _settings_requested)
	if bridge != null and "--dv-campaign-lab" in OS.get_cmdline_user_args():
		var cp_script: Script = load("res://scenes/main/CampaignPanel.gd")
		if cp_script != null:
			campaign_panel = cp_script.new()
			add_child(campaign_panel)
			campaign_panel.closed.connect(func(): _show_title())
			open_campaign.call_deferred()

func _open_book_page(page_id: String) -> void:
	if is_instance_valid(campaign_panel) and campaign_panel.visible:
		campaign_panel.hide()
		_show_title()
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
		_show_title()

func _settings_requested() -> void:
	if is_instance_valid(campaign_panel) and campaign_panel.visible:
		campaign_panel.hide()
		_show_title()
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
	if is_instance_valid(dual_world):
		if is_instance_valid(dual_world.checkpoints): dual_world.checkpoints.begin_shutdown()
		dual_world._finish_transit_now()
		dual_world._write_auto()
	if active and bridge != null: status_text = bridge.Save(_slot_path("auto"))
	if is_instance_valid(campaign_panel) and campaign_panel.visible: campaign_panel.begin_shutdown()
	if bridge != null: bridge.Close()
	var settings := get_node_or_null("/root/GameSettings")
	if settings != null and settings.has_method("flush"):
		settings.call("flush")

func wait_for_shutdown() -> void:
	await get_tree().process_frame

func _show_title(first := false) -> void:
	title_ui.set_life_menu(bridge != null, not _latest_life_save().is_empty())
	title_ui.show_title(not _latest_save(_dual_world_saves()).is_empty(), first)


static func _latest_save(paths: Array) -> String:
	var selected := ""
	var latest := -1
	for path in paths:
		if not FileAccess.file_exists(path): continue
		var modified := FileAccess.get_modified_time(path)
		if modified > latest:
			selected = path
			latest = modified
	return selected


func _continue_game() -> void:
	var path := _latest_save(_dual_world_saves())
	if not path.is_empty(): open_dual_world(path)


func _latest_life_save() -> String:
	if bridge == null: return ""
	var slots := [_auto_path()]
	for index in range(1, 7): slots.append(_slot_path(str(index)))
	return _latest_save(slots)


func _continue_life() -> void:
	var path := _latest_life_save()
	if not path.is_empty(): _load_save(path)


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
		# The builder can launch a title preview; load on demand to avoid preloading a cycle.
		var scene := load("res://tools/building_construction/BuildingSimulator.tscn") as PackedScene
		if scene == null: return
		builder = scene.instantiate()
		add_child(builder)
	builder.show()

func open_campaign() -> void:
	if not is_instance_valid(campaign_panel) or active or is_instance_valid(builder) and builder.visible: return
	book_ui.close_immediately()
	title_ui.hide_title(0.0)
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
	_show_title()
	Sound.music("main_theme", 1.5)

func open_life(building: Dictionary = {}) -> void:
	if active or bridge == null: return
	initial_building = building.duplicate(true)
	var result: Dictionary = JSON.parse_string(bridge.Open(content_path, JSON.stringify(building) if not building.is_empty() else "", seed_value))
	if not result.get("ok", false):
		status_text = str(result.get("error", "Could not start the simulation"))
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
	space = Routes.new()
	var layer_index := 0
	for index in range(rules.building.layers.size()):
		if not rules.building.layers[index].get("roomFaces", []).is_empty(): layer_index = index; break
	space.setup(rules.building, layer_index, rules.capacities)
	bridge.SetObjectRouteSpace3D(space, rules.actions)
	if is_instance_valid(title_ui): title_ui.hide_title()
	book_ui.close_immediately()
	stage.set_active(false)
	if is_instance_valid(builder): builder.hide()
	paths.clear()
	figures.clear()
	captions.clear()
	props.clear()
	walls.clear()
	door_models.clear()
	_make_life_ui()
	_build_view()
	_refresh_doors()
	_events_key = ""
	snapshot = JSON.parse_string(bridge.Observe())
	var roster: Array = load("res://scenes/components/characters/ModelCatalog.cs").new().ReadRoster()
	for profile in rules.agents:
		var declaration: Dictionary = {}
		for entry in roster:
			if entry.character_id == profile.id: declaration = entry; break
		if declaration.is_empty(): push_error("Missing character model: " + profile.id); continue
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
	var start_positions: Array[Vector3] = []
	for actor in snapshot.actors:
		if not figures.has(actor.id): continue
		var position := Vector3(actor.placement.X, actor.placement.Y, actor.placement.Z)
		if not restored:
			position = space.spawn_near(position, start_positions, 12)
			if not position.is_finite():
				# Very small rooms can have fewer full-body slots than the roster.
				# Prefer a tighter distinct start, then let the actor route out normally.
				position = space.spawn_near(Vector3(actor.placement.X, actor.placement.Y, actor.placement.Z), start_positions, 16, 0.45)
		if not position.is_finite():
			push_error("No distinct standable start for " + str(actor.id))
			figures[actor.id].hide()
			captions[actor.id].hide()
			continue
		start_positions.append(position)
		if not restored: bridge.Place(actor.id, position.x, position.y, position.z, 0.0)
		figures[actor.id].position = position
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
	_button(header, "Back to Builder" if is_instance_valid(builder) else "Main Menu", close_life)
	_button(header, "Pause / Resume", func():
		paused = not paused
		status_text = "Paused." if paused else "")
	var speeds := OptionButton.new()
	for value in [1, 5, 20, 60, 240]: speeds.add_item(str(value) + "×", value)
	speeds.select(2)
	speeds.item_selected.connect(func(index): speed = speeds.get_item_id(index))
	header.add_child(speeds)
	_button(header, "Quick Save", func(): status_text = bridge.Save(_slot_path("auto")))
	_button(header, "Quick Load", func(): _load_save(_auto_path()))
	_button(header, "Journal", func(): _open_book_page("journal"))
	_button(header, "Saves", func(): _open_book_page("save"))
	_button(header, "Settings", func(): _open_book_page("settings"))
	_button(header, "Reload Content", func():
		status_text = bridge.Reload(content_path)
		if status_text.is_empty(): status_text = "Content reloaded. Progress and evidence retained.")
	_button(header, "Toggle Walls", func():
		for wall in walls: wall.visible = not wall.visible)
	clock_label = Label.new()
	header.add_child(clock_label)
	door_pick = OptionButton.new()
	door_pick.item_selected.connect(func(_index): _refresh_door_buttons())
	header.add_child(door_pick)
	door_toggle = _button(header, "Close Door", func(): _change_door("toggle"))
	door_lock = _button(header, "Lock Door", func(): _change_door("lock"))
	var body := HBoxContainer.new()
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.add_child(body)
	var sidebar := VBoxContainer.new()
	sidebar.custom_minimum_size.x = 300
	body.add_child(sidebar)
	actor_pick = OptionButton.new()
	for profile in rules.agents: actor_pick.add_item(_life_text(profile.name))
	actor_pick.item_selected.connect(func(index): selected = rules.agents[index].id; _refresh())
	sidebar.add_child(actor_pick)
	detail = RichTextLabel.new()
	detail.size_flags_vertical = Control.SIZE_EXPAND_FILL
	sidebar.add_child(detail)
	choice_pick = OptionButton.new()
	choice_pick.custom_minimum_size.x = 280
	choice_pick.clip_text = true
	sidebar.add_child(choice_pick)
	_button(sidebar, "Queue Selected Action", func():
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
	status_label.text = "Right-click and drag to orbit; scroll to zoom."
	column.add_child(status_label)

func _build_view() -> void:
	var world := camera.get_parent()
	for layer in rules.building.layers: world.add_child(Floor.build(layer))
	for stair in rules.building.get("stairs", []): world.add_child(Stair.build(stair))
	for rail in rules.building.get("railings", []): world.add_child(Railing.build(rail))
	for data in rules.building.walls:
		var wall = Wall.build(data)
		if wall != null:
			world.add_child(wall)
			walls.append(wall)
			for part in wall.find_children("*", "Node3D", true, false):
				if part.has_meta("opening_id"): door_models[part.get_meta("opening_id")] = part
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
	camera_target = Vector3(space.primary.bounds.get_center().x, space.primary.layer_y + 0.4, space.primary.bounds.get_center().y)
	distance = maxf(space.primary.bounds.size.x, space.primary.bounds.size.y) * 1.25
	_update_camera()

func _refresh_doors() -> void:
	var retain := str(door_pick.get_selected_metadata().id) if door_pick.selected >= 0 else ""
	var controls: Array = JSON.parse_string(bridge.DoorControls())
	door_pick.clear()
	var choice := 0
	for control in controls:
		var index := door_pick.item_count
		door_pick.add_item("Door %d · %s" % [index + 1, str(control.state).capitalize()])
		door_pick.set_item_metadata(index, control)
		if control.id == retain: choice = index
		if door_models.has(control.id): Openings.set_door_open(door_models[control.id], control.state == "open")
	if not controls.is_empty(): door_pick.select(choice)
	for widget in [door_pick, door_toggle, door_lock]: widget.visible = not controls.is_empty()
	_refresh_door_buttons()

func _refresh_door_buttons() -> void:
	if door_pick.selected < 0: return
	var state_name := str(door_pick.get_selected_metadata().state)
	door_toggle.disabled = state_name == "locked"
	door_toggle.text = "Close Door" if state_name == "open" else "Open Door"
	door_lock.text = "Unlock Door" if state_name == "locked" else "Lock Door"

func _change_door(operation: String) -> void:
	if not active or door_pick.selected < 0: return
	status_text = bridge.ChangeDoor(str(door_pick.get_selected_metadata().id), operation)
	if status_text.is_empty():
		_refresh_doors()
		# The bridge has published the new grid and invalidated cached action costs.
		# Replace every outstanding physical approach before any actor moves again.
		for actor in paths:
			if figures.has(actor): figures[actor].set_motion(false)
		paths.clear()
		var navigation: Array = JSON.parse_string(bridge.Navigation())
		for action in navigation: _dispatch(action)
	snapshot = JSON.parse_string(bridge.Observe())
	_refresh()

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

func _occupied_stands(actor: String) -> Array[Vector3]:
	var occupied: Array[Vector3] = []
	for other in figures:
		if other == actor: continue
		occupied.append(figures[other].position)
		if paths.has(other): occupied.append(paths[other].endpoint)
	return occupied

func _dispatch(action: Dictionary, replans := 0) -> void:
	var model := figures.get(action.actor) as Node3D
	if model == null: bridge.Fail(int(action.execution), "navigation_actor_missing"); return
	var position := model.position
	var plan: Dictionary = {}
	var meta: Dictionary = action.meta
	var occupied := _occupied_stands(action.actor)
	if meta.get("target", "") != "":
		var other := figures.get(meta.target) as Node3D
		if other != null: plan = space.plan_social(position, other.position, occupied)
	else:
		plan = space.plan_use(position, str(meta.get("obj", "")), rules.actions[meta.action], int(meta.get("slot", 0)), occupied)
	if plan.is_empty(): bridge.Fail(int(action.execution), "navigation_unreachable"); return
	var endpoint: Vector3 = plan.target
	if not bridge.SetTarget(int(action.execution), endpoint.x, endpoint.y, endpoint.z, float(plan.length), 2.4):
		bridge.Fail(int(action.execution), "navigation_target_rejected")
		return
	paths[action.actor] = {"execution": int(action.execution), "route": plan.path, "endpoint": endpoint, "request": action, "replans": replans}

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
		var position := model.position
		var budget := seconds * 2.4
		if Routes.path_length(position, movement.route) <= budget + 0.6:
			var partner := figures.get(movement.request.meta.get("target", "")) as Node3D
			var stale := not Routes.stand_is_free(movement.endpoint, _occupied_stands(actor))
			stale = stale or (partner != null and not space.social_slot_valid(movement.endpoint, partner.position))
			if stale:
				paths.erase(actor)
				model.set_motion(false)
				if movement.replans < 3: _dispatch(movement.request, movement.replans + 1)
				else: bridge.Fail(movement.execution, "navigation_unreachable")
				continue
		while budget > 0.0 and not movement.route.is_empty():
			var waypoint: Vector3 = movement.route[0]
			var gap := position.distance_to(waypoint)
			if gap <= budget: position = waypoint; budget -= gap; movement.route.pop_front()
			else:
				var direction := position.direction_to(waypoint)
				position += direction * budget
				model.rotation.y = atan2(direction.x, direction.z)
				if model.has_method("set_motion"): model.set_motion(true, false)
				budget = 0
		model.position = position
		if model.has_method("set_motion") and movement.route.is_empty(): model.set_motion(false)
		bridge.Progress(movement.execution, position.x, position.y, position.z, Routes.path_length(position, movement.route))
		if movement.route.is_empty():
			var partner := figures.get(movement.request.meta.get("target", "")) as Node3D
			if partner != null: model.look_at(Vector3(partner.position.x, position.y, partner.position.z), Vector3.UP, true)
			if not bridge.Arrive(movement.execution, position.x, position.y, position.z): bridge.Fail(movement.execution, "arrival_rejected")
			paths.erase(actor)

func _sync_life_animations() -> void:
	for profile in snapshot.get("actors", []):
		var model: Node3D = figures.get(str(profile.id), null)
		if model == null or not is_instance_valid(model): continue
		var activity = profile.activity
		if activity == null or str(activity.Phase) == "cancelling":
			model.clear_life_action()
			model.set_motion(false)
		elif str(activity.Phase) in ["approaching", "moving"]:
			model.clear_life_action()
			model.set_motion(true)
		elif str(activity.Phase) == "working":
			var motor: Dictionary = profile.get("motor", {}) if profile.get("motor") is Dictionary else {}
			model.play_life_action(str(motor.get("posture", "stand")), str(motor.get("animation", "")))
		else:
			model.clear_life_action()
			model.set_motion(false)

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
	_sync_life_animations()
	for actor in snapshot.get("actors", []):
		if not figures.has(actor.id): continue
		figures[actor.id].pause_animation(paused)
		var placement: Dictionary = actor.placement
		figures[actor.id].position = Vector3(placement.X, placement.Y, placement.Z)
		var text: String = _life_text(actor.name)
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

# English presentation only: declarations, save hashes and evidence values stay intact.
func _life_text(raw: Variant) -> String:
	var label := str(raw) if raw != null else ""
	var aliases: Dictionary = LIFE_ENGLISH.data
	if aliases.has(label): return aliases[label]
	if label.begins_with(LIFE_PROMISE_PREFIX):
		return "Keep Promise: " + _life_text(label.trim_prefix(LIFE_PROMISE_PREFIX))
	return label

func _life_query(query: Dictionary) -> String:
	var id := str(query.id)
	var separator := id.find("_")
	if separator > 0 and id.substr(0, separator) in ["source", "ask", "offer", "stock", "motive"]:
		var other := id.substr(separator + 1)
		var template := str(query.label).replace(other, "${other}")
		var profile: Array = rules.agents.filter(func(agent): return agent.id == other)
		var name := _life_text(profile[0].name) if not profile.is_empty() else other.capitalize()
		return _life_text(template).replace("${other}", name)
	return _life_text(query.label)

func _refresh() -> void:
	if not active: return
	var minute := int(snapshot.get("time", 420))
	clock_label.text = "Day %d %02d:%02d%s" % [minute / 1440 + 1, minute % 1440 / 60, minute % 60, " · Paused" if paused else ""]
	var text := "Character Inspector\n"
	var refresh_choices := not choice_pick.get_popup().visible
	var previous_choice := str(choice_pick.get_item_metadata(choice_pick.selected)) if choice_pick.selected >= 0 else ""
	if refresh_choices: choice_pick.clear()
	for actor in snapshot.get("actors", []):
		if actor.id != selected: continue
		text += _life_text(actor.purpose) + "\n\n"
		for need in actor.needs: text += "%s: %.0f\n" % [_life_text(rules.needs[need].label), float(actor.needs[need])]
		text += "Rations %s · Evidence %s\n" % [actor.food, actor.evidence_count]
		text += "\nCharacter Knowledge (Observations and Inferences)\n"
		var cognition: Dictionary = actor.get("cognition", {})
		var status_labels := {"proved":"Supported", "refuted":"Refuted", "conflicted":"Conflicting", "unknown":"Unknown", "pending":"Pending"}
		for query in cognition.get("queries", []):
			text += "%s: %s\n" % [_life_query(query), status_labels.get(query.status, query.status)]
		if refresh_choices:
			for choice in actor.choices:
				choice_pick.add_item(_life_text(choice.label))
				choice_pick.set_item_metadata(choice_pick.item_count - 1, choice.id)
				if choice.id == previous_choice: choice_pick.select(choice_pick.item_count - 1)
	text += "\nRelationships (Affinity / Trust / Tension)\n"
	var audit: Dictionary = snapshot.get("audit", {})
	for relation in audit.get("relations", []):
		if relation.from == selected: text += "%s: %.1f / %.1f / %.1f %s\n" % [relation.to, relation.affinity, relation.trust, relation.tension, _life_text(relation.stage)]
	detail.text = text
	# F4：事件文本只在 mechanics / receipts 数量变化时重建，不再每 0.3 秒遍历全部历史
	var mech: Array = snapshot.get("mechanics", [])
	var rcpt: Array = snapshot.get("receipts", [])
	var events_key := "%d|%d" % [mech.size(), rcpt.size()]
	if events_key != _events_key:
		_events_key = events_key
		var log_text := "Events and Outcomes\n"
		for event in mech:
			if event.Kind == "life_response":
				var response: Dictionary = event.Details
				log_text += "%s → %s · %s\n%s · %s\n\n" % [response.requester, response.responder, _life_text(rules.social.categories[response.category].label), _life_text(rules.social.mode_labels[response.mode]), "Delivered" if response.delivered else "Pending"]
			elif event.Kind == "life_seating":
				log_text += "%s · Seating promise: %s\n\n" % [event.Details.requester, "Kept" if event.Success else "Expired"]
		for receipt in rcpt.slice(-8): log_text += "%s · %s\n" % [receipt.Actor, receipt.Reason]
		events.text = log_text
	if not status_text.is_empty(): status_label.text = status_text
	elif not audit.is_empty(): status_label.text = "Stock %.0f · Carried %.0f · Consumed %.0f · Total supply %.0f" % [audit.stock, audit.carried, audit.consumed, audit.supplied]

func _load_save(path: String) -> void:
	status_text = bridge.Load(path)
	if status_text.is_empty():
		rules = JSON.parse_string(bridge.Definition())
		_present_life(true)
		book_paused = true
		status_text = "Save restored. Simulation paused."
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
		_show_title()
		Sound.music("main_theme")

func can_save() -> bool:
	return active and bridge != null

func journal() -> Dictionary:
	if bridge == null: return {}
	return JSON.parse_string(bridge.Journal(selected))

func journal_actions() -> Array:
	for actor in snapshot.get("actors", []):
		if actor.id == selected: return actor.choices.map(func(choice): return {"id": choice.id, "label": _life_text(choice.label)})
	return []

func journal_submit(action: String) -> void:
	status_text = bridge.Submit(selected, action)

func journal_save_note(title: String, text: String, related: String, judgement: String, identity: String) -> String:
	return bridge.SaveNote(selected, title, text, related, judgement, identity)

func save_slots() -> Array:
	var slots: Array = []
	var auto_path := _auto_path()
	slots.append(_slot_summary("auto", "Autosave", auto_path))
	for index in range(1, 7):
		var path := _slot_path(str(index))
		slots.append(_slot_summary(str(index), "Slot %d" % index, path))
	return slots

func _slot_summary(id: String, label: String, path: String) -> Dictionary:
	var exists := FileAccess.file_exists(path)
	var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(path)) if exists else null
	var minute := float(data.get("game_time", 0.0)) if data is Dictionary else 0.0
	return {"id":id, "label":label, "kind":"auto" if id == "auto" else "manual", "exists":exists, "saved_at":FileAccess.get_modified_time(path) if exists else 0, "place":"Life Simulation" if exists else "—", "game_time":"Day %d %02d:%02d" % [int(minute / 1440) + 1, int(minute) % 1440 / 60, int(minute) % 60] if exists else "—"}

func save_to_slot(id: String) -> String:
	if id == "auto": return "The simulation writes the autosave."
	if not id.is_valid_int() or int(id) < 1 or int(id) > 6: return "Invalid save slot."
	return bridge.Save(_slot_path(id))

func load_slot(id: String) -> String:
	if id != "auto" and (not id.is_valid_int() or int(id) < 1 or int(id) > 6): return "Invalid save slot."
	var path := _auto_path() if id == "auto" else _slot_path(id)
	if not FileAccess.file_exists(path): return "This save could not be read."
	_load_save(path)
	return "" if status_text == "Save restored. Simulation paused." else status_text

func delete_slot(id: String) -> String:
	if id == "auto": return "The autosave cannot be deleted."
	if not id.is_valid_int() or int(id) < 1 or int(id) > 6: return "Invalid save slot."
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
	if is_instance_valid(dual_world) and dual_world.has_method("mcp_observe"):
		return dual_world.mcp_observe()
	if is_instance_valid(campaign_panel) and campaign_panel.visible: return campaign_panel.observation()
	var result := {"started": active, "state": snapshot if active else {"active": true, "campaign_completed": false}, "faulted": not str(snapshot.get("error", "")).is_empty(), "host_errors": [], "ui": {"paused": paused, "speed": speed, "status": status_text}}
	if is_instance_valid(builder):
		result["authored_scene"] = builder.state.data.duplicate(true)
		result["selection"] = builder.state.selected.duplicate(true)
		result["blueprint"] = {"pan": builder.blueprint.pan, "zoom": builder.blueprint.zoom}
	return result
