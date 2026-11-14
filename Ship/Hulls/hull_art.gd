@tool
class_name HullArt
extends Node2D

# Shared pixel language for the hulls drawn in code. Each hull has its own script on top of this one
# (ShipHull for the Bucket, CrabHull for the Crab): this one only holds what they all draw the same way.
# - Plates: outline, fill, light top edge, dark bottom edge, rivets, grime.
# - A nozzle housing behind each thruster (has_nozzle() says which ones get one).
# - The colours, so every hull reads as the same universe.
# Everything is drawn on 2 px texels, like the rooms. @tool: it's drawn in the editor too.
#
# Visuals only. The collision shapes are the ship's CollisionShape2D children, set by hand:
# when the layout changes, update them too (Debug > Visible Collision Shapes helps to compare).

const TEXEL: float = 2.0

@export var rooms: ShipRooms
@export var hangar: Hangar
@export var thrusters: Node2D
@export var grime_seed: int = 7 # Same seed, same dirt

@export_group("Mothership")
@export var berth_crosswise: bool = false # Sits across its mothership slot, nose out, instead of along it. For hulls wider than long
@export_enum("S", "M", "L") var berth_class: String = "S" # The mothership slot size it rides in (Mothership.SLOT_SIZE)

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


# For the mothership: true if this ship's hull sits across its slot. A ship without a HullArt
# "Hull" node sits along it.
static func is_berthed_crosswise(ship: Node) -> bool:
	var hull := ship.get_node_or_null(^"Hull") as HullArt
	return hull != null and hull.berth_crosswise


# For the mothership: the slot size this ship rides in. A ship without a HullArt "Hull" node is small.
static func get_berth_class(ship: Node) -> String:
	var hull := ship.get_node_or_null(^"Hull") as HullArt
	return hull.berth_class if hull != null else "S"


func _ready() -> void:
	set_process(Engine.is_editor_hint())


func _process(_delta: float) -> void:
	if Engine.is_editor_hint():
		queue_redraw() # Follows slot, thruster and hangar edits live. Never runs in game


# Overridden by each hull. False for the thrusters that get a bigger housing of their own (main engines).
func has_nozzle(_thruster: Node2D) -> bool:
	return true


func _get_slots() -> Array[RoomSlot]:
	var slots: Array[RoomSlot] = []

	if rooms == null:
		return slots

	for child in rooms.get_children():
		if child is RoomSlot:
			slots.append(child)

	return slots


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


# Eight corners, clockwise from the back of the left flank. For slabs and canopies.
func _get_chamfered(rect: Rect2, chamfer: float) -> PackedVector2Array:
	var left := rect.position.x
	var right := rect.end.x
	var top := rect.position.y
	var bottom := rect.end.y

	return PackedVector2Array([
		Vector2(left, top + chamfer),
		Vector2(left + chamfer, top),
		Vector2(right - chamfer, top),
		Vector2(right, top + chamfer),
		Vector2(right, bottom - chamfer),
		Vector2(right - chamfer, bottom),
		Vector2(left + chamfer, bottom),
		Vector2(left, bottom - chamfer),
	])


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


# --- Thrusters


# Engine bell from mount_x (where it meets the hull) back to the thruster at exit, with ribs and a
# dark mouth. The bell points toward -x, like every main engine.
func _draw_bell(mount_x: float, exit: Vector2, mount_half_width: float, exit_half_width: float) -> void:
	var exit_x := exit.x
	var y := exit.y
	var points := PackedVector2Array([
		Vector2(mount_x, y - mount_half_width),
		Vector2(exit_x, y - exit_half_width),
		Vector2(exit_x, y + exit_half_width),
		Vector2(mount_x, y + mount_half_width),
	])
	draw_colored_polygon(points, engine_color)

	var length := mount_x - exit_x
	var x := mount_x - TEXEL * 2.0

	while x > exit_x + TEXEL:
		var t := (mount_x - x) / length
		var half := lerpf(mount_half_width, exit_half_width, t) - TEXEL
		draw_rect(Rect2(x, y - half, TEXEL, half * 2.0), engine_color.lightened(0.15))
		x -= TEXEL * 3.0

	draw_rect(Rect2(exit_x, y - exit_half_width + TEXEL, TEXEL * 2.0, exit_half_width * 2.0 - TEXEL * 2.0), engine_inside_color)

	points.append(points[0])
	draw_polyline(points, outline_color, TEXEL)


# A housing behind every thruster that has_nozzle(). A thruster's +x is where its exhaust goes,
# so the housing sits on its -x side; the flame starts at the thruster's own position.
func _draw_nozzles() -> void:
	if thrusters == null:
		return

	for child in thrusters.get_children():
		var thruster := child as Node2D

		if thruster == null or not has_nozzle(thruster):
			continue

		draw_set_transform(thruster.position, thruster.rotation)
		draw_rect(Rect2(-TEXEL * 4.0, -TEXEL * 2.0, TEXEL * 4.0, TEXEL * 4.0), outline_color)
		draw_rect(Rect2(-TEXEL * 3.0, -TEXEL, TEXEL * 2.0, TEXEL * 2.0), pipe_dark_color)
		draw_rect(Rect2(-TEXEL, -TEXEL * 2.0, TEXEL, TEXEL * 4.0), nozzle_color)

	draw_set_transform(Vector2.ZERO)
