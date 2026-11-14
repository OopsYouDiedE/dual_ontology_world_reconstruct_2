extends RefCounted

const TRES_PATH := "res://.runtime/generated/animations/KayKitAnimationLibrary-v3.tres"

const CLIPS_CONFIG := {
	"res://assets/imported/kaykit/animations/Rig_Medium_General.glb": {
		"Idle_A": [{"name": "idle", "loop": Animation.LOOP_LINEAR}],
		"Idle_B": [{"name": "idle_b", "loop": Animation.LOOP_NONE}],
		"Interact": [
			{"name": "interact", "loop": Animation.LOOP_NONE},
			{"name": "talk", "loop": Animation.LOOP_LINEAR},
			{"name": "read_gauge", "loop": Animation.LOOP_NONE},
			{"name": "read_scroll", "loop": Animation.LOOP_NONE}
		],
		"PickUp": [{"name": "pickup", "loop": Animation.LOOP_NONE}],
		"Use_Item": [{"name": "eat", "loop": Animation.LOOP_NONE}]
	},
	"res://assets/imported/kaykit/animations/Rig_Medium_MovementBasic.glb": {
		"Walking_A": [{"name": "walk", "loop": Animation.LOOP_LINEAR}, {"name": "carry_walk", "loop": Animation.LOOP_LINEAR}],
		"Running_A": [{"name": "run", "loop": Animation.LOOP_LINEAR}]
	},
	"res://assets/imported/kaykit/animations/Rig_Medium_Simulation.glb": {
		"Waving": [{"name": "wave", "loop": Animation.LOOP_LINEAR}],
		"Sit_Chair_Down": [{"name": "sit_down", "loop": Animation.LOOP_NONE}],
		"Sit_Chair_Idle": [{"name": "sit_idle", "loop": Animation.LOOP_LINEAR}],
		"Sit_Chair_StandUp": [{"name": "stand_up", "loop": Animation.LOOP_NONE}],
		"Lie_Down": [{"name": "lie_down", "loop": Animation.LOOP_NONE}],
		"Lie_Idle": [{"name": "lie_idle", "loop": Animation.LOOP_LINEAR}],
		"Lie_StandUp": [{"name": "lie_stand_up", "loop": Animation.LOOP_NONE}]
	},
	"res://assets/imported/kaykit/animations/Rig_Medium_Tools.glb": {
		"Holding_A": [{"name": "carry_idle", "loop": Animation.LOOP_LINEAR}],
		"Work_A": [
			{"name": "operate", "loop": Animation.LOOP_NONE},
			{"name": "turn_wheel", "loop": Animation.LOOP_NONE}
		],
		"Working_A": [
			{"name": "work", "loop": Animation.LOOP_LINEAR},
			{"name": "work_loop", "loop": Animation.LOOP_LINEAR}
		],
		"Lockpick": [
			{"name": "lockpick", "loop": Animation.LOOP_NONE},
			{"name": "open_latch", "loop": Animation.LOOP_NONE}
		],
		"Lockpicking": [{"name": "lockpick_loop", "loop": Animation.LOOP_LINEAR}]
	}
}

static var _cached_library_ref: WeakRef = null

static func get_library() -> AnimationLibrary:
	if _cached_library_ref != null:
		var cached := _cached_library_ref.get_ref() as AnimationLibrary
		if _is_complete(cached):
			return cached
	if ResourceLoader.exists(TRES_PATH):
		var disk_lib := load(TRES_PATH) as AnimationLibrary
		if _is_complete(disk_lib):
			_cached_library_ref = weakref(disk_lib)
			return disk_lib
	var built := build_and_save_library()
	_cached_library_ref = weakref(built)
	return built

static func _is_complete(library: AnimationLibrary) -> bool:
	if library == null: return false
	for sources in CLIPS_CONFIG.values():
		for targets in sources.values():
			for target in targets:
				if not library.has_animation(str(target.name)): return false
				if library.get_animation(str(target.name)).loop_mode != int(target.loop): return false
	return true

static func build_and_save_library() -> AnimationLibrary:
	var lib := AnimationLibrary.new()
	for glb_path in CLIPS_CONFIG:
		if not ResourceLoader.exists(glb_path):
			push_warning("Animation GLB not found: " + glb_path)
			continue
		var packed := load(glb_path) as PackedScene
		if packed == null: continue
		var inst := packed.instantiate()
		var player := _find_player(inst)
		if player != null:
			var clip_map: Dictionary = CLIPS_CONFIG[glb_path]
			for src_name in clip_map:
				var target_list: Array = clip_map[src_name]
				if player.has_animation(src_name):
					var base_anim: Animation = player.get_animation(src_name)
					for target_meta in target_list:
						var target_name: String = target_meta.name
						var loop_mode: int = int(target_meta.loop)
						var anim: Animation = base_anim.duplicate(true)
						anim.loop_mode = loop_mode
						lib.add_animation(target_name, anim)
		inst.free()
	if lib.get_animation_list().size() > 0:
		DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(TRES_PATH.get_base_dir()))
		ResourceSaver.save(lib, TRES_PATH)
	return lib

static func _find_player(node: Node) -> AnimationPlayer:
	if node is AnimationPlayer: return node
	for child in node.get_children():
		var found := _find_player(child)
		if found != null: return found
	return null
