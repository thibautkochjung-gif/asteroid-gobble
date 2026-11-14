class_name Contract
extends RefCounted

# One mining guild contract: what to do, what it pays, and how far the player has got.
# Pure data (saved in GameState through Guild). Guild makes and settles them; ContractTracker
# updates the field contracts during a run.
#
# - Delivery: bring `target` units of `ore_id`. Handed in when docking, or from station storage.
#   Partial deliveries count and are kept between runs.
# - Rush delivery: the same, all at once, by the end of the next run (`runs_left`).
# - Speed trial: reach `target` m/s during a run.
# - Survey: fully scan `target` rocks of at least `min_cells` cells during a run.
# - Specimen tow: dock with an uncut rock of at least `target` cells near the ship.
# - Claim markers: dock with `target` beacons each left next to a different rock that holds ore.
# Field contracts (all but deliveries) count one run at a time: `progress` starts again at each
# undock, and is paid only if the ship docks.

enum Type { DELIVERY, RUSH_DELIVERY, SPEED_TRIAL, SURVEY, SPECIMEN_TOW, CLAIM_MARKERS }

const TYPE_NAMES: Dictionary[Type, String] = {
	Type.DELIVERY: "Delivery",
	Type.RUSH_DELIVERY: "Rush delivery",
	Type.SPEED_TRIAL: "Speed trial",
	Type.SURVEY: "Survey",
	Type.SPECIMEN_TOW: "Specimen tow",
	Type.CLAIM_MARKERS: "Claim markers",
}

var type: Type = Type.DELIVERY
var ore_id: int = -1 # Deliveries only
var target: float = 0.0 # Units, m/s, rocks, cells or beacons, depending on the type
var min_cells: int = 0 # Survey: the smallest rock that counts
var reward: int = 0
var runs_left: int = -1 # Rush delivery: runs before it expires. -1 = no limit
var progress: float = 0.0


func is_delivery() -> bool:
	return type == Type.DELIVERY or type == Type.RUSH_DELIVERY


func is_done() -> bool:
	return progress >= target - GameState.DUST


func get_title() -> String:
	return TYPE_NAMES[type]


func get_goal_text() -> String:
	match type:
		Type.DELIVERY:
			return "Bring %d u of %s" % [roundi(target), _ore_name()]
		Type.RUSH_DELIVERY:
			return "Bring %d u of %s by the end of your next run, all at once" % [roundi(target), _ore_name()]
		Type.SPEED_TRIAL:
			return "Reach %d m/s during a run" % roundi(target)
		Type.SURVEY:
			return "Fully scan %d rocks of %d+ cells in one run" % [roundi(target), min_cells]
		Type.SPECIMEN_TOW:
			return "Dock with an uncut rock of %d+ cells next to your ship" % roundi(target)
		Type.CLAIM_MARKERS:
			return "Dock after leaving %d beacons, each next to a different rock holding ore" % roundi(target)

	return ""


# What the player needs aboard for it. Empty if nothing special.
func get_needs_text() -> String:
	match type:
		Type.SURVEY:
			return "Needs a scanner"
		Type.SPECIMEN_TOW:
			return "Needs a way to tow: net, tractor beam or rock bolter"
		Type.CLAIM_MARKERS:
			return "Needs a beacon rack"

	return ""


# Short, for the cockpit and the guild board.
func get_progress_text() -> String:
	match type:
		Type.DELIVERY, Type.RUSH_DELIVERY:
			return "%d/%d u %s" % [floori(progress), roundi(target), _ore_name()]
		Type.SPEED_TRIAL:
			return "%d/%d m/s" % [floori(progress), roundi(target)]
		Type.SURVEY:
			return "%d/%d rocks" % [floori(progress), roundi(target)]
		Type.SPECIMEN_TOW:
			return "%d/%d cells nearby" % [floori(progress), roundi(target)]
		Type.CLAIM_MARKERS:
			return "%d/%d beacons placed" % [floori(progress), roundi(target)]

	return ""


func to_dict() -> Dictionary:
	return {
		"type": type,
		"ore_id": ore_id,
		"target": target,
		"min_cells": min_cells,
		"reward": reward,
		"runs_left": runs_left,
		"progress": progress,
	}


static func from_dict(data: Dictionary) -> Contract:
	var contract := Contract.new()
	contract.type = int(data.get("type", 0)) as Type
	contract.ore_id = int(data.get("ore_id", -1))
	contract.target = float(data.get("target", 0.0))
	contract.min_cells = int(data.get("min_cells", 0))
	contract.reward = int(data.get("reward", 0))
	contract.runs_left = int(data.get("runs_left", -1))
	contract.progress = float(data.get("progress", 0.0))
	return contract


func _ore_name() -> String:
	return CellMaterials.get_material(ore_id).display_name.to_lower() if ore_id >= 0 else "?"
