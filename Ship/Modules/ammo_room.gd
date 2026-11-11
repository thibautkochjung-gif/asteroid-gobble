class_name AmmoRoom
extends Room

# Rounds for the projectile launcher. ShipHardpoints draws from every ammo room through ShipRooms.
# Unlike the other rooms, the capacity doesn't follow the slot's size: a fixed number of rounds,
# racked in whatever space there is. The racks are bolted down, so the weight counts at the room's
# centre.
# Drawn as racks of shells standing upright, filled from the bottom row: each drawn shell stands
# for a share of the rounds, so a small slot shows fewer, fatter shares.

const SHELL_WIDTH: int = 2 # Texels
const SHELL_HEIGHT: int = 5 # Texels: 4 of casing, 1 of tip
const SHELL_GAP: int = 1 # Texels, between shells and between rows

@export var capacity: int = 240
@export var start_full: bool = true # Prototype: a freshly installed store comes full

@export_group("Visuals")
@export var shell_color: Color = Color(0.78, 0.6, 0.25)
@export var tip_color: Color = Color(0.45, 0.42, 0.4)
@export var empty_slot_color: Color = Color(0.16, 0.16, 0.18)
@export var rack_color: Color = Color(0.3, 0.29, 0.28)

var rounds: int = 0


func _ready() -> void:
	super()

	if start_full:
		rounds = capacity


# Returns how many rounds were actually given.
func draw_ammo(count: int) -> int:
	var granted := mini(count, rounds)

	if granted <= 0:
		return 0

	rounds -= granted
	contents_changed.emit()
	return granted


func restock() -> void:
	rounds = capacity
	contents_changed.emit()


func get_fill_ratio() -> float:
	return float(rounds) / capacity if capacity > 0 else 0.0


func get_status_text() -> String:
	return "%d / %d rounds" % [rounds, capacity]


func clear_contents() -> void:
	rounds = 0
	contents_changed.emit()


# Rows of shells, a rack bar under each row. Full shells fill the bottom rows first.
func _draw_contents() -> void:
	var inner := get_inner_rect().grow(-TEXEL)
	var step_x := (SHELL_WIDTH + SHELL_GAP) * TEXEL
	var step_y := (SHELL_HEIGHT + SHELL_GAP + 1) * TEXEL # +1: the rack bar
	var columns := maxi(1, floori((inner.size.x + SHELL_GAP * TEXEL) / step_x))
	var rows := maxi(1, floori(inner.size.y / step_y))
	var slot_count := columns * rows
	var full_count := ceili(get_fill_ratio() * slot_count)

	# Centre the grid in the room.
	var grid_size := Vector2(columns * step_x - SHELL_GAP * TEXEL, rows * step_y)
	var origin := _snap_texel_vector(inner.position + (inner.size - grid_size) * 0.5)

	for row in rows:
		var bottom := origin.y + grid_size.y - row * step_y # Row 0 is the bottom one
		draw_rect(Rect2(origin.x, bottom - TEXEL, grid_size.x, TEXEL), rack_color)

		for column in columns:
			var index := row * columns + column
			var shell := Rect2(origin.x + column * step_x, bottom - TEXEL - SHELL_HEIGHT * TEXEL, SHELL_WIDTH * TEXEL, SHELL_HEIGHT * TEXEL)

			if index >= full_count:
				draw_rect(shell, empty_slot_color)
				continue

			draw_rect(shell, shell_color)
			draw_rect(Rect2(shell.position, Vector2(shell.size.x, TEXEL)), tip_color)


func _snap_texel_vector(point: Vector2) -> Vector2:
	return Vector2(snap_texel(point.x), snap_texel(point.y))
