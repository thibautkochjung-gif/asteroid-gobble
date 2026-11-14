class_name ModulesTab
extends ShipMenuTab

# Modules with settings: a list on the left, the picked module's settings on the right.
# Today: the grinder's triage (saved as the loadout's `discarded`, GameState.set_discarded_materials)
# and each grabber's filter (Grabber.skipped_materials, saved in the loadout's module_settings).
# A new configurable module: an entry in _list_modules() and a _build_..._settings() function.

const LIST_WIDTH: float = 240.0

var _entries: Array[Dictionary] = [] # { "kind", "name", "build" (Callable taking the settings column) }
var _selected: int = 0


func get_title() -> String:
	return "Modules"


func refresh() -> void:
	clear()
	_list_modules()

	var list := add_column(LIST_WIDTH)
	list.add_theme_constant_override("separation", 4)
	var group := ButtonGroup.new()
	var last_kind := ""
	_selected = clampi(_selected, 0, maxi(_entries.size() - 1, 0))

	for i in _entries.size():
		var entry := _entries[i]

		if entry.kind != last_kind:
			last_kind = entry.kind
			var kind_label := VectorStyle.make_label(entry.kind, &"VectorSmall")
			kind_label.uppercase = true
			list.add_child(kind_label)

		var item := Button.new()
		item.theme_type_variation = &"VectorListItem"
		item.toggle_mode = true
		item.button_group = group
		item.button_pressed = i == _selected
		item.text = entry.name
		item.alignment = HORIZONTAL_ALIGNMENT_LEFT
		item.focus_mode = Control.FOCUS_NONE
		item.pressed.connect(_select.bind(i))
		list.add_child(item)

	var settings := add_column()

	if _entries.is_empty():
		settings.add_child(VectorStyle.make_label("Nothing to set up on this ship.", &"VectorSmall"))
		return

	_entries[_selected].build.call(settings)


func _select(index: int) -> void:
	_selected = index
	refresh()


func _list_modules() -> void:
	_entries.clear()

	if menu.grinder != null:
		_entries.append({ "kind": "Rooms", "name": "Grinder", "build": _build_grinder_settings })

	if menu.hardpoints == null:
		return

	for i in menu.hardpoints.get_slot_count():
		var weapon := menu.hardpoints.get_weapon(i)

		if weapon is Grabber:
			_entries.append({ "kind": "Hardpoints", "name": "Grabber · " + _get_side(i), "build": _build_grabber_settings.bind(weapon, i) })


func _get_side(slot_index: int) -> String:
	return "LMB" if slot_index % 2 == 0 else "RMB"


# --- Grinder


func _build_grinder_settings(column: VBoxContainer) -> void:
	var grinder := menu.grinder
	var state := VectorStyle.make_lamp(VectorStyle.ACCENT if grinder.is_working else VectorStyle.DIM, grinder.get_status_text())
	column.add_child(_make_header("Grinder", "Hold · sorts the cells for the ore bins", state))
	column.add_child(VectorStyle.make_heading_row("What to keep", "Ticked cells go to the ore bins. The rest is ground to dust and blown out the back."))
	column.add_child(_make_chips(func(id: int) -> bool: return not grinder.is_discarded(id), _on_grinder_toggled))
	column.add_child(_make_presets([["Ore only", _set_grinder_kept.bind(CellMaterials.ORES)], ["Everything", _set_grinder_kept.bind(range(CellMaterials.ALL.size()))]]))


func _on_grinder_toggled(is_kept: bool, id: int) -> void:
	var grinder := menu.grinder

	if is_kept:
		grinder.discarded_materials.erase(id)
	elif not grinder.is_discarded(id):
		grinder.discarded_materials.append(id)

	GameState.set_discarded_materials(grinder.discarded_materials)


func _set_grinder_kept(kept: Array) -> void:
	var grinder := menu.grinder
	grinder.discarded_materials.clear()

	for id in CellMaterials.ALL.size():
		if not kept.has(id):
			grinder.discarded_materials.append(id)

	GameState.set_discarded_materials(grinder.discarded_materials)
	refresh()


# --- Grabber


func _build_grabber_settings(column: VBoxContainer, grabber: Grabber, slot_index: int) -> void:
	var where := "Hardpoint %d · %s" % [slot_index + 1, _get_side(slot_index)]

	if menu.hardpoints.get_pair_count() > 1:
		where = "Hardpoint %d · pair %d · %s" % [slot_index + 1, menu.hardpoints.get_pair(slot_index) + 1, _get_side(slot_index)]

	var state := VectorStyle.make_lamp(VectorStyle.ACCENT if grabber.is_running else VectorStyle.DIM, "Running" if grabber.is_running else "Off")
	column.add_child(_make_header("Grabber", where, state))
	column.add_child(VectorStyle.make_heading_row("What to pick up", "The claw only goes for chunks with at least one ticked material in them."))
	column.add_child(_make_chips(func(id: int) -> bool: return not grabber.is_skipped(id), _on_grabber_toggled.bind(grabber)))

	var copy_grinder := Callable()

	if menu.grinder != null:
		copy_grinder = _set_grabber_wanted.bind(grabber, range(CellMaterials.ALL.size()).filter(func(id: int) -> bool: return not menu.grinder.is_discarded(id)))

	var presets := [["Ore only", _set_grabber_wanted.bind(grabber, CellMaterials.ORES)], ["Everything", _set_grabber_wanted.bind(grabber, range(CellMaterials.ALL.size()))]]

	if copy_grinder.is_valid():
		presets.append(["Same as grinder", copy_grinder])

	column.add_child(_make_presets(presets))


# toggled gives the new state; the bound values come after it.
func _on_grabber_toggled(is_wanted: bool, id: int, grabber: Grabber) -> void:
	grabber.set_skipped(id, not is_wanted)
	GameState.set_module_settings(grabber.settings_key, grabber.get_settings())


func _set_grabber_wanted(grabber: Grabber, wanted: Array) -> void:
	for id in CellMaterials.ALL.size():
		grabber.set_skipped(id, not wanted.has(id))

	GameState.set_module_settings(grabber.settings_key, grabber.get_settings())
	refresh()


# --- Building blocks


func _make_header(title: String, subtitle: String, right: Control) -> HBoxContainer:
	var names := VBoxContainer.new()
	names.add_theme_constant_override("separation", 0)
	var title_label := VectorStyle.make_label(title, &"VectorTitle")
	title_label.uppercase = true
	names.add_child(title_label)
	names.add_child(VectorStyle.make_label(subtitle, &"VectorSmall"))
	var row := VectorStyle.make_row(names, right)
	row.add_theme_constant_override("separation", 10)
	return row


# One toggle per material, three columns. is_ticked(id) gives each one's state;
# on_toggled(is_ticked, id) is called when the player clicks one.
func _make_chips(is_ticked: Callable, on_toggled: Callable) -> GridContainer:
	var grid := GridContainer.new()
	grid.columns = 3
	grid.add_theme_constant_override("h_separation", 8)
	grid.add_theme_constant_override("v_separation", 8)

	for id in CellMaterials.ALL.size():
		var cell_material := CellMaterials.get_material(id)
		var chip := Button.new()
		chip.theme_type_variation = &"VectorChip"
		chip.toggle_mode = true
		chip.icon = VectorStyle.get_swatch(cell_material.color)
		chip.alignment = HORIZONTAL_ALIGNMENT_LEFT
		chip.focus_mode = Control.FOCUS_NONE
		chip.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		chip.set_pressed_no_signal(is_ticked.call(id))
		_label_chip(chip, cell_material.display_name)
		chip.toggled.connect(_on_chip_toggled.bind(chip, cell_material.display_name, on_toggled, id))
		grid.add_child(chip)

	return grid


# toggled gives the new state; the bound values come after it.
func _on_chip_toggled(is_on: bool, chip: Button, material_name: String, on_toggled: Callable, id: int) -> void:
	_label_chip(chip, material_name)
	on_toggled.call(is_on, id)


func _label_chip(chip: Button, material_name: String) -> void:
	chip.text = "%s %s" % ["[x]" if chip.button_pressed else "[ ]", material_name]


# presets: [label, Callable] pairs.
func _make_presets(presets: Array) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	row.add_child(VectorStyle.make_label("Presets", &"VectorSmall"))

	for preset in presets:
		var button := Button.new()
		button.text = preset[0]
		button.focus_mode = Control.FOCUS_NONE
		button.pressed.connect(preset[1])
		row.add_child(button)

	return row
