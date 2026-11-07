class_name SoftPoint
extends Node2D

# Base class for every soft point: a utility module bolted on the outside of the hull.
# ShipSoftPoints adds it under a mount, then calls attach(). The module's space is the mount's:
# +x points outward, away from the hull. Everything is drawn in code, on 2 px texels.
#
# Physical, like any other part of the ship:
# - Its footprint (a rectangle in mount space) becomes a collision shape on the ship's body.
#   Rocks bump into it, and you scrape it when you scrape a rock.
# - Its mass counts at its own position (ShipMass asks ShipSoftPoints), so a heavy module on one
#   side moves the centre of mass, and the thrusters then turn the ship differently.
# - A hard enough hit on the footprint tears it off (ShipSoftPoints). It floats away as a
#   ModuleProp, with whatever it held, and goes back on an empty mount when you touch it gently.
#
# Input, one key per mount (ShipSoftPoints sets use_action):
# - a quick tap calls _on_tap();
# - holding the key past hold_time calls _on_hold_started() once, _on_holding() every frame
#   while it's held, and _on_hold_ended() on release.
# Holding jettisons the module by default, if can_jettison. Modules with a better use for the
# hold (detonate, reel in) override _on_hold_started().
# Holding show_aim_preview (mouse 4 or left Alt) makes every loaded launcher draw where a tap
# would send its shot. See "Aim preview" below.
#
# Hooks the ship's systems call through ShipSoftPoints: fuel (drop tank), power (capacitor),
# restocking at the station, and taking back props that come home (racks).

enum Type { DROP_TANK, TETHER, BEACON_RACK, HARPOON, CHARGE_RACK, MAGNETIC_CLAMP, BALLAST, CAPACITOR, PROBE_RACK, FLARE_RACK, CACHE_BUOY, CARGO_CANISTER } # New types go at the end: scenes store them as numbers

const TYPE_NAMES := {
	Type.DROP_TANK: "Drop tank",
	Type.TETHER: "Tether",
	Type.BEACON_RACK: "Beacon rack",
	Type.HARPOON: "Harpoon winch",
	Type.CHARGE_RACK: "Demolition charges",
	Type.MAGNETIC_CLAMP: "Magnetic clamp",
	Type.BALLAST: "Ballast pod",
	Type.CAPACITOR: "Capacitor pack",
	Type.PROBE_RACK: "Survey probes",
	Type.FLARE_RACK: "Flares",
	Type.CACHE_BUOY: "Cache buoy",
	Type.CARGO_CANISTER: "Cargo canister",
}

const TEXEL: float = 2.0
const AIM_ACTION: StringName = &"show_aim_preview"
const AIM_DASH: float = 6.0 # px

@export var footprint: Rect2 = Rect2(0, -8, 8, 16) # Mount space, px. x >= 0 is outside the hull
@export var dry_mass: float = 1.0 # Without its load (fuel, items...)
@export var break_impulse: float = 1500.0 # mass * px/s. A hit on this module that jolts the ship this hard tears it off
@export var can_jettison: bool = false # Holding the key throws the whole module away
@export var hold_time: float = 0.35 # s. Shorter is a tap
@export var jettison_speed: float = 20.0 # px/s outward, on top of the ship's own motion

@export_group("Aim preview")
@export var aim_color: Color = Color(0.85, 0.9, 1.0, 0.35) # Nothing on the path
@export var aim_hit_color: Color = Color(1.0, 0.8, 0.25, 0.9) # The shot would hit something

@export_group("Colors")
@export var outline_color: Color = Color(0.06, 0.055, 0.07)
@export var body_color: Color = Color(0.46, 0.44, 0.4)
@export var accent_color: Color = Color(0.83, 0.64, 0.16)
@export var light_on_color: Color = Color(0.4, 1.0, 0.5)
@export var light_off_color: Color = Color(0.2, 0.25, 0.22)

var soft_point_type: Type = Type.DROP_TANK # Set by ShipSoftPoints
var ship: RigidBody2D # Set by attach(). Null while the module floats loose
var soft_points: ShipSoftPoints
var mount: SoftPointMount
var use_action: StringName

var _shape_owner: int = -1
var _is_pressed: bool = false
var _is_holding: bool = false
var _press_time: float = 0.0
var _was_aiming: bool = false


func _process(delta: float) -> void:
	if ship == null or use_action.is_empty():
		return

	_read_input(delta)
	_update_aim_preview()


func _draw() -> void:
	_draw_module()

	if _is_aiming():
		_draw_aim_preview()


# --- Mounting


func attach(new_ship: RigidBody2D, new_soft_points: ShipSoftPoints, new_mount: SoftPointMount, action: StringName) -> void:
	ship = new_ship
	soft_points = new_soft_points
	mount = new_mount
	use_action = action
	_create_shape()
	_on_attached()
	queue_redraw()


# Before the module leaves its mount (jettisoned, torn off, swapped out).
func detach() -> void:
	if ship == null:
		return

	if _is_holding:
		_on_hold_ended()

	_on_detached()
	_remove_shape()
	_is_pressed = false
	_is_holding = false
	ship = null
	soft_points = null
	mount = null
	use_action = &""
	queue_redraw()


func is_attached() -> bool:
	return ship != null


func get_type_name() -> String:
	return TYPE_NAMES[soft_point_type]


# --- Mass


func get_mass() -> float:
	return dry_mass + _get_load_mass()


# Global position where the module's mass sits.
func get_mass_center() -> Vector2:
	return to_global(footprint.get_center())


# --- Text for the HUD


func get_status_text() -> String:
	return ""


# What tap and hold do right now, e.g. "tap: fire  hold: reel in".
func get_controls_text() -> String:
	return "hold: jettison" if can_jettison else ""


# --- Hooks for the ship's systems. Defaults: the module has none of these.


# Fuel the thrusters can burn. Returns how much was given.
func draw_fuel(_amount: float) -> float:
	return 0.0


func get_fuel() -> float:
	return 0.0


func get_fuel_capacity() -> float:
	return 0.0


# Power the ship's consumers can use. Returns how much was given.
func draw_power(_amount: float) -> float:
	return 0.0


# Surplus from the generator. Returns how much was taken.
func store_power(_amount: float) -> float:
	return 0.0


func get_power() -> float:
	return 0.0


func get_power_capacity() -> float:
	return 0.0


# Station service: refill, reload. Prototype: the pause menu's debug button.
func restock() -> void:
	pass


# Would this module take back this prop (a rack with room for it)?
func accepts_prop(_prop: SpaceProp) -> bool:
	return false


# Takes the prop back. The module frees it. Returns false if it couldn't.
func recover_prop(_prop: SpaceProp) -> bool:
	return false


# --- For the subclasses


func _on_attached() -> void:
	pass


# Let go of anything held, stop anything running: the module is leaving the ship.
func _on_detached() -> void:
	pass


func _on_tap() -> void:
	pass


func _on_hold_started() -> void:
	if can_jettison:
		soft_points.jettison(self)


func _on_holding(_delta: float) -> void:
	pass


func _on_hold_ended() -> void:
	pass


func _get_load_mass() -> float:
	return 0.0


func _draw_module() -> void:
	_draw_plate(footprint, body_color)


# Shows a short line on the HUD, tagged with the mount's key.
func say(text: String) -> void:
	if soft_points != null:
		soft_points.relay_message(self, text)


func get_outward() -> Vector2:
	return global_transform.x.normalized()


# Outer face of the module, middle. Where things leave from and where pads grip.
func get_tip() -> Vector2:
	return to_global(Vector2(footprint.end.x, footprint.get_center().y))


func get_ship_velocity_at(global_point: Vector2) -> Vector2:
	return SoftLink.velocity_at(ship, global_point)


# Where props go: the node the ship flies in.
func get_space() -> Node:
	return ship.get_parent()


# Returns the share of the needed power the ship could give, 0..1.
func draw_ship_power(amount: float) -> float:
	if soft_points == null or soft_points.generator == null or amount <= 0.0:
		return 1.0

	return soft_points.generator.draw_power(amount) / amount


# Puts a prop in space at a global point, moving with the ship there plus `push`.
# The ship gets the opposite push (Newton's third law), at the module.
func launch_prop(prop: SpaceProp, at: Vector2, push: Vector2) -> void:
	get_space().add_child(prop)
	prop.global_position = at
	prop.rotation = global_rotation
	prop.linear_velocity = get_ship_velocity_at(at) + push
	prop.angular_velocity = ship.angular_velocity
	ship.apply_impulse(-push * prop.mass, at - ship.global_position)
	soft_points.ignore_collisions_for(prop, 0.5)


# Outline, fill, a light edge, a dark edge: same plate as the hull.
func _draw_plate(rect: Rect2, color: Color) -> void:
	draw_rect(rect, outline_color)

	var inner := rect.grow(-TEXEL)

	if inner.size.x <= 0.0 or inner.size.y <= 0.0:
		return

	draw_rect(inner, color)
	draw_rect(Rect2(inner.position, Vector2(TEXEL, inner.size.y)), color.lightened(0.2))
	draw_rect(Rect2(inner.end.x - TEXEL, inner.position.y, TEXEL, inner.size.y), color.darkened(0.3))


func _draw_light(at: Vector2, is_on: bool) -> void:
	draw_rect(Rect2(at - Vector2(TEXEL, TEXEL), Vector2(TEXEL * 2.0, TEXEL * 2.0)), outline_color)
	draw_rect(Rect2(at - Vector2(TEXEL, TEXEL) * 0.5, Vector2(TEXEL, TEXEL)), light_on_color if is_on else light_off_color)


# A gauge across the module (along the hull), filled from one end. ratio 0..1.
func _draw_gauge(rect: Rect2, ratio: float, fill_color: Color, empty_color: Color) -> void:
	draw_rect(rect, outline_color)

	var inner := rect.grow(-TEXEL * 0.5)
	draw_rect(inner, empty_color)

	var length := snappedf(inner.size.y * clampf(ratio, 0.0, 1.0), TEXEL)
	draw_rect(Rect2(inner.position.x, inner.end.y - length, inner.size.x, length), fill_color)


# --- Aim preview
# While show_aim_preview is held, a launcher draws where a tap would send its shot: a dashed line
# along the real path (the ship's own motion and spin included), up to the first thing it would
# hit. Launchers override get_aim_speed(), and get_aim_range() / find_aim_hit() if needed.


# px/s outward that a tap would add to the ship's motion. 0: nothing to aim right now.
func get_aim_speed() -> float:
	return 0.0


# How far the preview reaches from the tip, in px.
func get_aim_range() -> float:
	return 160.0


# First thing on the segment a shot would hit: { "point": Vector2 }, or {} if none.
# By default, rock cells only.
func find_aim_hit(from: Vector2, to: Vector2) -> Dictionary:
	var hits := Asteroid.find_hits_on_ray(get_tree(), from, to, 1)

	if hits.is_empty():
		return {}

	var direction := (to - from).normalized()
	return { "point": from + direction * float(hits[0]["distance"]) }


# --- Internals


func _is_aiming() -> bool:
	return ship != null and Input.is_action_pressed(AIM_ACTION) and get_aim_speed() > 0.0


# Redraws every frame while aiming (the ship moves under the line), and once more when it stops.
func _update_aim_preview() -> void:
	var is_aiming := _is_aiming()

	if is_aiming or _was_aiming:
		queue_redraw()

	_was_aiming = is_aiming


# Same velocity as a real shot: the ship's velocity at the tip (spin included) plus the push.
func _draw_aim_preview() -> void:
	var from := get_tip()
	var velocity := get_ship_velocity_at(from) + get_outward() * get_aim_speed()
	var to := from + velocity.normalized() * get_aim_range()
	var hit := find_aim_hit(from, to)

	if hit.is_empty():
		draw_dashed_line(to_local(from), to_local(to), aim_color, TEXEL * 0.5, AIM_DASH)
		return

	var point := to_local(hit["point"])
	draw_dashed_line(to_local(from), point, aim_hit_color, TEXEL * 0.5, AIM_DASH)
	draw_rect(Rect2(point - Vector2(TEXEL, TEXEL) * 1.5, Vector2(TEXEL, TEXEL) * 3.0), aim_hit_color, false, TEXEL * 0.5)


func _read_input(delta: float) -> void:
	if Input.is_action_just_pressed(use_action):
		_is_pressed = true
		_is_holding = false
		_press_time = 0.0

	if not _is_pressed:
		return

	if Input.is_action_pressed(use_action):
		_press_time += delta

		if not _is_holding and _press_time >= hold_time:
			_is_holding = true
			_on_hold_started()

		# The hold may have jettisoned the module.
		if _is_holding and ship != null:
			_on_holding(delta)

		return

	_is_pressed = false

	if _is_holding:
		_is_holding = false
		_on_hold_ended()
	else:
		_on_tap()


# One rectangle on the ship's own body, so the module collides as part of the ship.
# Same technique as the robot arm's hitbox: a shape owner, no CollisionShape2D node.
func _create_shape() -> void:
	var shape := RectangleShape2D.new()
	shape.size = footprint.size
	_shape_owner = ship.create_shape_owner(self)
	ship.shape_owner_add_shape(_shape_owner, shape)
	ship.shape_owner_set_transform(_shape_owner, ship.global_transform.affine_inverse() * global_transform * Transform2D(0.0, footprint.get_center()))


func _remove_shape() -> void:
	if _shape_owner >= 0 and is_instance_valid(ship):
		ship.remove_shape_owner(_shape_owner)

	_shape_owner = -1
