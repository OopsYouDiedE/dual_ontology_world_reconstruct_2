@tool
class_name LevelTrigger3D
extends "res://scenes/components/structure/StructurePiece3D.gd"
## A level trigger: a box zone (or an E-key interaction) that runs its `actions` in order
## (set / animate properties, play animations, call methods, drive movers, send level
## events and dialogue). Place and resize it in 3D or in the plan tab; it is listed in the
## level manifest (id / how / condition / effect / dialogue) and the F2 blueprint, and the
## level hears it through AcademyLevelBase._on_level_action(action_id) and
## LevelStructure3D.trigger_fired.

const Interactable := preload("res://scenes/components/interaction/AcademyInteractable.gd")

signal fired(trigger: Node, ctx: Dictionary)

enum How { ZONE_ENTER, ZONE_EXIT, INTERACT, ON_READY, MANUAL }
const HOW_TEXT := ["进入区域自动触发", "离开区域触发", "按 E 交互触发", "关卡开始时触发", "由脚本或其他触发器触发"]

@export var trigger_id := "":
	set(v): trigger_id = v; mesh_changed()
@export var how: How = How.ZONE_ENTER:
	set(v): how = v; mesh_changed()
## Box size (x, height, z); the zone sits on the node origin.
@export var size := Vector3(2, 2, 2):
	set(v): size = Vector3(maxf(0.1, v.x), maxf(0.1, v.y), maxf(0.1, v.z)); shape_changed()
## Bodies in this group fire the zone (empty = any body).
@export var body_group := "player"
@export var once := true
@export var enabled := true
@export var actions: Array[LevelAction] = []
@export_group("Manifest")
## Shown in the level manifest / F2 blueprint (design notes, checked by the level audit).
@export var condition := ""
@export var effect := ""
## Sent to AcademyLevelBase._on_level_action when the trigger fires (optional).
@export var action_id := ""
## Declared dialogue line played when the trigger fires (optional).
@export var dialogue_id := ""
@export_group("Interaction")
@export var title_zh := ""
@export var title_en := ""
@export var verb_zh := "调查"
@export var verb_en := "Inspect"

var fire_count := 0
var _running := false

func plan_kind() -> String:
	return "trigger"

func shape_key() -> Array:
	return [size]

func plan_outline() -> PackedVector2Array:
	var h := Vector2(size.x, size.z) * 0.5
	return PackedVector2Array([to_plan(Vector3(-h.x, 0, -h.y)), to_plan(Vector3(h.x, 0, -h.y)), to_plan(Vector3(h.x, 0, h.y)), to_plan(Vector3(-h.x, 0, h.y))])

func plan_handles() -> Array:
	return [{"id": &"corner", "position": to_plan(Vector3(size.x * 0.5, 0, size.z * 0.5))}]

func set_plan_handle(_id: StringName, plan_position: Vector2) -> void:
	var local := from_plan(plan_position)
	var anchor := Vector2(-size.x * 0.5, -size.z * 0.5)
	var extent := (Vector2(local.x, local.z) - anchor).abs()
	var centre := anchor + extent * 0.5
	position += transform.basis * Vector3(centre.x, 0, centre.y)
	size = Vector3(maxf(0.1, extent.x), size.y, maxf(0.1, extent.y))

func resolved_id() -> String:
	return trigger_id if trigger_id != "" else str(name)

## Level manifest entry (AcademyLevelAudit trigger schema).
func manifest_entry() -> Dictionary:
	var notes: Array = actions.filter(func(a): return a != null).map(func(a): return a.describe())
	return {"id": resolved_id(), "how": HOW_TEXT[how], "source_id": str(name), "condition": condition,
		"dialogue_id": dialogue_id, "effect": effect if effect != "" else "；".join(notes), "action_id": action_id}

func rebuild() -> void:
	for child in get_children():
		if is_generated(child):
			remove_child(child)
			child.queue_free()
	if how in [How.ZONE_ENTER, How.ZONE_EXIT]:
		var area := Area3D.new()
		area.name = "Zone"
		area.monitorable = false
		area.monitoring = not Engine.is_editor_hint()
		var col := CollisionShape3D.new()
		var box := BoxShape3D.new()
		box.size = size
		col.shape = box
		col.position = Vector3(0, size.y * 0.5, 0)
		area.add_child(col)
		add_child(area)
		if not Engine.is_editor_hint():
			if how == How.ZONE_ENTER:
				area.body_entered.connect(_on_body.bind(true))
			else:
				area.body_exited.connect(_on_body.bind(false))
	if how == How.INTERACT and not Engine.is_editor_hint():
		var it := Interactable.attach_to(self, {"id": resolved_id(), "title_zh": title_zh, "title_en": title_en,
			"verb_zh": verb_zh, "verb_en": verb_en, "action_id": action_id, "anchor_offset": Vector3(0, size.y * 0.5, 0)})
		it.activated.connect(func(_h, _a): fire({"via": "interact"}))
	if Engine.is_editor_hint():
		var mesh := BoxMesh.new()
		mesh.size = size
		var mat := StandardMaterial3D.new()
		mat.albedo_color = Color(0.3, 0.95, 0.55, 0.18) if how != How.INTERACT else Color(0.35, 0.7, 1.0, 0.2)
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mat.cull_mode = BaseMaterial3D.CULL_DISABLED
		mesh.material = mat
		var box := MeshInstance3D.new()
		box.name = "EditorZone"
		box.mesh = mesh
		box.position = Vector3(0, size.y * 0.5, 0)
		add_child(box)
		var tag := Label3D.new()
		tag.name = "EditorTag"
		tag.text = "%s · %s" % [resolved_id(), HOW_TEXT[how]]
		tag.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		tag.no_depth_test = true
		tag.pixel_size = 0.004
		tag.position = Vector3(0, size.y + 0.25, 0)
		add_child(tag)

func _ready() -> void:
	super._ready()
	if how == How.ON_READY and not Engine.is_editor_hint():
		fire.call_deferred({"via": "ready"})

func _on_body(body: Node, entering: bool) -> void:
	if body_group != "" and not body.is_in_group(body_group):
		return
	fire({"via": "enter" if entering else "exit", "body": body})

## Run the actions (also callable from scripts and from other triggers' CallMethodAction).
func fire(ctx: Dictionary = {}) -> void:
	if not enabled or _running or (once and fire_count > 0):
		return
	fire_count += 1
	_running = true
	ctx["trigger_id"] = resolved_id()
	fired.emit(self, ctx)
	var level := LevelAction.level_of(self)
	var structure := scope()
	if structure != null and structure.has_signal(&"trigger_fired"):
		structure.trigger_fired.emit(resolved_id(), action_id, ctx)
	if level != null:
		if action_id != "":
			level._on_level_action(action_id, ctx)
		if dialogue_id != "" and level.has_method("play_dialogue"):
			level.play_dialogue(dialogue_id)
	for step in actions:
		if step == null:
			continue
		if step.delay > 0.0 and is_inside_tree():
			await get_tree().create_timer(step.delay).timeout
		await step.run(self, ctx)
	_running = false

func reset() -> void:
	fire_count = 0
