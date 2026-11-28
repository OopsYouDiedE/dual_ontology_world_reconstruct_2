@tool
extends Node
## The plan of a level structure, drawn and edited inside Godot's own 2D tab.
## Godot's 2D editor shows only 2D nodes, and level structures are 3D, so this plugin part
## paints the plan over the 2D viewport (1 m = PX canvas pixels, X right, Z down) and takes
## the mouse there: Godot keeps its own wheel zoom and middle-mouse pan, we handle the rest.
## Every piece is drawn from its plan outline; drag pieces and handles with grid and
## snap-point snapping; draw walls, floors, doors, windows, columns, arches, colonnades,
## stairs, triggers, stations, movers and anchors from the tool buttons in the 2D toolbar.
## The plan is only another view of the same nodes: every edit writes the nodes' exported
## values (undoable) and the 3D view rebuilds.
##
## Mouse: left = select / drag / draw / box select · wheel, middle drag = Godot zoom and pan
## Keys: V W F D N C A L S T B K M = tools · Del = delete · R / Shift+R = rotate 90°
##       Ctrl+D = duplicate · Ctrl+click = add / remove a vertex or opening
##       Esc = stop drawing · G = toggle snapping · Alt while dragging = no snapping

const Ops := preload("res://addons/archbuilder/structure_ops.gd")
const Piece := preload("res://scenes/components/structure/StructurePiece3D.gd")
const Queue := preload("res://scenes/components/structure/StructureRebuildQueue.gd")
const ToolTheme := preload("res://tools/building_construction/ToolTheme.gd")

## Canvas pixels per metre in the 2D tab (a 32 m lot fits the default 2D view).
const PX := 20.0

const TOOLS := [
	["select", "选择", KEY_V, "点选 / 框选 / 拖动构件与手柄"],
	["wall", "墙", KEY_W, "单击起点，再单击下一点连续画墙；Esc 或右键结束"],
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
	"floor": [Color(0.27, 0.31, 0.37, 0.9), Color(0.45, 0.52, 0.6)],
	"wall": [Color(0.82, 0.84, 0.88), Color(0.95, 0.96, 0.98)],
	"column": [Color(0.78, 0.7, 0.56), Color(0.95, 0.86, 0.68)],
	"arch": [Color(0.55, 0.68, 0.82, 0.55), Color(0.7, 0.82, 0.95)],
	"stair": [Color(0.55, 0.47, 0.33, 0.85), Color(0.82, 0.7, 0.5)],
	"trigger": [Color(0.3, 0.95, 0.55, 0.14), Color(0.35, 0.95, 0.6)],
	"station": [Color(1.0, 0.55, 0.2, 0.18), Color(1.0, 0.62, 0.3)],
	"mover": [Color(0.7, 0.45, 1.0, 0.18), Color(0.78, 0.6, 1.0)],
	"assembly": [Color(0, 0, 0, 0), Color(0.55, 0.85, 0.95)],
	"piece": [Color(0.5, 0.56, 0.66, 0.35), Color(0.62, 0.68, 0.78)],
	"generic": [Color(0.6, 0.6, 0.6, 0.12), Color(0.6, 0.6, 0.6)],
}
const DRAW_ORDER := ["floor", "generic", "piece", "station", "stair", "assembly", "arch", "wall", "column", "mover", "trigger"]
const ACCENT := Color(1.0, 0.7, 0.28)
const BACKDROP := Color(0.115, 0.125, 0.145)

var plugin: EditorPlugin
var ops
var structure: Node3D
var toolbar: HBoxContainer
var grid_menu: OptionButton
var snap_box: CheckBox
var tool_buttons := {}
var tool := "select"
var snap := true
var items: Array = []          # {node, kind, outline, area, handles, label}
var selected: Array = []
var hover: Object = null
var cursor := Vector2.ZERO     # plan space
var drag := {}
var chain = null               # wall / arch start point while drawing
var canvas: Control            # the 2D viewport overlay while drawing
var xform := Transform2D()     # plan metres -> overlay pixels
var zoom := PX                 # overlay pixels per metre
## True while Godot's 2D tab is the main screen (set by the plugin).
var in_2d := false
var hold_2d_until := 0
var _dirty := true
var _last_rebuilds := -1
var _refresh_clock := 0.0

func setup(p: EditorPlugin, o) -> void:
	plugin = p
	ops = o
	toolbar = _build_toolbar()
	toolbar.visible = false
	EditorInterface.get_selection().selection_changed.connect(_from_editor_selection)

func _exit_tree() -> void:
	var sel := EditorInterface.get_selection()
	if sel.selection_changed.is_connected(_from_editor_selection):
		sel.selection_changed.disconnect(_from_editor_selection)

func _build_toolbar() -> HBoxContainer:
	var bar := HBoxContainer.new()
	bar.add_theme_constant_override("separation", 2)
	bar.add_child(VSeparator.new())
	var title := Label.new()
	title.text = "关卡平面"
	title.add_theme_color_override("font_color", ToolTheme.MUTED)
	bar.add_child(title)
	var group := ButtonGroup.new()
	for t in TOOLS:
		var b := Button.new()
		b.text = t[1]
		b.flat = true
		b.toggle_mode = true
		b.button_group = group
		b.tooltip_text = "%s（%s）\n%s" % [t[1], OS.get_keycode_string(t[2]), t[3]]
		b.focus_mode = Control.FOCUS_NONE
		b.pressed.connect(set_tool.bind(t[0]))
		bar.add_child(b)
		tool_buttons[t[0]] = b
	tool_buttons["select"].button_pressed = true
	bar.add_child(VSeparator.new())
	grid_menu = OptionButton.new()
	grid_menu.flat = true
	grid_menu.tooltip_text = "平面网格（吸附步长）"
	for g in [0.05, 0.1, 0.25, 0.5, 1.0]:
		grid_menu.add_item("网格 %s m" % str(g))
		grid_menu.set_item_metadata(grid_menu.item_count - 1, g)
	grid_menu.select(2)
	grid_menu.focus_mode = Control.FOCUS_NONE
	grid_menu.item_selected.connect(func(i):
		if structure:
			structure.editor_grid = float(grid_menu.get_item_metadata(i))
		redraw())
	bar.add_child(grid_menu)
	snap_box = CheckBox.new()
	snap_box.text = "吸附"
	snap_box.button_pressed = true
	snap_box.focus_mode = Control.FOCUS_NONE
	snap_box.toggled.connect(func(on): snap = on; redraw())
	bar.add_child(snap_box)
	return bar

func set_tool(id: String) -> void:
	tool = id
	chain = null
	drag = {}
	if tool_buttons.has(id):
		tool_buttons[id].set_pressed_no_signal(true)
	redraw()

func redraw() -> void:
	if plugin:
		plugin.update_overlays()

func mark_dirty() -> void:
	_dirty = true

func _process(delta: float) -> void:
	_refresh_clock += delta
	var rebuilds := int(Queue.stats.get("rebuilds", 0))
	if rebuilds != _last_rebuilds or _refresh_clock > 0.6:
		_last_rebuilds = rebuilds
		_refresh_clock = 0.0
		_dirty = true
	if _dirty and drag.is_empty():
		_dirty = false
		refresh()

## The 2D tab shows this plan only for scenes that contain a LevelStructure3D.
func active() -> bool:
	return structure != null

# ── data ──────────────────────────────────────────────────────────────────────

func find_structure() -> Node3D:
	var root := EditorInterface.get_edited_scene_root()
	if root == null:
		return null
	for node in EditorInterface.get_selection().get_selected_nodes():
		var n: Node = node
		while n != null:
			if n is LevelStructure3D:
				return n
			n = n.get_parent()
	if root is LevelStructure3D:
		return root
	var list := root.find_children("*", "LevelStructure3D", true, true)
	return list[0] if not list.is_empty() else null

func refresh() -> void:
	var found := find_structure()
	if found != structure:
		structure = found
		if structure != null:
			var g := float(structure.editor_grid)
			for i in grid_menu.item_count:
				if is_equal_approx(float(grid_menu.get_item_metadata(i)), g):
					grid_menu.select(i)
	if toolbar:
		toolbar.visible = structure != null
	_collect()
	selected = selected.filter(func(n): return is_instance_valid(n) and n.is_inside_tree())
	redraw()

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
			if n.scope() != structure:
				continue
			item.kind = n.plan_kind()
			item.outline = n.plan_outline()
			item.handles = n.plan_handles()
			if item.kind == "trigger":
				item.label = n.resolved_id()
		elif (n.get_script() != null or n is VisualInstance3D) and not _has_authored_children(n):
			item.kind = "generic"
			item.outline = _generic_outline(n)
			item.label = n.name
		else:
			continue
		item.area = absf(_area(item.outline)) if item.outline.size() >= 3 else 0.01
		if not COLORS.has(item.kind) and item.kind != "anchor":
			item.kind = "piece"
		items.append(item)

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
		var t: Transform3D = inv * vi.global_transform
		for k in 8:
			var p: Vector3 = t * a.get_endpoint(k)
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

## Follow Godot's 2D view (its own zoom and pan) every time we draw or take input.
func _sync_view() -> void:
	var vp := EditorInterface.get_editor_viewport_2d()
	var canvas_xf := vp.global_canvas_transform if vp else Transform2D()
	xform = canvas_xf * Transform2D(0.0, Vector2(PX, PX), 0.0, Vector2.ZERO)
	zoom = xform.get_scale().x

func to_screen(p: Vector2) -> Vector2:
	return xform * p

func to_plan(s: Vector2) -> Vector2:
	return xform.affine_inverse() * s

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

## Plan bounds in metres (for framing the 2D view).
func bounds() -> Rect2:
	var box := Rect2()
	var first := true
	for it in items:
		for p in it.outline:
			box = Rect2(p, Vector2.ZERO) if first else box.expand(p)
			first = false
	return box

# ── selection ─────────────────────────────────────────────────────────────────

func _pick(s: Vector2) -> Dictionary:
	var p := to_plan(s)
	var best := {}
	var best_area := INF
	for it in items:
		if it.kind == "anchor":
			if to_screen(_plan_of(it.node)).distance_to(s) < 9.0:
				return it
		elif it.outline.size() >= 3 and Geometry2D.is_point_in_polygon(p, it.outline) and it.area < best_area:
			best_area = it.area
			best = it
	return best

func _pick_handle(s: Vector2) -> Dictionary:
	for node in selected:
		var it := _item_of(node)
		for h in it.get("handles", []):
			if to_screen(h.position).distance_to(s) < 8.0:
				return {"node": node, "id": h.id, "position": h.position}
	return {}

## Nothing picked keeps the structure itself selected, so the 2D tab keeps the mouse.
func _select(nodes: Array, additive := false) -> void:
	if additive:
		for n in nodes:
			if n in selected:
				selected.erase(n)
			else:
				selected.append(n)
	else:
		selected = nodes.duplicate()
	stay_in_2d()  # before touching the selection: Godot switches to 3D synchronously
	var sel := EditorInterface.get_selection()
	sel.clear()
	for n in selected:
		sel.add_node(n)
	if selected.is_empty() and structure != null:
		sel.add_node(structure)
	EditorInterface.edit_node(selected[-1] if not selected.is_empty() else structure)
	redraw()

## Selecting a 3D node makes Godot jump to the 3D tab; picking in the plan stays in 2D.
## (The plugin switches straight back if Godot moves to 3D within this window.)
func stay_in_2d() -> void:
	if in_2d:
		hold_2d_until = Time.get_ticks_msec() + 400

func _from_editor_selection() -> void:
	selected = EditorInterface.get_selection().get_selected_nodes().filter(func(n): return n != structure)
	_dirty = true

# ── input (from EditorPlugin._forward_canvas_gui_input) ────────────────────────

## Returns true when the event was used (Godot's 2D editor then ignores it).
func input(event: InputEvent) -> bool:
	if structure == null:
		return false
	_sync_view()
	if event is InputEventMouseMotion:
		cursor = to_plan(event.position)
		match drag.get("mode", ""):
			"handle":
				drag.node.set_plan_handle(drag.id, _snap_plan(cursor, [drag.node]))
				_collect()
			"move":
				var raw: Vector2 = drag.ref + (cursor - drag.start)
				var d: Vector2 = _snap_plan(raw, drag.nodes) - drag.ref - drag.applied
				if d != Vector2.ZERO:
					for n in drag.nodes:
						Ops.move_plan(structure, n, d)
					drag.applied += d
					_collect()
			"":
				hover = _pick(event.position).get("node")
		redraw()
		return not drag.is_empty()
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_RIGHT and mb.pressed and chain != null:
			chain = null
			redraw()
			return true
		if mb.button_index != MOUSE_BUTTON_LEFT:
			return false  # wheel / middle / right: Godot's zoom, pan and menus
		if mb.pressed:
			_press(mb)
		else:
			_release(mb)
		redraw()
		return true
	if event is InputEventKey and event.pressed and not event.echo:
		return _key(event)
	return false

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
				push_warning("门窗要放在墙上：单击离墙更近一些。")
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
			var r := Rect2(a, Vector2.ZERO).expand(_snap_plan(p))
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

func _ctrl_click(s: Vector2, h: Dictionary) -> void:
	var node: Node3D = h.get("node")
	if node != null:
		var before := [Ops.snapshot(node)]
		if node.plan_remove_handle(h.id):
			ops.commit("删除顶点", [node], before)
	else:
		node = _pick(s).get("node")
		if node != null and node.has_method("plan_insert_handle"):
			var before := [Ops.snapshot(node)]
			if node.plan_insert_handle(_snap_plan(to_plan(s), [node])):
				ops.commit("添加顶点", [node], before)
				_select([node])
	_dirty = true

func _after_create(node: Node3D) -> void:
	if node == null:
		return
	refresh()
	_select([node])

func _nearest_wall(p: Vector2) -> Node3D:
	var best: Node3D = null
	var best_d := maxf(0.5, 12.0 / zoom)
	for it in items:
		if it.kind != "wall":
			continue
		var n: Node3D = it.node
		var d := Geometry2D.get_closest_point_to_segment(p, n.to_plan(n.start_point), n.to_plan(n.end_point)).distance_to(p)
		if d < best_d:
			best_d = d
			best = n
	return best

func _key(event: InputEventKey) -> bool:
	if event.keycode == KEY_ESCAPE:
		chain = null
		set_tool("select")
	elif event.keycode == KEY_DELETE:
		if selected.is_empty():
			return false
		ops.delete(selected.duplicate())
		_select([])
	elif event.keycode == KEY_D and event.ctrl_pressed:
		if selected.is_empty():
			return false
		var copies: Array = ops.duplicate(structure, selected.duplicate(), Vector2(grid() * 4.0, grid() * 4.0))
		refresh()
		_select(copies)
	elif event.keycode == KEY_R and not event.ctrl_pressed:
		_rotate(-PI * 0.5 if event.shift_pressed else PI * 0.5)
	elif event.keycode == KEY_G and not event.ctrl_pressed:
		snap_box.button_pressed = not snap_box.button_pressed
	else:
		for t in TOOLS:
			if event.keycode == t[2] and not event.ctrl_pressed and not event.alt_pressed:
				set_tool(t[0])
				return true
		return false
	_dirty = true
	redraw()
	return true

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

# ── drawing (from EditorPlugin._forward_canvas_force_draw_over_viewport) ───────

func draw(overlay: Control) -> void:
	if structure == null:
		return
	canvas = overlay
	_sync_view()
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
			canvas.draw_rect(Rect2(s - Vector2(5, 5), Vector2(10, 10)), Color(0.1, 0.1, 0.12))
			canvas.draw_rect(Rect2(s - Vector2(4, 4), Vector2(8, 8)), ACCENT)
	if hover != null and is_instance_valid(hover) and not (hover in selected):
		var it := _item_of(hover)
		if not it.is_empty() and it.outline.size() >= 2:
			_poly_line(it.outline, Color(1, 1, 1, 0.55), 1.0)
	_draw_previews()
	_draw_status()

func _draw_grid() -> void:
	var g := grid()
	var lo := to_plan(Vector2.ZERO)
	var hi := to_plan(canvas.size)
	for spec in [[g, Color(1, 1, 1, 0.035)], [1.0, Color(1, 1, 1, 0.07)], [5.0, Color(1, 1, 1, 0.13)]]:
		var step: float = spec[0]
		if step * zoom < 6.0:
			continue
		var x := floorf(lo.x / step) * step
		while x <= hi.x:
			var sx := to_screen(Vector2(x, 0)).x
			canvas.draw_line(Vector2(sx, 0), Vector2(sx, canvas.size.y), spec[1])
			x += step
		var y := floorf(lo.y / step) * step
		while y <= hi.y:
			var sy := to_screen(Vector2(0, y)).y
			canvas.draw_line(Vector2(0, sy), Vector2(canvas.size.x, sy), spec[1])
			y += step

func _draw_item(it: Dictionary) -> void:
	var col: Array = COLORS.get(it.kind, COLORS.piece)
	var pts := PackedVector2Array()
	for p in it.outline:
		pts.append(to_screen(p))
	if pts.size() >= 3:
		if col[0].a > 0.0 and Geometry2D.triangulate_polygon(pts).size() > 0:
			canvas.draw_colored_polygon(pts, col[0])
		if it.kind in ["trigger", "mover", "assembly"]:
			_dashed(pts, col[1])
		else:
			_poly_line(it.outline, col[1].darkened(0.25), 1.0)
	elif pts.size() == 2:
		canvas.draw_line(pts[0], pts[1], col[1], 2.0)
	match it.kind:
		"wall": _draw_openings(it.node)
		"stair": _draw_steps(it.node)
		"mover":
			var open := PackedVector2Array()
			for p in it.node.plan_open_outline():
				open.append(to_screen(p))
			_dashed(open, Color(0.78, 0.6, 1.0, 0.6))
	if it.label != "" and zoom > 10.0 and pts.size() > 0:
		var centre := Vector2.ZERO
		for p in pts:
			centre += p
		centre /= float(pts.size())
		canvas.draw_string(canvas.get_theme_default_font(), centre + Vector2(-20, 4), str(it.label), HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(1, 1, 1, 0.75))

func _draw_openings(wall: Node3D) -> void:
	var a: Vector2 = wall.to_plan(wall.start_point)
	var b: Vector2 = wall.to_plan(wall.end_point)
	var dir := (b - a).normalized()
	var side := dir.orthogonal() * float(wall.wall_thickness) * 0.5
	for op: Dictionary in wall.openings:
		var p0 := a + dir * float(op.get("from", 0))
		var p1 := a + dir * float(op.get("to", 0))
		canvas.draw_colored_polygon(PackedVector2Array([to_screen(p0 + side), to_screen(p1 + side), to_screen(p1 - side), to_screen(p0 - side)]), BACKDROP)
		if float(op.get("bottom", 0)) <= 0.01:
			var r := p0.distance_to(p1) * zoom
			var hinge := to_screen(p0)
			var swing := (to_screen(p1) - hinge).normalized()
			canvas.draw_arc(hinge, r, swing.angle(), swing.angle() + PI * 0.5, 16, Color(0.95, 0.85, 0.6, 0.8), 1.0)
			canvas.draw_line(hinge, hinge + swing.rotated(PI * 0.5) * r, Color(0.95, 0.85, 0.6, 0.8), 1.5)
		else:
			canvas.draw_line(to_screen(p0), to_screen(p1), Color(0.6, 0.85, 1.0), 2.0)

func _draw_steps(stair: Node3D) -> void:
	var a: Vector2 = stair.to_plan(stair.start_point)
	var b: Vector2 = stair.to_plan(stair.end_point)
	var steps := maxi(1, roundi(absf(float(stair.end_point.y - stair.start_point.y)) / float(stair.standard_step_height)))
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
		canvas.draw_string(canvas.get_theme_default_font(), s + Vector2(8, 4), str(it.label), HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(1.0, 0.9, 0.55))

func _draw_previews() -> void:
	var q := _snap_plan(cursor)
	if tool != "select" and drag.is_empty():
		canvas.draw_circle(to_screen(q), 3.5, ACCENT)
	if chain != null:
		canvas.draw_line(to_screen(chain), to_screen(q), ACCENT, 2.0)
		var mid := (to_screen(chain) + to_screen(q)) * 0.5
		canvas.draw_string(canvas.get_theme_default_font(), mid + Vector2(6, -6), "%.2f m" % chain.distance_to(q), HORIZONTAL_ALIGNMENT_LEFT, -1, 12, ACCENT)
	if drag.get("mode") == "rect":
		var r := Rect2(to_screen(drag.start), Vector2.ZERO).expand(to_screen(q))
		canvas.draw_rect(r, Color(ACCENT, 0.15))
		canvas.draw_rect(r, ACCENT, false, 1.5)
		var size: Vector2 = (q - drag.start).abs()
		canvas.draw_string(canvas.get_theme_default_font(), r.end + Vector2(6, 0), "%.2f × %.2f m" % [size.x, size.y], HORIZONTAL_ALIGNMENT_LEFT, -1, 12, ACCENT)
	if drag.get("mode") == "box":
		var r := Rect2(to_screen(drag.start), Vector2.ZERO).expand(to_screen(cursor))
		canvas.draw_rect(r, Color(0.5, 0.75, 1.0, 0.1))
		canvas.draw_rect(r, Color(0.5, 0.75, 1.0, 0.8), false, 1.0)

func _draw_status() -> void:
	var hint := ""
	for t in TOOLS:
		if t[0] == tool:
			hint = t[3]
	var text := "%s · %d 个构件 · 选中 %d　|　X %.2f  Z %.2f m　|　%s　|　网格 %s m%s" % [
		structure.name, items.size(), selected.size(), cursor.x, cursor.y, hint, str(grid()), "" if snap else "（吸附关）"]
	var font := canvas.get_theme_default_font()
	var pos := Vector2(28, canvas.size.y - 12)
	canvas.draw_rect(Rect2(pos + Vector2(-6, -16), Vector2(font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, 12).x + 12, 22)), Color(0, 0, 0, 0.55))
	canvas.draw_string(font, pos, text, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(0.85, 0.87, 0.9))

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
