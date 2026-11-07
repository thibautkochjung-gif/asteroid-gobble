class_name Tether
extends SoftPoint

# Binds the ship to an asteroid: the two become one solid object. Tap near a rock to weld,
# tap again to let go.
#
# How "one object" is done: welding with joints (PinJoint2D...) is springy in Godot 2D, and a
# light ship pinned to a heavy rock jitters. So the rock really becomes part of the ship's body:
# - the asteroid node moves under the ship (reparent) and is frozen, with its collisions off;
# - its collision rectangles are copied onto the ship's body as extra shapes, so whatever hits
#   the rock hits the ship (and pushes it);
# - its mass counts in the ship's mass and centre of mass, at the rock's centre (through this
#   module's get_mass / get_mass_center). The thrusters now push ship + rock.
# The rock can still be cut while welded (laser, drill, charges): it rebuilds its shapes, and this
# module copies them again (Asteroid.shapes_rebuilt). Chunks cut off it go to space, not into the
# ship (Asteroid.space_parent).
#
# Momentum: welding is a perfectly inelastic catch (like the hangar's): the pair keeps the
# total linear momentum. Spin is only approximated: the ship's spin is scaled by the mass ratio.

@export var reach: float = 60.0 # px from the tether's tip to the rock's surface
@export var max_cells: int = 20000 # Bigger rocks can't be welded
@export var release_ignore_time: float = 1.0 # s without collisions between ship and rock after letting go

@export_group("Look")
@export var drum_color: Color = Color(0.54, 0.5, 0.45)
@export var cable_color: Color = Color(0.83, 0.64, 0.16)
@export var cable_dark_color: Color = Color(0.36, 0.34, 0.31)

var welded: Asteroid

var _anchor_local: Vector2 # Where the cable holds the rock, in the rock's space
var _mirror_owners: Array[int] = []
var _space: Node # Where the rock was, and goes back to
var _saved_layer: int = 0
var _saved_mask: int = 0


func _init() -> void:
	footprint = Rect2(0, -7, 8, 14)
	dry_mass = 2.0


func _physics_process(_delta: float) -> void:
	if welded == null:
		return

	if not is_instance_valid(welded) or welded.cells.is_empty():
		_forget_rock()
		say("Tether: the rock is gone")
		return

	# Frozen bodies keep whatever velocity they had. Chunks cut off the rock start with its velocity,
	# so keep it equal to the ship's motion there.
	welded.linear_velocity = get_ship_velocity_at(welded.get_global_center())
	welded.angular_velocity = ship.angular_velocity
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
	if is_instance_valid(welded):
		return "welded, %d cells" % welded.cells.size()

	return "free"


func get_controls_text() -> String:
	return "tap: let go" if is_instance_valid(welded) else "tap: weld"


func _on_tap() -> void:
	if is_instance_valid(welded):
		release()
	else:
		_try_weld()


func _on_detached() -> void:
	if is_instance_valid(welded):
		release()


func release() -> void:
	var rock := welded
	var velocity := get_ship_velocity_at(rock.get_global_center())

	_clear_mirror()
	rock.shapes_rebuilt.disconnect(_rebuild_mirror)
	rock.reparent(_space, true)
	rock.space_parent = null
	rock.freeze = false
	rock.collision_layer = _saved_layer
	rock.collision_mask = _saved_mask
	rock.linear_velocity = velocity
	rock.angular_velocity = ship.angular_velocity
	soft_points.ignore_collisions_for(rock, release_ignore_time)
	welded = null
	say("Tether: let go")
	queue_redraw()


# --- Welding


func _try_weld() -> void:
	var tip := get_tip()
	var best: Asteroid = null
	var best_point := Vector2.ZERO
	var best_distance := reach

	for node in get_tree().get_nodes_in_group(Asteroid.GROUP):
		var rock := node as Asteroid

		if rock == null or rock.freeze:
			continue

		var point := rock.get_closest_point(tip)
		var distance := point.distance_to(tip)

		if distance <= best_distance:
			best_distance = distance
			best = rock
			best_point = point

	if best == null:
		say("Tether: no rock within reach")
		return

	if best.cells.size() > max_cells:
		say("Tether: too massive to weld")
		return

	_weld(best, best_point)


func _weld(rock: Asteroid, point: Vector2) -> void:
	var total_mass := ship.mass + rock.mass
	ship.linear_velocity = (ship.linear_velocity * ship.mass + rock.linear_velocity * rock.mass) / total_mass
	ship.angular_velocity *= ship.mass / total_mass

	welded = rock
	_anchor_local = rock.to_local(point)
	_space = rock.get_parent()
	_saved_layer = rock.collision_layer
	_saved_mask = rock.collision_mask

	rock.space_parent = _space
	rock.collision_layer = 0
	rock.collision_mask = 0
	rock.freeze_mode = RigidBody2D.FREEZE_MODE_KINEMATIC
	rock.freeze = true
	rock.reparent(ship, true)
	rock.shapes_rebuilt.connect(_rebuild_mirror)
	_rebuild_mirror()
	say("Tether: welded to a %d-cell rock" % rock.cells.size())


# The rock's collision rectangles, copied onto the ship's body. Owned by the rock (not by this
# module), so a hit on the rock is not a hit on the tether (no tearing off).
func _rebuild_mirror() -> void:
	_clear_mirror()

	if not is_instance_valid(welded):
		return

	var rock_to_ship := ship.global_transform.affine_inverse() * welded.global_transform

	for rect in welded.get_collision_rects():
		var center := (Vector2(rect.position) + Vector2(rect.size) * 0.5) * welded.cell_size
		var owner_id := ship.create_shape_owner(welded)
		ship.shape_owner_set_transform(owner_id, rock_to_ship * Transform2D(0.0, center))
		ship.shape_owner_add_shape(owner_id, welded.get_rect_shape(rect.size))
		_mirror_owners.append(owner_id)


func _clear_mirror() -> void:
	if is_instance_valid(ship):
		for owner_id in _mirror_owners:
			ship.remove_shape_owner(owner_id)

	_mirror_owners.clear()


# The rock was destroyed while welded.
func _forget_rock() -> void:
	_clear_mirror()
	welded = null
	queue_redraw()


# --- Look


func _draw_module() -> void:
	_draw_plate(footprint, body_color)

	var drum := Rect2(footprint.position.x + TEXEL * 2.0, footprint.position.y + TEXEL * 2.0, TEXEL * 2.0, footprint.size.y - TEXEL * 4.0)
	draw_rect(drum, drum_color)

	var y := drum.position.y

	while y < drum.end.y:
		draw_rect(Rect2(drum.position.x, y, TEXEL * 2.0, TEXEL), cable_color)
		y += TEXEL * 2.0

	var tip := Vector2(footprint.end.x, footprint.get_center().y)

	if not is_instance_valid(welded):
		draw_rect(Rect2(tip - Vector2(TEXEL, TEXEL * 1.5), Vector2(TEXEL * 2.0, TEXEL * 3.0)), accent_color) # Stowed hook
		return

	var anchor := to_local(welded.to_global(_anchor_local))
	draw_line(tip, anchor, cable_dark_color, TEXEL * 1.5)
	draw_line(tip, anchor, cable_color, TEXEL * 0.5)
	draw_rect(Rect2(anchor - Vector2(TEXEL * 1.5, TEXEL * 1.5), Vector2(TEXEL * 3.0, TEXEL * 3.0)), outline_color)
	draw_rect(Rect2(anchor - Vector2(TEXEL * 0.5, TEXEL * 0.5), Vector2(TEXEL, TEXEL)), accent_color)
