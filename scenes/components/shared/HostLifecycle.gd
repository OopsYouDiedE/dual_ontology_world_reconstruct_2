extends RefCounted

static var _quitting := false

static func quit(tree: SceneTree, exit_code := 0) -> void:
	if _quitting: return
	_quitting = true
	var hosts := tree.get_nodes_in_group("lifecycle_hosts")
	for host: Node in hosts: host.begin_shutdown()
	for host: Node in hosts: await host.wait_for_shutdown()
	var audio := tree.root.get_node_or_null("GameAudio")
	var drained := true
	if audio != null: drained = await audio.release_audio_and_wait_for_mix()
	tree.quit(exit_code if drained or exit_code != 0 else 1)

## A replay surface owns its failure and its private host. Production failures
## still use the single draining/trace-sealing application exit.
static func binding_failure(node: Node, message: String) -> void:
	var owner := node
	while owner != null:
		if owner.has_meta("replay_surface"):
			owner.stop_with_error(message)
			return
		owner = owner.get_parent()
	await quit(node.get_tree(), 1)
