extends CanvasLayer

# The pause action (Escape) toggles the pause. While paused, the player can swap the ship's rooms,
# hardpoint weapons and soft points. The refuel button also restocks the soft points.
# Prototype only: room swapping will move to the hangar (station) later.
# process_mode is ALWAYS (set in the scene) so this node still gets input while the tree is paused.

const EMPTY_SOFT_POINT: int = 999 # Picker id for "no module". OptionButton ids can't be negative

@export var rooms: ShipRooms
@export var hardpoints: ShipHardpoints
@export var soft_points: ShipSoftPoints

var _pickers: Array[OptionButton] = []
var _contents_labels: Array[Label] = []
var _weapon_pickers: Array[OptionButton] = []
var _soft_point_pickers: Array[OptionButton] = []

@onready var slot_list: VBoxContainer = %SlotList
@onready var hardpoint_list: VBoxContainer = %HardpointList
@onready var soft_point_list: VBoxContainer = %SoftPointList
@onready var status_label: Label = %StatusLabel
@onready var refuel_button: Button = %RefuelButton
@onready var empty_cargo_button: Button = %EmptyCargoButton
@onready var resume_button: Button = %ResumeButton


func _ready() -> void:
	visible = false
	_build_slot_rows()
	_build_hardpoint_rows()
	_build_soft_point_rows()

	resume_button.pressed.connect(_set_paused.bind(false))
	refuel_button.pressed.connect(rooms.refuel)
	refuel_button.pressed.connect(soft_points.restock)
	refuel_button.pressed.connect(hardpoints.restock_ammo) # After soft_points.restock: see restock_ammo()
	soft_points.layout_changed.connect(_refresh_soft_point_rows)
	empty_cargo_button.pressed.connect(rooms.empty_cargo)
	rooms.layout_changed.connect(_refresh_slot_rows)
	hardpoints.layout_changed.connect(_refresh_hardpoint_rows)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("pause"):
		_set_paused(not get_tree().paused)
		get_viewport().set_input_as_handled()


func _process(_delta: float) -> void:
	if visible:
		_refresh_contents()


func _set_paused(paused: bool) -> void:
	get_tree().paused = paused
	visible = paused

	if paused:
		_refresh_slot_rows()
		_refresh_hardpoint_rows()
		_refresh_soft_point_rows()
	else:
		get_viewport().gui_release_focus() # Otherwise Space would "click" the last focused button


func _build_slot_rows() -> void:
	for i in rooms.get_slot_count():
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 12)

		var slot_size := rooms.get_slot_size(i) / Room.TEXEL # Shown in texels, like the art

		var name_label := Label.new()
		name_label.text = "Slot %d (%dx%d)" % [i + 1, slot_size.x, slot_size.y]
		name_label.custom_minimum_size.x = 120

		var picker := OptionButton.new()
		picker.custom_minimum_size.x = 140

		for type in Room.TYPE_NAMES:
			picker.add_item(Room.TYPE_NAMES[type], type)

		picker.item_selected.connect(_on_room_picked.bind(i))

		var contents_label := Label.new()
		contents_label.modulate = Color(1.0, 1.0, 1.0, 0.7)

		row.add_child(name_label)
		row.add_child(picker)
		row.add_child(contents_label)
		slot_list.add_child(row)
		_pickers.append(picker)
		_contents_labels.append(contents_label)


func _refresh_slot_rows() -> void:
	for i in _pickers.size():
		var room := rooms.get_room(i)

		if room != null:
			_pickers[i].select(_pickers[i].get_item_index(room.room_type)) # select() doesn't emit item_selected

	_refresh_contents()


func _refresh_contents() -> void:
	for i in _contents_labels.size():
		var room := rooms.get_room(i)
		_contents_labels[i].text = room.get_status_text() if room != null else "Empty"

	status_label.text = "Fuel %d / %d    Ingots %d / %d u    Ore bins %d / %d cells    Smelters %d / %d cells    Ammo %d / %d" % [
		rooms.get_fuel(),
		rooms.get_fuel_capacity(),
		rooms.get_ingot_units(),
		rooms.get_ingot_capacity(),
		rooms.get_ore_bin_cells(),
		rooms.get_ore_bin_capacity(),
		rooms.get_smelter_cells(),
		rooms.get_smelter_capacity(),
		hardpoints.get_ammo(),
		hardpoints.get_ammo_capacity(),
	]


# item_selected gives the item index; the bound slot_index is appended after it.
func _on_room_picked(index: int, slot_index: int) -> void:
	var type := _pickers[slot_index].get_item_id(index) as Room.Type
	rooms.install_room(slot_index, type)


func _build_hardpoint_rows() -> void:
	for i in hardpoints.get_slot_count():
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 12)

		var name_label := Label.new()
		name_label.text = "Slot %d (pair %d, %s)" % [i + 1, hardpoints.get_pair(i) + 1, _get_binding_text(hardpoints.get_trigger_action(i))]
		name_label.custom_minimum_size.x = 200

		var picker := OptionButton.new()
		picker.custom_minimum_size.x = 180

		for type in HardpointWeapon.TYPE_NAMES:
			picker.add_item(HardpointWeapon.TYPE_NAMES[type], type)

		picker.item_selected.connect(_on_weapon_picked.bind(i))

		row.add_child(name_label)
		row.add_child(picker)
		hardpoint_list.add_child(row)
		_weapon_pickers.append(picker)


func _refresh_hardpoint_rows() -> void:
	for i in _weapon_pickers.size():
		var weapon := hardpoints.get_weapon(i)

		if weapon != null:
			_weapon_pickers[i].select(_weapon_pickers[i].get_item_index(weapon.weapon_type))


# item_selected gives the item index; the bound slot_index is appended after it.
func _on_weapon_picked(index: int, slot_index: int) -> void:
	var type := _weapon_pickers[slot_index].get_item_id(index) as HardpointWeapon.Type
	hardpoints.install_weapon(slot_index, type)


func _build_soft_point_rows() -> void:
	for i in soft_points.get_mount_count():
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 12)

		var name_label := Label.new()
		name_label.text = "%s (%s)" % [soft_points.get_mount_name(i), _get_binding_text(soft_points.get_action(i))]
		name_label.custom_minimum_size.x = 200

		var picker := OptionButton.new()
		picker.custom_minimum_size.x = 180
		picker.add_item("Empty", EMPTY_SOFT_POINT)

		for type in SoftPoint.TYPE_NAMES:
			picker.add_item(SoftPoint.TYPE_NAMES[type], type)

		picker.item_selected.connect(_on_soft_point_picked.bind(i))

		row.add_child(name_label)
		row.add_child(picker)
		soft_point_list.add_child(row)
		_soft_point_pickers.append(picker)


func _refresh_soft_point_rows() -> void:
	for i in _soft_point_pickers.size():
		var module := soft_points.get_module(i)
		var id := module.soft_point_type as int if module != null else EMPTY_SOFT_POINT
		_soft_point_pickers[i].select(_soft_point_pickers[i].get_item_index(id))


# item_selected gives the item index; the bound mount_index is appended after it.
func _on_soft_point_picked(index: int, mount_index: int) -> void:
	var id := _soft_point_pickers[mount_index].get_item_id(index)

	if id == EMPTY_SOFT_POINT:
		soft_points.clear_mount(mount_index)
	else:
		soft_points.install(mount_index, id as SoftPoint.Type)


# "Left Mouse Button" etc., read from the Input Map so the label follows any rebinding.
func _get_binding_text(action: StringName) -> String:
	var events := InputMap.action_get_events(action)

	if events.is_empty():
		return "unbound"

	return events[0].as_text()
