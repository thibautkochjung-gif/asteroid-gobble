class_name ContractTracker
extends Node

# Follows the player's guild contracts during a run, and shows them in the cockpit (HudContracts).
# RunLink makes it and calls finish() on docking; GameState then pays what's done (Guild.settle_run).
#
# - Speed trial: the best speed this run.
# - Survey: rocks the ship's scanners have fully scanned this run, counted once each (field rocks only:
#   chunks of a rock already counted don't count again).
# - Specimen tow: the biggest uncut field rock within tow_range of the ship, right now.
# - Claim markers: beacons in space, each within claim_range of a different rock that holds ore, right now.
# - Deliveries: the ore aboard, for the readout only. They're handed in on docking.

signal message(text: String) # For the cockpit terminal. RunLink sends it through the dispatch

@export var update_interval: float = 0.25 # s between two checks of the slow contracts
@export var tow_range: float = 450.0 # px from the ship to a specimen's centre
@export var claim_range: float = 160.0 # px from a beacon to a rock's surface

var ship: RigidBody2D
var hardpoints: ShipHardpoints
var ship_rooms: ShipRooms

var _contracts: Array[Contract] = []
var _surveyed: Dictionary[int, bool] = {} # Field ids of the rocks counted for surveys
var _announced: Dictionary[Contract, bool] = {} # Field contracts already reported done this run
var _time_left: float = 0.0
var _hud: HudContracts


func setup(new_ship: RigidBody2D, new_hardpoints: ShipHardpoints, new_ship_rooms: ShipRooms) -> void:
	ship = new_ship
	hardpoints = new_hardpoints
	ship_rooms = new_ship_rooms


func _ready() -> void:
	_contracts = GameState.guild.active.duplicate()

	for contract in GameState.guild.get_field_contracts():
		contract.progress = 0.0 # Also done by Guild.begin_run(), but test runs (F6) don't call it

	var layer := CanvasLayer.new()
	layer.layer = 2 # Over the cockpit
	add_child(layer)
	_hud = HudContracts.new()
	_hud.contracts = _contracts
	layer.add_child(_hud)
	_hud.visible = not _contracts.is_empty()


func _physics_process(delta: float) -> void:
	if _contracts.is_empty() or ship == null:
		return

	var speed := ship.linear_velocity.length() # 1 px = 1 m (Cockpit.pixels_per_meter)

	for contract in _contracts:
		if contract.type == Contract.Type.SPEED_TRIAL:
			contract.progress = maxf(contract.progress, speed)

	_time_left -= delta

	if _time_left <= 0.0:
		_time_left = update_interval
		_update_slow_contracts()

	_announce_done()


# Last check before docking settles the run.
func finish() -> void:
	_update_slow_contracts()


func _update_slow_contracts() -> void:
	for contract in _contracts:
		match contract.type:
			Contract.Type.SURVEY:
				contract.progress = _count_surveyed(contract.min_cells)
			Contract.Type.SPECIMEN_TOW:
				contract.progress = _get_biggest_specimen()
			Contract.Type.CLAIM_MARKERS:
				contract.progress = _count_claims()
			Contract.Type.DELIVERY, Contract.Type.RUSH_DELIVERY:
				pass

	_hud.aboard = ship_rooms.get_ore_aboard() if ship_rooms != null else {}
	_hud.queue_redraw()


# Survey contracts can have different sizes: a rock counts for every contract it's big enough for.
func _count_surveyed(min_cells: int) -> int:
	for weapon in hardpoints.weapons:
		var scanner := weapon as Scanner

		if scanner == null:
			continue

		for rock in scanner.readout_rocks:
			if is_instance_valid(rock) and rock.field_id >= 0 and scanner.is_fully_scanned(rock):
				_surveyed[rock.field_id] = rock.cells.size() >= min_cells or _surveyed.get(rock.field_id, false)

	var count := 0

	for field_id in _surveyed:
		if _surveyed[field_id]:
			count += 1

	return count


func _get_biggest_specimen() -> int:
	var biggest := 0

	for rock in Asteroid.find_near(get_tree(), ship.global_position, tow_range):
		if rock.field_id >= 0 and not rock.was_cut:
			biggest = maxi(biggest, rock.cells.size())

	return biggest


func _count_claims() -> int:
	var claimed: Dictionary[Asteroid, bool] = {}

	for node in get_tree().get_nodes_in_group(SpaceProp.GROUP):
		var beacon := node as Beacon

		if beacon == null or not beacon.is_inside_tree():
			continue

		for rock in Asteroid.find_near(get_tree(), beacon.global_position, claim_range):
			if rock.has_ore_cells() and not claimed.has(rock):
				claimed[rock] = true
				break

	return claimed.size()


func _announce_done() -> void:
	for contract in _contracts:
		if contract.is_delivery() or _announced.has(contract):
			continue

		if contract.is_done() and (contract.type == Contract.Type.SPEED_TRIAL or contract.type == Contract.Type.SURVEY):
			_announced[contract] = true
			message.emit("Guild: %s done. Paid when you dock" % contract.get_title().to_lower())
