class_name DeflectorProw
extends HardpointWeapon

# Armoured wedge on an articulated arm (see RobotArm for how the arm moves), like the bow of an
# arctic icebreaker held out in front of the ship. The fire button deploys or stows it.
#
# Deploying: the arm reaches to a point on the ship's centreline, standoff px ahead of the
# foremost thing on the ship: the hull's collision shapes and the muzzles of the other hardpoints,
# where they are when the button is pressed (an arm tool at rest can stick out past the hull).
# The plate faces straight ahead, whatever angle the arm comes in at. Once the arm has stopped,
# the plate unfolds (unfold_time). Stowing: the plate folds first, then the arm goes back to rest.
# If the point is out of reach, the arm gets as close as it can and the plate unfolds there.
#
# The plate is a triangle shape on the ship's body (a shape owner, like the arm's links), moved
# with the arm's head: tip plate_length ahead of the arm's tip, back corners half_width to each
# side. It covers the hangar mouth: stow it to load rock.
# Rocks that hit the plate glance off it. ShipDamage hands those contacts to absorb_impact()
# instead of the hull: no hull damage, no wear on the parts nearby. Contacts on the arm's links
# don't count either, as for every arm tool.
# Wear: only heavy hits count, a rock of at least heavy_rock_mass closing at heavy_impact_speed or
# faster (the mothership always counts as heavy). Lighter or slower hits do nothing. After
# hits_to_buckle heavy hits the plate buckles: it folds and the arm stows until it's repaired.
# Each heavy hit takes the same share of its points, so the HUD's percentage counts them down.

@export_group("Reach")
@export var standoff: float = 10.0 # px between the foremost part of the ship and the plate's back edge
@export var settle_tolerance: float = 0.5 # px or degrees of arm movement per frame that still count as stopped

@export_group("Plate")
@export var plate_length: float = 44.0 # px from the arm's tip to the plate's point
@export var half_width: float = 54.0 # px from the centreline to each back corner
@export var unfold_time: float = 0.4 # s to unfold once in place, and to fold before stowing

@export_group("Wear")
@export var heavy_rock_mass: float = 150.0 # Lighter rocks never wear it. Ship ≈ 26, a rock about 90 px across ≈ 150
@export var heavy_impact_speed: float = 160.0 # px/s of closing speed. Slower hits never wear it
@export var hits_to_buckle: int = 10
@export var hit_shake: float = 0.3 # Camera trauma for a heavy hit

@export_group("Look")
@export var plate_color: Color = Color(0.25, 0.26, 0.28)
@export var rib_color: Color = Color(0.13, 0.13, 0.15)
@export var stripe_color: Color = Color(0.95, 0.74, 0.16)
@export var dent_color: Color = Color(0.08, 0.08, 0.09)
@export var flash_color: Color = Color(1.0, 0.86, 0.6)
@export var flash_time: float = 0.25 # s for the glow of a heavy hit to fade
@export var folded_scale: float = 0.15 # Size of the folded plate, as a share of the unfolded one

var is_deployed: bool = false # What the player asked for
var heavy_hits: int = 0

var _unfold: float = 0.0 # 0 = folded, 1 = open
var _goal: Vector2 # Where the arm's tip goes when deployed, in the arm's space
var _is_settled: bool = false # The arm has stopped moving toward _goal
var _shape := ConvexPolygonShape2D.new()
var _shape_owner: int = -1 # On the ship's body
var _shape_key: Transform2D # Plate transform and unfold the shape was last placed for
var _shape_unfold: float = -1.0
var _dents: Array[Vector3] = [] # Barycentric, so they stay on the plate while it folds
var _flash: float = 0.0

@onready var arm: RobotArm = $Arm
@onready var plate: Node2D = $Arm/Head/Plate


func _ready() -> void:
	get_part_health().changed.connect(_on_health_changed)
	plate.draw.connect(_draw_plate)
	arm.setup(ship)

	if ship == null:
		return

	_shape.points = _get_plate_points(1.0)
	_shape_owner = ship.create_shape_owner(self)
	ship.shape_owner_add_shape(_shape_owner, _shape)
	ship.shape_owner_set_disabled(_shape_owner, true)


func _exit_tree() -> void:
	if is_instance_valid(ship) and _shape_owner >= 0:
		ship.remove_shape_owner(_shape_owner)

	_shape_owner = -1


func _process(delta: float) -> void:
	if Input.is_action_just_pressed(fire_action):
		_toggle()

	if _flash > 0.0:
		_flash = maxf(_flash - delta / flash_time, 0.0)
		plate.queue_redraw()


func _physics_process(delta: float) -> void:
	if get_part_health().is_broken():
		is_deployed = false

	# Stowed and folded: nothing to do. Skips the arm's pose search, the costly part.
	if not is_deployed and _unfold <= 0.0 and arm.is_at_rest():
		return

	arm.refresh_hull()

	if is_deployed:
		_move_arm(delta, _goal.angle(), minf(_goal.length(), arm.max_reach), 0.0)
	elif _unfold > 0.0:
		_is_settled = false # Folds where it is, then goes home
	else:
		_move_arm(delta, arm.get_rest_angle(), arm.rest_tip_distance, NAN)

	var unfold_goal := 1.0 if is_deployed and _is_settled else 0.0
	_unfold = move_toward(_unfold, unfold_goal, delta / unfold_time)
	_apply_shape()


# Called by ShipDamage when a body starts touching the plate.
# impact: { speed, energy, other_mass, point }, see ShipDamage._measure_impact().
func absorb_impact(impact: Dictionary) -> void:
	var health := get_part_health()

	if health.is_broken():
		return

	if impact.other_mass < heavy_rock_mass or impact.speed < heavy_impact_speed:
		return

	heavy_hits += 1
	_add_dent(impact.point)
	_flash = 1.0
	Fx.shake(hit_shake)

	if heavy_hits >= hits_to_buckle:
		health.wear(INF)
		message.emit("buckled, repair at the mechanic")
		return

	health.wear(health.max_points * (1.0 - PartHealth.BROKEN_RATIO) / hits_to_buckle)
	message.emit("heavy hit, %d left" % [hits_to_buckle - heavy_hits])


func get_button_title() -> String:
	return "Prow out" if is_deployed else "Prow in"


# While moving: dark until the plate is open (or folded), so the button shows it working.
func get_cooldown_ratio() -> float:
	var goal := 1.0 if is_deployed else 0.0
	return absf(goal - _unfold)


func get_hit_distance(global_point: Vector2) -> float:
	return arm.get_hit_distance(global_point)


func get_damage_points() -> PackedVector2Array:
	return arm.get_damage_points()


func _toggle() -> void:
	if get_part_health().is_broken():
		message.emit("buckled, repair at the mechanic")
		return

	is_deployed = not is_deployed

	if is_deployed:
		_goal = _find_goal()
		_is_settled = false


# --- Arm


# Moves the arm and notes whether it has stopped: in place, or as close as it can get.
func _move_arm(delta: float, goal_angle: float, goal_tip: float, wanted_head: float) -> void:
	var before := Vector3(arm.angle, arm.tip_distance, arm.head_angle)
	arm.move(delta, goal_angle, goal_tip, wanted_head)
	var after := Vector3(arm.angle, arm.tip_distance, arm.head_angle)
	var tolerance := deg_to_rad(settle_tolerance)
	_is_settled = absf(after.x - before.x) <= tolerance and absf(after.y - before.y) <= settle_tolerance and absf(after.z - before.z) <= tolerance


# On the ship's centreline, standoff px ahead of the foremost part. In the arm's space.
func _find_goal() -> Vector2:
	var front := -INF

	for child in ship.get_children():
		var collision := child as CollisionShape2D

		if collision == null or collision.disabled or collision.shape == null:
			continue

		front = maxf(front, (collision.transform * collision.shape.get_rect()).end.x)

	var hardpoints := get_parent().get_parent() as ShipHardpoints

	if hardpoints != null:
		for weapon in hardpoints.weapons:
			if weapon == null or weapon == self:
				continue

			front = maxf(front, ship.to_local(weapon.muzzle.global_position).x)

	var ship_to_arm := arm.get_relative_transform_to_parent(ship).affine_inverse()
	return ship_to_arm * Vector2(front + standoff, 0.0)


# --- Plate shape


# The triangle in the plate's own space (the arm's tip, head direction = forward): tip, left back
# corner, right back corner. size 1 = unfolded.
func _get_plate_points(size: float) -> PackedVector2Array:
	return PackedVector2Array([
		Vector2(plate_length * size, 0.0),
		Vector2(0.0, -half_width * size),
		Vector2(0.0, half_width * size),
	])


# Folded, the plate has no shape: only the arm's links collide. Moved only when it changed.
func _apply_shape() -> void:
	var to_ship := plate.get_relative_transform_to_parent(ship)

	if to_ship == _shape_key and _unfold == _shape_unfold:
		return

	_shape_key = to_ship
	_shape_unfold = _unfold
	ship.shape_owner_set_disabled(_shape_owner, _unfold <= 0.0)

	if _unfold > 0.0:
		_shape.points = _get_plate_points(_get_size())
		ship.shape_owner_set_transform(_shape_owner, to_ship)

	plate.queue_redraw()


# Eased, so the plate opens and closes softly. Never quite 0, so the folded plate still shows.
func _get_size() -> float:
	return lerpf(folded_scale, 1.0, smoothstep(0.0, 1.0, _unfold))


# Kept as weights of the triangle's corners, nudged inward so it shows on the plate, not its edge.
func _add_dent(global_point: Vector2) -> void:
	var points := _get_plate_points(_get_size())
	var weights := _get_barycentric(plate.to_local(global_point), points[0], points[1], points[2])
	weights = weights.lerp(Vector3.ONE / 3.0, 0.15)
	_dents.append(weights.clamp(Vector3.ZERO, Vector3.ONE))


static func _get_barycentric(p: Vector2, a: Vector2, b: Vector2, c: Vector2) -> Vector3:
	var v0 := b - a
	var v1 := c - a
	var v2 := p - a
	var d00 := v0.dot(v0)
	var d01 := v0.dot(v1)
	var d11 := v1.dot(v1)
	var d20 := v2.dot(v0)
	var d21 := v2.dot(v1)
	var denominator := d00 * d11 - d01 * d01

	if is_zero_approx(denominator):
		return Vector3.ONE / 3.0

	var v := (d11 * d20 - d01 * d21) / denominator
	var w := (d00 * d21 - d01 * d20) / denominator
	return Vector3(1.0 - v - w, v, w)


func _on_health_changed() -> void:
	if get_part_health().get_ratio() < 1.0:
		return

	# Repaired
	heavy_hits = 0
	_dents.clear()
	plate.queue_redraw()


# --- Look. Drawn on the Plate node, which rides on the arm's head.


func _draw_plate() -> void:
	var points := _get_plate_points(_get_size())
	var tip := points[0]
	var left := points[1]
	var right := points[2]
	var back_middle := Vector2.ZERO
	var color := plate_color.lerp(flash_color, _flash * 0.7)

	plate.draw_colored_polygon(points, color)

	# Keel rib and two cross ribs
	plate.draw_line(tip, back_middle, rib_color, 2.0)
	plate.draw_line(tip.lerp(left, 0.55), tip.lerp(right, 0.55), rib_color, 2.0)
	plate.draw_line(left.lerp(back_middle, 0.2), right.lerp(back_middle, 0.2), rib_color, 2.0)

	for dent in _dents:
		var at := tip * dent.x + left * dent.y + right * dent.z
		plate.draw_circle(at, 2.0 * _unfold + 1.0, dent_color)

	# Hazard stripes on the leading edges
	for corner: Vector2 in [left, right]:
		plate.draw_line(tip, corner, stripe_color, 3.0)
		plate.draw_dashed_line(tip, corner, rib_color, 3.0, 4.0)

	var outline := points.duplicate()
	outline.append(tip)
	plate.draw_polyline(outline, rib_color, 1.0)

	# Mounting bracket where the arm's head holds the plate
	plate.draw_rect(Rect2(-6.0, -4.0, 8.0, 8.0), rib_color)
