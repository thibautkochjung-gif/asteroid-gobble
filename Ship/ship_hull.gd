@tool
class_name ShipHull
extends Node2D

# Draws the hull in code: the "Bucket", a starter ship welded together from whatever was lying around.
# - One plate section around each room slot (the slot grown by hull_padding), so resizing a slot
#   reshapes the hull. The biggest section is drawn last, on top: it bulges over its neighbours.
# - The hangar prongs at the nose, shaped from the hangar's door line and doorway width.
# - The generator housing and the main engine bell at the back. The bell ends on the main thruster.
# - A nozzle housing on every other thruster, wherever it's placed.
# - Bolted-on extras: crew cabin, radiator fins beside one slot, rear outriggers, an exposed fuel line.
# Everything is drawn on 2 px texels, like the rooms. @tool: it's drawn in the editor too.
#
# Visuals only. The collision shapes are the ship's CollisionShape2D children, set by hand:
# when the layout changes, update them too (Debug > Visible Collision Shapes helps to compare).

const TEXEL: float = 2.0

@export var rooms: ShipRooms
@export var hangar: Hangar
@export var thrusters: Node2D
@export var main_engine: Node2D # The bell is drawn ending here. Gets no nozzle housing
@export var grime_seed: int = 7 # Same seed, same dirt

@export_group("Sections")
@export var hull_padding: float = 6.0 # Hull around each slot, in px
@export var section_colors: Array[Color] = [Color(0.31, 0.3, 0.31), Color(0.46, 0.24, 0.15), Color(0.31, 0.3, 0.31)] # One per slot; the last one repeats
@export var patch_rect: Rect2 = Rect2(-40, 24, 16, 12) # Primer patch over an old breach

@export_group("Prongs")
@export var prong_back_x: float = 72.0
@export var prong_outer_y: float = 32.0
@export var prong_chamfer: float = 8.0
@export var left_prong_color: Color = Color(0.48, 0.47, 0.45) # The replacement: bare, unpainted
@export var right_prong_color: Color = Color(0.46, 0.24, 0.15)

@export_group("Tail")
@export var tail_rect: Rect2 = Rect2(-96, -18, 20, 36) # Generator housing
@export var engine_mount_half_width: float = 12.0
@export var engine_exit_half_width: float = 18.0

@export_group("Extras")
@export var cabin_rect: Rect2 = Rect2(-30, -50, 36, 14) # Bolted on the left flank
@export var radiator_slot: int = 0 # Fins on both sides of this slot (the smelter's)
@export var radiator_depth: float = 14.0
@export var outrigger_x: float = -82.0
@export var outrigger_reach: float = 42.0 # From the centreline to the end of each strut
@export var fuel_line_y: float = 38.0
@export var fuel_line_from_x: float = -56.0
@export var fuel_line_to_x: float = 72.0

@export_group("Colors")
@export var outline_color: Color = Color(0.06, 0.055, 0.07)
@export var dark_color: Color = Color(0.21, 0.2, 0.22)
@export var cabin_color: Color = Color(0.33, 0.35, 0.24)
@export var glass_color: Color = Color(0.38, 0.69, 0.77)
@export var glass_dark_color: Color = Color(0.2, 0.39, 0.47)
@export var primer_color: Color = Color(0.67, 0.36, 0.18)
@export var stripe_color: Color = Color(0.83, 0.64, 0.16)
@export var stripe_dark_color: Color = Color(0.12, 0.11, 0.11)
@export var pipe_color: Color = Color(0.54, 0.5, 0.45)
@export var pipe_dark_color: Color = Color(0.36, 0.34, 0.31)
@export var fin_color: Color = Color(0.59, 0.38, 0.27)
@export var engine_color: Color = Color(0.26, 0.27, 0.31)
@export var engine_inside_color: Color = Color(0.09, 0.09, 0.13)
@export var nozzle_color: Color = Color(0.59, 0.59, 0.63)
@export var grime_colors: Array[Color] = [Color(0.19, 0.18, 0.18), Color(0.38, 0.24, 0.16), Color(0.25, 0.24, 0.23)]

var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	set_process(Engine.is_editor_hint())


func _process(_delta: float) -> void:
	if Engine.is_editor_hint():
		queue_redraw() # Follows slot, thruster and hangar edits live. Never runs in game


func _draw() -> void:
	_rng.seed = grime_seed
	var slots := _get_slots()

	_draw_outriggers()
	_draw_engine()
	_draw_plate(tail_rect, dark_color)
	_draw_cabin()
	_draw_sections(slots)
	_draw_patch()
	_draw_prongs()
	_draw_fuel_line()
	_draw_radiators(slots)
	_draw_nozzles()


func _get_slots() -> Array[RoomSlot]:
	var slots: Array[RoomSlot] = []

	if rooms == null:
		return slots

	for child in rooms.get_children():
		if child is RoomSlot:
			slots.append(child)

	return slots


func _get_section_rect(slot: RoomSlot) -> Rect2:
	return Rect2(slot.position - slot.size * 0.5, slot.size).grow(hull_padding)


# --- Plates


# Outline, fill, a light top edge, a dark bottom edge, rivets, and some dirt.
func _draw_plate(rect: Rect2, color: Color) -> void:
	draw_rect(rect, outline_color)

	var inner := rect.grow(-TEXEL)
	draw_rect(inner, color)
	draw_rect(Rect2(inner.position, Vector2(inner.size.x, TEXEL)), color.lightened(0.2))
	draw_rect(Rect2(inner.position.x, inner.end.y - TEXEL, inner.size.x, TEXEL), color.darkened(0.3))

	var x := inner.position.x + TEXEL

	while x < inner.end.x - TEXEL:
		draw_rect(Rect2(x, inner.position.y + TEXEL, TEXEL, TEXEL), color.darkened(0.35))
		draw_rect(Rect2(x, inner.end.y - TEXEL * 2.0, TEXEL, TEXEL), color.darkened(0.35))
		x += TEXEL * 4.0

	_draw_grime(inner, int(inner.get_area() / 120.0))


func _draw_grime(rect: Rect2, count: int) -> void:
	if grime_colors.is_empty():
		return

	var columns := int(rect.size.x / TEXEL)
	var rows := int(rect.size.y / TEXEL)

	if columns <= 0 or rows <= 0:
		return

	for i in count:
		var cell := Vector2(_rng.randi_range(0, columns - 1), _rng.randi_range(0, rows - 1))
		var color := grime_colors[_rng.randi_range(0, grime_colors.size() - 1)]
		draw_rect(Rect2(rect.position + cell * TEXEL, Vector2(TEXEL, TEXEL)), color)


func _draw_sections(slots: Array[RoomSlot]) -> void:
	var order := range(slots.size())
	order.sort_custom(func(a: int, b: int) -> bool: return slots[a].size.x * slots[a].size.y < slots[b].size.x * slots[b].size.y)

	for i: int in order:
		var color: Color = section_colors[mini(i, section_colors.size() - 1)] if not section_colors.is_empty() else dark_color
		_draw_plate(_get_section_rect(slots[i]), color)


func _draw_patch() -> void:
	if patch_rect.has_area():
		draw_rect(patch_rect, primer_color)
		draw_rect(Rect2(patch_rect.position.x + TEXEL, patch_rect.get_center().y, patch_rect.size.x - TEXEL * 2.0, TEXEL), primer_color.darkened(0.25))


# --- Nose


func _draw_prongs() -> void:
	if hangar == null:
		return

	for side: float in [-1.0, 1.0]:
		var front_x := hangar.door_line_x + TEXEL
		var inner_y := hangar.doorway_half_width * side
		var outer_y := prong_outer_y * side
		var points := PackedVector2Array([
			Vector2(prong_back_x, outer_y),
			Vector2(front_x - prong_chamfer, outer_y),
			Vector2(front_x, outer_y - prong_chamfer * side),
			Vector2(front_x, inner_y),
			Vector2(prong_back_x, inner_y),
		])
		var color := left_prong_color if side < 0.0 else right_prong_color
		draw_colored_polygon(points, color)

		points.append(points[0])
		draw_polyline(points, outline_color, TEXEL)

		# Hazard stripe along the mouth
		var stripe_y := inner_y - TEXEL if side > 0.0 else inner_y
		var x := prong_back_x

		while x < front_x - TEXEL:
			var stripe := stripe_color if int(x / (TEXEL * 2.0)) % 2 == 0 else stripe_dark_color
			draw_rect(Rect2(x, stripe_y + side * TEXEL, TEXEL * 2.0, TEXEL), stripe)
			x += TEXEL * 2.0

		_draw_grime(Rect2(prong_back_x, minf(inner_y, outer_y), front_x - prong_chamfer - prong_back_x, absf(outer_y - inner_y)), 12)


# --- Tail


# Bell from the generator housing back to the main thruster, with ribs and a dark mouth.
func _draw_engine() -> void:
	if main_engine == null:
		return

	var mount_x := tail_rect.position.x
	var exit_x := main_engine.position.x
	var y := main_engine.position.y
	var points := PackedVector2Array([
		Vector2(mount_x, y - engine_mount_half_width),
		Vector2(exit_x, y - engine_exit_half_width),
		Vector2(exit_x, y + engine_exit_half_width),
		Vector2(mount_x, y + engine_mount_half_width),
	])
	draw_colored_polygon(points, engine_color)

	var length := mount_x - exit_x
	var x := mount_x - TEXEL * 2.0

	while x > exit_x + TEXEL:
		var t := (mount_x - x) / length
		var half := lerpf(engine_mount_half_width, engine_exit_half_width, t) - TEXEL
		draw_rect(Rect2(x, y - half, TEXEL, half * 2.0), engine_color.lightened(0.15))
		x -= TEXEL * 3.0

	draw_rect(Rect2(exit_x, y - engine_exit_half_width + TEXEL, TEXEL * 2.0, engine_exit_half_width * 2.0 - TEXEL * 2.0), engine_inside_color)

	points.append(points[0])
	draw_polyline(points, outline_color, TEXEL)


# Struts from the generator housing out to the rear side thrusters.
func _draw_outriggers() -> void:
	var tail_half := tail_rect.size.y * 0.5
	var y_center := tail_rect.get_center().y

	for side: float in [-1.0, 1.0]:
		var from_y := y_center + tail_half * side
		var to_y := y_center + outrigger_reach * side
		var strut := Rect2(outrigger_x - TEXEL * 2.0, minf(from_y, to_y), TEXEL * 4.0, absf(to_y - from_y))
		draw_rect(strut, outline_color)
		draw_rect(Rect2(outrigger_x - TEXEL, strut.position.y, TEXEL * 2.0, strut.size.y), pipe_dark_color)
		draw_rect(Rect2(outrigger_x - TEXEL, strut.position.y, TEXEL, strut.size.y), pipe_color)


# --- Extras


func _draw_cabin() -> void:
	if not cabin_rect.has_area():
		return

	_draw_plate(cabin_rect, cabin_color)

	var window := Rect2(cabin_rect.position.x + TEXEL * 3.0, cabin_rect.position.y + TEXEL * 2.0, cabin_rect.size.x - TEXEL * 6.0, TEXEL * 3.0)
	draw_rect(window, glass_dark_color)
	draw_rect(Rect2(window.position.x + TEXEL, window.position.y + TEXEL, window.size.x - TEXEL * 2.0, TEXEL), glass_color)


func _draw_radiators(slots: Array[RoomSlot]) -> void:
	if radiator_slot < 0 or radiator_slot >= slots.size():
		return

	var section := _get_section_rect(slots[radiator_slot])

	for side: float in [-1.0, 1.0]:
		var edge_y := section.position.y if side < 0.0 else section.end.y
		var fins := Rect2(section.position.x + TEXEL * 3.0, minf(edge_y, edge_y + radiator_depth * side), section.size.x - TEXEL * 6.0, radiator_depth)
		draw_rect(fins, outline_color)

		var inside := fins.grow(-TEXEL)
		draw_rect(inside, dark_color)

		var x := inside.position.x + TEXEL

		while x < inside.end.x:
			draw_rect(Rect2(x, inside.position.y, TEXEL, inside.size.y), fin_color)
			x += TEXEL * 2.0


# Two-texel pipe: light top, dark bottom, with a bend into the hull at the back.
func _draw_fuel_line() -> void:
	if fuel_line_to_x <= fuel_line_from_x:
		return

	var length := fuel_line_to_x - fuel_line_from_x
	draw_rect(Rect2(fuel_line_from_x - TEXEL, fuel_line_y - TEXEL, length + TEXEL * 2.0, TEXEL * 4.0), outline_color)
	draw_rect(Rect2(fuel_line_from_x, fuel_line_y, length, TEXEL), pipe_color)
	draw_rect(Rect2(fuel_line_from_x, fuel_line_y + TEXEL, length, TEXEL), pipe_dark_color)

	var x := fuel_line_from_x + TEXEL * 6.0

	while x < fuel_line_to_x:
		draw_rect(Rect2(x, fuel_line_y - TEXEL, TEXEL, TEXEL * 4.0), outline_color) # Clamps
		x += TEXEL * 12.0


# A housing behind every thruster but the main engine. A thruster's +x is where its exhaust goes,
# so the housing sits on its -x side; the flame starts at the thruster's own position.
func _draw_nozzles() -> void:
	if thrusters == null:
		return

	for child in thrusters.get_children():
		var thruster := child as Node2D

		if thruster == null or thruster == main_engine:
			continue

		draw_set_transform(thruster.position, thruster.rotation)
		draw_rect(Rect2(-TEXEL * 4.0, -TEXEL * 2.0, TEXEL * 4.0, TEXEL * 4.0), outline_color)
		draw_rect(Rect2(-TEXEL * 3.0, -TEXEL, TEXEL * 2.0, TEXEL * 2.0), pipe_dark_color)
		draw_rect(Rect2(-TEXEL, -TEXEL * 2.0, TEXEL, TEXEL * 4.0), nozzle_color)

	draw_set_transform(Vector2.ZERO)
