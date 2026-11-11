extends CanvasLayer

# The in-game ship menu: the ship_menu action (J) opens and closes it, and the game is paused
# while it's open. Escape closes it too.
# Tabs (one for now):
# - Ship configuration: the grinder's triage, one checkbox per material. Ticked = kept,
#   unticked = thrown out as dust. Saved with the ship's loadout (GameState), so it stays
#   from one run to the next.
# process_mode is ALWAYS (set in the scene) so this node still gets input while the tree is paused.
# It sits after PauseMenu in main.tscn, so it sees Escape first and can close itself.

@export var grinder: Grinder
@export var rooms: ShipRooms

var _keep_boxes: Dictionary[int, CheckBox] = {} # CellMaterials.Id -> its box

@onready var triage_list: GridContainer = %TriageList
@onready var bin_label: Label = %BinLabel
@onready var close_button: Button = %CloseButton


func _ready() -> void:
	visible = false
	_build_triage()
	close_button.pressed.connect(_close)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ship_menu"):
		if visible:
			_close()
		elif not get_tree().paused: # Not over the pause menu
			_open()

		get_viewport().set_input_as_handled()
	elif visible and event.is_action_pressed("pause"):
		_close()
		get_viewport().set_input_as_handled()


func _open() -> void:
	get_tree().paused = true
	visible = true
	_refresh()


func _close() -> void:
	get_tree().paused = false
	visible = false
	get_viewport().gui_release_focus() # Otherwise Space would "click" the last focused button


# --- Ship configuration


func _build_triage() -> void:
	for id in CellMaterials.ALL.size():
		var box := CheckBox.new()
		box.text = CellMaterials.get_material(id).display_name
		box.toggled.connect(_on_keep_toggled.bind(id))
		triage_list.add_child(box)
		_keep_boxes[id] = box


func _refresh() -> void:
	for id in _keep_boxes:
		_keep_boxes[id].set_pressed_no_signal(not grinder.is_discarded(id))

	if not rooms.has_ore_bin():
		bin_label.text = "No ore bin aboard."
		return

	var lines := PackedStringArray()
	lines.append("Ore bins: %d / %d cells" % [rooms.get_ore_bin_cells(), rooms.get_ore_bin_capacity()])
	var by_material := rooms.get_ore_bin_by_material()

	for id in by_material:
		lines.append("  %s: %d" % [CellMaterials.get_material(id).display_name, by_material[id]])

	bin_label.text = "\n".join(lines)


# toggled gives the new state; the bound material id is appended after it.
func _on_keep_toggled(is_kept: bool, id: int) -> void:
	if is_kept:
		grinder.discarded_materials.erase(id)
	elif not grinder.is_discarded(id):
		grinder.discarded_materials.append(id)

	GameState.set_discarded_materials(grinder.discarded_materials)
