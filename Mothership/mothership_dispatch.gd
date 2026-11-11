class_name MothershipDispatch
extends Node

# The mothership service. Drops the player off at the start of a run, sends a mothership back for
# the pickup when the player calls (C), and says when the player is back at the hub.
#
# Drop-off: the player starts in a random slot, lined up with it and facing aft, moving at the
# train's speed. The clamps release and push the ship out sideways (drop_off_push); from there the
# main engine brakes it.
#
# Pickup: a train appears min_distance..max_distance from the player, already moving, and
# heading at most max_heading_angle away from "straight away from the player": it never comes
# closer on its own, so waiting doesn't work. It's placed off screen when possible, so it doesn't
# pop in. Missed it? Call again, pay again.
#
# Each call emits fee_charged: RunLink passes the fee on to GameState. fees_paid keeps the total.

signal message(text: String) # For the cockpit terminal
signal returned_to_hub
signal fee_charged(amount: int)

const MOTHERSHIP_SCENE: PackedScene = preload("res://Mothership/mothership.tscn")

@export var ship: RigidBody2D
@export var ship_damage: ShipDamage # Optional: no pickup for a wreck
@export var call_action: StringName = &"call_mothership"
@export var call_fee: int = 500 # Credits per call
@export var speed: float = 80.0 # px/s
@export var drop_off_heading: float = -90.0 # Degrees. Where the mothership travels at the drop-off. -90 = up the screen
@export var drop_off_push: float = 40.0 # px/s. The clamps push the ship sideways out of its slot at this speed

@export_group("Pickup")
@export var min_distance: float = 6250.0 # px from the player to where the train appears (was 25000)
@export var max_distance: float = 12500.0 # (was 50000)
@export_range(0.0, 180.0) var max_heading_angle: float = 90.0 # Degrees. 90 = may pass sideways, never heads toward the player
@export var wait_time: float = 600.0 # s before it leaves
@export var spawn_tries: int = 30 # Random spots tried to find one off screen

var fees_paid: int = 0
var is_home: bool = false

var _pickup: Mothership


func _ready() -> void:
	assert(ship != null, "MothershipDispatch: assign the ship in the inspector")

	_drop_off.call_deferred()


func _process(_delta: float) -> void:
	if Input.is_action_just_pressed(call_action):
		_call_pickup()


func _drop_off() -> void:
	var heading := Vector2.from_angle(deg_to_rad(drop_off_heading))
	var mothership := _make(heading, false)
	mothership.state = Mothership.State.CARRYING
	mothership.player_left_bay.connect(_on_player_left_bay)

	# The ship is where it is in the scene: the train is placed around it, slot on the ship.
	mothership.position = ship.global_position - mothership.get_player_slot_transform().origin.rotated(heading.angle())
	_add(mothership)

	var ship_transform := Transform2D(heading.angle() + PI, ship.global_position)
	ship.global_transform = ship_transform
	PhysicsServer2D.body_set_state(ship.get_rid(), PhysicsServer2D.BODY_STATE_TRANSFORM, ship_transform)
	var outward := Vector2.from_angle(heading.angle() + mothership.get_player_exit_angle())
	ship.linear_velocity = mothership.cruise_velocity + outward * drop_off_push
	ship.angular_velocity = 0.0

	message.emit("Dispatch: drop-off, slot %02d. Clamps released" % mothership.player_slot.number)


func _call_pickup() -> void:
	if is_home or ship.freeze:
		return

	if ship_damage != null and ship_damage.is_destroyed:
		return

	if is_instance_valid(_pickup):
		message.emit("Dispatch: mothership already on its way")
		return

	var spot := _pick_spot()
	_pickup = _make(spot.heading, true)
	_pickup.position = spot.position
	_add(_pickup)
	fees_paid += call_fee
	fee_charged.emit(call_fee)

	var distance := ship.global_position.distance_to(_pickup.get_marker_position())
	message.emit("Dispatch: pickup -%d cr. Slot %02d, %d km out" % [call_fee, _pickup.player_slot.number, roundi(distance / 1000.0)])


# Where the pickup appears and where it heads. Takes the first spot off screen, or the last tried.
func _pick_spot() -> Dictionary:
	var spot := {}

	for i in spawn_tries:
		var out := Vector2.from_angle(randf() * TAU)
		var turn := deg_to_rad(randf_range(-max_heading_angle, max_heading_angle))
		spot = { "position": ship.global_position + out * randf_range(min_distance, max_distance), "heading": out.rotated(turn) }

		if not Mothership.is_visible_from(ship.get_viewport(), spot.position):
			break

	return spot


# A train, laid out but not in the tree yet: the caller places it, then calls _add().
func _make(heading: Vector2, can_pick_up: bool) -> Mothership:
	var mothership: Mothership = MOTHERSHIP_SCENE.instantiate()
	mothership.rotation = heading.angle()
	mothership.ship = ship
	mothership.cruise_velocity = heading * speed
	mothership.can_pick_up = can_pick_up
	mothership.wait_time = wait_time
	mothership.build()
	mothership.message.connect(message.emit)
	mothership.docked.connect(_on_docked)
	mothership.departed.connect(_on_departed.bind(mothership))
	return mothership


# Placed before it enters the tree: moved afterwards, an AnimatableBody2D sweeps from where it was
# to the new spot in one physics step, and shoves everything on the way. The scene's root sits at
# the origin, so the position set before is the global one.
func _add(mothership: Mothership) -> void:
	# After the background in the tree: drawn over it, under the rocks and the ship (z_index -1).
	ship.get_parent().add_child(mothership)


func _on_player_left_bay() -> void:
	message.emit("Dispatch: good hunting. %s: call pickup (%d cr)" % [Cockpit.get_key_text(call_action), call_fee])


func _on_docked() -> void:
	is_home = true
	message.emit("Docked. Heading back to the hub")
	returned_to_hub.emit()


func _on_departed(mothership: Mothership) -> void:
	if mothership != _pickup or is_home:
		return

	_pickup = null
	message.emit("Dispatch: you missed it. %s: call again (%d cr)" % [Cockpit.get_key_text(call_action), call_fee])
