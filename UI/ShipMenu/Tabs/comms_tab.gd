class_name CommsTab
extends ShipMenuTab

# The mothership: call her (same as the call key), where she is and how long she waits. The run's
# insurance. And the whole radio log of the run: the cockpit terminal only keeps the last lines.

func get_title() -> String:
	return "Comms"


func refresh() -> void:
	clear()

	var left := add_column()
	_add_mothership(left)
	_add_insurance(left)

	var right := add_column(440.0)
	_add_log(right)


func _add_mothership(column: VBoxContainer) -> void:
	var dispatch := menu.dispatch
	var card := add_card(column)

	if dispatch == null:
		card.body.add_child(VectorStyle.make_heading_row("Mothership"))
		card.body.add_child(VectorStyle.make_label("No radio contact in this scene.", &"VectorSmall"))
		return

	var pickup := dispatch.get_pickup()
	var status := _get_status(dispatch, pickup)
	var tip := "She turns up already moving, away from you or across your path, and waits %d minutes. Miss her and you pay again." % roundi(dispatch.wait_time / 60.0)
	card.body.add_child(VectorStyle.make_heading_row("Mothership", tip, VectorStyle.make_lamp(status.color, status.text)))

	var call_button := Button.new()
	call_button.theme_type_variation = &"VectorBig"
	call_button.text = "CALL THE MOTHERSHIP" if pickup == null else "MOTHERSHIP CALLED"
	call_button.disabled = not dispatch.can_call()
	call_button.focus_mode = Control.FOCUS_NONE
	call_button.pressed.connect(_on_call_pressed)
	card.body.add_child(call_button)
	card.body.add_child(make_line("Pickup fee", VectorStyle.format_credits(dispatch.call_fee), VectorStyle.ACCENT))

	var stats := HBoxContainer.new()
	stats.add_theme_constant_override("separation", 10)
	var distance := "-"
	var time_left := "-"

	if pickup != null:
		distance = "%d km" % roundi(menu.ship.global_position.distance_to(pickup.get_marker_position()) / 1000.0)
		var seconds := ceili(pickup.time_left)
		time_left = "%02d:%02d" % [floori(seconds / 60.0), seconds % 60]

	stats.add_child(_make_stat("Distance", distance))
	stats.add_child(_make_stat("Waits", time_left))
	stats.add_child(_make_stat("Status", status.text))
	card.body.add_child(stats)


func _get_status(dispatch: MothershipDispatch, pickup: Mothership) -> Dictionary:
	if dispatch.is_home:
		return { "text": "Docked", "color": VectorStyle.ACCENT }

	if pickup == null:
		return { "text": "Not called", "color": VectorStyle.DIM }

	match pickup.state:
		Mothership.State.LEAVING:
			return { "text": "Leaving", "color": VectorStyle.BAD }
		Mothership.State.DOCKING:
			return { "text": "Docking", "color": VectorStyle.ACCENT }

	return { "text": "Waiting", "color": VectorStyle.WARN }


func _make_stat(title: String, value: String) -> VectorCard:
	var card := VectorCard.new()
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	card.body.add_child(VectorStyle.make_label(title, &"VectorSmall"))
	card.body.add_child(VectorStyle.make_label(value, &"VectorValue"))
	return card


func _on_call_pressed() -> void:
	menu.dispatch.call_pickup()
	refresh()


func _add_insurance(column: VBoxContainer) -> void:
	var card := add_card(column)

	if not GameState.is_run_active:
		card.body.add_child(VectorStyle.make_heading_row("Insurance", "", VectorStyle.make_label("None (test run)", &"VectorValue")))
		return

	var plan := GameState.ECONOMY.insurance_plans[GameState.run_insurance_index]
	card.body.add_child(VectorStyle.make_heading_row("Insurance", plan.description, VectorStyle.make_label(plan.display_name, &"VectorValue", VectorStyle.ACCENT)))


func _add_log(column: VBoxContainer) -> void:
	var card := add_card(column)
	card.size_flags_vertical = Control.SIZE_EXPAND_FILL
	card.body.add_child(VectorStyle.make_heading_row("Radio log", "Everything the cockpit terminal showed this run."))

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	card.body.add_child(scroll)

	var lines: Array[String] = []

	if menu.cockpit != null:
		lines = menu.cockpit.get_history()

	var log_label := VectorStyle.make_label("\n".join(PackedStringArray(lines)) if not lines.is_empty() else "Nothing yet.", &"VectorSmall", VectorStyle.ACCENT)
	log_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	log_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(log_label)

	# Newest at the bottom: scroll down once the label has its height.
	var bar := scroll.get_v_scroll_bar()
	bar.changed.connect(func() -> void: scroll.scroll_vertical = int(bar.max_value), CONNECT_ONE_SHOT)
