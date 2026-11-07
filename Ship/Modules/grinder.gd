class_name Grinder
extends Node2D

# Grinds down chunks in the hold (behind the hangar doors) that are too big for every room that
# takes chunks (Hangar.is_too_big). While at least one is, the grinder works on the largest chunk in
# the hold. Every cut_time seconds of work, it cuts that chunk into two halves
# (Asteroid.split_in_halves). It repeats as often as needed. The hangar hands every piece that fits
# to a room by itself. With no room taking chunks, nothing is too big, and the grinder stays idle.
# A chunk only needs to be partly in the hold, like a log in a woodchipper.
# Rocks over max_grind_cells are ignored: a whole asteroid nudging the open doors isn't ground.
# Feed rollers pull every chunk in the hold toward the back (feed_acceleration), so cut pieces and
# chunks waiting for a free room don't drift back out of the doors. The rollers are part of the
# ship, so the ship gets the opposite force: the pull alone doesn't move the ship.
# Short on power = it works slower.

@export var ship: RigidBody2D
@export var hangar: Hangar
@export var generator: Generator
@export var cut_time: float = 5.0 # Seconds of work per cut. The starter ship's grinder is small and slow
@export var power_per_second: float = 1.5
@export var separation_speed: float = 6.0 # px/s between the two halves
@export var max_grind_cells: int = 300 # Bigger rocks touching the hold are left alone
@export var feed_acceleration: float = 30.0 # px/s², toward the back of the hold

var is_working: bool = false
var progress: float = 0.0 # 0..1 toward the next cut


func _physics_process(delta: float) -> void:
	_feed()

	var target := _find_target()
	is_working = target != null

	if not is_working:
		progress = 0.0
		return

	progress += delta / cut_time * _draw_power(delta)

	if progress >= 1.0:
		progress = 0.0
		_cut(target)


func get_status_text() -> String:
	if not is_working:
		return "idle"

	return "grinding %d%%" % roundi(progress * 100.0)


# Pulls the chunks in the hold toward the back wall. The hangar sits at the ship's origin,
# so its -x is the ship's backward direction.
# apply_central_force lasts one physics step, so this runs every frame.
func _feed() -> void:
	var inward := hangar.global_transform.basis_xform(Vector2.LEFT).normalized()

	for chunk in hangar.get_chunks_inside():
		if chunk.cells.size() > max_grind_cells:
			continue

		var force := inward * feed_acceleration * chunk.mass
		chunk.apply_central_force(force)
		ship.apply_force(-force, chunk.get_global_center() - ship.global_position)


# The largest chunk in the hold, if any chunk there is too big. Null otherwise.
# Rocks over max_grind_cells don't count, either way.
func _find_target() -> Asteroid:
	var is_any_too_big := false
	var largest: Asteroid = null

	for chunk in hangar.get_chunks_inside():
		if chunk.cells.size() > max_grind_cells:
			continue

		if hangar.is_too_big(chunk):
			is_any_too_big = true

		if largest == null or chunk.cells.size() > largest.cells.size():
			largest = chunk

	return largest if is_any_too_big else null


func _cut(chunk: Asteroid) -> void:
	var dust_color := chunk.get_cell_color(chunk.cells.keys()[0])
	var half := chunk.split_in_halves(separation_speed)

	if half == null:
		return

	# A puff of dust between the two halves.
	var between := (chunk.get_global_center() + half.get_global_center()) * 0.5
	var direction := (half.get_global_center() - chunk.get_global_center()).normalized()
	Fx.spawn_vaporize(PackedVector2Array([between]), direction.orthogonal(), dust_color, chunk.linear_velocity)


# Returns the share of the needed power the generator could give, 0..1.
func _draw_power(delta: float) -> float:
	var needed := power_per_second * delta

	if generator == null or needed <= 0.0:
		return 1.0

	return generator.draw_power(needed) / needed
