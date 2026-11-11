class_name HudVelocity
extends Control

# The drift ring: a faint ring around the ship, drawn in screen space like MapMarkers.
# - Drift: a yellow arc on the ring faces the way the ship is drifting. Chevrons outside it show
#   the speed band: cruising, fast, dangerous (orange).
# - Heading: a cream notch where the nose points now. While turning, a dashed notch shows where it
#   will point after `lead_time`, joined by a dotted arc. Dashed notch on the drift arc = nose
#   lined up with the drift: fire the reverse thrusters to brake.
# Sized in world units, so it hugs the hull at any camera zoom. Hidden while the ship is at rest.

const DRIFT_ARC_HALF_ANGLE: float = 0.28 # rad, about 16°
const NOTCH_HALF_LENGTH: float = 7.0 # px
const CHEVRON_OFFSET: float = 12.0 # px outside the ring
const CHEVRON_GAP: float = 9.0 # px between chevrons
const CHEVRON_SIZE := Vector2(4.0, 6.0) # Depth, half-width
const DOT_SPACING: float = 9.0 # px between the dots of the heading lead
const MAX_LEAD: float = PI * 0.9 # rad. Past this, the lead would wrap round and read as the wrong way

@export var ship: RigidBody2D
@export var ring_radius: float = 150.0 # World px from the ship's centre of mass. Clears the hull
@export var lead_time: float = 2.0 # s. Where the dashed notch predicts the nose will point
@export var min_speed: float = 3.0 # px/s. Slower: no drift arc
@export var min_spin: float = 0.05 # rad/s. Slower: no heading lead
@export var speed_bands: PackedFloat32Array = [6.0, 100.0, 200.0] # px/s for 1, 2 and 3 chevrons. 3 = heavy hits (ShipDamage danger starts)

@export_group("Colors")
@export var drift_color: Color = CockpitPalette.YELLOW
@export var danger_color: Color = CockpitPalette.ALARM # Chevrons in the top speed band
@export var heading_color: Color = CockpitPalette.CREAM
@export var ring_alpha: float = 0.12
@export var lead_alpha: float = 0.6


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _process(_delta: float) -> void:
	queue_redraw()


func _draw() -> void:
	if ship == null:
		return

	var speed := ship.linear_velocity.length()
	var spin := ship.angular_velocity
	var is_drifting := speed >= min_speed
	var is_turning := absf(spin) >= min_spin

	if not is_drifting and not is_turning:
		return

	var canvas := get_viewport().get_canvas_transform()
	var center := canvas * ship.global_position
	var radius := ring_radius * canvas.get_scale().x

	draw_arc(center, radius, 0.0, TAU, 96, Color(heading_color, ring_alpha), 1.5, true)

	if is_drifting:
		_draw_drift(center, radius, canvas.basis_xform(ship.linear_velocity).angle(), speed)

	var nose := canvas.basis_xform(Vector2.from_angle(ship.global_rotation)).angle()
	_draw_notch(center, radius, nose, heading_color, false)

	if is_turning:
		_draw_heading_lead(center, radius, nose, clampf(spin * lead_time, -MAX_LEAD, MAX_LEAD))


func _draw_drift(center: Vector2, radius: float, angle: float, speed: float) -> void:
	var start := angle - DRIFT_ARC_HALF_ANGLE
	var end := angle + DRIFT_ARC_HALF_ANGLE
	draw_arc(center, radius, start, end, 16, CockpitPalette.SHADOW, 6.0, true)
	draw_arc(center, radius, start, end, 16, drift_color, 4.0, true)

	var count := 0

	for band in speed_bands:
		if speed >= band:
			count += 1

	var color := danger_color if count == speed_bands.size() else drift_color
	var direction := Vector2.from_angle(angle)
	var side := direction.orthogonal()

	for i in count:
		var tip := center + direction * (radius + CHEVRON_OFFSET + i * CHEVRON_GAP)
		var back := tip - direction * CHEVRON_SIZE.x
		var points := PackedVector2Array([back + side * CHEVRON_SIZE.y, tip, back - side * CHEVRON_SIZE.y])
		var alpha := 1.0 - i * 0.25
		draw_polyline(points, Color(CockpitPalette.SHADOW, alpha), 4.0, true)
		draw_polyline(points, Color(color, alpha), 2.0, true)


# Dots along the ring from the nose to where it will point, then a dashed notch there.
func _draw_heading_lead(center: Vector2, radius: float, nose: float, lead: float) -> void:
	var step := DOT_SPACING / radius * signf(lead)
	var dots := floori(absf(lead / step))
	var color := Color(heading_color, lead_alpha)

	for i in range(1, dots):
		draw_circle(center + Vector2.from_angle(nose + step * i) * radius, 1.5, color)

	_draw_notch(center, radius, nose + lead, color, true)


func _draw_notch(center: Vector2, radius: float, angle: float, color: Color, is_dashed: bool) -> void:
	var direction := Vector2.from_angle(angle)
	var inner := center + direction * (radius - NOTCH_HALF_LENGTH)
	var outer := center + direction * (radius + NOTCH_HALF_LENGTH)

	if is_dashed:
		draw_dashed_line(inner, outer, color, 3.0, 3.0)
		return

	draw_line(inner, outer, CockpitPalette.SHADOW, 5.0, true)
	draw_line(inner, outer, color, 3.0, true)
