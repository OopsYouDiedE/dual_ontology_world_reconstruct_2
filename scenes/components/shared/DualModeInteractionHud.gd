extends Control
class_name DualModeInteractionHud
## Dual-mode (Aggregated C+ / Distributed Detroit) three-state spatial interaction UI
## for The Sleeping Academy (Godot 4.7.2).
##
## Three unified interaction states:
##   1. POTENTIAL   (4.6m - 9.0m, or outer frustum) -> subtle breathing pip, no clutter
##   2. ACTIVATABLE (2.4m - 4.5m, or non-primary hotspot) -> crisp hollow brass diamond (+ faint leader in Detroit)
##   3. SELECTED    (<= 2.35m and aimed within focus cone) -> glowing brass reticle + full action prompt
##
## Conflict-free keybind design across Public Hall + Expedition:
##   - Primary interact: E (consistent with RogueRoomView & Expedition.gd)
##   - C+ multi-action selection: Mouse Wheel or 1 / 2 / 3 (avoids Q wheel, R lamp, F stomp, Tab manual)
##   - Detroit multi-hotspot selection: Aim at stationary 3D part + E
##   - Hot-toggle UI mode anytime: V

const UiStyle := preload("res://scenes/components/shared/UiTheme.gd")
const R18n := preload("res://scenes/components/shared/R18n.gd")

enum Mode { AGGREGATED_CPLUS, DISTRIBUTED_DETROIT }
enum State { NONE, POTENTIAL, ACTIVATABLE, SELECTED }

const DIST_POTENTIAL := 9.5
const DIST_ACTIVATABLE := 4.6
const DIST_SELECTED := 2.85
const AIM_HALF_ANGLE_DEG := 24.0

const COL_BRASS := Color("c9a35b")
const COL_BRASS_HI := Color("f0d394")
const COL_INK := Color("f2efe9")
const COL_INK_2 := Color("c4bfb5")
const COL_BG_DARK := Color(0.055, 0.068, 0.095, 0.88)
const COL_BG_SOFT := Color(0.055, 0.068, 0.095, 0.56)

var mode: int = Mode.AGGREGATED_CPLUS
var active_enabled := false
var group_title := ""
var primary_anchor_world := Vector3.ZERO
## Array of dicts: {id, part_name, verb, world_pos, callback, enabled, badge_hint}
var hotspots: Array[Dictionary] = []

var _camera: Camera3D
var _viewport_rect := Rect2()
var _viewport_size := Vector2(1280, 720)
var _player_pos := Vector3.ZERO

var _cplus_state: int = State.NONE
var _cplus_index := 0
var _detroit_states: Dictionary = {}   # id -> State
var _detroit_focus_id := ""
var _detroit_override_focus_id := ""
var _time := 0.0
var _toast_text := ""
var _toast_timer := 0.0
var _font: Font

func _ready() -> void:
	name = "DualModeInteractionHud"
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_font = UiStyle.make_font()

func set_mode(new_mode: int, announce := false) -> void:
	mode = new_mode
	if announce:
		var label := R18n.pick("C+ 集合式（右下角语境条）", "C+ Aggregated (Corner Bar)") if mode == Mode.AGGREGATED_CPLUS else R18n.pick("底特律分散式（多热点折线）", "Detroit Distributed (Spatial Hotspots)")
		show_toast(R18n.pick("交互样式已切换：", "Interaction UI: ") + label)
	queue_redraw()

func toggle_mode() -> void:
	set_mode(Mode.DISTRIBUTED_DETROIT if mode == Mode.AGGREGATED_CPLUS else Mode.AGGREGATED_CPLUS, true)

func get_mode_name() -> String:
	return "cplus" if mode == Mode.AGGREGATED_CPLUS else "detroit"

func set_cplus_index(idx: int) -> void:
	if hotspots.is_empty():
		_cplus_index = 0
		return
	_cplus_index = posmod(idx, hotspots.size())
	queue_redraw()

func cycle_cplus(delta: int) -> void:
	set_cplus_index(_cplus_index + delta)

func set_detroit_focus_override(id: String) -> void:
	_detroit_override_focus_id = id
	queue_redraw()

func show_toast(msg: String, duration := 2.4) -> void:
	_toast_text = msg
	_toast_timer = duration
	queue_redraw()

func configure_target(title: String, anchor_world: Vector3, items: Array[Dictionary]) -> void:
	group_title = title
	primary_anchor_world = anchor_world
	hotspots = items
	if _cplus_index >= hotspots.size():
		_cplus_index = 0

func sync_view(camera: Camera3D, pixels_rect: Rect2, vp_size: Vector2, player_pos: Vector3, enabled: bool) -> void:
	_camera = camera
	_viewport_rect = pixels_rect
	_viewport_size = vp_size
	_player_pos = player_pos
	active_enabled = enabled
	_evaluate_states()
	queue_redraw()

func is_selected_active() -> bool:
	if not active_enabled:
		return false
	if mode == Mode.AGGREGATED_CPLUS:
		return _cplus_state == State.SELECTED and not hotspots.is_empty()
	return not _detroit_focus_id.is_empty() and int(_detroit_states.get(_detroit_focus_id, State.NONE)) == State.SELECTED

func trigger_selected() -> bool:
	if not is_selected_active():
		return false
	if mode == Mode.AGGREGATED_CPLUS:
		return trigger_index(_cplus_index)
	for h in hotspots:
		if str(h.get("id", "")) == _detroit_focus_id:
			var cb: Callable = h.get("callback", Callable())
			if cb.is_valid():
				cb.call()
				return true
	return false

func trigger_index(idx: int) -> bool:
	if not active_enabled or _cplus_state != State.SELECTED:
		return false
	if idx < 0 or idx >= hotspots.size():
		return false
	_cplus_index = idx
	var cb: Callable = hotspots[idx].get("callback", Callable())
	if cb.is_valid():
		cb.call()
		queue_redraw()
		return true
	return false

func get_state_snapshot() -> Dictionary:
	return {
		"mode": get_mode_name(),
		"enabled": active_enabled,
		"cplus_state": _state_name(_cplus_state),
		"cplus_index": _cplus_index,
		"detroit_focus_id": _detroit_focus_id,
		"detroit_states": _detroit_states_named(),
	}

func _state_name(s: int) -> String:
	match s:
		State.POTENTIAL: return "potential"
		State.ACTIVATABLE: return "activatable"
		State.SELECTED: return "selected"
		_: return "none"

func _detroit_states_named() -> Dictionary:
	var out := {}
	for k in _detroit_states:
		out[k] = _state_name(int(_detroit_states[k]))
	return out

func _process(dt: float) -> void:
	_time += dt
	if _toast_timer > 0.0:
		_toast_timer = maxf(0.0, _toast_timer - dt)
	if active_enabled or _toast_timer > 0.0:
		queue_redraw()

func _project_to_control(world_pos: Vector3) -> Dictionary:
	if not is_instance_valid(_camera) or _viewport_size.x <= 1.0 or _viewport_size.y <= 1.0:
		return {"visible": false, "pos": Vector2.ZERO}
	if _camera.is_position_behind(world_pos):
		return {"visible": false, "pos": Vector2.ZERO}
	var vp_pt: Vector2 = _camera.unproject_position(world_pos)
	var norm := Vector2(vp_pt.x / _viewport_size.x, vp_pt.y / _viewport_size.y)
	var screen_pt := _viewport_rect.position + Vector2(norm.x * _viewport_rect.size.x, norm.y * _viewport_rect.size.y)
	var local_pt := screen_pt - global_position
	var in_bounds := norm.x >= -0.05 and norm.x <= 1.05 and norm.y >= -0.05 and norm.y <= 1.05
	return {"visible": in_bounds, "pos": local_pt}

func _flat_dist(world_pos: Vector3) -> float:
	return Vector2(_player_pos.x - world_pos.x, _player_pos.z - world_pos.z).length()

func _aim_angle_deg(world_pos: Vector3) -> float:
	if not is_instance_valid(_camera):
		return 180.0
	var forward := -_camera.global_transform.basis.z.normalized()
	var to_pt := (world_pos - _camera.global_position).normalized()
	return rad_to_deg(acos(clampf(forward.dot(to_pt), -1.0, 1.0)))

func _evaluate_states() -> void:
	_cplus_state = State.NONE
	_detroit_states.clear()
	_detroit_focus_id = ""
	if not active_enabled or hotspots.is_empty() or not is_instance_valid(_camera):
		return

	# 1. C+ Aggregated state on primary anchor
	var d_main := _flat_dist(primary_anchor_world)
	var ang_main := _aim_angle_deg(primary_anchor_world)
	if d_main <= DIST_SELECTED and ang_main <= AIM_HALF_ANGLE_DEG:
		_cplus_state = State.SELECTED
	elif d_main <= DIST_ACTIVATABLE:
		_cplus_state = State.ACTIVATABLE
	elif d_main <= DIST_POTENTIAL:
		_cplus_state = State.POTENTIAL

	# 2. Detroit Distributed state per hotspot (at most one SELECTED primary focus)
	var best_id := ""
	var best_score := INF
	for h in hotspots:
		var id := str(h.get("id", ""))
		var wpos: Vector3 = h.get("world_pos", primary_anchor_world)
		var d := _flat_dist(wpos)
		var ang := _aim_angle_deg(wpos)
		var base_state := State.NONE
		if d <= DIST_SELECTED and ang <= AIM_HALF_ANGLE_DEG:
			base_state = State.ACTIVATABLE
			var score := ang + d * 2.2
			if id == _detroit_override_focus_id:
				score = -1.0
			if score < best_score:
				best_score = score
				best_id = id
		elif d <= DIST_ACTIVATABLE:
			base_state = State.ACTIVATABLE
		elif d <= DIST_POTENTIAL:
			base_state = State.POTENTIAL
		_detroit_states[id] = base_state

	if not best_id.is_empty():
		_detroit_focus_id = best_id
		_detroit_states[best_id] = State.SELECTED
	elif not _detroit_override_focus_id.is_empty() and _detroit_states.has(_detroit_override_focus_id):
		if int(_detroit_states[_detroit_override_focus_id]) >= State.ACTIVATABLE:
			_detroit_focus_id = _detroit_override_focus_id
			_detroit_states[_detroit_override_focus_id] = State.SELECTED

func _draw() -> void:
	if _font == null:
		return
	if active_enabled:
		_draw_mode_pill()
		if mode == Mode.AGGREGATED_CPLUS:
			_draw_cplus()
		else:
			_draw_detroit()
	if _toast_timer > 0.0 and not _toast_text.is_empty():
		_draw_toast()

func _draw_mode_pill() -> void:
	var txt := R18n.pick("[V] 交互样式：C+ 集合式", "[V] UI: C+ Aggregated") if mode == Mode.AGGREGATED_CPLUS else R18n.pick("[V] 交互样式：底特律分散式", "[V] UI: Detroit Spatial")
	var fsize := 12
	var tw := _font.get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fsize).x
	var pad := Vector2(12, 6)
	var rect := Rect2(Vector2(size.x - tw - pad.x * 2.0 - 22.0, 62.0), Vector2(tw + pad.x * 2.0, 26.0))
	draw_rect(rect, Color(0.055, 0.068, 0.095, 0.72), true)
	draw_rect(rect, Color(COL_BRASS.r, COL_BRASS.g, COL_BRASS.b, 0.42), false, 1.0)
	draw_string(_font, Vector2(rect.position.x + pad.x, rect.position.y + 17.5), txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fsize, COL_INK_2)

func _draw_toast() -> void:
	var alpha := clampf(_toast_timer * 1.4, 0.0, 1.0)
	var fsize := 13
	var tw := _font.get_string_size(_toast_text, HORIZONTAL_ALIGNMENT_LEFT, -1, fsize).x
	var rect := Rect2(Vector2((size.x - tw) * 0.5 - 16.0, 52.0), Vector2(tw + 32.0, 30.0))
	draw_rect(rect, Color(0.055, 0.068, 0.095, 0.90 * alpha), true)
	draw_rect(rect, Color(COL_BRASS_HI.r, COL_BRASS_HI.g, COL_BRASS_HI.b, 0.75 * alpha), false, 1.2)
	draw_string(_font, Vector2(rect.position.x + 16.0, rect.position.y + 19.5), _toast_text, HORIZONTAL_ALIGNMENT_LEFT, -1, fsize, Color(COL_BRASS_HI.r, COL_BRASS_HI.g, COL_BRASS_HI.b, alpha))

func _draw_diamond(center: Vector2, half_size: float, fill_col: Color, border_col: Color, border_w: float) -> void:
	var pts := PackedVector2Array([
		center + Vector2(0, -half_size),
		center + Vector2(half_size, 0),
		center + Vector2(0, half_size),
		center + Vector2(-half_size, 0),
	])
	if fill_col.a > 0.01:
		draw_colored_polygon(pts, fill_col)
	if border_col.a > 0.01 and border_w > 0.0:
		var loop := PackedVector2Array([pts[0], pts[1], pts[2], pts[3], pts[0]])
		draw_polyline(loop, border_col, border_w, true)

func _draw_cplus() -> void:
	if _cplus_state == State.NONE:
		return
	var proj := _project_to_control(primary_anchor_world)
	if proj.visible:
		var p: Vector2 = proj.pos
		var pulse := 0.5 + 0.5 * sin(_time * 3.2)
		if _cplus_state == State.POTENTIAL:
			# State 1: faint breathing brass dot
			draw_circle(p, 7.5 + pulse * 2.5, Color(COL_BRASS.r, COL_BRASS.g, COL_BRASS.b, 0.14 + pulse * 0.10))
			draw_circle(p, 3.2, Color(COL_BRASS_HI.r, COL_BRASS_HI.g, COL_BRASS_HI.b, 0.45 + pulse * 0.35))
		elif _cplus_state == State.ACTIVATABLE:
			# State 2: hollow crisp brass diamond
			_draw_diamond(p, 9.0, Color(0.05, 0.06, 0.09, 0.50), Color(COL_BRASS_HI.r, COL_BRASS_HI.g, COL_BRASS_HI.b, 0.85), 1.6)
			_draw_diamond(p, 3.2, Color(COL_BRASS_HI.r, COL_BRASS_HI.g, COL_BRASS_HI.b, 0.72), Color.TRANSPARENT, 0.0)
		elif _cplus_state == State.SELECTED:
			# State 3: glowing double brass diamond reticle
			var ring_s := 13.0 + fmod(_time * 1.1, 1.0) * 9.0
			var ring_a := (1.0 - fmod(_time * 1.1, 1.0)) * 0.55
			_draw_diamond(p, ring_s, Color.TRANSPARENT, Color(COL_BRASS_HI.r, COL_BRASS_HI.g, COL_BRASS_HI.b, ring_a), 1.2)
			_draw_diamond(p, 11.5, Color(COL_BRASS.r, COL_BRASS.g, COL_BRASS.b, 0.24), COL_BRASS_HI, 2.0)
			_draw_diamond(p, 4.2, COL_BRASS_HI, Color.TRANSPARENT, 0.0)

	# Bottom-right contextual bar: hidden on POTENTIAL, 52% preview on ACTIVATABLE, 100% on SELECTED
	if _cplus_state == State.POTENTIAL:
		return
	var alpha := 1.0 if _cplus_state == State.SELECTED else 0.52
	var row_h := 30.0
	var header_h := 28.0
	var tip_h := 20.0 if _cplus_state == State.SELECTED else 0.0
	var total_h := header_h + hotspots.size() * row_h + tip_h + 10.0
	var bar_w := 228.0
	var right_x := size.x - 32.0
	var bottom_y := size.y - 38.0
	var top_y := bottom_y - total_h
	var left_x := right_x - bar_w

	# Subtle dark gradient backing for legibility on bright firelight
	draw_rect(Rect2(left_x - 8.0, top_y - 4.0, bar_w + 14.0, total_h + 8.0), Color(0.04, 0.05, 0.075, 0.58 * alpha), true)

	# Left vertical antique brass hairline + center diamond accent
	draw_line(Vector2(left_x, top_y), Vector2(left_x, bottom_y), Color(COL_BRASS.r, COL_BRASS.g, COL_BRASS.b, 0.78 * alpha), 1.5, true)
	_draw_diamond(Vector2(left_x, (top_y + bottom_y) * 0.5), 3.8, Color(COL_BRASS_HI.r, COL_BRASS_HI.g, COL_BRASS_HI.b, alpha), Color.TRANSPARENT, 0.0)

	# Header: target title + state cue
	var title_col := Color(COL_BRASS_HI.r, COL_BRASS_HI.g, COL_BRASS_HI.b, alpha)
	var state_tag := R18n.pick("已锁定", "LOCKED") if _cplus_state == State.SELECTED else R18n.pick("靠近锁定", "APPROACH")
	draw_string(_font, Vector2(left_x + 14.0, top_y + 18.0), state_tag, HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(COL_INK_2.r, COL_INK_2.g, COL_INK_2.b, 0.85 * alpha))
	var title_w := _font.get_string_size(group_title, HORIZONTAL_ALIGNMENT_LEFT, -1, 15).x
	draw_string(_font, Vector2(right_x - title_w - 4.0, top_y + 19.0), group_title, HORIZONTAL_ALIGNMENT_LEFT, -1, 15, title_col)
	draw_line(Vector2(left_x + 12.0, top_y + header_h), Vector2(right_x, top_y + header_h), Color(COL_BRASS.r, COL_BRASS.g, COL_BRASS.b, 0.50 * alpha), 1.0, true)

	# Action rows (E + Wheel OR 1/2/3 direct)
	for i in hotspots.size():
		var h: Dictionary = hotspots[i]
		var ry := top_y + header_h + 6.0 + i * row_h
		var is_sel := (_cplus_state == State.SELECTED and i == _cplus_index)
		if is_sel:
			draw_rect(Rect2(left_x + 10.0, ry, bar_w - 10.0, row_h - 3.0), Color(COL_BRASS.r, COL_BRASS.g, COL_BRASS.b, 0.22 * alpha), true)
		var verb := str(h.get("verb", ""))
		var key_str := "E" if is_sel else str(i + 1)
		var key_rect := Rect2(right_x - 26.0, ry + 3.0, 22.0, 21.0)
		draw_rect(key_rect, Color(0.06, 0.075, 0.11, 0.88 * alpha), true)
		var k_border := Color(COL_BRASS_HI.r, COL_BRASS_HI.g, COL_BRASS_HI.b, alpha) if is_sel else Color(COL_BRASS.r, COL_BRASS.g, COL_BRASS.b, 0.65 * alpha)
		draw_rect(key_rect, k_border, false, 1.2)
		var kw := _font.get_string_size(key_str, HORIZONTAL_ALIGNMENT_LEFT, -1, 12).x
		draw_string(_font, Vector2(key_rect.position.x + (key_rect.size.x - kw) * 0.5, key_rect.position.y + 15.0), key_str, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, k_border)

		var vw := _font.get_string_size(verb, HORIZONTAL_ALIGNMENT_LEFT, -1, 14).x
		var vcol := Color(COL_INK.r, COL_INK.g, COL_INK.b, alpha) if is_sel else Color(COL_INK_2.r, COL_INK_2.g, COL_INK_2.b, 0.90 * alpha)
		draw_string(_font, Vector2(key_rect.position.x - vw - 10.0, ry + 18.0), verb, HORIZONTAL_ALIGNMENT_LEFT, -1, 14, vcol)

	if _cplus_state == State.SELECTED:
		var tip := R18n.pick("滚轮 / 1-3 切换 · 按 E 执行", "Wheel / 1-3 select · E confirm")
		var tw := _font.get_string_size(tip, HORIZONTAL_ALIGNMENT_LEFT, -1, 11).x
		draw_string(_font, Vector2(right_x - tw - 2.0, bottom_y - 3.0), tip, HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(COL_INK_2.r, COL_INK_2.g, COL_INK_2.b, 0.72))

func _draw_detroit() -> void:
	var pulse := 0.5 + 0.5 * sin(_time * 3.0)
	for i in hotspots.size():
		var h: Dictionary = hotspots[i]
		var id := str(h.get("id", ""))
		var st := int(_detroit_states.get(id, State.NONE))
		if st == State.NONE:
			continue
		var proj := _project_to_control(h.get("world_pos", primary_anchor_world))
		if not proj.visible:
			continue
		var p: Vector2 = proj.pos

		if st == State.POTENTIAL:
			# State 1: subtle 7px pale-brass micro diamond, zero leader line, zero text
			_draw_diamond(p, 4.5, Color(COL_BRASS_HI.r, COL_BRASS_HI.g, COL_BRASS_HI.b, 0.16 + pulse * 0.14), Color(COL_BRASS_HI.r, COL_BRASS_HI.g, COL_BRASS_HI.b, 0.45 + pulse * 0.25), 1.0)
			continue

		var dir_x := -1.0 if p.x < size.x * 0.44 else 1.0
		var elbow_dx := 48.0 if st == State.SELECTED else 34.0
		var elbow_dy := -54.0 if st == State.SELECTED else -32.0
		var elbow := p + Vector2(dir_x * elbow_dx, elbow_dy)
		var part_name := str(h.get("part_name", ""))
		var verb := str(h.get("verb", ""))

		if st == State.ACTIVATABLE:
			# State 2: crisp 14px hollow diamond + thin muted leader + quiet part label
			_draw_diamond(p, 8.0, Color(0.05, 0.06, 0.09, 0.55), Color(COL_BRASS.r, COL_BRASS.g, COL_BRASS.b, 0.85), 1.4)
			_draw_diamond(p, 2.8, Color(COL_BRASS.r, COL_BRASS.g, COL_BRASS.b, 0.65), Color.TRANSPARENT, 0.0)
			var pw := _font.get_string_size(part_name, HORIZONTAL_ALIGNMENT_LEFT, -1, 12).x
			var seg_len := pw + 22.0
			var end_pt := elbow + Vector2(dir_x * seg_len, 0.0)
			draw_polyline(PackedVector2Array([p, elbow, end_pt]), Color(COL_BRASS.r, COL_BRASS.g, COL_BRASS.b, 0.48), 1.1, true)
			var tx := elbow.x + 8.0 if dir_x > 0.0 else end_pt.x + 8.0
			draw_rect(Rect2(tx - 6.0, elbow.y - 23.0, pw + 14.0, 21.0), COL_BG_SOFT, true)
			draw_string(_font, Vector2(tx, elbow.y - 8.0), part_name, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(COL_INK_2.r, COL_INK_2.g, COL_INK_2.b, 0.88))
		elif st == State.SELECTED:
			# State 3: high-precision glowing brass diamond + inner ring + sharp 45-deg leader + [E] action bar
			_draw_diamond(p, 14.5, Color(COL_BRASS.r, COL_BRASS.g, COL_BRASS.b, 0.20), COL_BRASS_HI, 2.0)
			draw_arc(p, 8.0, 0.0, TAU, 24, Color(COL_BRASS_HI.r, COL_BRASS_HI.g, COL_BRASS_HI.b, 0.85), 1.1, true)
			draw_circle(p, 2.6, COL_BRASS_HI)

			var pw := _font.get_string_size(part_name, HORIZONTAL_ALIGNMENT_LEFT, -1, 15).x
			var vw := _font.get_string_size(verb, HORIZONTAL_ALIGNMENT_LEFT, -1, 13).x + 32.0
			var box_w := maxf(pw, vw) + 26.0
			var end_pt := elbow + Vector2(dir_x * box_w, 0.0)
			draw_polyline(PackedVector2Array([p, elbow, end_pt]), COL_BRASS_HI, 1.8, true)

			var bx := elbow.x if dir_x > 0.0 else end_pt.x
			var box_rect := Rect2(bx, elbow.y - 50.0, box_w, 48.0)
			draw_rect(box_rect, COL_BG_DARK, true)
			draw_string(_font, Vector2(bx + 10.0, elbow.y - 31.0), part_name, HORIZONTAL_ALIGNMENT_LEFT, -1, 15, COL_INK)

			var krect := Rect2(bx + 10.0, elbow.y - 23.0, 20.0, 18.0)
			draw_rect(krect, Color(COL_BRASS.r, COL_BRASS.g, COL_BRASS.b, 0.24), true)
			draw_rect(krect, COL_BRASS_HI, false, 1.2)
			draw_string(_font, Vector2(krect.position.x + 6.0, krect.position.y + 13.5), "E", HORIZONTAL_ALIGNMENT_LEFT, -1, 11, COL_BRASS_HI)
			draw_string(_font, Vector2(krect.position.x + 28.0, krect.position.y + 14.0), verb, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, COL_BRASS_HI)
