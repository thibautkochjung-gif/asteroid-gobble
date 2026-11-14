class_name ShipMenu
extends CanvasLayer

# The in-game ship menu, in the "Vector" style (VectorStyle). The ship_menu action (J) opens and
# closes it, Escape closes it, 1-5 pick a tab (physical keys: the same on AZERTY). The game is
# paused while it's open.
# Tabs (UI/ShipMenu/Tabs): Contracts, Modules, Hold, Ship, Comms. Each is a ShipMenuTab that
# rebuilds itself in refresh(): when the menu opens, when its tab is picked, and after the player
# does something in it. Everything is built in code; the scene is just this node.
# process_mode is ALWAYS (set in the scene) so this node still gets input while the tree is paused.
# It sits after PauseMenu in main.tscn, so it sees Escape first and can close itself.

const TAB_KEYS: Array[Key] = [KEY_1, KEY_2, KEY_3, KEY_4, KEY_5]
const FRAME_SIZE := Vector2(1080.0, 600.0)
const DIM_COLOR := Color(0.0, 0.0, 0.0, 0.65)

@export var ship: RigidBody2D
@export var grinder: Grinder
@export var rooms: ShipRooms
@export var hardpoints: ShipHardpoints
@export var ship_damage: ShipDamage
@export var dispatch: MothershipDispatch
@export var cockpit: Cockpit

var current_tab: int = 0

var _tabs: Array[ShipMenuTab] = []
var _tab_buttons: Array[Button] = []
var _ship_label: Label


func _ready() -> void:
	visible = false
	_build()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ship_menu"):
		if visible:
			_close()
		elif not get_tree().paused: # Not over the pause menu
			_open()

		get_viewport().set_input_as_handled()
		return

	if not visible:
		return

	if event.is_action_pressed("pause"):
		_close()
		get_viewport().set_input_as_handled()
		return

	var key := event as InputEventKey

	if key != null and key.pressed and not key.echo:
		var index := TAB_KEYS.find(key.physical_keycode)

		if index >= 0 and index < _tabs.size():
			show_tab(index)
			get_viewport().set_input_as_handled()


func show_tab(index: int) -> void:
	current_tab = index

	for i in _tabs.size():
		_tabs[i].visible = i == index
		_tab_buttons[i].set_pressed_no_signal(i == index)

	_tabs[index].refresh()


func _open() -> void:
	get_tree().paused = true
	visible = true
	_ship_label.text = GameState.get_hull().display_name.to_upper() if GameState.is_run_active else "TEST RUN"
	_tab_buttons[0].text = _get_tab_text(0) # Contracts: shows how many are active
	show_tab(current_tab)


func _close() -> void:
	get_tree().paused = false
	visible = false
	get_viewport().gui_release_focus() # Otherwise Space would "click" the last focused button


# --- Layout


func _build() -> void:
	var root := Control.new()
	root.theme = VectorStyle.get_theme()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(root)

	var dim := ColorRect.new()
	dim.color = DIM_COLOR
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.add_child(dim)

	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.add_child(center)

	var frame := PanelContainer.new()
	frame.theme_type_variation = &"VectorFrame"
	frame.custom_minimum_size = FRAME_SIZE
	center.add_child(frame)

	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 12)
	frame.add_child(column)

	_tabs = [ContractsTab.new(), ModulesTab.new(), HoldTab.new(), ShipTab.new(), CommsTab.new()]
	column.add_child(_make_header())
	column.add_child(_make_tab_bar())

	for tab in _tabs:
		tab.menu = self
		tab.visible = false
		column.add_child(tab)

	column.add_child(_make_footer())


func _make_header() -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 14)
	row.add_child(VectorStyle.make_label("SHIPNET//", &"VectorTitle"))
	_ship_label = VectorStyle.make_label("", &"VectorSmall")
	row.add_child(_ship_label)
	row.add_child(VectorStyle.make_spacer())
	row.add_child(VectorStyle.make_lamp(VectorStyle.WARN, "Paused"))
	row.add_child(VectorStyle.make_key(Cockpit.get_key_text(&"ship_menu")))
	row.add_child(VectorStyle.make_label("CLOSE", &"VectorSmall"))
	return row


func _make_tab_bar() -> VBoxContainer:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 0)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 4)
	box.add_child(row)
	box.add_child(HSeparator.new())

	var group := ButtonGroup.new()

	for i in _tabs.size():
		var button := Button.new()
		button.theme_type_variation = &"VectorTab"
		button.toggle_mode = true
		button.button_group = group
		button.focus_mode = Control.FOCUS_NONE
		button.text = _get_tab_text(i)
		button.pressed.connect(show_tab.bind(i))
		row.add_child(button)
		_tab_buttons.append(button)

	return box


func _get_tab_text(index: int) -> String:
	var text := "%d  %s" % [index + 1, _tabs[index].get_title().to_upper()]

	if _tabs[index] is ContractsTab and not GameState.guild.active.is_empty():
		text += " (%d)" % GameState.guild.active.size()

	return text


func _make_footer() -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	row.add_child(VectorStyle.make_key("1"))
	row.add_child(VectorStyle.make_label("-", &"VectorSmall"))
	row.add_child(VectorStyle.make_key("5"))
	row.add_child(VectorStyle.make_label("TABS", &"VectorSmall"))
	var gap := Control.new()
	gap.custom_minimum_size.x = 12.0
	row.add_child(gap)
	row.add_child(VectorStyle.make_key("Esc"))
	row.add_child(VectorStyle.make_label("CLOSE", &"VectorSmall"))
	row.add_child(VectorStyle.make_spacer())
	row.add_child(VectorStyle.make_label("PRICES FROZEN UNTIL DOCKING", &"VectorSmall"))
	return row
