class_name ShipTab
extends ShipMenuTab

# The ship's condition: schematic, hull, every part that can be damaged, fuel and ammo.

const PART_NAME_WIDTH: float = 190.0
const PART_EFFECT_WIDTH: float = 100.0


func get_title() -> String:
	return "Ship"


func refresh() -> void:
	clear()

	var left := add_column(240.0)
	var schematic_card := add_card(left)
	schematic_card.size_flags_vertical = Control.SIZE_EXPAND_FILL
	schematic_card.body.add_child(VectorStyle.make_heading_row("Condition"))
	var schematic := ShipSchematic.new()
	schematic.setup(menu.ship, menu.ship_damage)
	schematic_card.body.add_child(schematic)

	var legend := HBoxContainer.new()
	legend.add_theme_constant_override("separation", 12)
	legend.alignment = BoxContainer.ALIGNMENT_CENTER
	legend.add_child(VectorStyle.make_lamp(VectorStyle.ACCENT, "OK"))
	legend.add_child(VectorStyle.make_lamp(VectorStyle.WARN, "Worn"))
	legend.add_child(VectorStyle.make_lamp(VectorStyle.BAD, "< 20 %"))
	schematic_card.body.add_child(legend)

	var middle := add_column()
	_add_hull(middle)
	_add_parts(middle)

	var right := add_column(290.0)
	_add_supplies(right)


func _add_hull(column: VBoxContainer) -> void:
	if menu.ship_damage == null:
		return

	var ratio := menu.ship_damage.get_hull_ratio()
	var color := VectorStyle.get_health_color(ratio)
	var card := add_card(column)
	var value := VectorStyle.make_label("%d %%" % roundi(ratio * 100.0), &"VectorTitle", color)
	card.body.add_child(VectorStyle.make_heading_row("Hull", "Repair it at the mechanic. Under 70 %, the undock screen reminds you.", value))
	card.body.add_child(VectorStyle.make_bar(ratio, color, 14.0))


func _add_parts(column: VBoxContainer) -> void:
	if menu.ship_damage == null:
		return

	var card := add_card(column)
	card.size_flags_vertical = Control.SIZE_EXPAND_FILL
	card.body.add_child(VectorStyle.make_heading_row("Parts", "A part under 20 % stops working. Above that, it works as well as its health."))

	var parts: Array[Node] = []

	for part in menu.ship_damage.get_parts():
		if not ShipDamage.get_health(part).is_invulnerable:
			parts.append(part)

	parts.sort_custom(func(a: Node, b: Node) -> bool: return ShipDamage.get_health(a).get_ratio() < ShipDamage.get_health(b).get_ratio())

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	card.body.add_child(scroll)

	var grid := GridContainer.new()
	grid.columns = 4
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grid.add_theme_constant_override("h_separation", 12)
	grid.add_theme_constant_override("v_separation", 6)
	scroll.add_child(grid)

	for part in parts:
		var health := ShipDamage.get_health(part)
		var ratio := health.get_ratio()
		var color := VectorStyle.get_health_color(ratio)

		var name_label := VectorStyle.make_label(ShipDamage.get_part_name(part))
		name_label.custom_minimum_size.x = PART_NAME_WIDTH
		name_label.clip_text = true
		grid.add_child(name_label)
		grid.add_child(VectorStyle.make_bar(ratio, color, 8.0))
		grid.add_child(VectorStyle.make_label("%3d %%" % roundi(ratio * 100.0), &"VectorValue", color))

		var effect := ""

		if health.is_broken():
			effect = "not working"
		elif ratio < 1.0:
			effect = "works at %d %%" % roundi(health.get_performance() * 100.0)

		var effect_label := VectorStyle.make_label(effect, &"VectorSmall", color if health.is_broken() else VectorStyle.DIM)
		effect_label.custom_minimum_size.x = PART_EFFECT_WIDTH
		grid.add_child(effect_label)


# --- Fuel and ammo


func _add_supplies(column: VBoxContainer) -> void:
	var card := add_card(column)
	card.body.add_child(VectorStyle.make_heading_row("Supplies", "Topped up at the undock screen, before each drop."))

	if menu.rooms != null and menu.rooms.get_fuel_capacity() > 0.0:
		var fuel := menu.rooms.get_fuel() / menu.rooms.get_fuel_capacity()
		card.body.add_child(make_line("Fuel", "%d %%" % roundi(fuel * 100.0)))
		card.body.add_child(VectorStyle.make_bar(fuel, VectorStyle.ACCENT, 8.0))

	if menu.hardpoints != null and menu.hardpoints.get_ammo_capacity() > 0:
		var ammo := menu.hardpoints.get_ammo()
		var capacity := menu.hardpoints.get_ammo_capacity()
		card.body.add_child(make_line("Ammo", "%d / %d" % [ammo, capacity]))
		card.body.add_child(VectorStyle.make_bar(float(ammo) / capacity, VectorStyle.DIM, 8.0))
