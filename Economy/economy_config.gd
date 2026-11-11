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
@export_range(0.0, 1.0) var price_floor: float = 0.4 # Share of the base price. Prices never go lower
@export_range(0.0, 1.0) var price_recovery_per_run: float = 0.35 # Share of the gap to the base price closed after each run

@export_group("Services")
@export var fuel_price: float = 2.0 # Credits per fuel unit
@export var ammo_price: float = 3.0 # Credits per round
@export var pickup_fee_multiplier: float = 1.5 # Pickup call fee = the field's drop fee × this
@export_range(0.0, 1.0) var repair_cost_ratio: float = 0.3 # Repairing a fully broken hull costs this share of its value
@export_range(0.0, 1.0) var repair_reminder_threshold: float = 0.7 # The undock screen warns below this hull ratio

@export_group("Ship")
@export var hulls: Array[HullDefinition] = []
@export var starting_hull: StringName = &"bucket"

@export_group("Modules")
## Module prices, keyed by type (Room.Type, HardpointWeapon.Type, SoftPoint.Type values).
## A room's price is for a slot of room_reference_area and scales with the slot's area: rooms take
## the size of their slot.
@export var room_prices: Dictionary[int, int] = {}
@export var room_reference_area: float = 3840.0 # px². The Bucket's middle slot (64x60)
@export var hardpoint_prices: Dictionary[int, int] = {}
@export var soft_point_prices: Dictionary[int, int] = {}
@export_range(0.0, 1.0) var sell_back_rate: float = 0.8 # Share of the price paid back for a module in perfect condition

@export_group("Run options")
@export var fields: Array[FieldDestination] = []
@export var insurance_plans: Array[InsurancePlan] = []


func get_market_depth(ore_id: int) -> float:
	return market_depth.get(ore_id, 400.0)


func get_hull(id: StringName) -> HullDefinition:
	for hull in hulls:
		if hull.id == id:
			return hull

	return null
