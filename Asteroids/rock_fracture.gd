class_name RockFracture
extends RefCounted

# Cracks for the tools that break rocks along their weak seams (hydraulic splitter, breaching lance).
# A crack is a line of cells, one cell wide, walked from a start cell in a direction. At each step
# it takes one of the cells ahead (straight on, or up to 45° to a side): the cheapest. Soft rock
# costs less than tough rock (hardness²), turning costs, and so does drifting away from the line
# it started on. So it bends around tough patches and follows soft seams, but still crosses.
# It walks on through holes and gaps until it has left the rock: removing its cells
# (Asteroid.split_along) cuts the rock clean through, even across a concave shape.
# Diagonal steps are fine: cells only connect by their sides (Asteroid.NEIGHBOURS), so two cells
# that touch by a corner don't hold the two sides together.

const STEPS: Array[Vector2i] = [
	Vector2i(1, 0),
	Vector2i(1, 1),
	Vector2i(0, 1),
	Vector2i(-1, 1),
	Vector2i(-1, 0),
	Vector2i(-1, -1),
	Vector2i(0, -1),
	Vector2i(1, -1),
]
const MAX_TURN: float = 0.87 # rad, about 50°: the straight cell and the two diagonals ahead
const OPEN_SPACE_COST: float = 0.5 # Crossing a hole is cheap: the crack doesn't avoid holes, it just goes on


# Cells of a crack from start (cell units) along direction (in the rock's cell space).
# turn_cost: per radian off the heading. drift_cost: per cell away from the starting line.
# jitter: random cost added to each choice, so two cracks never look the same.
static func trace(rock: Asteroid, start: Vector2i, direction: Vector2, rng: RandomNumberGenerator, turn_cost: float = 4.0, drift_cost: float = 0.4, jitter: float = 1.5) -> Array[Vector2i]:
	var crack: Array[Vector2i] = []
	var heading := direction.normalized()
	var side := heading.orthogonal()
	var origin := Vector2(start)
	var center := rock.get_local_center() / rock.cell_size - Vector2(0.5, 0.5) # Same units as cell coordinates
	var bound := rock.get_bound_radius() / rock.cell_size + 2.0
	var cell := start

	for i in ceili(bound * 4.0) + 8:
		if rock.cells.has(cell):
			crack.append(cell)

		var from_center := Vector2(cell) - center

		if from_center.length() > bound and from_center.dot(heading) > 0.0:
			break

		cell = _pick_next(rock, cell, heading, side, origin, rng, turn_cost, drift_cost, jitter)

	return crack


static func _pick_next(rock: Asteroid, cell: Vector2i, heading: Vector2, side: Vector2, origin: Vector2, rng: RandomNumberGenerator, turn_cost: float, drift_cost: float, jitter: float) -> Vector2i:
	var best := cell
	var best_score := INF

	for step in STEPS:
		var turn := absf(Vector2(step).angle_to(heading))

		if turn > MAX_TURN:
			continue

		var candidate := cell + step
		var cost := OPEN_SPACE_COST

		if rock.cells.has(candidate):
			var hardness := rock.get_hardness(candidate)
			cost = hardness * hardness

		var drift := absf((Vector2(candidate) - origin).dot(side))
		var score := cost + turn * turn_cost + drift * drift_cost + rng.randf() * jitter

		if score < best_score:
			best_score = score
			best = candidate

	return best


# Global positions of these cells, for dust effects. Call it before the cells are removed.
static func get_points(rock: Asteroid, cell_list: Array[Vector2i]) -> PackedVector2Array:
	var points := PackedVector2Array()

	for cell in cell_list:
		if rock.cells.has(cell):
			points.append(rock.get_cell_global_position(cell))

	return points
