class_name HoldTab
extends ShipMenuTab

# The ore bins by material, with their value at today's (frozen) prices and a dump button that
# needs two clicks; the grinder at work; the ingot hold; and the run ledger: what the run has cost
# and what it would bring in if the player docked now.

const NAME_WIDTH: float = 120.0
const NUMBER_WIDTH: float = 80.0

var _armed_dump: int = -1 # Material whose DUMP was clicked once: the second click dumps it


func get_title() -> String:
	return "Hold"


func refresh() -> void:
	clear()

	var left := add_column()
	_add_bins(left)

	var right := add_column(320.0)
	_add_ledger(right)
	_add_ingots(right)


# --- Ore bins


func _add_bins(column: VBoxContainer) -> void:
	var rooms := menu.rooms

	if rooms == null or not rooms.has_ore_bin():
		column.add_child(VectorStyle.make_heading_row("Ore bins"))
		column.add_child(VectorStyle.make_label("No ore bin aboard.", &"VectorSmall"))
		return

	var cells := rooms.get_ore_bin_cells()
	var capacity := rooms.get_ore_bin_capacity()
	var fill := VectorStyle.make_label("%d / %d cells" % [cells, capacity], &"VectorValue")
	column.add_child(VectorStyle.make_heading_row("Ore bins", "Values at today's hub prices. They don't move while you're out here.", fill))
	column.add_child(VectorStyle.make_bar(float(cells) / capacity if capacity > 0 else 0.0, VectorStyle.ACCENT, 14.0))

	var by_material := rooms.get_ore_bin_by_material()

	if by_material.is_empty():
		column.add_child(VectorStyle.make_label("Empty.", &"VectorSmall"))
	else:
		column.add_child(_make_bin_table(by_material, capacity))

	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.add_child(spacer)

	if menu.grinder != null:
		_add_grinder(column)


func _make_bin_table(by_material: Dictionary[int, int], capacity: int) -> GridContainer:
	var grid := GridContainer.new()
	grid.columns = 6
	grid.add_theme_constant_override("h_separation", 12)
	grid.add_theme_constant_override("v_separation", 8)

	for heading in ["", "MATERIAL", "", "CELLS", "VALUE", ""]:
		grid.add_child(VectorStyle.make_label(heading, &"VectorSmall"))

	var values := _get_value_by_material()
	var ids := by_material.keys()
	ids.sort_custom(func(a: int, b: int) -> bool: return by_material[a] > by_material[b])

	for id: int in ids:
		var cell_material := CellMaterials.get_material(id)
		grid.add_child(VectorStyle.make_swatch(cell_material.color))

		var name_label := VectorStyle.make_label(cell_material.display_name)
		name_label.custom_minimum_size.x = NAME_WIDTH
		grid.add_child(name_label)

		var max_cells := maxi(capacity, 1)
		grid.add_child(VectorStyle.make_bar(float(by_material[id]) / max_cells, cell_material.color, 8.0))

		var count := VectorStyle.make_label(str(by_material[id]), &"VectorValue")
		count.custom_minimum_size.x = NUMBER_WIDTH
		count.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		grid.add_child(count)

		var value := VectorStyle.make_label(VectorStyle.format_credits(values.get(id, 0)), &"VectorValue", VectorStyle.ACCENT)
		value.custom_minimum_size.x = NUMBER_WIDTH
		value.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		grid.add_child(value)

		var dump := Button.new()
		dump.theme_type_variation = &"VectorDanger"
		dump.text = "SURE?" if _armed_dump == id else "DUMP"
		dump.custom_minimum_size.x = 64.0
		dump.focus_mode = Control.FOCUS_NONE
		dump.pressed.connect(_on_dump_pressed.bind(id))
		grid.add_child(dump)

	return grid


# CellMaterials.Id -> credits. Rock is worth a trace of its asteroid's ore (OreBinRoom).
func _get_value_by_material() -> Dictionary[int, int]:
	var units: Dictionary[int, Dictionary] = {} # Material -> { ore id -> units }

	for room in menu.rooms.rooms:
		var bin := room as OreBinRoom

		if bin == null:
			continue

		for entry in bin.contents:
			var amount := 1.0 if CellMaterials.is_ore(entry.x) else bin.rock_trace_yield

			if not units.has(entry.x):
				units[entry.x] = {}

			units[entry.x][entry.y] = units[entry.x].get(entry.y, 0.0) + amount

	var values: Dictionary[int, int] = {}

	for material_id in units:
		var total := 0

		for ore_id in units[material_id]:
			total += int(GameState.get_sale_quote(ore_id, units[material_id][ore_id]).revenue)

		values[material_id] = total

	return values


func _on_dump_pressed(material_id: int) -> void:
	if _armed_dump != material_id:
		_armed_dump = material_id
		refresh()
		return

	_armed_dump = -1
	var count := menu.rooms.dump_material(material_id)

	if count > 0 and menu.grinder != null:
		menu.grinder.puff_dust(CellMaterials.get_material(material_id).color)

	refresh()


func _add_grinder(column: VBoxContainer) -> void:
	var grinder := menu.grinder
	var card := add_card(column)
	var lamp := VectorStyle.make_lamp(VectorStyle.ACCENT if grinder.is_working else VectorStyle.DIM, "Grinder")
	card.body.add_child(VectorStyle.make_row(lamp, VectorStyle.make_label(grinder.get_status_text(), &"VectorSmall")))
	card.body.add_child(VectorStyle.make_bar(grinder.progress if grinder.is_working else 0.0, VectorStyle.WARN, 8.0))


# --- Ledger


func _add_ledger(column: VBoxContainer) -> void:
	var card := add_card(column)
	card.body.add_child(VectorStyle.make_heading_row("Run ledger", "What this run has cost so far, and what it would bring in if you docked now."))

	if not GameState.is_run_active:
		card.body.add_child(VectorStyle.make_label("Test run: nothing is paid.", &"VectorSmall"))
		return

	var paid := GameState.run_fees
	var pickup := 0
	var pickup_text := "Pickup, when called"

	if menu.dispatch != null:
		pickup = menu.dispatch.fees_paid if menu.dispatch.fees_paid > 0 else menu.dispatch.call_fee

		if menu.dispatch.fees_paid > 0:
			pickup_text = "Pickup"

	var income := _get_income()
	var net: int = income.cargo + income.contracts - paid - pickup

	card.body.add_child(make_line("Paid at undock", VectorStyle.format_credits(-paid), VectorStyle.BAD))
	card.body.add_child(make_line(pickup_text, VectorStyle.format_credits(-pickup), VectorStyle.BAD))
	card.body.add_child(HSeparator.new())
	card.body.add_child(make_line("Cargo, if sold", "+" + VectorStyle.format_credits(income.cargo), VectorStyle.ACCENT))
	card.body.add_child(make_line("Contracts ready", "+" + VectorStyle.format_credits(income.contracts), VectorStyle.ACCENT))
	card.body.add_child(HSeparator.new())

	var total := VectorStyle.make_label(VectorStyle.format_credits(net), &"VectorTitle", VectorStyle.ACCENT if net >= 0 else VectorStyle.BAD)
	card.body.add_child(VectorStyle.make_row(VectorStyle.make_heading("If you dock now"), total))


# Cargo value at today's prices, minus the ore the ready deliveries will take; and their rewards.
func _get_income() -> Dictionary:
	var aboard := menu.rooms.get_ore_aboard()
	var left_over: Dictionary[int, float] = {}

	for ore_id in aboard:
		left_over[ore_id] = aboard[ore_id]

	var contracts := 0

	for contract in GameState.guild.active:
		if not ContractsTab.is_ready(contract, aboard):
			continue

		contracts += contract.reward

		if contract.is_delivery():
			var owed := contract.target - contract.progress
			left_over[contract.ore_id] = maxf(left_over.get(contract.ore_id, 0.0) - owed, 0.0)

	var cargo := 0

	for ore_id in left_over:
		if left_over[ore_id] > 0.0:
			cargo += int(GameState.get_sale_quote(ore_id, left_over[ore_id]).revenue)

	return { "cargo": cargo, "contracts": contracts }


# --- Ingots


func _add_ingots(column: VBoxContainer) -> void:
	var rooms := menu.rooms
	var card := add_card(column)

	if rooms == null or rooms.get_ingot_capacity() <= 0.0:
		card.body.add_child(VectorStyle.make_heading_row("Ingot hold", "Fit a smelter and an ingot hold at the mechanic to pack ore tighter."))
		card.body.add_child(VectorStyle.make_label("No ingot hold aboard.", &"VectorSmall"))
		return

	var fill := VectorStyle.make_label("%d / %d u" % [roundi(rooms.get_ingot_units()), roundi(rooms.get_ingot_capacity())], &"VectorValue")
	card.body.add_child(VectorStyle.make_heading_row("Ingot hold", "", fill))
	card.body.add_child(VectorStyle.make_bar(rooms.get_ingot_units() / rooms.get_ingot_capacity(), VectorStyle.ACCENT, 8.0))

	var ingots := rooms.get_ingots_by_ore()

	for ore_id in ingots:
		var ore_name := CellMaterials.get_material(ore_id).display_name
		var value := int(GameState.get_sale_quote(ore_id, ingots[ore_id]).revenue)
		card.body.add_child(make_line("%s  %d u" % [ore_name, roundi(ingots[ore_id])], VectorStyle.format_credits(value), VectorStyle.ACCENT))
