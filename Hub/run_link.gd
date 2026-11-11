class_name RunLink
extends Node

# Connects a run in the field (main.tscn) to the station (GameState).
# At the start: fits the ship with the player's loadout, picks the field's rocks and the pickup fee,
# and puts the ship back in the state it was left in (fuel, ammo, hull). At the end: reports the ore
# aboard on docking, or the loss.
#
# With no run started (main.tscn launched on its own, F6), this is a test run: full ship, the field
# set in the scene, and docking still takes the ore to the station.
# Keep this node first in the scene tree: its _ready() must run before the ship's and the field's,
# to set the ship's starting layouts and the field's profile before they read them.
# The ship (Player) is an instance of a hull scene. Only the Bucket for now: swapping hulls in the
# field comes with the ship yard.

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


func _ready() -> void:
	assert(ship_rooms != null and hardpoints != null and ship_damage != null and dispatch != null, "RunLink: assign the ship's nodes and the dispatch in the inspector")

	if GameState.is_run_active or use_loadout_in_test_runs:
		_fit_ship()

	if GameState.is_run_active:
		var destination := GameState.get_run_field()

		if field != null and destination.profile != null:
			field.profile = destination.profile
			field.world_seed = destination.world_seed + GameState.run_count

		dispatch.call_fee = GameState.get_pickup_fee()
		_apply_condition.call_deferred()

	dispatch.fee_charged.connect(_on_fee_charged)
	dispatch.returned_to_hub.connect(_on_docked)
	ship_damage.destroyed.connect(_on_destroyed)


# The ship isn't ready yet (it comes after this node): its systems will install what the loadout says.
func _fit_ship() -> void:
	var ship := ship_rooms.get_parent()

	if GameState.loadout.hull_id != &"bucket":
		push_warning("RunLink: the field only has the Bucket for now, not %s" % GameState.loadout.hull_id)
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
