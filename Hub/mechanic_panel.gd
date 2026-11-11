class_name MechanicPanel
extends HubPanel

# The mechanic: fit the ship, buy modules, sell spares, repair the hull.
# Left: the ship as it is (ShipPreview) with a marker on each slot, then the same slots as a list
# of buttons (what's fitted in each), and the ship's stats. Click a slot, on the ship or in the list.
# Right: what can go in the selected slot, then the spares in storage.
#
# Rooms take the size of their slot: they're bought for a slot (price scaled by its area) and the
# old one is sold back when replaced. Hardpoints and soft points move to and from the spares.
# All the rules (prices, what goes where) are in GameState; this panel only shows and asks.

const KIND_NAMES := ["Room slot", "Hardpoint", "Soft point mount"]

var _preview: ShipPreview
var _slot_list: VBoxContainer
var _slot_group := ButtonGroup.new()
var _stats: Label
var _hull_label: Label
var _repair: Button
var _slot_title: Label
var _options: VBoxContainer
var _spares: VBoxContainer
var _kind: int = GameState.Kind.ROOM
var _index: int = 0


func _init() -> void:
	super("MECHANIC")
	custom_minimum_size = Vector2(1180.0, 0.0)
	size = custom_minimum_size


func _build() -> void:
	var columns := HBoxContainer.new()
	columns.add_theme_constant_override(&"separation", 20)
	body.add_child(columns)

	# Left: ship, stats, repairs
	var left := VBoxContainer.new()
	left.add_theme_constant_override(&"separation", 8)
	columns.add_child(left)

	var frame := PanelContainer.new()
	frame.add_theme_stylebox_override(&"panel", HubStyle.box(Color(0.03, 0.03, 0.05), CockpitPalette.OUTLINE, 3, 0))
	left.add_child(frame)
	_preview = ShipPreview.new()
	_preview.custom_minimum_size = Vector2(600.0, 340.0)
	_preview.slot_pressed.connect(_on_slot_pressed)
	_preview.built.connect(_refresh_stats)
	frame.add_child(_preview)

	left.add_child(HubStyle.label("Click a slot, on the ship or below, to change what's fitted there.", 15, HubStyle.ACCENT))
	_slot_list = VBoxContainer.new()
	_slot_list.add_theme_constant_override(&"separation", 4)
	left.add_child(_slot_list)
	_stats = HubStyle.label("", 15)
	left.add_child(_stats)
	left.add_child(HubStyle.label("Computer, generator, grinder and thrusters: one model each for now.", 13, HubStyle.DIM))

	var repair_row := HBoxContainer.new()
	repair_row.add_theme_constant_override(&"separation", 12)
	left.add_child(repair_row)
	_hull_label = HubStyle.label("", 17)
	repair_row.add_child(_hull_label)
	_repair = HubStyle.button("", 15)
	_repair.pressed.connect(func() -> void: GameState.repair_hull())
	repair_row.add_child(_repair)

	# Right: the selected slot, then the spares
	var right := VBoxContainer.new()
	right.add_theme_constant_override(&"separation", 8)
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	columns.add_child(right)

	_slot_title = HubStyle.label("", 18, HubStyle.GOOD)
	right.add_child(_slot_title)
	right.add_child(_scrolling(260.0, func(box: VBoxContainer) -> void: _options = box))
	right.add_child(HubStyle.label("SPARES IN STORAGE (sell for %d%% of the price)" % roundi(GameState.ECONOMY.sell_back_rate * 100.0), 13, HubStyle.DIM))
	right.add_child(_scrolling(150.0, func(box: VBoxContainer) -> void: _spares = box))

	GameState.loadout_changed.connect(_on_loadout_changed)
	GameState.credits_changed.connect(refresh)


func _ready() -> void:
	super()
	_preview.show_loadout(GameState.loadout)
	_on_slot_pressed(_kind, _index)


func refresh() -> void:
	if _options == null:
		return

	var repair_cost := GameState.get_repair_cost()
	_hull_label.text = "Hull %d%%" % roundi(GameState.hull_ratio * 100.0)
	_hull_label.add_theme_color_override(&"font_color", HubStyle.BAD if GameState.needs_repair() else HubStyle.TEXT)
	_repair.text = "REPAIR   %s" % HubStyle.format_credits(repair_cost) if repair_cost > 0 else "NO REPAIRS NEEDED"
	_repair.disabled = repair_cost <= 0 or not GameState.can_afford(repair_cost)

	_refresh_slot_list()
	_refresh_options()
	_refresh_spares()


func _on_loadout_changed() -> void:
	_preview.show_loadout(GameState.loadout)
	_preview.select(_kind, _index)
	refresh()


func _on_slot_pressed(kind: int, index: int) -> void:
	_kind = kind
	_index = index
	_preview.select(kind, index)
	refresh()


# One row per kind of slot: a button for each, named after what's fitted in it.
func _refresh_slot_list() -> void:
	for child in _slot_list.get_children():
		child.queue_free()

	var rows := [
		[GameState.Kind.HARDPOINT, "HARDPOINTS"],
		[GameState.Kind.SOFT_POINT, "SOFT POINTS"],
		[GameState.Kind.ROOM, "ROOMS"],
	]

	for row_info in rows:
		var kind: int = row_info[0]
		var row := HBoxContainer.new()
		row.add_theme_constant_override(&"separation", 8)
		_slot_list.add_child(row)

		var title := HubStyle.label(row_info[1], 13, ShipPreview.KIND_COLORS[kind])
		title.custom_minimum_size = Vector2(100.0, 0.0)
		row.add_child(title)

		var flow := HFlowContainer.new()
		flow.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		flow.add_theme_constant_override(&"h_separation", 4)
		flow.add_theme_constant_override(&"v_separation", 4)
		row.add_child(flow)

		var slots := GameState.get_slots(kind)

		for index in slots.size():
			var type: int = slots[index]
			var name := "empty" if type == ShipLoadout.EMPTY else GameState.get_type_name(kind, type)
			var button := HubStyle.choice("%s%d  %s" % [ShipPreview.KIND_LETTERS[kind], index + 1, name], _slot_group)
			button.custom_minimum_size = Vector2(0.0, 28.0)
			button.add_theme_font_size_override(&"font_size", 13)
			button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
			button.set_pressed_no_signal(kind == _kind and index == _index)
			button.pressed.connect(_on_slot_pressed.bind(kind, index))
			flow.add_child(button)


func _refresh_stats() -> void:
	var stats := _preview.get_stats()
	_stats.text = "Mass %.1f   Ore bins %d cells   Ingots %d u   Smelter %d cells   Fuel %d   Ammo %d   Battery %d" % [stats.mass, stats.ore_bin, stats.ingots, stats.smelter, stats.fuel, stats.ammo, stats.battery]


func _refresh_options() -> void:
	for child in _options.get_children():
		child.queue_free()

	var slots := GameState.get_slots(_kind)

	if _index >= slots.size():
		return

	var current: int = slots[_index]
	var title := "%s %d" % [KIND_NAMES[_kind], _index + 1]

	if _kind == GameState.Kind.ROOM:
		var slot_size: Vector2 = GameState.get_hull_layout().room_sizes[_index] / Room.TEXEL
		title += " (%d×%d)" % [slot_size.x, slot_size.y]

	_slot_title.text = "%s: %s" % [title, "empty" if current == ShipLoadout.EMPTY else GameState.get_type_name(_kind, current)]

	if current != ShipLoadout.EMPTY:
		var take_off := "Sell it back   +%s" % HubStyle.format_credits(GameState.get_module_sell_price(_kind, current, _index)) if _kind == GameState.Kind.ROOM else "Take it off (to the spares)"
		_add_option(take_off, ShipLoadout.EMPTY)

	for type in GameState.get_type_count(_kind):
		if type == current:
			continue

		var cost := GameState.get_fit_cost(_kind, _index, type)
		var name := GameState.get_type_name(_kind, type)
		var text := ""

		if _kind != GameState.Kind.ROOM and GameState.get_spare_count(_kind, type) > 0:
			text = "Fit %s from the spares" % name
		elif cost < 0:
			text = "Fit %s   +%s back" % [name, HubStyle.format_credits(-cost)]
		else:
			text = "Fit %s   %s" % [name, HubStyle.format_credits(cost)]

		_add_option(text, type)


func _add_option(text: String, type: int) -> void:
	var button := HubStyle.choice(text, null)
	button.toggle_mode = false
	var cost := GameState.get_fit_cost(_kind, _index, type)
	button.disabled = cost > 0 and not GameState.can_afford(cost)
	button.pressed.connect(func() -> void: GameState.fit(_kind, _index, type))
	_options.add_child(button)


func _refresh_spares() -> void:
	for child in _spares.get_children():
		child.queue_free()

	if GameState.spares.is_empty():
		_spares.add_child(HubStyle.label("Nothing in storage.", 15, HubStyle.DIM))
		return

	for kind in [GameState.Kind.HARDPOINT, GameState.Kind.SOFT_POINT]:
		for type in GameState.get_type_count(kind):
			var count := GameState.get_spare_count(kind, type)

			if count <= 0:
				continue

			var button := HubStyle.choice("%s ×%d   sell one for %s" % [GameState.get_type_name(kind, type), count, HubStyle.format_credits(GameState.get_module_sell_price(kind, type))], null)
			button.toggle_mode = false
			button.pressed.connect(func() -> void: GameState.sell_spare(kind, type))
			_spares.add_child(button)


# A scroll box of `height` px holding a VBoxContainer, handed to `keep` so the caller can fill it.
func _scrolling(height: float, keep: Callable) -> ScrollContainer:
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(0.0, height)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	var box := VBoxContainer.new()
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.add_theme_constant_override(&"separation", 4)
	scroll.add_child(box)
	keep.call(box)
	return scroll
