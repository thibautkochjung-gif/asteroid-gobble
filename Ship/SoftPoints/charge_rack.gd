class_name ChargeRack
extends ItemRack

# Demolition charges, to cut a rock where you choose.
# - tap: throw a charge outward. It sticks where it hits (see DemolitionCharge). Throw it into a
#   laser tunnel or a drill hole to plant it deep.
# - hold: detonate every charge this rack has planted.
# Det-cord: charges planted one after the other on the same rock, less than link_range apart, are
# linked. On detonation, the rock is cut along the straight line between each linked pair, about
# cut_width wide: plant a row of charges to draw the cut.
# Tough rock costs more: a cut has a budget (in soft-rock cells, like the laser), and a long cut
# through tough rock may stop short.
# Each charge also blows on its own: it vaporizes a few cells where it sits (a crater, whatever
# the rock), then tears 8 to 16 medium chunks off around the crater. They break off along a few
# random cracks running from the crater, mostly into the rock, so the hole comes out lobed and
# irregular, not round (scraps too small for a chunk turn to dust). Chunks grow along soft rock
# (like the projectile's), so tough patches tend to stay attached, and fly off away from the rock.
# They tumble away from the blast: the edge facing the crater swings outward, like petals opening.
# The chunks come out jagged, locked into the rock like puzzle pieces: for chunk_ghost_time they
# pass through the blasted rocks, to slide out of their hole instead of catching on it. They pass
# through each other for much longer (chunk_separation_time), so they don't clump back together.
# The rock recoils: it gets the chunks' momentum, the other way. A big rock barely moves.
# The blast then pushes anything else close by (det-cord pieces, other rocks, props, the ship).
# It's an impulse: light bodies fly, heavy ones barely move.

@export var link_range: float = 90.0 # px between two linked charges
@export var cut_width: float = 6.0 # px
@export var cut_budget: float = 120.0 # Soft-rock cells per linked pair. Enough for a full link_range through average rock

@export_group("Blast, per charge")
@export var min_crater_cells: int = 15 # Vaporized where the charge sits, soft or tough
@export var max_crater_cells: int = 18
@export var min_chunks: int = 8
@export var max_chunks: int = 16
@export var min_chunk_cells: int = 20
@export var max_chunk_cells: int = 50
@export var crumb_cells: int = 4 # A torn part this small (a scrap left between holes) turns to dust instead of a chunk
@export var chunk_seed_radius_cells: float = 5.0 # Chunks start from cells this close to the crater...
@export var max_seed_radius_cells: float = 20.0 # ...or further, up to this, once the closer rock is gone
@export var min_cracks: int = 2 # Directions the chunks break off along, from the crater
@export var max_cracks: int = 4
@export var crack_spread_degrees: float = 100.0 # Cracks point this far, at most, from straight into the rock
@export var crack_jitter_degrees: float = 20.0 # Each chunk starts this far, at most, off its crack
@export var crack_reach_cells: float = 5.0 # A chunk can start this much further than the nearest rock left
@export var chunk_spin: float = 2.5 # rad/s for a chunk well off to the side of the blast. Less in front of it
@export var chunk_speed: float = 35.0 # px/s, relative to the rock
@export var spread_degrees: float = 40.0 # Around the surface's outward direction. Keep under 90
@export var chunk_ghost_time: float = 1.5 # s. Torn chunks don't collide with the blasted rocks this long
@export var chunk_separation_time: float = 120.0 # s. Chunks torn by the same detonation don't collide with each other this long
@export var blast_radius: float = 50.0 # px. Bodies closer than this to a charge get pushed
@export var blast_impulse: float = 300.0 # Given to a body right on the charge, less further away. Speed = impulse / mass
@export var max_blast_speed: float = 80.0 # px/s. Cap, so tiny debris doesn't shoot off at thousands of px/s

@export_group("Screen shake")
@export var shake_base: float = 0.5 # Trauma for any detonation...
@export var shake_per_charge: float = 0.08 # ...plus this per charge...
@export var max_shake: float = 1.0 # ...up to this. The camera shakes with trauma² and decays fast: below 0.5 it barely shows

var _next_order: int = 0


func _init() -> void:
	footprint = Rect2(0, -10, 8, 20)
	capacity = 10
	item_mass = 0.3
	launch_speed = 60.0
	item_color = Color(0.67, 0.36, 0.18)


func get_status_text() -> String:
	return "%d / %d, %d planted" % [count, capacity, _get_planted().size()]


func get_controls_text() -> String:
	return "tap: throw  hold: detonate"


func _on_hold_started() -> void:
	detonate()


func detonate() -> void:
	var planted := _get_planted()

	if planted.is_empty():
		say("Charges: none planted on a rock")
		return

	var blast_points := PackedVector2Array()

	for charge in planted:
		blast_points.append(charge.global_position)

	# Det-cord first: the craters may remove the cells the line starts from.
	for i in range(1, planted.size()):
		var a := planted[i - 1]
		var b := planted[i]

		if a.get_rock() == b.get_rock() and a.global_position.distance_to(b.global_position) <= link_range:
			_cut_line(a.get_rock(), a.global_position, b.global_position)

	# _blast() already set the speed of the rocks the charges sat on, and of the chunks they tore off.
	var rocks: Array[RigidBody2D] = []
	var torn: Array[RigidBody2D] = []

	for charge in planted:
		var rock := charge.get_rock()

		if is_instance_valid(rock) and not rock.cells.is_empty():
			if not rocks.has(rock):
				rocks.append(rock)

			torn.append_array(_blast(rock, charge.global_position))

		launched.erase(charge)
		charge.queue_free()

	# After the rocks have split (their split is deferred too, and was queued first).
	_start_ghosting(rocks, torn)
	_push_bodies.call_deferred(blast_points, rocks + torn)
	Fx.shake(minf(shake_base + shake_per_charge * planted.size(), max_shake))
	say("Charges: %d detonated" % planted.size())


func _make_item() -> SpaceProp:
	var charge := DemolitionCharge.new()
	charge.order = _next_order
	_next_order += 1
	return charge


func _is_my_item(prop: SpaceProp) -> bool:
	return prop is DemolitionCharge


# Charges of this rack stuck on a rock, in throw order.
func _get_planted() -> Array[DemolitionCharge]:
	var planted: Array[DemolitionCharge] = []

	for item in get_launched():
		var charge := item as DemolitionCharge

		if charge != null and charge.is_stuck() and is_instance_valid(charge.get_rock()):
			planted.append(charge)

	planted.sort_custom(func(a: DemolitionCharge, b: DemolitionCharge) -> bool: return a.order < b.order)
	return planted


# Removes the cells along the segment, cut_width wide, until the budget runs out.
# Samples every half cell along the line and across it.
func _cut_line(rock: Asteroid, from: Vector2, to: Vector2) -> void:
	var step := rock.cell_size * 0.5
	var length := from.distance_to(to)
	var direction := (to - from) / length if length > 0.0 else Vector2.RIGHT
	var across := direction.orthogonal()
	var cells: Array[Vector2i] = []
	var seen: Dictionary[Vector2i, bool] = {}
	var distance := 0.0

	while distance <= length:
		var offset := -cut_width * 0.5

		while offset <= cut_width * 0.5:
			var local := rock.to_local(from + direction * distance + across * offset) / rock.cell_size
			var cell := Vector2i(floori(local.x), floori(local.y))

			if rock.cells.has(cell) and not seen.has(cell):
				seen[cell] = true
				cells.append(cell)

			offset += step

		distance += step

	_vaporize(rock, cells, cut_budget, direction.orthogonal())


# One charge going off: a crater, then medium chunks torn off around it. The rock recoils.
# Returns the chunks it tore off.
func _blast(rock: Asteroid, at: Vector2) -> Array[RigidBody2D]:
	var torn: Array[RigidBody2D] = []
	var center := rock.get_cell_near(at)

	if not rock.cells.has(center):
		return torn

	# Crater: a fixed number of cells, grown from the charge's cell, soft ones first.
	var crater := rock.grow_part(center, randi_range(min_crater_cells, max_crater_cells), true)
	var surface_out := rock.get_outward_direction(crater) # The rock's surface at the charge. Also works deep in a hole
	Fx.spawn_explosion(at, surface_out, rock.get_cell_color(center), rock.get_velocity_at(at))
	_vaporize(rock, crater, INF, surface_out)

	# Crack directions, in the rock's cell space: around "straight into the rock".
	var inward_angle := rock.global_transform.basis_xform_inv(-surface_out).angle()
	var cracks: Array[float] = []

	for _i in randi_range(min_cracks, max_cracks):
		cracks.append(inward_angle + deg_to_rad(randf_range(-crack_spread_degrees, crack_spread_degrees)))

	var recoil := Vector2.ZERO # Momentum the chunks carry away. The rock takes the opposite

	var chunk_count := randi_range(min_chunks, max_chunks)
	var tries_left := chunk_count * 3 # Crumbs don't count as chunks: don't loop forever on them

	while torn.size() < chunk_count and tries_left > 0:
		tries_left -= 1

		if rock.cells.is_empty():
			break

		var seeds := _get_chunk_seeds(rock, center, cracks)

		if seeds.is_empty():
			break

		var part := rock.grow_part(rock.pick_soft_cell(seeds), randi_range(min_chunk_cells, max_chunk_cells), true)
		var is_whole_rock := part.size() >= rock.cells.size()

		if part.size() <= crumb_cells and not is_whole_rock:
			_vaporize(rock, part, INF, surface_out)
			continue

		# The part's own outward guess can be off for a chunk carved deep beside the crater: the
		# surface at the charge keeps it pointing out of the rock.
		var direction := rock.get_outward_direction(part) + surface_out
		direction = direction.normalized() if direction.length_squared() > 0.01 else surface_out
		direction = direction.rotated(deg_to_rad(randf_range(-spread_degrees, spread_degrees)))
		var part_center := rock.get_part_global_center(part)
		var part_velocity := rock.get_velocity_at(part_center)
		var chunk := rock.detach_cells(part, part_velocity + direction * chunk_speed)

		# A small rock can go whole: it's flung, and there's nothing left to tear off.
		if is_whole_rock:
			break

		# Tumbles away from the blast: the cross product is +1 for a chunk off to one side of the
		# blast's axis, -1 for the other side, 0 straight in front of it.
		var side := surface_out.cross((part_center - at).normalized())
		chunk.angular_velocity = rock.angular_velocity + side * chunk_spin * randf_range(0.7, 1.3)
		torn.append(chunk)
		recoil += direction * chunk_speed * part.size() * rock.mass_per_cell

	# The cells are already gone from the rock, but its mass is only updated later (deferred).
	var rock_mass := rock.cells.size() * rock.mass_per_cell

	if not rock.freeze and rock_mass > 0.0:
		rock.linear_velocity -= recoil / rock_mass

	return torn


# Cells to grow the next chunk from, near the hole and along one of the cracks.
# The blast reaches as far as the closest rock left, plus crack_reach_cells: as chunks leave, it
# reaches further out. Inside that reach, a random point along a random crack; the seeds are the
# rock cells around the rock cell closest to that point.
func _get_chunk_seeds(rock: Asteroid, center: Vector2i, cracks: Array[float]) -> Array[Vector2i]:
	var radius := chunk_seed_radius_cells
	var candidates: Array[Vector2i] = []

	while radius <= max_seed_radius_cells:
		candidates = rock.get_cells_near(center, radius)

		if not candidates.is_empty():
			break

		radius += 2.0

	if candidates.is_empty():
		return candidates

	var reach := radius + crack_reach_cells
	candidates = rock.get_cells_near(center, reach)
	var angle: float = cracks.pick_random() + deg_to_rad(randf_range(-crack_jitter_degrees, crack_jitter_degrees))
	var target := Vector2(center) + Vector2.from_angle(angle) * randf_range(0.0, reach)
	var closest := candidates[0]
	var closest_distance := INF

	for cell in candidates:
		var distance := Vector2(cell).distance_squared_to(target)

		if distance < closest_distance:
			closest_distance = distance
			closest = cell

	return rock.get_cells_near(closest, 2.0)


# The torn chunks stop colliding with the blasted rocks for chunk_ghost_time (also with the ship
# a blasted rock is welded to, which holds that rock's collisions), and with each other for
# chunk_separation_time.
func _start_ghosting(rocks: Array[RigidBody2D], torn: Array[RigidBody2D]) -> void:
	if torn.is_empty():
		return

	var bodies: Array[RigidBody2D] = rocks.duplicate()

	# A rock welded to a ship (Tether) is frozen under it, and its collisions are on the ship's body.
	for rock in rocks:
		var holder := rock.get_parent() as RigidBody2D

		if rock.freeze and holder != null and not bodies.has(holder):
			bodies.append(holder)

	for chunk in torn:
		for other in bodies + torn:
			if other != chunk:
				chunk.add_collision_exception_with(other)

	# Static: still runs if this rack is torn off and freed in the meantime.
	var rocks_timer := get_tree().create_timer(chunk_ghost_time, false, true)
	rocks_timer.timeout.connect(ChargeRack._end_ghosting.bind(torn, bodies))
	var chunks_timer := get_tree().create_timer(chunk_separation_time, false, true)
	chunks_timer.timeout.connect(ChargeRack._end_ghosting.bind(torn, torn))


# The torn chunks collide again with these bodies.
static func _end_ghosting(torn: Array[RigidBody2D], bodies: Array[RigidBody2D]) -> void:
	for chunk in torn:
		if not is_instance_valid(chunk):
			continue

		for other in bodies:
			if other != chunk and is_instance_valid(other):
				chunk.remove_collision_exception_with(other)


# Removes cells in order while the budget lasts. Each costs its hardness. Dust for each one.
# budget INF: removes them all.
func _vaporize(rock: Asteroid, cells: Array[Vector2i], budget: float, direction: Vector2) -> void:
	var points := PackedVector2Array()
	var dust_color := Color.GRAY
	var velocity := Vector2.ZERO

	for cell in cells:
		if not rock.cells.has(cell):
			continue

		var hardness := rock.get_hardness(cell)

		if hardness > budget:
			break

		budget -= hardness

		if points.is_empty():
			dust_color = rock.get_cell_color(cell)
			velocity = rock.get_velocity_at(rock.get_cell_global_position(cell))

		points.append(rock.get_cell_global_position(cell))
		rock.remove_cell(cell)

	Fx.spawn_vaporize(points, direction, dust_color, velocity)


# Pushes every free body near a blast point away from it. Closer = harder, heavier = slower.
# Skips the bodies in `skip`: the blasted rocks and their chunks. For a chunk torn from under the
# charge, "away from the charge" points back into the rock: pushing it would send it right back.
func _push_bodies(blast_points: PackedVector2Array, skip: Array[RigidBody2D]) -> void:
	var bodies: Array[RigidBody2D] = []

	for node in get_tree().get_nodes_in_group(Asteroid.GROUP):
		bodies.append(node as RigidBody2D)

	for node in get_tree().get_nodes_in_group(SpaceProp.GROUP):
		bodies.append(node as RigidBody2D)

	if is_instance_valid(ship):
		bodies.append(ship)

	for body in bodies:
		if body == null or body.freeze or skip.has(body):
			continue

		var center := body.global_position

		if body is Asteroid:
			center = (body as Asteroid).get_global_center()

		var push := Vector2.ZERO

		for point in blast_points:
			var offset := center - point
			var distance := offset.length()

			if body is Asteroid:
				distance = (body as Asteroid).get_closest_point(point).distance_to(point)

			if distance > blast_radius:
				continue

			var strength := 1.0 - distance / blast_radius
			push += offset.normalized() * strength

		if push != Vector2.ZERO:
			var speed_change := push * blast_impulse / body.mass
			body.apply_central_impulse(speed_change.limit_length(max_blast_speed) * body.mass)
