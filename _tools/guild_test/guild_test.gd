extends Node

# Checks the guild rules without flying: makes contracts, settles fake runs, prints what happened.
# Run this scene (F6). It doesn't touch the save: it uses its own Guild, not GameState.guild.


func _ready() -> void:
	var guild := Guild.new()
	guild.refresh_offers(1)
	print("Offers: ", guild.offers.map(func(c: Contract) -> String: return "%s, %s, %d cr" % [c.get_title(), c.get_goal_text(), c.reward]))

	for tier in [1, 2, 3]:
		for type in Contract.TYPE_NAMES:
			var sample := guild.make_contract(type, tier)
			print("Tier %d  %s: %s -> %d cr" % [tier, sample.get_title(), sample.get_goal_text(), sample.reward])

	# A delivery, a rush delivery and a speed trial
	var delivery := guild.make_contract(Contract.Type.DELIVERY, 1)
	delivery.ore_id = CellMaterials.Id.COBALT
	delivery.target = 40.0
	var rush := guild.make_contract(Contract.Type.RUSH_DELIVERY, 1)
	rush.ore_id = CellMaterials.Id.COBALT
	rush.target = 30.0
	rush.runs_left = 1
	var speed := guild.make_contract(Contract.Type.SPEED_TRIAL, 1)
	guild.active.assign([delivery, rush])
	guild.begin_run()

	# Run 1: docked with 25 cobalt. The delivery takes 25 (partial), the rush can't be met and runs out
	var ore: Dictionary[int, float] = { CellMaterials.Id.COBALT: 25.0 }
	var result := guild.settle_run(ore, true, 1)
	_check(is_equal_approx(delivery.progress, 25.0), "partial delivery kept: %s" % delivery.progress)
	_check(ore[CellMaterials.Id.COBALT] < 0.01, "delivered ore leaves the hold")
	_check(result.expired.size() == 1 and not guild.active.has(rush), "rush delivery ran out")
	_check(result.total == 0, "nothing paid yet")

	# Run 2: speed trial done in the field, docked with 50 cobalt
	guild.active.append(speed)
	guild.begin_run()
	speed.progress = speed.target + 5.0
	ore = { CellMaterials.Id.COBALT: 50.0 }
	result = guild.settle_run(ore, true, 1)
	_check(result.total == delivery.reward + speed.reward, "delivery and speed trial paid: %d" % result.total)
	_check(is_equal_approx(ore[CellMaterials.Id.COBALT], 35.0), "only the 15 owed are taken: %s left" % ore[CellMaterials.Id.COBALT])
	_check(guild.active.is_empty() and guild.completed_count == 2, "completed: %d" % guild.completed_count)

	# Lost ship: field progress is not paid and starts over
	var survey := guild.make_contract(Contract.Type.SURVEY, 1)
	guild.active.append(survey)
	survey.progress = survey.target
	var no_ore: Dictionary[int, float] = {}
	result = guild.settle_run(no_ore, false, 1)
	_check(result.total == 0 and survey.progress == 0.0 and guild.active.has(survey), "lost ship: survey kept, progress reset")

	# Save round trip
	var copy := Guild.from_dict(JSON.parse_string(JSON.stringify(guild.to_dict())))
	_check(copy.active.size() == 1 and copy.active[0].type == Contract.Type.SURVEY and copy.completed_count == 2, "save round trip")
	print("Guild test finished")


func _check(ok: bool, what: String) -> void:
	print(("PASS  " if ok else "FAIL  ") + what)

	if not ok:
		push_error("Guild test failed: " + what)
