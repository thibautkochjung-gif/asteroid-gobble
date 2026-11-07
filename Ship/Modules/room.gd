class_name Room
extends Node2D

# Base class for every swappable room.
# ShipRooms installs a room in a slot and hands it a reference to itself (ship_rooms) and the
# slot's size, so a room can reach the hangar, the generator or the other rooms without hard-coded
# paths, and one room scene fits any slot. Each room type works out its capacity from its size.
# Rooms draw themselves in code, on a grid of 2 px texels to match the pixel art:
# first the shell (walls, floor), then what's inside (_draw_contents, overridden by each type).

signal contents_changed

enum Type { SMELTER, CARGO, FUEL_TANK }

const TYPE_NAMES := {
	Type.SMELTER: "Smelter",
	Type.CARGO: "Liquid cargo",
	Type.FUEL_TANK: "Fuel tank",
}

const TEXEL: float = 2.0 # One art pixel, in px. Everything is drawn on this grid
const FLOOR_LINE_SPACING: int = 4 # In texels

@export var room_type: Type = Type.CARGO

@export_group("Shell")
@export var wall_color: Color = Color(0.42, 0.4, 0.38)
@export var floor_color: Color = Color(0.11, 0.11, 0.13)
@export var floor_line_color: Color = Color(0.16, 0.16, 0.18)

var ship_rooms: ShipRooms # Set by ShipRooms before add_child()
var size: Vector2 = Vector2(34, 48) # Set by ShipRooms before add_child(). In px, centred on the origin


func _ready() -> void:
	contents_changed.connect(queue_redraw)


func _draw() -> void:
	_draw_shell()
	_draw_contents()


func get_room_rect() -> Rect2:
	return Rect2(-size * 0.5, size)


# Inside the walls, which are one texel thick.
func get_inner_rect() -> Rect2:
	return get_room_rect().grow(-TEXEL)


# Capacities scale with this.
func get_area_texels() -> float:
	return size.x * size.y / (TEXEL * TEXEL)


# 0..1. Each room type overrides it.
func get_fill_ratio() -> float:
	return 0.0


# Where the contents' weight sits, in this room's space. ShipMass uses it for the centre of mass.
func get_contents_center() -> Vector2:
	return Vector2.ZERO


func get_status_text() -> String:
	return ""


# Called right before the room is swapped out: whatever it held is lost.
func clear_contents() -> void:
	pass


# --- Taking chunks from the hold
# Rooms that take raw chunks (the smelter; later, a holding room) override these four.
# The hangar and the grinder only go through them, never through a specific room type.


func takes_chunks() -> bool:
	return false


# Could this room ever take the chunk, if it were empty? A chunk that no room fits is too big:
# the grinder cuts it down.
func fits_chunk(_chunk: Asteroid) -> bool:
	return false


# Can it take the chunk right now?
func can_accept_chunk(_chunk: Asteroid) -> bool:
	return false


# Takes the chunk off the hold. Returns false if it couldn't after all (it's still in the hold).
# Call can_accept_chunk() first.
func receive_chunk(_chunk: Asteroid) -> bool:
	return false


# Walls, then the floor with a line every few texels.
func _draw_shell() -> void:
	var inner := get_inner_rect()
	draw_rect(get_room_rect(), wall_color)
	draw_rect(inner, floor_color)

	var x := inner.position.x + FLOOR_LINE_SPACING * TEXEL - TEXEL

	while x < inner.end.x - TEXEL:
		draw_rect(Rect2(x, inner.position.y, TEXEL, inner.size.y), floor_line_color)
		x += FLOOR_LINE_SPACING * TEXEL


# Each room type draws what it holds here.
func _draw_contents() -> void:
	pass


# Rounds a length to whole texels, so fills keep the pixel-art look.
func snap_texel(value: float) -> float:
	return snappedf(value, TEXEL)
