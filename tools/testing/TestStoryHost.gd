extends "res://scenes/dual_world/DualWorldMain.gd"
## The production scene implementation with an isolated, explicit test-state boundary.
const Scenario := preload("res://scenes/components/testing/ScenarioLoader.gd")
const Ceiling := preload("res://scenes/components/world/ShadowCeiling.gd")
const CaptureSource := preload("res://mcp/CaptureSource.gd")
var fixture: RefCounted
var fixture_directory := ""
var fixture_error := ""
var fixture_initial_state: Dictionary = {}
var _fixture_room := ""

func _ready() -> void:
	if fixture == null:
		fixture_error = "Missing scenario configuration"
		return
	show_intro = str(fixture.configuration.get("entry", "exploration")) == "wake"
	instant_story = false
	resume_path = ""
	super._ready()

func _load_designs() -> void:
	# Never read the player's design or campaign saves in a fixture session.
	designs.clear()
	fixture_initial_state = fixture.state_for(eng)
	if fixture_initial_state.is_empty():
		fixture_error = fixture.error
		return
	eng.load_dict(fixture_initial_state.duplicate(true))

func _start_opening() -> void:
	if fixture_error != "": return
	var entry := str(fixture.configuration.get("entry", "exploration"))
	if entry == "wake":
		super._start_opening()
		if opening == null: fixture_error = "Wake entry requires the initial R05 bed state"
	elif str(eng.s.room) == "B-P":
		start_kitchen_exploration()
	elif str(eng.s.room) == "R05":
		# Enter the very same free-exploration presentation without replaying the opening.
		var position_before := det.position
		det.set_pose("lie")
		show_intro = true
		super._start_opening()
		if opening != null:
			det.set_pose("stand")
			det.position = Vector3(position_before.x, 0.0, position_before.z)
			opening._enter("free")
			opening._snap_camera()
			fade_rect.modulate.a = 0.0
		eng.s.playing = bool(fixture.configuration.get("playing", false))
	else:
		# Other configured rooms retain their production room renderer and controls.
		eng.s.playing = bool(fixture.configuration.get("playing", false))
	_apply_fixture_environment()

func _process(delta: float) -> void:
	if fixture_error != "" or eng == null: return
	super._process(delta)
	_apply_fixture_environment()

func _apply_fixture_environment() -> void:
	if room_mesh == null: return
	if _fixture_room != str(eng.s.room):
		_fixture_room = str(eng.s.room)
		var bounds: Rect2 = lowpoly.walk_rect(0.0) if _lowpoly_ok else Rect2(0, 0, float(room_mesh.design.w), float(room_mesh.design.d))
		Ceiling.install(room_mesh, Vector3(bounds.get_center().x, 0, bounds.get_center().y), bounds.size)
	if str(fixture.configuration.get("weather", "clear")) == "fog" and env != null:
		env.fog_enabled = true
		env.fog_density = 0.055
		env.fog_light_color = Color("#b2bbc0")
		if sun != null: sun.light_energy = float(DayNight.lighting(eng.clock().hour).sun_energy) * 0.45

func _save_design() -> void:
	if editor == null or editor.design.is_empty(): return
	designs[editor.design.room_id] = editor.design.duplicate(true)
	_write_fixture("designs.json", designs)

func _write_save(path: String) -> void:
	_write_fixture(path.get_file(), eng.save_dict())

func _read_save(path: String) -> bool:
	var isolated := CaptureSource.project_output(fixture_directory + "/saves/" + path.get_file())
	return super._read_save(isolated) if not isolated.is_empty() else false

func _load_game(slot: int) -> void:
	if _read_save(slot_save_path(slot)): _toast("已读取测试槽位 %d" % slot)
	else: _toast("测试槽位为空")

func _write_fixture(filename: String, value: Dictionary) -> void:
	var isolated := CaptureSource.project_output(fixture_directory + "/saves/" + filename)
	if isolated.is_empty(): return
	DirAccess.make_dir_recursive_absolute(isolated.get_base_dir())
	var file := FileAccess.open(isolated, FileAccess.WRITE)
	if file != null: file.store_string(JSON.stringify(value)); file.close()

func test_snapshot() -> Dictionary:
	var result := {"room": eng.s.room, "clock": eng.clock(), "mock": true, "entry": fixture.configuration.get("entry", "exploration"), "isolated_save_directory": fixture_directory + "/saves"}
	if opening != null: result["opening_phase"] = opening.phase
	if kitchen != null: result["kitchen_phase"] = kitchen.phase
	var targets: Array = []
	var items: Array = kitchen._items if kitchen != null and kitchen.active else opening._items if opening != null and opening.active else []
	for item in items:
		var marker: Node3D = item.marker
		if not marker.is_visible_in_tree() or cam.is_position_behind(marker.global_position): continue
		var projected := cam.unproject_position(marker.global_position)
		var screen := room_container.get_global_rect().position + projected/Vector2(room_vp.size)*room_container.size
		targets.append({"id":item.id,"label":item.label,"x":screen.x,"y":screen.y})
	result["interaction_targets"] = targets
	if interactions != null and is_instance_valid(interactions.active): result["closeup"] = interactions.active.test_snapshot()
	result["collected_evidence"] = eng.s.evidence.keys()
	if kitchen != null and is_instance_valid(kitchen._order_replay): result["reconstruction"] = kitchen._order_replay.test_snapshot()
	return result
