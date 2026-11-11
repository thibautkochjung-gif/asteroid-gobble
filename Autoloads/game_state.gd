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
# Prices: each ore has a price factor (1 = its base price, the material's `value`). Selling pushes
# the factor down, linearly with the units sold, never below the floor. After each run the factor
# moves back toward 1. Prices don't move while the player is out, so they can plan around them.

signal credits_changed
signal storage_changed
signal prices_changed
signal loadout_changed

enum Kind { ROOM, HARDPOINT, SOFT_POINT }

const ECONOMY: EconomyConfig = preload("res://Economy/economy.tres")
const SAVE_PATH: String = "user://save.json"
const SAVE_VERSION: int = 3 # 3: ore bins and grinder triage. Older saves start a new game
const HUB_SCENE: String = "res://Hub/hub.tscn"
const FIELD_SCENE: String = "res://main.tscn"
const DUST: float = 0.001 # Units below this count as none

var credits: int = 0
var storage: Dictionary[int, float] = {} # CellMaterials.Id -> units at the station
var price_factors: Dictionary[int, float] = {} # CellMaterials.Id -> share of the base price
var licence_tier: int = 1
var run_count: int = 0

# The ship. Modules taken off go to `spares` (rooms don't: they're sold back, see fit()).
var loadout: ShipLoadout
var spares: Dictionary[String, int] = {} # "kind:type" (see _spare_key) -> count

# Ship condition between runs. What's missing is bought back on the undock screen.
var fuel_missing: float = 0.0
var ammo_missing: int = 0
var hull_ratio: float = 1.0

# The run in progress. A run started from the field scene alone (F6) is a test run: not active.
var is_run_active: bool = false
var run_field_index: int = 0
var run_insurance_index: int = 0
var run_fees: int = 0 # Paid at undock: drop fee, premium, refit

# Shown once by the hub when the player arrives, then cleared. Not saved.
var last_report: Dictionary = {}

var _hull_layouts: Dictionary[StringName, Dictionary] = {}


func _ready() -> void:
	if not load_game():
		new_game()


func new_game() -> void:
	credits = ECONOMY.starting_credits
	storage.clear()
	price_factors.clear()
	licence_tier = 1
	run_count = 0
	var hull := ECONOMY.get_hull(ECONOMY.starting_hull)
	loadout = ShipLoadout.from_hull_scene(hull.id, hull.get_scene())
	spares.clear()
	fuel_missing = 0.0
	ammo_missing = 0
	hull_ratio = 1.0
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
	return price_factors.get(ore_id, 1.0)


func get_price(ore_id: int) -> float:
	return get_base_price(ore_id) * get_price_factor(ore_id)


func get_stored(ore_id: int) -> float:
	return storage.get(ore_id, 0.0)


func get_storage_value() -> int:
	var total := 0

	for ore_id in storage:
		total += get_sale_quote(ore_id, storage[ore_id]).revenue

	return total


# What selling `units` would pay, and the price factor it would leave. Accounts for the price
# sliding down during the sale itself.
func get_sale_quote(ore_id: int, units: float) -> Dictionary:
	var base := get_base_price(ore_id)
	var start := get_price_factor(ore_id)
	var slope := ECONOMY.price_drop_per_depth / ECONOMY.get_market_depth(ore_id) # Factor lost per unit sold
	var floor_factor := minf(ECONOMY.price_floor, start)
	var units_to_floor := (start - floor_factor) / slope if slope > 0.0 else INF
	var revenue := 0.0
	var end := start

	if units <= units_to_floor:
		end = start - slope * units
		revenue = base * units * (start + end) * 0.5
	else:
		end = floor_factor
		revenue = base * units_to_floor * (start + end) * 0.5 + base * (units - units_to_floor) * floor_factor

	return { "revenue": roundi(revenue), "factor_after": end }


# Returns the credits earned.
func sell(ore_id: int, units: float) -> int:
	units = minf(units, get_stored(ore_id))

	if units <= DUST:
		return 0

	var quote: Dictionary = get_sale_quote(ore_id, units)
	price_factors[ore_id] = quote.factor_after
	storage[ore_id] -= units

	if storage[ore_id] <= DUST:
		storage.erase(ore_id)

	earn(quote.revenue)
	save_game()
	storage_changed.emit()
	prices_changed.emit()
	return quote.revenue


func sell_all() -> int:
	var total := 0

	for ore_id in storage.keys():
		total += sell(ore_id, storage[ore_id])

	return total


func _recover_prices() -> void:
	for ore_id in price_factors.keys():
		price_factors[ore_id] += (1.0 - price_factors[ore_id]) * ECONOMY.price_recovery_per_run

		if absf(1.0 - price_factors[ore_id]) < 0.005:
			price_factors.erase(ore_id)

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
	return roundi(get_run_field().drop_fee * ECONOMY.pickup_fee_multiplier)


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

		for child in ship.get_node("Rooms").get_children():
			if child is RoomSlot:
				sizes.append((child as RoomSlot).size)

		_hull_layouts[hull_id] = { "room_sizes": sizes }
		ship.free()

	return _hull_layouts[hull_id]


func get_slots(kind: Kind) -> Array[int]:
	match kind:
		Kind.ROOM:
			return loadout.rooms
		Kind.HARDPOINT:
			return loadout.hardpoints

	return loadout.soft_points


# Room prices scale with the slot's area. slot_index is only used for rooms.
func get_module_price(kind: Kind, type: int, slot_index: int = 0) -> int:
	match kind:
		Kind.ROOM:
			var size: Vector2 = get_hull_layout().room_sizes[slot_index]
			return roundi(ECONOMY.room_prices.get(type, 0) * size.x * size.y / ECONOMY.room_reference_area)
		Kind.HARDPOINT:
			return ECONOMY.hardpoint_prices.get(type, 0)

	return ECONOMY.soft_point_prices.get(type, 0)


# Modules are always in perfect condition for now (part damage isn't kept between runs), so this is
# the full sell-back rate. It will drop with wear once parts keep their damage.
func get_module_sell_price(kind: Kind, type: int, slot_index: int = 0) -> int:
	return roundi(get_module_price(kind, type, slot_index) * ECONOMY.sell_back_rate)


func get_fitted_value() -> int:
	var total := 0

	for kind in [Kind.ROOM, Kind.HARDPOINT, Kind.SOFT_POINT]:
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

	return SoftPoint.TYPE_NAMES.get(type, "?")


static func get_type_count(kind: Kind) -> int:
	match kind:
		Kind.ROOM:
			return Room.Type.size()
		Kind.HARDPOINT:
			return HardpointWeapon.Type.size()

	return SoftPoint.Type.size()


func _spare_key(kind: Kind, type: int) -> String:
	return "%d:%d" % [kind, type]


func _add_spare(kind: Kind, type: int, amount: int) -> void:
	var key := _spare_key(kind, type)
	spares[key] = spares.get(key, 0) + amount

	if spares[key] <= 0:
		spares.erase(key)


# The grinder's triage (ship menu): CellMaterials.Id the grinder throws out. Saved right away.
func set_discarded_materials(materials: Array[int]) -> void:
	loadout.discarded.assign(materials)
	save_game()


# --- Runs


func get_run_field() -> FieldDestination:
	return ECONOMY.fields[run_field_index]


func is_field_open(field_index: int) -> bool:
	return ECONOMY.fields[field_index].licence_tier <= licence_tier


# What leaving costs, all in.
func get_undock_cost(field_index: int, plan_index: int, refit: bool) -> int:
	var cost := ECONOMY.fields[field_index].drop_fee + get_premium(plan_index)

	if refit:
		cost += get_refit_cost()

	return cost


# The station never strands anyone: a player who can't pay for the nearest field, with nothing
# left to sell, gets a free drop there, uninsured.
func can_get_free_drop() -> bool:
	return credits < ECONOMY.fields[0].drop_fee and storage.is_empty()


# Pays and loads the field. Returns false if the player can't pay (the scene doesn't change).
func start_run(field_index: int, plan_index: int, refit: bool) -> bool:
	if not is_field_open(field_index):
		return false

	var cost := get_undock_cost(field_index, plan_index, refit)
	var is_free_drop := field_index == 0 and plan_index == 0 and can_get_free_drop()

	if is_free_drop:
		cost = get_refit_cost() if refit and can_afford(get_refit_cost()) else 0
		refit = cost > 0
	elif not can_afford(cost):
		return false

	charge(cost)

	if refit:
		fuel_missing = 0.0
		ammo_missing = 0

	is_run_active = true
	run_field_index = field_index
	run_insurance_index = plan_index
	run_fees = cost
	run_count += 1
	save_game()
	get_tree().change_scene_to_file(FIELD_SCENE)
	return true


# The ship docked with the mothership. `ore` maps CellMaterials.Id to units (cargo and unsmelted
# chunks alike: smelting only compacts ore).
func end_run_docked(ore: Dictionary[int, float], fuel_left_missing: float, ammo_left_missing: int, hull_left: float, pickup_fees: int) -> void:
	for ore_id in ore:
		if ore[ore_id] > DUST:
			storage[ore_id] = get_stored(ore_id) + ore[ore_id]

	fuel_missing = fuel_left_missing
	ammo_missing = ammo_left_missing
	hull_ratio = hull_left
	last_report = {
		"outcome": "docked",
		"field": get_run_field().display_name if is_run_active else "Test run",
		"ore": ore,
		"fees": run_fees + pickup_fees,
		"hull": hull_left,
	}
	_finish_run()


# The ship was destroyed. Cargo is lost. Until the ship yard exists, the Union hands out a
# replacement Bucket, so the only cost is what was in the hold and the insurance outcome.
func end_run_lost(pickup_fees: int) -> void:
	var payout := 0

	if is_run_active:
		var plan := ECONOMY.insurance_plans[run_insurance_index]
		payout = roundi(get_insured_value(plan) * plan.payout_ratio)
		earn(payout)

	fuel_missing = 0.0
	ammo_missing = 0
	hull_ratio = 1.0
	last_report = {
		"outcome": "lost",
		"field": get_run_field().display_name if is_run_active else "Test run",
		"fees": run_fees + pickup_fees,
		"payout": payout,
	}
	_finish_run()


func _finish_run() -> void:
	is_run_active = false
	run_fees = 0
	_recover_prices()
	save_game()
	storage_changed.emit()
	get_tree().change_scene_to_file(HUB_SCENE)


# --- Saving


func save_game() -> void:
	var data := {
		"version": SAVE_VERSION,
		"credits": credits,
		"storage": _ids_to_strings(storage),
		"price_factors": _ids_to_strings(price_factors),
		"licence_tier": licence_tier,
		"run_count": run_count,
		"fuel_missing": fuel_missing,
		"ammo_missing": ammo_missing,
		"hull_ratio": hull_ratio,
		"loadout": loadout.to_dict(),
		"spares": spares,
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

	if not data is Dictionary or data.get("version", 0) != SAVE_VERSION:
		return false

	credits = int(data.credits)
	storage = _strings_to_ids(data.storage)
	price_factors = _strings_to_ids(data.price_factors)
	licence_tier = int(data.licence_tier)
	run_count = int(data.run_count)
	fuel_missing = float(data.fuel_missing)
	ammo_missing = int(data.ammo_missing)
	hull_ratio = float(data.hull_ratio)
	loadout = ShipLoadout.from_dict(data.loadout)
	spares.clear()

	for key in data.spares:
		spares[key] = int(data.spares[key])

	if ECONOMY.get_hull(loadout.hull_id) == null:
		return false

	return true


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
