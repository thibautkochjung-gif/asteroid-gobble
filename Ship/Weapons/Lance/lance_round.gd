class_name LanceRound
extends Node2D

# One breaching lance, fired by a BreachingLance (its settings come from there).
# FLYING: straight on, no drag. Each frame it tests the segment it just flew, so it can't skip a
# thin rock.
# Hitting a rock, it drives in along its flight line: each cell costs its hardness out of the
# weapon's penetration_budget, and it stops on the last cell it can afford (or the last rock cell
# on its line, if it comes out the other side). The cells are pushed aside, not removed.
# ARMED: it rides on that cell (BodyAnchor) and blinks for fuse_time, then goes off:
# - a small crater around it, vaporized;
# - min_pieces to max_pieces cracks running out from it in evenly spread directions, each following
#   the weak rock (RockFracture). They cut the rock in that many big pieces;
# - the pieces fly apart from the blast, small ones faster.
# If its cell is cut away before the fuse ends, it falls out: a dud.

enum State { FLYING, ARMED }

const TEXEL: float = 2.0
const REFERENCE_PIECE_CELLS: float = 300.0 # A piece this big gets blast_speed. Smaller ones more, bigger ones less
const DUST_EVERY: int = 3 # One dust puff per this many crack cells

var weapon: BreachingLance
var velocity: Vector2 = Vector2.ZERO
var lifetime: float = 1.0
var state: State = State.FLYING
var anchor: BodyAnchor

var _age: float = 0.0
var _fuse_left: float = 0.0
var _local_rotation: float = 0.0 # Relative to the rock, once armed
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	z_index = 2
	_rng.randomize()


func _physics_process(delta: float) -> void:
	_age += delta

	match state:
		State.FLYING:
			_fly(delta)
		State.ARMED:
			_tick_fuse(delta)

	queue_redraw()


func _fly(delta: float) -> void:
	var from := global_position
	var to := from + velocity * delta
	var hits := Asteroid.find_hits_on_ray(get_tree(), from, to, 1)

	if hits.is_empty():
		global_position = to

		if _age > lifetime:
			queue_free()

		return

	_embed(hits[0]["asteroid"], from + velocity.normalized() * hits[0]["distance"])


func _embed(rock: Asteroid, entry: Vector2) -> void:
	var direction := velocity.normalized()
	var budget := weapon.penetration_budget if is_instance_valid(weapon) else 40.0
	var depth := weapon.max_depth if is_instance_valid(weapon) else 200.0
	var stop_cell := rock.get_cell_near(entry)

	for hit in rock.get_cells_on_ray(entry, entry + direction * depth):
		var cell: Vector2i = hit["cell"]
		var hardness := rock.get_hardness(cell)

		if hardness > budget:
			break

		budget -= hardness
		stop_cell = cell

	if not rock.cells.has(stop_cell):
		queue_free()
		return

	anchor = BodyAnchor.on_body(rock, rock.get_cell_global_position(stop_cell))
	_local_rotation = direction.angle() - rock.global_rotation
	_fuse_left = weapon.fuse_time if is_instance_valid(weapon) else 1.5
	state = State.ARMED
	global_position = anchor.get_global_position()
	Fx.spawn_vaporize(PackedVector2Array([entry]), -direction, rock.get_cell_color(stop_cell), rock.get_velocity_at(entry))


func _tick_fuse(delta: float) -> void:
	if not anchor.resolve(get_tree()):
		queue_free() # Its cell was cut away: it fell out, a dud
		return

	global_position = anchor.get_global_position()
	rotation = anchor.body.global_rotation + _local_rotation
	_fuse_left -= delta

	if _fuse_left <= 0.0:
		_detonate(anchor.get_asteroid(), anchor.cell)
		queue_free()


func _detonate(rock: Asteroid, center: Vector2i) -> void:
	if rock == null or not rock.cells.has(center):
		return

	var blast_at := rock.get_cell_global_position(center)
	var crater := rock.grow_part(center, weapon.crater_cells, true)
	var cut: Array[Vector2i] = crater.duplicate()
	var dust := RockFracture.get_points(rock, crater)
	var piece_count := _rng.randi_range(weapon.min_pieces, weapon.max_pieces)
	var start_angle := _rng.randf() * TAU

	for i in piece_count:
		var angle := start_angle + TAU * i / piece_count + _rng.randf_range(-0.3, 0.3)
		var crack := RockFracture.trace(rock, center, Vector2.from_angle(angle), _rng, 3.0, 0.25)

		for j in range(0, crack.size(), DUST_EVERY):
			if rock.cells.has(crack[j]):
				dust.append(rock.get_cell_global_position(crack[j]))

		cut.append_array(crack)

	var dust_color := rock.get_cell_color(center)
	var old_center := rock.get_global_center()
	var old_velocity := rock.linear_velocity
	var old_spin := rock.angular_velocity
	var out_of_rock := (blast_at - old_center).normalized() if blast_at != old_center else Vector2.RIGHT

	var pieces := rock.split_along(cut)

	if is_instance_valid(rock) and not rock.cells.is_empty():
		pieces.append(rock)

	Fx.spawn_explosion(blast_at, out_of_rock, dust_color, old_velocity)
	Fx.spawn_vaporize(dust, out_of_rock, dust_color, old_velocity)
	Fx.shake(weapon.blast_shake)

	for piece in pieces:
		if piece.freeze:
			continue

		var piece_center := piece.get_global_center()
		var offset := piece_center - old_center
		var carried := old_velocity + Vector2(-old_spin * offset.y, old_spin * offset.x)
		var away := (piece_center - blast_at).normalized()
		var speed := weapon.blast_speed * clampf(sqrt(REFERENCE_PIECE_CELLS / maxf(piece.cells.size(), 1.0)), 0.3, 2.0)
		piece.linear_velocity = carried + away * speed
		piece.angular_velocity = old_spin + _rng.randf_range(-0.3, 0.3)


# A steel shaft with a red light, blinking faster as the fuse runs out.
func _draw() -> void:
	var shaft := Rect2(-TEXEL * 6.0, -TEXEL * 0.75, TEXEL * 7.0, TEXEL * 1.5)
	draw_rect(shaft.grow(TEXEL * 0.5), Color(0.06, 0.055, 0.07))
	draw_rect(shaft, Color(0.84, 0.82, 0.77))
	draw_colored_polygon(PackedVector2Array([Vector2(TEXEL * 3.0, 0.0), Vector2(TEXEL, -TEXEL), Vector2(TEXEL, TEXEL)]), Color(0.66, 0.63, 0.59))

	if state != State.ARMED:
		return

	var fuse := weapon.fuse_time if is_instance_valid(weapon) else 1.5
	var rate := lerpf(12.0, 3.0, _fuse_left / fuse) # Blinks per second
	var is_on := fmod(_age * rate, 1.0) < 0.5
	var tail := Vector2(-TEXEL * 6.0, 0.0)
	draw_rect(Rect2(tail - Vector2(TEXEL, TEXEL), Vector2(TEXEL * 2.0, TEXEL * 2.0)), Color(0.06, 0.055, 0.07))
	draw_rect(Rect2(tail - Vector2(TEXEL, TEXEL) * 0.5, Vector2(TEXEL, TEXEL)), Color(1.0, 0.2, 0.12) if is_on else Color(0.35, 0.08, 0.06))

	if is_on:
		draw_circle(tail, TEXEL * 4.0, Color(1.0, 0.2, 0.12, 0.25))
