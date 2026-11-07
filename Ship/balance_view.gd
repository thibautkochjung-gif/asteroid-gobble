class_name BalanceView
extends Node2D

# Shows how the ship is balanced. Toggle with toggle_balance_view (B).
# Drawn in the ship's space (this node sits at the ship's origin), on top of everything:
# - the centre of mass (yellow cross), and where it would be with an empty hull (grey cross);
# - every module's mass (circles, bigger = heavier), so you see what drags the balance where;
# - each thruster's line of push (dashed) and its lever arm: the perpendicular from the centre of
#   mass to that line. A push turns the ship by force * lever arm. Blue levers turn it clockwise,
#   red ones counterclockwise; the active thrusters are drawn bright;
# - live: the net push (arrow from the centre of mass) and the net turn (arc around it).
# get_role_report() gives the same thing per input, for the HUD: how hard each one pushes the
# ship, and how much it turns it while doing so. A balanced ship strafes without turning.

const TEXEL: float = 2.0

const ROLE_NAMES := {
	&"forward_thrust": "Forward",
	&"backward_thrust": "Backward",
	&"left_thrust": "Strafe left",
	&"right_thrust": "Strafe right",
	&"left_turn": "Turn left",
	&"right_turn": "Turn right",
}

@export var ship: RigidBody2D
@export var thrusters: Node2D
@export var ship_mass: ShipMass
@export var soft_points: ShipSoftPoints
@export var report_roles: Array[StringName] = [&"forward_thrust", &"backward_thrust", &"left_thrust", &"right_thrust"]
@export var line_length: float = 260.0 # How far each line of push is drawn
@export var force_arrow_scale: float = 0.01 # px of arrow per unit of force
@export var turn_arc_scale: float = 0.0004 # Radians of arc per unit of torque

@export_group("Colors")
@export var center_color: Color = Color(1.0, 0.85, 0.2)
@export var empty_center_color: Color = Color(0.6, 0.6, 0.6, 0.8)
@export var line_color: Color = Color(1.0, 1.0, 1.0, 0.15)
@export var clockwise_color: Color = Color(0.35, 0.65, 1.0)
@export var counterclockwise_color: Color = Color(1.0, 0.4, 0.35)
@export var mass_color: Color = Color(1.0, 0.85, 0.2, 0.35)
@export var force_color: Color = Color(0.4, 1.0, 0.5)


func _ready() -> void:
	visible = false
	z_index = 20


func _process(_delta: float) -> void:
	if Input.is_action_just_pressed("toggle_balance_view"):
		visible = not visible

	if visible:
		queue_redraw()


func _draw() -> void:
	var center := ship.center_of_mass
	var net_force := Vector2.ZERO
	var net_torque := 0.0

	_draw_masses()

	for thruster in _get_thrusters():
		var thruster_position := ship.to_local(thruster.global_position)
		var push := _get_push_direction(thruster)
		var torque := (thruster_position - center).cross(push * thruster.thrust_force)
		var is_active := thruster.current_strength > 0.0
		var lever_color := clockwise_color if torque > 0.0 else counterclockwise_color

		if not is_active:
			lever_color.a = 0.35

		draw_dashed_line(thruster_position - push * 12.0, thruster_position + push * line_length, line_color, 1.0, 6.0)

		var foot := thruster_position + push * (center - thruster_position).dot(push)
		draw_line(center, foot, lever_color, TEXEL if is_active else 1.0)
		draw_circle(foot, TEXEL, lever_color)

		if is_active:
			net_force += push * thruster.thrust_force * thruster.current_strength
			net_torque += torque * thruster.current_strength

	_draw_cross(ship_mass.hull_center_of_mass, empty_center_color, 5.0)
	_draw_cross(center, center_color, 8.0)

	if net_force.length() > 0.0:
		var tip := center + net_force * force_arrow_scale
		draw_line(center, tip, force_color, TEXEL)
		_draw_arrow_head(tip, net_force.normalized(), force_color)

	if absf(net_torque) > 0.0:
		var sweep := clampf(net_torque * turn_arc_scale, -PI * 1.5, PI * 1.5)
		var color := clockwise_color if net_torque > 0.0 else counterclockwise_color
		draw_arc(center, 18.0, -PI * 0.5, -PI * 0.5 + sweep, 24, color, TEXEL)
		var end := center + Vector2.from_angle(-PI * 0.5 + sweep) * 18.0
		_draw_arrow_head(end, Vector2.from_angle(-PI * 0.5 + sweep).orthogonal() * signf(sweep), color)


# One line per input: push (px/s²) and turn (°/s²) when that input alone is held.
# Clockwise is "cw": Godot's y axis points down, so a positive angle turns clockwise on screen.
func get_role_report() -> PackedStringArray:
	var lines := PackedStringArray()
	var inverse_inertia := _get_inverse_inertia()
	var center := ship.center_of_mass

	for role in report_roles:
		var force := Vector2.ZERO
		var torque := 0.0

		for thruster in _get_thrusters():
			if not thruster.roles.has(role):
				continue

			var push := _get_push_direction(thruster) * thruster.thrust_force
			force += push
			torque += (ship.to_local(thruster.global_position) - center).cross(push)

		var acceleration := force.length() / ship.mass
		var turn := rad_to_deg(torque * inverse_inertia)
		var turn_text := "no turn" if absf(turn) < 0.5 else "turns %.0f°/s² %s" % [absf(turn), "cw" if turn > 0.0 else "ccw"]
		lines.append("%-12s %4.0f px/s²  %s" % [ROLE_NAMES.get(role, role), acceleration, turn_text])

	return lines


func _get_thrusters() -> Array[Thruster]:
	var found: Array[Thruster] = []

	for child in thrusters.get_children():
		if child is Thruster:
			found.append(child)

	return found


# In the ship's space. A thruster pushes along its -x (its exhaust goes along +x).
func _get_push_direction(thruster: Thruster) -> Vector2:
	return ship.global_transform.basis_xform_inv(-thruster.global_transform.x).normalized()


func _get_inverse_inertia() -> float:
	var state := PhysicsServer2D.body_get_direct_state(ship.get_rid())
	return state.inverse_inertia if state != null else 0.0


func _draw_masses() -> void:
	if soft_points == null:
		return

	for module in soft_points.modules:
		if module == null:
			continue

		var at := ship.to_local(module.get_mass_center())
		draw_circle(at, 2.0 + sqrt(module.get_mass()) * 2.0, mass_color)


func _draw_cross(at: Vector2, color: Color, size: float) -> void:
	draw_line(at - Vector2(size, 0.0), at + Vector2(size, 0.0), color, TEXEL)
	draw_line(at - Vector2(0.0, size), at + Vector2(0.0, size), color, TEXEL)
	draw_arc(at, size * 0.6, 0.0, TAU, 16, color, 1.0)


func _draw_arrow_head(tip: Vector2, direction: Vector2, color: Color) -> void:
	var side := direction.orthogonal() * 4.0
	var back := tip - direction * 6.0
	draw_colored_polygon(PackedVector2Array([tip, back + side, back - side]), color)
