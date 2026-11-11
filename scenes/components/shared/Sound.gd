extends RefCounted

const LIFECYCLE := preload("res://scenes/components/shared/HostLifecycle.gd")
## 配乐与音效的静态入口：转给自动加载的 GameAudio；它不在时（无头检查脚本）什么也不做。

static func _hub() -> Node:
	var tree := Engine.get_main_loop() as SceneTree
	return tree.root.get_node_or_null("GameAudio") if tree else null

static func music(id: String, fade := 1.6) -> void:
	var hub := _hub()
	if hub:
		hub.play_music(id, fade)

static func scene_music(snapshot: Dictionary) -> void:
	var hub := _hub()
	if hub: hub.apply_music_scene(snapshot)

static func begin_presentation_music(presentation: Dictionary) -> int:
	var hub := _hub()
	return int(hub.begin_presentation_music(presentation)) if hub else 0

static func end_presentation_music(token: int) -> void:
	var hub := _hub()
	if hub: hub.end_presentation_music(token)

static func stop_music(fade := 1.6) -> void:
	var hub := _hub()
	if hub:
		hub.stop_music(fade)

static func duck(on: bool) -> void:
	var hub := _hub()
	if hub:
		hub.duck(on)

static func sfx(id: String, volume_db := 0.0, pitch := 1.0) -> void:
	var hub := _hub()
	if hub:
		hub.play_sfx(id, volume_db, pitch)

static func release_audio() -> void:
	var hub := _hub()
	if hub: hub.release_audio()

static func quit_cleanly(exit_code := 0) -> void:
	await LIFECYCLE.quit(Engine.get_main_loop() as SceneTree, exit_code)
