class_name Guild
extends RefCounted

# The mining guild's side of the game state: the contract board, the player's contracts and how
# many they have completed. Kept and saved by GameState, which handles the money and the ore.
#
# The board shows OFFER_COUNT offers and is drawn again after every run. The player can hold
# MAX_ACTIVE contracts and drop any of them, at no cost. Offers get bigger with the guild rank (GameState.get_guild_rank()).
# Balance numbers are in EconomyConfig (Guild group).

const OFFER_COUNT: int = 3
const MAX_ACTIVE: int = 2

# Ores asked for at each rank: rarer ores come with a better rank.
const ORES_BY_TIER: Dictionary[int, Array] = {
	1: [CellMaterials.Id.WATER_ICE, CellMaterials.Id.NICKEL_IRON, CellMaterials.Id.COBALT],
	2: [CellMaterials.Id.NICKEL_IRON, CellMaterials.Id.COBALT, CellMaterials.Id.GOLD],
	3: [CellMaterials.Id.COBALT, CellMaterials.Id.GOLD, CellMaterials.Id.PLATINUM],
}

# How often each type comes up on the board.
const TYPE_WEIGHTS: Dictionary[Contract.Type, float] = {
	Contract.Type.DELIVERY: 3.0,
	Contract.Type.RUSH_DELIVERY: 1.0,
	Contract.Type.SPEED_TRIAL: 1.0,
	Contract.Type.SURVEY: 1.0,
	Contract.Type.SPECIMEN_TOW: 1.0,
	Contract.Type.CLAIM_MARKERS: 1.0,
}

var offers: Array[Contract] = []
var active: Array[Contract] = []
var completed_count: int = 0

var _rng := RandomNumberGenerator.new()


func _init() -> void:
	_rng.randomize()


# --- Board


func refresh_offers(rank: int) -> void:
	offers.clear()
	var used: Array[Contract.Type] = []

	for i in OFFER_COUNT:
		var type := _pick_type(used)
		used.append(type)
		offers.append(make_contract(type, rank))


func can_accept() -> bool:
	return active.size() < MAX_ACTIVE


func accept(offer_index: int) -> bool:
	if not can_accept() or offer_index < 0 or offer_index >= offers.size():
		return false

	var contract := offers[offer_index]
	offers.remove_at(offer_index)

	if contract.type == Contract.Type.RUSH_DELIVERY:
		contract.runs_left = 1

	active.append(contract)
	return true


func drop(contract: Contract) -> void:
	active.erase(contract)


func get_field_contracts() -> Array[Contract]:
	var out: Array[Contract] = []

	for contract in active:
		if not contract.is_delivery():
			out.append(contract)

	return out


# --- Runs


# Field contracts count one run at a time.
func begin_run() -> void:
	for contract in get_field_contracts():
		contract.progress = 0.0


# Called when a run ends. On docking, deliveries take what they need from `ore` (it is changed in
# place: what's left goes to the station). Done contracts are paid, rush deliveries run out, and
# the board is drawn again. Returns { "paid": [{ title, goal, reward }], "expired": [title], "total": int }.
func settle_run(ore: Dictionary[int, float], docked: bool, rank: int) -> Dictionary:
	var paid: Array[Dictionary] = []
	var expired: Array[String] = []
	var total := 0

	for contract in active.duplicate():
		if docked and contract.is_delivery():
			var taken := hand_in(contract, ore.get(contract.ore_id, 0.0))
			ore[contract.ore_id] = ore.get(contract.ore_id, 0.0) - taken

		if docked and contract.is_done():
			total += _complete(contract, paid)
			continue

		if contract.runs_left > 0:
			contract.runs_left -= 1

			if contract.runs_left == 0:
				expired.append(contract.get_title())
				active.erase(contract)
				continue

		if not contract.is_delivery():
			contract.progress = 0.0

	refresh_offers(rank)
	return { "paid": paid, "expired": expired, "total": total }


# Gives a delivery up to `available` units. Returns what it took. A rush delivery only takes the
# whole amount at once.
func hand_in(contract: Contract, available: float) -> float:
	var needed := contract.target - contract.progress

	if needed <= 0.0 or available < GameState.DUST:
		return 0.0

	if contract.type == Contract.Type.RUSH_DELIVERY and available < needed - GameState.DUST:
		return 0.0

	var taken := minf(available, needed)
	contract.progress += taken
	return taken


# Pays a done contract from the station (a delivery handed in from storage). Returns the reward.
func complete_now(contract: Contract) -> int:
	if not contract.is_done():
		return 0

	var paid: Array[Dictionary] = []
	return _complete(contract, paid)


func _complete(contract: Contract, paid: Array[Dictionary]) -> int:
	active.erase(contract)
	completed_count += 1
	paid.append({ "title": contract.get_title(), "goal": contract.get_goal_text(), "reward": contract.reward })
	return contract.reward


# --- Making contracts


func make_contract(type: Contract.Type, rank: int) -> Contract:
	var economy := GameState.ECONOMY
	var tier := clampi(rank, 1, 3)
	var contract := Contract.new()
	contract.type = type

	match type:
		Contract.Type.DELIVERY, Contract.Type.RUSH_DELIVERY:
			var ores: Array = ORES_BY_TIER[tier]
			contract.ore_id = ores[_rng.randi_range(0, ores.size() - 1)]
			var price := GameState.get_base_price(contract.ore_id)
			var value := economy.delivery_value_per_tier * pow(tier, 1.3) * _rng.randf_range(0.8, 1.25)
			var is_rush := type == Contract.Type.RUSH_DELIVERY
			var units := value / price * (economy.rush_amount_ratio if is_rush else 1.0)
			contract.target = clampf(snappedf(units, 5.0), 10.0, economy.max_delivery_units)
			var premium := economy.rush_premium if is_rush else economy.delivery_premium
			contract.reward = _round_reward(contract.target * price * premium)
		Contract.Type.SPEED_TRIAL:
			contract.target = economy.speed_trial_base + economy.speed_trial_per_tier * tier + 25.0 * _rng.randi_range(0, 2)
			contract.reward = _round_reward(economy.speed_trial_reward_per_ms * contract.target * tier)
		Contract.Type.SURVEY:
			contract.target = _rng.randi_range(3, 5)
			contract.min_cells = 150 * tier
			contract.reward = _round_reward(contract.target * economy.survey_reward_per_rock * tier)
		Contract.Type.SPECIMEN_TOW:
			var cells_by_tier: Array[Vector2i] = [Vector2i(150, 250), Vector2i(300, 450), Vector2i(500, 800)]
			var cells := cells_by_tier[tier - 1]
			contract.target = snappedf(_rng.randi_range(cells.x, cells.y), 10.0)
			contract.reward = _round_reward(contract.target * economy.tow_reward_per_cell + 300.0 * tier)
		Contract.Type.CLAIM_MARKERS:
			contract.target = _rng.randi_range(2, 3)
			contract.reward = _round_reward(contract.target * economy.claim_reward_per_beacon * tier)

	return contract


# A type not on the board yet, by weight.
func _pick_type(used: Array[Contract.Type]) -> Contract.Type:
	var total := 0.0

	for type in TYPE_WEIGHTS:
		if not used.has(type):
			total += TYPE_WEIGHTS[type]

	var roll := _rng.randf() * total

	for type in TYPE_WEIGHTS:
		if used.has(type):
			continue

		roll -= TYPE_WEIGHTS[type]

		if roll <= 0.0:
			return type

	return Contract.Type.DELIVERY


func _round_reward(amount: float) -> int:
	return maxi(50, roundi(amount / 50.0) * 50)


# --- Saving


func to_dict() -> Dictionary:
	return {
		"offers": offers.map(func(contract: Contract) -> Dictionary: return contract.to_dict()),
		"active": active.map(func(contract: Contract) -> Dictionary: return contract.to_dict()),
		"completed_count": completed_count,
	}


static func from_dict(data: Dictionary) -> Guild:
	var guild := Guild.new()
	guild.completed_count = int(data.get("completed_count", 0))

	for contract_data in data.get("offers", []):
		guild.offers.append(Contract.from_dict(contract_data))

	for contract_data in data.get("active", []):
		guild.active.append(Contract.from_dict(contract_data))

	return guild
