class_name UndockPanel
extends HubPanel

# Undock: pick a drop point on the map of today's mothership route, an insurance plan, refuel and
# rearm, see the total, board the mothership.
# The drop fee is shown as it is worked out (DropQuote): line fare for the depth × transfer for
# the distance to the route. The route leg nearest to the drop point is used: it's the cheapest.
# A player who can't pay for anything gets a free, uninsured drop anywhere it costs up to
# EconomyConfig.free_drop_max_fee.

const WIDTH: float = 1180.0
const MAP_SIZE := Vector2(700.0, 520.0)
const DEFAULT_DEPTH: float = 20.0 # km. Where the pin starts: on the outbound leg

# The last pick, kept while the route is the same (closing and opening the panel).
static var _kept_pick := Vector2.ZERO
static var _kept_seed: int = -1

var _route: BeltRoute
var _drop: DropQuote
var _plan_group := ButtonGroup.new()
var _plan_buttons: Array[Button] = []
var _map: DropMap
var _place: Label
var _hop: Label
var _fare_label: Label
var _fare_value: Label
var _transfer_label: Label
var _transfer_value: Label
var _fee_value: Label
var _fare_curve: CostCurve
var _transfer_curve: CostCurve
var _plan_info: Label
var _refit: CheckBox
var _warning: Label
var _total: Label
var _pickup: Label
var _go: Button


func _init() -> void:
	super("UNDOCK")
	custom_minimum_size = Vector2(WIDTH, 0)
	size = Vector2(WIDTH, 0)


func _build() -> void:
	var economy := GameState.ECONOMY
	_route = GameState.get_next_route()

	var columns := HBoxContainer.new()
	columns.add_theme_constant_override(&"separation", 18)
	body.add_child(columns)

	_map = DropMap.new()
	_map.custom_minimum_size = MAP_SIZE
	_map.setup(_route, GameState.get_next_run_seed())
	_map.point_picked.connect(_on_point_picked)
	var frame := PanelContainer.new()
	frame.add_theme_stylebox_override(&"panel", HubStyle.box(Color.BLACK, CockpitPalette.OUTLINE, 3, 0))
	frame.add_child(_map)
	columns.add_child(frame)

	var side := VBoxContainer.new()
	side.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	side.add_theme_constant_override(&"separation", 6)
	columns.add_child(side)

	side.add_child(HubStyle.label("DROP POINT  ·  click the map", 13, HubStyle.DIM))
	_place = HubStyle.label("", 17)
	side.add_child(_place)
	_hop = HubStyle.label("", 13, HubStyle.DIM)
	_hop.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	side.add_child(_hop)

	# The fee, worked out line by line.
	var ledger := PanelContainer.new()
	ledger.add_theme_stylebox_override(&"panel", HubStyle.box(Color(0.12, 0.12, 0.11), CockpitPalette.OUTLINE, 2, 8))
	side.add_child(ledger)
	var rows := GridContainer.new()
	rows.columns = 2
	rows.add_theme_constant_override(&"h_separation", 12)
	rows.add_theme_constant_override(&"v_separation", 2)
	ledger.add_child(rows)
	_fare_label = _add_row(rows, 15, HubStyle.TEXT)
	_fare_value = rows.get_child(-1) as Label
	_transfer_label = _add_row(rows, 15, HubStyle.GOOD)
	_transfer_value = rows.get_child(-1) as Label
	_add_row(rows, 17, HubStyle.ACCENT).text = "= Drop fee"
	_fee_value = rows.get_child(-1) as Label

	var curves := HBoxContainer.new()
	curves.add_theme_constant_override(&"separation", 8)
	side.add_child(curves)
	_fare_curve = CostCurve.new()
	_fare_curve.title = "LINE FARE BY DEPTH"
	_fare_curve.curve = DropQuote.get_fare
	_fare_curve.x_max = economy.belt.depth_km
	_fare_curve.y_min = economy.drop_fare_top
	_fare_curve.y_max = economy.drop_fare_bottom
	_fare_curve.right_text = "%d km" % roundi(economy.belt.depth_km)
	_fare_curve.top_text = HubStyle.format_credits(roundi(economy.drop_fare_bottom))
	_fare_curve.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	curves.add_child(_fare_curve)
	_transfer_curve = CostCurve.new()
	_transfer_curve.title = "TRANSFER"
	_transfer_curve.curve = DropQuote.get_multiplier
	_transfer_curve.x_max = 15.0
	_transfer_curve.y_min = 1.0
	_transfer_curve.y_max = DropQuote.get_multiplier(15.0)
	_transfer_curve.color = CockpitPalette.SCOPE
	_transfer_curve.left_text = "on the route"
	_transfer_curve.right_text = "15 km off"
	_transfer_curve.top_text = "×%.1f" % DropQuote.get_multiplier(15.0)
	_transfer_curve.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	curves.add_child(_transfer_curve)

	side.add_child(HubStyle.label("INSURANCE (cargo is never covered)", 13, HubStyle.DIM))
	var plans := HBoxContainer.new()
	plans.add_theme_constant_override(&"separation", 6)
	side.add_child(plans)

	for i in economy.insurance_plans.size():
		var plan := economy.insurance_plans[i]
		var button := HubStyle.choice("%s  %s" % [plan.display_name, HubStyle.format_credits(GameState.get_premium(i))], _plan_group)
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.add_theme_font_size_override(&"font_size", 14)
		button.toggled.connect(func(_on: bool) -> void: refresh())
		plans.add_child(button)
		_plan_buttons.append(button)

	_plan_buttons[0].button_pressed = true
	_plan_info = HubStyle.label("", 13, HubStyle.DIM)
	side.add_child(_plan_info)

	_refit = CheckBox.new()
	_refit.button_pressed = true
	_refit.add_theme_font_size_override(&"font_size", 15)
	_refit.toggled.connect(func(_on: bool) -> void: refresh())
	side.add_child(_refit)

	_warning = HubStyle.label("", 14, HubStyle.BAD)
	_warning.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	side.add_child(_warning)

	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	side.add_child(spacer)

	_total = HubStyle.label("", 19)
	_total.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	side.add_child(_total)
	_pickup = HubStyle.label("", 13, HubStyle.DIM)
	_pickup.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	side.add_child(_pickup)

	_go = HubStyle.button("BOARD THE MOTHERSHIP", 20)
	_go.custom_minimum_size = Vector2(0, 46)
	_go.pressed.connect(_on_go)
	side.add_child(_go)

	GameState.credits_changed.connect(refresh)

	var seed_value := GameState.get_next_run_seed()
	_map.pick(_kept_pick if _kept_seed == seed_value else _get_default_pick())


func refresh() -> void:
	if _go == null or _drop == null: # Pressing the default choices in _build() calls this before the panel is complete
		return

	var economy := GameState.ECONOMY
	_place.text = "%d km into the belt · %.1f km from the route" % [roundi(_drop.depth), _drop.hop.distance]
	_hop.text = "Hop off on the %s: the nearest leg, so the cheapest." % _drop.get_leg_text()
	_fare_label.text = "Line fare at %d km" % roundi(_drop.depth)
	_fare_value.text = HubStyle.format_credits(roundi(_drop.fare))
	_transfer_label.text = "× Transfer, %.1f km off the route" % _drop.hop.distance
	_transfer_value.text = "×%.2f" % _drop.multiplier
	_fee_value.text = HubStyle.format_credits(_drop.fee)
	_fare_curve.set_marker(_drop.depth, HubStyle.format_credits(roundi(_drop.fare)))
	_transfer_curve.set_marker(_drop.hop.distance, "×%.2f" % _drop.multiplier)

	var plan_index := _get_pressed(_plan_buttons)
	_plan_info.text = economy.insurance_plans[plan_index].description

	var refit_cost := GameState.get_refit_cost()
	_refit.disabled = refit_cost <= 0
	_refit.text = "Refuel and rearm   %s" % HubStyle.format_credits(refit_cost) if refit_cost > 0 else "Tanks and racks are full"

	var warnings: PackedStringArray = []

	if GameState.needs_repair():
		warnings.append("Hull at %d%%. The mechanic can patch it before you go." % roundi(GameState.hull_ratio * 100.0))

	if not _refit.button_pressed and refit_cost > 0:
		warnings.append("You'll leave with what's left in the tanks and racks.")

	_warning.text = "\n".join(warnings)
	_warning.visible = not warnings.is_empty()

	var refit := _refit.button_pressed and refit_cost > 0
	var cost := GameState.get_undock_cost(_drop, plan_index, refit)
	var pickup := roundi(_drop.fee * economy.pickup_fee_multiplier)
	_pickup.text = "Later, the pickup call: drop fee × %s = %s" % [str(economy.pickup_fee_multiplier), HubStyle.format_credits(pickup)]

	if GameState.is_broke():
		var is_free := GameState.is_free_drop(_drop, plan_index)
		_total.text = "Free drop: the Union pays for broke miners, uninsured, up to %s." % HubStyle.format_credits(economy.free_drop_max_fee)
		_go.disabled = not is_free
	elif GameState.can_afford(cost):
		_total.text = "PAY NOW %s   (wallet %s)" % [HubStyle.format_credits(cost), HubStyle.format_credits(GameState.credits)]
		_go.disabled = false
	else:
		_total.text = "PAY NOW %s. Not enough credits: sell some ore first." % HubStyle.format_credits(cost)
		_go.disabled = true


# A label and its value, right-aligned in the next column. Returns the label.
func _add_row(rows: GridContainer, font_size: int, value_color: Color) -> Label:
	var name_label := HubStyle.label("", font_size)
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	rows.add_child(name_label)
	var value := HubStyle.label("", font_size, value_color)
	value.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	rows.add_child(value)
	return name_label


# On the outbound leg, DEFAULT_DEPTH km out.
func _get_default_pick() -> Vector2:
	for point in _route.outbound:
		if point.x >= DEFAULT_DEPTH:
			return point

	return _route.outbound[0]


func _get_pressed(buttons: Array[Button]) -> int:
	for i in buttons.size():
		if buttons[i].button_pressed:
			return i

	return 0


func _on_point_picked(km: Vector2) -> void:
	_drop = DropQuote.create(_route, km)
	_kept_pick = km
	_kept_seed = GameState.get_next_run_seed()
	refresh()


func _on_go() -> void:
	var refit := _refit.button_pressed and GameState.get_refit_cost() > 0
	GameState.start_run(_drop, _get_pressed(_plan_buttons), refit)
