class_name Market
extends RefCounted

# The commodities exchange's side of the game state: what each ore sells for, its price history and
# the rumours going around. Kept and saved by GameState, which handles the money and the ore.
#
# An ore's price is its base price (the material's `value`) × level × pressure.
# - level is the market itself. After each run it takes a random step (market_volatility) and is
#   pulled back toward 1. Now and then a swing starts: a hidden surge or slump with its own target,
#   pull and length. The level creeps toward the target, a random amount each run, then drifts back
#   once the swing is over. The player only sees prices and, sometimes, a rumour.
# - pressure is the player's own selling. It drops linearly with the units sold, never below
#   price_floor, and moves back toward 1 after each run.
# Nothing moves while the player is out: advance_run() is called once per run, on the way back.
#
# Swings are kept here in full (target, pull, runs left) so a market analyst hired later can read
# them and tell the player more.

const ECONOMY: EconomyConfig = preload("res://Economy/economy.tres")
const HISTORY_LENGTH: int = 40 # Runs of history kept per ore
const INVENTED_HISTORY: int = 20 # Runs of past prices made up for a new game
const WARM_UP_RUNS: int = 6 # Simulated before the invented history, so it doesn't start at the base price
const NEWS_LENGTH: int = 4

const SURGE_RUMOURS: Array[String] = [
	"A refinery up-ring is said to be short of %s.",
	"Dock talk: someone is buying %s and not asking the price.",
	"A shipyard contract needs %s, they say.",
	"Couriers are asking around for %s.",
]
const SLUMP_RUMOURS: Array[String] = [
	"Word is a big %s haul just came in from the outer belt.",
	"The dockhands say the warehouses are full of %s.",
	"Fewer buyers for %s lately.",
	"A trader dumped a hold of %s at the exchange this morning.",
]

var pressure: Dictionary[int, float] = {} # Ore id -> share left after the player's sales. Missing = 1
var levels: Dictionary[int, float] = {} # Ore id -> market level. Missing = 1
var swings: Dictionary[int, Dictionary] = {} # Ore id -> { target, pull, runs_left }
var history: Dictionary[int, Array] = {} # Ore id -> price factors, oldest first. The last one is today's
var news: Array[Dictionary] = [] # { run, text }, newest first

var _rng := RandomNumberGenerator.new()


func _init() -> void:
	_rng.randomize()


# A market for a new game, with a made-up past so the charts aren't empty.
static func create() -> Market:
	var market := Market.new()
	market.invent_history()
	return market


func invent_history() -> void:
	levels.clear()
	swings.clear()
	history.clear()

	for i in WARM_UP_RUNS + INVENTED_HISTORY:
		_step_levels(-1)

		if i >= WARM_UP_RUNS:
			_record()


# --- Prices


func get_level(ore_id: int) -> float:
	return levels.get(ore_id, 1.0)


func get_pressure(ore_id: int) -> float:
	return pressure.get(ore_id, 1.0)


# Share of the base price the ore sells for today.
func get_factor(ore_id: int) -> float:
	return get_level(ore_id) * get_pressure(ore_id)


# The factor at the end of the previous run, for trends. Today's if there's no history.
func get_previous_factor(ore_id: int) -> float:
	var points: Array = history.get(ore_id, [])

	if points.size() < 2:
		return get_factor(ore_id)

	return points[-2]


# Price factors, oldest first. The last one is today's.
func get_history(ore_id: int) -> Array:
	var points: Array = history.get(ore_id, [])
	return points.duplicate()


# What selling `units` would pay, and the pressure it would leave. Accounts for the price sliding
# down during the sale itself.
func get_sale_quote(ore_id: int, units: float) -> Dictionary:
	var base := CellMaterials.get_material(ore_id).value * get_level(ore_id)
	var start := get_pressure(ore_id)
	var slope := ECONOMY.price_drop_per_depth / ECONOMY.get_market_depth(ore_id) # Pressure lost per unit sold
	var floor_pressure := minf(ECONOMY.price_floor, start)
	var units_to_floor := (start - floor_pressure) / slope if slope > 0.0 else INF
	var revenue := 0.0
	var end := start

	if units <= units_to_floor:
		end = start - slope * units
		revenue = base * units * (start + end) * 0.5
	else:
		end = floor_pressure
		revenue = base * units_to_floor * (start + end) * 0.5 + base * (units - units_to_floor) * floor_pressure

	return { "revenue": roundi(revenue), "pressure_after": end }


# Returns the credits the sale pays. Today's point in the history follows the price down.
func sell(ore_id: int, units: float) -> int:
	var quote := get_sale_quote(ore_id, units)
	pressure[ore_id] = quote.pressure_after
	var points: Array = history.get(ore_id, [])

	if points.is_empty():
		points.append(get_factor(ore_id))
	else:
		points[-1] = get_factor(ore_id)

	history[ore_id] = points
	return quote.revenue


# --- Between runs


# Called once per run, when the player gets back. `run` is the run's number, for the news.
func advance_run(run: int) -> void:
	for ore_id in pressure.keys():
		pressure[ore_id] += (1.0 - pressure[ore_id]) * ECONOMY.price_recovery_per_run

		if absf(1.0 - pressure[ore_id]) < 0.005:
			pressure.erase(ore_id)

	_step_levels(run)
	_record()


# One run's worth of market moves. `run` < 0 means a made-up past: no news.
func _step_levels(run: int) -> void:
	for ore_id in CellMaterials.ORES:
		var level := get_level(ore_id)
		var swing: Dictionary = swings.get(ore_id, {})

		if swing.is_empty() and _rng.randf() < ECONOMY.swing_chance_per_run:
			swing = _start_swing(ore_id, run)

		if swing.is_empty():
			level += (1.0 - level) * ECONOMY.market_reversion
		else:
			# The pull changes every run, so two runs of a swing don't tell where it's heading
			level += (swing.target - level) * swing.pull * _rng.randf_range(0.4, 1.6)
			swing.runs_left -= 1

			if swing.runs_left <= 0:
				swings.erase(ore_id)

		level *= exp(_rng.randfn(0.0, ECONOMY.get_market_volatility(ore_id)))
		levels[ore_id] = clampf(level, ECONOMY.market_level_limits.x, ECONOMY.market_level_limits.y)


func _start_swing(ore_id: int, run: int) -> Dictionary:
	var is_surge := _rng.randf() < 0.5
	var targets := ECONOMY.surge_targets if is_surge else ECONOMY.slump_targets
	# Mild swings are more common than wild ones
	var swing := {
		"target": lerpf(targets.x, targets.y, pow(_rng.randf(), 1.6)),
		"pull": _rng.randf_range(ECONOMY.swing_pull.x, ECONOMY.swing_pull.y),
		"runs_left": _rng.randi_range(ECONOMY.swing_runs.x, ECONOMY.swing_runs.y),
	}
	swings[ore_id] = swing

	if run >= 0 and _rng.randf() < ECONOMY.rumour_chance:
		var rumours := SURGE_RUMOURS if is_surge else SLUMP_RUMOURS
		var ore_name := CellMaterials.get_material(ore_id).display_name.to_lower()
		_add_news(run, rumours[_rng.randi() % rumours.size()] % ore_name)

	return swing


func _record() -> void:
	for ore_id in CellMaterials.ORES:
		var points: Array = history.get(ore_id, [])
		points.append(get_factor(ore_id))

		if points.size() > HISTORY_LENGTH:
			points.pop_front()

		history[ore_id] = points


func _add_news(run: int, text: String) -> void:
	news.push_front({ "run": run, "text": text })

	if news.size() > NEWS_LENGTH:
		news.resize(NEWS_LENGTH)


# --- Saving


func to_dict() -> Dictionary:
	var swing_data := {}

	for ore_id in swings:
		swing_data[str(ore_id)] = swings[ore_id]

	var history_data := {}

	for ore_id in history:
		history_data[str(ore_id)] = history[ore_id]

	return {
		"pressure": _floats_out(pressure),
		"levels": _floats_out(levels),
		"swings": swing_data,
		"history": history_data,
		"news": news,
	}


static func from_dict(data: Dictionary) -> Market:
	var market := Market.new()
	market.pressure = _floats_in(data.get("pressure", {}))
	market.levels = _floats_in(data.get("levels", {}))

	var swing_data: Dictionary = data.get("swings", {})

	for key in swing_data:
		var swing: Dictionary = swing_data[key]
		market.swings[int(key)] = { "target": float(swing.target), "pull": float(swing.pull), "runs_left": int(swing.runs_left) }

	var history_data: Dictionary = data.get("history", {})

	for key in history_data:
		market.history[int(key)] = Array(history_data[key]).map(func(point: Variant) -> float: return float(point))

	for item in data.get("news", []):
		market.news.append({ "run": int(item.run), "text": str(item.text) })

	if market.history.is_empty():
		market.invent_history()

	return market


# JSON keys are strings: ore ids go out as "4" and come back as 4.
static func _floats_out(source: Dictionary[int, float]) -> Dictionary:
	var out := {}

	for key in source:
		out[str(key)] = source[key]

	return out


static func _floats_in(source: Dictionary) -> Dictionary[int, float]:
	var out: Dictionary[int, float] = {}

	for key in source:
		out[int(key)] = float(source[key])

	return out
