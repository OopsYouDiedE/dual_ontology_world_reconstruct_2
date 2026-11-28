@tool
extends VBoxContainer
## The "平面" main-screen tab: the level structure seen from above. Every piece is drawn
## from its plan outline; drag pieces and their handles with grid and snap-point snapping,
## draw walls, floors, doors, windows, columns, arches, colonnades, stairs, triggers,
## stations, movers and anchors. The plan is only another view of the same nodes: every
## edit writes the nodes' exported values (undoable) and the 3D view rebuilds.
##
## Mouse: left = select / drag / draw · middle or right drag = pan · wheel = zoom
## Keys: V W F D N C A L S T B K M = tools · Del = delete · R / Shift+R = rotate 90°
##       Ctrl+D = duplicate · Ctrl+click = add / remove a vertex or opening · F = frame all
##       Esc = stop drawing · G = toggle snapping

const Ops := preload("res://addons/archbuilder/structure_ops.gd")
const Piece := preload("res://scenes/components/structure/StructurePiece3D.gd")
const Queue := preload("res://scenes/components/structure/StructureRebuildQueue.gd")
const ToolTheme := preload("res://tools/building_construction/ToolTheme.gd")

const TOOLS := [
	["select", "选择", KEY_V, "点选 / 框选 / 拖动构件与手柄"],
	["wall", "墙", KEY_W, "单击起点，再单击下一点连续画墙；Esc 结束"],
	["floor", "地面", KEY_F, "拖出矩形地面；Ctrl+单击边加顶点"],
	["door", "门", KEY_D, "单击墙体放一扇门（0.9 × 2.1 m）"],
	["window", "窗", KEY_N, "单击墙体放一扇窗（1.2 m，离地 0.9 m）"],
	["column", "柱", KEY_C, "单击放柱"],
	["arch", "拱", KEY_A, "单击两点放拱"],
	["colonnade", "柱廊", KEY_L, "单击两点放一排柱与拱"],
	["stair", "楼梯", KEY_S, "单击两点放楼梯（升高 3 m）"],
	["trigger", "触发器", KEY_T, "拖出触发区域"],
	["station", "站位", KEY_B, "拖出占位脚印"],
	["mover", "移动体", KEY_M, "拖出移动体（门、升降台）"],
	["anchor", "锚点", KEY_K, "单击放锚点"],
]
const COLORS := {
	"floor": [Color(0.27, 0.31, 0.37, 0.85), Color(0.45, 0.52, 0.6)],
	"wall": [Color(0.82, 0.84, 0.88), Color(0.95, 0.96, 0.98)],
	"column": [Color(0.78, 0.7, 0.56), Color(0.95, 0.86, 0.68)],
	"arch": [Color(0.55, 0.68, 0.82, 0.55), Color(0.7, 0.82, 0.95)],
	"stair": [Color(0.55, 0.47, 0.33, 0.8), Color(0.82, 0.7, 0.5)],
	"trigger": [Color(0.3, 0.95, 0.55, 0.14), Color(0.35, 0.95, 0.6)],
	"station": [Color(1.0, 0.55, 0.2, 0.18), Color(1.0, 0.62, 0.3)],
	"mover": [Color(0.7, 0.45, 1.0, 0.18), Color(0.78, 0.6, 1.0)],
	"assembly": [Color(0, 0, 0, 0), Color(0.55, 0.85, 0.95)],
	"piece": [Color(0.5, 0.56, 0.66, 0.35), Color(0.62, 0.68, 0.78)],
	"generic": [Color(0.6, 0.6, 0.6, 0.12), Color(0.6, 0.6, 0.6)],
}
const DRAW_ORDER := ["floor", "generic", "piece", "station", "stair", "assembly", "arch", "wall", "column", "mover", "trigger"]
const ACCENT := Color(1.0, 0.7, 0.28)

var plugin: EditorPlugin
var ops
var structure: Node3D
var canvas: Control
var status: Label
var grid_menu: OptionButton
var snap_box: CheckBox
var tool_buttons := {}
var tool := "select"
var zoom := 28.0
var pan := Vector2(60, 60)
var snap := true
var items: Array = []          # {node, kind, outline, area, handles, label}
var selected: Array = []
var hover: Object = null
var cursor := Vector2.ZERO     # plan space
var drag := {}
var chain = null               # wall / arch start point while drawing
var _dirty := true
var _last_rebuilds := -1
var _refresh_clock := 0.0
var _framed_for: Node = null

func setup(p: EditorPlugin, o) -> void:
	plugin = p
	ops = o

func _ready() -> void:
	name = "平面"
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	add_theme_constant_override("separation", 0)
	var bar := HBoxContainer.new()
	bar.add_theme_constant_override("separation", 2)
	add_child(bar)
	var group := ButtonGroup.new()
	for t in TOOLS:
		var b := Button.new()
		b.text = t[1]
		b.toggle_mode = true
		b.button_group = group
		b.tooltip_text = "%s（%s）\n%s" % [t[1], OS.get_keycode_string(t[2]), t[3]]
		b.focus_mode = Control.FOCUS_NONE
		b.pressed.connect(set_tool.bind(t[0]))
		bar.add_child(b)
		tool_buttons[t[0]] = b
	tool_buttons["select"].button_pressed = true
	bar.add_child(VSeparator.new())
	var gl := Label.new()
	gl.text = "网格"
	bar.add_child(gl)
	grid_menu = OptionButton.new()
	for g in [0.05, 0.1, 0.25, 0.5, 1.0]:
		grid_menu.add_item("%s m" % str(g))
		grid_menu.set_item_metadata(grid_menu.item_count - 1, g)
	grid_menu.select(2)
	grid_menu.focus_mode = Control.FOCUS_NONE
	grid_menu.item_selected.connect(func(i):
		if structure:
			structure.editor_grid = float(grid_menu.get_item_metadata(i))
		canvas.queue_redraw())
	bar.add_child(grid_menu)
	snap_box = CheckBox.new()
	snap_box.text = "吸附"
	snap_box.button_pressed = true
	snap_box.focus_mode = Control.FOCUS_NONE
	snap_box.toggled.connect(func(on): snap = on)
	bar.add_child(snap_box)
	var frame := Button.new()
	frame.text = "全部"
	frame.tooltip_text = "缩放到整个结构（F）"
	frame.focus_mode = Control.FOCUS_NONE
	frame.pressed.connect(frame_all)
	bar.add_child(frame)
	canvas = Control.new()
	canvas.name = "PlanCanvas"
	canvas.size_flags_vertical = Control.SIZE_EXPAND_FILL
	canvas.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	canvas.clip_contents = true
	canvas.focus_mode = Control.FOCUS_ALL
	canvas.mouse_default_cursor_shape = Control.CURSOR_CROSS
	canvas.draw.connect(_draw_canvas)
	canvas.gui_input.connect(_canvas_input)
	canvas.mouse_exited.connect(func(): hover = null; canvas.queue_redraw())
	add_child(canvas)
	status = Label.new()
	status.add_theme_color_override("font_color", ToolTheme.MUTED)
	status.add_theme_font_size_override("font_size", 12)
	add_child(status)
	EditorInterface.get_selection().selection_changed.connect(_from_editor_selection)

func _exit_tree() -> void:
	var sel := EditorInterface.get_selection()
	if sel.selection_changed.is_connected(_from_editor_selection):
		sel.selection_changed.disconnect(_from_editor_selection)

func set_tool(id: String) -> void:
	tool = id
	chain = null
	drag = {}
	if tool_buttons.has(id):
		tool_buttons[id].set_pressed_no_signal(true)
	_update_status()
	canvas.queue_redraw()

func mark_dirty() -> void:
	_dirty = true

func _process(delta: float) -> void:
	if not is_visible_in_tree():
		return
	_refresh_clock += delta
	var rebuilds := int(Queue.stats.get("rebuilds", 0))
	if rebuilds != _last_rebuilds or _refresh_clock > 0.6:
		_last_rebuilds = rebuilds
		_refresh_clock = 0.0
		_dirty = true
	if _dirty and drag.is_empty():
		_dirty = false
		refresh()

# ── data ──────────────────────────────────────────────────────────────────────

func refresh() -> void:
	var root := EditorInterface.get_edited_scene_root()
	var found: Node3D = null
	if root != null:
		for node in EditorInterface.get_selection().get_selected_nodes():
			var n: Node = node
			while n != null and found == null:
				if n is LevelStructure3D:
					found = n
				n = n.get_parent()
		if found == null:
			found = root if root is LevelStructure3D else null
		if found == null:
			var list := root.find_children("*", "LevelStructure3D", true, true)
			found = list[0] if not list.is_empty() else null
	structure = found
	if structure != null and _framed_for != structure:
		_framed_for = structure
		var g := float(structure.editor_grid)
		for i in grid_menu.item_count:
			if is_equal_approx(float(grid_menu.get_item_metadata(i)), g):
				grid_menu.select(i)
		_collect()
		frame_all()
	else:
		_collect()
	selected = selected.filter(func(n): return is_instance_valid(n) and n.is_inside_tree())
	_update_status()
	canvas.queue_redraw()

func grid() -> float:
	return float(structure.editor_grid) if structure != null and float(structure.editor_grid) > 0.0 else 0.25

func _authored(n: Node) -> bool:
	var root := EditorInterface.get_edited_scene_root()
	return n.owner != null and not n.has_meta(Piece.GENERATED_META) and (n.owner == root or root.is_editable_instance(n.owner) or n.owner == structure)

func _collect() -> void:
	items.clear()
	if structure == null:
		return
	for n in structure.find_children("*", "Node3D", true, false):
		if not _authored(n):
			continue
		var item := {"node": n, "handles": [], "label": ""}
		if n is LevelAnchor3D:
			var p: Vector2 = _plan_of(n)
			var r := 0.22
			item.kind = "anchor"
			item.outline = PackedVector2Array([p + Vector2(0, -r), p + Vector2(r, 0), p + Vector2(0, r), p + Vector2(-r, 0)])
			item.label = n.anchor_id if n.anchor_id != "" else n.role
		elif n.has_method("plan_outline") and n.has_method("plan_kind"):
			if _inside_scope(n):
				item.kind = n.plan_kind()
				item.outline = n.plan_outline()
				item.handles = n.plan_handles()
				if item.kind == "trigger":
					item.label = n.resolved_id()
			else:
				continue
		elif (n.get_script() != null or n is VisualInstance3D) and not _has_authored_children(n):
			item.kind = "generic"
			item.outline = _generic_outline(n)
			item.label = n.name
		else:
			continue
		if item.outline.size() >= 3:
			item.area = absf(_area(item.outline))
		else:
			item.area = 0.01
		if not COLORS.has(item.kind) and item.kind != "anchor":
			item.kind = "piece"
		items.append(item)

func _inside_scope(n: Node) -> bool:
	return n.scope() == structure

func _has_authored_children(n: Node) -> bool:
	for c in n.get_children():
		if c is Node3D and _authored(c):
			return true
	return false

func _plan_of(n: Node3D) -> Vector2:
	var o := Ops.relative(structure, n).origin
	return Vector2(o.x, o.z)

## Plan footprint of a non-piece node: its visual bounds (generated meshes included).
func _generic_outline(n: Node3D) -> PackedVector2Array:
	var inv := structure.global_transform.affine_inverse()
	var box := AABB()
	var first := true
	var list: Array = [n] + n.find_children("*", "VisualInstance3D", true, false)
	for vi in list:
		if not (vi is VisualInstance3D) or not vi.is_inside_tree():
			continue
		var a: AABB = vi.get_aabb()
		if a.size == Vector3.ZERO:
			continue
		var xf: Transform3D = inv * vi.global_transform
		for k in 8:
			var p: Vector3 = xf * a.get_endpoint(k)
			if first:
				box = AABB(p, Vector3.ZERO)
				first = false
			else:
				box = box.expand(p)
	if first:
		var c := _plan_of(n)
		return PackedVector2Array([c + Vector2(-0.2, -0.2), c + Vector2(0.2, -0.2), c + Vector2(0.2, 0.2), c + Vector2(-0.2, 0.2)])
	return PackedVector2Array([Vector2(box.position.x, box.position.z), Vector2(box.end.x, box.position.z), Vector2(box.end.x, box.end.z), Vector2(box.position.x, box.end.z)])

static func _area(poly: PackedVector2Array) -> float:
	var a := 0.0
	for i in poly.size():
		var p := poly[i]
		var q := poly[(i + 1) % poly.size()]
		a += p.x * q.y - q.x * p.y
	return a * 0.5

func _item_of(node: Object) -> Dictionary:
	for it in items:
		if it.node == node:
			return it
	return {}

# ── coordinates & snapping ────────────────────────────────────────────────────

func to_screen(p: Vector2) -> Vector2:
	return pan + p * zoom

func to_plan(s: Vector2) -> Vector2:
	return (s - pan) / zoom

func snap_targets(exclude: Array) -> PackedVector2Array:
	var out := PackedVector2Array()
	for it in items:
		if it.node in exclude:
			continue
		if it.node.has_method("snap_targets"):
			out.append_array(it.node.snap_targets())
		elif it.kind == "anchor":
			out.append(_plan_of(it.node))
	return out

## Snap a plan point: snap points within 10 px win, else the grid.
func _snap_plan(p: Vector2, exclude: Array = []) -> Vector2:
	if not snap or Input.is_key_pressed(KEY_ALT):
		return p
	return Piece.snap_point(p, grid(), snap_targets(exclude), 10.0 / zoom)

func frame_all() -> void:
	if items.is_empty() or canvas.size.x < 10:
		return
	var box := Rect2()
	var first := true
	for it in items:
		for p in it.outline:
			box = Rect2(p, Vector2.ZERO) if first else box.expand(p)
			first = false
	if first:
		return
	box = box.grow(1.0)
	zoom = clampf(minf(canvas.size.x / box.size.x, canvas.size.y / box.size.y), 2.0, 400.0)
	pan = canvas.size * 0.5 - box.get_center() * zoom
	canvas.queue_redraw()

# ── selection ─────────────────────────────────────────────────────────────────

func _pick(s: Vector2) -> Dictionary:
	var p := to_plan(s)
	var best := {}
	var best_area := INF
	for it in items:
		var hit := false
		if it.kind == "anchor":
			hit = to_screen(_plan_of(it.node)).distance_to(s) < 9.0
			if hit:
				return it
		elif it.outline.size() >= 3:
			hit = Geometry2D.is_point_in_polygon(p, it.outline)
		if hit and it.area < best_area:
			best_area = it.area
			best = it
	return best

func _pick_handle(s: Vector2) -> Dictionary:
	for node in selected:
		var it := _item_of(node)
		if it.is_empty():
			continue
		for h in it.handles:
			if to_screen(h.position).distance_to(s) < 8.0:
				return {"node": node, "id": h.id, "position": h.position}
	return {}

func _select(nodes: Array, additive := false) -> void:
	if additive:
		for n in nodes:
			if n in selected:
				selected.erase(n)
			else:
				selected.append(n)
	else:
		selected = nodes.duplicate()
	var sel := EditorInterface.get_selection()
	sel.selection_changed.disconnect(_from_editor_selection)
	sel.clear()
	for n in selected:
		sel.add_node(n)
	if not selected.is_empty():
		EditorInterface.edit_node(selected[-1])
	sel.selection_changed.connect(_from_editor_selection)
	canvas.queue_redraw()

func _from_editor_selection() -> void:
	var picked: Array = []
	for n in EditorInterface.get_selection().get_selected_nodes():
		picked.append(n)
	selected = picked
	if is_visible_in_tree():
		_dirty = true
		canvas.queue_redraw()

# ── input ─────────────────────────────────────────────────────────────────────

func _canvas_input(event: InputEvent) -> void:
	if structure == null:
		return
	if event is InputEventMouseMotion:
		cursor = to_plan(event.position)
		if drag.get("mode") == "pan":
			pan += event.relative
		elif drag.get("mode") == "handle":
			var p := _snap_plan(to_plan(event.position), [drag.node])
			drag.node.set_plan_handle(drag.id, p)
			_collect()
		elif drag.get("mode") == "move":
			var raw: Vector2 = drag.ref + (to_plan(event.position) - drag.start)
			var target := _snap_plan(raw, drag.nodes)
			var d: Vector2 = target - drag.ref - drag.applied
			if d != Vector2.ZERO:
				for n in drag.nodes:
					Ops.move_plan(structure, n, d)
				drag.applied += d
				_collect()
		else:
			var h := _pick(event.position)
			hover = h.get("node")
		_update_status()
		canvas.queue_redraw()
	elif event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_WHEEL_UP or mb.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			if mb.pressed:
				var before := to_plan(mb.position)
				zoom = clampf(zoom * (1.15 if mb.button_index == MOUSE_BUTTON_WHEEL_UP else 1.0 / 1.15), 2.0, 400.0)
				pan = mb.position - before * zoom
				canvas.queue_redraw()
			canvas.accept_event()
			return
		if mb.button_index in [MOUSE_BUTTON_MIDDLE, MOUSE_BUTTON_RIGHT]:
			if mb.pressed:
				if mb.button_index == MOUSE_BUTTON_RIGHT and chain != null:
					chain = null
					canvas.queue_redraw()
				else:
					drag = {"mode": "pan"}
			else:
				drag = {}
			canvas.accept_event()
			return
		if mb.button_index == MOUSE_BUTTON_LEFT:
			canvas.grab_focus()
			if mb.pressed:
				_press(mb)
			else:
				_release(mb)
			canvas.accept_event()
	elif event is InputEventKey and event.pressed and not event.echo:
		_key(event)

func _press(mb: InputEventMouseButton) -> void:
	var p := to_plan(mb.position)
	match tool:
		"select":
			var h := _pick_handle(mb.position)
			if mb.ctrl_pressed:
				_ctrl_click(mb.position, h)
				return
			if not h.is_empty():
				drag = {"mode": "handle", "node": h.node, "id": h.id, "before": [Ops.snapshot(h.node)]}
				return
			var it := _pick(mb.position)
			if it.is_empty():
				if not mb.shift_pressed:
					_select([])
				drag = {"mode": "box", "start": p}
				return
			if not (it.node in selected):
				_select([it.node], mb.shift_pressed)
			elif mb.shift_pressed:
				_select([it.node], true)
				return
			var ref := p
			if not it.handles.is_empty():
				ref = it.handles[0].position
			elif it.node is Node3D:
				ref = _plan_of(it.node)
			drag = {"mode": "move", "nodes": selected.duplicate(), "start": p, "ref": ref, "applied": Vector2.ZERO,
				"before": selected.map(func(n): return Ops.snapshot(n))}
		"wall", "arch", "colonnade", "stair":
			var q := _snap_plan(p)
			if chain == null:
				chain = q
			elif q.distance_to(chain) > 0.05:
				var made: Node3D
				match tool:
					"wall": made = ops.add_wall(structure, chain, q)
					"arch": made = ops.add_arch(structure, chain, q)
					"colonnade": made = ops.add_colonnade(structure, chain, q)
					"stair": made = ops.add_stair(structure, chain, q)
				chain = q if tool == "wall" else null
				_after_create(made)
		"floor", "trigger", "station", "mover":
			drag = {"mode": "rect", "start": _snap_plan(p)}
		"column":
			_after_create(ops.add_column(structure, _snap_plan(p)))
		"anchor":
			_after_create(ops.add_anchor(structure, _snap_plan(p)))
		"door", "window":
			var wall := _nearest_wall(p)
			if wall == null:
				status.text = "门窗要放在墙上：单击离墙更近一些。"
				return
			var before := [Ops.snapshot(wall)]
			if tool == "door":
				wall.add_opening_at(p, 0.9, 0.0, 2.1)
			else:
				wall.add_opening_at(p, 1.2, 0.9, 2.1)
			ops.commit("添加%s" % ("门" if tool == "door" else "窗"), [wall], before)
			_select([wall])
			_dirty = true

func _release(mb: InputEventMouseButton) -> void:
	var p := to_plan(mb.position)
	match drag.get("mode", ""):
		"handle":
			ops.commit("拖动手柄", [drag.node], drag.before)
		"move":
			if drag.applied != Vector2.ZERO:
				ops.commit("移动 %d 个构件" % drag.nodes.size(), drag.nodes, drag.before)
		"box":
			var r := Rect2(drag.start, Vector2.ZERO).expand(p)
			if r.size.length() * zoom > 4.0:
				var hits: Array = []
				for it in items:
					for q in it.outline:
						if r.has_point(q):
							hits.append(it.node)
							break
				_select(hits, mb.shift_pressed)
		"rect":
			var a: Vector2 = drag.start
			var b := _snap_plan(p)
			var r := Rect2(a, Vector2.ZERO).expand(b)
			if r.size.x < 0.1 or r.size.y < 0.1:
				r = Rect2(a - Vector2.ONE, Vector2.ONE * 2.0)
			var made: Node3D
			match tool:
				"floor": made = ops.add_floor(structure, r)
				"trigger": made = ops.add_trigger(structure, r)
				"station": made = ops.add_station(structure, r)
				"mover": made = ops.add_mover(structure, r)
			_after_create(made)
	drag = {}
	_dirty = true
	canvas.queue_redraw()

func _ctrl_click(s: Vector2, h: Dictionary) -> void:
	var node: Node3D = h.get("node")
	var before: Array
	if node != null:
		before = [Ops.snapshot(node)]
		if node.plan_remove_handle(h.id):
			ops.commit("删除顶点", [node], before)
	else:
		var it := _pick(s)
		node = it.get("node")
		if node != null and node.has_method("plan_insert_handle"):
			before = [Ops.snapshot(node)]
			if node.plan_insert_handle(_snap_plan(to_plan(s), [node])):
				ops.commit("添加顶点", [node], before)
				_select([node])
	_dirty = true

func _after_create(node: Node3D) -> void:
	if node == null:
		return
	_dirty = true
	refresh()
	_select([node])

func _nearest_wall(p: Vector2) -> Node3D:
	var best: Node3D = null
	var best_d := maxf(0.5, 12.0 / zoom)
	for it in items:
		if it.kind != "wall":
			continue
		var n: Node3D = it.node
		var a: Vector2 = n.to_plan(n.start_point)
		var b: Vector2 = n.to_plan(n.end_point)
		var d := Geometry2D.get_closest_point_to_segment(p, a, b).distance_to(p)
		if d < best_d:
			best_d = d
			best = n
	return best

func _key(event: InputEventKey) -> void:
	var handled := true
	if event.keycode == KEY_ESCAPE:
		if chain != null or tool != "select":
			chain = null
			set_tool("select")
	elif event.keycode == KEY_DELETE or event.keycode == KEY_BACKSPACE:
		if not selected.is_empty():
			ops.delete(selected.duplicate())
			selected = []
			_dirty = true
	elif event.keycode == KEY_D and event.ctrl_pressed:
		if not selected.is_empty():
			var copies: Array = ops.duplicate(structure, selected.duplicate(), Vector2(grid() * 4.0, grid() * 4.0))
			_dirty = true
			refresh()
			_select(copies)
	elif event.keycode == KEY_R and not event.ctrl_pressed:
		_rotate(-PI * 0.5 if event.shift_pressed else PI * 0.5)
	elif event.keycode == KEY_F and tool == "select":
		frame_all()
	elif event.keycode == KEY_G:
		snap_box.button_pressed = not snap_box.button_pressed
	else:
		handled = false
		for t in TOOLS:
			if event.keycode == t[2] and not event.ctrl_pressed:
				set_tool(t[0])
				handled = true
	if handled:
		canvas.accept_event()
		canvas.queue_redraw()

func _rotate(angle: float) -> void:
	if selected.is_empty():
		return
	var box := Rect2()
	var first := true
	for n in selected:
		for p in _item_of(n).get("outline", PackedVector2Array([_plan_of(n)])):
			box = Rect2(p, Vector2.ZERO) if first else box.expand(p)
			first = false
	var centre := box.get_center().snappedf(grid()) if snap else box.get_center()
	var before: Array = selected.map(func(n): return Ops.snapshot(n))
	for n in selected:
		Ops.rotate_plan(structure, n, centre, angle)
	ops.commit("旋转 90°", selected.duplicate(), before)
	_dirty = true

# ── drawing ───────────────────────────────────────────────────────────────────

func _draw_canvas() -> void:
	var c := canvas
	c.draw_rect(Rect2(Vector2.ZERO, c.size), Color(0.115, 0.125, 0.145))
	if structure == null:
		c.draw_string(get_theme_default_font(), Vector2(24, 40), "打开一个含 LevelStructure3D 的关卡场景（例如 scenes/levels/structures/public_nave.tscn）。", HORIZONTAL_ALIGNMENT_LEFT, -1, 15, ToolTheme.MUTED)
		return
	_draw_grid()
	var by_kind := {}
	for it in items:
		by_kind.get_or_add(it.kind, []).append(it)
	for kind in DRAW_ORDER:
		for it in by_kind.get(kind, []):
			_draw_item(it)
	for it in by_kind.get("anchor", []):
		_draw_anchor(it)
	for n in selected:
		var it := _item_of(n)
		if it.is_empty():
			continue
		if it.outline.size() >= 2:
			_poly_line(it.outline, ACCENT, 2.0)
		for h in it.handles:
			var s := to_screen(h.position)
			c.draw_rect(Rect2(s - Vector2(5, 5), Vector2(10, 10)), Color(0.1, 0.1, 0.12))
			c.draw_rect(Rect2(s - Vector2(4, 4), Vector2(8, 8)), ACCENT)
	if hover != null and not (hover in selected):
		var it := _item_of(hover)
		if not it.is_empty() and it.outline.size() >= 2:
			_poly_line(it.outline, Color(1, 1, 1, 0.55), 1.0)
	_draw_previews()

func _draw_grid() -> void:
	var c := canvas
	var g := grid()
	var lo := to_plan(Vector2.ZERO)
	var hi := to_plan(c.size)
	for spec in [[g, Color(1, 1, 1, 0.035)], [1.0, Color(1, 1, 1, 0.07)], [5.0, Color(1, 1, 1, 0.12)]]:
		var step: float = spec[0]
		if step * zoom < 6.0:
			continue
		var x := floorf(lo.x / step) * step
		while x <= hi.x:
			c.draw_line(Vector2(to_screen(Vector2(x, 0)).x, 0), Vector2(to_screen(Vector2(x, 0)).x, c.size.y), spec[1])
			x += step
		var y := floorf(lo.y / step) * step
		while y <= hi.y:
			c.draw_line(Vector2(0, to_screen(Vector2(0, y)).y), Vector2(c.size.x, to_screen(Vector2(0, y)).y), spec[1])
			y += step
	var o := to_screen(Vector2.ZERO)
	c.draw_line(Vector2(o.x, 0), Vector2(o.x, c.size.y), Color(0.45, 0.6, 1.0, 0.35))
	c.draw_line(Vector2(0, o.y), Vector2(c.size.x, o.y), Color(1.0, 0.45, 0.45, 0.35))

func _draw_item(it: Dictionary) -> void:
	var c := canvas
	var col: Array = COLORS.get(it.kind, COLORS.piece)
	var pts := PackedVector2Array()
	for p in it.outline:
		pts.append(to_screen(p))
	if pts.size() >= 3:
		if col[0].a > 0.0 and Geometry2D.triangulate_polygon(pts).size() > 0:
			c.draw_colored_polygon(pts, col[0])
		if it.kind == "trigger" or it.kind == "mover" or it.kind == "assembly":
			_dashed(pts, col[1])
		else:
			_poly_line(it.outline, col[1].darkened(0.25), 1.0)
	elif pts.size() == 2:
		c.draw_line(pts[0], pts[1], col[1], 2.0)
	match it.kind:
		"wall": _draw_openings(it.node)
		"stair": _draw_steps(it.node)
		"mover":
			var open := PackedVector2Array()
			for p in it.node.plan_open_outline():
				open.append(to_screen(p))
			_dashed(open, Color(0.78, 0.6, 1.0, 0.6))
	if it.label != "" and zoom > 10.0:
		var centre := Vector2.ZERO
		for p in pts:
			centre += p
		centre /= maxf(1.0, pts.size())
		c.draw_string(get_theme_default_font(), centre + Vector2(-20, 4), str(it.label), HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(1, 1, 1, 0.75))

func _draw_openings(wall: Node3D) -> void:
	var a: Vector2 = wall.to_plan(wall.start_point)
	var b: Vector2 = wall.to_plan(wall.end_point)
	var dir := (b - a).normalized()
	var side := dir.orthogonal() * float(wall.wall_thickness) * 0.5
	for op: Dictionary in wall.openings:
		var p0 := a + dir * float(op.get("from", 0))
		var p1 := a + dir * float(op.get("to", 0))
		var gap := PackedVector2Array([to_screen(p0 + side), to_screen(p1 + side), to_screen(p1 - side), to_screen(p0 - side)])
		canvas.draw_colored_polygon(gap, Color(0.115, 0.125, 0.145))
		if float(op.get("bottom", 0)) <= 0.01:
			var r := p0.distance_to(p1)
			var hinge := to_screen(p0)
			var start_ang := (dir * zoom).angle()
			canvas.draw_arc(hinge, r * zoom, start_ang, start_ang + PI * 0.5, 16, Color(0.95, 0.85, 0.6, 0.8), 1.0)
			canvas.draw_line(hinge, hinge + (dir.rotated(PI * 0.5)) * r * zoom, Color(0.95, 0.85, 0.6, 0.8), 1.5)
		else:
			canvas.draw_line(to_screen(p0), to_screen(p1), Color(0.6, 0.85, 1.0), 2.0)

func _draw_steps(stair: Node3D) -> void:
	var a: Vector2 = stair.to_plan(stair.start_point)
	var b: Vector2 = stair.to_plan(stair.end_point)
	var rise := absf(float(stair.end_point.y - stair.start_point.y))
	var steps := maxi(1, roundi(rise / float(stair.standard_step_height)))
	var side := (b - a).orthogonal().normalized() * float(stair.stair_width) * 0.5
	for i in range(1, steps):
		var p := a.lerp(b, float(i) / float(steps))
		canvas.draw_line(to_screen(p + side), to_screen(p - side), Color(0, 0, 0, 0.35))
	canvas.draw_line(to_screen(a), to_screen(b), Color(1, 1, 1, 0.5), 1.0)

func _draw_anchor(it: Dictionary) -> void:
	var s := to_screen(_plan_of(it.node))
	var r := 6.0
	canvas.draw_colored_polygon(PackedVector2Array([s + Vector2(0, -r), s + Vector2(r, 0), s + Vector2(0, r), s + Vector2(-r, 0)]), Color(1.0, 0.85, 0.3))
	if zoom > 8.0:
		canvas.draw_string(get_theme_default_font(), s + Vector2(8, 4), str(it.label), HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(1.0, 0.9, 0.55))

func _draw_previews() -> void:
	var c := canvas
	var q := _snap_plan(cursor)
	if tool != "select" and drag.is_empty():
		c.draw_circle(to_screen(q), 3.5, ACCENT)
	if chain != null:
		c.draw_line(to_screen(chain), to_screen(q), ACCENT, 2.0)
		var mid := (to_screen(chain) + to_screen(q)) * 0.5
		c.draw_string(get_theme_default_font(), mid + Vector2(6, -6), "%.2f m" % chain.distance_to(q), HORIZONTAL_ALIGNMENT_LEFT, -1, 12, ACCENT)
	if drag.get("mode") == "rect":
		var r := Rect2(to_screen(drag.start), Vector2.ZERO).expand(to_screen(q))
		c.draw_rect(r, Color(ACCENT, 0.15))
		c.draw_rect(r, ACCENT, false, 1.5)
		var size: Vector2 = (q - drag.start).abs()
		c.draw_string(get_theme_default_font(), r.end + Vector2(6, 0), "%.2f × %.2f m" % [size.x, size.y], HORIZONTAL_ALIGNMENT_LEFT, -1, 12, ACCENT)
	if drag.get("mode") == "box":
		var r := Rect2(to_screen(drag.start), Vector2.ZERO).expand(to_screen(cursor))
		c.draw_rect(r, Color(0.5, 0.75, 1.0, 0.1))
		c.draw_rect(r, Color(0.5, 0.75, 1.0, 0.8), false, 1.0)

func _poly_line(outline: PackedVector2Array, color: Color, width: float) -> void:
	var pts := PackedVector2Array()
	for p in outline:
		pts.append(to_screen(p))
	if pts.size() >= 3:
		pts.append(pts[0])
	canvas.draw_polyline(pts, color, width)

func _dashed(pts: PackedVector2Array, color: Color) -> void:
	for i in pts.size():
		canvas.draw_dashed_line(pts[i], pts[(i + 1) % pts.size()], color, 1.5, 6.0)

func _update_status() -> void:
	if status == null:
		return
	var hint := ""
	for t in TOOLS:
		if t[0] == tool:
			hint = t[3]
	var name_text := ""
	if structure == null:
		name_text = "没有关卡结构"
	else:
		name_text = "%s · %d 个构件 · 选中 %d" % [structure.name, items.size(), selected.size()]
	status.text = "  %s　|　X %.2f  Z %.2f　|　%s　|　网格 %s m%s" % [name_text, cursor.x, cursor.y, hint, str(grid()), "" if snap else "（吸附关）"]
