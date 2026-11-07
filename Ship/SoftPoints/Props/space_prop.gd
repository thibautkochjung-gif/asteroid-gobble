class_name SpaceProp
extends RigidBody2D

# Base class for everything soft points put in space: beacons, probes, flares, charges, the cache
# buoy, cargo canisters, and whole modules that were jettisoned or torn off (ModuleProp).
# Props are real bodies: they leave with the ship's momentum, drift, spin and bump into rocks.
# Built and drawn in code: a circle of `radius` unless a subclass builds its own shape.
#
# Coming home: a recoverable prop touching a ship that has soft points, slower than that ship's
# recover_speed, is offered to it (ShipSoftPoints.try_recover). The prop doesn't decide where it
# goes; the ship does. The harpoon can hook props, to reel them in from afar.
#
# Map markers: a prop with marker text gets an arrow at the edge of the screen (MapMarkers).
#
# Subclasses use _prop_process() instead of _physics_process().

const GROUP: StringName = &"space_props"
const TEXEL: float = 2.0
const STATION_MIN_DECELERATION: float = 6.0 # px/s². Without a floor, slowing in proportion to speed never quite stops

@export var radius: float = 4.0 # Collision circle, and the harpoon's target size
@export var recoverable: bool = true
@export var recover_delay: float = 1.5 # s after launch before it can be taken back

@export_group("Colors")
@export var outline_color: Color = Color(0.06, 0.055, 0.07)
@export var body_color: Color = Color(0.46, 0.44, 0.4)
@export var light_color: Color = Color(1.0, 0.3, 0.25)
@export var marker_color: Color = Color(1.0, 0.85, 0.35)

var _recover_timer: float = 0.0
var _age: float = 0.0


func _init() -> void:
	gravity_scale = 0.0
	linear_damp_mode = RigidBody2D.DAMP_MODE_REPLACE # Space: no drag
	angular_damp_mode = RigidBody2D.DAMP_MODE_REPLACE
	contact_monitor = true
	max_contacts_reported = 4
	continuous_cd = RigidBody2D.CCD_MODE_CAST_SHAPE # Small and sometimes fast: don't tunnel through thin chunks


func _ready() -> void:
	add_to_group(GROUP)
	_build_shape()
	_recover_timer = recover_delay


func _physics_process(delta: float) -> void:
	_age += delta
	_prop_process(delta)

	if _recover_timer > 0.0:
		_recover_timer -= delta
	elif recoverable and can_recover():
		_try_recovery()

	queue_redraw()


func _draw() -> void:
	_draw_prop()


# Extra conditions on top of `recoverable` (a buoy only comes home empty).
func can_recover() -> bool:
	return true


# Empty = no marker on the map.
func get_marker_text() -> String:
	return ""


func get_marker_color() -> Color:
	return marker_color


# Blinks: on for `duty` of every `period` seconds.
func is_blink_on(period: float, duty: float = 0.5) -> bool:
	return fmod(_age, period) < period * duty


func _prop_process(_delta: float) -> void:
	pass


func _build_shape() -> void:
	var circle := CircleShape2D.new()
	circle.radius = radius
	var collision := CollisionShape2D.new()
	collision.shape = circle
	add_child(collision)


func _draw_prop() -> void:
	draw_circle(Vector2.ZERO, radius, outline_color)
	draw_circle(Vector2.ZERO, radius - TEXEL * 0.5, body_color)


# Small pixel light: a dark frame and a bright texel.
func _draw_light(at: Vector2, is_on: bool) -> void:
	draw_rect(Rect2(at - Vector2(TEXEL, TEXEL), Vector2(TEXEL * 2.0, TEXEL * 2.0)), outline_color)

	if is_on:
		draw_rect(Rect2(at - Vector2(TEXEL, TEXEL) * 0.5, Vector2(TEXEL, TEXEL)), light_color)


# Slows the prop down to a full stop in about settle_time seconds, with small thrusters, and stops
# its spin the same way. For beacons and the buoy: a bookmark that drifts away isn't a bookmark.
# Braking is proportional to speed (smooth), with a floor so it ends, and a cap so a hard shove
# still sends it away. The last bit of speed is cancelled exactly, instead of overshooting.
func _hold_station(delta: float, settle_time: float, max_acceleration: float) -> void:
	var speed := linear_velocity.length()

	if speed > 0.0:
		var deceleration := clampf(speed / settle_time, STATION_MIN_DECELERATION, max_acceleration)

		if deceleration * delta >= speed:
			apply_central_impulse(-linear_velocity * mass)
		else:
			apply_central_force(-linear_velocity / speed * deceleration * mass)

	var spin := absf(angular_velocity)

	if spin <= 0.0:
		return

	var spin_deceleration := maxf(spin / settle_time, 0.5)

	if spin_deceleration * delta >= spin:
		angular_velocity = 0.0
	else:
		apply_torque(-signf(angular_velocity) * spin_deceleration * _get_inertia())


func _get_inertia() -> float:
	var state := PhysicsServer2D.body_get_direct_state(get_rid())

	if state == null or state.inverse_inertia <= 0.0:
		return mass * radius * radius * 0.5

	return 1.0 / state.inverse_inertia


func _try_recovery() -> void:
	for body in get_colliding_bodies():
		if not body.has_meta(ShipSoftPoints.META_KEY):
			continue

		var soft_points := body.get_meta(ShipSoftPoints.META_KEY) as ShipSoftPoints
		var ship := body as RigidBody2D

		if soft_points == null or ship == null:
			continue

		var relative_speed := (linear_velocity - SoftLink.velocity_at(ship, global_position)).length()

		if relative_speed <= soft_points.recover_speed and soft_points.try_recover(self):
			return
