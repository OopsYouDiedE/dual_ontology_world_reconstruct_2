extends RefCounted
## Optional scheduling-only trace. This records no cue name or story context.
static func record(category: String) -> void:
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null: return
	var monitor := tree.get_first_node_in_group("runtime_audio_cue_monitor")
	if monitor != null and monitor.has_method("record_audio_cue"):
		monitor.call("record_audio_cue", category)
