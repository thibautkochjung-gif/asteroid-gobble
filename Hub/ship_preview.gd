class_name ShipPreview
extends Control

# The mechanic's view of the ship: the real hull scene, built from a loadout and frozen in its own
# SubViewport (a separate 2D world, so it collides with nothing and reads no input).
# Markers on top of it mark each slot; clicking one emits slot_pressed. Unselected markers pulse
# gently and show a hand cursor, so they read as buttons.
# Once built, `ship` can be read for stats (capacities, mass): see get_stats().
#
# View: fitted to the whole ship when it's shown (never closer than max_fit_zoom), since hulls
# differ a lot in size. Mouse wheel: zoom toward the cursor. Drag: move the view. Double-click:
# fit again. The markers follow the view.

signal slot_pressed(kind: int, index: int)
signal built

const MARKER_SIZE := Vector2(34.0, 24.0)
const PULSE_PERIOD: float = 1.6 # s
const PULSE_MIN_ALPHA: float = 0.55
const KIND_LETTERS := ["R", "H", "S", "C"] # GameState.Kind order. The computer has no marker on the ship
const KIND_COLORS := [Color(0.38, 0.69, 0.77), Color(0.94, 0.75, 0.29), Color(0.62, 0.84, 0.48), Color(0.78, 0.62, 0.92)]

@export var max_fit_zoom: float = 2.0 # A small ship isn't blown up past this when fitted
@export var fit_margin: float = 48.0 # px kept free around the ship when fitted, for the markers
@export var min_zoom: float = 0.5
@export var max_zoom: float = 4.0
@export var zoom_step: float = 1.15 # Per wheel notch

var ship: RigidBody2D
var zoom: float = 2.0

var _viewport: SubViewport
var _markers: Control
var _selected := Vector2i(-1, -1) # (kind, index)
var _loadout: ShipLoadout # The one shown: not always the active ship (the shipyard shows others)
var _pulse_time: float = 0.0
var _bounds := Rect2() # The ship's extent, in its own space
var _pan := Vector2.ZERO # px. Where the view's centre is, in ship space times zoom, from the bounds' centre
var _is_dragging: bool = false


func _init() -> void:
	clip_contents = true
	mouse_filter = Control.MOUSE_FILTER_STOP
	tooltip_text = "Wheel: zoom. Drag: move. Double-click: fit"
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
	_loadout = loadout
	_clear_markers() # They point at the old ship's slots: gone once it's freed

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
	_bounds = _measure_ship()
	_fit_view()
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
	return {
		"mass": mass.get_total_mass() if mass != null else ship.mass,
		"ingots": rooms.get_ingot_capacity(),
		"ore_bin": rooms.get_ore_bin_capacity(),
		"smelter": rooms.get_smelter_capacity(),
		"fuel": rooms.get_fuel_capacity(),
		"ammo": hardpoints.get_ammo_capacity(),
	}


func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED:
		_fit_view()


func _gui_input(event: InputEvent) -> void:
	var button := event as InputEventMouseButton

	if button != null:
		if button.pressed and button.button_index == MOUSE_BUTTON_WHEEL_UP:
			_zoom_at(button.position, zoom * zoom_step)
			accept_event()
		elif button.pressed and button.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_zoom_at(button.position, zoom / zoom_step)
			accept_event()
		elif button.button_index == MOUSE_BUTTON_LEFT or button.button_index == MOUSE_BUTTON_MIDDLE:
			if button.double_click:
				_fit_view()

			_is_dragging = button.pressed
			accept_event()

		return

	var motion := event as InputEventMouseMotion

	if motion != null and _is_dragging:
		_pan += motion.relative
		_apply_view()
		accept_event()


# --- View


# The ship's collision shapes, plus every slot (hardpoints stick out of the hull), in ship space.
func _measure_ship() -> Rect2:
	var bounds := Rect2()
	var has_any := false

	for child in ship.get_children():
		var collision := child as CollisionShape2D

		if collision == null or collision.shape == null:
			continue

		var rect := collision.transform * collision.shape.get_rect()
		bounds = rect if not has_any else bounds.merge(rect)
		has_any = true

	for node in _get_slot_nodes().reduce(func(all: Array, group: Array) -> Array: return all + group, []):
		var point: Vector2 = ship.to_local((node as Node2D).global_position)
		bounds = Rect2(point, Vector2.ZERO) if not has_any else bounds.expand(point)
		has_any = true

	return bounds


# The whole ship in view, centred, with room for the markers.
func _fit_view() -> void:
	if ship == null or size.x <= 0.0 or size.y <= 0.0:
		return

	var room := (size - Vector2.ONE * fit_margin * 2.0).max(Vector2.ONE)
	var extent := _bounds.size.max(Vector2.ONE)
	zoom = minf(room.x / extent.x, room.y / extent.y)
	zoom = clampf(minf(zoom, max_fit_zoom), min_zoom, max_zoom)
	_pan = Vector2.ZERO
	_apply_view()


# Zooms keeping the ship point under the cursor where it is.
func _zoom_at(screen_point: Vector2, new_zoom: float) -> void:
	new_zoom = clampf(new_zoom, min_zoom, max_zoom)
	var ship_point := (screen_point - _get_origin()) / zoom
	zoom = new_zoom
	_pan += screen_point - (_get_origin() + ship_point * zoom)
	_apply_view()


# Where the ship's origin lands on screen.
func _get_origin() -> Vector2:
	return size * 0.5 + _pan - _bounds.get_center() * zoom


func _apply_view() -> void:
	if _viewport == null or not _viewport.is_inside_tree():
		return

	_viewport.canvas_transform = Transform2D(0.0, Vector2(zoom, zoom), 0.0, _get_origin())
	_place_markers()


# --- Markers


func _get_slot_nodes() -> Array:
	return [
		ship.get_node("Rooms").get_children().filter(func(n: Node) -> bool: return n is RoomSlot),
		ship.get_node("Hardpoints").get_children().filter(func(n: Node) -> bool: return n is Node2D),
		ship.get_node("SoftPoints").get_children().filter(func(n: Node) -> bool: return n is SoftPointMount),
	]


func _clear_markers() -> void:
	for child in _markers.get_children():
		_markers.remove_child(child)
		child.queue_free()


func _build_markers() -> void:
	_clear_markers()

	if ship == null or not ship.is_inside_tree():
		return

	var groups := _get_slot_nodes()

	for kind in groups.size():
		for index in groups[kind].size():
			var node: Node2D = groups[kind][index]
			var marker := Button.new()
			marker.text = "%s%d" % [KIND_LETTERS[kind], index + 1]
			marker.tooltip_text = _get_slot_tooltip(kind, index)
			marker.size = MARKER_SIZE
			marker.add_theme_font_size_override(&"font_size", 14)
			marker.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
			marker.pressed.connect(func() -> void: slot_pressed.emit(kind, index))
			marker.set_meta(&"slot", Vector2i(kind, index))
			marker.set_meta(&"node", node)
			_markers.add_child(marker)

	_place_markers()
	_refresh_markers()


func _place_markers() -> void:
	if ship == null:
		return

	var origin := _get_origin()

	for marker: Button in _markers.get_children():
		var node: Variant = marker.get_meta(&"node")

		if not is_instance_valid(node):
			continue

		marker.position = ship.to_local(node.global_position) * zoom + origin - MARKER_SIZE * 0.5


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
	var slots: Array[int] = [_loadout.rooms, _loadout.hardpoints, _loadout.soft_points][kind]
	var type: int = slots[index] if index < slots.size() else ShipLoadout.EMPTY
	var type_name := "empty" if type == ShipLoadout.EMPTY else GameState.get_type_name(kind, type)
	return "%s %d: %s" % [["Room", "Hardpoint", "Soft point"][kind], index + 1, type_name]
