extends Node

# Everything that outlives a scene: money, ore stored at the station, market prices, the ship's
# loadout and spare modules, the run in progress and the ship's condition between runs.
# Autoload "GameState".
#
# Flow: the hub (Hub/hub.tscn) calls start_run(), which pays the fees and loads the field
# (main.tscn). There, RunLink reports back with end_run_docked() or end_run_lost(), which bring the
# player back to the hub with a run report.
# Saved to user://save.json each time the player gets back to the station and after each purchase.
#
# Prices live in `market` (Economy/market.gd): random drift, hidden surges and slumps, the player's
# own sales, and the price history. They move once per run, when the player gets back, and don't
# move while the player is out, so they can plan around them.

signal credits_changed
signal storage_changed
signal prices_changed
signal loadout_changed
signal guild_changed

enum Kind { ROOM, HARDPOINT, SOFT_POINT, COMPUTER }

const ECONOMY: EconomyConfig = preload("res://Economy/economy.tres")
const SAVE_PATH: String = "user://save.json"
const SAVE_VERSION: int = 4 # 3: ore bins and grinder triage. 4: several ships. Older saves start a new game
const HUB_SCENE: String = "res://Hub/hub.tscn"
const FIELD_SCENE: String = "res://main.tscn"
const DUST: float = 0.001 # Units below this count as none

var credits: int = 0
var storage: Dictionary[int, float] = {} # CellMaterials.Id -> units at the station
var market := Market.create() # Prices and their history. Saved under "market"
var run_count: int = 0

# The player's ships, and the one they fly. Modules taken off go to `spares`, shared by all ships
# (rooms don't: they're sold back, see fit()).
var ships: Array[ShipLoadout] = []
var active_ship: int = 0
var spares: Dictionary[String, int] = {} # "kind:type" (see _spare_key) -> count
var guild := Guild.new() # Contracts. Saved under "guild"; saves without it get a fresh board

var loadout: ShipLoadout:
	get:
		return ships[active_ship]

# The active ship's condition between runs, kept on its ShipLoadout. What's missing is bought back
# on the undock screen.
var fuel_missing: float:
	get:
		return loadout.fuel_missing
	set(value):
		loadout.fuel_missing = value
var ammo_missing: int:
	get:
		return loadout.ammo_missing
	set(value):
		loadout.ammo_missing = value
var hull_ratio: float:
	get:
		return loadout.hull_ratio
	set(value):
		loadout.hull_ratio = value

# The run in progress. A run started from the field scene alone (F6) is a test run: not active.
var is_run_active: bool = false
var run_drop: DropQuote # Where the mothership dropped the player, and what it cost
var run_seed: int = 0 # The run's belt: route, richness and rocks
var run_insurance_index: int = 0
var run_fees: int = 0 # Paid at undock: drop fee, premium, refit

# Shown once by the hub when the player arrives, then cleared. Not saved.
var last_report: Dictionary = {}

var _hull_layouts: Dictionary[StringName, Dictionary] = {}
var _route: BeltRoute # The next run's, cached: see get_next_route()
var _route_seed: int = 0


func _ready() -> void:
	if not load_game():
		_back_up_save()
		new_game()


func new_game() -> void:
	credits = ECONOMY.starting_credits
	storage.clear()
	market = Market.create()
	run_count = 0
	ships = [make_ship(ECONOMY.starting_hull, true)]
	active_ship = 0
	spares.clear()
	guild = Guild.new()
	guild.refresh_offers(get_guild_rank())
	is_run_active = false
	save_game()
	credits_changed.emit()
	storage_changed.emit()
	prices_changed.emit()
	loadout_changed.emit()


# --- Money


func can_afford(amount: int) -> bool:
	return credits >= amount


# Takes the money even if the player can't afford it: a pickup must always be possible.
# Credits can go below zero, and the next sale pays the debt back first.
func charge(amount: int) -> void:
	credits -= amount
	credits_changed.emit()


func earn(amount: int) -> void:
	credits += amount
	credits_changed.emit()


# --- Market


func get_base_price(ore_id: int) -> float:
	return CellMaterials.get_material(ore_id).value


func get_price_factor(ore_id: int) -> float:
	return market.get_factor(ore_id)


# Prices at the end of each past run, in credits per unit, oldest first. The last one is today's.
func get_price_history(ore_id: int) -> Array[float]:
	var base := get_base_price(ore_id)
	var prices: Array[float] = []

	for factor in market.get_history(ore_id):
		prices.append(base * factor)

	return prices


func get_previous_price(ore_id: int) -> float:
	return get_base_price(ore_id) * market.get_previous_factor(ore_id)


func get_price(ore_id: int) -> float:
	return get_base_price(ore_id) * get_price_factor(ore_id)


func get_stored(ore_id: int) -> float:
	return storage.get(ore_id, 0.0)


func get_storage_value() -> int:
	var total := 0

	for ore_id in storage:
		total += get_sale_quote(ore_id, storage[ore_id]).revenue

	return total


# What selling `units` would pay. Accounts for the price sliding down during the sale itself.
func get_sale_quote(ore_id: int, units: float) -> Dictionary:
	return market.get_sale_quote(ore_id, units)


# Returns the credits earned.
func sell(ore_id: int, units: float) -> int:
	units = minf(units, get_stored(ore_id))

	if units <= DUST:
		return 0

	var revenue := market.sell(ore_id, units)
	storage[ore_id] -= units

	if storage[ore_id] <= DUST:
		storage.erase(ore_id)

	earn(revenue)
	save_game()
	storage_changed.emit()
	prices_changed.emit()
	return revenue


func sell_all() -> int:
	var total := 0

	for ore_id in storage.keys():
		total += sell(ore_id, storage[ore_id])

	return total


func _advance_market() -> void:
	market.advance_run(run_count)
	prices_changed.emit()


# --- Ship services


func get_insured_value(plan: InsurancePlan) -> int:
	var value := get_hull().price

	if plan.covers_modules:
		value += get_fitted_value()

	return value


func get_premium(plan_index: int) -> int:
	var plan := ECONOMY.insurance_plans[plan_index]
	return roundi(get_insured_value(plan) * plan.premium_ratio)


func get_refit_cost() -> int:
	return ceili(fuel_missing * ECONOMY.fuel_price + ammo_missing * ECONOMY.ammo_price)


func get_repair_cost() -> int:
	return ceili(get_hull().price * (1.0 - hull_ratio) * ECONOMY.repair_cost_ratio)


func needs_repair() -> bool:
	return hull_ratio < ECONOMY.repair_reminder_threshold


# Returns false if the player can't pay.
func repair_hull() -> bool:
	var cost := get_repair_cost()

	if cost <= 0 or not can_afford(cost):
		return false

	# Hull first: charge() emits credits_changed, and the screens refresh on it
	hull_ratio = 1.0
	charge(cost)
	save_game()
	return true


func get_pickup_fee() -> int:
	return roundi(run_drop.fee * ECONOMY.pickup_fee_multiplier) if run_drop != null else 0


# --- Ship and modules


func get_hull() -> HullDefinition:
	return ECONOMY.get_hull(loadout.hull_id)


# Slot sizes and counts of a hull, read once from its scene.
func get_hull_layout(hull_id: StringName = &"") -> Dictionary:
	if hull_id == &"":
		hull_id = loadout.hull_id

	if not _hull_layouts.has(hull_id):
		var ship := ECONOMY.get_hull(hull_id).get_scene().instantiate()
		var sizes: Array[Vector2] = []
		var fixed: Array[bool] = []
		var starting_rooms: Array[int] = []
		starting_rooms.assign(ship.get_node("Rooms").starting_layout)

		for child in ship.get_node("Rooms").get_children():
			if child is RoomSlot:
				sizes.append((child as RoomSlot).size)
				fixed.append((child as RoomSlot).fixed)

		var hardpoint_count := ship.get_node("Hardpoints").get_children().filter(func(n: Node) -> bool: return n is Node2D).size()
		var soft_point_count := ship.get_node("SoftPoints").get_children().filter(func(n: Node) -> bool: return n is SoftPointMount).size()
		_hull_layouts[hull_id] = { "room_sizes": sizes, "fixed_rooms": fixed, "starting_rooms": starting_rooms, "hardpoint_count": hardpoint_count, "soft_point_count": soft_point_count }
		ship.free()

	return _hull_layouts[hull_id]


# True if the slot holds a module that comes with the hull (the Commuter's computer, the Harvester's
# smelter): the mechanic can't swap it or sell it.
func is_slot_fixed(kind: Kind, slot_index: int) -> bool:
	if kind == Kind.COMPUTER:
		return get_hull().integrated_computer

	if kind == Kind.ROOM:
		return get_hull_layout().fixed_rooms[slot_index]

	return false


func get_slots(kind: Kind) -> Array[int]:
	match kind:
		Kind.ROOM:
			return loadout.rooms
		Kind.HARDPOINT:
			return loadout.hardpoints
		Kind.COMPUTER:
			return loadout.computers

	return loadout.soft_points


# Room prices scale with the slot's area. slot_index is only used for rooms.
func get_module_price(kind: Kind, type: int, slot_index: int = 0) -> int:
	match kind:
		Kind.ROOM:
			var size: Vector2 = get_hull_layout().room_sizes[slot_index]
			return roundi(ECONOMY.room_prices.get(type, 0) * size.x * size.y / ECONOMY.room_reference_area)
		Kind.HARDPOINT:
			return ECONOMY.hardpoint_prices.get(type, 0)
		Kind.COMPUTER:
			return ECONOMY.computer_prices.get(type, 0)

	return ECONOMY.soft_point_prices.get(type, 0)


# Modules are always in perfect condition for now (part damage isn't kept between runs), so this is
# the full sell-back rate. It will drop with wear once parts keep their damage.
func get_module_sell_price(kind: Kind, type: int, slot_index: int = 0) -> int:
	return roundi(get_module_price(kind, type, slot_index) * ECONOMY.sell_back_rate)


func get_fitted_value() -> int:
	var total := 0

	for kind in [Kind.ROOM, Kind.HARDPOINT, Kind.SOFT_POINT, Kind.COMPUTER]:
		var slots := get_slots(kind)

		for i in slots.size():
			if slots[i] != ShipLoadout.EMPTY:
				total += get_module_price(kind, slots[i], i)

	return total


func get_spare_count(kind: Kind, type: int) -> int:
	return spares.get(_spare_key(kind, type), 0)


# What fit() would cost (negative: the player gets money back).
# Rooms: the new one is bought for this slot, the old one is sold back.
# Other modules: taken from the spares if there's one, else bought. The old one goes to the spares.
func get_fit_cost(kind: Kind, slot_index: int, type: int) -> int:
	var current: int = get_slots(kind)[slot_index]

	if current == type:
		return 0

	if kind == Kind.ROOM:
		var cost := get_module_price(kind, type, slot_index) if type != ShipLoadout.EMPTY else 0

		if current != ShipLoadout.EMPTY:
			cost -= get_module_sell_price(kind, current, slot_index)

		return cost

	if type == ShipLoadout.EMPTY or get_spare_count(kind, type) > 0:
		return 0

	return get_module_price(kind, type)


# Puts `type` in the slot (ShipLoadout.EMPTY clears it). Returns false if the player can't pay.
func fit(kind: Kind, slot_index: int, type: int) -> bool:
	var slots := get_slots(kind)
	var current: int = slots[slot_index]

	if current == type:
		return true

	if kind == Kind.COMPUTER and type == ShipLoadout.EMPTY: # A ship always has a computer
		return false

	if is_slot_fixed(kind, slot_index):
		return false

	var cost := get_fit_cost(kind, slot_index, type)

	if cost > 0 and not can_afford(cost):
		return false

	if cost > 0:
		charge(cost)
	elif cost < 0:
		earn(-cost)

	if kind != Kind.ROOM:
		if current != ShipLoadout.EMPTY:
			_add_spare(kind, current, 1)

		if type != ShipLoadout.EMPTY and get_spare_count(kind, type) > 0:
			_add_spare(kind, type, -1)

	slots[slot_index] = type
	save_game()
	loadout_changed.emit()
	return true


func sell_spare(kind: Kind, type: int) -> void:
	if get_spare_count(kind, type) <= 0:
		return

	_add_spare(kind, type, -1)
	earn(get_module_sell_price(kind, type))
	save_game()
	loadout_changed.emit()


static func get_type_name(kind: Kind, type: int) -> String:
	match kind:
		Kind.ROOM:
			return Room.TYPE_NAMES.get(type, "?")
		Kind.HARDPOINT:
			return HardpointWeapon.TYPE_NAMES.get(type, "?")
		Kind.COMPUTER:
			return ComputerModule.load_type(type).display_name

	return SoftPoint.TYPE_NAMES.get(type, "?")


# Every type of that kind, by number. Not always 0 to n - 1: a removed type leaves a gap (SoftPoint.Type).
static func get_types(kind: Kind) -> Array:
	match kind:
		Kind.ROOM:
			return Room.Type.values()
		Kind.HARDPOINT:
			return HardpointWeapon.Type.values()
		Kind.COMPUTER:
			return ComputerModule.Type.values()

	return SoftPoint.Type.values()


func _spare_key(kind: Kind, type: int) -> String:
	return "%d:%d" % [kind, type]


# False for modules that no longer exist (the capacitor pack, the generators): saves can still have them.
func _is_known_spare(key: String) -> bool:
	var parts := key.split(":")

	if parts.size() != 2 or not Kind.values().has(int(parts[0])):
		return false

	return get_types(int(parts[0]) as Kind).has(int(parts[1]))


func _add_spare(kind: Kind, type: int, amount: int) -> void:
	var key := _spare_key(kind, type)
	spares[key] = spares.get(key, 0) + amount

	if spares[key] <= 0:
		spares.erase(key)


# The grinder's triage (ship menu): CellMaterials.Id the grinder throws out. Saved right away.
func set_discarded_materials(materials: Array[int]) -> void:
	loadout.discarded.assign(materials)
	save_game()


# A module's settings from the ship menu (see ShipLoadout.module_settings). Saved right away.
func set_module_settings(key: String, settings: Dictionary) -> void:
	loadout.module_settings[key] = settings.duplicate(true)
	save_game()


# --- Shipyard


# A new ship of this hull. `with_fit`: the modules its scene comes with; otherwise only its rooms
# (the shipyard sells hulls with their rooms, the rest is for the mechanic).
func make_ship(hull_id: StringName, with_fit: bool) -> ShipLoadout:
	var hull := ECONOMY.get_hull(hull_id)
	var ship := ShipLoadout.from_hull_scene(hull.id, hull.get_scene())

	if not with_fit:
		ship.hardpoints.fill(ShipLoadout.EMPTY)
		ship.soft_points.fill(ShipLoadout.EMPTY)

	return ship


func buy_hull(hull_id: StringName) -> bool:
	var hull := ECONOMY.get_hull(hull_id)

	if hull == null or not can_afford(hull.price):
		return false

	charge(hull.price)
	ships.append(make_ship(hull_id, false))
	save_game()
	loadout_changed.emit()
	return true


# Makes another ship the one the player flies. `move_modules`: the hardpoints and soft points of
# the current ship go to the new one, slot by slot in order; what doesn't fit goes to the spares.
# Rooms stay with their hull (they're the size of its slots).
func switch_ship(index: int, move_modules: bool) -> void:
	if index == active_ship or index < 0 or index >= ships.size():
		return

	var old_ship := loadout
	active_ship = index

	if move_modules:
		_move_modules(old_ship.hardpoints, loadout.hardpoints, Kind.HARDPOINT)
		_move_modules(old_ship.soft_points, loadout.soft_points, Kind.SOFT_POINT)

	save_game()
	loadout_changed.emit()


func _move_modules(from: Array[int], to: Array[int], kind: Kind) -> void:
	for i in from.size():
		if from[i] == ShipLoadout.EMPTY:
			continue

		var free := to.find(ShipLoadout.EMPTY)

		if free >= 0:
			to[free] = from[i]
		else:
			_add_spare(kind, from[i], 1)

		from[i] = ShipLoadout.EMPTY


# --- Runs


# The next run's belt: drawn from its seed, so the undock map and the field agree.
func get_next_run_seed() -> int:
	return ECONOMY.run_seed_base + run_count + 1


func get_next_route() -> BeltRoute:
	var seed_value := get_next_run_seed()

	if _route == null or _route_seed != seed_value:
		_route = BeltRoute.create(ECONOMY.belt, seed_value)
		_route_seed = seed_value

	return _route


# What leaving costs, all in.
func get_undock_cost(drop: DropQuote, plan_index: int, refit: bool) -> int:
	var cost := drop.fee + get_premium(plan_index)

	if refit:
		cost += get_refit_cost()

	return cost


# The station never strands anyone: a player who can't pay for a short drop, with nothing left to
# sell, gets one for free (drops up to free_drop_max_fee), uninsured.
func is_broke() -> bool:
	return credits < ECONOMY.free_drop_max_fee and storage.is_empty()


func is_free_drop(drop: DropQuote, plan_index: int) -> bool:
	return is_broke() and plan_index == 0 and drop.fee <= ECONOMY.free_drop_max_fee


# Pays and loads the field. Returns false if the player can't pay (the scene doesn't change).
func start_run(drop: DropQuote, plan_index: int, refit: bool) -> bool:
	var cost := get_undock_cost(drop, plan_index, refit)

	if is_free_drop(drop, plan_index):
		cost = get_refit_cost() if refit and can_afford(get_refit_cost()) else 0
		refit = cost > 0
	elif not can_afford(cost):
		return false

	charge(cost)

	if refit:
		fuel_missing = 0.0
		ammo_missing = 0

	is_run_active = true
	run_seed = get_next_run_seed()
	run_drop = drop
	run_insurance_index = plan_index
	run_fees = cost
	run_count += 1
	guild.begin_run()
	save_game()
	var field: Node = load(FIELD_SCENE).instantiate()
	FieldShip.swap(field, get_hull().get_scene())
	get_tree().change_scene_to_node(field)
	return true


# For the run report.
func get_run_place_text() -> String:
	if not is_run_active or run_drop == null:
		return "Test run"

	return "Drop at %d km into the belt" % roundi(run_drop.depth)


# The ship docked with the mothership. `ore` maps CellMaterials.Id to units (cargo and unsmelted
# chunks alike: smelting only compacts ore).
func end_run_docked(ore: Dictionary[int, float], fuel_left_missing: float, ammo_left_missing: int, hull_left: float, pickup_fees: int) -> void:
	var delivered := ore.duplicate()
	var contracts := guild.settle_run(ore, true, get_guild_rank()) # Deliveries take their ore out of `ore`

	for ore_id in delivered:
		delivered[ore_id] -= ore.get(ore_id, 0.0)

	if contracts.total > 0:
		earn(contracts.total)

	for ore_id in ore:
		if ore[ore_id] > DUST:
			storage[ore_id] = get_stored(ore_id) + ore[ore_id]

	fuel_missing = fuel_left_missing
	ammo_missing = ammo_left_missing
	hull_ratio = hull_left
	last_report = {
		"outcome": "docked",
		"field": get_run_place_text(),
		"ore": ore,
		"fees": run_fees + pickup_fees,
		"hull": hull_left,
		"delivered": delivered,
		"contracts": contracts,
	}
	_finish_run()


# The ship was destroyed. Cargo is lost. Until the shipyard exists, the Union hands out a
# replacement Bucket, so the only cost is what was in the hold and the insurance outcome.
func end_run_lost(pickup_fees: int) -> void:
	var payout := 0

	if is_run_active:
		var plan := ECONOMY.insurance_plans[run_insurance_index]
		payout = roundi(get_insured_value(plan) * plan.payout_ratio)
		earn(payout)

	# The ship is gone, with its modules. If it was the last one, the Union lends a Bucket with its
	# basic fit, so the player can keep working.
	var no_ore: Dictionary[int, float] = {}
	var contracts := guild.settle_run(no_ore, false, get_guild_rank()) # Field progress is lost with the ship
	var lost_hull := get_hull().display_name
	ships.remove_at(active_ship)
	active_ship = 0
	var is_replaced := ships.is_empty()

	if is_replaced:
		ships.append(make_ship(ECONOMY.starting_hull, true))

	last_report = {
		"outcome": "lost",
		"ship": lost_hull,
		"replaced": is_replaced,
		"field": get_run_place_text(),
		"fees": run_fees + pickup_fees,
		"payout": payout,
		"contracts": contracts,
	}
	_finish_run()


func _finish_run() -> void:
	is_run_active = false
	run_fees = 0
	_advance_market()
	save_game()
	storage_changed.emit()
	get_tree().change_scene_to_file(HUB_SCENE)


# --- Mining guild


func accept_contract(offer_index: int) -> bool:
	if not guild.accept(offer_index):
		return false

	save_game()
	guild_changed.emit()
	return true


func drop_contract(contract: Contract) -> void:
	guild.drop(contract)
	save_game()
	guild_changed.emit()


# Hands ore from the station's storage to a delivery. Pays at once if that completes it.
func hand_in_from_storage(contract: Contract) -> void:
	var taken := guild.hand_in(contract, get_stored(contract.ore_id))

	if taken <= 0.0:
		return

	storage[contract.ore_id] = get_stored(contract.ore_id) - taken
	var reward := guild.complete_now(contract)

	if reward > 0:
		earn(reward)

	save_game()
	storage_changed.emit()
	guild_changed.emit()


# The guild's rank goes up on its own with completed contracts. It sets the size of the offers.
func get_guild_rank() -> int:
	var rank := 1

	for i in range(2, ECONOMY.rank_contracts.size()):
		if guild.completed_count >= ECONOMY.rank_contracts[i]:
			rank = i

	return rank


# { rank, contracts } for the next rank, or {} at the top.
func get_next_rank() -> Dictionary:
	var rank := get_guild_rank() + 1

	if rank >= ECONOMY.rank_contracts.size():
		return {}

	return { "rank": rank, "contracts": ECONOMY.rank_contracts[rank] }


# --- Saving


func save_game() -> void:
	var data := {
		"version": SAVE_VERSION,
		"credits": credits,
		"storage": _ids_to_strings(storage),
		"market": market.to_dict(),
		"run_count": run_count,
		"ships": ships.map(func(ship: ShipLoadout) -> Dictionary: return ship.to_dict()),
		"active_ship": active_ship,
		"spares": spares,
		"guild": guild.to_dict(),
	}
	var file := FileAccess.open(SAVE_PATH, FileAccess.WRITE)

	if file == null:
		push_warning("GameState: can't write %s" % SAVE_PATH)
		return

	file.store_string(JSON.stringify(data, "\t"))


# Returns false if there's no usable save.
func load_game() -> bool:
	if not FileAccess.file_exists(SAVE_PATH):
		return false

	var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(SAVE_PATH))

	if not data is Dictionary:
		return false

	if data.get("version", 0) == 3:
		data = _migrate_from_3(data)

	if data.get("version", 0) != SAVE_VERSION:
		return false

	credits = int(data.credits)
	storage = _strings_to_ids(data.storage)
	if data.has("market"):
		market = Market.from_dict(data.market)
	else:
		market = Market.create() # Saves from before the market moved on its own
		market.pressure = _strings_to_ids(data.get("price_factors", {}))
		save_game.call_deferred() # Keep the made-up past, or it changes at every launch
	run_count = int(data.run_count)
	ships.clear()

	for ship_data in data.ships:
		ships.append(ShipLoadout.from_dict(ship_data))

	if ships.is_empty():
		return false

	active_ship = clampi(int(data.active_ship), 0, ships.size() - 1)
	spares.clear()

	for key in data.spares:
		if _is_known_spare(key):
			spares[key] = int(data.spares[key])

	for ship in ships:
		if ECONOMY.get_hull(ship.hull_id) == null:
			return false

	if _fit_ships_to_hulls():
		save_game.call_deferred() # Keep the spares that came off removed slots

	if data.has("guild"):
		guild = Guild.from_dict(data.guild)
	else:
		guild = Guild.new()
		guild.refresh_offers(get_guild_rank())

	return true


# A hull scene may have gained or lost slots since the save was written (the Commuter went from four
# hardpoints to two). Each saved ship is fitted to its hull's slots as they are now: missing slots
# are added empty, extra ones are removed and their modules go to the spares. Rooms on removed slots
# are dropped: a room takes the size of its slot. True if any ship changed.
func _fit_ships_to_hulls() -> bool:
	var changed := false

	for ship in ships:
		var layout := get_hull_layout(ship.hull_id)
		var counts := [layout.room_sizes.size(), layout.hardpoint_count, layout.soft_point_count]
		var before := [ship.rooms.size(), ship.hardpoints.size(), ship.soft_points.size()]

		if before != counts:
			ship.rooms = _fit_slots(ship.rooms, counts[0], Kind.ROOM)
			ship.hardpoints = _fit_slots(ship.hardpoints, counts[1], Kind.HARDPOINT)
			ship.soft_points = _fit_slots(ship.soft_points, counts[2], Kind.SOFT_POINT)
			changed = true

		if _fit_fixed_rooms(ship, layout):
			changed = true

	return changed


# A room built into the hull is always the one the hull scene comes with, even if the save says
# otherwise (the Harvester's smelter became a flash smelter).
func _fit_fixed_rooms(ship: ShipLoadout, layout: Dictionary) -> bool:
	var changed := false
	var fixed: Array[bool] = layout.fixed_rooms
	var starting_rooms: Array[int] = layout.starting_rooms

	for i in mini(ship.rooms.size(), fixed.size()):
		if not fixed[i] or i >= starting_rooms.size():
			continue

		if ship.rooms[i] != starting_rooms[i]:
			ship.rooms[i] = starting_rooms[i]
			changed = true

	return changed


func _fit_slots(slots: Array[int], count: int, kind: Kind) -> Array[int]:
	var fitted: Array[int] = []

	for i in maxi(slots.size(), count):
		var type: int = slots[i] if i < slots.size() else ShipLoadout.EMPTY

		if i < count:
			fitted.append(type)
		elif type != ShipLoadout.EMPTY and kind != Kind.ROOM:
			_add_spare(kind, type, 1)

	return fitted


# Version 3 had one ship ("loadout") and its condition at the top level.
func _migrate_from_3(data: Dictionary) -> Dictionary:
	var ship: Dictionary = data.loadout
	ship.hull_ratio = data.get("hull_ratio", 1.0)
	ship.fuel_missing = data.get("fuel_missing", 0.0)
	ship.ammo_missing = data.get("ammo_missing", 0)
	data.ships = [ship]
	data.active_ship = 0
	data.version = 4
	return data


# A save that can't be loaded is kept aside (save.json.bak) before a new game writes over it.
func _back_up_save() -> void:
	if FileAccess.file_exists(SAVE_PATH):
		DirAccess.copy_absolute(ProjectSettings.globalize_path(SAVE_PATH), ProjectSettings.globalize_path(SAVE_PATH + ".bak"))


# JSON keys are strings: ore ids go out as "4" and come back as 4.
func _ids_to_strings(source: Dictionary[int, float]) -> Dictionary:
	var out := {}

	for key in source:
		out[str(key)] = source[key]

	return out


func _strings_to_ids(source: Dictionary) -> Dictionary[int, float]:
	var out: Dictionary[int, float] = {}

	for key in source:
		out[int(key)] = float(source[key])

	return out
