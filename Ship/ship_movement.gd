extends Node
class_name ShipMovement

@export var thruster_group: Node2D
@export var fuel_source: ShipRooms # Optional: without it, thrusters never run dry
@export var drop_tanks: ShipSoftPoints # Optional: soft point drop tanks, burned before fuel_source
@export var computer: ShipComputer # Optional: flight computer (X kill momentum, F match speed, settling)

var thrusters: Array[Thruster] = []
var thrusters_by_role: Dictionary = {}


func _ready() -> void:
	for child in thruster_group.get_children():
		if child is Thruster:
			thrusters.append(child)

	for thruster in thrusters:
		for role in thruster.roles: # Looks up each role on a given thruster
			if not InputMap.has_action(role): # Catches role typos once, instead of erroring every frame
				push_warning("Thruster '%s' has role '%s', which is not an input action." % [thruster.name, role])
				continue

			if not thrusters_by_role.has(role): # Creates role in dictionary if first encounter
				thrusters_by_role[role] = []
			thrusters_by_role[role].append(thruster)
	print(thrusters_by_role)


func _physics_process(delta: float) -> void:
	for thruster in thrusters:
		thruster.reset_strength()

	var is_player_steering := false

	for role in thrusters_by_role:
		var strength := Input.get_action_strength(role)
		_request_role(role, strength)

		if strength > 0.0:
			is_player_steering = true

	if computer != null:
		computer.steer(thrusters, is_player_steering) # Never fights the player: steps back while they steer

	_limit_by_fuel(delta)

	for thruster in thrusters:
		thruster.apply_thrust()


func _request_role(role: StringName, strength: float) -> void:
	if strength <= 0.0:
		return

	for thruster in thrusters_by_role[role]:
		thruster.request_thrust(strength)


# Asks the tanks for this frame's fuel, drop tanks first. If they can't cover it, every thruster
# weakens by the same ratio (so a half-empty frame doesn't turn into a spin).
func _limit_by_fuel(delta: float) -> void:
	if fuel_source == null and drop_tanks == null:
		return

	var needed := 0.0

	for thruster in thrusters:
		needed += thruster.get_fuel_needed(delta)

	if needed <= 0.0:
		return

	var granted := 0.0

	if drop_tanks != null:
		granted += drop_tanks.draw_fuel(needed)

	if fuel_source != null and granted < needed:
		granted += fuel_source.draw_fuel(needed - granted)

	var ratio := granted / needed

	if ratio >= 1.0:
		return

	for thruster in thrusters:
		thruster.scale_strength(ratio)
