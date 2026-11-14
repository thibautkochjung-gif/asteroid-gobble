class_name HudLoadout
extends Control

# The ship seen from above, nose to the right: hull outline, damaged parts, and every soft point
# and hardpoint with its key and module. Built from the ship's own collision shapes and mounts,
# so another ship gets its diagram without new art.
# It floats over space with no panel behind it, so its text gets a drop shadow.

const KEY_SIZE := Vector2(20.0, 18.0)
const KEY_GAP: float = 6.0 # Between the hull's outline and a key cap
const PART_MARK_SIZE: float = 6.0
const LABEL_GAP: float = 6.0

@export var margin_left: float = 150.0 # Room for the hull readout and the left-hand labels
@export var margin_right: float = 120.0 # Room for the hardpoint labels
@export var margin_vertical: float = 30.0 # Room for the key caps above and below the hull
@export var outline_color: Color = Color(CockpitPalette.CREAM, 0.55)

@export_group("Text")
@export var font: Font
@export var font_size: int = 16
@export var title_font: Font
@export var title_size: int = 11
@export var small_font: Font
@export var small_size: int = 11
@export var hull_size: int = 34

var ship: RigidBody2D
var soft_points: ShipSoftPoints
var hardpoints: ShipHardpoints
var ship_damage: ShipDamage
var soft_key_texts: PackedStringArray = [] # Set by Cockpit, same index as the mounts
var hard_key_texts: PackedStringArray = [] # Same index as the hardpoint slots

var _bounds: Rect2 # The hull in ship-local space
var _scale: float = 1.0
var _origin: Vector2 # Where _bounds.position lands in this widget
var _shown_state: Array = [] # What the last redraw showed (see _get_shown_state)


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func setup(new_ship: RigidBody2D, new_soft_points: ShipSoftPoints, new_hardpoints: ShipHardpoints, new_ship_damage: ShipDamage) -> void:
	ship = new_ship
	soft_points = new_soft_points
	hardpoints = new_hardpoints
	ship_damage = new_ship_damage
	_fit_hull()


# Redraws only when something it shows has changed: drawing all this text every frame is costly.
func _process(_delta: float) -> void:
	if ship == null:
		return

	var state := _get_shown_state()

	if state != _shown_state:
		_shown_state = state
		queue_redraw()


func _draw() -> void:
	if ship == null:
		return

	_draw_hull()

	if ship_damage != null:
		_draw_damaged_parts()
		_draw_hull_readout()

	if soft_points != null:
		_draw_soft_points()

	if hardpoints != null:
		_draw_hardpoints()


# --- Layout


# Bounds are measured once: the doors swing, and a diagram that rescales with them would wobble.
func _fit_hull() -> void:
	var polygons := get_hull_polygons(ship)

	if polygons.is_empty():
		return

	_bounds = Rect2(polygons[0][0], Vector2.ZERO)

	for polygon in polygons:
		for point in polygon:
			_bounds = _bounds.expand(point)

	var available := Rect2(margin_left, margin_vertical, size.x - margin_left - margin_right, size.y - 2.0 * margin_vertical)
	_scale = minf(available.size.x / _bounds.size.x, available.size.y / _bounds.size.y)
	_origin = available.position + (available.size - _bounds.size * _scale) / 2.0


func _to_view(local_point: Vector2) -> Vector2:
	return _origin + (local_point - _bounds.position) * _scale


# The hull in ship-local space, from its collision shapes. Static: the ship menu's schematic uses it too.
static func get_hull_polygons(body: Node) -> Array[PackedVector2Array]:
	var polygons: Array[PackedVector2Array] = []

	for child in body.get_children():
		var collision := child as CollisionShape2D

		if collision == null or collision.shape == null or collision.disabled:
			continue

		polygons.append(collision.transform * get_shape_points(collision.shape))

	return polygons


static func get_shape_points(shape: Shape2D) -> PackedVector2Array:
	var convex := shape as ConvexPolygonShape2D

	if convex != null:
		return convex.points

	var rect := shape.get_rect()
	return PackedVector2Array([rect.position, Vector2(rect.end.x, rect.position.y), rect.end, Vector2(rect.position.x, rect.end.y)])


# --- Drawing


func _draw_hull() -> void:
	for polygon in get_hull_polygons(ship):
		var points := PackedVector2Array()

		for point in polygon:
			points.append(_to_view(point))

		draw_colored_polygon(points, Color(CockpitPalette.CREAM, 0.04))
		points.append(points[0])
		draw_polyline(points, Color(0.0, 0.0, 0.0, 0.5), 3.0)
		draw_polyline(points, outline_color, 1.5)


func _draw_damaged_parts() -> void:
	for part in ship_damage.get_parts():
		var health := ShipDamage.get_health(part)

		if health.get_ratio() >= 1.0:
			continue

		for point in ShipDamage.get_damage_points(part):
			var at := _to_view(ship.to_local(point))
			var mark := Rect2(at - Vector2.ONE * PART_MARK_SIZE / 2.0, Vector2.ONE * PART_MARK_SIZE)
			draw_rect(mark.grow(1.0), CockpitPalette.OUTLINE)
			draw_rect(mark, _get_health_color(health))


func _draw_hull_readout() -> void:
	var ratio := ship_damage.get_hull_ratio()
	var middle := _origin.y + _bounds.size.y * _scale / 2.0
	var color := CockpitPalette.YELLOW

	if ratio < 0.25:
		color = CockpitPalette.ALARM
	elif ratio < 0.5:
		color = CockpitPalette.PRIMER

	_draw_text(_font_or_default(title_font), "HULL", Vector2(0.0, middle - 26.0), title_size, CockpitPalette.YELLOW)
	_draw_text(_font_or_default(font), "%d%%" % roundi(ratio * 100.0), Vector2(0.0, middle + 12.0), hull_size, color)

	var worst := _find_worst_part()

	if worst != null:
		var health := ShipDamage.get_health(worst)
		var state := "BROKEN" if health.is_broken() else "%d%%" % roundi(health.get_ratio() * 100.0)
		var text := "%s %s" % [ShipDamage.get_part_name(worst).to_upper(), state]
		_draw_text(_font_or_default(small_font), text, Vector2(0.0, middle + 28.0), small_size, _get_health_color(health))


func _draw_soft_points() -> void:
	var hull_top := _origin.y
	var hull_bottom := _origin.y + _bounds.size.y * _scale
	var middle_x := _bounds.get_center().x

	for i in soft_points.get_mount_count():
		var local := ship.to_local(soft_points.mounts[i].global_position)
		var at := _to_view(local)
		var is_port := local.y < 0.0 # Port side is drawn on top, nose to the right
		var key_y := hull_top - KEY_GAP - KEY_SIZE.y if is_port else hull_bottom + KEY_GAP
		var key_rect := Rect2(at.x - KEY_SIZE.x / 2.0, key_y, KEY_SIZE.x, KEY_SIZE.y)
		var leader_end := key_rect.end.y if is_port else key_rect.position.y

		draw_line(at, Vector2(at.x, leader_end), Color(CockpitPalette.YELLOW, 0.5), 1.0)
		draw_rect(Rect2(at - Vector2(2.0, 2.0), Vector2(4.0, 4.0)), CockpitPalette.YELLOW)

		var module := soft_points.get_module(i)
		var key_text := soft_key_texts[i] if i < soft_key_texts.size() else "?"
		_draw_key(key_rect, key_text, module != null)

		var text := "EMPTY"
		var color := CockpitPalette.TILE_OFF_TEXT

		if module != null:
			text = module.get_type_name().to_upper()
			color = CockpitPalette.CREAM

			if module.get_part_health().is_broken():
				text += " · BROKEN"
				color = CockpitPalette.ALARM
			elif module.is_engaged():
				text += " · " + module.get_status_text().to_upper()
				color = CockpitPalette.YELLOW

		var used_font := _font_or_default(font)
		var baseline := key_rect.position.y + KEY_SIZE.y - 3.0

		if local.x < middle_x:
			var width := used_font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
			_draw_text(used_font, text, Vector2(key_rect.position.x - LABEL_GAP - width, baseline), font_size, color)
		else:
			_draw_text(used_font, text, Vector2(key_rect.end.x + LABEL_GAP, baseline), font_size, color)


func _draw_hardpoints() -> void:
	var label_x := _origin.x + _bounds.size.x * _scale + 10.0

	for i in hardpoints.get_slot_count():
		var at := _to_view(ship.to_local(hardpoints.slots[i].global_position))
		var weapon := hardpoints.get_weapon(i)
		var key_text := hard_key_texts[i] if i < hard_key_texts.size() else "?"
		var text := "%s  %s" % [key_text, weapon.get_part_name().to_upper() if weapon != null else "EMPTY"]
		var color := CockpitPalette.CREAM

		if weapon == null:
			color = CockpitPalette.TILE_OFF_TEXT
		elif weapon.get_part_health().is_broken():
			color = CockpitPalette.ALARM

		if not hardpoints.is_slot_active(i):
			color.a *= 0.4 # The other pair: LMB and RMB don't fire it right now

		draw_line(at, Vector2(label_x - 4.0, at.y), Color(CockpitPalette.CREAM, 0.3), 1.0)
		_draw_text(_font_or_default(font), text, Vector2(label_x, at.y + 5.0), font_size, color)


func _draw_key(rect: Rect2, text: String, is_used: bool) -> void:
	var face := CockpitPalette.YELLOW if is_used else CockpitPalette.LED_OFF
	var side := CockpitPalette.YELLOW_DARK if is_used else CockpitPalette.OUTLINE
	var ink := CockpitPalette.INK_DARK if is_used else CockpitPalette.TILE_OFF_TEXT

	draw_rect(Rect2(rect.position + Vector2(1.0, 2.0), rect.size), Color(0.0, 0.0, 0.0, 0.6))
	draw_rect(rect, face)
	draw_rect(Rect2(rect.position.x, rect.end.y - 3.0, rect.size.x, 3.0), side)
	HudText.draw_centered(self, _font_or_default(font), text, Rect2(rect.position, rect.size - Vector2(0.0, 2.0)), font_size, ink)


func _draw_text(used_font: Font, text: String, baseline_left: Vector2, used_size: int, color: Color) -> void:
	draw_string(used_font, baseline_left + Vector2(0.0, 1.0), text, HORIZONTAL_ALIGNMENT_LEFT, -1, used_size, CockpitPalette.SHADOW)
	draw_string(used_font, baseline_left, text, HORIZONTAL_ALIGNMENT_LEFT, -1, used_size, color)


# --- Helpers


# Everything _draw() depends on, in one list that can be compared. Much cheaper to build than to
# draw. Anything new drawn here must be added here too, or it won't update.
func _get_shown_state() -> Array:
	var state := []

	for child in ship.get_children():
		var collision := child as CollisionShape2D

		if collision != null:
			state.append(collision.disabled)
			state.append(collision.transform) # The hangar doors swing

	if ship_damage != null:
		state.append(ship_damage.get_hull_ratio())

		for part in ship_damage.get_parts():
			var health := ShipDamage.get_health(part)
			state.append(health.get_ratio())

			if health.get_ratio() < 1.0:
				for point in ShipDamage.get_damage_points(part):
					state.append(ship.to_local(point).round()) # Marks follow moving parts, like the drill arm

	if soft_points != null:
		for i in soft_points.get_mount_count():
			var module := soft_points.get_module(i)
			state.append(module)

			if module != null:
				state.append(module.get_part_health().is_broken())
				state.append(module.get_status_text() if module.is_engaged() else "")

	if hardpoints != null:
		for i in hardpoints.get_slot_count():
			var weapon := hardpoints.get_weapon(i)
			state.append(weapon)

			if weapon != null:
				state.append(weapon.get_part_health().is_broken())

	state.append(soft_key_texts)
	state.append(hard_key_texts)
	state.append(hardpoints.active_pair if hardpoints != null else 0)
	return state


func _find_worst_part() -> Node:
	var worst: Node = null
	var worst_ratio := 1.0

	for part in ship_damage.get_parts():
		var ratio := ShipDamage.get_health(part).get_ratio()

		if ratio < worst_ratio:
			worst = part
			worst_ratio = ratio

	return worst


func _get_health_color(health: PartHealth) -> Color:
	if health.is_broken():
		return CockpitPalette.ALARM

	if health.get_ratio() < 0.5:
		return CockpitPalette.PRIMER

	return CockpitPalette.YELLOW


func _font_or_default(used_font: Font) -> Font:
	return used_font if used_font != null else get_theme_default_font()
