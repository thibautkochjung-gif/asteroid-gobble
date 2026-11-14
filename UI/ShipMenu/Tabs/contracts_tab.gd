class_name ContractsTab
extends ShipMenuTab

# Guild contracts taken at the hub: goal, progress, reward, and what would pay out on docking now.
# Deliveries count the ore aboard on top of what was already handed in.

const TAG_WIDTH: float = 130.0
const PROGRESS_WIDTH: float = 190.0


func get_title() -> String:
	return "Contracts"


# Where the contract would stand if the player docked now.
static func get_progress(contract: Contract, aboard: Dictionary[int, float]) -> float:
	if contract.is_delivery():
		return minf(contract.progress + aboard.get(contract.ore_id, 0.0), contract.target)

	return contract.progress


static func is_ready(contract: Contract, aboard: Dictionary[int, float]) -> bool:
	return get_progress(contract, aboard) >= contract.target - GameState.DUST


func refresh() -> void:
	clear()

	var contracts := GameState.guild.active
	var aboard: Dictionary[int, float] = {}

	if menu.rooms != null:
		aboard = menu.rooms.get_ore_aboard()

	var left := add_column()
	var count := VectorStyle.make_label("%d / %d" % [contracts.size(), Guild.MAX_ACTIVE], &"VectorSmall")
	left.add_child(VectorStyle.make_heading_row("Active contracts", "Take new ones at the guild board on Union Ring Four.", count))

	if contracts.is_empty():
		left.add_child(VectorStyle.make_label("No contracts. The guild board has some.", &"VectorSmall"))

	var ready_total := 0
	var open_total := 0

	for contract in contracts:
		var contract_ready := is_ready(contract, aboard)
		left.add_child(_make_contract(contract, get_progress(contract, aboard), contract_ready))
		left.add_child(HSeparator.new())

		if contract_ready:
			ready_total += contract.reward
		else:
			open_total += contract.reward

	var right := add_column(270.0)
	var card := add_card(right)
	card.body.add_child(VectorStyle.make_heading_row("This run", "Contracts pay in credits when you dock at the hub."))
	card.body.add_child(make_line("Ready if you dock now", VectorStyle.format_credits(ready_total), VectorStyle.ACCENT))
	card.body.add_child(make_line("Still to do", VectorStyle.format_credits(open_total)))


func _make_contract(contract: Contract, progress: float, contract_ready: bool) -> VBoxContainer:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 6)

	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 10)
	var tag := VectorStyle.make_label(contract.get_title(), &"VectorTag")
	tag.uppercase = true
	tag.custom_minimum_size.x = TAG_WIDTH
	tag.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	tag.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	top.add_child(tag)

	var goal := VectorStyle.make_label(contract.get_goal_text())
	goal.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	goal.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(goal)

	var needs := contract.get_needs_text()

	if not needs.is_empty():
		top.add_child(VectorInfo.new(needs + "."))

	var is_last_run := contract.runs_left == 1

	if is_last_run:
		top.add_child(VectorStyle.make_label("LAST RUN", &"VectorValue", VectorStyle.WARN))

	top.add_child(VectorStyle.make_label(VectorStyle.format_credits(contract.reward), &"VectorValue"))
	box.add_child(top)

	var bottom := HBoxContainer.new()
	bottom.add_theme_constant_override("separation", 10)
	var pad := Control.new()
	pad.custom_minimum_size.x = TAG_WIDTH
	bottom.add_child(pad)

	var color := VectorStyle.WARN if is_last_run and not contract_ready else VectorStyle.ACCENT
	var ratio := progress / contract.target if contract.target > 0.0 else 0.0
	bottom.add_child(VectorStyle.make_bar(ratio, color))

	var text := _get_progress_text(contract, progress)

	if contract_ready:
		text = "READY  " + text

	var progress_label := VectorStyle.make_label(text, &"VectorSmall", VectorStyle.ACCENT if contract_ready else VectorStyle.DIM)
	progress_label.custom_minimum_size.x = PROGRESS_WIDTH
	progress_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	bottom.add_child(progress_label)
	box.add_child(bottom)
	return box


# Contract.get_progress_text(), but deliveries count the ore aboard too.
func _get_progress_text(contract: Contract, progress: float) -> String:
	if contract.is_delivery():
		var ore_name := CellMaterials.get_material(contract.ore_id).display_name
		return "%d / %d u %s" % [floori(progress), roundi(contract.target), ore_name]

	return contract.get_progress_text()
