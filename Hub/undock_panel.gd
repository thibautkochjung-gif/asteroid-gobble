class_name UndockPanel
extends HubPanel

# Undock: pick a field and an insurance plan, refuel and rearm, see the total, board the mothership.
# Locked fields need a better mining licence (the mining guild sells them, later).
# A player who can't pay for anything gets a free, uninsured drop to the nearest field.

var _field_group := ButtonGroup.new()
var _plan_group := ButtonGroup.new()
var _field_buttons: Array[Button] = []
var _plan_buttons: Array[Button] = []
var _field_info: Label
var _refit: CheckBox
var _warning: Label
var _total: Label
var _go: Button


func _init() -> void:
	super("UNDOCK")


func _build() -> void:
	var economy := GameState.ECONOMY
	body.add_child(HubStyle.label("DESTINATION", 13, HubStyle.DIM))

	for i in economy.fields.size():
		var field := economy.fields[i]
		var text := "%s   %s" % [field.display_name, HubStyle.format_credits(field.drop_fee)]

		if not GameState.is_field_open(i):
			text += "   licence %s needed" % ["I", "II", "III", "IV"][clampi(field.licence_tier - 1, 0, 3)]

		var button := HubStyle.choice(text, _field_group)
		button.disabled = not GameState.is_field_open(i)
		button.toggled.connect(func(_on: bool) -> void: refresh())
		body.add_child(button)
		_field_buttons.append(button)

	_field_buttons[0].button_pressed = true
	_field_info = HubStyle.label("", 14, HubStyle.DIM)
	_field_info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body.add_child(_field_info)

	body.add_child(HubStyle.label("INSURANCE (cargo is never covered)", 13, HubStyle.DIM))

	for i in economy.insurance_plans.size():
		var plan := economy.insurance_plans[i]
		var button := HubStyle.choice("%s   %s   %s" % [plan.display_name, HubStyle.format_credits(GameState.get_premium(i)), plan.description], _plan_group)
		button.toggled.connect(func(_on: bool) -> void: refresh())
		body.add_child(button)
		_plan_buttons.append(button)

	_plan_buttons[0].button_pressed = true

	_refit = CheckBox.new()
	_refit.button_pressed = true
	_refit.add_theme_font_size_override(&"font_size", 15)
	_refit.toggled.connect(func(_on: bool) -> void: refresh())
	body.add_child(_refit)

	_warning = HubStyle.label("", 15, HubStyle.BAD)
	_warning.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body.add_child(_warning)

	_total = HubStyle.label("", 18)
	body.add_child(_total)

	_go = HubStyle.button("BOARD THE MOTHERSHIP", 20)
	_go.custom_minimum_size = Vector2(0, 48)
	_go.pressed.connect(_on_go)
	body.add_child(_go)

	GameState.credits_changed.connect(refresh)


func refresh() -> void:
	if _go == null: # Pressing the default choices in _build() calls this before the panel is complete
		return

	var field_index := _get_pressed(_field_buttons)
	var plan_index := _get_pressed(_plan_buttons)
	var field := GameState.ECONOMY.fields[field_index]
	_field_info.text = "%s Ores: %s. Pickup call: %s." % [field.description, field.ores_hint, HubStyle.format_credits(roundi(field.drop_fee * GameState.ECONOMY.pickup_fee_multiplier))]

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

	var cost := GameState.get_undock_cost(field_index, plan_index, _refit.button_pressed and refit_cost > 0)

	if GameState.can_afford(cost):
		_total.text = "Total %s   (wallet %s)" % [HubStyle.format_credits(cost), HubStyle.format_credits(GameState.credits)]
		_go.disabled = false
	elif GameState.can_get_free_drop():
		var is_free := field_index == 0 and plan_index == 0
		_total.text = "The Union gives broke miners a free, uninsured drop to %s." % GameState.ECONOMY.fields[0].display_name
		_go.disabled = not is_free
	else:
		_total.text = "Total %s. Not enough credits: sell some ore first." % HubStyle.format_credits(cost)
		_go.disabled = true


func _get_pressed(buttons: Array[Button]) -> int:
	for i in buttons.size():
		if buttons[i].button_pressed:
			return i

	return 0


func _on_go() -> void:
	var refit := _refit.button_pressed and GameState.get_refit_cost() > 0
	GameState.start_run(_get_pressed(_field_buttons), _get_pressed(_plan_buttons), refit)
