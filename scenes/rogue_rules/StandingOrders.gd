extends VBoxContainer
## Player-authored standing orders. The caller owns the encounter and its consequences.

var _rules: Array[Dictionary] = []
var _context := {}
var _used := {}
var _editing := -1
var _next_id := 1
var _replace_condition := false
var _list := OptionButton.new()
var _action := OptionButton.new()
var _condition := Label.new()
var _notice := Label.new()
var _save := Button.new()
var _delete := Button.new()
var _use_here := CheckButton.new()

func _ready() -> void:
	var title := Label.new()
	title.text = "Standing orders"
	add_child(title)
	var row := HFlowContainer.new()
	add_child(row)
	row.add_child(_list)
	row.add_child(_save)
	row.add_child(_delete)
	_save.pressed.connect(_save_selected)
	_delete.text = "Delete selected order"
	_delete.pressed.connect(_delete_selected)
	_list.item_selected.connect(_select_rule)
	_use_here.text = "Use current observation"
	_use_here.toggled.connect(func(value: bool):
		_replace_condition = value
		_rebuild()
	)
	add_child(_use_here)
	_condition.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(_condition)
	add_child(_action)
	_notice.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(_notice)
	_rebuild()

## Keys: encounter_id, room_type (visible label), clue (visible text), options, observed,
## in_guide, at_camp. Only supply a clue/options the player has actually seen.
func set_context(context: Dictionary) -> void:
	if _context == context: return
	_context = context.duplicate(true)
	if is_node_ready(): _rebuild()

## Returns {} or a single decision for an observed field encounter. Call at the
## inspection boundary, then pass option_index through the same resolver as a click.
func try_order(context: Dictionary) -> Dictionary:
	if not _eligible(context): return {}
	var encounter: String = context.encounter_id
	if _used.has(encounter): return {}
	var options := Array(context.options)
	for rule in _rules:
		if rule.room_type != context.room_type or rule.clue != context.clue: continue
		var index := _unique_option(options, rule.action)
		if index == -1: continue
		_used[encounter] = true
		return {"rule_id": rule.id, "action": rule.action, "option_index": index,
			"command_beats_saved": 1, "action_beats_saved": 0, "action_beats": 1}
	return {}

## The player's explicit save operation. Return a stable rule ID or -1.
## Existing orders may update their action; checking "Use current observation"
## changes their condition too. Actions always come from an observed menu.
func save_order(context: Dictionary, action: String, rule_id := -1, use_current := true) -> int:
	if _blocked(context): return -1
	var index := _index_of(rule_id)
	if rule_id != -1 and index == -1: return -1
	var source := context
	if index != -1 and not use_current:
		source = _rules[index]
	elif not _eligible(context):
		return -1
	var options := Array(source.options)
	if _unique_option(options, action) == -1: return -1
	var rule := {"id": rule_id, "room_type": source.room_type, "clue": source.clue,
		"options": options.duplicate(), "action": action}
	for other in _rules:
		if other.id != rule_id and other.room_type == rule.room_type and other.clue == rule.clue:
			return -1
	if index == -1:
		rule.id = _next_id
		_next_id += 1
		_rules.append(rule)
	else:
		_rules[index] = rule
	return rule.id

func delete_order(rule_id: int) -> bool:
	var index := _index_of(rule_id)
	if index == -1: return false
	_rules.remove_at(index)
	return true

func orders() -> Array[Dictionary]:
	return _rules.duplicate(true)

## Scope orders and once-per-encounter protection to the current run.
func reset() -> void:
	_rules.clear()
	_used.clear()
	_context.clear()
	_editing = -1
	_replace_condition = false
	_next_id = 1
	if is_node_ready(): _rebuild()

func _index_of(rule_id: int) -> int:
	for i in range(_rules.size()):
		if _rules[i].id == rule_id: return i
	return -1

func _blocked(context: Dictionary) -> bool:
	return context.get("in_guide", false) or context.get("at_camp", false)

func _eligible(context: Dictionary) -> bool:
	if _blocked(context) or context.get("observed") != true: return false
	for key in ["encounter_id", "room_type", "clue"]:
		if not context.get(key) is String or context[key].strip_edges().is_empty(): return false
	return (context.get("options") is Array or context.get("options") is PackedStringArray) and not context.options.is_empty()

func _unique_option(options: Array, text: String) -> int:
	if text.strip_edges().is_empty(): return -1
	var index := options.find(text)
	return index if index >= 0 and options.find(text, index + 1) == -1 else -1

func _select_rule(index: int) -> void:
	_editing = _list.get_item_id(index) if index > 0 else -1
	_replace_condition = false
	_rebuild()

func _rebuild() -> void:
	visible = not _blocked(_context) and (_eligible(_context) or not _rules.is_empty())
	_list.clear()
	_list.add_item("New order")
	var selected := 0
	for rule in _rules:
		_list.add_item("%s: %s" % [rule.room_type, rule.action], rule.id)
		if rule.id == _editing: selected = _list.item_count - 1
	_list.select(selected)
	var index := _index_of(_editing)
	_use_here.visible = index != -1 and _eligible(_context)
	_use_here.set_pressed_no_signal(_replace_condition and _use_here.visible)
	var source := _rules[index] if index != -1 and not _use_here.button_pressed else _context
	var can_save := index != -1 or _eligible(_context)
	_condition.text = "%s · %s" % [source.room_type, source.clue] if can_save else "Inspect a field encounter to author an order."
	_action.clear()
	if can_save:
		for option in source.options:
			if option is String and _unique_option(Array(source.options), option) >= 0: _action.add_item(option)
		if index != -1 and not _use_here.button_pressed:
			for i in range(_action.item_count):
				if _action.get_item_text(i) == source.action: _action.select(i)
		else:
			_action.select(-1)
	_save.text = "Update order" if index != -1 else "Commit order"
	_save.disabled = not can_save or _action.item_count == 0
	_delete.disabled = index == -1
	_notice.text = "A matching order skips one command beat. The action still takes a beat and has its usual consequences."

func _save_selected() -> void:
	if _action.selected == -1:
		_notice.text = "Choose the exact action the team should take."
		return
	var id := save_order(_context, _action.get_item_text(_action.selected), _editing, _editing == -1 or _use_here.button_pressed)
	if id == -1:
		_notice.text = "That condition already has an order. Select it above to edit or delete it."
		return
	_editing = id
	_replace_condition = false
	_rebuild()
	_notice.text = "Order saved. It will run on a matching field observation."

func _delete_selected() -> void:
	delete_order(_editing)
	_editing = -1
	_replace_condition = false
	_rebuild()
