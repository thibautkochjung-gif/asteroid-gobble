class_name ShipPreview
extends Control

# The mechanic's view of the ship: the real hull scene, built from a loadout and frozen in its own
# SubViewport (a separate 2D world, so it collides with nothing and reads no input).
# Markers on top of it mark each slot; clicking one emits slot_pressed. Unselected markers pulse
# gently and show a hand cursor, so they read as buttons.
# Once built, `ship` can be read for stats (capacities, mass): see get_stats().

signal slot_pressed(kind: int, index: int)
signal built

const MARKER_SIZE := Vector2(34.0, 24.0)
const PULSE_PERIOD: float = 1.6 # s
const PULSE_MIN_ALPHA: float = 0.55
const KIND_LETTERS := ["R", "H", "S"] # GameState.Kind order
const KIND_COLORS := [Color(0.38, 0.69, 0.77), Color(0.94, 0.75, 0.29), Color(0.62, 0.84, 0.48)]

@export var zoom: float = 2.0

var ship: RigidBody2D

var _viewport: SubViewport
var _markers: Control
var _selected := Vector2i(-1, -1) # (kind, index)
var _pulse_time: float = 0.0


func _init() -> void:
	clip_contents = true
	var holder := SubViewportContainer.new()
	holder.stretch = true
	holder.set_anchors_preset(Control.PRESET_FULL_RECT)
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(holder)

	_viewport = SubViewport.new()
	_viewport.transparent_bg = true
	_viewport.handle_input_locally = false
	holder.add_child(_viewport)

	_markers = Control.new()
	_markers.set_anchors_preset(Control.PRESET_FULL_RECT)
	_markers.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_markers)


func _process(delta: float) -> void:
	_pulse_time = fmod(_pulse_time + delta, PULSE_PERIOD)
	var alpha := lerpf(PULSE_MIN_ALPHA, 1.0, 0.5 + 0.5 * cos(TAU * _pulse_time / PULSE_PERIOD))

	for marker: Button in _markers.get_children():
		var is_selected: bool = marker.get_meta(&"slot") == _selected
		marker.modulate.a = 1.0 if is_selected or marker.is_hovered() else alpha


func show_loadout(loadout: ShipLoadout) -> void:
	if ship != null:
		_viewport.remove_child(ship)
		ship.free()

	var hull := GameState.ECONOMY.get_hull(loadout.hull_id)
	ship = hull.get_scene().instantiate()
	loadout.apply(ship)
	ship.freeze = true
	ship.process_mode = Node.PROCESS_MODE_DISABLED # Drawn, but nothing runs: no thrust, no input

	var camera := ship.get_node_or_null("Camera2D") as Camera2D

	if camera != null:
		camera.enabled = false # The view is set below, the ship's camera would fight it

	_viewport.add_child(ship)
	_viewport.canvas_transform = Transform2D(0.0, Vector2(zoom, zoom), 0.0, size * 0.5)
	_build_markers()
	built.emit()


func select(kind: int, index: int) -> void:
	_selected = Vector2i(kind, index)
	_refresh_markers()


# What the mechanic shows under the preview.
func get_stats() -> Dictionary:
	var rooms := ship.get_node("Rooms") as ShipRooms
	var hardpoints := ship.get_node("Hardpoints") as ShipHardpoints
	var mass := ship.get_node_or_null("ShipMass") as ShipMass
	var generator := ship.get_node_or_null("Generator") as Generator
	return {
		"mass": mass.get_total_mass() if mass != null else ship.mass,
		"ingots": rooms.get_ingot_capacity(),
		"ore_bin": rooms.get_ore_bin_capacity(),
		"smelter": rooms.get_smelter_capacity(),
		"fuel": rooms.get_fuel_capacity(),
		"ammo": hardpoints.get_ammo_capacity(),
		"battery": generator.battery_capacity if generator != null else 0.0,
	}


func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED and _viewport != null and is_inside_tree():
		_viewport.canvas_transform = Transform2D(0.0, Vector2(zoom, zoom), 0.0, size * 0.5)
		_build_markers()


func _build_markers() -> void:
	for child in _markers.get_children():
		child.queue_free()

	if ship == null or not ship.is_inside_tree():
		return

	var groups := [
		ship.get_node("Rooms").get_children().filter(func(n: Node) -> bool: return n is RoomSlot),
		ship.get_node("Hardpoints").get_children().filter(func(n: Node) -> bool: return n is Node2D),
		ship.get_node("SoftPoints").get_children().filter(func(n: Node) -> bool: return n is SoftPointMount),
	]

	for kind in groups.size():
		for index in groups[kind].size():
			var node: Node2D = groups[kind][index]
			var marker := Button.new()
			marker.text = "%s%d" % [KIND_LETTERS[kind], index + 1]
			marker.tooltip_text = _get_slot_tooltip(kind, index)
			marker.size = MARKER_SIZE
			marker.position = node.global_position * zoom + size * 0.5 - MARKER_SIZE * 0.5
			marker.add_theme_font_size_override(&"font_size", 14)
			marker.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
			marker.pressed.connect(func() -> void: slot_pressed.emit(kind, index))
			marker.set_meta(&"slot", Vector2i(kind, index))
			_markers.add_child(marker)

	_refresh_markers()


func _refresh_markers() -> void:
	for marker in _markers.get_children():
		var slot: Vector2i = marker.get_meta(&"slot")
		var color: Color = KIND_COLORS[slot.x]
		var is_selected := slot == _selected
		var bg := Color(0.05, 0.05, 0.04, 0.85) if not is_selected else color
		var style := HubStyle.box(bg, color, 2, 2)
		marker.add_theme_stylebox_override(&"normal", style)
		marker.add_theme_stylebox_override(&"hover", HubStyle.box(bg, HubStyle.ACCENT, 2, 2))
		marker.add_theme_stylebox_override(&"pressed", style)
		marker.add_theme_color_override(&"font_color", color if not is_selected else CockpitPalette.INK_DARK)
		marker.add_theme_color_override(&"font_hover_color", HubStyle.ACCENT if not is_selected else CockpitPalette.INK_DARK)


func _get_slot_tooltip(kind: int, index: int) -> String:
	var type: int = GameState.get_slots(kind)[index]
	var name := "empty" if type == ShipLoadout.EMPTY else GameState.get_type_name(kind, type)
	return "%s %d: %s" % [["Room", "Hardpoint", "Soft point"][kind], index + 1, name]
