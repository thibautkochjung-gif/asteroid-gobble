class_name EconomyConfig
extends Resource

# Every number of the economy, in one place. The first draft comes from the "Economy balance" sheet
# on the Drive (01 Game design): keep the two in step when tuning.
# Ore base prices are the materials' own `value` (Asteroids/Materials/*.tres), so the scanner's
# estimates and the market agree.

@export var starting_credits: int = 1500

@export_group("Market")
## Units of an ore the market absorbs before its price has dropped by price_drop_per_depth.
## Keys are CellMaterials.Id values: 2 water ice, 3 nickel-iron, 4 cobalt, 5 gold, 6 platinum.
@export var market_depth: Dictionary[int, float] = {}
@export_range(0.0, 1.0) var price_drop_per_depth: float = 0.5 # Selling one full depth takes this share off the base price
@export_range(0.0, 1.0) var price_floor: float = 0.4 # Selling never pushes a price below this share of what the market pays
@export_range(0.0, 1.0) var price_recovery_per_run: float = 0.35 # Share of the sales pressure undone after each run
## How much each ore's market moves on its own after a run (standard deviation of the log step).
## Rare ores are jumpier. Ores missing here use 0.06.
@export var market_volatility: Dictionary[int, float] = { 2: 0.04, 3: 0.05, 4: 0.07, 5: 0.09, 6: 0.12 }
@export_range(0.0, 1.0) var market_reversion: float = 0.2 # Share of the gap to the base level closed each run, outside swings
@export var market_level_limits: Vector2 = Vector2(0.3, 3.0) # The market level never leaves this range
@export_range(0.0, 1.0) var swing_chance_per_run: float = 0.1 # Chance per ore and per run that a surge or slump starts
@export var surge_targets: Vector2 = Vector2(1.25, 2.2) # Level a surge heads for: mild (x) to wild (y). Mild is more common
@export var slump_targets: Vector2 = Vector2(0.8, 0.45) # Same for slumps
@export var swing_pull: Vector2 = Vector2(0.15, 0.4) # Share of the gap to the target closed per run, on average
@export var swing_runs: Vector2i = Vector2i(2, 7) # How many runs a swing lasts. Hidden from the player
@export_range(0.0, 1.0) var rumour_chance: float = 0.6 # Chance that a swing starts with a rumour at the exchange

@export_group("Services")
@export var fuel_price: float = 2.0 # Credits per fuel unit
@export var ammo_price: float = 3.0 # Credits per round
@export var pickup_fee_multiplier: float = 1.5 # Pickup call fee = the run's drop fee × this
@export_range(0.0, 1.0) var repair_cost_ratio: float = 0.3 # Repairing a fully broken hull costs this share of its value
@export_range(0.0, 1.0) var repair_reminder_threshold: float = 0.7 # The undock screen warns below this hull ratio

@export_group("Ship")
@export var hulls: Array[HullDefinition] = []
@export var starting_hull: StringName = &"bucket"

@export_group("Modules")
## Module prices, keyed by type (Room.Type, HardpointWeapon.Type, SoftPoint.Type values; computers
## by their model's Type).
## A room's price is for a slot of room_reference_area and scales with the slot's area: rooms take
## the size of their slot.
@export var room_prices: Dictionary[int, int] = {}
@export var room_reference_area: float = 3840.0 # px². The Bucket's middle slot (64x60)
@export var hardpoint_prices: Dictionary[int, int] = {}
@export var soft_point_prices: Dictionary[int, int] = {}
@export var computer_prices: Dictionary[int, int] = {} # ComputerModule.Type values
@export_range(0.0, 1.0) var sell_back_rate: float = 0.8 # Share of the price paid back for a module in perfect condition

@export_group("Guild")
## Completed contracts needed for each guild rank, indexed by rank (0 and 1 unused: rank I from the
## start). The rank sets how big the offers are (the "tier" below).
@export var rank_contracts: Array[int] = [0, 0, 3, 8]
@export var delivery_value_per_tier: float = 600.0 # Market value of the ore a delivery asks for, at tier I (grows as tier^1.3)
@export var delivery_premium: float = 1.6 # A delivery pays its ore's base value × this
@export var rush_premium: float = 2.4
@export_range(0.1, 1.0) var rush_amount_ratio: float = 0.6 # Rush deliveries ask for less
@export var max_delivery_units: float = 160.0 # A full ore bin on the Bucket is 189
@export var speed_trial_base: float = 200.0 # m/s. Target = base + per_tier × tier, plus 0-50
@export var speed_trial_per_tier: float = 100.0
@export var speed_trial_reward_per_ms: float = 2.5 # × target × tier
@export var survey_reward_per_rock: float = 200.0 # × tier
@export var tow_reward_per_cell: float = 3.0 # Plus 300 × tier
@export var claim_reward_per_beacon: float = 350.0 # × tier

@export_group("Drops")
## The belt the mothership drops players in. Each run draws a new one from its seed (BeltRoute).
@export var belt: BeltSettings = preload("res://Asteroids/Belt/belt.tres")
## Line fare: what the mothership charges to carry you to a depth, before the transfer. Grows
## exponentially, from drop_fare_top at the station's lane to drop_fare_bottom at the belt's edge.
@export var drop_fare_top: float = 200.0
@export var drop_fare_bottom: float = 2000.0
@export var transfer_per_km: float = 0.08 # Drop fee = line fare × (1 + this × km between the route and the drop point)
@export var free_drop_max_fee: int = 300 # Broke and nothing to sell: drops up to this fee are free (uninsured)
@export var run_seed_base: int = 7919 # Run seeds are this + the run number: a new belt every run

@export_group("Run options")
@export var insurance_plans: Array[InsurancePlan] = []


func get_market_depth(ore_id: int) -> float:
	return market_depth.get(ore_id, 400.0)


func get_market_volatility(ore_id: int) -> float:
	return market_volatility.get(ore_id, 0.06)


func get_hull(id: StringName) -> HullDefinition:
	for hull in hulls:
		if hull.id == id:
			return hull

	return null
