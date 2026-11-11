class_name RockBolter
extends SoftPoint

# Bolts the ship to an asteroid: the two become one solid object. Tap near a rock to bolt on,
# tap again to let go.
#
# The rig: a strut that pushes on the rock, and two guy cables that pull on it, each held by a
# piton driven into a cell. Push and pull on three points is what makes the pair rigid.
#
# States:
# - STOWED: folded on the module.
# - EXTENDING: the strut and the pitons travel to their cells. Nothing is joined yet. Misses if
#   the rock drifts out of reach or one of the cells is cut away.
# - LOCKED: the pitons bite and the weld happens on that frame, not at the tap. If the rock and
#   the ship move too differently there (max_lock_speed), the pitons bounce off instead.
#   Holds while the strut and at least one guy keep their cells.
# - RELEASING: the pitons and cables fly off the rock as if kicked. The rock keeps its motion:
#   no push-off.
# - RETRACTING: everything reels back in. Taps do nothing until it's stowed.
#
# How "one object" is done: welding with joints (PinJoint2D...) is springy in Godot 2D, and a
# light ship pinned to a heavy rock jitters. So the rock really becomes part of the ship's body:
# - the asteroid node moves under the ship (reparent) and is frozen, with its collisions off.
#   A frozen RigidBody2D isn't reliably carried by its parent (Godot writes the physics server's
#   position back onto it every step), so this module puts it back on its bolted spot every
#   frame (_pin_rock). Without that, it slowly drifts off after a bump;
# - its collision rectangles are copied onto the ship's body as extra shapes, so whatever hits
#   the rock hits the ship (and pushes it);
# - its mass counts in the ship's mass and centre of mass, at the rock's centre (through this
#   module's get_mass / get_mass_center). The thrusters now push ship + rock.
# The rock can still be cut while bolted (laser, drill, charges): it rebuilds its shapes, and this
# module copies them again (Asteroid.shapes_rebuilt). Chunks cut off it go to space, not into the
# ship (Asteroid.space_parent).
#
# Momentum: locking is a perfectly inelastic catch (like the hangar's): the pair keeps the
# total linear momentum. Spin is only approximated: the ship's spin is scaled by the mass ratio.

enum State { STOWED, EXTENDING, LOCKED, RELEASING, RETRACTING }

const STRUT: int = 0
const GUY_TOP: int = 1
const GUY_BOTTOM: int = 2
const LINE_COUNT: int = 3
const CABLE_SEGMENTS: int = 6
const DUST_PER_PUFF: int = 6 # When the pitons bite
const RELEASE_DUST: int = 14 # Per piton, when they're kicked out
const RELEASE_CHIPS: int = 5 # Bits of the rock torn out with each piton
const RELEASE_SPARKS: int = 3
const DUST_RING: Array[Vector2i] = [
	Vector2i(-2, 0), Vector2i(2, 0), Vector2i(0, -2), Vector2i(0, 2), Vector2i(-1, -2),
	Vector2i(1, 2), Vector2i(2, -1), Vector2i(-2, 1), Vector2i(1, -1), Vector2i(-1, 1),
] # Texels around a piton where the hammering left dust

@export var reach: float = 60.0 # px from the strut's mount to the rock's surface
@export var min_reach: float = 6.0 # px. Closer, the strut can't unfold (that's the clamp's job)
@export var guy_reach: float = 90.0 # px, longest a guy cable can be
@export var guy_angles: Array[float] = [35.0, 25.0, 15.0, 5.0] # Degrees off the strut, tried in order until both pitons find a cell
@export var max_cells: int = 20000 # Bigger rocks can't be bolted
@export var extend_speed: float = 220.0 # px/s
@export var miss_margin: float = 16.0 # px past reach before the rock counts as missed
@export var max_lock_speed: float = 40.0 # px/s between rock and ship at the strut's foot. Faster: the pitons bounce off
@export var release_ignore_time: float = 1.0 # s without collisions between ship and rock after letting go

@export_group("Release")
@export var fly_off_speed: float = 140.0 # px/s, the kick that throws the pitons off the rock
@export var fly_off_spin: float = 18.0 # rad/s at most, the pitons tumble as they fly
@export var fly_off_drag: float = 4.0 # 1/s, how fast that kick dies out
@export var fly_off_time: float = 0.35 # s of free flight before the reel starts
@export var strut_kick: float = 6.0 # px the strut's foot jumps back when it lets go
@export var reel_speed: float = 260.0 # px/s
@export var cable_sag: float = 9.0 # px, how far a slack cable bulges

@export_group("Look")
@export var drum_color: Color = Color(0.54, 0.5, 0.45)
@export var cable_color: Color = Color(0.83, 0.64, 0.16)
@export var cable_dark_color: Color = Color(0.36, 0.34, 0.31)
@export var strut_color: Color = Color(0.66, 0.63, 0.59)
@export var piton_color: Color = Color(0.91, 0.72, 0.23)
@export var spike_color: Color = Color(0.84, 0.82, 0.77)
@export var dust_color: Color = Color(0.64, 0.61, 0.56)
@export var dust_life: float = 0.5 # s
@export var spark_color: Color = Color(1.0, 0.85, 0.45)

var state: State = State.STOWED
var welded: Asteroid # Only while LOCKED

var _target: Asteroid # The rock being bolted (EXTENDING) or bolted (LOCKED)
var _anchor_cells: Array[Vector2i] = [Vector2i.ZERO, Vector2i.ZERO, Vector2i.ZERO] # Per line
var _anchor_locals: Array[Vector2] = [Vector2.ZERO, Vector2.ZERO, Vector2.ZERO] # Per line, in the rock's space
var _line_alive: Array[bool] = [false, false, false]
var _extend_distance: float = 0.0 # px every line has unrolled so far
var _piton_positions: Array[Vector2] = [Vector2.ZERO, Vector2.ZERO, Vector2.ZERO] # Module space, once let go
var _piton_velocities: Array[Vector2] = [Vector2.ZERO, Vector2.ZERO, Vector2.ZERO]
var _piton_angles: Array[float] = [0.0, 0.0, 0.0] # Once let go: tumbling
var _piton_spins: Array[float] = [0.0, 0.0, 0.0]
var _strut_end: Vector2 = Vector2.ZERO # Module space, once let go
var _release_time: float = 0.0
var _dust: Array[Dictionary] = [] # { "position", "velocity", "life", "max_life", "color" }, module space

var _rock_local: Transform2D # The bolted rock's place in the ship's space, kept from the lock
var _mirror_owners: Array[int] = []
var _space: Node # Where the rock was, and goes back to
var _saved_layer: int = 0
var _saved_mask: int = 0


func _init() -> void:
	footprint = Rect2(0, -11, 8, 22) # Tall: the guys leave from both ends
	dry_mass = 3.0
	z_index = 1 # Above a bolted rock, or the pitons would hide under it


func _process(delta: float) -> void:
	super._process(delta)
	_pin_rock() # Again after the physics step, so the rock is drawn where it belongs


func _physics_process(delta: float) -> void:
	if ship == null:
		return

	var was_busy := state != State.STOWED or not _dust.is_empty()
	_update_dust(delta)

	match state:
		State.EXTENDING:
			_extend(delta)
		State.LOCKED:
			_hold()
		State.RELEASING:
			_fly_off(delta)
		State.RETRACTING:
			_retract(delta)

	if was_busy:
		queue_redraw()


func get_mass() -> float:
	if is_instance_valid(welded):
		return dry_mass + welded.mass

	return dry_mass


func get_mass_center() -> Vector2:
	var own := to_global(footprint.get_center())

	if not is_instance_valid(welded):
		return own

	return (own * dry_mass + welded.get_global_center() * welded.mass) / (dry_mass + welded.mass)


func get_status_text() -> String:
	match state:
		State.EXTENDING:
			return "bolting"
		State.LOCKED:
			return "bolted, %d cells" % welded.cells.size() if is_instance_valid(welded) else "bolted"
		State.RELEASING, State.RETRACTING:
			return "reeling in"

	return "stowed"


func is_engaged() -> bool:
	return state != State.STOWED


func get_controls_text() -> String:
	match state:
		State.STOWED:
			return "tap: bolt"
		State.EXTENDING:
			return "tap: cancel"
		State.LOCKED:
			return "tap: let go"

	return ""


func _on_tap() -> void:
	match state:
		State.STOWED:
			_try_deploy()
		State.EXTENDING:
			_abort("Rock bolter: cancelled")
		State.LOCKED:
			release()
		_:
			say("Rock bolter: still reeling in")


func _on_detached() -> void:
	if state == State.LOCKED:
		_unweld(welded)

	state = State.STOWED
	_target = null
	_dust.clear()


func release(text: String = "Rock bolter: let go") -> void:
	if state != State.LOCKED:
		return

	var rock := welded
	_start_release()
	_unweld(rock)
	say(text)


# --- Deploying


func _try_deploy() -> void:
	var tip := get_tip()
	var rock := _find_rock(tip)

	if rock == null:
		say("Rock bolter: no rock within reach")
		return

	if rock.cells.size() > max_cells:
		say("Rock bolter: too massive to bolt")
		return

	var surface := rock.get_closest_point(tip)

	if surface.distance_to(tip) < min_reach:
		say("Rock bolter: too close to unfold")
		return

	if not _pick_anchors(rock, surface):
		say("Rock bolter: no grip on that face")
		return

	_target = rock
	_line_alive = [true, true, true]
	_extend_distance = 0.0
	state = State.EXTENDING


func _find_rock(tip: Vector2) -> Asteroid:
	var best: Asteroid = null
	var best_distance := reach

	for rock in Asteroid.find_near(get_tree(), tip, reach):
		if rock.freeze:
			continue

		var distance := rock.get_closest_point(tip).distance_to(tip)

		if distance <= best_distance:
			best_distance = distance
			best = rock

	return best


# The strut aims straight at the rock, the guys fan out from it. Narrower fans are tried
# until both pitons find a cell.
func _pick_anchors(rock: Asteroid, surface: Vector2) -> bool:
	var strut_mount := _get_mount(STRUT)
	var direction := (to_local(surface) - strut_mount).normalized()
	var strut_hit := _cast(rock, strut_mount, direction, reach + rock.cell_size * 2.0)

	if strut_hit.is_empty():
		return false

	for angle in guy_angles:
		var top_hit := _cast(rock, _get_mount(GUY_TOP), direction.rotated(-deg_to_rad(angle)), guy_reach)
		var bottom_hit := _cast(rock, _get_mount(GUY_BOTTOM), direction.rotated(deg_to_rad(angle)), guy_reach)

		if top_hit.is_empty() or bottom_hit.is_empty():
			continue

		_set_anchor(rock, STRUT, strut_hit)
		_set_anchor(rock, GUY_TOP, top_hit)
		_set_anchor(rock, GUY_BOTTOM, bottom_hit)
		return true

	return false


# First cell of the rock on a ray, module space in. Returns { "cell", "point" (global) } or {}.
func _cast(rock: Asteroid, from: Vector2, direction: Vector2, length: float) -> Dictionary:
	var start := to_global(from)
	var end := to_global(from + direction * length)
	var hits := rock.get_cells_on_ray(start, end)

	if hits.is_empty():
		return {}

	var point := start + (end - start).normalized() * float(hits[0]["distance"])
	return { "cell": hits[0]["cell"], "point": point }


func _set_anchor(rock: Asteroid, line: int, hit: Dictionary) -> void:
	_anchor_cells[line] = hit["cell"]
	_anchor_locals[line] = rock.to_local(hit["point"])


func _extend(delta: float) -> void:
	if not is_instance_valid(_target) or _target.freeze or not _are_anchors_intact():
		_abort("Rock bolter: lost the grip points")
		return

	if _is_out_of_reach():
		_abort("Rock bolter: missed, the rock drifted away")
		return

	_extend_distance += extend_speed * delta

	if _extend_distance >= _get_longest_line():
		_impact()


func _are_anchors_intact() -> bool:
	for line in LINE_COUNT:
		if not _target.cells.has(_anchor_cells[line]):
			return false

	return true


func _is_out_of_reach() -> bool:
	if _get_line_length(STRUT) > reach + miss_margin:
		return true

	return _get_line_length(GUY_TOP) > guy_reach + miss_margin or _get_line_length(GUY_BOTTOM) > guy_reach + miss_margin


# The pitons bite. Too much slip between rock and ship: they bounce off.
func _impact() -> void:
	var foot := _target.to_global(_anchor_locals[STRUT])
	var slip := _target.get_velocity_at(foot) - get_ship_velocity_at(foot)

	for line in LINE_COUNT:
		var end := _get_line_end(line)
		_spawn_dust(end, _get_away_from_rock(end))

	if slip.length() > max_lock_speed:
		_start_release()
		say("Rock bolter: too fast, the pitons bounced off")
		return

	_weld(_target)
	state = State.LOCKED
	say("Rock bolter: bolted to a %d-cell rock" % welded.cells.size())


func _abort(text: String) -> void:
	_start_release()
	say(text)


# --- Locked


func _weld(rock: Asteroid) -> void:
	var total_mass := ship.mass + rock.mass
	var pair_velocity := (ship.linear_velocity * ship.mass + rock.linear_velocity * rock.mass) / total_mass
	var pair_spin := ship.angular_velocity * ship.mass / total_mass

	welded = rock
	_space = rock.get_parent()
	_saved_layer = rock.collision_layer
	_saved_mask = rock.collision_mask

	rock.space_parent = _space
	rock.collision_layer = 0
	rock.collision_mask = 0
	rock.freeze_mode = RigidBody2D.FREEZE_MODE_KINEMATIC
	rock.freeze = true
	rock.reparent(ship, true)
	_rock_local = rock.transform
	rock.shapes_rebuilt.connect(_rebuild_mirror)
	_rebuild_mirror()

	# The centre of mass moves into the pair now, then the pair gets its motion: the velocity
	# set here is the pair's centre's, so it must already be there.
	soft_points.mass_changed.emit()
	ship.linear_velocity = pair_velocity
	ship.angular_velocity = pair_spin


func _hold() -> void:
	if not is_instance_valid(welded) or welded.cells.is_empty():
		_forget_rock()
		_start_release()
		say("Rock bolter: the rock is gone")
		return

	_pin_rock()

	# Frozen bodies keep whatever velocity they had. Chunks cut off the rock start with its velocity,
	# so keep it equal to the ship's motion there.
	welded.linear_velocity = get_ship_velocity_at(welded.get_global_center())
	welded.angular_velocity = ship.angular_velocity

	if not welded.cells.has(_anchor_cells[STRUT]):
		release("Rock bolter: the strut lost its footing")
		return

	for guy: int in [GUY_TOP, GUY_BOTTOM]:
		if _line_alive[guy] and not welded.cells.has(_anchor_cells[guy]):
			var end := _get_line_end(guy)
			_spawn_dust(end, _get_away_from_rock(end))
			_line_alive[guy] = false
			say("Rock bolter: a piton pulled out")

	if not _line_alive[GUY_TOP] and not _line_alive[GUY_BOTTOM]:
		release("Rock bolter: both pitons pulled out")


# The rock's collision rectangles, copied onto the ship's body. Owned by the rock (not by this
# module), so a hit on the rock is not a hit on the bolter (no tearing off).
func _rebuild_mirror() -> void:
	_clear_mirror()

	if not is_instance_valid(welded):
		return

	for rect in welded.get_collision_rects():
		var center := (Vector2(rect.position) + Vector2(rect.size) * 0.5) * welded.cell_size
		var owner_id := ship.create_shape_owner(welded)
		ship.shape_owner_set_transform(owner_id, _rock_local * Transform2D(0.0, center))
		ship.shape_owner_add_shape(owner_id, welded.get_rect_shape(rect.size))
		_mirror_owners.append(owner_id)


func _clear_mirror() -> void:
	if is_instance_valid(ship):
		for owner_id in _mirror_owners:
			ship.remove_shape_owner(owner_id)

	_mirror_owners.clear()


func _pin_rock() -> void:
	if state == State.LOCKED and is_instance_valid(welded):
		welded.transform = _rock_local


# Puts the rock back in space, moving as it moved on the ship.
func _unweld(rock: Asteroid) -> void:
	_clear_mirror()
	welded = null

	if not is_instance_valid(rock):
		soft_points.mass_changed.emit()
		return

	var velocity := get_ship_velocity_at(rock.get_global_center())

	rock.shapes_rebuilt.disconnect(_rebuild_mirror)
	rock.reparent(_space, true)
	rock.space_parent = null
	rock.freeze = false
	rock.collision_layer = _saved_layer
	rock.collision_mask = _saved_mask
	rock.linear_velocity = velocity
	rock.angular_velocity = ship.angular_velocity
	soft_points.ignore_collisions_for(rock, release_ignore_time)
	soft_points.mass_changed.emit() # The centre of mass goes back into the ship, which keeps its sling motion


# The rock was destroyed while bolted.
func _forget_rock() -> void:
	_clear_mirror()
	welded = null
	_target = null
	soft_points.mass_changed.emit()


# --- Letting go


# The pitons get kicked off the rock, the strut starts folding. Works from any state with lines
# out: lock, bounce, miss, cancel, lost rock.
func _start_release() -> void:
	var has_rock := is_instance_valid(_target) and not _target.cells.is_empty()

	for line in LINE_COUNT:
		var end := _get_line_end(line) if has_rock else _get_mount(line)
		_piton_positions[line] = end
		_piton_velocities[line] = Vector2.ZERO
		_piton_angles[line] = (end - _get_mount(line)).angle()
		_piton_spins[line] = 0.0

		if not has_rock or not _line_alive[line]:
			continue

		var away := _get_away_from_rock(end)
		_kick_out(line, end, away)

		if line == STRUT:
			_piton_positions[STRUT] = end + away * strut_kick
		else:
			_piton_velocities[line] = away.rotated(randf_range(-0.5, 0.5)) * fly_off_speed * randf_range(0.8, 1.2)
			_piton_spins[line] = randf_range(-fly_off_spin, fly_off_spin)

	_strut_end = _piton_positions[STRUT]
	_release_time = 0.0
	_target = null
	state = State.RELEASING


func _fly_off(delta: float) -> void:
	_release_time += delta
	var drag := maxf(0.0, 1.0 - fly_off_drag * delta)

	for guy: int in [GUY_TOP, GUY_BOTTOM]:
		_piton_velocities[guy] *= drag
		_piton_positions[guy] += _piton_velocities[guy] * delta
		_piton_spins[guy] *= drag
		_piton_angles[guy] += _piton_spins[guy] * delta

	_strut_end = _strut_end.move_toward(_get_mount(STRUT), reel_speed * delta)

	if _release_time >= fly_off_time:
		state = State.RETRACTING


func _retract(delta: float) -> void:
	var step := reel_speed * delta
	_strut_end = _strut_end.move_toward(_get_mount(STRUT), step)
	var is_home := _strut_end == _get_mount(STRUT)

	for guy: int in [GUY_TOP, GUY_BOTTOM]:
		var home := _get_mount(guy)
		_piton_positions[guy] = _piton_positions[guy].move_toward(home, step)
		_piton_angles[guy] = lerp_angle(_piton_angles[guy], (_piton_positions[guy] - home).angle(), 0.3)
		is_home = is_home and _piton_positions[guy] == home

	if is_home:
		state = State.STOWED


# --- Dust


func _spawn_dust(at: Vector2, away: Vector2) -> void:
	_spawn_particles(at, away, DUST_PER_PUFF, 8.0, 30.0, dust_life, dust_color)


# What a piton tears out of the rock as it's kicked off: a cloud of dust, chips of the rock
# itself (in the anchor cell's colour), and a few sparks.
func _kick_out(line: int, at: Vector2, away: Vector2) -> void:
	_spawn_particles(at, away, RELEASE_DUST, 10.0, 55.0, dust_life * 1.4, dust_color)
	_spawn_particles(at, away, RELEASE_SPARKS, 60.0, 110.0, dust_life * 0.4, spark_color)

	if _target.cells.has(_anchor_cells[line]):
		var chip_color := _target.get_cell_color(_anchor_cells[line])
		_spawn_particles(at, away, RELEASE_CHIPS, 30.0, 80.0, dust_life * 1.6, chip_color)


func _spawn_particles(at: Vector2, away: Vector2, count: int, min_speed: float, max_speed: float, life: float, color: Color) -> void:
	for i in count:
		var direction := away.rotated(randf_range(-1.2, 1.2))
		var particle_life := life * randf_range(0.5, 1.0)
		_dust.append({ "position": at, "velocity": direction * randf_range(min_speed, max_speed), "life": particle_life, "max_life": particle_life, "color": color })


func _update_dust(delta: float) -> void:
	for i in range(_dust.size() - 1, -1, -1):
		var particle: Dictionary = _dust[i]
		particle["life"] -= delta

		if particle["life"] <= 0.0:
			_dust.remove_at(i)
			continue

		particle["position"] += particle["velocity"] * delta
		particle["velocity"] *= maxf(0.0, 1.0 - 3.0 * delta)


# --- Geometry (module space)


# Where each line leaves the module: the strut from the middle of the outer face, the guys
# from its ends.
func _get_mount(line: int) -> Vector2:
	match line:
		GUY_TOP:
			return Vector2(footprint.end.x, footprint.position.y + TEXEL)
		GUY_BOTTOM:
			return Vector2(footprint.end.x, footprint.end.y - TEXEL)

	return Vector2(footprint.end.x, footprint.get_center().y)


func _get_anchor(line: int) -> Vector2:
	return to_local(_target.to_global(_anchor_locals[line]))


# Where a line ends right now: partway while extending, on its anchor once locked.
func _get_line_end(line: int) -> Vector2:
	var start := _get_mount(line)

	if not _line_alive[line]:
		return start

	var anchor := _get_anchor(line)

	if state != State.EXTENDING:
		return anchor

	return start + (anchor - start).limit_length(_extend_distance)


func _get_line_length(line: int) -> float:
	return _get_mount(line).distance_to(_get_anchor(line))


func _get_longest_line() -> float:
	return maxf(_get_line_length(STRUT), maxf(_get_line_length(GUY_TOP), _get_line_length(GUY_BOTTOM)))


func _get_away_from_rock(at: Vector2) -> Vector2:
	var away := to_global(at) - _target.get_global_center()
	return global_transform.basis_xform_inv(away).normalized()


func _rock_has_cell_at(global_point: Vector2) -> bool:
	var local := welded.to_local(global_point) / welded.cell_size
	return welded.cells.has(Vector2i(floori(local.x), floori(local.y)))


# --- Look


func _draw_module() -> void:
	_draw_plate(footprint, body_color)
	_draw_drums()

	match state:
		State.STOWED:
			_draw_stowed()
		State.EXTENDING, State.LOCKED:
			_draw_rig()
		State.RELEASING, State.RETRACTING:
			_draw_reeling()

	_draw_dust()


func _draw_drums() -> void:
	var drum := Rect2(footprint.position.x + TEXEL * 2.0, footprint.position.y + TEXEL * 2.0, TEXEL * 2.0, footprint.size.y - TEXEL * 4.0)
	draw_rect(drum, drum_color)

	var y := drum.position.y

	while y < drum.end.y:
		if absf(y + TEXEL * 0.5 - footprint.get_center().y) > TEXEL * 2.0:
			draw_rect(Rect2(drum.position.x, y, TEXEL * 2.0, TEXEL), cable_color)

		y += TEXEL * 2.0

	draw_rect(Rect2(drum.position.x, footprint.get_center().y - TEXEL, TEXEL * 2.0, TEXEL * 2.0), strut_color) # Strut hinge


func _draw_stowed() -> void:
	_draw_foot(_get_mount(STRUT), Vector2.RIGHT)
	_draw_piton(_get_mount(GUY_TOP), Vector2.RIGHT)
	_draw_piton(_get_mount(GUY_BOTTOM), Vector2.RIGHT)


func _draw_rig() -> void:
	if not is_instance_valid(_target):
		return

	if state == State.LOCKED:
		_draw_dust_rings()

	for guy: int in [GUY_TOP, GUY_BOTTOM]:
		if not _line_alive[guy]:
			continue

		var end := _get_line_end(guy)
		_draw_cable(_get_mount(guy), end, 0.0)
		_draw_piton(end, end - _get_mount(guy))

	var foot := _get_line_end(STRUT)
	_draw_strut(foot)
	_draw_foot(foot, foot - _get_mount(STRUT))


func _draw_reeling() -> void:
	var sag := cable_sag if state == State.RELEASING else 0.0

	for guy: int in [GUY_TOP, GUY_BOTTOM]:
		var home := _get_mount(guy)
		var end := _piton_positions[guy]
		var side := 1.0 if guy == GUY_TOP else -1.0
		_draw_cable(home, end, sag * side)
		_draw_piton(end, Vector2.from_angle(_piton_angles[guy]))

	_draw_strut(_strut_end)
	_draw_foot(_strut_end, _strut_end - _get_mount(STRUT))


func _draw_dust_rings() -> void:
	if not is_instance_valid(welded):
		return

	for line in LINE_COUNT:
		if not _line_alive[line]:
			continue

		var center := (_get_anchor(line) / TEXEL).floor() * TEXEL

		for offset in DUST_RING:
			var at := center + Vector2(offset) * TEXEL

			if _rock_has_cell_at(to_global(at + Vector2(TEXEL, TEXEL) * 0.5)):
				draw_rect(Rect2(at, Vector2(TEXEL, TEXEL)), dust_color)


func _draw_dust() -> void:
	for particle in _dust:
		var life: float = particle["life"]
		var max_life: float = particle["max_life"]
		var at: Vector2 = particle["position"]
		var color: Color = particle["color"]
		color.a = clampf(life / max_life * 1.5, 0.0, 1.0)
		draw_rect(Rect2((at / TEXEL).floor() * TEXEL, Vector2(TEXEL, TEXEL)), color)


# sag > 0 bulges to the left of from -> to, < 0 to the right. 0: taut.
func _draw_cable(from: Vector2, to: Vector2, sag: float) -> void:
	var points := PackedVector2Array()
	var normal := (to - from).orthogonal().normalized()

	for i in CABLE_SEGMENTS + 1:
		var t := float(i) / CABLE_SEGMENTS
		points.append(from.lerp(to, t) + normal * sag * 4.0 * t * (1.0 - t))

	draw_polyline(points, cable_dark_color, TEXEL * 1.5)
	draw_polyline(points, cable_color, TEXEL * 0.5)


func _draw_strut(to: Vector2) -> void:
	var from := _get_mount(STRUT)
	draw_line(from, to, outline_color, TEXEL * 2.5)
	draw_line(from, to, strut_color, TEXEL * 1.5)
	draw_line(from, to, strut_color.lightened(0.3), TEXEL * 0.5)


func _draw_foot(at: Vector2, direction: Vector2) -> void:
	draw_set_transform(at, direction.angle())
	draw_rect(Rect2(-TEXEL * 2.0, -TEXEL * 3.5, TEXEL * 2.0, TEXEL * 7.0), outline_color)
	draw_rect(Rect2(-TEXEL * 1.5, -TEXEL * 3.0, TEXEL, TEXEL * 6.0), strut_color.darkened(0.1))
	draw_set_transform(Vector2.ZERO, 0.0)


# Head behind the point, spike past it (into the rock once driven in).
func _draw_piton(at: Vector2, direction: Vector2) -> void:
	draw_set_transform(at, direction.angle())
	draw_rect(Rect2(0.0, -TEXEL * 0.5, TEXEL * 2.0, TEXEL), spike_color)
	draw_rect(Rect2(-TEXEL * 2.5, -TEXEL * 1.5, TEXEL * 2.5, TEXEL * 3.0), outline_color)
	draw_rect(Rect2(-TEXEL * 2.0, -TEXEL, TEXEL * 1.5, TEXEL * 2.0), piton_color)
	draw_set_transform(Vector2.ZERO, 0.0)
