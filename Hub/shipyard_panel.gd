class_name ShipyardPanel
extends HubPanel

# The shipyard: buy hulls, and pick which of your ships you fly.
# Left: the hulls for sale. Each is shown as it's delivered, with its rooms but no hardpoints or
# soft points (that's the mechanic's job). Right: your ships.
# Switching ships asks whether the hardpoints and soft points come along (GameState.switch_ship).

var _hull_buttons: Array[Button] = []
var _hull_group := ButtonGroup.new()
var _preview: ShipPreview
var _hull_info: Label
var _buy: Button
var _ships: VBoxContainer
var _selected_hull: int = 0
var _pending_switch: int = -1 # Ship waiting for the "bring the modules?" answer


func _init() -> void:
	super("SHIPYARD")
	custom_minimum_size = Vector2(1180.0, 0.0)
	size = custom_minimum_size


func _build() -> void:
	var columns := HBoxContainer.new()
	columns.add_theme_constant_override(&"separation", 20)
	body.add_child(columns)

	var left := VBoxContainer.new()
	left.add_theme_constant_override(&"separation", 8)
	columns.add_child(left)
	left.add_child(HubStyle.label("HULLS FOR SALE (delivered with their rooms, nothing else fitted)", 13, HubStyle.DIM))

	var list := HBoxContainer.new()
	list.add_theme_constant_override(&"separation", 6)
	left.add_child(list)

	for i in GameState.ECONOMY.hulls.size():
		var hull := GameState.ECONOMY.hulls[i]
		var button := HubStyle.choice("%s   %s" % [hull.display_name, HubStyle.format_credits(hull.price)], _hull_group)
		button.toggled.connect(func(on: bool) -> void:
			if on:
				_select_hull(i))
		list.add_child(button)
		_hull_buttons.append(button)

	var frame := PanelContainer.new()
	frame.add_theme_stylebox_override(&"panel", HubStyle.box(Color(0.03, 0.03, 0.05), CockpitPalette.OUTLINE, 3, 0))
	left.add_child(frame)
	_preview = ShipPreview.new()
	_preview.custom_minimum_size = Vector2(600.0, 320.0)
	frame.add_child(_preview)

	_hull_info = HubStyle.label("", 15)
	_hull_info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_hull_info.custom_minimum_size = Vector2(600.0, 0.0)
	left.add_child(_hull_info)

	_buy = HubStyle.button("", 18)
	_buy.pressed.connect(_on_buy)
	left.add_child(_buy)

	var right := VBoxContainer.new()
	right.add_theme_constant_override(&"separation", 8)
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	columns.add_child(right)
	right.add_child(HubStyle.label("YOUR SHIPS", 13, HubStyle.DIM))
	_ships = VBoxContainer.new()
	_ships.add_theme_constant_override(&"separation", 6)
	right.add_child(_ships)

	GameState.credits_changed.connect(refresh)
	GameState.loadout_changed.connect(refresh)


func _ready() -> void:
	super()
	_hull_buttons[0].button_pressed = true


func refresh() -> void:
	if _ships == null:
		return

	var hull := GameState.ECONOMY.hulls[_selected_hull]
	_buy.text = "BUY %s   %s" % [hull.display_name.to_upper(), HubStyle.format_credits(hull.price)]
	_buy.disabled = not GameState.can_afford(hull.price)
	_refresh_ships()


func _select_hull(index: int) -> void:
	_selected_hull = index
	var hull := GameState.ECONOMY.hulls[index]
	var delivered := GameState.make_ship(hull.id, false)
	_preview.show_loadout(delivered)
	var stats := _preview.get_stats()
	_hull_info.text = "%s\n%d room slots · %d hardpoints · %d soft points · mass %.1f empty · ore bins %d cells · ingots %d u · fuel %d" % [
		hull.description, delivered.rooms.size(), delivered.hardpoints.size(), delivered.soft_points.size(),
		stats.mass, stats.ore_bin, stats.ingots, stats.fuel]
	refresh()


func _refresh_ships() -> void:
	for child in _ships.get_children():
		child.queue_free()

	for i in GameState.ships.size():
		var ship := GameState.ships[i]
		var hull := GameState.ECONOMY.get_hull(ship.hull_id)
		var fitted := ship.hardpoints.filter(func(t: int) -> bool: return t != ShipLoadout.EMPTY).size() + ship.soft_points.filter(func(t: int) -> bool: return t != ShipLoadout.EMPTY).size()
		var row := VBoxContainer.new()
		row.add_theme_constant_override(&"separation", 4)
		_ships.add_child(row)
		row.add_child(HubStyle.label("%s   hull %d%%   %d modules fitted" % [hull.display_name, roundi(ship.hull_ratio * 100.0), fitted], 17))

		if i == GameState.active_ship:
			row.add_child(HubStyle.label("You're flying this one.", 14, HubStyle.GOOD))
		elif i == _pending_switch:
			row.add_child(HubStyle.label("Bring your hardpoints and soft points over? What doesn't fit goes to the spares.", 14, HubStyle.TEXT))
			var answers := HBoxContainer.new()
			answers.add_theme_constant_override(&"separation", 6)
			row.add_child(answers)
			_add_answer(answers, "BRING THEM", func() -> void: _switch(i, true))
			_add_answer(answers, "LEAVE THEM", func() -> void: _switch(i, false))
			_add_answer(answers, "CANCEL", func() -> void:
				_pending_switch = -1
				refresh())
		else:
			_add_answer(row, "FLY THIS ONE", func() -> void:
				_pending_switch = i
				refresh())


func _add_answer(parent: Container, text: String, action: Callable) -> void:
	var button := HubStyle.button(text, 14)
	button.pressed.connect(action)
	parent.add_child(button)


func _switch(index: int, move_modules: bool) -> void:
	_pending_switch = -1
	GameState.switch_ship(index, move_modules)


func _on_buy() -> void:
	GameState.buy_hull(GameState.ECONOMY.hulls[_selected_hull].id)
