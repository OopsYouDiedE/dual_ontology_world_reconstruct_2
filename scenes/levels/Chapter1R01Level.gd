extends "res://scenes/components/shared/AcademyLevelBase.gd"
class_name Chapter1R01Level
## Reference Chapter 1 room (`R-01 北翼编号门廊与二层海侧侧廊`) built strictly on AcademyLevelBase.
## Demonstrates zero-boilerplate declarative authoring: objects, interactables, triggers,
## dialogues (epistemic-firewall safe), and Hale's AI route (H2/H5 + Rule-04 telegraph).

var _cam: Camera3D

func define_level_manifest() -> Dictionary:
	return {
		"level_id": "chapter1_r01_corridor",
		"title": "R-01 · 北翼编号门廊与二层海侧侧廊",
		"allow_deep_lore": false,
		"capabilities": LevelPipeline.capabilities_expedition(),
		"objects": [
			{"id": "r01_bench_w", "kind": "recipe", "catalog_id": "bench", "pos": Vector3(-2.4, 0.0, -3.5), "yaw": PI * 0.5, "params": {"width": 2.2}, "zone": "门廊西侧"},
			{"id": "r01_desk_guard", "kind": "recipe", "catalog_id": "reception_desk", "pos": Vector3(2.3, 0.0, -4.8), "yaw": -PI * 0.5, "params": {"width": 1.6}, "zone": "编号登记台"},
			{"id": "r01_lamp_desk", "kind": "recipe", "catalog_id": "banker_lamp", "pos": Vector3(2.3, 1.08, -4.5), "yaw": 0.0, "params": {"light_energy": 1.2}, "zone": "编号登记台"},
			{"id": "r01_shelf_n", "kind": "recipe", "catalog_id": "bookshelf", "pos": Vector3(-2.6, 0.0, -8.2), "yaw": PI * 0.5, "params": {"width": 2.0, "bays": 2, "shelves": 4}, "zone": "北端门牌柜"},
			{"id": "r01_table_side", "kind": "glb", "catalog_id": "manor_table_long", "pos": Vector3(2.4, 0.0, -8.6), "yaw": PI * 0.5, "scale": 0.76, "zone": "海侧窗台旁"},
			{"id": "r01_candle", "kind": "glb", "catalog_id": "brass_candle_triple", "pos": Vector3(2.4, 0.74, -8.6), "yaw": 0.2, "scale": 0.65, "zone": "海侧窗台旁"},
			# Catalog item made selectable with its catalog default (Search chest) + a level dialogue.
			{"id": "r01_supply_chest", "kind": "glb", "catalog_id": "manor_chest", "pos": Vector3(-2.3, 0.0, -6.2), "yaw": PI * 0.5, "scale": 0.8, "zone": "门廊西侧",
				"interaction": {"from_catalog": true, "action_id": "search_supply_chest", "dialogue_id": "dlg_chest_supplies"}},
		],
		"interactables": [
			{
				"id": "r01_logbook",
				"title": "北翼编号登记簿",
				"anchor_world": Vector3(2.3, 1.12, -4.8),
				"hotspots": [
					{
						"id": "r01_log_read",
						"part_name": "登记簿",
						"verb": "核对通道编号",
						"world_pos": Vector3(2.3, 1.12, -4.8),
						"action_id": "read_corridor_log",
						"dialogue_id": "dlg_log_read",
					},
				],
			},
			{
				"id": "r01_drifted_letter",
				"title": "窗台湿咸信件",
				"anchor_world": Vector3(2.4, 0.85, -8.6),
				"hotspots": [
					{
						"id": "r01_letter_inspect",
						"part_name": "陌生邮戳信件",
						"verb": "俯身观察（勿徒手收起）",
						"world_pos": Vector3(2.4, 0.85, -8.6),
						"action_id": "inspect_drifted_letter",
						"dialogue_id": "dlg_letter_salt",
					},
					{
						"id": "r01_letter_sweep",
						"part_name": "工具拨离",
						"verb": "用铜尺拨离主通道",
						"world_pos": Vector3(2.1, 0.82, -8.9),
						"action_id": "sweep_drifted_letter",
						"unlock_when": "letter_inspected",
						"dialogue_id": "dlg_hale_h5_nod",
					},
				],
			},
		],
		"triggers": [
			{"id": "trg_enter_r01", "how": "进入区域自动触发", "source_id": "r01_entry_zone", "condition": "首次跨过北门", "dialogue_id": "dlg_hale_entry", "effect": "启动霍铎沿门廊自主排查"},
			{"id": "trg_foghorn_h2", "how": "远海汽笛声事件", "source_id": "r01_sea_window", "condition": "霍铎行至海侧窗前", "dialogue_id": "dlg_hale_h2_turn", "effect": "霍铎立刻背对所有窗户（演示 H2）"},
			{"id": "trg_lantern_r04", "how": "无风室焰色倒伏前摇", "source_id": "r01_mist_pocket", "condition": "进入低洼雾囊且未拦截", "dialogue_id": "dlg_hale_r04_mistake", "effect": "4.0s 可视前摇：玩家按 Q/E 喊停并盖灭提灯"},
		],
		"dialogues": [
			{"id": "dlg_hale_entry", "speaker": "霍铎", "voice_profile": "hale", "text_zh": "门牌写着 N-01。记住编号，如果前面走廊长得一模一样，立刻原路退回这里。", "text_en": "Plaque says N-01. Remember the number—if the next corridor looks identical, back straight out."},
			{"id": "dlg_log_read", "speaker": "", "voice_profile": "resident", "text_zh": "登记簿记着正常编号序列：N-01 门廊 → N-02 下沉档案廊。墨迹干燥，没有撕页。", "text_en": "The log lists the numbered sequence: N-01 Porch -> N-02 Sunken Archive. Ink dry, no torn pages."},
			{"id": "dlg_letter_salt", "speaker": "", "voice_profile": "resident", "text_zh": "信封潮湿并带着浓重海盐味，邮戳日期竟是昨天——绝不能带回主楼。", "text_en": "The envelope is damp with sea salt and postmarked yesterday—do not bring this into the main hall."},
			{"id": "dlg_hale_h2_turn", "speaker": "霍铎", "voice_profile": "hale", "text_zh": "……汽笛声。别看窗户，低头等它过去。", "text_en": "...A foghorn. Don't look at the windows—keep your eyes down until it passes."},
			{"id": "dlg_hale_r04_mistake", "speaker": "霍铎", "voice_profile": "hale", "text_zh": "奇怪，这儿没风，提灯火苗怎么发白还往一边倒？我把灯芯拧大一点看看……", "text_en": "Odd—no draft here, yet the flame went pale and tilted. Let me turn the wick up a bit..."},
			{"id": "dlg_chest_supplies", "speaker": "", "voice_profile": "resident", "text_zh": "箱里只有几截受潮的蜡烛头和一卷麻绳，封条完好。", "text_en": "Only a few damp candle stubs and a coil of rope inside; the seal was intact."},
			{"id": "dlg_hale_h5_nod", "speaker": "霍铎", "voice_profile": "hale", "text_zh": "做得对，别徒手碰带海盐味和近日期的东西。我们可以往 N-02 走了。", "text_en": "Good call—never pocket anything damp with sea salt and a fresh date. Let's push on to N-02."},
		],
		"ai_routes": [
			{
				"actor_id": "hale",
				"actor_name": "霍铎 (Hale)",
				"role": "partner",
				"waypoints": [
					{"pos": Vector3(0.0, 0.0, -2.5), "action": "核对 N-01 门牌并停步等待", "rule_tag": "Rule-03", "foreshadow_sec": 0.0, "dialogue_id": "dlg_hale_entry"},
					{"pos": Vector3(1.2, 0.0, -5.2), "action": "闻汽笛声瞬间背对海侧廊窗", "rule_tag": "H2", "foreshadow_sec": 0.0, "dialogue_id": "dlg_hale_h2_turn"},
					{"pos": Vector3(0.6, 0.0, -7.8), "action": "提灯焰色发白倒伏，准备拧大灯芯（需玩家喊停）", "rule_tag": "Rule-04", "is_rule_mistake": true, "foreshadow_sec": 4.0, "dialogue_id": "dlg_hale_r04_mistake"},
					{"pos": Vector3(1.5, 0.0, -9.2), "action": "示意远离湿咸信件，准备转入 N-02", "rule_tag": "H5", "foreshadow_sec": 0.0, "dialogue_id": "dlg_hale_h5_nod"},
				],
			},
		],
	}

func _on_level_ready() -> void:
	# Minimal architectural corridor shell for standalone preview & inspection
	var floor_mesh := MeshInstance3D.new()
	var box := BoxMesh.new(); box.size = Vector3(7.0, 0.12, 14.0)
	floor_mesh.mesh = box
	floor_mesh.position = Vector3(0.0, -0.06, -5.5)
	floor_mesh.material_override = FurnitureCatalog.material("slate_honed")
	add_child(floor_mesh)

	for sx: float in [-3.4, 3.4]:
		var wall := MeshInstance3D.new()
		var wb := BoxMesh.new(); wb.size = Vector3(0.24, 4.2, 14.0)
		wall.mesh = wb
		wall.position = Vector3(sx, 2.1, -5.5)
		wall.material_override = FurnitureCatalog.material("oak_aged")
		add_child(wall)

	var light := OmniLight3D.new()
	light.position = Vector3(0.0, 3.3, -5.5)
	light.light_color = Color("ffdca8")
	light.light_energy = 2.4
	light.omni_range = 16.0
	add_child(light)

	_cam = Camera3D.new()
	_cam.fov = 73.0
	add_child(_cam)
	_cam.look_at_from_position(Vector3(0.0, 1.57, -1.2), Vector3(0.4, 1.0, -7.8), Vector3.UP)
	_cam.current = true

func get_level_camera() -> Camera3D:
	return _cam

func get_player_position() -> Vector3:
	return _cam.global_position if is_instance_valid(_cam) else Vector3.ZERO

func _on_level_action(action_id: String, _ctx: Dictionary) -> void:
	if action_id == "inspect_drifted_letter":
		unlocked_flags["letter_inspected"] = true
