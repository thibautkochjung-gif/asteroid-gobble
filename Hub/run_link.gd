class_name RunLink
extends Node

# Connects a run in the field (main.tscn) to the station (GameState).
# At the start: fits the ship with the player's loadout, sets the field to the drop point (belt,
# seed), the drop heading and the pickup fee,
# and puts the ship back in the state it was left in (fuel, ammo, hull). At the end: reports the ore
# aboard on docking, or the loss.
#
# With no run started (main.tscn launched on its own, F6), this is a test run: full ship, the field
# set in the scene, and docking still takes the ore to the station.
# Keep this node first in the scene tree: its _ready() must run before the ship's and the field's,
# to set the ship's starting layouts and the field's belt before they read them.
# The ship (Player) is an instance of a hull scene, swapped for the player's hull before the scene
# starts (GameState.start_run(), FieldShip).

@export var ship_rooms: ShipRooms
@export var hardpoints: ShipHardpoints
@export var ship_damage: ShipDamage
@export var dispatch: MothershipDispatch
@export var field: AsteroidField
@export var use_loadout_in_test_runs: bool = true # false: F6 runs use the layout saved in the hull scene
@export var return_delay: float = 2.5 # s between docking and the station screen
@export var loss_delay: float = 4.0 # s to watch the wreck before the report

var _pickup_fees: int = 0
var _is_ending: bool = false
var _contracts: ContractTracker


func _ready() -> void:
	assert(ship_rooms != null and hardpoints != null and ship_damage != null and dispatch != null, "RunLink: assign the ship's nodes and the dispatch in the inspector")

	if GameState.is_run_active or use_loadout_in_test_runs:
		_fit_ship()

	if GameState.is_run_active:
		var drop := GameState.run_drop

		# The field's origin is the drop point: the belt around it sets the rocks (BeltSampler).
		# Its rocks come from the run seed and the drop point. The starter cluster is for test runs.
		if field != null:
			field.run_seed = GameState.run_seed
			field.drop_km = drop.point
			field.world_seed = hash([GameState.run_seed, roundi(drop.point.x * 10.0), roundi(drop.point.y * 10.0)])
			field.starter_cluster = null

		# The ship leaves the mothership where the route passed nearest: heading along that leg.
		dispatch.drop_off_heading = rad_to_deg(drop.hop.heading.angle())
		dispatch.call_fee = GameState.get_pickup_fee()
		_apply_condition.call_deferred()

	dispatch.fee_charged.connect(_on_fee_charged)
	dispatch.returned_to_hub.connect(_on_docked)
	ship_damage.destroyed.connect(_on_destroyed)

	# Guild contracts: followed during the run, settled by GameState when it ends.
	_contracts = ContractTracker.new()
	_contracts.setup(ship_rooms.get_parent() as RigidBody2D, hardpoints, ship_rooms)
	_contracts.message.connect(dispatch.message.emit) # Guild news comes over the dispatch radio
	add_child(_contracts)


# The ship isn't ready yet (it comes after this node): its systems will install what the loadout says.
func _fit_ship() -> void:
	var ship := ship_rooms.get_parent()

	# GameState.start_run() swapped in the right hull (FieldShip). A test run (F6) keeps the Bucket
	# from main.tscn: then only a Bucket loadout fits it.
	if ship.scene_file_path != GameState.get_hull().scene_path:
		push_warning("RunLink: test run with the scene's ship, not the %s" % GameState.get_hull().display_name)
		return

	GameState.loadout.apply(ship)


# Deferred: the rooms, weapons and hull fill themselves in their own _ready().
func _apply_condition() -> void:
	ship_rooms.draw_fuel(GameState.fuel_missing)
	hardpoints.draw_ammo(GameState.ammo_missing)
	ship_damage.hull = ship_damage.max_hull * GameState.hull_ratio
	ship_damage.hull_changed.emit()


func _on_fee_charged(amount: int) -> void:
	_pickup_fees += amount
	GameState.charge(amount)


func _on_docked() -> void:
	if _is_ending:
		return

	_is_ending = true
	_contracts.finish() # Specimens and claims count as they are at the moment of docking
	var ore := get_ore_aboard()
	var fuel_missing := ship_rooms.get_fuel_capacity() - ship_rooms.get_fuel()
	var ammo_missing := hardpoints.get_ammo_capacity() - hardpoints.get_ammo()
	var hull := ship_damage.get_hull_ratio()
	await get_tree().create_timer(return_delay).timeout
	GameState.end_run_docked(ore, fuel_missing, ammo_missing, hull, _pickup_fees)


func _on_destroyed() -> void:
	if _is_ending:
		return

	_is_ending = true
	await get_tree().create_timer(loss_delay).timeout
	GameState.end_run_lost(_pickup_fees)


# Ingots, raw cells in the ore bins, and what the chunks still in the smelters would give.
# Chunks waiting in the hold or held by the arm aren't counted yet.
func get_ore_aboard() -> Dictionary[int, float]:
	return ship_rooms.get_ore_aboard()
